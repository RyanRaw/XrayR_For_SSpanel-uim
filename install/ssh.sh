#!/usr/bin/env bash
#
# XrayR 配套脚本：SSH 安全设置
#   bash <(curl -Ls https://cdn.jsdelivr.net/gh/RyanRaw/XrayR_For_SSpanel-uim@master/install/ssh.sh)
#
# 功能：修改 SSH 端口 / 生成登录密钥 / 关闭密码登录 / 开启 SSH 转发 / 查看生效配置 / 恢复备份
#
# 兼容：Ubuntu、Debian、CentOS、Rocky、AlmaLinux、Fedora、Alpine（OpenRC）
#   * 系统命令只用 bash 内建与 POSIX 工具（awk/grep/find/tr），不依赖 GNU sed 扩展
#   * 服务名自动探测 ssh / sshd，systemd 与 OpenRC 都支持
#   * Debian 系会把设置写进 sshd_config.d 里排序最靠前的片段，否则会被云厂商片段覆盖
#
# 安全设计：
#   * 每次写入前备份配置，sshd -t 校验失败自动回滚
#   * 只在确认 authorized_keys 非空后才允许关闭密码登录
#   * 各功能使用独立的托管块，互不覆盖
#   * 改端口会顺带放行 ufw / firewalld / SELinux

set -u

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

SSHD_CONFIG="${SSHD_CONFIG:-/etc/ssh/sshd_config}"
DROPIN_DIR="${DROPIN_DIR:-/etc/ssh/sshd_config.d}"
DROPIN_FILE="${DROPIN_FILE:-${DROPIN_DIR}/00-xrayr-hardening.conf}"
BACKUP_DIR="${BACKUP_DIR:-/etc/ssh/xrayr-backup}"
BACKUP_LAST="${BACKUP_DIR}/last"

DIRECTIVES_PORT=(Port)
DIRECTIVES_PASSWORD=(PubkeyAuthentication PasswordAuthentication ChallengeResponseAuthentication KbdInteractiveAuthentication PermitRootLogin)
DIRECTIVES_FORWARD=(AllowTcpForwarding AllowStreamLocalForwarding GatewayPorts PermitTunnel)

# 日志一律走 stderr，保证 stdout 只用于输出数据（例如命令替换里取文件路径）
log_info()  { echo -e "${green}$*${plain}" >&2; }
log_warn()  { echo -e "${yellow}$*${plain}" >&2; }
log_error() { echo -e "${red}$*${plain}" >&2; }

# ==================== 基础检查 ====================

need_root() {
    if [[ ${EUID} -ne 0 ]]; then
        log_error "错误：必须使用 root 用户运行。"
        exit 1
    fi
}

check_sshd() {
    if [[ ! -f "$SSHD_CONFIG" ]]; then
        log_error "未找到 ${SSHD_CONFIG}，本机可能没有安装 OpenSSH 服务端。"
        exit 1
    fi
}

sshd_bin() {
    if command -v sshd >/dev/null 2>&1; then
        command -v sshd
    elif [[ -x /usr/sbin/sshd ]]; then
        echo /usr/sbin/sshd
    elif [[ -x /usr/local/sbin/sshd ]]; then
        echo /usr/local/sbin/sshd
    else
        echo ""
    fi
}

# sshd 服务名：Debian/Ubuntu 多为 ssh，RHEL/Alpine 多为 sshd
sshd_service() {
    local s
    if command -v systemctl >/dev/null 2>&1; then
        for s in ssh sshd; do
            if systemctl list-unit-files "${s}.service" 2>/dev/null | grep -q "${s}.service"; then
                echo "$s"
                return 0
            fi
        done
    fi
    for s in sshd ssh; do
        if [[ -f "/etc/init.d/${s}" ]]; then
            echo "$s"
            return 0
        fi
    done
    echo ""
}

sshd_reload() {
    local svc rc=1
    svc="$(sshd_service)"
    if [[ -z "$svc" ]]; then
        log_warn "未找到 sshd 服务，请手动重启 SSH 使配置生效。"
        return 1
    fi
    if command -v systemctl >/dev/null 2>&1; then
        systemctl reload "$svc" >/dev/null 2>&1 || systemctl restart "$svc" >/dev/null 2>&1
        rc=$?
    else
        "/etc/init.d/${svc}" reload >/dev/null 2>&1 || "/etc/init.d/${svc}" restart >/dev/null 2>&1
        rc=$?
    fi
    if [[ $rc -eq 0 ]]; then
        log_info "SSH 服务（${svc}）已重新加载配置。"
        return 0
    fi
    log_warn "SSH 服务重新加载失败，请手动检查：systemctl status ${svc} / rc-service ${svc} status"
    return 1
}

# ==================== 配置文件读写 ====================

# 实际写入目标：Debian/Ubuntu 若 Include 了 sshd_config.d，则写排序最靠前的片段。
# sshd 对同一指令取「第一个出现的值」，排在 50-cloud-init.conf 之前才能生效。
config_target() {
    if grep -qE '^[[:space:]]*Include[[:space:]]+.*sshd_config\.d' "$SSHD_CONFIG" 2>/dev/null; then
        mkdir -p "$DROPIN_DIR"
        echo "$DROPIN_FILE"
    else
        echo "$SSHD_CONFIG"
    fi
}

backup_config() {
    mkdir -p "$BACKUP_DIR"
    local ts stamp
    ts="$(date +%Y%m%d%H%M%S)"
    stamp="${BACKUP_DIR}/sshd_config.${ts}"
    cp -f "$SSHD_CONFIG" "$stamp"
    echo "$stamp" > "$BACKUP_LAST"
    if [[ -f "$DROPIN_FILE" ]]; then
        cp -f "$DROPIN_FILE" "${BACKUP_DIR}/dropin.${ts}"
    fi
    log_info "已备份配置：${stamp}"
}

list_backups() {
    [[ -d "$BACKUP_DIR" ]] || return 0
    find "$BACKUP_DIR" -maxdepth 1 -name 'sshd_config.*' 2>/dev/null | sort -r | head -n 10
}

block_begin() { echo "# ===== XrayR SSH 加固 begin: ${1} ====="; }
block_end()   { echo "# ===== XrayR SSH 加固 end: ${1} ====="; }

# 去掉指定功能的托管块（幂等）
remove_block() {
    local file="$1" topic="$2" tmp b e
    [[ -f "$file" ]] || return 0
    b="$(block_begin "$topic")"
    e="$(block_end "$topic")"
    tmp="$(mktemp)"
    awk -v b="$b" -v e="$e" '
        $0 == b { skip = 1; next }
        $0 == e { skip = 0; next }
        !skip   { print }
    ' "$file" > "$tmp" && cat "$tmp" > "$file"
    rm -f "$tmp"
}

# 注释掉指定指令（保留原行内容，前缀标记便于人工识别）
comment_directives() {
    local file="$1"
    shift
    [[ -f "$file" ]] || return 0
    [[ $# -gt 0 ]] || return 0
    local tmp dirs
    dirs="$(printf '%s\n' "$@")"
    tmp="$(mktemp)"
    awk -v dirs="$dirs" '
        BEGIN {
            n = split(dirs, a, "\n")
            for (i = 1; i <= n; i++) if (a[i] != "") want[tolower(a[i])] = 1
        }
        {
            line = $0
            t = line
            sub(/^[ \t]+/, "", t)
            if (t != "" && substr(t, 1, 1) != "#") {
                split(t, p, /[ \t]+/)
                if (tolower(p[1]) in want) {
                    print "# xrayr-disabled: " line
                    next
                }
            }
            print line
        }
    ' "$file" > "$tmp" && cat "$tmp" > "$file"
    rm -f "$tmp"
}

comment_dropins_except_target() {
    local target="$1"
    shift
    [[ -d "$DROPIN_DIR" ]] || return 0
    local f
    for f in "$DROPIN_DIR"/*.conf; do
        [[ -f "$f" ]] || continue
        [[ "$f" == "$target" ]] && continue
        comment_directives "$f" "$@"
    done
}

# 写入指定功能的托管块
write_block() {
    local file="$1" topic="$2"
    shift 2
    remove_block "$file" "$topic"
    {
        echo ""
        block_begin "$topic"
        printf '%s\n' "$@"
        block_end "$topic"
    } >> "$file"
    log_info "已写入配置：${file}（${topic}）"
}

# 校验；失败则回滚
apply_config() {
    local bin err rc
    bin="$(sshd_bin)"

    if [[ -n "$bin" ]]; then
        # 容器/精简系统里 /run/sshd 可能不存在，会让 sshd -t 误报
        [[ -d /run/sshd ]] || mkdir -p /run/sshd 2>/dev/null || true

        err="$("$bin" -t 2>&1)"
        rc=$?
        if [[ $rc -ne 0 ]]; then
            log_error "sshd 配置校验失败，正在回滚："
            echo "$err" >&2
            rollback
            return 1
        fi
        [[ -n "$err" ]] && log_warn "sshd -t 提示：$err"
        log_info "sshd 配置校验通过（${bin} -t）。"
    else
        log_warn "未找到 sshd 可执行文件，跳过配置校验。"
    fi

    sshd_reload
    return 0
}

rollback() {
    local last bin
    last="$(cat "$BACKUP_LAST" 2>/dev/null || true)"
    if [[ -n "$last" && -f "$last" ]]; then
        cat "$last" > "$SSHD_CONFIG"
        log_warn "已恢复主配置：${last}"
    fi
    rm -f "$DROPIN_FILE"
    bin="$(sshd_bin)"
    [[ -n "$bin" ]] && "$bin" -t >/dev/null 2>&1
    sshd_reload >/dev/null 2>&1
}

# ==================== 读取当前值 ====================

sshd_effective() {
    local bin
    bin="$(sshd_bin)"
    [[ -n "$bin" ]] || return 1
    "$bin" -T 2>/dev/null
}

# sshd -T 输出统一小写，直接用 awk 取第二个字段
effective_of() {
    local key="$1" out
    out="$(sshd_effective)"
    if [[ -n "$out" ]]; then
        echo "$out" | awk -v k="$key" 'tolower($1) == k { print $2; exit }'
        return 0
    fi
    grep -iE "^[[:space:]]*${key}[[:space:]]+" "$SSHD_CONFIG" 2>/dev/null | tail -n 1 | awk '{print $2}'
}

current_ports() {
    local out
    out="$(sshd_effective)"
    if [[ -n "$out" ]]; then
        echo "$out" | awk 'tolower($1) == "port" { printf "%s ", $2 }'
        return 0
    fi
    grep -iE '^[[:space:]]*Port[[:space:]]+' "$SSHD_CONFIG" 2>/dev/null | awk '{printf "%s ", $2}'
}

if_enabled() {
    [[ "$(effective_of "$1")" == "yes" ]] && echo "已开启" || echo "未开启"
}

# ==================== 通用：备份 + 注释旧值 ====================

# 备份 + 注释旧值，并把写入目标输出到 stdout。
# 注意：本函数只允许往 stdout 输出目标路径，日志一律走 stderr，
# 否则调用方用 $(prepare_write ...) 取路径时会被日志内容污染。
prepare_write() {
    local target
    target="$(config_target)"
    backup_config
    comment_directives "$SSHD_CONFIG" "$@"
    comment_dropins_except_target "$target" "$@"
    echo "$target"
}

# ==================== 功能 1：修改端口 ====================

open_firewall_port() {
    local port="$1" handled=0
    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qi '^Status: active'; then
        ufw allow "${port}/tcp" >/dev/null 2>&1 && log_info "ufw 已放行 ${port}/tcp"
        handled=1
    fi
    if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
        firewall-cmd --permanent --add-port="${port}/tcp" >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1 && log_info "firewalld 已放行 ${port}/tcp"
        handled=1
    fi
    if command -v getenforce >/dev/null 2>&1 && [[ "$(getenforce 2>/dev/null)" == "Enforcing" ]] \
        && command -v semanage >/dev/null 2>&1; then
        if semanage port -a -t ssh_port_t -p tcp "$port" >/dev/null 2>&1; then
            log_info "SELinux 已放行 ssh_port_t ${port}"
        elif semanage port -m -t ssh_port_t -p tcp "$port" >/dev/null 2>&1; then
            log_info "SELinux 已修改 ssh_port_t 为 ${port}"
        else
            log_warn "SELinux 端口放行失败，请手动执行：semanage port -a -t ssh_port_t -p tcp ${port}"
        fi
        handled=1
    fi
    if [[ $handled -eq 0 ]]; then
        log_warn "未检测到 ufw/firewalld/SELinux，请自行确认防火墙（含 iptables/nftables）与云安全组已放行 ${port}/tcp。"
    fi
}

change_port() {
    echo ""
    log_info "当前生效的 SSH 端口：$(current_ports)"
    echo ""
    local port
    read -p "请输入新的 SSH 端口 (1-65535，回车取消): " port
    [[ -z "$port" ]] && { log_info "已取消。"; return 0; }

    if ! [[ "$port" =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); then
        log_error "端口必须是 1-65535 之间的数字。"
        return 1
    fi

    local target
    target="$(prepare_write "${DIRECTIVES_PORT[@]}")"
    write_block "$target" port "Port ${port}"

    if ! apply_config; then
        log_error "改端口失败，配置已回滚。"
        return 1
    fi

    open_firewall_port "$port"

    echo ""
    log_warn "════════ 务必先不要关闭当前窗口 ════════"
    echo "  1. 新开一个终端，用新端口连接测试："
    echo -e "       ${green}ssh -p ${port} root@<本机IP>${plain}"
    echo "  2. 确认能登录后再关闭当前连接"
    echo "  3. 如果连不上，在本机控制台执行以下命令回滚："
    echo -e "       ${green}bash <(curl -Ls https://cdn.jsdelivr.net/gh/RyanRaw/XrayR_For_SSpanel-uim@master/install/ssh.sh)${plain} → 选 [7] 恢复备份"
    echo "  4. 云服务器还需在控制台「安全组」放行 TCP ${port}"
    log_warn "═══════════════════════════════════════"
}

# ==================== 功能 2：生成登录密钥 ====================

install_pubkey() {
    local pubkey="$1" auth="/root/.ssh/authorized_keys"
    mkdir -p /root/.ssh
    chmod 700 /root/.ssh
    touch "$auth"
    chmod 600 "$auth"
    if grep -qF "$pubkey" "$auth" 2>/dev/null; then
        log_info "该公钥已存在于 ${auth}，跳过。"
    else
        echo "$pubkey" >> "$auth"
        log_info "公钥已写入 ${auth}"
    fi
    chown -R root:root /root/.ssh 2>/dev/null || true
}

generate_key() {
    echo ""
    echo "  1) ed25519  （推荐，现代客户端都支持）"
    echo "  2) rsa-4096 （兼容老客户端）"
    echo ""
    local choice
    read -p "请选择密钥类型 [1-2，默认 1]: " choice
    choice="${choice:-1}"

    local type size keyfile
    case "$choice" in
        1) type="ed25519"; size="";;
        2) type="rsa"; size="-b 4096";;
        *) log_error "请输入 1 或 2。"; return 1;;
    esac

    if ! command -v ssh-keygen >/dev/null 2>&1; then
        log_error "未找到 ssh-keygen，请先安装 openssh-client。"
        return 1
    fi

    keyfile="/root/.ssh/id_${type}_xrayr"
    if [[ -f "$keyfile" ]]; then
        keyfile="${keyfile}.$(date +%Y%m%d%H%M%S)"
    fi

    # shellcheck disable=SC2086
    if ! ssh-keygen -t "$type" $size -f "$keyfile" -N "" -C "xrayr@$(hostname)" >/dev/null; then
        log_error "生成密钥失败。"
        return 1
    fi
    chmod 600 "$keyfile"
    log_info "已生成密钥对：${keyfile}"

    install_pubkey "$(cat "${keyfile}.pub")"

    echo ""
    log_warn "════ 下面是私钥，请立刻复制保存到本地 ════"
    echo ""
    cat "$keyfile"
    echo ""
    log_warn "══════════════════════════════════════════"
    echo "  客户端保存为文件（如 ~/.ssh/xrayr_key）后："
    echo -e "    ${green}chmod 600 ~/.ssh/xrayr_key${plain}"
    echo -e "    ${green}ssh -i ~/.ssh/xrayr_key root@<本机IP>${plain}"
    echo ""
    echo "  确认能正常登录后，建议删除服务器上的私钥副本："
    echo -e "    ${green}rm -f ${keyfile}${plain}（公钥 ${keyfile}.pub 可保留）"
    echo ""
    read -p "按回车返回..." _
}

use_existing_pubkey() {
    echo ""
    echo "请粘贴你的公钥（通常以 ssh-ed25519 / ssh-rsa 开头，整行粘贴后回车）："
    local pubkey
    read -r pubkey
    if [[ -z "$pubkey" ]]; then
        log_error "内容为空，已取消。"
        return 1
    fi
    if [[ ! "$pubkey" =~ ^(ssh-ed25519|ssh-rsa|ecdsa-sha2-|sk-ssh-ed25519) ]]; then
        log_error "看起来不是有效的公钥（应以 ssh-ed25519 / ssh-rsa / ecdsa-sha2- 开头）。"
        return 1
    fi
    install_pubkey "$pubkey"
}

list_authorized_keys() {
    local auth="/root/.ssh/authorized_keys"
    echo ""
    if [[ ! -s "$auth" ]]; then
        log_warn "root 尚未配置任何公钥（${auth} 为空）。"
        return 0
    fi
    log_info "root 已安装的公钥（类型 + 注释）："
    awk 'NF { print "  [" NR "] " $1 "  " $NF }' "$auth"
}

key_menu() {
    echo ""
    log_info "SSH 登录密钥"
    echo ""
    echo "  1) 在服务器上生成新密钥对（会打印私钥，需自行保存到本地）"
    echo "  2) 使用已有公钥（把本地 ~/.ssh/id_ed25519.pub 的内容粘贴进来）"
    echo "  3) 查看当前已安装的公钥"
    echo "  0) 返回"
    echo ""
    local n
    read -p "请输入选择 [0-3]: " n
    case "$n" in
        1) generate_key ;;
        2) use_existing_pubkey ;;
        3) list_authorized_keys ;;
        0) return 0 ;;
        *) log_error "请输入正确的数字 [0-3]。" ;;
    esac
}

# ==================== 功能 3 / 4：密钥登录 ====================

count_other_keyed_users() {
    local count=0 home f
    for home in /home/*; do
        [[ -d "$home" ]] || continue
        f="${home}/.ssh/authorized_keys"
        [[ -s "$f" ]] && count=$((count + 1))
    done
    echo "$count"
}

# 密钥登录相关操作后的统一提示
show_keysetup_hint() {
    echo ""
    log_warn "════════ 务必先不要关闭当前窗口 ════════"
    echo "  1. 新开一个终端，用密钥登录测试："
    echo -e "       ${green}ssh -i <你的私钥> root@<本机IP>${plain}"
    echo "  2. 确认能登录后再关闭当前连接"
    echo "  3. 若登不上，在本机控制台执行以下命令回滚："
    echo -e "       ${green}bash <(curl -Ls https://cdn.jsdelivr.net/gh/RyanRaw/XrayR_For_SSpanel-uim@master/install/ssh.sh)${plain} → 选 [7] 恢复备份"
    echo ""
    echo "  当前生效值："
    printf "    %-46s %s\n" "公钥登录 (pubkeyauthentication)"   "$(effective_of pubkeyauthentication)"
    printf "    %-46s %s\n" "密码登录 (passwordauthentication)" "$(effective_of passwordauthentication)"
    printf "    %-46s %s\n" "公钥文件 (authorizedkeysfile)"     "$(effective_of authorizedkeysfile)"
    printf "    %-46s %s\n" "root 公钥数量"                      "$( [[ -s /root/.ssh/authorized_keys ]] && grep -c . /root/.ssh/authorized_keys || echo 0 )"
    log_warn "═══════════════════════════════════════"
}

# 打开密钥登录、保留密码登录：用于从密码迁移到密钥的中转步骤
enable_pubkey_only() {
    echo ""
    local auth="/root/.ssh/authorized_keys"
    if [[ ! -s "$auth" ]]; then
        log_warn "root 还没有任何公钥（${auth} 为空），打开后也无法用密钥登录。"
        echo "  建议先执行 [2] 生成或安装密钥。"
        local c
        read -p "仍要继续？输入 yes 继续: " c
        [[ "$c" == "yes" ]] || { log_info "已取消。"; return 0; }
    fi

    log_info "已启用密钥登录，密码登录保持不变。"
    echo "  写入的配置项："
    echo "    PubkeyAuthentication yes"
    echo ""
    log_warn "迁移建议：本次改完先用密钥另开终端验证，确认能登进，再用 [4] 关闭密码登录。"

    local target
    target="$(prepare_write PubkeyAuthentication)"
    write_block "$target" pubkey "PubkeyAuthentication yes"

    if ! apply_config; then
        log_error "写入失败，配置已回滚。"
        return 1
    fi

    show_keysetup_hint
}

disable_password() {
    echo ""
    local auth="/root/.ssh/authorized_keys"
    if [[ ! -s "$auth" ]]; then
        log_error "root 的 authorized_keys 为空，关闭密码登录后将无法登录！"
        echo "  请先执行 [2] 生成或安装密钥，确认能用密钥登录之后再回来执行本项。"
        return 1
    fi

    log_warn "即将关闭密码登录，改为仅允许密钥登录。"
    echo "  root 已安装 $(grep -c . "$auth") 个公钥"
    echo "  其它用户已配置公钥的数量：$(count_other_keyed_users)"
    echo ""
    echo "  写入的配置项："
    echo "    PubkeyAuthentication yes"
    echo "    PasswordAuthentication no"
    echo "    ChallengeResponseAuthentication no"
    echo "    KbdInteractiveAuthentication no"
    echo "    PermitRootLogin prohibit-password"
    echo ""
    log_warn "执行前请确认：你已能用密钥成功登录（不只是「配了公钥」）。"
    local confirm
    read -p "确认继续？输入 yes 继续: " confirm
    [[ "$confirm" == "yes" ]] || { log_info "已取消。"; return 0; }

    local target
    target="$(prepare_write "${DIRECTIVES_PASSWORD[@]}")"
    write_block "$target" password \
        "PubkeyAuthentication yes" \
        "PasswordAuthentication no" \
        "ChallengeResponseAuthentication no" \
        "KbdInteractiveAuthentication no" \
        "PermitRootLogin prohibit-password"

    if ! apply_config; then
        log_error "关闭密码登录失败，配置已回滚。"
        return 1
    fi

    show_keysetup_hint
}

# ==================== 功能 5：开启 SSH 转发 ====================

forward_status() {
    echo ""
    printf "  %-42s %s\n" "TCP 转发 (AllowTcpForwarding)"        "$(effective_of allowtcpforwarding)"
    printf "  %-42s %s\n" "Unix socket 转发 (AllowStreamLocalForwarding)" "$(effective_of allowstreamlocalforwarding)"
    printf "  %-42s %s\n" "远程端口绑定 (GatewayPorts)"           "$(effective_of gatewayports)"
    printf "  %-42s %s\n" "TUN 设备转发 (PermitTunnel)"           "$(effective_of permittunnel)"
    local po pl
    po="$(effective_of permitopen)"
    pl="$(effective_of permitlisten)"
    if [[ -n "$po" && "$po" != "any" ]] || [[ -n "$pl" && "$pl" != "any" ]]; then
        echo ""
        log_warn "检测到 PermitOpen/PermitListen 限制了转发目标："
        [[ -n "$po" ]] && echo "    PermitOpen   = ${po}"
        [[ -n "$pl" ]] && echo "    PermitListen = ${pl}"
        echo "  这些限制会覆盖上面的开关，需要时可手动注释掉。"
    fi
}

apply_forwarding() {
    local mode="$1" target
    target="$(prepare_write "${DIRECTIVES_FORWARD[@]}")"

    case "$mode" in
        tcp)
            write_block "$target" forward-tcp \
                "AllowTcpForwarding yes" \
                "AllowStreamLocalForwarding yes"
            ;;
        gateway)
            write_block "$target" forward-gateway "GatewayPorts yes"
            ;;
        tun)
            write_block "$target" forward-tun "PermitTunnel yes"
            ;;
        all)
            write_block "$target" forward-tcp \
                "AllowTcpForwarding yes" \
                "AllowStreamLocalForwarding yes"
            write_block "$target" forward-gateway "GatewayPorts yes"
            write_block "$target" forward-tun "PermitTunnel yes"
            ;;
        off)
            write_block "$target" forward-tcp \
                "AllowTcpForwarding no" \
                "AllowStreamLocalForwarding no"
            write_block "$target" forward-gateway "GatewayPorts no"
            write_block "$target" forward-tun "PermitTunnel no"
            ;;
    esac

    if ! apply_config; then
        log_error "写入失败，配置已回滚。"
        return 1
    fi
    forward_status
}

forward_menu() {
    echo ""
    log_info "SSH 转发设置"
    forward_status
    echo ""
    echo "  1) 开启 TCP 转发      （AllowTcpForwarding yes，支持 ssh -L / -R）"
    echo "  2) 开启远程绑定所有地址（GatewayPorts yes，-R 可监听 0.0.0.0）"
    echo "  3) 开启 TUN 设备转发  （PermitTunnel yes，支持 ssh -w）"
    echo "  4) 一键全部开启"
    echo "  5) 全部关闭"
    echo "  0) 返回"
    echo ""
    local n
    read -p "请输入选择 [0-5]: " n
    case "$n" in
        1) apply_forwarding tcp ;;
        2) apply_forwarding gateway ;;
        3) apply_forwarding tun ;;
        4)
            log_warn "GatewayPorts yes 会让 -R 绑定的端口暴露在公网，请确认这是你想要的效果。"
            local c
            read -p "确认全部开启？输入 yes 继续: " c
            [[ "$c" == "yes" ]] || { log_info "已取消。"; return 0; }
            apply_forwarding all
            ;;
        5) apply_forwarding off ;;
        0) return 0 ;;
        *) log_error "请输入正确的数字 [0-5]。" ;;
    esac
}

# ==================== 功能 6：查看生效配置 ====================

show_config() {
    echo ""
    local out
    out="$(sshd_effective)"
    if [[ -z "$out" ]]; then
        log_warn "sshd -T 读取失败，以下为配置文件里的相关行："
        grep -inE '^[[:space:]]*(Port|PasswordAuthentication|PubkeyAuthentication|PermitRootLogin|ChallengeResponseAuthentication|KbdInteractiveAuthentication|AllowTcpForwarding|GatewayPorts|PermitTunnel)' "$SSHD_CONFIG" 2>/dev/null
        return 0
    fi

    log_info "当前生效配置（sshd -T）"
    echo ""
    printf "  %-48s %s\n" "监听端口 (port)"                            "$(current_ports)"
    printf "  %-48s %s\n" "公钥登录 (pubkeyauthentication)"           "$(effective_of pubkeyauthentication)"
    printf "  %-48s %s\n" "密码登录 (passwordauthentication)"         "$(effective_of passwordauthentication)"
    printf "  %-48s %s\n" "键盘交互 (kbdinteractiveauthentication)"   "$(effective_of kbdinteractiveauthentication)"
    printf "  %-48s %s\n" "root 登录 (permitrootlogin)"               "$(effective_of permitrootlogin)"
    printf "  %-48s %s\n" "TCP 转发 (allowtcpforwarding)"             "$(effective_of allowtcpforwarding)"
    printf "  %-48s %s\n" "远程绑定 (gatewayports)"                   "$(effective_of gatewayports)"
    printf "  %-48s %s\n" "TUN 转发 (permittunnel)"                   "$(effective_of permittunnel)"
    printf "  %-48s %s\n" "PAM (usepam)"                              "$(effective_of usepam)"
    echo ""
    echo "  配置文件：$(config_target)"
    echo "  SSH 服务：$(sshd_service)"
    echo "  root 公钥数量：$( [[ -s /root/.ssh/authorized_keys ]] && grep -c . /root/.ssh/authorized_keys || echo 0 )"
}

# ==================== 功能 7：恢复备份 ====================

restore_backup() {
    echo ""
    local list
    list="$(list_backups)"
    if [[ -z "$list" ]]; then
        log_error "没有找到任何备份（${BACKUP_DIR}）。"
        return 1
    fi
    log_info "可用备份（新→旧）："
    local i=1 line
    local -a arr=()
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        arr+=("$line")
        printf "  %-2s %s\n" "[$i]" "$line"
        i=$((i + 1))
    done <<< "$list"

    echo ""
    local n
    read -p "请输入要恢复的编号（回车取消）: " n
    [[ -z "$n" ]] && { log_info "已取消。"; return 0; }
    if ! [[ "$n" =~ ^[0-9]+$ ]] || (( n < 1 || n > ${#arr[@]} )); then
        log_error "编号无效。"
        return 1
    fi

    local chosen="${arr[$((n - 1))]}"
    cat "$chosen" > "$SSHD_CONFIG"
    rm -f "$DROPIN_FILE"
    echo "$chosen" > "$BACKUP_LAST"
    log_info "已恢复：${chosen} → ${SSHD_CONFIG}"

    local bin
    bin="$(sshd_bin)"
    if [[ -n "$bin" ]]; then
        [[ -d /run/sshd ]] || mkdir -p /run/sshd 2>/dev/null || true
        if ! "$bin" -t >/dev/null 2>&1; then
            log_error "恢复后的配置校验失败，请手动检查：$("$bin" -t 2>&1)"
            return 1
        fi
    fi
    sshd_reload
    log_info "恢复完成，当前端口：$(current_ports)"
}

# ==================== 菜单 ====================

show_menu() {
    echo ""
    echo -e "  ${green}XrayR 配套脚本 · SSH 安全设置${plain}"
    echo "————————————————————————————"
    echo -e "  ${green}1.${plain} 修改 SSH 端口"
    echo -e "  ${green}2.${plain} 生成 / 安装 SSH 登录密钥"
    echo -e "  ${green}3.${plain} 启用密钥登录（保留密码登录）"
    echo -e "  ${green}4.${plain} 关闭密码登录（仅允许密钥登录）"
    echo -e "  ${green}5.${plain} 开启 SSH 转发（TCP / 远程绑定 / TUN）"
    echo -e "  ${green}6.${plain} 查看当前 SSH 生效配置"
    echo -e "  ${green}7.${plain} 恢复最近一次备份的配置"
    echo "————————————————————————————"
    echo -e "  ${green}0.${plain} 退出"
    echo ""
    local n
    read -p "请输入选择 [0-7]: " n
    case "$n" in
        1) change_port ;;
        2) key_menu ;;
        3) enable_pubkey_only ;;
        4) disable_password ;;
        5) forward_menu ;;
        6) show_config ;;
        7) restore_backup ;;
        0) exit 0 ;;
        *) log_error "请输入正确的数字 [0-7]。" ;;
    esac
}

main() {
    need_root
    check_sshd
    while true; do
        show_menu
        echo ""
        read -p "按回车返回菜单，或输入 q 退出: " back
        [[ "$back" == "q" || "$back" == "Q" ]] && exit 0
    done
}

# XRAYR_SSH_NO_MAIN=1 时只加载函数、不执行主流程（供自测使用）
if [[ "${XRAYR_SSH_NO_MAIN:-0}" != "1" ]]; then
    main "$@"
fi
