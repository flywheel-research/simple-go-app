# GitHub Webhook 配置指南

## 当前状态

Webhook server 已正确运行在：
```
http://101.35.23.127:9666/webhook
```

## 问题

从日志可以看到，目前接收到的都是 `push` 事件，但我们的 webhook server 只处理 `release` 事件。

```
2025-10-26 00:01:21 [INFO] 📥 Received webhook: push
2025-10-26 00:01:21 [INFO] ⏩ Ignoring event type: push  ← 正确忽略了 push 事件
```

## 修复步骤

### 1. 访问 GitHub Webhook 设置

```
https://github.com/flywheel-research/simple-go-app/settings/hooks
```

### 2. 编辑 Webhook

找到配置为 `http://101.35.23.127:9666/webhook` 的 webhook，点击 "Edit"

### 3. 修改事件配置

在 "Which events would you like to trigger this webhook?" 部分：

**当前配置（错误）：**
```
● Just the push event  ← 这个导致只发送 push 事件
```

**正确配置：**
```
● Let me select individual events

取消勾选：
☐ Pushes

勾选：
☑ Releases  ← 只勾选这一个！
```

### 4. 保存

点击页面底部的 "Update webhook" 按钮

## 验证配置

### 方法 1：通过 GitHub UI 测试

1. 在 Webhook 设置页面，往下滚动到 "Recent Deliveries"
2. 点击最近的一次请求
3. 检查 "Headers" 中的 `X-GitHub-Event` 应该是 `release`（而不是 `push`）

### 方法 2：推送新版本测试

```bash
# 回到项目目录
cd /mnt/data/code/code.bing.com/btc/btc-ops/examples/simple-go-app

# 创建并推送新 tag
git tag v1.0.2
git push origin v1.0.2
```

### 预期日志输出

修复后，当创建 Release 时，webhook server 会显示：

```
[INFO] 📥 Received webhook: release
[INFO] 🎯 Release event detected: published
[INFO] 📦 Version: v1.0.2
[INFO] ⚡ Adding deployment task to queue
[INFO] 🚀 Starting deployment for version v1.0.2
[INFO] 📥 Downloading from GitHub...
[INFO] ✅ Deployment completed successfully
```

## 正确的 Webhook 配置摘要

| 配置项 | 值 |
|-------|-----|
| **Payload URL** | `http://101.35.23.127:9666/webhook` |
| **Content type** | `application/json` |
| **Secret** | (你的 webhook secret) |
| **SSL verification** | Enable SSL verification |
| **Events** | ☑ **Releases** only |
| **Active** | ☑ Active |

## 常见问题

### Q: 为什么选择 Releases 而不是 Pushes？

**A:**
- ✅ **Releases** - 只在正式发布时触发，避免每次代码提交都部署
- ❌ **Pushes** - 每次 git push 都会触发，包括开发中的提交

### Q: 我想在每次 push 到 main 分支时自动部署怎么办？

**A:** 可以同时勾选 Pushes 和 Releases，然后在 webhook-server.py 中添加逻辑来处理 push 事件。但**不推荐**，因为：
1. 开发中的代码可能不稳定
2. 频繁部署增加服务中断风险
3. 没有明确的版本控制

推荐使用 tag/release 方式发布：
```bash
git tag v1.0.2        # 创建 tag
git push origin v1.0.2  # 推送 tag → 触发 Actions → 创建 Release → 触发 Webhook → 自动部署
```

### Q: 如何查看 webhook 触发历史？

**A:**
```
GitHub 仓库 → Settings → Webhooks →
点击 webhook → 往下滚动到 "Recent Deliveries"
```

可以看到：
- 发送时间
- 请求 payload
- 响应状态
- 可以点击 "Redeliver" 重新发送

## 测试完整流程

配置修改后，测试完整的 CI/CD 流程：

```bash
# 1. 创建新 tag
git tag v1.0.2

# 2. 推送 tag
git push origin v1.0.2

# 3. 等待 GitHub Actions 构建（约 2-3 分钟）
# 访问: https://github.com/flywheel-research/simple-go-app/actions

# 4. 查看 webhook server 日志，应该会自动部署
tail -f /var/log/webhook-server.log  # 如果用 systemd
# 或查看手动运行的终端输出

# 5. 验证部署
curl http://localhost:8080/version
# 应该返回: {"version":"1.0.2",...}
```

## 下一步

修复 GitHub webhook 配置后，完整的自动化部署流程就完全打通了：

```
开发 → 提交代码 → 推送 tag → GitHub Actions 构建 →
创建 Release → 触发 Webhook → 自动部署 → 完成！
```

所有这些都是自动的，你只需要推送 tag！
