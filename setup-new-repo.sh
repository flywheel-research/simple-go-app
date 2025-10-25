#!/bin/bash
################################################################################
# 设置独立 Git 仓库脚本
# 直接在当前目录初始化并推送到新仓库
################################################################################

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置
CURRENT_DIR="$(pwd)"
REPO_URL="git@github.com:flywheel-research/simple-go-app.git"

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

log_step() {
    echo -e "${BLUE}==>${NC} $1"
}

# 检查 GitHub 连接
check_github_connection() {
    log_step "检查 GitHub SSH 连接..."
    if ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
        log_info "✅ GitHub SSH 连接正常"
        return 0
    else
        log_error "❌ GitHub SSH 连接失败"
        log_warn "请确保："
        echo "  1. SSH key 已添加到 GitHub"
        echo "  2. 运行: ssh-keygen -t rsa -b 4096 -C 'your_email@example.com'"
        echo "  3. 添加 key: cat ~/.ssh/id_rsa.pub"
        echo "  4. 访问: https://github.com/settings/keys"
        return 1
    fi
}

# 主函数
main() {
    echo ""
    log_info "=========================================="
    log_info "设置独立 Git 仓库"
    log_info "=========================================="
    echo ""

    # 检查当前目录
    log_step "当前目录: $CURRENT_DIR"

    # 检查 GitHub 连接
    if ! check_github_connection; then
        log_error "请先配置 GitHub SSH 连接"
        exit 1
    fi

    # 检查是否已经是 git 仓库
    if [ -d ".git" ]; then
        log_warn "当前目录已是 git 仓库"
        log_warn "是否要删除现有 git 历史并重新初始化? (y/n)"
        read -p "> " -n 1 -r
        echo ""

        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "取消操作"
            exit 0
        fi

        log_step "删除现有 git 历史..."
        rm -rf .git
        log_info "✅ 已清理 git 历史"
    fi

    # 初始化新仓库
    log_step "初始化新 Git 仓库..."
    git init
    log_info "✅ Git 仓库已初始化"

    # 添加所有文件
    log_step "添加文件到 Git..."
    git add .
    log_info "✅ 已添加所有文件"

    # 创建初始提交
    log_step "创建初始提交..."
    git commit -m "Initial commit: Complete CI/CD example with webhook deployment

Features:
- ✅ GitHub Actions CI/CD pipeline
- ✅ Multi-platform builds (Linux AMD64/ARM64)
- ✅ Webhook-based auto deployment (Python3)
- ✅ Deployment scripts (deploy, rollback, canary)
- ✅ Version management (keep last 5 versions)
- ✅ Health checks and monitoring
- ✅ Supervisor process management
- ✅ Complete documentation

Documentation:
- README.md: Complete guide
- QUICK_START.md: 10-minute quickstart
- WEBHOOK_SETUP.md: Webhook deployment guide
- AUTO_DEPLOY_GUIDE.md: Deployment methods comparison

Repository: $REPO_URL
"
    log_info "✅ 初始提交已创建"

    # 设置分支和 remote
    log_step "设置 main 分支和 remote..."
    git branch -M main
    git remote add origin "$REPO_URL"
    log_info "✅ Remote 已设置: $REPO_URL"

    # 显示状态
    echo ""
    log_info "=========================================="
    log_info "准备完成！"
    log_info "=========================================="
    echo ""

    log_info "📁 工作目录: $CURRENT_DIR"
    log_info "🌐 远程仓库: $REPO_URL"
    echo ""

    log_step "Git 状态："
    git log --oneline -1
    echo ""
    git remote -v
    echo ""

    # 询问是否立即推送
    log_warn "是否立即推送到 GitHub? (y/n)"
    read -p "> " -n 1 -r
    echo ""

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_step "推送到 GitHub..."

        if git push -u origin main; then
            echo ""
            log_info "=========================================="
            log_info "✅ 推送成功！"
            log_info "=========================================="
            echo ""
            log_info "仓库地址: https://github.com/flywheel-research/simple-go-app"
            echo ""

            log_step "后续步骤："
            echo ""
            echo "1️⃣  配置 GitHub Webhook (可选)"
            echo "   Settings → Webhooks → Add webhook"
            echo "   URL: http://your-server:9666/webhook"
            echo "   Secret: (webhook secret)"
            echo "   Events: Releases"
            echo ""
            echo "2️⃣  测试 CI/CD"
            echo "   git tag v1.0.0"
            echo "   git push origin v1.0.0"
            echo ""
            echo "3️⃣  查看 GitHub Actions"
            echo "   https://github.com/flywheel-research/simple-go-app/actions"
            echo ""

        else
            log_error "推送失败"
            log_warn "请检查："
            echo "  1. GitHub 上是否已创建仓库: simple-go-app"
            echo "  2. 是否有推送权限"
            echo ""
            log_info "可以手动推送："
            echo "  git push -u origin main"
        fi
    else
        echo ""
        log_info "跳过推送"
        log_info "后续可以手动推送："
        echo ""
        echo "  git push -u origin main"
        echo ""
    fi
}

# 运行主函数
main "$@"
