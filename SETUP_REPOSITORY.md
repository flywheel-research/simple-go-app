# 设置独立仓库

## 当前状态

`simple-go-app` 目录目前是 `btc-ops` 仓库的一部分：
```
/mnt/data/code/code.bing.com/btc/btc-ops/
└── examples/
    └── simple-go-app/  ← 我们在这里
```

## 目标

将 `simple-go-app` 独立出来，推送到新仓库：
```
git@github.com:flywheel-research/simple-go-app.git
```

---

## 方案 1：直接在当前目录初始化（推荐）

### 步骤 1：在 GitHub 上创建新仓库

1. 访问 https://github.com/flywheel-research
2. 点击 "New repository"
3. Repository name: `simple-go-app`
4. Description: `Simple Go App - Complete CI/CD Example`
5. Public/Private: 根据需要选择
6. **不要**勾选 "Add a README file"（我们已经有了）
7. 点击 "Create repository"

### 步骤 2：初始化并推送

```bash
# 1. 进入项目目录
cd /mnt/data/code/code.bing.com/btc/btc-ops/examples/simple-go-app

# 2. 删除旧 git 历史（如果存在）
rm -rf .git

# 3. 初始化新仓库
git init
git add .
git commit -m "Initial commit: Complete CI/CD example with webhook deployment"

# 4. 添加 remote 并推送
git branch -M main
git remote add origin git@github.com:flywheel-research/simple-go-app.git
git push -u origin main
```

### 步骤 3：验证

```bash
# 检查 remote
git remote -v

# 应该显示：
# origin  git@github.com:flywheel-research/simple-go-app.git (fetch)
# origin  git@github.com:flywheel-research/simple-go-app.git (push)

# 查看提交历史
git log --oneline

# 访问仓库
# https://github.com/flywheel-research/simple-go-app
```

---

## 方案 2：使用 git filter-branch 保留历史（高级）

如果需要保留 `simple-go-app` 相关的 git 历史：

```bash
# 1. 克隆原仓库
cd /tmp
git clone git@github.com:flywheel-research/btc-ops.git btc-ops-filter
cd btc-ops-filter

# 2. 只保留 examples/simple-go-app 的历史
git filter-branch --subdirectory-filter examples/simple-go-app -- --all

# 3. 更改 remote
git remote remove origin
git remote add origin git@github.com:flywheel-research/simple-go-app.git

# 4. 推送
git push -u origin main
```

---

## 方案 3：Git Subtree Split（推荐用于保留历史）

```bash
# 1. 在原仓库中
cd /mnt/data/code/code.bing.com/btc/btc-ops

# 2. 创建独立分支
git subtree split --prefix=examples/simple-go-app -b simple-go-app-branch

# 3. 推送到新仓库
git push git@github.com:flywheel-research/simple-go-app.git simple-go-app-branch:main
```

---

## 推荐方案

**如果不需要保留 git 历史：** 使用方案 1（最简单）

**如果需要保留 git 历史：** 使用方案 3（git subtree split）

---

## 快速执行脚本

### 方案 1 脚本（不保留历史）

```bash
#!/bin/bash
set -e

SOURCE_DIR="/mnt/data/code/code.bing.com/btc/btc-ops/examples/simple-go-app"
TEMP_DIR="/tmp/simple-go-app-$(date +%s)"
REPO_URL="git@github.com:flywheel-research/simple-go-app.git"

echo "📦 复制项目文件..."
cp -r "$SOURCE_DIR" "$TEMP_DIR"
cd "$TEMP_DIR"

echo "🔧 清理 git 历史..."
rm -rf .git

echo "🎯 初始化新仓库..."
git init
git add .
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
"

echo "🌐 设置 remote..."
git branch -M main
git remote add origin "$REPO_URL"

echo "✅ 准备完成！"
echo ""
echo "现在可以推送到 GitHub："
echo "  cd $TEMP_DIR"
echo "  git push -u origin main"
echo ""
echo "或者直接执行："
echo "  cd $TEMP_DIR && git push -u origin main"
```

保存为 `setup-new-repo.sh` 并执行：

```bash
chmod +x setup-new-repo.sh
./setup-new-repo.sh
```

---

## 推送后的步骤

### 1. 配置 GitHub Secrets

在新仓库中配置以下 Secrets（如果需要自动部署）：

```
Settings → Secrets and variables → Actions → New repository secret
```

**基本 Secrets：**
- `GITHUB_TOKEN` - 自动提供，无需配置

**如果使用 SSH 部署（不推荐）：**
- `SSH_PRIVATE_KEY` - SSH 私钥
- `SSH_KNOWN_HOSTS` - known_hosts 内容
- `DEPLOY_SERVERS` - 服务器列表 JSON

**如果使用 Webhook 部署（推荐）：**
- 无需配置 Secrets
- 在服务器上运行 webhook-server.py 即可

### 2. 配置 GitHub Webhook

```
Settings → Webhooks → Add webhook

Payload URL: http://your-server:9000/webhook
Content type: application/json
Secret: (webhook secret)
Events: Releases
```

### 3. 测试 CI/CD

```bash
# 创建第一个 tag
cd /tmp/simple-go-app-xxxxx
git tag v1.0.0
git push origin v1.0.0

# GitHub Actions 会自动：
# 1. 构建二进制文件
# 2. 创建 GitHub Release
# 3. 上传二进制文件
# 4. 触发 Webhook
# 5. 服务器自动部署
```

### 4. 更新文档链接

确认所有文档中的链接都指向新仓库：
```bash
https://github.com/flywheel-research/simple-go-app
```

---

## 验证清单

推送后检查：

- [ ] 仓库首页显示 README.md
- [ ] 文件结构完整
- [ ] GitHub Actions workflow 文件存在（.github/workflows/）
- [ ] 文档链接正确
- [ ] License 文件存在（如果需要）
- [ ] .gitignore 文件正确

测试 CI/CD：

- [ ] 推送 tag 触发 GitHub Actions
- [ ] Actions 成功构建
- [ ] 创建 GitHub Release
- [ ] 二进制文件上传成功
- [ ] Webhook 触发成功（如果配置）
- [ ] 服务器自动部署成功（如果配置）

---

## 常见问题

### Q1: 推送时提示权限错误

**错误：**
```
Permission denied (publickey)
```

**解决：**
```bash
# 确认 SSH key 已添加到 GitHub
ssh -T git@github.com

# 应该显示：
# Hi flywheel-research! You've successfully authenticated...
```

### Q2: 推送时提示仓库不存在

**错误：**
```
Repository not found
```

**解决：**
1. 确认已在 GitHub 上创建仓库
2. 确认仓库名称正确：`simple-go-app`
3. 确认有权限推送到该仓库

### Q3: 需要修改提交历史

```bash
# 修改最后一次提交
git commit --amend

# 交互式修改多次提交
git rebase -i HEAD~3
```

---

## 后续维护

仓库推送后，原 btc-ops 仓库中的 `examples/simple-go-app` 可以：

**选项 1：保留作为示例**
```bash
# 在 btc-ops 中添加说明
echo "This example has been moved to:" > examples/simple-go-app/README.md
echo "https://github.com/flywheel-research/simple-go-app" >> examples/simple-go-app/README.md
```

**选项 2：删除并添加链接**
```bash
cd /mnt/data/code/code.bing.com/btc/btc-ops/examples
rm -rf simple-go-app
echo "# Simple Go App" > simple-go-app.md
echo "Moved to: https://github.com/flywheel-research/simple-go-app" >> simple-go-app.md
```

**选项 3：Git Submodule**
```bash
cd /mnt/data/code/code.bing.com/btc/btc-ops/examples
rm -rf simple-go-app
git submodule add git@github.com:flywheel-research/simple-go-app.git simple-go-app
```

---

## 总结

推荐流程：

1. ✅ 在 GitHub 创建新仓库 `simple-go-app`
2. ✅ 运行 `setup-new-repo.sh` 脚本
3. ✅ 推送到新仓库：`git push -u origin main`
4. ✅ 配置 GitHub Webhook（如果需要自动部署）
5. ✅ 测试 CI/CD：推送 tag `v1.0.0`
6. ✅ 验证自动部署

完成后，`simple-go-app` 将成为一个独立的、完整的 CI/CD 示例仓库！
