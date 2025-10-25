# 启用自动部署（可选）

## 默认推荐方式：GitHub Webhook ⭐⭐⭐

**最简单、最安全的方式，无需修改 workflow！**

### 步骤：

1. **在服务器上安装 webhook server**
   ```bash
   curl -sSL https://raw.githubusercontent.com/flywheel-research/simple-go-app/main/install-webhook-server.sh | sudo bash
   ```

2. **在 GitHub 配置 Webhook**
   ```
   Repository → Settings → Webhooks → Add webhook

   Payload URL: http://your-server:9666/webhook
   Content type: application/json
   Secret: (安装时设置的密钥)
   Events: ✓ Releases only
   ```

3. **测试**
   ```bash
   git tag v1.0.0
   git push origin v1.0.0
   ```

完成！GitHub 会在创建 Release 后自动触发 Webhook，服务器自动部署。

详细文档：[WEBHOOK_SETUP.md](./WEBHOOK_SETUP.md)

---

## 可选方式 1：GitHub Actions SSH 部署

⚠️ **不推荐**：需要在 GitHub 存储 SSH 私钥，安全风险较高。

### 启用步骤：

#### 1. 生成 SSH 密钥

```bash
# 生成专用密钥对
ssh-keygen -t rsa -b 4096 -C "github-actions" -f ~/.ssh/github_actions_rsa -N ""

# 复制公钥到服务器
ssh-copy-id -i ~/.ssh/github_actions_rsa.pub ecs-user@your-server-ip

# 查看私钥（需要添加到 GitHub Secrets）
cat ~/.ssh/github_actions_rsa

# 生成 known_hosts（需要添加到 GitHub Secrets）
ssh-keyscan your-server-ip > ~/.ssh/known_hosts
cat ~/.ssh/known_hosts
```

#### 2. 配置 GitHub Secrets

访问：`Repository → Settings → Secrets and variables → Actions`

添加以下 Secrets：

```
SSH_PRIVATE_KEY = (上面生成的私钥内容)

SSH_KNOWN_HOSTS = (上面生成的 known_hosts 内容)

DEPLOY_SERVERS =
[
  {
    "name": "prod-server-01",
    "host": "192.168.1.101",
    "user": "ecs-user",
    "environment": "prod"
  },
  {
    "name": "prod-server-02",
    "host": "192.168.1.102",
    "user": "ecs-user",
    "environment": "prod"
  }
]
```

#### 3. 启用 workflow job

编辑 `.github/workflows/release-and-deploy.yml`，找到：

```yaml
  deploy-ssh:
    name: Deploy via SSH
    needs: build
    runs-on: ubuntu-latest
    if: |
      false &&                           # ← 删除这一行
      github.event_name == 'push' &&
      !contains(github.ref, '-dev') &&
      !contains(github.ref, '-beta')
```

改为：

```yaml
  deploy-ssh:
    name: Deploy via SSH
    needs: build
    runs-on: ubuntu-latest
    if: |
      github.event_name == 'push' &&
      !contains(github.ref, '-dev') &&
      !contains(github.ref, '-beta')
```

#### 4. 推送并测试

```bash
git add .github/workflows/release-and-deploy.yml
git commit -m "Enable SSH deployment"
git push

# 创建 release 测试
git tag v1.0.1
git push origin v1.0.1
```

---

## 可选方式 2：JumpServer API 部署

适用于已有 JumpServer 基础设施的环境。

### 启用步骤：

#### 1. 获取 JumpServer API Token

登录 JumpServer Web 界面：
```
用户 → API Key → 创建 Token
```

#### 2. 配置 GitHub Secrets

```
JUMPSERVER_URL = https://jumpserver.yourdomain.com

JUMPSERVER_TOKEN = (JumpServer API Token)

JUMPSERVER_HOSTS =
[
  "prod-server-01",
  "prod-server-02",
  "prod-server-03"
]
```

#### 3. 启用 workflow job

编辑 `.github/workflows/release-and-deploy.yml`：

```yaml
  deploy-jumpserver:
    name: Deploy via JumpServer
    needs: build
    runs-on: ubuntu-latest
    if: |
      # 删除 false && 这一行
      github.event_name == 'push' &&
      !contains(github.ref, '-dev') &&
      !contains(github.ref, '-beta')
```

---

## 方案对比

| 方案 | 安全性 | 配置难度 | 维护成本 | 推荐度 |
|------|--------|----------|----------|--------|
| **GitHub Webhook** | ✅ 最高 | ✅ 最简单 | ✅ 最低 | ⭐⭐⭐ |
| GitHub Actions SSH | ⚠️ 中等 | ⚠️ 中等 | ⚠️ 中等 | ⭐ |
| JumpServer API | ✅ 高 | ⚠️ 复杂 | ⚠️ 中等 | ⭐⭐ |

### 详细对比

**GitHub Webhook 方式：**
- ✅ 服务器主动拉取，不暴露 SSH 私钥
- ✅ Python3 实现，易维护
- ✅ 无需修改 GitHub Actions workflow
- ✅ 支持 HMAC 签名验证
- ⚠️ 需要服务器可接收外网请求

**GitHub Actions SSH 方式：**
- ⚠️ 需要在 GitHub 存储 SSH 私钥（安全风险）
- ⚠️ 需要管理多个 secrets
- ⚠️ 服务器需要开放 SSH 端口
- ✅ 部署逻辑集中在 GitHub

**JumpServer API 方式：**
- ✅ 统一权限管理
- ✅ 完整审计日志
- ⚠️ 依赖 JumpServer 基础设施
- ⚠️ API 配置相对复杂

---

## 故障排查

### 问题：SSH 部署失败

**错误：Permission denied**

```bash
# 检查 SSH 连接
ssh -i ~/.ssh/github_actions_rsa ecs-user@your-server-ip

# 检查公钥是否正确添加
cat ~/.ssh/authorized_keys | grep github-actions
```

### 问题：Webhook 未触发

**检查项：**

1. Webhook 配置是否正确
   ```
   Settings → Webhooks → 查看 Recent Deliveries
   ```

2. 服务器是否可访问
   ```bash
   curl http://your-server:9666/health
   ```

3. 防火墙是否开放端口
   ```bash
   sudo firewall-cmd --list-ports
   # 应该包含 9000/tcp
   ```

### 问题：JumpServer API 调用失败

**检查项：**

1. Token 是否有效
   ```bash
   curl -H "Authorization: Bearer $TOKEN" \
        https://jumpserver.yourdomain.com/api/v1/users/profile/
   ```

2. 主机列表是否正确
   ```bash
   # 在 JumpServer 中查看资产列表
   ```

---

## 推荐实践

### 开发环境

```
git tag v1.0.0-dev
git push origin v1.0.0-dev
```

不触发自动部署（workflow 检查会跳过 `-dev` tag）

### 测试环境

```
git tag v1.0.0-beta
git push origin v1.0.0-beta
```

不触发自动部署（workflow 检查会跳过 `-beta` tag）

### 生产环境

```
git tag v1.0.0
git push origin v1.0.0
```

触发自动部署（如果启用）

---

## 安全建议

1. **使用 GitHub Webhook 方式**（最安全）
2. **定期轮换 secrets**（每 3-6 个月）
3. **使用强密码生成 webhook secret**
   ```bash
   openssl rand -hex 32
   ```
4. **限制 SSH 密钥权限**（仅部署权限）
5. **启用 GitHub 分支保护**
6. **监控部署日志**

---

## 相关文档

- [WEBHOOK_SETUP.md](./WEBHOOK_SETUP.md) - Webhook 完整配置指南
- [AUTO_DEPLOY_GUIDE.md](./AUTO_DEPLOY_GUIDE.md) - 部署方案详细对比
- [README.md](./README.md) - 项目完整文档

---

**推荐：** 使用 GitHub Webhook 方式，简单、安全、易维护！

查看详细配置：`cat WEBHOOK_SETUP.md`
