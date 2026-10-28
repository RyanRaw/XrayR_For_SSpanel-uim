#!/usr/bin/env bash
# ============================================================
# AList 伪装站 + 反代加固（供 XHTTP + CDN 节点使用）
#
# 做的事：
#   1. 装 nginx / openssl / jq 等依赖
#   2. 装 AList（只读文件站，作为伪装首页），只监听 127.0.0.1
#   3. nginx 按路径分流：<xhttp 路径> -> 后端 XrayR，其余 -> AList
#   4. 加固：管理入口 + /dav 按 IP 白名单（非白名单直接 404）、
#            Cloudflare 真实 IP 还原、隐藏版本号
#   5. 80 / 443(自签或指定证书) / 自定义端口 三个入口同时可用，
#      兼容 CDN 的 Flexible / Full / Full(strict) 回源
#
# 用法：
#   bash alist-mask.sh --domain ro.example.com [选项]
#
# 选项：
#   --domain <域名[,域名]>   必填，nginx server_name
#   --path <路径>            xhttp 路径前缀，默认 /steam
#   --upstream <ip:port>     后端 XrayR 明文入站，默认 127.0.0.1:21074
#   --cert <文件>            证书 fullchain（不传则交互选择：输入已有 / 生成自签）
#   --key <文件>             私钥（必须与 --cert 成对）
#   --self-signed            直接生成自签证书，不交互
#   --admin-ip <ip[,ip]>     管理入口白名单，默认只允许本机（127.0.0.1）
#   --alist-port <端口>      AList 监听端口，默认 5244
#   --extra-port <端口>      额外的 HTTPS 监听端口（如 21073），默认不加
#   --no-alist               只配 nginx 分流，不安装 AList
#   --force                  已装 AList 也重新下载
#   -y, --yes                不再二次确认
#   -h, --help               显示帮助
# ============================================================
set -uo pipefail

green='\033[0;32m'; yellow='\033[0;33m'; red='\033[0;31m'; plain='\033[0m'
log_info()  { echo -e "${green}$*${plain}" >&2; }
log_warn()  { echo -e "${yellow}$*${plain}" >&2; }
log_error() { echo -e "${red}$*${plain}" >&2; }

ALIST_DIR="/opt/alist"
ALIST_DATA="${ALIST_DIR}/data"
ALIST_FILES="${ALIST_DIR}/files"
ALIST_SERVICE="/etc/systemd/system/alist.service"
ALIST_OPENRC="/etc/init.d/alist"
NGINX_ETC="/etc/nginx"
SSL_ROOT="/etc/nginx/ssl"
REALIP_CONF="${NGINX_ETC}/conf.d/zz-cdn-realip.conf"
UPGRADE_CONF="${NGINX_ETC}/conf.d/zz-upgrade-map.conf"
ADMIN_CONF="${NGINX_ETC}/conf.d/zz-alist-admin.conf"
SITE_NAME="alist-mask"
PASS_FILE="/root/alist_admin_password.txt"

DOMAINS=""
XHTTP_PATH="/steam"
UPSTREAM="127.0.0.1:21074"
CERT_SRC=""
KEY_SRC=""
CERT_MODE="auto"   # auto | input | self | reuse
ADMIN_IPS=""
ALIST_PORT="5244"
EXTRA_HTTPS_PORT=""
WITH_ALIST=1
FORCE=0
ASSUME_YES=0

usage() {
    sed -n '2,31p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --domain)      DOMAINS="${2:-}"; shift 2 ;;
        --path)        XHTTP_PATH="${2:-}"; shift 2 ;;
        --upstream)    UPSTREAM="${2:-}"; shift 2 ;;
        --cert)        CERT_SRC="${2:-}"; shift 2 ;;
        --key)         KEY_SRC="${2:-}"; shift 2 ;;
        --self-signed) CERT_MODE="self"; shift ;;
        --admin-ip)    ADMIN_IPS="${2:-}"; shift 2 ;;
        --alist-port)  ALIST_PORT="${2:-}"; shift 2 ;;
        --extra-port)  EXTRA_HTTPS_PORT="${2:-}"; shift 2 ;;
        --no-alist)    WITH_ALIST=0; shift ;;
        --force)       FORCE=1; shift ;;
        -y|--yes)      ASSUME_YES=1; shift ;;
        -h|--help)     usage ;;
        *) log_error "未知参数：$1"; usage ;;
    esac
done

need_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "请以 root 运行。"
        exit 1
    fi
}

# ---------- 系统与包管理 ----------
detect_pm() {
    if command -v apt-get >/dev/null 2>&1; then echo apt
    elif command -v dnf >/dev/null 2>&1; then echo dnf
    elif command -v yum >/dev/null 2>&1; then echo yum
    elif command -v apk >/dev/null 2>&1; then echo apk
    else echo none; fi
}

pkg_install() {
    local pm; pm="$(detect_pm)"
    case "$pm" in
        apt)
            DEBIAN_FRONTEND=noninteractive apt-get update -qq >/dev/null 2>&1 || true
            DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
                -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold "$@" >/dev/null 2>&1
            ;;
        dnf) dnf install -y -q "$@" >/dev/null 2>&1 ;;
        yum) yum install -y -q "$@" >/dev/null 2>&1 ;;
        apk) apk add --no-cache "$@" >/dev/null 2>&1 ;;
        *)   log_error "未识别的包管理器，请手动安装：$*"; return 1 ;;
    esac
}

svc_reload() {
    if command -v systemctl >/dev/null 2>&1; then
        systemctl daemon-reload 2>/dev/null || true
    fi
}

svc_enable_now() {
    local name="$1"
    if command -v systemctl >/dev/null 2>&1; then
        systemctl enable --now "$name" >/dev/null 2>&1 || systemctl restart "$name"
    else
        rc-service "$name" restart >/dev/null 2>&1 || /etc/init.d/"$name" restart >/dev/null 2>&1
    fi
}

arch_name() {
    case "$(uname -m | tr '[:upper:]' '[:lower:]')" in
        x86_64|amd64) echo amd64 ;;
        aarch64|arm64) echo arm64 ;;
        armv7l|armv7) echo armv7 ;;
        *) echo amd64 ;;
    esac
}

# ---------- nginx ----------
install_nginx() {
    if ! command -v nginx >/dev/null 2>&1; then
        log_info "安装 nginx ..."
        pkg_install nginx || { log_error "nginx 安装失败"; exit 1; }
    fi
    local pm; pm="$(detect_pm)"
    if [[ "$pm" == "apt" ]]; then
        pkg_install openssl jq curl || true
    else
        pkg_install openssl jq curl || true
    fi
    command -v nginx >/dev/null 2>&1 || { log_error "nginx 不可用"; exit 1; }
    command -v jq >/dev/null 2>&1 || log_warn "jq 不可用，AList 自动配置将跳过（可手动到 AList 后台配置）"
}

nginx_site_dir() {
    # 返回站点配置应放置的目录
    if [[ -d "${NGINX_ETC}/sites-available" && -d "${NGINX_ETC}/sites-enabled" ]]; then
        echo "${NGINX_ETC}/sites-available"
    elif [[ -d "${NGINX_ETC}/http.d" ]]; then
        echo "${NGINX_ETC}/http.d"
    else
        echo "${NGINX_ETC}/conf.d"
    fi
}

validate_cert_pair() {
    local cert="$1" key="$2" cpub kpub
    [[ -f "$cert" && -r "$cert" ]] || { log_error "证书文件不存在或不可读：${cert}"; return 1; }
    [[ -f "$key"  && -r "$key"  ]] || { log_error "私钥文件不存在或不可读：${key}"; return 1; }
    openssl x509 -in "$cert" -noout >/dev/null 2>&1 \
        || { log_error "证书解析失败（需要 PEM 格式，fullchain 亦可）：${cert}"; return 1; }
    openssl pkey -in "$key" -noout >/dev/null 2>&1 \
        || { log_error "私钥解析失败（需要未加密的 PEM 私钥）：${key}"; return 1; }
    cpub="$(openssl x509 -in "$cert" -noout -pubkey 2>/dev/null \
        | openssl pkey -pubin -outform der 2>/dev/null \
        | openssl dgst -sha256 2>/dev/null | awk '{print $NF}')"
    kpub="$(openssl pkey -in "$key" -pubout -outform der 2>/dev/null \
        | openssl dgst -sha256 2>/dev/null | awk '{print $NF}')"
    if [[ -z "$cpub" || "$cpub" != "$kpub" ]]; then
        log_error "证书与私钥不匹配：${cert} / ${key}"
        return 1
    fi
    return 0
}

generate_self_signed() {
    local primary="${DOMAINS%%,*}" san="DNS:${primary}" d days=3650
    IFS=',' read -ra _ds <<< "$DOMAINS"
    for d in "${_ds[@]}"; do
        d="${d// /}"
        [[ -z "$d" ]] && continue
        [[ ",${san}," == *",DNS:${d},"* ]] && continue
        san+=",DNS:${d}"
    done

    log_warn "生成自签证书：CN=${primary}，SAN=${san}，有效期 ${days} 天"
    log_warn "自签只适合直连测试或 CDN Flexible/Full 回源；Full(strict) 必须用真实证书"
    if ! openssl req -x509 -nodes -newkey rsa:2048 -days "$days" \
            -keyout "${SSL_DIR}/privkey.pem" -out "${SSL_DIR}/fullchain.pem" \
            -subj "/CN=${primary}" \
            -addext "subjectAltName=${san}" >/dev/null 2>&1; then
        # 旧版 openssl 可能不支持 -addext，退化为仅 CN
        if ! openssl req -x509 -nodes -newkey rsa:2048 -days "$days" \
                -keyout "${SSL_DIR}/privkey.pem" -out "${SSL_DIR}/fullchain.pem" \
                -subj "/CN=${primary}" >/dev/null 2>&1; then
            log_error "自签证书生成失败，443 将不可用（可用 --cert/--key 指定真实证书）"
            return 1
        fi
        log_warn "openssl 不支持 -addext，已生成仅含 CN 的自签证书（无 SAN，部分 CDN 会拒绝）"
    fi
    chmod 600 "${SSL_DIR}/privkey.pem" 2>/dev/null || true
    chmod 644 "${SSL_DIR}/fullchain.pem" 2>/dev/null || true
    log_info "已生成自签证书：${SSL_DIR}/fullchain.pem"
}

# 先录入路径（校验放到 openssl 安装完成之后），回车则改为自签
read_cert_paths_raw() {
    local cert key
    read -rp "证书 fullchain 路径（回车改用自签）：" cert || cert=""
    read -rp "私钥路径（回车改用自签）：" key || key=""
    cert="${cert%\"}"; cert="${cert#\"}"
    key="${key%\"}"; key="${key#\"}"
    if [[ -z "$cert" || -z "$key" ]]; then
        log_warn "路径不完整，改为生成自签证书"
        CERT_MODE="self"
        return 0
    fi
    CERT_SRC="$cert"
    KEY_SRC="$key"
}

# 交互选择证书来源（在确认清单之前调用，方便用户看到最终选择）
choose_cert_mode() {
    if [[ -n "$CERT_SRC" || -n "$KEY_SRC" ]]; then
        CERT_MODE="input"
        return 0
    fi
    if [[ "$CERT_MODE" == "self" || "$CERT_MODE" == "reuse" ]]; then
        return 0
    fi
    if [[ "$ASSUME_YES" == "1" || ! -t 0 ]]; then
        CERT_MODE="auto"
        return 0
    fi

    SSL_DIR="${SSL_ROOT}/${DOMAINS%%,*}"
    local has_local=0
    [[ -f "${SSL_DIR}/fullchain.pem" && -f "${SSL_DIR}/privkey.pem" ]] && has_local=1

    echo ""
    echo "证书处理方式："
    echo "  1) 输入已有证书与私钥路径（CDN 用 Full(strict) 回源请选这个）"
    echo "  2) 生成自签证书（仅直连测试 / Flexible、Full 回源）"
    if [[ "$has_local" == "1" ]]; then
        echo "  3) 沿用本机已有证书（${SSL_DIR}）"
    else
        echo "  3) 自动：有可用证书就沿用，没有则生成自签"
    fi
    local ans
    read -rp "请选择 [1/2/3，回车默认 3]：" ans || ans=""
    case "$ans" in
        1) CERT_MODE="input"; read_cert_paths_raw ;;
        2) CERT_MODE="self" ;;
        *) if [[ "$has_local" == "1" ]]; then CERT_MODE="reuse"; else CERT_MODE="auto"; fi ;;
    esac
    return 0
}

cert_mode_desc() {
    case "$CERT_MODE" in
        input) echo "交互输入已有证书（${CERT_SRC:-待输入}）" ;;
        self)  echo "生成自签证书" ;;
        reuse) echo "沿用本机已有证书" ;;
        *)     echo "自动（有可用证书则沿用，否则自签）" ;;
    esac
}

# 交互录入证书路径，最多重试 3 次
prompt_cert_paths() {
    local i cert key
    for i in 1 2 3; do
        read -rp "证书 fullchain 路径（回车改用自签）：" cert || cert=""
        if [[ -z "$cert" ]]; then
            log_warn "未输入证书，改为生成自签证书"
            CERT_MODE="self"
            return 0
        fi
        read -rp "私钥路径（回车改用自签）：" key || key=""
        if [[ -z "$key" ]]; then
            log_warn "未输入私钥，改为生成自签证书"
            CERT_MODE="self"
            return 0
        fi
        cert="${cert%\"}"; cert="${cert#\"}"
        key="${key%\"}"; key="${key#\"}"
        if validate_cert_pair "$cert" "$key"; then
            CERT_SRC="$cert"
            KEY_SRC="$key"
            CERT_MODE="input"
            return 0
        fi
        log_warn "校验未通过，请重新输入（第 ${i}/3 次）"
    done
    log_error "证书多次校验失败，已退出（可改用 --cert/--key 或 --self-signed）"
    exit 1
}

install_certs() {
    local primary="${DOMAINS%%,*}"
    SSL_DIR="${SSL_ROOT}/${primary}"
    mkdir -p "$SSL_DIR"
    chmod 755 "$SSL_DIR"

    case "$CERT_MODE" in
        input)
            if [[ -n "$CERT_SRC" && -n "$KEY_SRC" ]]; then
                if ! validate_cert_pair "$CERT_SRC" "$KEY_SRC"; then
                    if [[ -t 0 ]]; then
                        prompt_cert_paths
                    else
                        exit 1
                    fi
                fi
            elif [[ -n "$CERT_SRC" || -n "$KEY_SRC" ]]; then
                log_error "证书与私钥必须成对指定（--cert 与 --key）"
                [[ -t 0 ]] && prompt_cert_paths || exit 1
            elif [[ -t 0 ]]; then
                prompt_cert_paths
            else
                log_error "非交互模式需用 --cert 与 --key 指定证书，或加 --self-signed"
                exit 1
            fi
            if [[ "$CERT_MODE" == "self" ]]; then
                generate_self_signed || exit 1
            else
                cp -f "$CERT_SRC" "${SSL_DIR}/fullchain.pem" || { log_error "复制证书失败：$CERT_SRC"; exit 1; }
                cp -f "$KEY_SRC"  "${SSL_DIR}/privkey.pem"  || { log_error "复制私钥失败：$KEY_SRC"; exit 1; }
                chmod 600 "${SSL_DIR}/privkey.pem"  2>/dev/null || true
                chmod 644 "${SSL_DIR}/fullchain.pem" 2>/dev/null || true
                log_info "已安装证书：${SSL_DIR}/fullchain.pem"
            fi
            ;;
        self)
            generate_self_signed || exit 1
            ;;
        reuse)
            validate_cert_pair "${SSL_DIR}/fullchain.pem" "${SSL_DIR}/privkey.pem" || {
                log_error "没有可沿用的有效证书：${SSL_DIR}（可用 --cert/--key 指定，或改用 --self-signed）"
                exit 1
            }
            log_info "沿用已有证书：${SSL_DIR}"
            ;;
        *)
            if [[ -f "${SSL_DIR}/fullchain.pem" && -f "${SSL_DIR}/privkey.pem" ]] \
                && validate_cert_pair "${SSL_DIR}/fullchain.pem" "${SSL_DIR}/privkey.pem"; then
                log_info "沿用已有证书：${SSL_DIR}"
            else
                generate_self_signed || exit 1
            fi
            ;;
    esac
}

write_realip_conf() {
    cat > "$REALIP_CONF" <<'EOF'
# 让 nginx 用 CDN 下发的真实客户端 IP 作为 remote_addr（Cloudflare 段）
set_real_ip_from 173.245.48.0/20;
set_real_ip_from 103.21.244.0/22;
set_real_ip_from 103.22.200.0/22;
set_real_ip_from 103.31.4.0/22;
set_real_ip_from 141.101.64.0/18;
set_real_ip_from 108.162.192.0/18;
set_real_ip_from 190.93.240.0/20;
set_real_ip_from 188.114.96.0/20;
set_real_ip_from 197.234.240.0/22;
set_real_ip_from 198.41.128.0/17;
set_real_ip_from 162.158.0.0/15;
set_real_ip_from 104.16.0.0/13;
set_real_ip_from 104.24.0.0/14;
set_real_ip_from 172.64.0.0/13;
set_real_ip_from 131.0.72.0/22;
set_real_ip_from 2400:cb00::/32;
set_real_ip_from 2606:4700::/32;
set_real_ip_from 2803:f800::/32;
set_real_ip_from 2405:b500::/32;
set_real_ip_from 2405:8100::/32;
set_real_ip_from 2a06:98c0::/29;
set_real_ip_from 2c0f:f248::/32;
real_ip_header CF-Connecting-IP;
real_ip_recursive on;
EOF
}

write_admin_conf() {
    local ips=" 127.0.0.1 1;\n    ::1 1;\n"
    local i
    IFS=',' read -ra _ips <<< "${ADMIN_IPS:-}"
    for i in "${_ips[@]}"; do
        i="$(echo "$i" | tr -d ' ')"
        [[ -n "$i" ]] && ips+="    ${i} 1;\n"
    done
    {
        echo "# 管理入口 / WebDAV 白名单：非白名单一律 404（不暴露后台存在）"
        echo "map \$remote_addr \$alist_admin_ok {"
        echo "    default 0;"
        printf "%b" "$ips"
        echo "}"
    } > "$ADMIN_CONF"
}

write_site_conf() {
    local dir primary
    dir="$(nginx_site_dir)"
    primary="${DOMAINS%%,*}"
    local conf="${dir}/${SITE_NAME}.conf"

    # 备份既有配置
    [[ -f "$conf" ]] && cp -f "$conf" "${conf}.bak.$(date +%Y%m%d%H%M%S)"

    local proxy_headers
    proxy_headers='
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;'

    local xhttp_block alist_block guard_block
    xhttp_block=$(cat <<EOF
    location ${XHTTP_PATH} {
        proxy_pass http://${UPSTREAM};${proxy_headers}
        # xhttp 是长连接 + 分片 POST，必须关缓冲、放开超时
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_cache off;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        chunked_transfer_encoding on;
    }
EOF
)

    alist_block=$(cat <<EOF
    location / {
        proxy_pass http://127.0.0.1:${ALIST_PORT};${proxy_headers}
        proxy_read_timeout 300s;
    }
EOF
)

    guard_block=$(cat <<'EOF'
    # 管理入口与 WebDAV：非白名单直接 404
    location ~ ^/(@manage|api/admin|dav) {
        if ($alist_admin_ok = 0) {
            return 404;
        }
        proxy_pass http://127.0.0.1:__ALIST_PORT__;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 300s;
    }
EOF
)
    guard_block="${guard_block//__ALIST_PORT__/${ALIST_PORT}}"

    local extra_listen=""
    [[ -n "$EXTRA_HTTPS_PORT" ]] && extra_listen="    listen ${EXTRA_HTTPS_PORT} ssl;"$'\n'

    cat > "$conf" <<EOF
# 由 install.sh mask 生成：AList 伪装站 + XHTTP 反代
#   ${XHTTP_PATH}  -> ${UPSTREAM}（XrayR 的 xhttp 入站，明文）
#   其余           -> 127.0.0.1:${ALIST_PORT}（AList 只读文件站）

server {
    listen 80;
    server_name ${DOMAINS};

    server_tokens off;
    access_log /var/log/nginx/${SITE_NAME}.access.log;
    error_log  /var/log/nginx/${SITE_NAME}.error.log warn;

${guard_block}
${xhttp_block}
${alist_block}
}

server {
    listen 443 ssl;
${extra_listen}    server_name ${DOMAINS};

    ssl_certificate     ${SSL_DIR}/fullchain.pem;
    ssl_certificate_key ${SSL_DIR}/privkey.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;
    ssl_session_cache   shared:SSL:10m;
    ssl_session_timeout 1h;

    server_tokens off;
    access_log /var/log/nginx/${SITE_NAME}.access.log;
    error_log  /var/log/nginx/${SITE_NAME}.error.log warn;

${guard_block}
${xhttp_block}
${alist_block}
}
EOF

    # sites-available 目录需要软链到 sites-enabled
    if [[ "$dir" == "${NGINX_ETC}/sites-available" ]]; then
        ln -sfn "$conf" "${NGINX_ETC}/sites-enabled/${SITE_NAME}.conf"
        # 移除默认站点，避免 IP 直连看到 nginx 欢迎页
        rm -f "${NGINX_ETC}/sites-enabled/default"
    fi
    rm -f "${NGINX_ETC}/http.d/default.conf" 2>/dev/null || true
}

write_upgrade_map() {
    cat > "$UPGRADE_CONF" <<'EOF'
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}
EOF
}

reload_nginx() {
    if ! nginx -t >/dev/null 2>&1; then
        log_error "nginx 配置校验失败，已保留现场，请手动排查："
        nginx -t
        exit 1
    fi
    if command -v systemctl >/dev/null 2>&1; then
        systemctl enable --now nginx >/dev/null 2>&1 || systemctl start nginx
        systemctl reload nginx >/dev/null 2>&1 || systemctl restart nginx
    else
        rc-service nginx restart >/dev/null 2>&1 || /etc/init.d/nginx restart >/dev/null 2>&1
    fi
    log_info "nginx 已加载新配置"
}

# ---------- AList ----------
install_alist() {
    local bin="${ALIST_DIR}/alist"
    if [[ -x "$bin" && "$FORCE" != "1" ]]; then
        log_info "检测到已安装 AList：$("$bin" version 2>/dev/null | head -1)，跳过下载"
    else
        log_info "下载 AList ..."
        mkdir -p "$ALIST_DIR"
        local url="https://github.com/AlistGo/alist/releases/latest/download/alist-linux-$(arch_name).tar.gz"
        local tmp="${ALIST_DIR}/alist.tar.gz"
        if ! curl -fsL --max-time 180 -o "$tmp" "$url"; then
            log_error "AList 下载失败：${url}"
            return 1
        fi
        ( cd "$ALIST_DIR" && tar -xzf alist.tar.gz && chmod +x alist ) || { log_error "AList 解压失败"; return 1; }
        rm -f "$tmp"
    fi

    mkdir -p "$ALIST_DATA" "$ALIST_FILES"/{docs,media}
    [[ -f "${ALIST_FILES}/README.txt" ]] || printf 'Nova Storage\n\nThis is a private file index.\n' > "${ALIST_FILES}/README.txt"
    [[ -f "${ALIST_FILES}/docs/catalog.csv" ]] || printf 'index,name,size\n1,demo,1024\n' > "${ALIST_FILES}/docs/catalog.csv"
    if [[ ! -f "${ALIST_FILES}/media/sample-01.bin" ]]; then
        head -c 204800 /dev/urandom > "${ALIST_FILES}/media/sample-01.bin" 2>/dev/null || \
            dd if=/dev/urandom of="${ALIST_FILES}/media/sample-01.bin" bs=1024 count=200 2>/dev/null
    fi

    if command -v systemctl >/dev/null 2>&1; then
        cat > "$ALIST_SERVICE" <<EOF
[Unit]
Description=alist (file index)
After=network.target

[Service]
Type=simple
WorkingDirectory=${ALIST_DIR}
ExecStart=${ALIST_DIR}/alist server --data ${ALIST_DATA}
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
        svc_reload
        svc_enable_now alist
    else
        cat > "$ALIST_OPENRC" <<EOF
#!/sbin/openrc-run
name="alist"
description="alist (file index)"
command="${ALIST_DIR}/alist"
command_args="server --data ${ALIST_DATA}"
command_background="yes"
pidfile="/run/alist.pid"
directory="${ALIST_DIR}"
EOF
        chmod +x "$ALIST_OPENRC"
        svc_enable_now alist
    fi
    sleep 4
}

bind_alist_loopback() {
    local cfg="${ALIST_DATA}/config.json"
    local i
    for i in $(seq 1 10); do
        [[ -f "$cfg" ]] && break
        sleep 1
    done
    [[ -f "$cfg" ]] || { log_warn "未找到 ${cfg}，请手动把 AList 监听地址改为 127.0.0.1"; return 0; }

    # 只改 address / http_port，避免覆盖其它配置
    sed -i -E 's/("address"[[:space:]]*:[[:space:]]*")[^"]*"/\1127.0.0.1"/' "$cfg"
    sed -i -E 's/("http_port"[[:space:]]*:[[:space:]]*)[-0-9]+/\1'"${ALIST_PORT}"'/' "$cfg"
    if command -v systemctl >/dev/null 2>&1; then
        systemctl restart alist >/dev/null 2>&1
    else
        rc-service alist restart >/dev/null 2>&1
    fi
    sleep 3
    log_info "AList 监听已收敛到 127.0.0.1:${ALIST_PORT}"
}

configure_alist_api() {
    command -v jq >/dev/null 2>&1 || { log_warn "缺少 jq，跳过 AList 自动初始化"; return 0; }

    local bin="${ALIST_DIR}/alist"
    local pass base token guest
    base="http://127.0.0.1:${ALIST_PORT}"

    if [[ -f "$PASS_FILE" ]]; then
        pass="$(cat "$PASS_FILE")"
    else
        pass="$(head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 18)"
        echo "$pass" > "$PASS_FILE"
        chmod 600 "$PASS_FILE"
    fi
    "$bin" admin set "$pass" --data "$ALIST_DATA" >/dev/null 2>&1 || \
        log_warn "设置 AList 管理密码失败，可手动执行：$bin admin random"
    if command -v systemctl >/dev/null 2>&1; then systemctl restart alist >/dev/null 2>&1; else rc-service alist restart >/dev/null 2>&1; fi
    sleep 4

    token=$(curl -s -m 10 -X POST "${base}/api/auth/login" \
        -H 'Content-Type: application/json' \
        -d "$(jq -nc --arg u admin --arg p "$pass" '{username:$u,password:$p}')" \
        | jq -r '.data.token // empty')
    if [[ -z "$token" ]]; then
        log_warn "AList 登录失败，跳过自动建存储（密码：${pass}）"
        return 0
    fi

    # 1) 启用 guest 并置为只读（permission=0）
    guest=$(curl -s -m 10 "${base}/api/admin/user/list?page=1&per_page=50" -H "Authorization: ${token}" \
        | jq -c '[.data.content[]? | select(.username=="guest")][0] | if . == null then empty else .disabled=false | .permission=0 | del(.password) end')
    if [[ -n "$guest" && "$guest" != "null" ]]; then
        curl -s -m 10 -X POST "${base}/api/admin/user/update" -H "Authorization: ${token}" \
            -H 'Content-Type: application/json' -d "$guest" >/dev/null
        log_info "guest 已启用且为只读"
    else
        log_warn "未找到 guest 用户，跳过（可在后台手动启用并设为只读）"
    fi

    # 2) 挂载本地目录为只读存储（已存在同名挂载则跳过）
    local mounts
    mounts=$(curl -s -m 10 "${base}/api/admin/storage/list?page=1&per_page=50" -H "Authorization: ${token}" \
        | jq -r '[.data.content[]?.mount_path] | join(",")')
    if [[ ",${mounts}," == *",/,"* ]]; then
        log_info "已存在挂载 / ，跳过创建存储"
    else
        local body
        body=$(jq -nc --arg root "$ALIST_FILES" '{
            mount_path:"/", order:0, driver:"Local", cache_expiration:30,
            status:"work",
            addition:({root_folder_path:$root, thumbnail:false, thumb_max_size:100, mkdir_perm:"777", show_hidden:false} | tostring),
            remark:"storage", web_proxy:false, webdav_policy:"native_proxy", enable_sign:false,
            order_by:"name", order_direction:"asc", extract_folder:"", down_proxy_url:""
        }')
        curl -s -m 15 -X POST "${base}/api/admin/storage/create" -H "Authorization: ${token}" \
            -H 'Content-Type: application/json' -d "$body" >/dev/null
        log_info "已创建只读存储：${ALIST_FILES} -> /"
    fi

    # 3) 换个不像后台的站点标题
    curl -s -m 15 -X POST "${base}/api/admin/setting/save" -H "Authorization: ${token}" \
        -H 'Content-Type: application/json' \
        -d '[{"key":"site_title","value":"Nova Storage","type":"string"}]' >/dev/null || true

    echo ""
    log_info "AList 管理入口：${DOMAINS%%,*}/@manage"
    log_info "AList 管理密码：${pass}（已保存到 ${PASS_FILE}）"
}

# ---------- 防火墙 ----------
open_firewall() {
    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
        ufw allow 80/tcp  >/dev/null 2>&1 || true
        ufw allow 443/tcp >/dev/null 2>&1 || true
        [[ -n "$EXTRA_HTTPS_PORT" ]] && ufw allow "${EXTRA_HTTPS_PORT}/tcp" >/dev/null 2>&1 || true
        log_info "已放行 ufw：80/443${EXTRA_HTTPS_PORT:+ + ${EXTRA_HTTPS_PORT}}"
    elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
        firewall-cmd --permanent --add-service=http  >/dev/null 2>&1 || true
        firewall-cmd --permanent --add-service=https >/dev/null 2>&1 || true
        [[ -n "$EXTRA_HTTPS_PORT" ]] && firewall-cmd --permanent --add-port="${EXTRA_HTTPS_PORT}/tcp" >/dev/null 2>&1 || true
        firewall-cmd --reload >/dev/null 2>&1 || true
        log_info "已放行 firewalld：http/https"
    fi
}

# ---------- 自检 ----------
verify() {
    echo ""
    echo "-------------------- 自检 --------------------"
    local primary="${DOMAINS%%,*}"
    curl -s -o /dev/null -w "  80  /            -> %{http_code}\n" -m 8 -H "Host: ${primary}" "http://127.0.0.1/"
    curl -sk -o /dev/null -w "  443 /            -> %{http_code}\n" -m 8 -H "Host: ${primary}" "https://127.0.0.1/"
    curl -sk -o /dev/null -w "  443 ${XHTTP_PATH} -> %{http_code} (404/400 属正常：后端在等 xhttp 握手)\n" -m 8 -H "Host: ${primary}" "https://127.0.0.1${XHTTP_PATH}"
    curl -sk -o /dev/null -w "  443 /@manage(本机) -> %{http_code}\n" -m 8 -H "Host: ${primary}" "https://127.0.0.1/@manage"
    echo "  监听："
    (ss -lntp 2>/dev/null || netstat -lntp 2>/dev/null) | grep -E ":(80|443|${ALIST_PORT}|${EXTRA_HTTPS_PORT:-21073}) " | awk '{print "    " $4}'
    echo "----------------------------------------------"
}

# ---------- 主流程 ----------
main() {
    need_root

    if [[ -z "$DOMAINS" ]]; then
        if [[ -t 0 ]]; then
            read -rp "请输入域名（多个用逗号分隔，如 ro.example.com）：" DOMAINS
        fi
        [[ -n "$DOMAINS" ]] || { log_error "必须用 --domain 指定域名"; usage; }
    fi
    if [[ "$UPSTREAM" != *:* ]]; then
        log_error "--upstream 需形如 127.0.0.1:21074"
        exit 1
    fi

    choose_cert_mode

    echo "即将执行："
    echo "  域名        : ${DOMAINS}"
    echo "  xhttp 路径  : ${XHTTP_PATH}  ->  ${UPSTREAM}"
    echo "  伪装站      : $([[ "$WITH_ALIST" == "1" ]] && echo "AList（只读，127.0.0.1:${ALIST_PORT}）" || echo "不安装")"
    echo "  证书        : $(cert_mode_desc)"
    echo "  管理白名单  : ${ADMIN_IPS:-仅本机 127.0.0.1}"
    echo "  额外 HTTPS  : ${EXTRA_HTTPS_PORT:-无}"
    echo ""
    if [[ "$ASSUME_YES" != "1" && -t 0 ]]; then
        read -rp "确认继续？[y/N] " ans
        [[ "$ans" =~ ^[Yy]$ ]] || { echo "已取消"; exit 0; }
    fi

    install_nginx
    write_realip_conf
    write_upgrade_map
    write_admin_conf
    install_certs
    write_site_conf

    if [[ "$WITH_ALIST" == "1" ]]; then
        install_alist || log_warn "AList 安装未完成，nginx 分流仍可单独使用"
        bind_alist_loopback
        configure_alist_api
    fi

    reload_nginx
    open_firewall
    verify

    echo ""
    log_info "完成。下一步："
    cat <<EOF
  1) CDN 侧把回源地址指向本机，端口按 SSL 模式选：
       Flexible        -> 80
       Full / Full(严格) -> 443（Full(严格) 需要用真实证书，覆盖 ${SSL_DIR}/fullchain.pem）
       自定义端口        -> 加 --extra-port 后指向该端口
  2) 面板节点填：host / xhttp_host / sni = ${DOMAINS%%,*}，path = ${XHTTP_PATH}，
     后端监听端口用 --upstream 里那个（建议绑 127.0.0.1，只让 nginx 访问）
  3) 管理入口白名单改这里后 reload：
       ${ADMIN_CONF}
EOF
}

main
