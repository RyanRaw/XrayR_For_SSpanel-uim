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

# ==================== 日志函数 ====================
log_info()    { echo -e "${green}$*${plain}" >&2; }
log_warn()    { echo -e "${yellow}$*${plain}" >&2; }
log_error()   { echo -e "${red}$*${plain}" >&2; }

# ==================== 前置检查 ====================
need_root() {
    if [[ ${EUID} -ne 0 ]]; then
        log_error "错误：必须使用 root 用户运行此脚本。"
        exit 1
    fi
}

check_os() {
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
        log_error "未检测到系统版本，请联系脚本作者！"
        exit 1
    fi

    # 检测系统版本号
    os_version=""
    if [[ -f /etc/os-release ]]; then
        os_version=$(awk -F'[= ."]' '/VERSION_ID/{print $3}' /etc/os-release)
    fi
    if [[ -z "$os_version" && -f /etc/lsb-release ]]; then
        os_version=$(awk -F'[= ."]+' '/DISTRIB_RELEASE/{print $2}' /etc/lsb-release)
    fi

    if [[ x"${release}" == x"centos" ]]; then
        if [[ ${os_version} -le 6 ]]; then
            log_error "请使用 CentOS 7 或更高版本的系统！"
            exit 1
        fi
    elif [[ x"${release}" == x"ubuntu" ]]; then
        if [[ ${os_version} -lt 16 ]]; then
            log_error "请使用 Ubuntu 16 或更高版本的系统！"
            exit 1
        fi
    elif [[ x"${release}" == x"debian" ]]; then
        if [[ ${os_version} -lt 8 ]]; then
            log_error "请使用 Debian 8 或更高版本的系统！"
            exit 1
        fi
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
        yum install epel-release -y
        yum install wget curl unzip tar crontabs socat -y
    else
        apt update -y
        apt install wget curl unzip tar cron socat -y
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

# ==================== 网络优化 ====================
backup_sysctl_conf() {
    local backup
    if [[ ! -f "$SYSCTL_CONF" ]]; then
        touch "$SYSCTL_CONF"
    fi
    backup="${SYSCTL_CONF}.bak.XrayR.$(date +%Y%m%d%H%M%S)"
    cp -a "$SYSCTL_CONF" "$backup"
    log_info "已备份 ${SYSCTL_CONF} 到 ${backup}"
}

detect_congestion_control() {
    local current available
    current="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true)"
    available="$(cat /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null || true)"
    if [[ "$current" == "bbrplus" ]]; then
        echo "bbrplus"
        return 0
    fi
    if echo "$available" | grep -q " bbr "; then
        echo "bbr"
        return 0
    fi
    echo ""
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
    cat "$tmp" > "$SYSCTL_CONF"
    rm -f "$tmp"
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
        log_warn "当前内核未检测到 bbr，跳过 tcp_congestion_control 设置。"
    elif [[ "$cc" == "bbrplus" ]]; then
        log_info "检测到已使用 bbrplus，保留现有拥塞控制。"
    else
        log_info "检测到内核支持 bbr，启用原生 BBR。"
    fi
    append_sysctl_optimization "$cc"
    apply_sysctl_optimization
    log_info "网络优化已应用。"
}

# ==================== 安装管理脚本 ====================
install_manager() {
    local script_url="https://cdn.jsdelivr.net/gh/${OWNER}/${SCRIPT_REPO}@master/install/XrayR.sh"
    if curl -fLs --connect-timeout 15 --retry 3 --retry-delay 2 -o "$MANAGER_BIN" "$script_url"; then
        chmod +x "$MANAGER_BIN"
        ln -sf "$MANAGER_BIN" "$MANAGER_BIN_LOWER"
        log_info "管理脚本已安装到 ${MANAGER_BIN}"
    else
        log_error "管理脚本下载失败！"
        exit 1
    fi
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

# ==================== 状态查询 ====================
# 返回值: 0=运行中, 1=未运行, 2=未安装
check_status() {
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

# ==================== 安装主流程 ====================
install_xrayr() {
    local version url
    version="$(normalize_version "${1:-}")"
    url="https://github.com/${OWNER}/${REPO}/releases/download/${version}/$(detect_arch)"

    log_info "开始安装 XrayR ${version}"
    echo "架构: $(detect_arch)"
    echo "下载地址: ${url}"

    install_base

    # 停止已有服务
    if command -v systemctl >/dev/null 2>&1; then
        systemctl stop XrayR >/dev/null 2>&1 || true
    fi

    # 清理并创建安装目录
    rm -rf "$INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"

    # 下载
    if ! wget -q --no-check-certificate -O "${INSTALL_DIR}/XrayR" "${url}"; then
        log_error "下载 XrayR 失败，请检查网络或版本是否存在。"
        exit 1
    fi

    chmod +x "${INSTALL_DIR}/XrayR"

    # 配置目录
    mkdir -p "$CONFIG_DIR"

    # systemd 服务
    write_service

    # 网络优化
    optimize_network

    # 管理脚本
    install_manager

    # 配置文件
    copy_config_files

    # 启动服务
    systemctl daemon-reload
    systemctl enable XrayR >/dev/null 2>&1 || true
    if [[ -f "$CONFIG_DIR/config.yml" ]]; then
        systemctl restart XrayR >/dev/null 2>&1 || true
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
    if command -v systemctl >/dev/null 2>&1; then
        systemctl stop XrayR >/dev/null 2>&1 || true
        systemctl disable XrayR >/dev/null 2>&1 || true
    fi
    rm -f "$SERVICE_FILE"
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
