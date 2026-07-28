#!/usr/bin/env bash
set -euo pipefail

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

version="v1.0.0"

# ==================== 常量 ====================
INSTALL_DIR="/usr/local/XrayR"
CONFIG_DIR="/etc/XrayR"
SERVICE_FILE="/etc/systemd/system/XrayR.service"

# ==================== 日志 ====================
log_info()  { echo -e "${green}$*${plain}"; }
log_warn()  { echo -e "${yellow}$*${plain}"; }
log_error() { echo -e "${red}$*${plain}" >&2; }

# ==================== 前置检查 ====================
need_root() {
    [[ $EUID -ne 0 ]] && log_error "错误：必须使用root用户运行此脚本！" && exit 1
}

# ==================== 系统检测 ====================
check_os() {
    local release os_version
    if [[ -f /etc/redhat-release ]]; then
        release="centos"
    elif grep -Eqi "debian" /etc/issue 2>/dev/null; then
        release="debian"
    elif grep -Eqi "ubuntu" /etc/issue 2>/dev/null; then
        release="ubuntu"
    elif grep -Eqi "centos|red hat|redhat" /etc/issue 2>/dev/null; then
        release="centos"
    elif grep -Eqi "debian" /proc/version 2>/dev/null; then
        release="debian"
    elif grep -Eqi "ubuntu" /proc/version 2>/dev/null; then
        release="ubuntu"
    elif grep -Eqi "centos|red hat|redhat" /proc/version 2>/dev/null; then
        release="centos"
    else
        log_error "未检测到系统版本！"
        exit 1
    fi

    os_version=""
    if [[ -f /etc/os-release ]]; then
        os_version=$(awk -F'[= ."]' '/VERSION_ID/{print $3}' /etc/os-release)
    fi
    if [[ -z "$os_version" && -f /etc/lsb-release ]]; then
        os_version=$(awk -F'[= ."]+' '/DISTRIB_RELEASE/{print $2}' /etc/lsb-release)
    fi

    case "$release" in
        centos) [[ ${os_version} -le 6 ]] && log_error "请使用 CentOS 7+" && exit 1 ;;
        ubuntu) [[ ${os_version} -lt 16 ]] && log_error "请使用 Ubuntu 16+" && exit 1 ;;
        debian) [[ ${os_version} -lt 8 ]] && log_error "请使用 Debian 8+" && exit 1 ;;
    esac
}

# ==================== 确认 ====================
confirm() {
    local prompt="$1" default="$2"
    echo && read -p "$prompt [默认$default]: " temp
    [[ x"${temp}" == x"" ]] && temp=$default
    [[ x"${temp}" == x"y" || x"${temp}" == x"Y" ]]
}

before_show_menu() {
    echo && echo -n -e "${yellow}按回车返回主菜单: ${plain}" && read temp
    show_menu
}

# ==================== 状态查询 ====================
# 0=running, 1=not running, 2=not installed
check_status() {
    if [[ ! -f "$SERVICE_FILE" ]]; then
        return 2
    fi
    local temp
    temp=$(systemctl status XrayR | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
    [[ x"${temp}" == x"running" ]]
}

check_enabled() {
    systemctl is-enabled XrayR >/dev/null 2>&1
}

check_uninstall() {
    if check_status; then
        log_error "XrayR已安装，请不要重复安装"
        return 1
    fi
    if [[ $? -eq 1 ]]; then
        log_error "XrayR已安装，请不要重复安装"
        return 1
    fi
    if [[ -f "$SERVICE_FILE" ]]; then
        log_error "XrayR已安装，请不要重复安装"
        return 1
    fi
    return 0
}

check_install() {
    if [[ ! -f "$SERVICE_FILE" ]]; then
        log_error "请先安装XrayR"
        return 1
    fi
    return 0
}

# ==================== 操作函数 ====================
install_xrayr() {
    bash <(curl -Ls https://cdn.jsdelivr.net/gh/RyanRaw/XrayR_For_SSpanel-uim@master/install/install.sh) "${1:-}"
    if [[ $? == 0 && $# == 0 ]]; then
        start
    fi
}

update_xrayr() {
    local ver="${2:-}"
    if [[ $# -lt 2 ]]; then
        echo && read -p "输入指定版本（默认最新版）: " ver
    fi
    bash <(curl -Ls https://cdn.jsdelivr.net/gh/RyanRaw/XrayR_For_SSpanel-uim@master/install/install.sh) "${ver}"
    log_info "更新完成，已自动重启 XrayR，请使用 XrayR log 查看运行日志"
    exit
}

edit_config() {
    echo "XrayR在修改配置后会自动尝试重启"
    vi "$CONFIG_DIR/config.yml"
    sleep 2
    check_status
    case $? in
        0) log_info "XrayR状态: 已运行" ;;
        1)
            echo -e "检测到XrayR自动重启失败，是否查看日志？[Y/n]"
            read -e -p "(默认: y): " yn
            [[ -z ${yn} ]] && yn="y"
            [[ ${yn} == [Yy] ]] && show_log
            ;;
    esac
}

start() {
    check_status && { log_info "XrayR已运行"; return 0; }
    systemctl start XrayR
    sleep 2
    check_status && log_info "XrayR 启动成功" || log_warn "XrayR可能启动失败"
}

stop() {
    systemctl stop XrayR
    sleep 2
    check_status || log_info "XrayR 停止成功" || log_warn "XrayR停止失败"
}

restart() {
    systemctl restart XrayR
    sleep 2
    check_status && log_info "XrayR 重启成功" || log_warn "XrayR可能启动失败"
}

status() {
    systemctl status XrayR --no-pager -l
    before_show_menu
}

enable() {
    systemctl enable XrayR && log_info "开机自启设置成功" || log_error "开机自启设置失败"
}

disable() {
    systemctl disable XrayR && log_info "取消开机自启成功" || log_error "取消开机自启失败"
}

show_log() {
    journalctl -u XrayR.service -e --no-pager -f
}

install_bbr() {
    bash <(curl -L -s https://raw.githubusercontent.com/chiakge/Linux-NetSpeed/master/tcp.sh)
}

update_shell() {
    wget -O "$(readlink -f "$0")" -N --no-check-certificate \
        https://cdn.jsdelivr.net/gh/RyanRaw/XrayR_For_SSpanel-uim@master/install/XrayR.sh
    chmod +x "$(readlink -f "$0")"
    log_info "升级脚本成功，请重新运行脚本" && exit 0
}

uninstall() {
    confirm "确定要卸载 XrayR 吗?" "n" || { show_menu; return 0; }
    systemctl stop XrayR >/dev/null 2>&1 || true
    systemctl disable XrayR >/dev/null 2>&1 || true
    rm -f "$SERVICE_FILE"
    systemctl daemon-reload || true
    systemctl reset-failed >/dev/null 2>&1 || true
    rm -rf "$CONFIG_DIR" "$INSTALL_DIR"
    rm -f /usr/bin/XrayR /usr/bin/xrayr
    echo ""
    log_info "卸载成功。"
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
    if check_status; then
        echo -e "XrayR状态: ${green}已运行${plain}"
    elif [[ -f "$SERVICE_FILE" ]]; then
        echo -e "XrayR状态: ${yellow}未运行${plain}"
    else
        echo -e "XrayR状态: ${red}未安装${plain}"
    fi
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
}

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
 ${green}11.${plain} 一键安装 bbr (最新内核)
 ${green}12.${plain} 查看 XrayR 版本 
 ${green}13.${plain} 升级维护脚本
"
    show_status
    echo && read -p "请输入选择 [0-13]: " num

    case "${num}" in
        0) edit_config ;;
        1) check_uninstall && install_xrayr ;;
        2) check_install && update_xrayr ;;
        3) check_install && uninstall ;;
        4) check_install && start ;;
        5) check_install && stop ;;
        6) check_install && restart ;;
        7) check_install && status ;;
        8) check_install && show_log ;;
        9) check_install && enable ;;
        10) check_install && disable ;;
        11) install_bbr ;;
        12) show_xrayr_version; before_show_menu ;;
        13) update_shell ;;
        *) echo -e "${red}请输入正确的数字 [0-13]${plain}" ;;
    esac
}

# ==================== 入口 ====================
main() {
    if [[ $# == 0 ]]; then
        show_menu
        return 0
    fi

    case $1 in
        start)     check_install && start 0 ;;
        stop)      check_install && stop 0 ;;
        restart)   check_install && restart 0 ;;
        status)    check_install && status 0 ;;
        enable)    check_install && enable 0 ;;
        disable)   check_install && disable 0 ;;
        log)       check_install && show_log 0 ;;
        update)    check_install && update_xrayr "$@" ;;
        config)    edit_config ;;
        install)   check_uninstall && install_xrayr 0 ;;
        uninstall) check_install && uninstall ;;
        version)   show_xrayr_version ;;
        update_shell) update_shell ;;
        *)         show_usage ;;
    esac
}

need_root
check_os
main "$@"
