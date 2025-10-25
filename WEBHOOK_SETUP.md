# Webhook 自动部署设置指南

## 为什么选择 Webhook 方式？

### 与 SSH 方式对比

| 对比项 | Webhook 方式 | SSH 方式 |
|--------|--------------|----------|
| **安全性** | ✅ 更安全（服务器主动拉取） | ⚠️ 需要在 GitHub 存储 SSH 私钥 |
| **网络要求** | 需要服务器可接收外网请求 | 需要服务器开放 SSH 端口 |
| **实时性** | ✅ 秒级响应 | ✅ 秒级响应 |
| **维护难度** | ✅ Python3 代码，易维护 | 需要管理 SSH 密钥 |
| **扩展性** | ✅ 易于扩展到多服务器 | 需要逐一配置 SSH |
| **适用场景** | 10+ 台服务器 | 1-5 台服务器 |

**推荐：** 生产环境使用 Webhook 方式，更安全、更易维护

---

## 快速开始（5 分钟）

### 步骤 1：在服务器上安装 Webhook Server

```bash
# SSH 登录到服务器
ssh ecs-user@your-server-ip

# 下载并运行一键安装脚本
curl -sSL https://raw.githubusercontent.com/flywheel-research/simple-go-app/main/install-webhook-server.sh | sudo bash
```

脚本会提示输入 Webhook Secret，请**妥善保管**这个 secret！

### 步骤 2：配置 GitHub Webhook

1. 访问你的 GitHub 仓库
2. 点击 `Settings` → `Webhooks` → `Add webhook`
3. 配置如下：

   ```
   Payload URL: http://your-server-ip:9666/webhook
   Content type: application/json
   Secret: (刚才设置的 webhook secret)

   Which events: Let me select individual events
   ✓ Releases  (只勾选这一个)

   Active: ✓ (确保勾选)
   ```

4. 点击 `Add webhook`

### 步骤 3：测试部署

```bash
# 在本地创建并推送一个 tag
git tag v1.0.0
git push origin v1.0.0
```

GitHub Actions 会自动：
1. 构建二进制文件
2. 创建 GitHub Release
3. 触发 Webhook
4. 服务器自动部署

---

## 详细配置

### 1. 生成 Webhook Secret

**推荐方式：** 使用 openssl 生成强随机密码

```bash
# 生成 32 字节的随机密码
openssl rand -hex 32
```

输出示例：`a8f5f167f44f4964e6c998dee827110c3f7c46f2b123456789abcdef01234567`

### 2. 安装 Webhook Server（手动安装）

如果一键脚本不适用，可以手动安装：

```bash
# 1. 安装 Python3
sudo yum install -y python3  # CentOS/RHEL
# 或
sudo apt-get install -y python3  # Ubuntu/Debian

# 2. 创建目录
sudo mkdir -p /opt/simple-go-app/deploy

# 3. 下载 webhook server
sudo curl -sSL https://raw.githubusercontent.com/flywheel-research/simple-go-app/main/webhook-server.py \
    -o /opt/simple-go-app/webhook-server.py
sudo chmod +x /opt/simple-go-app/webhook-server.py

# 4. 下载部署脚本
sudo curl -sSL https://raw.githubusercontent.com/flywheel-research/simple-go-app/main/deploy/deploy.sh \
    -o /opt/simple-go-app/deploy/deploy.sh
sudo chmod +x /opt/simple-go-app/deploy/deploy.sh

# 5. 创建 systemd 服务
sudo tee /etc/systemd/system/webhook-server.service > /dev/null <<'EOF'
[Unit]
Description=GitHub Release Webhook Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/simple-go-app
ExecStart=/usr/bin/python3 /opt/simple-go-app/webhook-server.py

# 修改这里的配置
Environment="WEBHOOK_SECRET=your-secret-here"
Environment="DEPLOY_SCRIPT=/opt/simple-go-app/deploy/deploy.sh"
Environment="ENVIRONMENT=prod"
Environment="PORT=9666"

Restart=always
RestartSec=10

StandardOutput=journal
StandardError=journal
SyslogIdentifier=webhook-server

[Install]
WantedBy=multi-user.target
EOF

# 6. 启动服务
sudo systemctl daemon-reload
sudo systemctl enable webhook-server
sudo systemctl start webhook-server

# 7. 检查状态
sudo systemctl status webhook-server
```

### 3. 配置防火墙

**firewalld (CentOS/RHEL):**
```bash
sudo firewall-cmd --permanent --add-port=9000/tcp
sudo firewall-cmd --reload
```

**iptables:**
```bash
sudo iptables -A INPUT -p tcp --dport 9666 -j ACCEPT
sudo iptables-save
```

**AWS Security Group / 阿里云安全组：**
- 添加入站规则：TCP 9000 端口

### 4. 验证安装

```bash
# 健康检查
curl http://localhost:9666/health

# 应该返回：
# {
#   "status": "healthy",
#   "timestamp": "2024-10-25T10:00:00",
#   "queue_size": 0
# }
```

---

## GitHub Actions 配置

### 方式 1：自动触发 Webhook（推荐）

GitHub 会在 Release 创建时自动触发配置好的 Webhook，**无需在 Actions 中额外配置**。

你的 `.github/workflows/release.yml` 只需要：

```yaml
name: Release

on:
  push:
    tags:
      - 'v*'

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Go
        uses: actions/setup-go@v4
        with:
          go-version: '1.21'

      - name: Build
        run: |
          VERSION=${GITHUB_REF#refs/tags/}
          GOOS=linux GOARCH=amd64 go build \
            -ldflags="-s -w -X main.Version=${VERSION}" \
            -o simple-go-app-linux-amd64 .

      - name: Create Release
        uses: actions/create-release@v1
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        with:
          tag_name: ${{ github.ref_name }}
          release_name: Release ${{ github.ref_name }}

      - name: Upload Binary
        uses: actions/upload-release-asset@v1
        # ...
```

GitHub 会在 Release 创建后自动触发 Webhook → 服务器自动部署

### 方式 2：手动触发 Webhook（可选）

如果需要在 Actions 中手动触发 Webhook：

```yaml
      - name: Trigger Webhook
        run: |
          VERSION=${{ github.ref_name }}
          WEBHOOK_URL="http://your-server:9666/webhook"
          WEBHOOK_SECRET="${{ secrets.WEBHOOK_SECRET }}"

          PAYLOAD='{"action":"published","release":{"tag_name":"'$VERSION'"}}'
          SIGNATURE=$(echo -n "$PAYLOAD" | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | sed 's/^.* //')

          curl -X POST "$WEBHOOK_URL" \
            -H "Content-Type: application/json" \
            -H "X-GitHub-Event: release" \
            -H "X-Hub-Signature-256: sha256=$SIGNATURE" \
            -d "$PAYLOAD"
```

---

## 运维管理

### 查看日志

```bash
# 实时查看日志
sudo journalctl -u webhook-server -f

# 查看最近 100 行
sudo journalctl -u webhook-server -n 100

# 按时间查看
sudo journalctl -u webhook-server --since "1 hour ago"

# 查看部署日志
sudo tail -f /var/log/webhook-server.log
```

### 服务管理

```bash
# 查看状态
sudo systemctl status webhook-server

# 重启服务
sudo systemctl restart webhook-server

# 停止服务
sudo systemctl stop webhook-server

# 启动服务
sudo systemctl start webhook-server

# 禁用自动启动
sudo systemctl disable webhook-server

# 启用自动启动
sudo systemctl enable webhook-server
```

### 更新配置

修改环境变量后需要重启：

```bash
# 编辑配置
sudo vim /etc/systemd/system/webhook-server.service

# 重新加载并重启
sudo systemctl daemon-reload
sudo systemctl restart webhook-server
```

### 查看部署状态

```bash
# 查看当前部署状态
curl http://localhost:9666/status

# 返回示例：
# {
#   "version": "v1.0.0",
#   "status": "success",
#   "start_time": "2024-10-25T10:00:00",
#   "end_time": "2024-10-25T10:01:30"
# }
```

---

## 故障排查

### 问题 1：Webhook 接收失败

**症状：** GitHub Webhook 显示错误

**排查：**

```bash
# 1. 检查服务是否运行
sudo systemctl status webhook-server

# 2. 检查端口是否监听
sudo netstat -tlnp | grep 9000

# 3. 检查防火墙
sudo firewall-cmd --list-ports
# 或
sudo iptables -L -n | grep 9000

# 4. 测试本地连接
curl -X POST http://localhost:9666/webhook \
  -H "Content-Type: application/json" \
  -H "X-GitHub-Event: ping" \
  -d '{"zen":"test"}'
```

### 问题 2：签名验证失败

**症状：** 日志显示 "Invalid signature"

**原因：** GitHub 配置的 Secret 与服务器不一致

**解决：**

```bash
# 1. 检查服务器配置的 secret
sudo systemctl cat webhook-server | grep WEBHOOK_SECRET

# 2. 确保与 GitHub Webhook 配置一致
# GitHub: Settings → Webhooks → Edit → Secret

# 3. 如果不一致，更新配置
sudo vim /etc/systemd/system/webhook-server.service
# 修改 Environment="WEBHOOK_SECRET=xxx"

# 4. 重启服务
sudo systemctl daemon-reload
sudo systemctl restart webhook-server
```

### 问题 3：部署脚本执行失败

**症状：** Webhook 收到，但部署失败

**排查：**

```bash
# 1. 查看详细日志
sudo journalctl -u webhook-server -n 200 | grep -A 20 "Deployment failed"

# 2. 手动执行部署脚本测试
sudo /opt/simple-go-app/deploy/deploy.sh v1.0.0 prod

# 3. 检查部署脚本权限
ls -la /opt/simple-go-app/deploy/deploy.sh

# 4. 检查部署目录权限
ls -la /opt/simple-go-app/
```

### 问题 4：外网无法访问

**症状：** 本地 curl 成功，GitHub 触发失败

**排查：**

```bash
# 1. 检查服务监听地址
sudo netstat -tlnp | grep 9000
# 应该显示 0.0.0.0:9666 而不是 127.0.0.1:9666

# 2. 检查云服务器安全组
# AWS: Security Groups
# 阿里云: 安全组规则
# 腾讯云: 安全组

# 3. 测试外网连接
# 从另一台机器测试
curl -v http://your-server-public-ip:9666/health
```

---

## 安全加固

### 1. 使用 HTTPS（推荐）

通过 Nginx 反向代理提供 HTTPS：

```nginx
server {
    listen 443 ssl;
    server_name webhook.yourdomain.com;

    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;

    location /webhook {
        proxy_pass http://127.0.0.1:9666;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

GitHub Webhook URL 改为：`https://webhook.yourdomain.com/webhook`

### 2. IP 白名单

限制只允许 GitHub 的 IP 访问：

```bash
# GitHub Webhook IP 段（需要定期更新）
# https://api.github.com/meta

sudo iptables -A INPUT -p tcp --dport 9666 -s 140.82.112.0/20 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 9666 -s 143.55.64.0/20 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 9666 -j DROP
```

### 3. 强化 Secret

```bash
# 使用强随机密码（至少 32 字节）
openssl rand -hex 32

# 定期轮换 Secret（建议每 3-6 个月）
```

---

## 多服务器部署

### 方式 1：每台服务器独立部署

每台服务器都运行 webhook-server，GitHub 配置多个 Webhook：

```
GitHub Webhook 1 → Server 1 (192.168.1.101:9666)
GitHub Webhook 2 → Server 2 (192.168.1.102:9666)
GitHub Webhook 3 → Server 3 (192.168.1.103:9666)
```

### 方式 2：中心化 Webhook + 远程部署

一台服务器接收 Webhook，通过 SSH 部署到其他服务器：

```
GitHub Webhook → Master Server → SSH deploy to:
                                  - Server 1
                                  - Server 2
                                  - Server 3
```

修改 `deploy.sh`：
```bash
# 部署到远程服务器列表
SERVERS=("192.168.1.101" "192.168.1.102" "192.168.1.103")

for server in "${SERVERS[@]}"; do
    ssh ecs-user@$server "curl -sSL ... | sudo bash -s $VERSION $ENV"
done
```

---

## 监控告警

### Prometheus 监控

```python
# 在 webhook-server.py 中添加 metrics endpoint
from prometheus_client import Counter, Histogram, generate_latest

deployment_counter = Counter('deployments_total', 'Total deployments')
deployment_duration = Histogram('deployment_duration_seconds', 'Deployment duration')

# /metrics endpoint
def handle_metrics(self):
    self.send_response(200)
    self.send_header('Content-Type', 'text/plain')
    self.end_headers()
    self.wfile.write(generate_latest())
```

### 告警规则

```yaml
# Alertmanager rules
- alert: DeploymentFailed
  expr: rate(deployments_failed_total[5m]) > 0
  annotations:
    summary: "Deployment failed on {{ $labels.instance }}"
```

---

## 总结

✅ **优势总结：**
- 安全性高（服务器主动拉取，无需暴露 SSH）
- 实时性好（秒级响应）
- 易维护（Python3 代码简单）
- 易扩展（支持多服务器）

📚 **相关文档：**
- [完整 CI/CD 流程](./README.md)
- [部署方案对比](./AUTO_DEPLOY_GUIDE.md)
- [快速开始](./QUICK_START.md)

🆘 **需要帮助？**
- 查看日志：`sudo journalctl -u webhook-server -f`
- 测试连接：`curl http://localhost:9666/health`
- GitHub Issues: https://github.com/flywheel-research/simple-go-app/issues
