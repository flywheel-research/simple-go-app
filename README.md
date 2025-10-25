# Simple Go App - CI/CD 完整示例

这是一个完整的 CI/CD 示例项目，展示如何从代码提交到自动部署的全流程。

## 📋 目录

- [项目简介](#项目简介)
- [快速开始](#快速开始)
- [CI/CD 流程](#cicd-流程)
- [部署指南](#部署指南)
- [灰度发布](#灰度发布)
- [回滚机制](#回滚机制)
- [监控告警](#监控告警)

---

## 项目简介

### 功能特性

- ✅ 简单的 HTTP 服务器
- ✅ 健康检查接口 `/health`
- ✅ 版本信息接口 `/version`
- ✅ 自动构建（GitHub Actions）
- ✅ 自动发布（GitHub Release）
- ✅ 自动部署（CD 脚本）
- ✅ 灰度发布支持
- ✅ 一键回滚

### 技术栈

- **语言：** Go 1.21
- **CI：** GitHub Actions
- **CD：** Shell Scripts
- **服务管理：** Supervisor
- **监控：** （待集成）

---

## 快速开始

### 本地运行

```bash
# 1. 克隆代码
git clone https://github.com/flywheel-research/simple-go-app.git
cd simple-go-app

# 2. 运行
go run main.go

# 3. 测试
curl http://localhost:8080/
curl http://localhost:8080/health
curl http://localhost:8080/version
```

### 本地构建

```bash
# 构建 Linux AMD64
GOOS=linux GOARCH=amd64 go build -o simple-go-app-linux-amd64 .

# 运行
./simple-go-app-linux-amd64
```

---

## CI/CD 流程

### 整体架构

```
开发者提交代码
    ↓
推送 Tag (v1.0.0)
    ↓
GitHub Actions 触发
    ↓
CI：编译多平台二进制文件
    ↓
创建 GitHub Release
    ↓
上传二进制文件到 Release
    ↓
CD：自动部署到环境
    ↓
健康检查和验证
```

### CI 流程（GitHub Actions）

**触发条件：**
- 推送 Tag（如 `v1.0.0`）
- 手动触发（workflow_dispatch）

**构建步骤：**
1. Checkout 代码
2. 设置 Go 环境
3. 获取版本信息
4. 编译二进制文件（Linux AMD64/ARM64）
5. 创建 GitHub Release
6. 上传二进制文件

**配置文件：** `.github/workflows/release.yml`

### CD 流程（自动部署）

**部署阶段：**
1. **Dev 环境：** Tag 包含 `-dev` 后缀（如 `v1.0.0-dev`）
2. **Staging 环境：** Tag 包含 `-beta` 后缀（如 `v1.0.0-beta`）
3. **Production 环境：** 正式版本 Tag（如 `v1.0.0`）

**部署脚本：** `deploy/deploy.sh`

---

## 部署指南

### 环境要求

- Linux 服务器（Ubuntu 20.04+ / CentOS 7+）
- Supervisor 已安装
- ecs-user 账户已配置
- curl, jq 已安装

### 手动部署

```bash
# 1. 复制部署脚本到服务器
scp -r deploy/ ecs-user@server:/tmp/

# 2. 登录服务器
ssh ecs-user@server

# 3. 执行部署
cd /tmp/deploy
chmod +x *.sh
sudo ./deploy.sh v1.0.0 prod
```

### 批量部署（JumpServer）

```bash
# 使用 JumpServer 批量命令
curl -sSL https://raw.githubusercontent.com/flywheel-research/simple-go-app/main/deploy/deploy.sh | sudo bash -s v1.0.0 prod
```

### 部署验证

```bash
# 1. 检查服务状态
sudo supervisorctl status simple-go-app

# 2. 检查健康状态
curl http://localhost:8080/health

# 3. 检查版本
curl http://localhost:8080/version

# 4. 查看日志
sudo tail -f /var/log/simple-go-app.log
```

---

## 灰度发布

### 灰度发布策略

**三阶段发布：**

```
阶段 1：10% 灰度（Canary）
    ↓
监控 15-30 分钟
    ↓
阶段 2：50% 灰度
    ↓
监控 30-60 分钟
    ↓
阶段 3：100% 全量
```

### 执行灰度发布

```bash
# 阶段 1：10% 灰度（Canary 服务器）
./canary-deploy.sh v1.0.0 1

# 监控 15-30 分钟，确认无问题后继续

# 阶段 2：50% 灰度
./canary-deploy.sh v1.0.0 2

# 监控 30-60 分钟，确认无问题后继续

# 阶段 3：100% 全量
./canary-deploy.sh v1.0.0 3
```

### 监控指标

在每个阶段需要监控以下指标：

**服务指标：**
- ✅ 服务状态（RUNNING）
- ✅ 健康检查通过率
- ✅ 响应时间（P50/P95/P99）
- ✅ 错误率

**系统指标：**
- ✅ CPU 使用率
- ✅ 内存使用率
- ✅ 磁盘 I/O
- ✅ 网络流量

**业务指标（根据实际情况）：**
- ✅ 订单量
- ✅ 交易成功率
- ✅ 用户活跃度

---

## 回滚机制

### 版本管理

系统自动保留最近 5 个版本：

```
/opt/simple-go-app/
├── simple-go-app              # 当前运行版本
├── .current_version          # 当前版本号
├── .previous_version         # 上一个版本号
├── backup/                   # 备份目录
│   ├── simple-go-app-v1.0.0-20231024_120000
│   ├── simple-go-app-v0.9.0-20231023_150000
│   └── ...
└── versions/                 # 所有下载的版本
    ├── simple-go-app-v1.0.0
    ├── simple-go-app-v0.9.0
    └── ...
```

### 快速回滚

```bash
# 1. 回滚到上一个版本
./rollback.sh

# 2. 回滚到指定版本
./rollback.sh v0.9.0

# 3. 验证回滚
curl http://localhost:8080/version
```

### 回滚流程

```
检测到问题
    ↓
执行回滚脚本
    ↓
停止当前服务
    ↓
恢复旧版本二进制
    ↓
启动服务
    ↓
健康检查
    ↓
版本验证
```

---

## 发布流程实战

### 完整发布流程

#### 步骤 1：开发和测试

```bash
# 1. 开发新功能
git checkout -b feature/new-feature
# ... 开发代码 ...

# 2. 本地测试
go test ./...
go run main.go

# 3. 提交代码
git add .
git commit -m "Add new feature"
git push origin feature/new-feature

# 4. 创建 Pull Request，合并到 main
```

#### 步骤 2：创建 Dev 版本

```bash
# 1. 打 Dev Tag
git tag v1.1.0-dev
git push origin v1.1.0-dev

# 2. GitHub Actions 自动构建
#    - 编译二进制文件
#    - 创建 GitHub Release
#    - 自动部署到 Dev 环境

# 3. 验证 Dev 环境
curl http://dev-server:8080/version
```

#### 步骤 3：创建 Beta 版本

```bash
# 1. Dev 测试通过后，打 Beta Tag
git tag v1.1.0-beta
git push origin v1.1.0-beta

# 2. 自动部署到 Staging 环境

# 3. 验证 Staging 环境
curl http://staging-server:8080/version
```

#### 步骤 4：灰度发布到生产环境

```bash
# 1. Beta 测试通过后，打正式 Tag
git tag v1.1.0
git push origin v1.1.0

# 2. 阶段 1：10% 灰度
./canary-deploy.sh v1.1.0 1
# 监控 15-30 分钟

# 3. 阶段 2：50% 灰度
./canary-deploy.sh v1.1.0 2
# 监控 30-60 分钟

# 4. 阶段 3：100% 全量
./canary-deploy.sh v1.1.0 3
# 持续监控 24-48 小时
```

#### 步骤 5：监控和告警

```bash
# 监控关键指标
# - 服务健康状态
# - 错误率
# - 响应时间
# - 业务指标

# 如发现问题，立即回滚
./rollback.sh
```

---

## 监控告警

### 服务监控

**Supervisor 状态监控：**
```bash
# 查看所有服务状态
sudo supervisorctl status

# 查看特定服务
sudo supervisorctl status simple-go-app
```

**健康检查：**
```bash
# 定期健康检查（可配置 cron）
*/1 * * * * curl -s http://localhost:8080/health || echo "Health check failed"
```

### 日志监控

```bash
# 实时查看日志
sudo tail -f /var/log/simple-go-app.log

# 错误日志过滤
sudo tail -f /var/log/simple-go-app.log | grep -i error

# 日志分析
sudo cat /var/log/simple-go-app.log | grep "ERROR" | wc -l
```

### 告警配置

**建议告警规则：**
- ❌ 服务停止运行
- ❌ 健康检查失败超过 3 次
- ❌ 错误率超过 1%
- ❌ 响应时间 P95 超过 1 秒
- ❌ CPU 使用率超过 80%
- ❌ 内存使用率超过 85%

---

## 最佳实践

### 版本命名规范

```
v<major>.<minor>.<patch>[-<pre-release>]

示例:
v1.0.0          # 正式版本（Production）
v1.0.0-dev      # 开发版本（Dev）
v1.0.0-beta     # 测试版本（Staging）
v1.0.0-rc1      # 候选版本
```

### 发布检查清单

**发布前：**
- [ ] 代码已合并到 main 分支
- [ ] 所有测试通过
- [ ] 文档已更新
- [ ] Release Notes 已准备

**发布中：**
- [ ] CI 构建成功
- [ ] 二进制文件已上传
- [ ] Dev 环境部署成功
- [ ] Beta 环境测试通过

**发布后：**
- [ ] 生产环境灰度发布
- [ ] 监控指标正常
- [ ] 回滚方案就绪
- [ ] 团队通知已发送

### 回滚决策

**立即回滚的情况：**
- ❌ 服务无法启动
- ❌ 健康检查持续失败
- ❌ 错误率急剧上升（>5%）
- ❌ 核心业务功能不可用

**暂停发布并观察：**
- ⚠️ 错误率略有上升（1-5%）
- ⚠️ 响应时间略有增加
- ⚠️ 部分非核心功能异常

---

## 故障排查

### 常见问题

**1. 部署失败**
```bash
# 检查网络连接
curl -I https://github.com

# 检查磁盘空间
df -h

# 检查权限
ls -la /opt/simple-go-app/
```

**2. 服务无法启动**
```bash
# 查看详细日志
sudo tail -100 /var/log/simple-go-app.log

# 检查端口占用
sudo netstat -tlnp | grep 8080

# 手动运行测试
cd /opt/simple-go-app
./simple-go-app
```

**3. 版本验证失败**
```bash
# 检查二进制文件
/opt/simple-go-app/simple-go-app --version

# 检查版本文件
cat /opt/simple-go-app/.current_version

# 对比实际运行版本
curl http://localhost:8080/version
```

---

## 目录结构

```
simple-go-app/
├── main.go                      # 主程序
├── go.mod                       # Go 模块定义
├── README.md                    # 本文档
├── .github/
│   └── workflows/
│       └── release.yml          # GitHub Actions CI 配置
└── deploy/
    ├── deploy.sh                # 部署脚本
    ├── rollback.sh              # 回滚脚本
    └── canary-deploy.sh         # 灰度发布脚本
```

---

## 参考资料

- [Go 官方文档](https://go.dev/doc/)
- [GitHub Actions 文档](https://docs.github.com/en/actions)
- [Supervisor 文档](http://supervisord.org/)
- [12-Factor App](https://12factor.net/)

---

## 贡献指南

欢迎提交 Issue 和 Pull Request！

---

## License

MIT License
