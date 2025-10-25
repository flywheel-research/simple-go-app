#!/bin/bash
################################################################################
# 应用回滚脚本
# 功能：回滚到上一个版本或指定版本
# 用法：./rollback.sh [version]
################################################################################

set -e

# 配置
APP_NAME="simple-go-app"
INSTALL_DIR="/opt/${APP_NAME}"
BACKUP_DIR="/opt/${APP_NAME}/backup"
VERSIONS_DIR="/opt/${APP_NAME}/versions"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_info "========================================="
log_info "  回滚 ${APP_NAME}"
log_info "========================================="

# 获取当前版本
CURRENT_VERSION=""
if [ -f "${INSTALL_DIR}/.current_version" ]; then
    CURRENT_VERSION=$(sudo cat "${INSTALL_DIR}/.current_version")
    log_info "当前版本: ${CURRENT_VERSION}"
fi

# 确定回滚目标版本
if [ $# -eq 1 ]; then
    # 指定版本回滚
    TARGET_VERSION=$1
    log_info "回滚到指定版本: ${TARGET_VERSION}"
else
    # 回滚到上一个版本
    if [ -f "${INSTALL_DIR}/.previous_version" ]; then
        TARGET_VERSION=$(sudo cat "${INSTALL_DIR}/.previous_version")
        log_info "回滚到上一个版本: ${TARGET_VERSION}"
    else
        log_error "未找到上一个版本信息"
        echo ""
        echo "可用的备份版本:"
        sudo ls -lh ${BACKUP_DIR}/
        echo ""
        echo "使用方法: $0 <version>"
        exit 1
    fi
fi

# 查找备份文件
BACKUP_FILE=""
if [ -n "${TARGET_VERSION}" ]; then
    # 在 backup 目录查找
    BACKUP_FILE=$(sudo ls -1t ${BACKUP_DIR}/${APP_NAME}-${TARGET_VERSION}* 2>/dev/null | head -n 1)
fi

if [ -z "${BACKUP_FILE}" ]; then
    # 在 versions 目录查找
    if [ -f "${VERSIONS_DIR}/${APP_NAME}-${TARGET_VERSION}" ]; then
        BACKUP_FILE="${VERSIONS_DIR}/${APP_NAME}-${TARGET_VERSION}"
    else
        log_error "未找到版本 ${TARGET_VERSION} 的备份"
        echo ""
        echo "可用的版本:"
        echo ""
        echo "备份目录:"
        sudo ls -1 ${BACKUP_DIR}/ 2>/dev/null || echo "  无备份"
        echo ""
        echo "版本目录:"
        sudo ls -1 ${VERSIONS_DIR}/ 2>/dev/null || echo "  无历史版本"
        exit 1
    fi
fi

log_success "找到备份: ${BACKUP_FILE}"

# 确认回滚
echo ""
log_warning "确认回滚操作？"
echo "  当前版本: ${CURRENT_VERSION}"
echo "  目标版本: ${TARGET_VERSION}"
echo "  备份文件: ${BACKUP_FILE}"
echo ""
read -p "继续? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    log_info "回滚已取消"
    exit 0
fi

# 停止服务
log_info "停止服务..."
sudo supervisorctl stop ${APP_NAME}
sleep 2
log_success "服务已停止"

# 回滚二进制文件
log_info "回滚二进制文件..."
sudo cp "${BACKUP_FILE}" "${INSTALL_DIR}/${APP_NAME}"
sudo chmod +x "${INSTALL_DIR}/${APP_NAME}"

# 更新版本信息
echo "${TARGET_VERSION}" | sudo tee "${INSTALL_DIR}/.current_version" > /dev/null
if [ -n "${CURRENT_VERSION}" ]; then
    echo "${CURRENT_VERSION}" | sudo tee "${INSTALL_DIR}/.previous_version" > /dev/null
fi

log_success "回滚完成"

# 启动服务
log_info "启动服务..."
sudo supervisorctl start ${APP_NAME}
sleep 3

# 验证服务状态
log_info "验证服务状态..."
if sudo supervisorctl status ${APP_NAME} | grep -q "RUNNING"; then
    log_success "✓ 服务运行正常"
else
    log_error "✗ 服务启动失败"
    sudo supervisorctl status ${APP_NAME}
    exit 1
fi

# 健康检查
log_info "健康检查..."
sleep 2
if curl -s http://localhost:8080/health | grep -q "healthy"; then
    log_success "✓ 健康检查通过"
else
    log_error "✗ 健康检查失败"
    exit 1
fi

# 版本验证
log_info "版本验证..."
DEPLOYED_VERSION=$(curl -s http://localhost:8080/version | jq -r '.version' 2>/dev/null || echo "unknown")
log_info "当前运行版本: ${DEPLOYED_VERSION}"

echo ""
log_success "========================================="
log_success "  回滚完成！"
log_success "========================================="
echo ""
echo "应用信息:"
echo "  - 版本: ${TARGET_VERSION}"
echo "  - 安装目录: ${INSTALL_DIR}"
echo "  - 日志文件: /var/log/${APP_NAME}.log"
echo ""
echo "常用命令:"
echo "  - 查看状态: sudo supervisorctl status ${APP_NAME}"
echo "  - 查看日志: sudo tail -f /var/log/${APP_NAME}.log"
echo ""
