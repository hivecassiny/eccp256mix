#!/bin/bash

#######################################
# eccp256mix 服务安装管理脚本
# 用法: ./install.sh <下载链接>
#######################################

# 脚本版本号
APP_VERSION="v1.0.7"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 配置变量
PROGRAM_NAME="eccp256mix"
INSTALL_DIR="/opt/${PROGRAM_NAME}"
SERVICE_NAME="${PROGRAM_NAME}"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
DOWNLOAD_URL=""
TEMP_DIR="/tmp/${PROGRAM_NAME}_install"

# 打印带颜色的消息
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否为 root 用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "此脚本需要 root 权限运行"
        print_info "请使用 sudo ./install.sh <下载链接> 运行"
        exit 1
    fi
}

# 检查服务是否已安装
is_installed() {
    if [[ -d "$INSTALL_DIR" ]] && [[ -f "${INSTALL_DIR}/${PROGRAM_NAME}" ]]; then
        return 0
    else
        return 1
    fi
}

# 检查服务是否正在运行
is_running() {
    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# 下载并解压程序
download_and_extract() {
    local url="$1"
    
    if [[ -z "$url" ]]; then
        print_error "下载链接为空"
        return 1
    fi
    
    print_info "创建临时目录..."
    rm -rf "$TEMP_DIR"
    mkdir -p "$TEMP_DIR"
    
    local filename="package.tar.gz"
    local filepath="${TEMP_DIR}/${filename}"
    
    print_info "正在下载程序包..."
    print_info "下载链接: $url"
    
    # 使用 curl 或 wget 下载
    if command -v curl &> /dev/null; then
        curl -fSL -o "$filepath" "$url" --progress-bar
    elif command -v wget &> /dev/null; then
        wget -q --show-progress -O "$filepath" "$url"
    else
        print_error "未找到 curl 或 wget，请先安装"
        return 1
    fi
    
    if [[ $? -ne 0 ]] || [[ ! -f "$filepath" ]]; then
        print_error "下载失败"
        return 1
    fi
    
    print_success "下载完成"
    
    print_info "正在解压程序包..."
    tar -xzf "$filepath" -C "$TEMP_DIR"
    
    if [[ $? -ne 0 ]]; then
        print_error "解压失败"
        return 1
    fi
    
    print_success "解压完成"
    return 0
}

# 创建 systemd 服务文件
create_service_file() {
    print_info "创建 systemd 服务文件..."
    
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=${PROGRAM_NAME} Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}
ExecStart=${INSTALL_DIR}/${PROGRAM_NAME}
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    if [[ $? -eq 0 ]]; then
        print_success "服务文件创建成功"
        return 0
    else
        print_error "服务文件创建失败"
        return 1
    fi
}

# 安装程序
do_install() {
    echo ""
    print_info "============ 开始安装 ${PROGRAM_NAME} ============"
    
    if is_installed; then
        print_warning "程序已安装，如需重新安装请选择重新安装选项"
        return 1
    fi
    
    if [[ -z "$DOWNLOAD_URL" ]]; then
        print_error "未提供下载链接"
        print_info "请使用 ./install.sh <下载链接> 运行脚本"
        return 1
    fi
    
    # 下载并解压
    if ! download_and_extract "$DOWNLOAD_URL"; then
        print_error "下载或解压失败"
        rm -rf "$TEMP_DIR"
        return 1
    fi
    
    # 查找解压后的程序文件
    local program_file=$(find "$TEMP_DIR" -name "$PROGRAM_NAME" -type f | head -n 1)
    
    if [[ -z "$program_file" ]]; then
        print_error "未找到程序文件 ${PROGRAM_NAME}"
        rm -rf "$TEMP_DIR"
        return 1
    fi
    
    # 创建安装目录
    print_info "创建安装目录..."
    mkdir -p "$INSTALL_DIR"
    
    # 复制文件到安装目录
    print_info "复制文件到安装目录..."
    local source_dir=$(dirname "$program_file")
    cp -r "${source_dir}/"* "$INSTALL_DIR/"
    
    # 设置执行权限
    chmod +x "${INSTALL_DIR}/${PROGRAM_NAME}"
    
    # 创建服务文件
    if ! create_service_file; then
        rm -rf "$INSTALL_DIR"
        rm -rf "$TEMP_DIR"
        return 1
    fi
    
    # 重新加载 systemd
    print_info "重新加载 systemd 配置..."
    systemctl daemon-reload
    
    # 启用服务开机自启
    print_info "设置开机自启..."
    systemctl enable "$SERVICE_NAME" &>/dev/null
    
    # 启动服务
    print_info "启动服务..."
    systemctl start "$SERVICE_NAME"
    
    sleep 1
    
    if is_running; then
        print_success "服务启动成功"
    else
        print_warning "服务启动失败，请手动检查"
        print_info "使用 'journalctl -u ${SERVICE_NAME} -n 50' 查看日志"
    fi
    
    # 保存安装信息
    echo "INSTALL_TIME=$(date '+%Y-%m-%d %H:%M:%S')" > "${INSTALL_DIR}/.install_info"
    echo "DOWNLOAD_URL=${DOWNLOAD_URL}" >> "${INSTALL_DIR}/.install_info"
    echo "VERSION=1.0.0" >> "${INSTALL_DIR}/.install_info"
    
    # 清理临时文件
    rm -rf "$TEMP_DIR"
    
    print_success "============ 安装完成 ============"
    echo ""
    print_info "可以使用以下命令管理服务:"
    echo "  启动服务: systemctl start ${SERVICE_NAME}"
    echo "  停止服务: systemctl stop ${SERVICE_NAME}"
    echo "  查看状态: systemctl status ${SERVICE_NAME}"
    echo ""
    
    return 0
}

# 卸载程序
do_uninstall() {
    echo ""
    print_info "============ 开始卸载 ${PROGRAM_NAME} ============"
    
    if ! is_installed; then
        print_warning "程序未安装"
        return 1
    fi
    
    # 确认卸载
    echo -n -e "${YELLOW}确定要卸载 ${PROGRAM_NAME} 吗? (y/N): ${NC}"
    read -r confirm
    if [[ "$confirm" != "y" ]] && [[ "$confirm" != "Y" ]]; then
        print_info "已取消卸载"
        return 0
    fi
    
    # 停止服务
    if is_running; then
        print_info "停止服务..."
        systemctl stop "$SERVICE_NAME"
    fi
    
    # 禁用服务
    print_info "禁用服务..."
    systemctl disable "$SERVICE_NAME" &>/dev/null
    
    # 删除服务文件
    print_info "删除服务文件..."
    rm -f "$SERVICE_FILE"
    
    # 重新加载 systemd
    systemctl daemon-reload
    
    # 删除安装目录
    print_info "删除安装目录..."
    rm -rf "$INSTALL_DIR"
    
    print_success "============ 卸载完成 ============"
    return 0
}

# 重新安装程序
do_reinstall() {
    echo ""
    print_info "============ 开始重新安装 ${PROGRAM_NAME} ============"
    
    if is_installed; then
        # 停止服务
        if is_running; then
            print_info "停止服务..."
            systemctl stop "$SERVICE_NAME"
        fi
        
        # 禁用服务
        print_info "禁用服务..."
        systemctl disable "$SERVICE_NAME" &>/dev/null
        
        # 删除服务文件
        print_info "删除服务文件..."
        rm -f "$SERVICE_FILE"
        
        # 删除安装目录
        print_info "删除安装目录..."
        rm -rf "$INSTALL_DIR"
        
        # 重新加载 systemd
        systemctl daemon-reload
    fi
    
    # 执行安装
    do_install
}

# 启动服务
do_start() {
    echo ""
    if ! is_installed; then
        print_error "程序未安装，请先安装"
        return 1
    fi
    
    if is_running; then
        print_warning "服务已在运行中"
        return 0
    fi
    
    print_info "正在启动服务..."
    systemctl start "$SERVICE_NAME"
    
    sleep 1
    
    if is_running; then
        print_success "服务启动成功"
    else
        print_error "服务启动失败"
        print_info "请使用 'journalctl -u ${SERVICE_NAME} -n 50' 查看日志"
        return 1
    fi
}

# 停止服务
do_stop() {
    echo ""
    if ! is_installed; then
        print_error "程序未安装"
        return 1
    fi
    
    if ! is_running; then
        print_warning "服务未运行"
        return 0
    fi
    
    print_info "正在停止服务..."
    systemctl stop "$SERVICE_NAME"
    
    sleep 1
    
    if ! is_running; then
        print_success "服务已停止"
    else
        print_error "服务停止失败"
        return 1
    fi
}

# 重启服务
do_restart() {
    echo ""
    if ! is_installed; then
        print_error "程序未安装，请先安装"
        return 1
    fi
    
    print_info "正在重启服务..."
    systemctl restart "$SERVICE_NAME"
    
    sleep 1
    
    if is_running; then
        print_success "服务重启成功"
    else
        print_error "服务重启失败"
        print_info "请使用 'journalctl -u ${SERVICE_NAME} -n 50' 查看日志"
        return 1
    fi
}

# 查看服务状态
do_status() {
    echo ""
    if ! is_installed; then
        print_error "程序未安装"
        return 1
    fi
    
    print_info "============ 服务状态 ============"
    systemctl status "$SERVICE_NAME" --no-pager
    echo ""
}

# 查看安装信息
do_info() {
    echo ""
    print_info "============ 安装信息 ============"
    
    if ! is_installed; then
        print_warning "程序未安装"
        return 1
    fi
    
    echo -e "${CYAN}程序名称:${NC} ${PROGRAM_NAME}"
    echo -e "${CYAN}安装目录:${NC} ${INSTALL_DIR}"
    echo -e "${CYAN}服务文件:${NC} ${SERVICE_FILE}"
    
    if is_running; then
        echo -e "${CYAN}运行状态:${NC} ${GREEN}运行中${NC}"
    else
        echo -e "${CYAN}运行状态:${NC} ${RED}已停止${NC}"
    fi
    
    # 读取安装信息
    if [[ -f "${INSTALL_DIR}/.install_info" ]]; then
        echo ""
        echo -e "${CYAN}--- 安装详情 ---${NC}"
        while IFS='=' read -r key value; do
            case "$key" in
                INSTALL_TIME)
                    echo -e "${CYAN}安装时间:${NC} ${value}"
                    ;;
                DOWNLOAD_URL)
                    echo -e "${CYAN}下载链接:${NC} ${value}"
                    ;;
                VERSION)
                    echo -e "${CYAN}版本:${NC} ${value}"
                    ;;
            esac
        done < "${INSTALL_DIR}/.install_info"
    fi
    
    # 显示文件列表
    echo ""
    echo -e "${CYAN}--- 安装文件 ---${NC}"
    ls -lh "${INSTALL_DIR}/"
    
    echo ""
}

# 显示菜单
show_menu() {
    clear
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}      ${GREEN}${PROGRAM_NAME} 矿池高级混淆加密${NC}   ${YELLOW}${APP_VERSION}${NC}      ${CYAN}║${NC}"
    echo -e "${CYAN}╠════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}                                                ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}   ${YELLOW}1.${NC} 安装服务                               ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}   ${YELLOW}2.${NC} 卸载服务                               ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}   ${YELLOW}3.${NC} 重新安装                               ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}   ${YELLOW}4.${NC} 启动服务                               ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}   ${YELLOW}5.${NC} 停止服务                               ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}   ${YELLOW}6.${NC} 重启服务                               ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}   ${YELLOW}7.${NC} 查看服务状态                           ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}   ${YELLOW}8.${NC} 查看安装信息                           ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}   ${YELLOW}9.${NC} 退出                                   ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                                ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # 显示当前状态
    if is_installed; then
        if is_running; then
            echo -e "  当前状态: ${GREEN}● 已安装 - 运行中${NC}"
        else
            echo -e "  当前状态: ${YELLOW}● 已安装 - 已停止${NC}"
        fi
    else
        echo -e "  当前状态: ${RED}● 未安装${NC}"
    fi
    echo ""
}

# 等待用户按键
wait_for_key() {
    echo ""
    echo -n -e "${CYAN}按任意键继续...${NC}"
    read -r -n 1
}

# 主函数
main() {
    # 检查 root 权限
    check_root
    
    # 获取下载链接参数
    DOWNLOAD_URL="$1"
    
    if [[ -z "$DOWNLOAD_URL" ]]; then
        print_warning "未提供下载链接，安装功能将不可用"
        print_info "用法: $0 <下载链接>"
        echo ""
        sleep 2
    fi
    
    while true; do
        show_menu
        echo -n -e "${CYAN}请选择操作 [1-9]: ${NC}"
        read -r choice
        
        case "$choice" in
            1)
                do_install
                wait_for_key
                ;;
            2)
                do_uninstall
                wait_for_key
                ;;
            3)
                do_reinstall
                wait_for_key
                ;;
            4)
                do_start
                wait_for_key
                ;;
            5)
                do_stop
                wait_for_key
                ;;
            6)
                do_restart
                wait_for_key
                ;;
            7)
                do_status
                wait_for_key
                ;;
            8)
                do_info
                wait_for_key
                ;;
            9)
                echo ""
                print_info "感谢使用，再见！"
                echo ""
                exit 0
                ;;
            *)
                print_error "无效选项，请输入 1-9"
                sleep 1
                ;;
        esac
    done
}

# 运行主函数
main "$@"
