# 🚀 快速开始指南

10 分钟搭建完整的 CI/CD 流程！

---

## 📋 准备工作

### 1. 创建 GitHub 仓库

```bash
# 1. 在 GitHub 创建新仓库（或使用现有仓库）
# 2. 克隆到本地
git clone https://github.com/YOUR_USERNAME/simple-go-app.git
cd simple-go-app

# 3. 复制示例代码
cp -r /path/to/btc-ops/examples/simple-go-app/* .
```

### 2. 准备服务器

确保服务器已经：
- ✅ 安装了 Supervisor
- ✅ 配置了 ecs-user 账户
- ✅ 安装了 curl 和 jq

```bash
# 快速初始化服务器（在 JumpServer 批量执行）
# 步骤 1：初始化用户
cat /path/to/jumpserver-compact.sh

# 步骤 2：安装依赖
sudo apt-get update
sudo apt-get install -y supervisor curl jq
sudo systemctl enable supervisor
sudo systemctl start supervisor
```

---

## 🎯 第一次发布

### Step 1: 提交代码到 GitHub

```bash
git add .
git commit -m "Initial commit"
git push origin main
```

### Step 2: 创建第一个 Release

```bash
# 打 Tag
git tag v1.0.0
git push origin v1.0.0
```

### Step 3: 等待 GitHub Actions 构建

1. 访问 GitHub 仓库页面
2. 点击 "Actions" 标签
3. 查看构建进度
4. 构建成功后，会自动创建 Release

### Step 4: 部署到服务器

```bash
# 方式 1：在服务器上手动部署
ssh ecs-user@your-server
curl -sSL https://github.com/YOUR_USERNAME/simple-go-app/raw/main/deploy/deploy.sh -o /tmp/deploy.sh
chmod +x /tmp/deploy.sh
sudo /tmp/deploy.sh v1.0.0 prod

# 方式 2：使用 JumpServer 批量部署
# 在 JumpServer 批量命令中执行：
curl -sSL https://github.com/YOUR_USERNAME/simple-go-app/raw/main/deploy/deploy.sh | sudo bash -s v1.0.0 prod
```

### Step 5: 验证部署

```bash
# 1. 检查服务状态
sudo supervisorctl status simple-go-app

# 2. 测试接口
curl http://localhost:8080/
curl http://localhost:8080/health
curl http://localhost:8080/version

# 3. 查看日志
sudo tail -f /var/log/simple-go-app.log
```

---

## 🔄 第二次发布（灰度发布）

### Step 1: 修改代码

```bash
# 修改 main.go，例如：
# func handleRoot(w http.ResponseWriter, r *http.Request) {
#     fmt.Fprintf(w, "Hello from Simple Go App v%s! - NEW VERSION\n", Version)
# }

git add main.go
git commit -m "Update welcome message"
git push origin main
```

### Step 2: 创建新版本

```bash
git tag v1.1.0
git push origin v1.1.0
```

### Step 3: 灰度发布

```bash
# 下载灰度发布脚本
curl -sSL https://github.com/YOUR_USERNAME/simple-go-app/raw/main/deploy/canary-deploy.sh -o /tmp/canary-deploy.sh
chmod +x /tmp/canary-deploy.sh

# 阶段 1：10% 灰度（1 台服务器）
/tmp/canary-deploy.sh v1.1.0 1

# 监控 15 分钟，确认无问题

# 阶段 2：50% 灰度（5 台服务器）
/tmp/canary-deploy.sh v1.1.0 2

# 监控 30 分钟，确认无问题

# 阶段 3：100% 全量
/tmp/canary-deploy.sh v1.1.0 3
```

---

## ↩️ 回滚演练

### 模拟故障回滚

```bash
# 1. 下载回滚脚本
curl -sSL https://github.com/YOUR_USERNAME/simple-go-app/raw/main/deploy/rollback.sh -o /tmp/rollback.sh
chmod +x /tmp/rollback.sh

# 2. 执行回滚
sudo /tmp/rollback.sh

# 3. 验证回滚
curl http://localhost:8080/version
# 应该显示之前的版本号
```

---

## 📊 完整流程演示

### 场景：从开发到生产

```bash
# === 1. 开发环境 ===
git checkout -b feature/add-metrics
# 修改代码...
git commit -m "Add metrics endpoint"
git push origin feature/add-metrics

# === 2. Dev 环境测试 ===
git checkout main
git merge feature/add-metrics
git tag v1.2.0-dev
git push origin v1.2.0-dev
# GitHub Actions 自动部署到 Dev 环境

# === 3. Staging 环境测试 ===
git tag v1.2.0-beta
git push origin v1.2.0-beta
# GitHub Actions 自动部署到 Staging 环境

# === 4. 生产环境灰度发布 ===
git tag v1.2.0
git push origin v1.2.0

# 灰度发布
./canary-deploy.sh v1.2.0 1  # 10%
# 监控...
./canary-deploy.sh v1.2.0 2  # 50%
# 监控...
./canary-deploy.sh v1.2.0 3  # 100%

# === 5. 监控和验证 ===
# 持续监控 24-48 小时
# 如有问题立即回滚
./rollback.sh
```

---

## 🎓 学习路径

### 初级（第 1 天）
- [x] 本地运行程序
- [x] 理解代码结构
- [x] 手动构建二进制文件
- [x] 手动部署到一台服务器

### 中级（第 2-3 天）
- [x] 配置 GitHub Actions
- [x] 创建第一个 Release
- [x] 自动部署到服务器
- [x] 测试回滚功能

### 高级（第 4-7 天）
- [x] 实现灰度发布
- [x] 配置多环境部署（Dev/Staging/Prod）
- [x] 集成监控告警
- [x] 优化部署流程

---

## 💡 常见问题

### Q1: GitHub Actions 构建失败？

**A:** 检查以下几点：
```bash
# 1. 检查 Go 版本
cat go.mod | grep "go 1"

# 2. 检查依赖
go mod tidy

# 3. 本地测试构建
go build .
```

### Q2: 部署失败，无法下载二进制文件？

**A:** 检查网络和权限：
```bash
# 1. 测试网络
curl -I https://github.com

# 2. 检查 Release 是否创建成功
# 访问: https://github.com/YOUR_USERNAME/simple-go-app/releases

# 3. 手动下载测试
wget https://github.com/YOUR_USERNAME/simple-go-app/releases/download/v1.0.0/simple-go-app-linux-amd64
```

### Q3: Supervisor 无法启动服务？

**A:** 检查配置和日志：
```bash
# 1. 检查配置文件
sudo cat /etc/supervisor/conf.d/simple-go-app.conf

# 2. 测试二进制文件
/opt/simple-go-app/simple-go-app

# 3. 查看 supervisor 日志
sudo tail -f /var/log/supervisor/supervisord.log

# 4. 手动启动测试
cd /opt/simple-go-app
sudo -u ecs-user ./simple-go-app
```

### Q4: 版本验证失败？

**A:** 检查版本注入：
```bash
# 1. 检查二进制文件版本
/opt/simple-go-app/simple-go-app -version

# 2. 检查运行时版本
curl http://localhost:8080/version

# 3. 检查构建参数
# 确保 GitHub Actions 中的 ldflags 正确
```

---

## 🔗 相关资源

- [完整文档](./README.md)
- [部署脚本说明](./deploy/)
- [GitHub Actions 配置](./.github/workflows/release.yml)

---

## ✅ 检查清单

### 首次部署检查

- [ ] GitHub 仓库已创建
- [ ] 代码已推送
- [ ] GitHub Actions 已配置
- [ ] 服务器已准备好
- [ ] Supervisor 已安装
- [ ] 网络连接正常
- [ ] 部署脚本已下载
- [ ] 权限配置正确

### 发布前检查

- [ ] 代码已测试
- [ ] 版本号已确定
- [ ] Release Notes 已准备
- [ ] 回滚方案已就绪
- [ ] 监控已配置
- [ ] 团队已通知

### 发布后检查

- [ ] 服务状态正常
- [ ] 健康检查通过
- [ ] 版本验证成功
- [ ] 日志无异常
- [ ] 监控指标正常
- [ ] 业务功能正常

---

## 🎉 成功！

如果你完成了以上所有步骤，恭喜你已经搭建了一个完整的 CI/CD 流程！

**下一步：**
1. 尝试添加新功能
2. 实践灰度发布
3. 测试回滚机制
4. 优化监控告警
5. 扩展到更多服务

**遇到问题？**
- 查看 [完整文档](./README.md)
- 查看 [故障排查指南](./README.md#故障排查)
- 提交 Issue

祝你部署愉快！🚀
