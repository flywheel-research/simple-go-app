# 自动部署方案指南

## 问题

**GitHub Actions 构建完成后，如何自动传到 deploy-agent 服务器？**

---

## 方案对比

### 方案 1：GitHub Webhook + Agent 监听 ⭐⭐⭐ 强烈推荐

**原理：** deploy-agent 监听 GitHub webhook，收到通知后自动拉取部署

**优点：**
- ✅ **最安全**（服务器主动拉取，无需暴露 SSH）
- ✅ **实时性好**（秒级响应）
- ✅ **易于维护**（Python3 实现，代码简单）
- ✅ **易于扩展**（支持多服务器）
- ✅ **HMAC 签名验证**（防止伪造请求）

**缺点：**
- ⚠️ 需要服务器可接收外网请求（可通过反向代理或 VPN 解决）

**适用场景：**
- 中大规模部署（10+ 台服务器）
- 安全要求高的生产环境
- 需要自动化部署的场景

**安全性说明：**
- SSH 方式需要在 GitHub 存储私钥（风险较高）
- Webhook 方式只需配置 Secret，服务器主动拉取（更安全）
- 支持 HMAC-SHA256 签名验证，防止伪造请求

---

### 方案 2：GitHub Actions + SSH 直接部署

**原理：** GitHub Actions 通过 SSH 直接连接服务器执行部署脚本

**优点：**
- ✅ 简单直接
- ✅ 实时部署
- ✅ 无需额外服务

**缺点：**
- ❌ **需要在 GitHub 配置 SSH 私钥**（安全风险）
- ❌ 服务器需要开放 SSH 端口
- ❌ 批量部署性能一般

**适用场景：** 小规模部署（1-5 台服务器），快速原型

---

### 方案 3：服务器轮询 GitHub Release

**原理：** deploy-agent 定期检查 GitHub Release，发现新版本自动部署

**优点：**
- ✅ 最安全（无需开放端口）
- ✅ 实现简单
- ✅ 无需 webhook

**缺点：**
- ❌ 延迟较大（取决于轮询间隔）
- ❌ API 调用频繁

**适用场景：** 安全要求高，对实时性要求不高

---

### 方案 4：通过 JumpServer API 批量部署

**原理：** GitHub Actions 调用 JumpServer API 批量执行部署命令

**优点：**
- ✅ 统一权限管理
- ✅ 支持批量操作
- ✅ 审计日志完整

**缺点：**
- ❌ 依赖 JumpServer
- ❌ API 调用复杂

**适用场景：** 已有 JumpServer 基础设施

---

### 方案 5：使用 CD 平台（ArgoCD/Spinnaker）

**原理：** 使用专业的 CD 平台管理部署

**优点：**
- ✅ 功能强大
- ✅ 可视化界面
- ✅ 完整的部署流程管理

**缺点：**
- ❌ 学习成本高
- ❌ 基础设施复杂

**适用场景：** 大规模企业级部署

---

## 方案 1 详解：GitHub Actions + SSH

### 架构图

```
GitHub Actions
    ↓
构建二进制文件
    ↓
创建 GitHub Release
    ↓
SSH 连接服务器 1 ─┐
SSH 连接服务器 2 ─┼─→ 并行执行
SSH 连接服务器 3 ─┘
    ↓
执行部署脚本
    ↓
验证部署成功
```

### 实现步骤

#### 1. 配置 GitHub Secrets

在 GitHub 仓库设置中添加：

```
Settings → Secrets and variables → Actions → New repository secret

SSH_PRIVATE_KEY    # SSH 私钥
SSH_KNOWN_HOSTS    # SSH known_hosts
DEPLOY_SERVERS     # 服务器列表（JSON 格式）
```

**DEPLOY_SERVERS 格式：**
```json
[
  {
    "name": "prod-01",
    "host": "192.168.1.101",
    "user": "ecs-user",
    "environment": "production"
  },
  {
    "name": "prod-02",
    "host": "192.168.1.102",
    "user": "ecs-user",
    "environment": "production"
  }
]
```

#### 2. GitHub Actions 配置

```yaml
# .github/workflows/release-and-deploy.yml
name: Release and Deploy

on:
  push:
    tags:
      - 'v*'

jobs:
  build:
    name: Build and Release
    runs-on: ubuntu-latest
    outputs:
      version: ${{ steps.version.outputs.version }}

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up Go
        uses: actions/setup-go@v4
        with:
          go-version: '1.21'

      - name: Get version
        id: version
        run: |
          VERSION=${GITHUB_REF#refs/tags/}
          echo "version=$VERSION" >> $GITHUB_OUTPUT

      - name: Build
        run: |
          GOOS=linux GOARCH=amd64 go build \
            -ldflags="-s -w -X main.Version=${{ steps.version.outputs.version }}" \
            -o simple-go-app-linux-amd64 .

      - name: Create Release
        id: create_release
        uses: actions/create-release@v1
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        with:
          tag_name: ${{ steps.version.outputs.version }}
          release_name: Release ${{ steps.version.outputs.version }}
          draft: false
          prerelease: false

      - name: Upload Release Asset
        uses: actions/upload-release-asset@v1
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        with:
          upload_url: ${{ steps.create_release.outputs.upload_url }}
          asset_path: ./simple-go-app-linux-amd64
          asset_name: simple-go-app-linux-amd64
          asset_content_type: application/octet-stream

  deploy:
    name: Deploy to Servers
    needs: build
    runs-on: ubuntu-latest
    if: ${{ !contains(github.ref, '-dev') && !contains(github.ref, '-beta') }}

    steps:
      - name: Checkout deploy scripts
        uses: actions/checkout@v4

      - name: Setup SSH
        run: |
          mkdir -p ~/.ssh
          echo "${{ secrets.SSH_PRIVATE_KEY }}" > ~/.ssh/id_rsa
          chmod 600 ~/.ssh/id_rsa
          echo "${{ secrets.SSH_KNOWN_HOSTS }}" > ~/.ssh/known_hosts

      - name: Deploy to servers
        run: |
          VERSION="${{ needs.build.outputs.version }}"
          SERVERS='${{ secrets.DEPLOY_SERVERS }}'

          echo "Deploying version: $VERSION"
          echo "$SERVERS" | jq -c '.[]' | while read server; do
            NAME=$(echo $server | jq -r '.name')
            HOST=$(echo $server | jq -r '.host')
            USER=$(echo $server | jq -r '.user')
            ENV=$(echo $server | jq -r '.environment')

            echo "Deploying to $NAME ($HOST)..."

            # 上传部署脚本
            scp -o StrictHostKeyChecking=no \
                deploy/deploy.sh \
                ${USER}@${HOST}:/tmp/deploy.sh

            # 执行部署
            ssh -o StrictHostKeyChecking=no ${USER}@${HOST} \
                "chmod +x /tmp/deploy.sh && sudo /tmp/deploy.sh ${VERSION} ${ENV}"

            # 验证部署
            ssh -o StrictHostKeyChecking=no ${USER}@${HOST} \
                "curl -s http://localhost:8080/version | jq -r '.version'"

            echo "✅ $NAME deployed successfully"
          done

      - name: Notify deployment
        if: always()
        run: |
          # 发送通知（Slack/Email/etc）
          echo "Deployment completed: ${{ needs.build.outputs.version }}"
```

#### 3. 生成 SSH 密钥

```bash
# 1. 生成 SSH 密钥对（无密码）
ssh-keygen -t rsa -b 4096 -C "github-actions" -f ~/.ssh/github_actions_rsa -N ""

# 2. 复制公钥到服务器
ssh-copy-id -i ~/.ssh/github_actions_rsa.pub ecs-user@192.168.1.101
ssh-copy-id -i ~/.ssh/github_actions_rsa.pub ecs-user@192.168.1.102

# 3. 获取私钥内容（添加到 GitHub Secrets）
cat ~/.ssh/github_actions_rsa

# 4. 获取 known_hosts（添加到 GitHub Secrets）
ssh-keyscan 192.168.1.101 192.168.1.102 > ~/.ssh/known_hosts
cat ~/.ssh/known_hosts
```

---

## 方案 1 详解：Webhook + Agent 监听 (Python3 实现)

### 架构图

```
GitHub Release
    ↓
触发 Webhook
    ↓
Deploy Agent (Python3 HTTP Server)
    ↓
HMAC-SHA256 签名验证
    ↓
下载新版本 (从 GitHub Release)
    ↓
执行部署脚本
    ↓
健康检查 & 版本验证
```

### 为什么选择 Python3？

**优势：**
- ✅ **简单易维护**：代码少，逻辑清晰
- ✅ **无需编译**：直接部署，修改即生效
- ✅ **标准库强大**：HTTP Server、HMAC、JSON 都是内置的
- ✅ **调试方便**：可以直接修改代码测试
- ✅ **依赖少**：只需要 Python3，无需额外安装包

**对比 Go：**
- Go 需要编译，修改代码需要重新构建
- Python3 直接运行，适合这种简单的 webhook 服务

### 实现步骤

#### 1. Deploy Agent Webhook 接收器 (Python3)

**完整代码：** `webhook-server.py` (约 300 行，包含注释)

**核心功能代码示例：**

```python
#!/usr/bin/env python3
"""GitHub Release Webhook Server - Python3 实现"""

import os
import hmac
import hashlib
import json
import subprocess
from http.server import HTTPServer, BaseHTTPRequestHandler

# 配置
WEBHOOK_SECRET = os.getenv('WEBHOOK_SECRET', '')
DEPLOY_SCRIPT = os.getenv('DEPLOY_SCRIPT', '/opt/simple-go-app/deploy/deploy.sh')
ENVIRONMENT = os.getenv('ENVIRONMENT', 'prod')
PORT = int(os.getenv('PORT', '9000'))

def verify_signature(payload, signature):
    """验证 GitHub webhook 签名 (HMAC-SHA256)"""
    if not WEBHOOK_SECRET:
        return True  # 开发环境可以禁用验证

    # GitHub 使用 sha256=xxx 格式
    if signature.startswith('sha256='):
        signature = signature[7:]

    # 计算期望的签名
    mac = hmac.new(
        WEBHOOK_SECRET.encode('utf-8'),
        msg=payload,
        digestmod=hashlib.sha256
    )
    expected = mac.hexdigest()

    # 常量时间比较，防止时序攻击
    return hmac.compare_digest(signature, expected)

def deploy_new_version(version):
    """执行部署"""
    cmd = [DEPLOY_SCRIPT, version, ENVIRONMENT]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=600)

    if result.returncode == 0:
        print(f"✅ Deployment success: {version}")
        return True
    else:
        print(f"❌ Deployment failed: {result.stderr}")
        return False

class WebhookHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path == '/webhook':
            # 读取请求体
            content_length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(content_length)

            # 验证签名
            signature = self.headers.get('X-Hub-Signature-256', '')
            if not verify_signature(body, signature):
                self.send_error(401, "Invalid signature")
                return

            # 解析 JSON
            payload = json.loads(body)

            # 只处理 release published 事件
            if payload.get('action') == 'published':
                version = payload.get('release', {}).get('tag_name', '')

                # 忽略 draft 和 prerelease
                if not payload.get('release', {}).get('draft') and \
                   not payload.get('release', {}).get('prerelease'):

                    # 异步执行部署
                    import threading
                    threading.Thread(
                        target=deploy_new_version,
                        args=(version,)
                    ).start()

                    self.send_response(200)
                    self.end_headers()
                    self.wfile.write(f"Deployment triggered: {version}\n".encode())
                    return

            self.send_response(200)
            self.end_headers()

    def do_GET(self):
        if self.path == '/health':
            # 健康检查
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({
                'status': 'healthy',
                'service': 'webhook-server'
            }).encode())

if __name__ == '__main__':
    server = HTTPServer(('0.0.0.0', PORT), WebhookHandler)
    print(f"🚀 Webhook server listening on port {PORT}")
    server.serve_forever()
```

**完整代码已提供：** `webhook-server.py` (约 300 行)

**特性：**
- ✅ HMAC-SHA256 签名验证
- ✅ 部署队列（避免并发问题）
- ✅ 健康检查端点 `/health`
- ✅ 部署状态端点 `/status`
- ✅ 日志记录到文件和控制台
- ✅ 超时控制（10分钟）
- ✅ 错误处理和重试

#### 2. 快速部署 Webhook Server

**一键安装脚本：**

```bash
# 下载安装脚本
curl -sSL https://raw.githubusercontent.com/flywheel-research/simple-go-app/main/install-webhook-server.sh -o install-webhook-server.sh

# 执行安装（需要提供 webhook secret）
sudo bash install-webhook-server.sh

# 或者直接指定参数
sudo bash install-webhook-server.sh "your-webhook-secret" "prod" "9000"
```

**手动安装：**

```bash
# 1. 安装 Python3（如果未安装）
# CentOS/RHEL
sudo yum install -y python3

# Ubuntu/Debian
sudo apt-get update && sudo apt-get install -y python3

# 2. 下载 webhook-server.py
sudo mkdir -p /opt/simple-go-app
curl -sSL https://raw.githubusercontent.com/flywheel-research/simple-go-app/main/webhook-server.py \
    -o /opt/simple-go-app/webhook-server.py
chmod +x /opt/simple-go-app/webhook-server.py

# 3. 创建 systemd 服务
sudo tee /etc/systemd/system/webhook-server.service > /dev/null <<'EOF'
[Unit]
Description=GitHub Release Webhook Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/simple-go-app
ExecStart=/usr/bin/python3 /opt/simple-go-app/webhook-server.py

# 环境变量（修改为你的配置）
Environment="WEBHOOK_SECRET=your-secret-here-change-me"
Environment="DEPLOY_SCRIPT=/opt/simple-go-app/deploy/deploy.sh"
Environment="ENVIRONMENT=prod"
Environment="PORT=9000"

Restart=always
RestartSec=10

StandardOutput=journal
StandardError=journal
SyslogIdentifier=webhook-server

[Install]
WantedBy=multi-user.target
EOF

# 4. 启动服务
sudo systemctl daemon-reload
sudo systemctl enable webhook-server
sudo systemctl start webhook-server

# 5. 检查状态
sudo systemctl status webhook-server

# 6. 查看日志
sudo journalctl -u webhook-server -f
```

#### 3. 配置 GitHub Webhook

```
GitHub 仓库 → Settings → Webhooks → Add webhook

Payload URL: http://your-server-ip:9000/webhook
Content type: application/json
Secret: your-secret-here
Events: Releases only
Active: ✓
```

#### 4. 使用 Nginx 反向代理（可选）

```nginx
# /etc/nginx/sites-available/webhook
server {
    listen 80;
    server_name webhook.example.com;

    location /webhook {
        proxy_pass http://localhost:9000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
```

---

## 方案 3 详解：服务器轮询

### 实现步骤

#### 1. 轮询脚本

```bash
#!/bin/bash
# auto-update.sh - 定期检查并自动更新

APP_NAME="simple-go-app"
GITHUB_REPO="flywheel-research/simple-go-app"
CHECK_INTERVAL=300  # 5 分钟
CURRENT_VERSION_FILE="/opt/${APP_NAME}/.current_version"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

get_latest_release() {
    curl -s "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" \
        | jq -r '.tag_name'
}

get_current_version() {
    if [ -f "$CURRENT_VERSION_FILE" ]; then
        cat "$CURRENT_VERSION_FILE"
    else
        echo "unknown"
    fi
}

deploy_version() {
    local version=$1
    log "Deploying version: $version"

    /opt/${APP_NAME}/deploy/deploy.sh "$version" prod

    if [ $? -eq 0 ]; then
        log "✅ Deployment successful"
        return 0
    else
        log "❌ Deployment failed"
        return 1
    fi
}

main() {
    log "Starting auto-update service..."

    while true; do
        CURRENT_VERSION=$(get_current_version)
        LATEST_VERSION=$(get_latest_release)

        if [ -z "$LATEST_VERSION" ]; then
            log "Failed to fetch latest version"
        elif [ "$CURRENT_VERSION" != "$LATEST_VERSION" ]; then
            log "New version available: $LATEST_VERSION (current: $CURRENT_VERSION)"

            # 部署新版本
            if deploy_version "$LATEST_VERSION"; then
                log "Auto-update completed"
            else
                log "Auto-update failed"
            fi
        else
            log "Already on latest version: $CURRENT_VERSION"
        fi

        sleep $CHECK_INTERVAL
    done
}

main
```

#### 2. 创建 systemd 服务

```bash
sudo tee /etc/systemd/system/auto-update.service > /dev/null <<EOF
[Unit]
Description=Auto Update Service
After=network.target

[Service]
Type=simple
User=ecs-user
ExecStart=/opt/simple-go-app/auto-update.sh
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable auto-update
sudo systemctl start auto-update
```

---

## 推荐方案总结

### 小规模部署（1-10 台）
**推荐：方案 1（GitHub Actions + SSH）**
- 最简单
- 配置快速
- 维护成本低

### 中等规模（10-50 台）
**推荐：方案 2（Webhook + Agent）**
- 安全性好
- 实时性高
- 易于监控

### 大规模部署（50+ 台）
**推荐：方案 4（JumpServer API）或方案 5（CD 平台）**
- 统一管理
- 批量操作
- 审计完整

### 高安全要求
**推荐：方案 3（服务器轮询）**
- 无需开放端口
- 服务器主动拉取
- 最安全

---

## 实战演练

### 场景 1：首次配置（方案 1）

```bash
# 1. 生成 SSH 密钥
ssh-keygen -t rsa -b 4096 -f ~/.ssh/github_actions_rsa -N ""

# 2. 复制到服务器
ssh-copy-id -i ~/.ssh/github_actions_rsa.pub ecs-user@your-server

# 3. 添加 GitHub Secrets
# SSH_PRIVATE_KEY: 复制 ~/.ssh/github_actions_rsa
# SSH_KNOWN_HOSTS: ssh-keyscan your-server
# DEPLOY_SERVERS: JSON 配置

# 4. 更新 GitHub Actions 配置
# 使用上面的 release-and-deploy.yml

# 5. 测试
git tag v1.0.0
git push origin v1.0.0
# 等待自动部署完成
```

### 场景 2：配置 Webhook（方案 2）

```bash
# 1. 部署 webhook server
go build -o webhook-server webhook-server.go
sudo cp webhook-server /opt/simple-go-app/

# 2. 创建 systemd 服务
# 使用上面的配置

# 3. 配置 GitHub Webhook
# 在 GitHub 仓库设置中添加

# 4. 测试
curl -X POST http://your-server:9000/webhook \
  -H "Content-Type: application/json" \
  -d '{"action":"published","release":{"tag_name":"v1.0.0"}}'
```

---

## 监控和告警

### Webhook Server 监控

```bash
# 健康检查
curl http://localhost:9000/health

# 查看日志
sudo journalctl -u webhook-server -f

# 查看状态
sudo systemctl status webhook-server
```

### 部署状态监控

```bash
# 检查最新部署
cat /opt/simple-go-app/.current_version

# 查看部署日志
sudo tail -f /var/log/simple-go-app-deploy.log

# 验证版本
curl http://localhost:8080/version
```

---

## 常见问题

### Q1: SSH 连接超时？
```bash
# 检查网络
ping your-server

# 检查 SSH
ssh -v ecs-user@your-server

# 检查防火墙
sudo ufw status
```

### Q2: Webhook 未触发？
```bash
# 检查服务状态
sudo systemctl status webhook-server

# 查看日志
sudo journalctl -u webhook-server -n 50

# 测试 webhook
curl -X POST http://your-server:9000/webhook
```

### Q3: 部署失败如何回滚？
```bash
# 自动回滚（在部署脚本中添加）
if ! verify_deployment; then
    rollback
fi

# 手动回滚
./rollback.sh
```

---

## 下一步

1. 选择适合你的部署方案
2. 配置 GitHub Secrets 或 Webhook
3. 测试自动部署流程
4. 配置监控告警
5. 编写运维文档

---

**文档版本：** v1.0
**最后更新：** 2024-10-25
**维护者：** BTC Ops Team
