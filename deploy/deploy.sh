#!/bin/bash
################################################################################
# 应用部署脚本
# 功能：下载新版本、备份旧版本、更新应用、重启服务
# 用法：./deploy.sh <version> [environment]
################################################################################

set -e

# 配置
APP_NAME="simple-go-app"
GITHUB_REPO="flywheel-research/simple-go-app"
INSTALL_DIR="/opt/${APP_NAME}"
BACKUP_DIR="/opt/${APP_NAME}/backup"
VERSIONS_DIR="/opt/${APP_NAME}/versions"
CONFIG_FILE="/opt/${APP_NAME}/config.json"
MAX_BACKUPS=5

# 代理配置（可选）
# 支持通过环境变量或配置文件设置代理
# 环境变量优先级高于配置文件
HTTP_PROXY="${HTTP_PROXY:-}"
HTTPS_PROXY="${HTTPS_PROXY:-}"

# 从配置文件读取代理设置（如果环境变量未设置）
if [ -z "${HTTP_PROXY}" ] && [ -f "${CONFIG_FILE}" ]; then
    HTTP_PROXY=$(grep -oP '"http_proxy":\s*"\K[^"]+' "${CONFIG_FILE}" 2>/dev/null || echo "")
fi
if [ -z "${HTTPS_PROXY}" ] && [ -f "${CONFIG_FILE}" ]; then
    HTTPS_PROXY=$(grep -oP '"https_proxy":\s*"\K[^"]+' "${CONFIG_FILE}" 2>/dev/null || echo "")
fi

# 构建 curl 代理参数
CURL_PROXY_ARGS=""
if [ -n "${HTTP_PROXY}" ]; then
    CURL_PROXY_ARGS="${CURL_PROXY_ARGS} --proxy ${HTTP_PROXY}"
fi
if [ -n "${HTTPS_PROXY}" ] && [ -z "${HTTP_PROXY}" ]; then
    CURL_PROXY_ARGS="${CURL_PROXY_ARGS} --proxy ${HTTPS_PROXY}"
fi

# 下载超时和重试配置
DOWNLOAD_TIMEOUT=600  # 10分钟
DOWNLOAD_RETRIES=3    # 重试3次

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

# 检查参数
if [ $# -lt 1 ]; then
    log_error "Usage: $0 <version> [environment]"
    echo "Example: $0 v1.0.0 prod"
    exit 1
fi

VERSION=$1
ENVIRONMENT=${2:-prod}

log_info "========================================="
log_info "  部署 ${APP_NAME} ${VERSION}"
log_info "  环境: ${ENVIRONMENT}"
if [ -n "${CURL_PROXY_ARGS}" ]; then
    log_info "  代理: ${HTTPS_PROXY:-${HTTP_PROXY}}"
fi
log_info "========================================="

# 创建必要的目录
log_info "创建目录结构..."
sudo mkdir -p ${INSTALL_DIR}
sudo mkdir -p ${BACKUP_DIR}
sudo mkdir -p ${VERSIONS_DIR}
sudo mkdir -p $(dirname ${CONFIG_FILE})

# 下载新版本
log_info "下载版本 ${VERSION}..."
BINARY_URL="https://github.com/${GITHUB_REPO}/releases/download/${VERSION}/${APP_NAME}-linux-amd64"
DOWNLOAD_PATH="${VERSIONS_DIR}/${APP_NAME}-${VERSION}"

if [ -f "${DOWNLOAD_PATH}" ]; then
    log_warning "版本 ${VERSION} 已存在，跳过下载"
else
    # 使用重试机制下载
    DOWNLOAD_SUCCESS=0
    for i in $(seq 1 ${DOWNLOAD_RETRIES}); do
        log_info "下载尝试 ${i}/${DOWNLOAD_RETRIES}..."

        # 构建 curl 命令
        CURL_CMD="sudo curl -L --max-time ${DOWNLOAD_TIMEOUT} --connect-timeout 30"
        if [ -n "${CURL_PROXY_ARGS}" ]; then
            CURL_CMD="${CURL_CMD} ${CURL_PROXY_ARGS}"
        fi
        CURL_CMD="${CURL_CMD} -o \"${DOWNLOAD_PATH}\" \"${BINARY_URL}\""

        # 执行下载
        if eval ${CURL_CMD}; then
            DOWNLOAD_SUCCESS=1
            break
        else
            log_warning "下载失败，等待 5 秒后重试..."
            sleep 5
        fi
    done

    if [ ${DOWNLOAD_SUCCESS} -eq 0 ]; then
        log_error "下载失败（已重试 ${DOWNLOAD_RETRIES} 次）: ${BINARY_URL}"
        log_error "请检查："
        log_error "  1. 网络连接是否正常"
        log_error "  2. 代理配置是否正确（如需要）"
        log_error "  3. GitHub Release 是否存在"
        exit 1
    fi

    sudo chmod +x "${DOWNLOAD_PATH}"
    log_success "下载完成"
fi

# 验证二进制文件
log_info "验证二进制文件..."
if ! sudo "${DOWNLOAD_PATH}" --version 2>/dev/null | grep -q "${VERSION#v}"; then
    log_warning "无法验证版本信息（可能是新版本没有 --version 参数）"
fi

# 备份当前版本
if [ -f "${INSTALL_DIR}/${APP_NAME}" ]; then
    log_info "备份当前版本..."
    CURRENT_VERSION=$(sudo "${INSTALL_DIR}/${APP_NAME}" --version 2>/dev/null | grep -oP 'v\d+\.\d+\.\d+' || echo "unknown")
    BACKUP_FILE="${BACKUP_DIR}/${APP_NAME}-${CURRENT_VERSION}-$(date +%Y%m%d_%H%M%S)"
    sudo cp "${INSTALL_DIR}/${APP_NAME}" "${BACKUP_FILE}"
    log_success "备份完成: ${BACKUP_FILE}"

    # 记录当前版本
    echo "${CURRENT_VERSION}" | sudo tee "${INSTALL_DIR}/.previous_version" > /dev/null
fi

# 清理旧备份（保留最近 N 个）
log_info "清理旧备份（保留最近 ${MAX_BACKUPS} 个）..."
BACKUP_COUNT=$(sudo ls -1 ${BACKUP_DIR}/${APP_NAME}-* 2>/dev/null | wc -l)
if [ ${BACKUP_COUNT} -gt ${MAX_BACKUPS} ]; then
    sudo ls -1t ${BACKUP_DIR}/${APP_NAME}-* | tail -n +$((MAX_BACKUPS + 1)) | sudo xargs rm -f
    log_success "清理完成"
fi

# 检查是否使用 supervisor 管理服务
USE_SUPERVISOR=false
if command -v supervisorctl &>/dev/null && [ -d /etc/supervisor/conf.d ]; then
    USE_SUPERVISOR=true
fi

# 停止服务
log_info "停止服务..."
if [ "${USE_SUPERVISOR}" = true ]; then
    if sudo supervisorctl status ${APP_NAME} &>/dev/null; then
        sudo supervisorctl stop ${APP_NAME}
        log_success "服务已停止"
    else
        log_warning "服务未在 supervisor 中运行"
    fi
else
    # 尝试通过进程名停止服务
    if pgrep -f "${INSTALL_DIR}/${APP_NAME}" &>/dev/null; then
        log_warning "检测到运行中的进程，请手动停止服务"
        log_warning "运行: pkill -f ${INSTALL_DIR}/${APP_NAME}"
    fi
fi

# 部署新版本
log_info "部署新版本..."
sudo cp "${DOWNLOAD_PATH}" "${INSTALL_DIR}/${APP_NAME}"
sudo chmod +x "${INSTALL_DIR}/${APP_NAME}"
echo "${VERSION}" | sudo tee "${INSTALL_DIR}/.current_version" > /dev/null
log_success "部署完成"

# 配置 supervisor（如果可用）
if [ "${USE_SUPERVISOR}" = true ]; then
    log_info "配置 supervisor..."
    SUPERVISOR_CONF="/etc/supervisor/conf.d/${APP_NAME}.conf"
    sudo tee ${SUPERVISOR_CONF} > /dev/null <<EOF
[program:${APP_NAME}]
command=${INSTALL_DIR}/${APP_NAME}
directory=${INSTALL_DIR}
user=ecs-user
autostart=true
autorestart=true
redirect_stderr=true
stdout_logfile=/var/log/${APP_NAME}.log
stderr_logfile=/var/log/${APP_NAME}.log
environment=PORT="8080",ENV="${ENVIRONMENT}"
EOF

    # 重载 supervisor 配置
    sudo supervisorctl reread
    sudo supervisorctl update
    log_success "Supervisor 配置完成"

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
    if [ "${DEPLOYED_VERSION}" = "${VERSION#v}" ]; then
        log_success "✓ 版本验证通过: ${DEPLOYED_VERSION}"
    else
        log_warning "⚠ 版本不匹配: 期望 ${VERSION#v}, 实际 ${DEPLOYED_VERSION}"
    fi
else
    # Supervisor 不可用，提供手动启动说明
    log_warning "Supervisor 未安装或未配置"
    log_info "部署已完成，但服务未自动启动"
    log_info "手动启动服务："
    log_info "  ${INSTALL_DIR}/${APP_NAME} &"
    log_info ""
    log_info "或者安装 supervisor 实现自动管理："
    log_info "  yum install -y supervisor  # RHEL/CentOS"
    log_info "  apt install -y supervisor  # Debian/Ubuntu"
fi

echo ""
log_success "========================================="
log_success "  部署完成！"
log_success "========================================="
echo ""
echo "应用信息:"
echo "  - 版本: ${VERSION}"
echo "  - 安装目录: ${INSTALL_DIR}"
echo "  - 日志文件: /var/log/${APP_NAME}.log"
echo ""
echo "常用命令:"
echo "  - 查看状态: sudo supervisorctl status ${APP_NAME}"
echo "  - 查看日志: sudo tail -f /var/log/${APP_NAME}.log"
echo "  - 重启服务: sudo supervisorctl restart ${APP_NAME}"
echo "  - 回滚版本: ./rollback.sh"
echo ""
