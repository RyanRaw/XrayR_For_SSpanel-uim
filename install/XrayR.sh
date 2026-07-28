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

# ==================== 日志 ====================
log_info()  { echo -e "${green}$*${plain}"; }
log_warn()  { echo -e "${yellow}$*${plain}"; }
log_error() { echo -e "${red}$*${plain}" >&2; }

# ==================== 前置检查 ====================
need_root() {
    [[ $EUID -ne 0 ]] && log_error "错误：必须使用 root 用户运行此脚本！" && exit 1
}

before_show_menu() {
    echo && echo -n -e "${yellow}按回车返回主菜单: ${plain}" && read temp
    show_menu
}

# ==================== 状态查询 ====================
# 返回值: 0=运行中, 1=未运行, 2=未安装
check_status() {
    if [[ ! -f "$SERVICE_FILE" ]]; then
        return 2
    fi
    if systemctl is-active --quiet XrayR 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# 返回值: 0=已连接, 1=未运行, 2=未安装, 3=未连接(面板不通)
check_panel_status() {
    local state logs fail_line success_line
    if [[ ! -f "$SERVICE_FILE" ]]; then
        return 2
    fi
    state=$(systemctl is-active XrayR 2>/dev/null || true)
    if [[ x"${state}" != x"active" && x"${state}" != x"activating" ]]; then
        return 1
    fi
    logs=$(journalctl -u XrayR -n 100 --no-pager 2>/dev/null || true)
    fail_line=$(echo "${logs}" | grep -Ein "connect: connection refused|no such host|timeout|unauthorized|(^|[^0-9])401([^0-9]|$)|(^|[^0-9])403([^0-9]|$)|Failed to get node info|Get node info failed|request failed|cannot get node info|panel" | tail -n1 | cut -d: -f1)
    success_line=$(echo "${logs}" | grep -Ein "Added|users|Start monitor node status|Start report node status|Get node info|node info|Update node info|Core Start|Xray Core Version" | tail -n1 | cut -d: -f1)
    if [[ -n "${success_line}" && ( -z "${fail_line}" || "${success_line}" -gt "${fail_line}" ) ]]; then
        return 0
    fi
    return 3
}

check_enabled() {
    systemctl is-enabled XrayR >/dev/null 2>&1
}

check_installed() {
    if [[ ! -f "$SERVICE_FILE" ]]; then
        log_error "请先安装 XrayR"
        return 1
    fi
    return 0
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
        systemctl start XrayR
        sleep 2
        if systemctl is-active --quiet XrayR 2>/dev/null; then
            log_info "XrayR 启动成功"
        else
            log_warn "XrayR 可能启动失败"
        fi
    fi
}

do_stop() {
    systemctl stop XrayR
    sleep 2
    if systemctl is-active --quiet XrayR 2>/dev/null; then
        log_warn "XrayR 停止失败，请查看日志"
    else
        log_info "XrayR 停止成功"
    fi
}

do_restart() {
    systemctl restart XrayR
    sleep 2
    if systemctl is-active --quiet XrayR 2>/dev/null; then
        log_info "XrayR 重启成功"
    else
        log_warn "XrayR 可能启动失败"
    fi
}

do_status() {
    systemctl status XrayR --no-pager -l
}

do_enable() {
    if systemctl enable XrayR 2>/dev/null; then
        log_info "开机自启设置成功"
    else
        log_error "开机自启设置失败"
    fi
}

do_disable() {
    if systemctl disable XrayR 2>/dev/null; then
        log_info "取消开机自启成功"
    else
        log_error "取消开机自启失败"
    fi
}

show_log() {
    journalctl -u XrayR.service -e --no-pager -f
}

install_bbr() {
    bash <(curl -Ls https://cdn.jsdelivr.net/gh/RyanRaw/XrayR_For_SSpanel-uim@master/install/install.sh) optimize
}

update_shell() {
    local self
    self="$(readlink -f "$0")"
    wget -O "$self" -N --no-check-certificate \
        https://cdn.jsdelivr.net/gh/RyanRaw/XrayR_For_SSpanel-uim@master/install/XrayR.sh
    chmod +x "$self"
    log_info "升级脚本成功，请重新运行脚本" && exit 0
}

do_uninstall() {
    confirm "确定要卸载 XrayR 吗?" "n" || { show_menu; return 0; }
    systemctl stop XrayR >/dev/null 2>&1 || true
    systemctl disable XrayR >/dev/null 2>&1 || true
    rm -f "$SERVICE_FILE"
    systemctl daemon-reload || true
    systemctl reset-failed >/dev/null 2>&1 || true
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
"
    show_status
    echo && read -p "请输入选择 [0-13]: " num

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
        *) echo -e "${red}请输入正确的数字 [0-13]${plain}" && before_show_menu ;;
    esac
}

# ==================== 入口 ====================
main() {
    if [[ $# == 0 ]]; then
        show_menu
        return 0
    fi

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
        *)         show_usage ;;
    esac
}

need_root
main "$@"
