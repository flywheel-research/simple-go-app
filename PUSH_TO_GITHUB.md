# 推送到独立仓库

## 快速开始（3 步）

### 步骤 1：在 GitHub 上创建仓库

1. 访问 https://github.com/flywheel-research/new
2. Repository name: `simple-go-app`
3. **不要**勾选 "Add a README file"
4. 点击 "Create repository"

### 步骤 2：运行自动化脚本

```bash
cd /mnt/data/code/code.bing.com/btc/btc-ops/examples/simple-go-app

# 运行脚本（会自动处理所有步骤）
./setup-new-repo.sh
```

脚本会自动：
- ✅ 复制项目到临时目录
- ✅ 初始化 Git 仓库
- ✅ 创建初始提交
- ✅ 设置 remote
- ✅ 询问是否立即推送

### 步骤 3：验证

访问仓库：https://github.com/flywheel-research/simple-go-app

---

## 手动步骤（如果脚本不适用）

```bash
# 1. 进入项目目录
cd /mnt/data/code/code.bing.com/btc/btc-ops/examples/simple-go-app

# 2. 清理旧 git 历史（如果有）
rm -rf .git

# 3. 初始化新仓库
git init
git add .
git commit -m "Initial commit: Complete CI/CD example with webhook deployment"

# 4. 设置 remote 并推送
git branch -M main
git remote add origin git@github.com:flywheel-research/simple-go-app.git
git push -u origin main
```

---

## 测试 CI/CD

推送成功后，测试自动化流程：

```bash
# 进入仓库目录
cd /tmp/simple-go-app  # 或者克隆新仓库

# 创建第一个版本
git tag v1.0.0
git push origin v1.0.0
```

GitHub Actions 会自动：
1. ✅ 编译二进制文件（Linux AMD64/ARM64）
2. ✅ 创建 GitHub Release
3. ✅ 上传二进制文件
4. ✅ 触发 Webhook（如果已配置）
5. ✅ 服务器自动部署（如果已配置）

---

## 配置 Webhook 自动部署（可选）

### 在服务器上安装 Webhook Server

```bash
# SSH 登录到服务器
ssh ecs-user@your-server

# 一键安装
curl -sSL https://raw.githubusercontent.com/flywheel-research/simple-go-app/main/install-webhook-server.sh | sudo bash
```

### 在 GitHub 配置 Webhook

```
Repository Settings → Webhooks → Add webhook

Payload URL: http://your-server:9000/webhook
Content type: application/json
Secret: (安装时设置的密钥)
Events: ✓ Releases only
Active: ✓
```

---

## 验证清单

推送后检查：

- [ ] ✅ 仓库首页显示 README.md
- [ ] ✅ 文件结构完整（所有 .md, .sh, .py 文件）
- [ ] ✅ GitHub Actions workflows 存在（.github/workflows/）
- [ ] ✅ 推送 tag 触发 Actions
- [ ] ✅ Actions 成功构建
- [ ] ✅ 创建 GitHub Release
- [ ] ✅ 二进制文件上传成功

如果配置了 Webhook：

- [ ] ✅ Webhook 触发成功
- [ ] ✅ 服务器接收到请求
- [ ] ✅ 自动部署成功
- [ ] ✅ 服务健康检查通过

---

## 故障排查

### 问题 1：权限错误

```
Permission denied (publickey)
```

**解决：**
```bash
# 测试 SSH 连接
ssh -T git@github.com

# 如果失败，添加 SSH key
ssh-keygen -t rsa -b 4096 -C "your_email@example.com"
cat ~/.ssh/id_rsa.pub
# 复制输出，添加到 GitHub: https://github.com/settings/keys
```

### 问题 2：仓库不存在

```
Repository not found
```

**解决：**
1. 确认已在 GitHub 上创建 `simple-go-app` 仓库
2. 确认仓库名称正确
3. 确认有推送权限（如果是组织仓库）

### 问题 3：推送被拒绝

```
Updates were rejected
```

**解决：**
```bash
# 如果是空仓库，使用 force push（仅首次）
git push -u origin main --force
```

---

## 相关文档

- [README.md](./README.md) - 完整项目文档
- [QUICK_START.md](./QUICK_START.md) - 10 分钟快速开始
- [WEBHOOK_SETUP.md](./WEBHOOK_SETUP.md) - Webhook 部署指南
- [SETUP_REPOSITORY.md](./SETUP_REPOSITORY.md) - 详细的仓库设置说明

---

## 后续步骤

仓库推送成功后：

1. **设置仓库描述和主题**
   ```
   Settings → General
   Description: Complete CI/CD example with webhook auto-deployment
   Topics: ci-cd, github-actions, golang, deployment, webhook, python3
   ```

2. **配置 GitHub Pages（可选）**
   ```
   Settings → Pages
   Source: Deploy from a branch
   Branch: main / docs
   ```

3. **添加 Badge 到 README（可选）**
   ```markdown
   ![Build Status](https://github.com/flywheel-research/simple-go-app/actions/workflows/release.yml/badge.svg)
   ![Release](https://img.shields.io/github/v/release/flywheel-research/simple-go-app)
   ```

4. **设置 Branch Protection（推荐）**
   ```
   Settings → Branches → Add rule
   Branch name pattern: main
   ✓ Require a pull request before merging
   ```

---

## 总结

✅ **推荐流程：**

```bash
# 1. 创建 GitHub 仓库
# 访问 https://github.com/flywheel-research/new

# 2. 运行自动化脚本
cd /mnt/data/code/code.bing.com/btc/btc-ops/examples/simple-go-app
./setup-new-repo.sh

# 3. 测试 CI/CD
git tag v1.0.0
git push origin v1.0.0

# 完成！🎉
```

仓库地址：https://github.com/flywheel-research/simple-go-app
