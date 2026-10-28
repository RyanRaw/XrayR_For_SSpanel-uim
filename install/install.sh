#!/usr/bin/env bash
set -euo pipefail

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

# ==================== 配置 ====================
OWNER="RyanRaw"
REPO="XrayR_For_SSpanel-uim"
SCRIPT_REPO="XrayR_For_SSpanel-uim"  # 脚本和 release 在同一个仓库

INSTALL_DIR="/usr/local/XrayR"
CONFIG_DIR="/etc/XrayR"
SERVICE_FILE="/etc/systemd/system/XrayR.service"
MANAGER_BIN="/usr/bin/XrayR"
MANAGER_BIN_LOWER="/usr/bin/xrayr"
SYSCTL_CONF="/etc/sysctl.conf"
cur_dir=$(pwd)

# 系统类型/版本：check_os 会填值；先给默认值，避免 set -u 下未赋值报 "unbound variable"
release=""
os_version=""
os_major=""

# ==================== 日志函数 ====================
log_info()    { echo -e "${green}$*${plain}" >&2; }
log_warn()    { echo -e "${yellow}$*${plain}" >&2; }
log_error()   { echo -e "${red}$*${plain}" >&2; }

# ==================== 下载 ====================
# 下载文件，优先 curl，其次 wget
download_file() {
    local url="$1" dest="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fsL --connect-timeout 15 --retry 3 --retry-delay 2 -o "$dest" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$dest" "$url"
    else
        log_error "未找到 curl 或 wget，无法下载"
        return 1
    fi
}

# ==================== 前置检查 ====================
need_root() {
    if [[ ${EUID} -ne 0 ]]; then
        log_error "错误：必须使用 root 用户运行此脚本。"
        exit 1
    fi
}

check_os() {
    # 优先使用 /etc/os-release 的 ID 字段（Alpine 等均可识别）
    if [[ -f /etc/os-release ]]; then
        local os_id
        os_id=$(. /etc/os-release 2>/dev/null; echo "${ID:-}")
        case "$os_id" in
            alpine)
                release="alpine"
                ;;
            debian)
                release="debian"
                ;;
            ubuntu)
                release="ubuntu"
                ;;
            centos|rhel|fedora|rocky|almalinux)
                release="centos"
                ;;
        esac
    fi

    # 兜底：通过 /etc/issue、/proc/version 识别（兼容旧系统 / 容器）
    if [[ -z "${release:-}" ]]; then
        if [[ -f /etc/redhat-release ]]; then
            release="centos"
        elif grep -Eqi "debian" /etc/issue 2>/dev/null; then
            release="debian"
        elif grep -Eqi "ubuntu" /etc/issue 2>/dev/null; then
            release="ubuntu"
        elif grep -Eqi "centos|red hat|redhat" /etc/issue 2>/dev/null; then
            release="centos"
        elif grep -Eqi "alpine" /etc/issue 2>/dev/null; then
            release="alpine"
        elif grep -Eqi "debian" /proc/version 2>/dev/null; then
            release="debian"
        elif grep -Eqi "ubuntu" /proc/version 2>/dev/null; then
            release="ubuntu"
        elif grep -Eqi "centos|red hat|redhat" /proc/version 2>/dev/null; then
            release="centos"
        elif grep -Eqi "alpine" /proc/version 2>/dev/null; then
            release="alpine"
        else
            log_error "未检测到系统版本，请联系脚本作者！"
            exit 1
        fi
    fi

    # 检测系统版本号（取主版本号，比较时必须是纯数字，否则 [[ -lt ]] 会算术报错）
    os_version=""
    if [[ -f /etc/os-release ]]; then
        os_version=$(. /etc/os-release 2>/dev/null; printf '%s' "${VERSION_ID:-}")
    fi
    if [[ -z "$os_version" && -f /etc/lsb-release ]]; then
        os_version=$(. /etc/lsb-release 2>/dev/null; printf '%s' "${DISTRIB_RELEASE:-}")
    fi
    os_major="${os_version%%.*}"
    [[ "$os_major" =~ ^[0-9]+$ ]] || os_major=""

    if [[ -n "$os_major" ]]; then
        if [[ x"${release}" == x"centos" ]]; then
            if (( os_major <= 6 )); then
                log_error "请使用 CentOS 7 或更高版本的系统！"
                exit 1
            fi
        elif [[ x"${release}" == x"ubuntu" ]]; then
            if (( os_major < 16 )); then
                log_error "请使用 Ubuntu 16 或更高版本的系统！"
                exit 1
            fi
        elif [[ x"${release}" == x"debian" ]]; then
            if (( os_major < 8 )); then
                log_error "请使用 Debian 8 或更高版本的系统！"
                exit 1
            fi
        fi
    fi

    if [[ x"${release:-}" == x"alpine" ]]; then
        # Alpine 无最低版本限制，仅提示
        log_info "检测到 Alpine 系统，将使用 OpenRC 管理服务。"
    fi
}

normalize_version() {
    local version="${1:-}"
    if [[ -z "$version" ]]; then
        # 从 GitHub API 获取最新版本
        version=$(curl -fLs "https://api.github.com/repos/${OWNER}/${REPO}/releases/latest" | \
            grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ -z "$version" ]]; then
            log_error "检测最新版本失败，可能是超出 GitHub API 限制，请稍后再试或手动指定版本。"
            exit 1
        fi
        log_info "检测到最新版本：${version}"
    fi
    if [[ "$version" != v* ]]; then
        version="v${version}"
    fi
    echo "$version"
}

detect_arch() {
    local machine
    machine="$(uname -m | tr '[:upper:]' '[:lower:]')"
    case "$machine" in
        x86_64|amd64)       echo "XrayR_linux_amd64" ;;
        aarch64|arm64)      echo "XrayR_linux_arm64" ;;
        *)                  log_warn "检测架构失败(${machine})，使用默认: XrayR_linux_amd64"
                            echo "XrayR_linux_amd64" ;;
    esac
}

# ==================== 基础安装 ====================
install_base() {
    if [[ x"${release}" == x"centos" ]]; then
        yum install epel-release -y || log_warn "安装 epel-release 失败，继续尝试"
        yum install wget curl unzip tar crontabs socat -y || log_warn "依赖安装失败，继续尝试"
    elif [[ x"${release}" == x"alpine" ]]; then
        # Alpine 使用 apk，OpenRC 自带 crond（busybox），无需额外 cron 包
        apk update || log_warn "apk update 失败，继续尝试"
        apk add wget curl unzip tar socat bash || log_warn "依赖安装失败，继续尝试"
    else
        # 用 apt-get 而不是 apt，避免 "apt does not have a stable CLI interface" 警告
        apt-get update -y || log_warn "软件源更新失败，继续尝试"
        apt-get install -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold \
            wget curl unzip tar cron socat || log_warn "依赖安装失败，继续尝试"
    fi
}

# ==================== systemd 服务文件 ====================
write_service() {
    cat > "$SERVICE_FILE" <<'EOF'
[Unit]
Description=XrayR Service
After=network.target nss-lookup.target
Wants=network.target

[Service]
User=root
Group=root
Type=simple
LimitAS=infinity
LimitRSS=infinity
LimitCORE=infinity
LimitNOFILE=1048576
LimitNPROC=1048576
WorkingDirectory=/usr/local/XrayR/
ExecStart=/usr/local/XrayR/XrayR --config /etc/XrayR/config.yml
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
}

# ==================== OpenRC 服务脚本（Alpine） ====================
OPENRC_FILE="/etc/init.d/XrayR"

write_openrc() {
    mkdir -p /var/log
    touch /var/log/XrayR.log
    chmod 644 /var/log/XrayR.log
    cat > "$OPENRC_FILE" <<'EOF'
#!/sbin/openrc-run

name="XrayR"
description="XrayR Service"
command="/usr/local/XrayR/XrayR"
command_args="--config /etc/XrayR/config.yml"
command_background="yes"
pidfile="/run/XrayR.pid"
directory="/usr/local/XrayR"
# 将标准输出/错误重定向到日志文件，便于 XrayR log 查看
output_log="/var/log/XrayR.log"
error_log="/var/log/XrayR.log"

depend() {
    need net
    after firewall
}

start_pre() {
    # 启动前验证二进制存在，避免静默失败
    if [[ ! -x /usr/local/XrayR/XrayR ]]; then
        einfo "XrayR 二进制不存在或不可执行，请先运行 install.sh install"
        return 1
    fi
}
EOF
    chmod +x "$OPENRC_FILE"
    # 写入 rc 默认配置，确保开机自启参数（部分 Alpine 用 /etc/conf.d/XrayR）
    cat > /etc/conf.d/XrayR <<'EOF'
# XrayR OpenRC 配置
cfgfile="/etc/XrayR/config.yml"
EOF
}

# ==================== 网络优化 ====================
backup_sysctl_conf() {
    local backup
    if [[ ! -f "$SYSCTL_CONF" ]]; then
        touch "$SYSCTL_CONF"
    fi
    backup="${SYSCTL_CONF}.bak.XrayR.$(date +%Y%m%d%H%M%S)"
    cp -a "$SYSCTL_CONF" "$backup"
    log_info "已备份 ${SYSCTL_CONF} 到 ${backup}"
    # 只保留最近 5 份备份，避免反复安装/优化把磁盘塞满
    ls -1t "${SYSCTL_CONF}".bak.XrayR.* 2>/dev/null | tail -n +6 | while IFS= read -r f; do
        rm -f "$f"
    done
}

# 返回可用/正在使用的拥塞控制算法：bbrplus / bbr / 空
detect_congestion_control() {
    local current available
    current="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true)"
    if [[ "$current" == "bbrplus" ]]; then
        echo "bbrplus"
        return 0
    fi
    available="$(cat /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null || true)"
    # 很多系统只是没加载 tcp_bbr 模块，先尝试加载再判断，否则会误报"内核不支持 BBR"
    if ! echo "$available" | tr ' ' '\n' | grep -qx "bbr"; then
        modprobe tcp_bbr >/dev/null 2>&1 || true
        available="$(cat /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null || true)"
    fi
    # 按空格拆词精确匹配：用 " bbr " 匹配会漏掉排在最后一项的情况
    if echo "$available" | tr ' ' '\n' | grep -qx "bbr"; then
        echo "bbr"
        return 0
    fi
    echo ""
}

# 把 bbr 模块写进开机加载列表，避免重启后又退回 cubic
persist_bbr_module() {
    local conf="/etc/modules-load.d/xrayr-bbr.conf"
    [[ -d /etc/modules-load.d ]] || return 0
    if ! grep -qx "tcp_bbr" "$conf" 2>/dev/null; then
        echo "tcp_bbr" > "$conf"
        log_info "已设置开机自动加载 tcp_bbr（${conf}）"
    fi
}

clean_sysctl_duplicates() {
    local tmp
    tmp="$(mktemp)"
    awk '
    BEGIN { skip = 0 }
    /^# XrayR network optimization begin$/ { skip = 1; next }
    /^# XrayR network optimization end$/   { skip = 0; next }
    skip == 1 { next }
    {
        line = $0
        sub(/^[ \t]*/, "", line)
        if (line ~ /^(net\.core\.default_qdisc|net\.ipv4\.tcp_congestion_control|net\.ipv4\.tcp_fastopen|net\.ipv4\.tcp_tw_reuse|net\.ipv4\.ip_local_port_range|net\.core\.somaxconn|net\.ipv4\.tcp_max_syn_backlog|net\.core\.netdev_max_backlog)[ \t]*=/) {
            next
        }
        print
    }
    ' "$SYSCTL_CONF" > "$tmp"
    # 折叠连续空行：反复安装时每次都会多留一个空行，久了文件里全是空行
    awk '
    /^[ \t]*$/ { blank++; if (blank <= 1) print; next }
    { blank = 0; print }
    ' "$tmp" > "${tmp}.2"
    cat "${tmp}.2" > "$SYSCTL_CONF"
    rm -f "$tmp" "${tmp}.2"
}

append_sysctl_optimization() {
    local cc="$1"
    {
        echo ""
        echo "# XrayR network optimization begin"
        echo "net.core.default_qdisc=fq"
        if [[ -n "$cc" ]]; then
            echo "net.ipv4.tcp_congestion_control=${cc}"
        fi
        echo "net.ipv4.tcp_fastopen=3"
        echo "net.ipv4.tcp_tw_reuse=1"
        echo "net.ipv4.ip_local_port_range=1024 65535"
        echo "net.core.somaxconn=65535"
        echo "net.ipv4.tcp_max_syn_backlog=65535"
        echo "net.core.netdev_max_backlog=250000"
        echo "# XrayR network optimization end"
    } >> "$SYSCTL_CONF"
}

apply_sysctl_optimization() {
    local line key value
    while IFS= read -r line; do
        [[ -z "$line" || "$line" == \#* || "$line" != *=* ]] && continue
        key="${line%%=*}"
        value="${line#*=}"
        sysctl -w "${key}=${value}" >/dev/null 2>&1 || log_warn "无法应用 ${key}=${value}，已跳过。"
    done < <(sed -n '/^# XrayR network optimization begin$/,/^# XrayR network optimization end$/p' "$SYSCTL_CONF")
}

optimize_network() {
    local cc
    log_info "开始应用网络优化：原生 BBR/fq、高并发队列、系统参数。"
    backup_sysctl_conf
    clean_sysctl_duplicates
    cc="$(detect_congestion_control)"
    if [[ -z "$cc" ]]; then
        log_warn "当前内核未检测到 bbr（模块可能不可用），跳过 tcp_congestion_control 设置。"
    elif [[ "$cc" == "bbrplus" ]]; then
        log_info "检测到已使用 bbrplus，保留现有拥塞控制。"
    else
        log_info "检测到内核支持 bbr，启用原生 BBR。"
        persist_bbr_module
    fi
    append_sysctl_optimization "$cc"
    apply_sysctl_optimization
    log_info "网络优化已应用。"
}

# ==================== 安装管理脚本 ====================
install_manager() {
    local cdn_url="https://cdn.jsdelivr.net/gh/${OWNER}/${SCRIPT_REPO}@master/install/XrayR.sh"
    local raw_url="https://raw.githubusercontent.com/${OWNER}/${SCRIPT_REPO}/master/install/XrayR.sh"
    local tmp url ok=0
    tmp="$(mktemp 2>/dev/null || echo "${MANAGER_BIN}.tmp")"

    # 先清 jsDelivr 缓存，否则 @master 可能仍返回旧脚本
    curl -fsL --max-time 20 \
        "https://purge.jsdelivr.net/gh/${OWNER}/${SCRIPT_REPO}@master/install/XrayR.sh" >/dev/null 2>&1 || true

    # CDN 优先，失败或内容异常时回退源站
    for url in "$cdn_url" "$raw_url"; do
        if download_file "$url" "$tmp" && [[ -s "$tmp" ]] && bash -n "$tmp" 2>/dev/null; then
            ok=1
            break
        fi
    done

    if [[ "$ok" != "1" ]]; then
        rm -f "$tmp"
        log_error "管理脚本下载失败！"
        exit 1
    fi

    mv -f "$tmp" "$MANAGER_BIN"
    # mktemp 建的文件是 600，mv 后 chmod +x 只会得到 711，普通用户连脚本都读不了，
    # 而「未识别参数透传给二进制」是刻意支持非 root 使用的，所以这里必须给 755
    chmod 755 "$MANAGER_BIN"
    ln -sf "$MANAGER_BIN" "$MANAGER_BIN_LOWER"
    log_info "管理脚本已安装到 ${MANAGER_BIN}"
}

# ==================== 配置文件复制 ====================
copy_config_files() {
    if [[ -f "$INSTALL_DIR/geoip.dat" ]]; then
        cp -f "$INSTALL_DIR/geoip.dat" "$CONFIG_DIR/geoip.dat"
    fi
    if [[ -f "$INSTALL_DIR/geosite.dat" ]]; then
        cp -f "$INSTALL_DIR/geosite.dat" "$CONFIG_DIR/geosite.dat"
    fi
    for file in config.yml dns.json route.json custom_outbound.json custom_inbound.json rulelist; do
        if [[ ! -f "$CONFIG_DIR/$file" && -f "$INSTALL_DIR/$file" ]]; then
            cp "$INSTALL_DIR/$file" "$CONFIG_DIR/$file"
        fi
    done
}

# ==================== 生成默认配置模板 ====================
# 0=使用已有配置, 1=本次新生成了默认模板（此时不自动启动服务）
config_is_new=0

write_default_config() {
    if [[ -f "$CONFIG_DIR/config.yml" ]]; then
        return 0
    fi
    cat > "$CONFIG_DIR/config.yml" <<'EOF'
Log:
  Level: warning  # 日志级别：none / error / warning / info / debug，debug 会刷很多日志
  AccessPath: # 访问日志文件路径，例如 /etc/XrayR/access.log；留空=不单独记录
  ErrorPath: # 错误日志文件路径，例如 /etc/XrayR/error.log；留空=不单独记录
DnsConfigPath: # 自定义 DNS 配置文件（dns.json）路径，例如 /etc/XrayR/dns.json；留空=用内置默认
RouteConfigPath: # 自定义路由配置文件（route.json）路径，例如 /etc/XrayR/route.json；留空=用内置默认
InboundConfigPath: # 自定义入站配置文件（custom_inbound.json）路径；留空=用内置默认
OutboundConfigPath: # 自定义出站配置文件（custom_outbound.json）路径；留空=用内置默认
ConnectionConfig:
  Handshake: 4 # 握手超时时间（秒）
  ConnIdle: 30 # 连接空闲多久后自动断开（秒）
  UplinkOnly: 2 # 下行已关闭时，上行再多保留多久（秒）
  DownlinkOnly: 4 # 上行已关闭时，下行再多保留多久（秒）
  BufferSize: 64 # 每条连接的缓冲区大小（KB）
Nodes:
  - PanelType: "SSpanel" # 对接的面板类型，本分支只支持 SSpanel
    ApiConfig:
      ApiHost: "https://xxx.icu" # 面板站点地址（你自己的域名，要带 https://）
      ApiKey: "abcdefg" # 面板「系统设置 → 安全设置」里的 muKey（通信密钥）
      NodeID: 1 # 本节点在面板里的节点 ID
      NodeType: V2ray # 节点类型：V2ray / Shadowsocks / Trojan / Shadowsocks-Plugin
      Timeout: 10 # 请求面板接口的超时时间（秒）
      EnableVless: false # V2ray 类型是否走 VLESS，false=走 VMess
      VlessFlow: "xtls-rprx-vision" # VLESS 的流控，只对 VLESS 有效；REALITY 一般用 xtls-rprx-vision
      SpeedLimit: 0 # 本节点限速（Mbps），0=不限速；填了会覆盖面板里的设置
      DeviceLimit: 0 # 本节点设备数上限，0=不限制；填了会覆盖面板里的设置
      RuleListPath: # 本地审计规则文件或目录路径，例如 /etc/XrayR/rulelist；留空=不用本地规则
      DisableCustomConfig: false # true=忽略面板下发的节点自定义配置（custom_config）
    ControllerConfig:
      ListenIP: 0.0.0.0 # 入站监听地址，0.0.0.0=监听本机所有网卡
      SendIP: 0.0.0.0 # 出站使用的本机 IP，0.0.0.0=自动选择
      UpdatePeriodic: 60 # 每隔多少秒向面板同步一次节点信息和用户列表
      EnableDNS: false # true=使用上面 DnsConfigPath 指定的自定义 DNS（要先配好该文件）
      DNSType: AsIs # 域名解析策略：AsIs=原样送出 / UseIP / UseIPv4 / UseIPv6
      EnableProxyProtocol: false # 只对 WebSocket 和 TCP 生效，开启后由前置代理回传真实客户端 IP
      DisableSniffing: false # true=关闭域名嗅探（同时会让「数据包内容」审计拿不到首包）
      DisablePayloadRule: false # true=关闭「数据包内容」审计，只按目标地址匹配（省 CPU）
      # REALITY 的全部参数都由面板下发（私钥、serverNames、shortIds），本地不需要再写 REALITYConfigs 兜底：
      # 面板没给 dest 时后端会自动用面板的 sni 拼成 "sni:443"，serverNames 用 [sni]，shortIds 全空时用内置默认值。
      # 要调 REALITY 参数请到面板改。若把它设成 false，则会忽略面板下发的 REALITY 参数、只用本地配置
      # —— 多节点场景（每台节点私钥不同）千万不要用 false，否则所有节点共用同一把私钥，客户端会握手失败。
      DisableLocalREALITYConfig: true
      # 以下是可选配置，省略即等于关闭，需要时再自行添加：
      #   AutoSpeedLimitConfig     用户超速后自动限速（Limit / WarnTimes / LimitSpeed / LimitDuration）
      #   GlobalDeviceLimitConfig  跨节点统计设备数并限制（Enable / RedisAddr / RedisPassword / RedisDB / Timeout / Expiry）
      #   EnableFallback + FallBackConfigs   VLESS / Trojan 的 TLS 回落（REALITY 节点用不到）
      # 下面这一项不能删：不是 REALITY 且面板开了 TLS 的节点会读它，缺了会直接崩；CertMode 填 none 即可跳过证书逻辑。
      CertConfig:
        CertMode: none # 证书获取方式：none=不用证书；只有需要 TLS 证书（非 REALITY）的节点才改成 file / http / dns
EOF
    config_is_new=1
    log_info "未检测到配置文件，已生成默认模板：${CONFIG_DIR}/config.yml"
}

# ==================== 状态查询 ====================
# 返回值: 0=运行中, 1=未运行, 2=未安装
check_status() {
    if [[ x"${release}" == x"alpine" ]]; then
        if [[ ! -f "$OPENRC_FILE" ]]; then
            return 2
        fi
        if rc-service XrayR status >/dev/null 2>&1; then
            return 0
        else
            return 1
        fi
    fi
    if [[ ! -f "$SERVICE_FILE" ]]; then
        return 2
    fi
    local temp
    temp=$(systemctl status XrayR | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
    if [[ x"${temp}" == x"running" ]]; then
        return 0
    else
        return 1
    fi
}

# ==================== 服务控制辅助（兼容 systemd / OpenRC） ====================
svc_stop() {
    if [[ x"${release}" == x"alpine" ]]; then
        rc-service XrayR stop >/dev/null 2>&1 || true
    elif command -v systemctl >/dev/null 2>&1; then
        systemctl stop XrayR >/dev/null 2>&1 || true
    fi
}

svc_enable() {
    if [[ x"${release}" == x"alpine" ]]; then
        rc-update add XrayR default >/dev/null 2>&1 || true
    elif command -v systemctl >/dev/null 2>&1; then
        systemctl daemon-reload
        systemctl enable XrayR >/dev/null 2>&1 || true
    fi
}

svc_restart() {
    if [[ x"${release}" == x"alpine" ]]; then
        rc-service XrayR restart >/dev/null 2>&1 || true
    elif command -v systemctl >/dev/null 2>&1; then
        systemctl daemon-reload
        systemctl restart XrayR >/dev/null 2>&1 || true
    fi
}

svc_disable() {
    if [[ x"${release}" == x"alpine" ]]; then
        rc-update del XrayR default >/dev/null 2>&1 || true
    elif command -v systemctl >/dev/null 2>&1; then
        systemctl disable XrayR >/dev/null 2>&1 || true
    fi
}

# ==================== 安装主流程 ====================
install_xrayr() {
    local version url tmp
    version="$(normalize_version "${1:-}")"
    url="https://github.com/${OWNER}/${REPO}/releases/download/${version}/$(detect_arch)"

    log_info "开始安装 XrayR ${version}"
    echo "架构: $(detect_arch)"
    echo "下载地址: ${url}"

    install_base

    # 先下载到临时文件并校验，确认可用后再停服务、替换二进制。
    # 否则版本号写错 / 网络中断会把已有安装清空，节点直接停摆。
    tmp="${INSTALL_DIR}.new.$$"
    # 注意用 ${tmp:-}：tmp 是 local，函数返回后 EXIT trap 里变量已失效，set -u 会报 unbound
    trap 'rm -f "${tmp:-}"' EXIT
    if ! download_file "$url" "$tmp"; then
        log_error "下载 XrayR 失败，请检查网络或版本是否存在（现有安装未改动）。"
        exit 1
    fi
    if [[ ! -s "$tmp" ]]; then
        log_error "下载的文件为空，${version} 可能不存在（现有安装未改动）。"
        exit 1
    fi
    if ! chmod +x "$tmp" || ! "$tmp" version >/dev/null 2>&1; then
        log_error "下载的文件无法运行，可能不是本机架构的二进制（现有安装未改动）。"
        exit 1
    fi

    # 停止已有服务
    svc_stop

    # 清理并创建安装目录
    rm -rf "$INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"
    mv -f "$tmp" "${INSTALL_DIR}/XrayR"
    chmod +x "${INSTALL_DIR}/XrayR"
    cd "$INSTALL_DIR"

    # 配置目录
    mkdir -p "$CONFIG_DIR"

    # 服务文件（按系统分支：systemd / OpenRC）
    if [[ x"${release}" == x"alpine" ]]; then
        rm -f "$SERVICE_FILE"   # 清理可能残留的 systemd 文件
        write_openrc
    else
        write_service
    fi

    # 网络优化
    optimize_network

    # 管理脚本
    install_manager

    # 配置文件
    copy_config_files
    write_default_config

    # 启动服务
    svc_enable
    if [[ "$config_is_new" != "1" ]]; then
        svc_restart
        sleep 2
        check_status
        if [[ $? == 0 ]]; then
            log_info "XrayR 启动成功"
        else
            log_warn "XrayR 可能启动失败，请查看日志：XrayR log"
            log_warn "配置教程：https://ryanraw.github.io/XrayR_For_SSpanel-uim/"
        fi
    else
        log_info "全新安装，请先配置 ${CONFIG_DIR}/config.yml"
        log_info "配置教程：https://ryanraw.github.io/XrayR_For_SSpanel-uim/"
    fi

    cd "$cur_dir"
    log_info "XrayR ${version} 安装完成，已设置开机自启。"
    echo ""
    echo "使用方法：XrayR              - 显示管理菜单"
    echo "          XrayR start|stop|restart|status|log|update|uninstall|version"
    echo "          或使用小写: xrayr"
    echo "详细文档: https://ryanraw.github.io/XrayR_For_SSpanel-uim/"
}

# ==================== 卸载 ====================
uninstall_xrayr() {
    need_root
    log_info "开始卸载 XrayR..."
    svc_disable
    svc_stop
    rm -f "$SERVICE_FILE" "$OPENRC_FILE" /etc/conf.d/XrayR
    if command -v systemctl >/dev/null 2>&1; then
        systemctl daemon-reload || true
        systemctl reset-failed >/dev/null 2>&1 || true
    fi
    rm -rf "$INSTALL_DIR" "$CONFIG_DIR"
    rm -f "$MANAGER_BIN" "$MANAGER_BIN_LOWER"
    log_info "XrayR 已卸载。"
}

# ==================== 用法 ====================
usage() {
    cat <<EOF
用法: $(basename "$0") [install|update|uninstall|optimize] [版本]

命令:
  install [版本]   安装 XrayR（默认检测最新版本）
  update [版本]    更新 XrayR（默认检测最新版本）
  optimize         仅应用网络优化，不安装 XrayR
  uninstall        卸载 XrayR
  version          查看 XrayR 版本

示例:
  $(basename "$0")                  # 安装最新版
  $(basename "$0") install v0.9.5   # 安装指定版本
  $(basename "$0") update           # 更新到最新版
  $(basename "$0") optimize         # 仅网络优化
EOF
}

# ==================== 入口 ====================
main() {
    local command="${1:-install}"
    case "$command" in
        install)
            need_root
            check_os
            install_xrayr "${2:-}"
            ;;
        update)
            need_root
            check_os
            install_xrayr "${2:-}"
            ;;
        optimize)
            need_root
            optimize_network
            log_info "网络优化完成。"
            ;;
        uninstall)
            need_root
            check_os          # 需要 release 判断 systemd / OpenRC
            uninstall_xrayr
            ;;
        version)
            if [[ -x "$INSTALL_DIR/XrayR" ]]; then
                "$INSTALL_DIR/XrayR" version
            else
                echo "XrayR 未安装。"
            fi
            ;;
        -h|--help|help)
            usage
            ;;
        v*|[0-9]*)
            need_root
            check_os
            install_xrayr "$command"
            ;;
        *)
            log_error "未知命令：${command}"
            usage
            exit 1
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
