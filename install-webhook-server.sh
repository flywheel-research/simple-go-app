#!/bin/bash
################################################################################
# Webhook Server 安装脚本
# 用途：在服务器上安装和配置 webhook server
################################################################################

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否以 root 运行
if [ "$EUID" -ne 0 ]; then
    log_error "Please run as root (use sudo)"
    exit 1
fi

# 配置变量
INSTALL_DIR="/opt/simple-go-app"
WEBHOOK_SECRET="${1:-}"
ENVIRONMENT="${2:-prod}"
PORT="${3:-9666}"

# 交互式获取 webhook secret
if [ -z "$WEBHOOK_SECRET" ]; then
    echo ""
    log_warn "Webhook secret is required for security!"
    read -p "Enter webhook secret (generate at GitHub repo Settings > Webhooks): " WEBHOOK_SECRET

    if [ -z "$WEBHOOK_SECRET" ]; then
        log_error "Webhook secret cannot be empty!"
        exit 1
    fi
fi

log_info "Installing webhook server..."
echo ""
log_info "Configuration:"
echo "  - Install Directory: $INSTALL_DIR"
echo "  - Environment: $ENVIRONMENT"
echo "  - Port: $PORT"
echo "  - Webhook Secret: ${WEBHOOK_SECRET:0:8}..."
echo ""

# 1. 检查 Python3
log_info "Checking Python3..."
if ! command -v python3 &> /dev/null; then
    log_error "Python3 is not installed!"
    log_info "Installing Python3..."

    if command -v yum &> /dev/null; then
        yum install -y python3 python3-pip
    elif command -v apt-get &> /dev/null; then
        apt-get update
        apt-get install -y python3 python3-pip
    else
        log_error "Unsupported package manager. Please install Python3 manually."
        exit 1
    fi
fi

PYTHON_VERSION=$(python3 --version)
log_info "✅ Python3 installed: $PYTHON_VERSION"

# 2. 创建安装目录
log_info "Creating installation directory..."
mkdir -p "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/deploy"
mkdir -p /var/log

# 3. 下载或复制 webhook server
log_info "Installing webhook-server.py..."

if [ -f "./webhook-server.py" ]; then
    # 从当前目录复制
    cp ./webhook-server.py "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/webhook-server.py"
    log_info "✅ Copied from current directory"
else
    # 从 GitHub 下载
    REPO="flywheel-research/simple-go-app"
    FILE_URL="https://raw.githubusercontent.com/$REPO/main/webhook-server.py"

    log_info "Downloading from GitHub..."
    if curl -sSL -o "$INSTALL_DIR/webhook-server.py" "$FILE_URL"; then
        chmod +x "$INSTALL_DIR/webhook-server.py"
        log_info "✅ Downloaded from GitHub"
    else
        log_error "Failed to download webhook-server.py"
        exit 1
    fi
fi

# 4. 创建 systemd service 文件
log_info "Creating systemd service..."

cat > /etc/systemd/system/webhook-server.service <<EOF
[Unit]
Description=GitHub Release Webhook Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/python3 $INSTALL_DIR/webhook-server.py

# 环境变量配置
Environment="WEBHOOK_SECRET=$WEBHOOK_SECRET"
Environment="DEPLOY_SCRIPT=$INSTALL_DIR/deploy/deploy.sh"
Environment="ENVIRONMENT=$ENVIRONMENT"
Environment="PORT=$PORT"

# 重启策略
Restart=always
RestartSec=10

# 日志
StandardOutput=journal
StandardError=journal
SyslogIdentifier=webhook-server

[Install]
WantedBy=multi-user.target
EOF

log_info "✅ Service file created: /etc/systemd/system/webhook-server.service"

# 5. 启动服务
log_info "Starting webhook server..."

systemctl daemon-reload
systemctl enable webhook-server
systemctl restart webhook-server

sleep 2

# 6. 检查服务状态
if systemctl is-active --quiet webhook-server; then
    log_info "✅ Webhook server is running!"

    echo ""
    log_info "Service status:"
    systemctl status webhook-server --no-pager | head -n 10

    echo ""
    log_info "Health check:"
    if curl -s http://localhost:$PORT/health | python3 -m json.tool; then
        log_info "✅ Health check passed!"
    else
        log_warn "Health check failed, but service is running"
    fi
else
    log_error "Webhook server failed to start!"
    log_info "Check logs with: journalctl -u webhook-server -f"
    exit 1
fi

# 7. 防火墙配置提示
echo ""
log_info "================================================"
log_info "Installation Complete!"
log_info "================================================"
echo ""
log_info "Next Steps:"
echo ""
echo "1. Configure GitHub Webhook:"
echo "   - Go to: https://github.com/YOUR_REPO/settings/hooks"
echo "   - Click 'Add webhook'"
echo "   - Payload URL: http://YOUR_SERVER_IP:$PORT/webhook"
echo "   - Content type: application/json"
echo "   - Secret: (the secret you just entered)"
echo "   - Events: Let me select individual events → Releases"
echo "   - Active: ✓"
echo ""
echo "2. Configure Firewall (if needed):"
echo "   # firewalld"
echo "   sudo firewall-cmd --permanent --add-port=$PORT/tcp"
echo "   sudo firewall-cmd --reload"
echo ""
echo "   # iptables"
echo "   sudo iptables -A INPUT -p tcp --dport $PORT -j ACCEPT"
echo ""
echo "3. Test webhook:"
echo "   curl -X POST http://localhost:$PORT/webhook \\"
echo "     -H 'Content-Type: application/json' \\"
echo "     -H 'X-GitHub-Event: ping' \\"
echo "     -d '{\"zen\":\"test\"}'"
echo ""
echo "4. View logs:"
echo "   sudo journalctl -u webhook-server -f"
echo ""
echo "5. Manage service:"
echo "   sudo systemctl status webhook-server   # 查看状态"
echo "   sudo systemctl restart webhook-server  # 重启"
echo "   sudo systemctl stop webhook-server     # 停止"
echo "   sudo systemctl start webhook-server    # 启动"
echo ""
log_info "================================================"
