# 推送前检查清单

## 📋 推送前必查项

### 1. 文件完整性

- [x] ✅ main.go - Go 源代码
- [x] ✅ go.mod - Go 模块定义
- [x] ✅ .gitignore - Git 忽略规则
- [x] ✅ webhook-server.py - Python3 webhook 服务器
- [x] ✅ webhook-server.service - systemd 服务配置
- [x] ✅ install-webhook-server.sh - 一键安装脚本
- [x] ✅ deploy/deploy.sh - 部署脚本
- [x] ✅ deploy/rollback.sh - 回滚脚本
- [x] ✅ deploy/canary-deploy.sh - 灰度发布脚本
- [x] ✅ .github/workflows/release.yml - CI 工作流（已验证）
- [x] ✅ .github/workflows/release-and-deploy.yml - CI/CD 工作流（已修复）

### 2. 文档完整性

- [x] ✅ README.md - 主文档
- [x] ✅ QUICK_START.md - 快速开始
- [x] ✅ WEBHOOK_SETUP.md - Webhook 设置指南
- [x] ✅ AUTO_DEPLOY_GUIDE.md - 部署方案对比
- [x] ✅ SETUP_REPOSITORY.md - 仓库设置说明
- [x] ✅ PUSH_TO_GITHUB.md - 推送指南
- [x] ✅ ENABLE_AUTO_DEPLOY.md - 启用自动部署（新增）
- [x] ✅ FIX_PORT_CONFLICT.md - 端口冲突解决（新增）

### 3. 仓库地址检查

- [x] ✅ go.mod - 模块路径更新为 `github.com/flywheel-research/simple-go-app`
- [x] ✅ deploy/deploy.sh - GITHUB_REPO 更新
- [x] ✅ 所有文档中的下载链接更新
- [x] ✅ 所有示例命令更新

### 4. 脚本可执行权限

- [x] ✅ setup-new-repo.sh - 有执行权限
- [x] ✅ install-webhook-server.sh - 有执行权限
- [x] ✅ webhook-server.py - 有执行权限
- [x] ✅ deploy/*.sh - 所有部署脚本有执行权限

## 🚀 推送步骤

### 方式 1：使用自动化脚本（推荐）

```bash
cd /mnt/data/code/code.bing.com/btc/btc-ops/examples/simple-go-app
./setup-new-repo.sh
```

### 方式 2：手动推送

```bash
# 1. 复制到临时目录
cp -r /mnt/data/code/code.bing.com/btc/btc-ops/examples/simple-go-app /tmp/simple-go-app-new
cd /tmp/simple-go-app-new

# 2. 清理并初始化
rm -rf .git
git init
git add .
git commit -m "Initial commit: Complete CI/CD example with webhook deployment"

# 3. 推送
git branch -M main
git remote add origin git@github.com:flywheel-research/simple-go-app.git
git push -u origin main
```

## ✅ 推送后验证

### GitHub 仓库检查

- [ ] 访问 https://github.com/flywheel-research/simple-go-app
- [ ] README.md 正确显示
- [ ] 文件结构完整
- [ ] .github/workflows 存在

### CI/CD 测试

```bash
# 1. 克隆仓库（或使用临时目录）
git clone git@github.com:flywheel-research/simple-go-app.git
cd simple-go-app

# 2. 创建测试 tag
git tag v1.0.0
git push origin v1.0.0

# 3. 检查 GitHub Actions
# 访问: https://github.com/flywheel-research/simple-go-app/actions

# 4. 验证 Release
# 访问: https://github.com/flywheel-research/simple-go-app/releases
```

### Webhook 测试（可选）

如果配置了 webhook server：

- [ ] 服务器上 webhook-server 运行正常
- [ ] GitHub webhook 配置正确
- [ ] 推送 tag 触发 webhook
- [ ] 服务器接收到请求并自动部署
- [ ] 健康检查通过：`curl http://localhost:8080/health`
- [ ] 版本验证通过：`curl http://localhost:8080/version`

## 🎯 完成标准

所有以下项目都完成：

- [x] ✅ 仓库推送成功
- [ ] GitHub Actions 运行成功
- [ ] Release 创建成功
- [ ] 二进制文件上传成功
- [ ] 文档链接全部正确
- [ ] CI/CD 流程测试通过

## 📞 遇到问题？

查看故障排查文档：
- [PUSH_TO_GITHUB.md](./PUSH_TO_GITHUB.md#故障排查)
- [WEBHOOK_SETUP.md](./WEBHOOK_SETUP.md#故障排查)

---

**创建时间：** 2025-10-25
**仓库地址：** git@github.com:flywheel-research/simple-go-app.git
