#!/bin/bash
#
# Steam++ Linux 系统级代理配置脚本
# 适用于: Ubuntu / Debian / CentOS / Fedora / Arch
# 功能: 系统级导入根证书 + 全局代理环境变量
#
# 用法:
#   sudo bash steampp-system-proxy.sh [install|uninstall|status]
#   
# 默认行为: 交互式安装
#

set -euo pipefail

# ==================== 配置 ====================
SCRIPT_VERSION="1.0.0"
STEAMPP_CERT_NAME="SteamTools"
STEAMPP_CERT_FILE="SteamTools.Certificate.cer"
PROFILE_FILE="/etc/profile.d/steampp-proxy.sh"
GIT_CONFIG_SYSTEM="/etc/gitconfig"

# Steam++ 默认端口（HTTP 代理）
PROXY_HTTP_PORT="26501"
PROXY_SOCKS_PORT="26501"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ==================== 工具函数 ====================
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_ok() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_err() {
    echo -e "${RED}[ERR]${NC} $1"
}

# 检测发行版
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "$ID"
    elif [ -f /etc/redhat-release ]; then
        echo "centos"
    elif [ -f /etc/arch-release ]; then
        echo "arch"
    else
        echo "unknown"
    fi
}

# 检测包管理器
get_pkg_manager() {
    local distro=$(detect_distro)
    case "$distro" in
        ubuntu|debian|linuxmint|pop)
            echo "apt"
            ;;
        centos|rhel|fedora|rocky|almalinux)
            if command -v dnf &>/dev/null; then
                echo "dnf"
            else
                echo "yum"
            fi
            ;;
        arch|manjaro|endeavouros)
            echo "pacman"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# 检测 Steam++ 是否运行
check_steamp_running() {
    if ss -tlnp 2>/dev/null | grep -q ":$PROXY_HTTP_PORT"; then
        return 0
    elif netstat -tlnp 2>/dev/null | grep -q ":$PROXY_HTTP_PORT"; then
        return 0
    fi
    return 1
}

# 获取 Steam++ 证书路径（自动搜索常见位置）
find_steamp_cert() {
    local search_paths=(
        "$HOME/.local/share/Steam++/Plugins/Accelerator/$STEAMPP_CERT_FILE"
        "$HOME/.config/Steam++/Plugins/Accelerator/$STEAMPP_CERT_FILE"
        "/opt/Steam++/Plugins/Accelerator/$STEAMPP_CERT_FILE"
        "/usr/share/Steam++/Plugins/Accelerator/$STEAMPP_CERT_FILE"
        "/tmp/$STEAMPP_CERT_FILE"
    )
    
    for path in "${search_paths[@]}"; do
        if [ -f "$path" ]; then
            echo "$path"
            return 0
        fi
    done
    
    return 1
}

# 检查 root 权限
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_err "此脚本需要 root 权限运行"
        log_info "请使用: sudo bash $0"
        exit 1
    fi
}

# ==================== 安装功能 ====================
install_cert() {
    log_info "正在导入 Steam++ 根证书到系统 CA..."
    
    local distro=$(detect_distro)
    local cert_path=""
    
    # 尝试自动查找证书
    cert_path=$(find_steamp_cert || true)
    
    # 如果找不到，提示用户输入
    if [ -z "$cert_path" ] || [ ! -f "$cert_path" ]; then
        log_warn "无法自动找到 Steam++ 证书文件"
        echo ""
        echo "请手动指定证书路径，常见位置:"
        echo "  - ~/.local/share/Steam++/Plugins/Accelerator/$STEAMPP_CERT_FILE"
        echo "  - /opt/Steam++/Plugins/Accelerator/$STEAMPP_CERT_FILE"
        echo ""
        read -rp "证书路径 (留空退出): " cert_path
        
        if [ -z "$cert_path" ] || [ ! -f "$cert_path" ]; then
            log_err "证书文件不存在"
            return 1
        fi
    fi
    
    log_info "使用证书: $cert_path"
    
    # 根据发行版导入证书
    case "$distro" in
        ubuntu|debian|linuxmint|pop)
            # Debian/Ubuntu 方式
            cp "$cert_path" "/usr/local/share/ca-certificates/${STEAMPP_CERT_NAME}.crt"
            update-ca-certificates
            ;;
        centos|rhel|fedora|rocky|almalinux)
            # RHEL/CentOS/Fedora 方式
            local cert_dir="/etc/pki/ca-trust/source/anchors"
            mkdir -p "$cert_dir"
            cp "$cert_path" "$cert_dir/${STEAMPP_CERT_NAME}.crt"
            update-ca-trust extract
            ;;
        arch|manjaro|endeavouros)
            # Arch 方式
            if command -v trust &>/dev/null; then
                trust anchor --store "$cert_path"
            else
                cp "$cert_path" "/usr/local/share/ca-certificates/${STEAMPP_CERT_NAME}.crt"
                update-ca-certificates
            fi
            ;;
        *)
            # 通用方式
            if command -v update-ca-certificates &>/dev/null; then
                mkdir -p /usr/local/share/ca-certificates
                cp "$cert_path" "/usr/local/share/ca-certificates/${STEAMPP_CERT_NAME}.crt"
                update-ca-certificates
            elif command -v update-ca-trust &>/dev/null; then
                local cert_dir="/etc/pki/ca-trust/source/anchors"
                mkdir -p "$cert_dir"
                cp "$cert_path" "$cert_dir/${STEAMPP_CERT_NAME}.crt"
                update-ca-trust extract
            else
                log_err "不支持的发行版，无法自动导入证书"
                return 1
            fi
            ;;
    esac
    
    log_ok "系统 CA 证书导入成功"
    return 0
}

install_proxy_env() {
    log_info "正在配置系统级代理环境变量..."
    
    cat > "$PROFILE_FILE" << 'EOF'
# Steam++ System Proxy Configuration
# 由 steampp-system-proxy.sh 自动生成
# 作用: 为所有用户配置 HTTP/HTTPS 代理环境变量

# 检测 Steam++ 是否在运行
_steamp_check_proxy() {
    local port=26501
    # 使用多种方式检测端口
    if command -v ss &>/dev/null && ss -tln 2>/dev/null | grep -q ":${port}"; then
        return 0
    elif command -v netstat &>/dev/null && netstat -tln 2>/dev/null | grep -q ":${port}"; then
        return 0
    elif command -v lsof &>/dev/null && lsof -i :${port} &>/dev/null; then
        return 0
    fi
    return 1
}

# 如果 Steam++ 在运行，设置代理
if _steamp_check_proxy; then
    export HTTP_PROXY="http://127.0.0.1:26501"
    export HTTPS_PROXY="http://127.0.0.1:26501"
    export ALL_PROXY="socks5://127.0.0.1:26501"
    export http_proxy="http://127.0.0.1:26501"
    export https_proxy="http://127.0.0.1:26501"
    export all_proxy="socks5://127.0.0.1:26501"
    
    # 不代理本地地址
    export NO_PROXY="localhost,127.0.0.1,::1,.local"
    export no_proxy="localhost,127.0.0.1,::1,.local"
    
    # Git 专用环境变量
    export GIT_HTTP_PROXY="http://127.0.0.1:26501"
    export GIT_HTTPS_PROXY="http://127.0.0.1:26501"
fi

# 清理临时函数
unset -f _steamp_check_proxy 2>/dev/null || true
EOF
    
    chmod 644 "$PROFILE_FILE"
    log_ok "代理环境变量配置完成: $PROFILE_FILE"
}

install_git_config() {
    log_info "正在配置 Git 系统级代理..."
    
    # 配置 Git 系统级代理
    git config --system http.proxy "http://127.0.0.1:26501" || true
    git config --system https.proxy "http://127.0.0.1:26501" || true
    git config --system http.sslVerify true || true
    
    log_ok "Git 系统级代理配置完成"
}

# ==================== 卸载功能 ====================
uninstall() {
    log_info "正在卸载 Steam++ 系统代理配置..."
    
    local distro=$(detect_distro)
    local removed=0
    
    # 1. 移除系统证书
    case "$distro" in
        ubuntu|debian|linuxmint|pop)
            if [ -f "/usr/local/share/ca-certificates/${STEAMPP_CERT_NAME}.crt" ]; then
                rm -f "/usr/local/share/ca-certificates/${STEAMPP_CERT_NAME}.crt"
                update-ca-certificates --fresh
                removed=1
            fi
            ;;
        centos|rhel|fedora|rocky|almalinux)
            if [ -f "/etc/pki/ca-trust/source/anchors/${STEAMPP_CERT_NAME}.crt" ]; then
                rm -f "/etc/pki/ca-trust/source/anchors/${STEAMPP_CERT_NAME}.crt"
                update-ca-trust extract
                removed=1
            fi
            ;;
        arch|manjaro|endeavouros)
            if command -v trust &>/dev/null; then
                trust anchor --remove "${STEAMPP_CERT_NAME}" 2>/dev/null || true
                removed=1
            fi
            ;;
    esac
    
    if [ "$removed" -eq 1 ]; then
        log_ok "系统 CA 证书已移除"
    else
        log_warn "未找到已导入的证书"
    fi
    
    # 2. 移除环境变量配置
    if [ -f "$PROFILE_FILE" ]; then
        rm -f "$PROFILE_FILE"
        log_ok "代理环境变量配置已移除: $PROFILE_FILE"
    fi
    
    # 3. 移除 Git 配置
    if [ -f "$GIT_CONFIG_SYSTEM" ]; then
        git config --system --unset http.proxy 2>/dev/null || true
        git config --system --unset https.proxy 2>/dev/null || true
        log_ok "Git 代理配置已移除"
    fi
    
    log_ok "卸载完成！用户需要重新登录才能完全生效"
}

# ==================== 状态检查 ====================
status() {
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}  Steam++ 系统代理状态${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
    
    # 检查 Steam++ 运行状态
    echo -e "${BLUE}[Steam++ 运行状态]${NC}"
    if check_steamp_running; then
        echo -e "  状态: ${GREEN}运行中${NC} (端口 $PROXY_HTTP_PORT)"
    else
        echo -e "  状态: ${RED}未运行${NC}"
        log_warn "Steam++ 未运行，代理配置不会生效"
    fi
    echo ""
    
    # 检查证书
    echo -e "${BLUE}[系统证书状态]${NC}"
    local cert_found=0
    if [ -f "/usr/local/share/ca-certificates/${STEAMPP_CERT_NAME}.crt" ]; then
        echo -e "  Debian/Ubuntu CA: ${GREEN}已导入${NC}"
        cert_found=1
    fi
    if [ -f "/etc/pki/ca-trust/source/anchors/${STEAMPP_CERT_NAME}.crt" ]; then
        echo -e "  RHEL/CentOS CA: ${GREEN}已导入${NC}"
        cert_found=1
    fi
    if [ "$cert_found" -eq 0 ]; then
        echo -e "  状态: ${RED}未导入${NC}"
    fi
    echo ""
    
    # 检查环境变量配置
    echo -e "${BLUE}[代理环境变量]${NC}"
    if [ -f "$PROFILE_FILE" ]; then
        echo -e "  配置文件: ${GREEN}存在${NC} ($PROFILE_FILE)"
    else
        echo -e "  配置文件: ${RED}不存在${NC}"
    fi
    echo ""
    
    # 检查当前会话的代理变量
    echo -e "${BLUE}[当前会话代理设置]${NC}"
    echo "  HTTP_PROXY:  ${HTTP_PROXY:-'(未设置)'}"
    echo "  HTTPS_PROXY: ${HTTPS_PROXY:-'(未设置)'}"
    echo "  ALL_PROXY:   ${ALL_PROXY:-'(未设置)'}"
    echo ""
    
    # Git 配置
    echo -e "${BLUE}[Git 代理配置]${NC}"
    local git_http=$(git config --system http.proxy 2>/dev/null || echo '(未设置)')
    local git_https=$(git config --system https.proxy 2>/dev/null || echo '(未设置)')
    echo "  http.proxy:  $git_http"
    echo "  https.proxy: $git_https"
    echo ""
    
    # 测试 GitHub 连通性
    echo -e "${BLUE}[连通性测试]${NC}"
    if curl -sI --max-time 5 https://github.com >/dev/null 2>&1; then
        echo -e "  GitHub HTTPS: ${GREEN}正常${NC}"
    else
        echo -e "  GitHub HTTPS: ${RED}失败${NC}"
    fi
    echo ""
}

# ==================== 测试功能 ====================
test_connectivity() {
    log_info "正在测试代理连通性..."
    echo ""
    
    # 测试 HTTP 代理端口
    echo -n "检测 Steam++ 代理端口 ($PROXY_HTTP_PORT): "
    if check_steamp_running; then
        echo -e "${GREEN}监听中${NC}"
    else
        echo -e "${RED}未监听${NC}"
        log_err "请先启动 Steam++ 再测试"
        return 1
    fi
    
    # 测试 GitHub 访问
    echo -n "测试 GitHub 访问 (curl): "
    if curl -sI --max-time 10 https://github.com >/dev/null 2>&1; then
        echo -e "${GREEN}成功${NC}"
    else
        echo -e "${RED}失败${NC}"
    fi
    
    # 测试 Git 访问
    echo -n "测试 GitHub 访问 (git): "
    if git ls-remote --heads https://github.com/git/git.git >/dev/null 2>&1; then
        echo -e "${GREEN}成功${NC}"
    else
        echo -e "${RED}失败${NC}"
    fi
    
    echo ""
}

# ==================== 主程序 ====================
main() {
    local command="${1:-}"
    
    # 显示标题
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}  Steam++ Linux 系统代理配置工具 v${SCRIPT_VERSION}${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
    
    # 处理命令
    case "$command" in
        uninstall|remove|delete)
            check_root
            uninstall
            ;;
        status|check|info)
            status
            ;;
        test)
            test_connectivity
            ;;
        install|""|*)
            if [ -n "$command" ] && [ "$command" != "install" ]; then
                log_err "未知命令: $command"
                echo ""
                echo "用法: sudo bash $0 [install|uninstall|status|test]"
                exit 1
            fi
            
            check_root
            
            # 显示系统信息
            log_info "发行版: $(detect_distro)"
            log_info "包管理器: $(get_pkg_manager)"
            
            # 检查 Steam++ 是否运行
            if ! check_steamp_running; then
                log_warn "Steam++ 似乎没有在运行 (端口 $PROXY_HTTP_PORT 未监听)"
                echo ""
                read -rp "是否继续配置? [y/N]: " confirm
                if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                    log_info "已取消"
                    exit 0
                fi
            else
                log_ok "Steam++ 正在运行"
            fi
            
            echo ""
            log_info "开始安装系统代理配置..."
            echo ""
            
            # 执行安装步骤
            install_cert || exit 1
            echo ""
            install_proxy_env
            echo ""
            install_git_config
            echo ""
            
            # 完成提示
            echo -e "${GREEN}========================================${NC}"
            echo -e "${GREEN}  安装完成！${NC}"
            echo -e "${GREEN}========================================${NC}"
            echo ""
            log_info "配置已应用到所有用户"
            log_info "用户需要重新登录或执行 'source /etc/profile' 生效"
            echo ""
            echo -e "${CYAN}常用命令:${NC}"
            echo "  source /etc/profile           # 当前会话立即生效"
            echo "  curl -I https://github.com    # 测试 HTTPS 连通性"
            echo "  git clone https://github.com/xxx/xxx.git  # 测试 Git"
            echo ""
            echo -e "${CYAN}管理脚本:${NC}"
            echo "  sudo bash $0 status           # 查看状态"
            echo "  sudo bash $0 test             # 连通性测试"
            echo "  sudo bash $0 uninstall        # 卸载配置"
            echo ""
            ;;
    esac
}

# 运行主程序
main "$@"
