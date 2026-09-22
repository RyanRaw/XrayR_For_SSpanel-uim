#!/usr/bin/env bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

version="v1.0.0"

# ==================== 常量 ====================
INSTALL_DIR="/usr/local/XrayR"
CONFIG_DIR="/etc/XrayR"
SERVICE_FILE="/etc/systemd/system/XrayR.service"
OPENRC_FILE="/etc/init.d/XrayR"

# 脚本下载源（jsDelivr 加速 / 源站直连备用）
SCRIPT_OWNER="RyanRaw"
SCRIPT_REPO="XrayR_For_SSpanel-uim"
SCRIPT_CDN_BASE="https://cdn.jsdelivr.net/gh/${SCRIPT_OWNER}/${SCRIPT_REPO}@master"
SCRIPT_RAW_BASE="https://raw.githubusercontent.com/${SCRIPT_OWNER}/${SCRIPT_REPO}/master"

# 检测系统类型（Alpine 使用 OpenRC，其余使用 systemd）
if [[ -f /etc/os-release ]]; then
    . /etc/os-release 2>/dev/null
    release="${ID:-}"
fi
if [[ -z "${release:-}" ]]; then
    release="debian"   # 兜底
fi

# ==================== 日志 ====================
log_info()  { echo -e "${green}$*${plain}"; }
log_warn()  { echo -e "${yellow}$*${plain}"; }
log_error() { echo -e "${red}$*${plain}" >&2; }

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

# jsDelivr 对 @master 有缓存，先请求 purge 接口强制刷新，避免拉到旧脚本
purge_jsdelivr() {
    command -v curl >/dev/null 2>&1 || return 0
    curl -fsL --max-time 20 \
        "https://purge.jsdelivr.net/gh/${SCRIPT_OWNER}/${SCRIPT_REPO}@master/$1" >/dev/null 2>&1 || true
}

# ==================== 前置检查 ====================
need_root() {
    [[ $EUID -ne 0 ]] && log_error "错误：必须使用 root 用户运行此脚本！" && exit 1
}

before_show_menu() {
    echo && echo -n -e "${yellow}按回车返回主菜单: ${plain}" && read temp
    show_menu
}

# ==================== 状态查询 ====================
service_installed() {
    if [[ x"${release}" == x"alpine" ]]; then
        [[ -f "$OPENRC_FILE" ]]
    else
        [[ -f "$SERVICE_FILE" ]]
    fi
}

# 返回值: 0=运行中, 1=未运行, 2=未安装
check_status() {
    if ! service_installed; then
        return 2
    fi
    if [[ x"${release}" == x"alpine" ]]; then
        rc-service XrayR status >/dev/null 2>&1 && return 0 || return 1
    else
        systemctl is-active --quiet XrayR 2>/dev/null && return 0 || return 1
    fi
}

# 返回值: 0=已连接, 1=未运行, 2=未安装, 3=未连接(面板不通)
check_panel_status() {
    local state logs fail_line success_line
    if ! service_installed; then
        return 2
    fi
    if [[ x"${release}" == x"alpine" ]]; then
        state=$(rc-service XrayR status >/dev/null 2>&1 && echo active || echo inactive)
    else
        state=$(systemctl is-active XrayR 2>/dev/null || true)
    fi
    if [[ x"${state}" != x"active" && x"${state}" != x"activating" ]]; then
        return 1
    fi
    if [[ x"${release}" == x"alpine" ]]; then
        logs=$(rc-service XrayR status 2>/dev/null || true)
    else
        logs=$(journalctl -u XrayR -n 100 --no-pager 2>/dev/null || true)
    fi
    fail_line=$(echo "${logs}" | grep -Ein "connect: connection refused|no such host|timeout|unauthorized|(^|[^0-9])401([^0-9]|$)|(^|[^0-9])403([^0-9]|$)|Failed to get node info|Get node info failed|request failed|cannot get node info|panel" | tail -n1 | cut -d: -f1)
    success_line=$(echo "${logs}" | grep -Ein "Added|users|Start monitor node status|Start report node status|Get node info|node info|Update node info|Core Start|Xray Core Version" | tail -n1 | cut -d: -f1)
    if [[ -n "${success_line}" && ( -z "${fail_line}" || "${success_line}" -gt "${fail_line}" ) ]]; then
        return 0
    fi
    return 3
}

check_enabled() {
    if [[ x"${release}" == x"alpine" ]]; then
        rc-update show default 2>/dev/null | grep -q "^ *XrayR " 
    else
        systemctl is-enabled XrayR >/dev/null 2>&1
    fi
}

check_installed() {
    if ! service_installed; then
        log_error "请先安装 XrayR"
        return 1
    fi
    return 0
}

# 把未识别的命令原样透传给 XrayR 二进制（mldsa65 / x25519 / tls ping 等）
run_binary() {
    if [[ ! -x "$INSTALL_DIR/XrayR" ]]; then
        log_error "XrayR 未安装，请先执行：XrayR install"
        return 1
    fi
    exec "$INSTALL_DIR/XrayR" "$@"
}

# ==================== 确认 ====================
confirm() {
    local prompt="$1" default="$2"
    echo && read -p "$prompt [默认$default]: " temp
    [[ x"${temp}" == x"" ]] && temp=$default
    [[ x"${temp}" == x"y" || x"${temp}" == x"Y" ]]
}

# ==================== 操作函数 ====================
install_xrayr() {
    bash <(curl -Ls https://cdn.jsdelivr.net/gh/RyanRaw/XrayR_For_SSpanel-uim@master/install/install.sh) "${1:-}"
}

update_xrayr() {
    local ver="${2:-}"
    if [[ $# -lt 2 ]]; then
        echo && read -p "输入指定版本（默认最新版）: " ver
    fi
    bash <(curl -Ls https://cdn.jsdelivr.net/gh/RyanRaw/XrayR_For_SSpanel-uim@master/install/install.sh) "${ver}"
    log_info "更新完成，请使用 XrayR log 查看运行日志"
    exit
}

edit_config() {
    echo "XrayR 在修改配置后会自动尝试重启"
    vi "$CONFIG_DIR/config.yml"
    sleep 2
    check_status
    case $? in
        0) log_info "XrayR 状态: 已运行" ;;
        1)
            echo -e "检测到 XrayR 自动重启失败，是否查看日志？[Y/n]"
            read -e -p "(默认: y): " yn
            [[ -z ${yn} ]] && yn="y"
            [[ ${yn} == [Yy] ]] && show_log
            ;;
    esac
}

do_start() {
    check_status
    local st=$?
    if [[ $st -eq 0 ]]; then
        log_info "XrayR 已运行，无需再次启动"
    elif [[ $st -eq 2 ]]; then
        log_error "请先安装 XrayR"
        return 1
    else
        if [[ x"${release}" == x"alpine" ]]; then
            rc-service XrayR start
        else
            systemctl start XrayR
        fi
        sleep 2
        if check_status; then
            log_info "XrayR 启动成功"
        else
            log_warn "XrayR 可能启动失败"
        fi
    fi
}

do_stop() {
    if [[ x"${release}" == x"alpine" ]]; then
        rc-service XrayR stop
    else
        systemctl stop XrayR
    fi
    sleep 2
    if check_status; then
        log_warn "XrayR 停止失败，请查看日志"
    else
        log_info "XrayR 停止成功"
    fi
}

do_restart() {
    if [[ x"${release}" == x"alpine" ]]; then
        rc-service XrayR restart
    else
        systemctl restart XrayR
    fi
    sleep 2
    if check_status; then
        log_info "XrayR 重启成功"
    else
        log_warn "XrayR 可能启动失败"
    fi
}

do_status() {
    if [[ x"${release}" == x"alpine" ]]; then
        rc-service XrayR status
    else
        systemctl status XrayR --no-pager -l
    fi
}

do_enable() {
    if [[ x"${release}" == x"alpine" ]]; then
        if rc-update add XrayR default 2>/dev/null; then
            log_info "开机自启设置成功"
        else
            log_error "开机自启设置失败"
        fi
    else
        if systemctl enable XrayR 2>/dev/null; then
            log_info "开机自启设置成功"
        else
            log_error "开机自启设置失败"
        fi
    fi
}

do_disable() {
    if [[ x"${release}" == x"alpine" ]]; then
        if rc-update del XrayR default 2>/dev/null; then
            log_info "取消开机自启成功"
        else
            log_error "取消开机自启失败"
        fi
    else
        if systemctl disable XrayR 2>/dev/null; then
            log_info "取消开机自启成功"
        else
            log_error "取消开机自启失败"
        fi
    fi
}

show_log() {
    if [[ x"${release}" == x"alpine" ]]; then
        local logfile="/var/log/XrayR.log"
        if [[ ! -f "$logfile" ]]; then
            log_warn "未找到日志文件 ${logfile}，请确认 XrayR 已安装并启动。"
            return 1
        fi
        check_status
        local st=$?
        if [[ $st -eq 0 ]]; then
            tail -f "$logfile"
        elif [[ $st -eq 2 ]]; then
            log_warn "XrayR 未安装或 init 脚本不存在，请先运行 install.sh install"
            return 1
        else
            # 进程存在但已退出（可能是配置问题）
            if grep -q "error\|fail\|config" "$logfile" 2>/dev/null; then
                log_warn "日志中发现错误/配置问题，请检查 ${logfile}"
            fi
            log_info "XrayR 当前未运行，仅显示已有日志（实时跟踪 ${logfile}）。"
            tail -f "$logfile"
        fi
    else
        journalctl -u XrayR.service -e --no-pager -f
    fi
}

install_bbr() {
    bash <(curl -Ls https://cdn.jsdelivr.net/gh/RyanRaw/XrayR_For_SSpanel-uim@master/install/install.sh) optimize
}

# ==================== 密钥生成 ====================
do_x25519() {
    local key
    echo "直接回车随机生成；也可粘贴已有私钥，反推出对应的公钥。"
    read -p "私钥 (base64.RawURLEncoding, 可留空): " key
    echo ""
    if [[ -n "$key" ]]; then
        "$INSTALL_DIR/XrayR" x25519 -i "$key" || return 1
    else
        "$INSTALL_DIR/XrayR" x25519 || return 1
    fi
    echo ""
    echo -e "  ${green}Private key${plain} → 服务端 privateKey / config.yml 的 REALITYConfigs.PrivateKey"
    echo -e "  ${green}Public key${plain}  → 客户端 pbk / publicKey"
}

do_mldsa65() {
    local seed
    echo "直接回车随机生成；也可粘贴已有 seed，反推出对应的 Verify。"
    read -p "Seed (base64.RawURLEncoding, 可留空): " seed
    echo ""
    if [[ -n "$seed" ]]; then
        "$INSTALL_DIR/XrayR" mldsa65 -i "$seed" || return 1
    else
        "$INSTALL_DIR/XrayR" mldsa65 || return 1
    fi
    echo ""
    echo -e "  ${green}Seed${plain}   → 服务端 mldsa65Seed（必须与 privateKey 不同）"
    echo -e "  ${green}Verify${plain} → 客户端 mldsa65Verify / pqv"
}

do_ssh() {
    # SSH 安全设置（改端口 / 生成密钥 / 密码登录 / 转发）由独立脚本处理。
    # 与 update_shell 一致：先清 CDN 缓存，CDN 失败或内容异常时回退源站，
    # 否则 @master 的缓存窗口内可能跑到旧脚本（或新文件刚发布时拿到 404）。
    local tmp url ok=0
    tmp="$(mktemp 2>/dev/null || echo "/tmp/ssh.sh.$$")"

    log_info "正在拉取 SSH 安全设置脚本..."
    purge_jsdelivr "install/ssh.sh"

    for url in "${SCRIPT_CDN_BASE}/install/ssh.sh" "${SCRIPT_RAW_BASE}/install/ssh.sh"; do
        if download_file "$url" "$tmp" && [[ -s "$tmp" ]] && bash -n "$tmp" 2>/dev/null; then
            ok=1
            break
        fi
    done

    if [[ "$ok" != "1" ]]; then
        rm -f "$tmp"
        log_error "下载 SSH 安全设置脚本失败，请检查网络后重试"
        return 1
    fi

    bash "$tmp"
    local rc=$?
    rm -f "$tmp"
    return $rc
}

update_shell() {
    local self tmp url ok=0
    self="$(readlink -f "$0")"
    tmp="$(mktemp 2>/dev/null || echo "/tmp/XrayR.sh.$$")"

    log_info "正在拉取最新管理脚本..."
    # 先清 jsDelivr 缓存，否则 @master 可能仍返回旧内容
    purge_jsdelivr "install/XrayR.sh"

    # CDN 优先，失败或内容异常时回退源站
    for url in "${SCRIPT_CDN_BASE}/install/XrayR.sh" "${SCRIPT_RAW_BASE}/install/XrayR.sh"; do
        if download_file "$url" "$tmp" && [[ -s "$tmp" ]] && bash -n "$tmp" 2>/dev/null; then
            ok=1
            break
        fi
    done

    if [[ "$ok" != "1" ]]; then
        rm -f "$tmp"
        log_error "下载管理脚本失败，请检查网络后重试"
        return 1
    fi

    cp -f "$self" "${self}.bak" 2>/dev/null || true
    cat "$tmp" > "$self"
    rm -f "$tmp"
    chmod +x "$self"
    log_info "升级脚本成功（旧版已备份为 ${self}.bak），请重新运行脚本"
    exit 0
}

do_uninstall() {
    confirm "确定要卸载 XrayR 吗?" "n" || { show_menu; return 0; }
    if [[ x"${release}" == x"alpine" ]]; then
        rc-service XrayR stop >/dev/null 2>&1 || true
        rc-update del XrayR default >/dev/null 2>&1 || true
        rm -f "$OPENRC_FILE" /etc/conf.d/XrayR
    else
        systemctl stop XrayR >/dev/null 2>&1 || true
        systemctl disable XrayR >/dev/null 2>&1 || true
        rm -f "$SERVICE_FILE"
        systemctl daemon-reload || true
        systemctl reset-failed >/dev/null 2>&1 || true
    fi
    rm -rf "$CONFIG_DIR" "$INSTALL_DIR"
    rm -f /usr/bin/XrayR /usr/bin/xrayr
    echo ""
    log_info "XrayR 已卸载。"
}

show_xrayr_version() {
    if [[ -x "$INSTALL_DIR/XrayR" ]]; then
        echo -n "XrayR 版本："
        "$INSTALL_DIR/XrayR" version
    else
        echo "XrayR 未安装"
    fi
}

show_status() {
    check_panel_status
    case $? in
        0) echo -e "XrayR 状态: ${green}已运行 (已连接)${plain}" ;;
        1) echo -e "XrayR 状态: ${yellow}未运行${plain}" ;;
        2) echo -e "XrayR 状态: ${red}未安装${plain}" ;;
        3) echo -e "XrayR 状态: ${yellow}已运行 (面板未连接)${plain}" ;;
    esac
    if check_enabled; then
        echo -e "是否开机自启: ${green}是${plain}"
    else
        echo -e "是否开机自启: ${red}否${plain}"
    fi
}

show_usage() {
    echo "XrayR 管理脚本使用方法: "
    echo "------------------------------------------"
    echo "XrayR              - 显示管理菜单 (功能更多)"
    echo "XrayR start        - 启动 XrayR"
    echo "XrayR stop         - 停止 XrayR"
    echo "XrayR restart      - 重启 XrayR"
    echo "XrayR status       - 查看 XrayR 状态"
    echo "XrayR enable       - 设置 XrayR 开机自启"
    echo "XrayR disable      - 取消 XrayR 开机自启"
    echo "XrayR log          - 查看 XrayR 日志"
    echo "XrayR update       - 更新 XrayR"
    echo "XrayR update x.x.x - 更新 XrayR 指定版本"
    echo "XrayR install      - 安装 XrayR"
    echo "XrayR uninstall    - 卸载 XrayR"
    echo "XrayR version      - 查看 XrayR 版本"
    echo "------------------------------------------"
    echo "未识别的参数会原样透传给 XrayR 二进制，例如: "
    echo "XrayR mldsa65      - 生成 ML-DSA-65 密钥对 (REALITY)"
    echo "XrayR x25519       - 生成 x25519 密钥对"
    echo "XrayR tls ping xxx - TLS 握手探测 (可加 -ip <ip>)"
    echo "------------------------------------------"
}

# ==================== 菜单 ====================
show_menu() {
    echo -e "
  ${green}XrayR 后端管理脚本 (SSPanel-UIM 适配版)${plain}${red}不适用于docker${plain}
--- https://github.com/RyanRaw/XrayR_For_SSpanel-uim ---
  ${green}0.${plain} 修改配置
————————————————
  ${green}1.${plain} 安装 XrayR
  ${green}2.${plain} 更新 XrayR
  ${green}3.${plain} 卸载 XrayR
————————————————
  ${green}4.${plain} 启动 XrayR
  ${green}5.${plain} 停止 XrayR
  ${green}6.${plain} 重启 XrayR
  ${green}7.${plain} 查看 XrayR 状态
  ${green}8.${plain} 查看 XrayR 日志
————————————————
  ${green}9.${plain} 设置 XrayR 开机自启
 ${green}10.${plain} 取消 XrayR 开机自启
————————————————
 ${green}11.${plain} 应用网络优化 (原生 BBR/fq)
 ${green}12.${plain} 查看 XrayR 版本
 ${green}13.${plain} 升级维护脚本
————————————————
 ${green}14.${plain} 生成 x25519 密钥对 (REALITY)
 ${green}15.${plain} 生成 ML-DSA-65 密钥对 (REALITY 后量子)
————————————————
 ${green}16.${plain} SSH 安全设置 (端口 / 密钥 / 密码登录 / 转发)
————————————————
 ${green}17.${plain} 退出
"
    show_status
    echo && read -p "请输入选择 [0-17]: " num

    case "${num}" in
        0) edit_config; before_show_menu ;;
        1) if check_installed 2>/dev/null; then log_error "XrayR 已安装"; else install_xrayr; fi; before_show_menu ;;
        2) check_installed && update_xrayr ;;
        3) check_installed && do_uninstall ;;
        4) check_installed && do_start; before_show_menu ;;
        5) check_installed && do_stop; before_show_menu ;;
        6) check_installed && do_restart; before_show_menu ;;
        7) check_installed && do_status ;;
        8) check_installed && show_log ;;
        9) check_installed && do_enable; before_show_menu ;;
        10) check_installed && do_disable; before_show_menu ;;
        11) install_bbr; before_show_menu ;;
        12) show_xrayr_version; before_show_menu ;;
        13) update_shell ;;
        14) check_installed && do_x25519; before_show_menu ;;
        15) check_installed && do_mldsa65; before_show_menu ;;
        16) do_ssh; before_show_menu ;;
        17) log_info "已退出。"; exit 0 ;;
        *) echo -e "${red}请输入正确的数字 [0-17]${plain}" && before_show_menu ;;
    esac
}

# ==================== 入口 ====================
main() {
    if [[ $# == 0 ]]; then
        need_root
        show_menu
        return 0
    fi

    case $1 in
        # 以下为管理命令，需要 root 权限
        start|stop|restart|status|enable|disable|log|update|config|install|uninstall|version|update_shell)
            need_root
            ;;
        *)
            # 其他命令原样透传给 XrayR 二进制，工具类命令（mldsa65 / x25519 / tls ping）无需 root
            run_binary "$@"
            return
            ;;
    esac

    case $1 in
        start)     check_installed && do_start ;;
        stop)      check_installed && do_stop ;;
        restart)   check_installed && do_restart ;;
        status)    check_installed && do_status ;;
        enable)    check_installed && do_enable ;;
        disable)   check_installed && do_disable ;;
        log)       check_installed && show_log ;;
        update)    check_installed && update_xrayr "$@" ;;
        config)    edit_config ;;
        install)   if check_installed 2>/dev/null; then log_error "XrayR 已安装"; else install_xrayr; fi ;;
        uninstall) check_installed && do_uninstall ;;
        version)   show_xrayr_version ;;
        update_shell) update_shell ;;
    esac
}

main "$@"
