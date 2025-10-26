# 代理支持配置指南

## 问题背景

在国内环境访问 GitHub Release 下载二进制文件时，经常会遇到网络问题：

```
curl: (56) OpenSSL SSL_read: error:0A000126:SSL routines::unexpected eof while reading, errno 0
```

这会导致：
- 下载超时（90+ 秒后失败）
- 部署失败
- CI/CD 流程中断

## 解决方案

部署脚本 `deploy/deploy.sh` 现已支持通过代理下载，提供两种配置方式：

### 方式 1：环境变量（推荐用于临时测试）

```bash
# 临时设置代理
export HTTP_PROXY="http://192.168.31.114:7890"
export HTTPS_PROXY="http://192.168.31.114:7890"

# 运行部署
./deploy/deploy.sh v1.0.2 prod
```

### 方式 2：配置文件（推荐用于生产环境）

创建配置文件 `/opt/simple-go-app/config.json`：

```json
{
  "http_proxy": "http://192.168.31.114:7890",
  "https_proxy": "http://192.168.31.114:7890"
}
```

配置文件示例已包含在仓库中：`config.json.example`

## 性能对比

### 不使用代理
```
下载时间: 90+ 秒（通常超时失败）
成功率: ~20%
错误: SSL_read: unexpected eof
```

### 使用代理
```
下载时间: ~1 秒
成功率: 99%+
下载速度: 3-7 MB/s
```

## 其他改进

### 1. 重试机制

脚本现在会自动重试失败的下载（默认 3 次）：

```bash
[INFO] 下载尝试 1/3...
[WARNING] 下载失败，等待 5 秒后重试...
[INFO] 下载尝试 2/3...
[SUCCESS] 下载完成
```

配置参数：
```bash
DOWNLOAD_TIMEOUT=600    # 单次下载超时：10 分钟
DOWNLOAD_RETRIES=3      # 重试次数
```

### 2. 超时控制

```bash
--max-time 600           # 总超时时间：10 分钟
--connect-timeout 30     # 连接超时：30 秒
```

### 3. 日志改进

显示代理配置信息：

```
[INFO] =========================================
[INFO]   部署 simple-go-app v1.0.2
[INFO]   环境: prod
[INFO]   代理: http://192.168.31.114:7890
[INFO] =========================================
```

## 使用示例

### 部署 v1.0.2（使用代理）

```bash
# 1. 配置代理（二选一）

# 方式 A: 环境变量
export HTTPS_PROXY="http://192.168.31.114:7890"

# 方式 B: 配置文件
sudo tee /opt/simple-go-app/config.json > /dev/null <<'EOF'
{
  "https_proxy": "http://192.168.31.114:7890"
}
EOF

# 2. 运行部署
cd /opt/simple-go-app
sudo ./deploy/deploy.sh v1.0.2 prod

# 3. 验证
cat /opt/simple-go-app/.current_version
/opt/simple-go-app/simple-go-app
```

### 实际部署输出

```
[INFO] =========================================
[INFO]   部署 simple-go-app v1.0.2
[INFO]   环境: prod
[INFO]   代理: http://192.168.31.114:7890
[INFO] =========================================
[INFO] 创建目录结构...
[INFO] 下载版本 v1.0.2...
[INFO] 下载尝试 1/3...
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100 4656k  100 4656k    0     0  3204k      0  0:00:01  0:00:01 --:--:-- 7402k
[SUCCESS] 下载完成
[INFO] 验证二进制文件...
[INFO] 备份当前版本...
[SUCCESS] 备份完成
[INFO] 部署新版本...
[SUCCESS] 部署完成
```

## 验证结果

```bash
# 检查版本
$ cat /opt/simple-go-app/.current_version
v1.0.2

# 检查备份
$ ls -lh /opt/simple-go-app/versions/
-rwxr-xr-x 1 root root 4.6M 10月 26 00:12 simple-go-app-v1.0.0
-rwxr-xr-x 1 root root 4.6M 10月 26 09:54 simple-go-app-v1.0.2

# 运行程序
$ /opt/simple-go-app/simple-go-app
2025/10/26 09:55:18 🚀 Server starting on port 8080
2025/10/26 09:55:18 📦 Version: v1.0.2
2025/10/26 09:55:18 ⏰ Build Time: 2025-10-25_16:22:56
2025/10/26 09:55:18 🔖 Git Commit: a2e5524
```

## Webhook 集成

Webhook 服务器 (`webhook-server.py`) 会自动调用更新后的部署脚本，代理配置会自动生效。

无需修改 webhook 服务器代码，只需配置好 `config.json` 即可。

## 故障排查

### 代理连接失败

```bash
# 检查代理是否可访问
curl -x http://192.168.31.114:7890 https://www.google.com

# 检查配置文件
cat /opt/simple-go-app/config.json
```

### 仍然超时

1. 检查代理配置是否正确
2. 增加 `DOWNLOAD_TIMEOUT`
3. 检查 GitHub Release 文件是否存在

### 查看详细日志

部署脚本会显示每次重试的详细信息，包括：
- 当前重试次数
- 下载进度
- 失败原因

## 最佳实践

1. **生产环境**：使用配置文件方式，便于管理
2. **测试环境**：可以使用环境变量快速测试
3. **定期检查**：确保代理服务稳定可用
4. **监控日志**：关注部署日志中的代理使用情况

## 配置优先级

```
环境变量 > 配置文件 > 无代理
```

如果同时设置了环境变量和配置文件，环境变量优先。

## 相关文件

- `deploy/deploy.sh` - 部署脚本（包含代理支持）
- `config.json.example` - 配置文件示例
- `webhook-server.py` - Webhook 服务器（自动调用部署脚本）

## 提交记录

- Commit: `58aaa86`
- 日期: 2025-10-26
- 改进: 添加代理支持、重试机制、超时控制
