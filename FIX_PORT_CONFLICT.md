# 修复端口被占用问题

## 问题描述

```
OSError: [Errno 98] Address already in use
```

webhook-server 启动失败，因为 9000 端口已被其他程序占用。

---

## 快速解决方案

### 方案 1：查找并停止占用端口的进程（推荐）

```bash
# 1. 查找占用 9000 端口的进程
sudo netstat -tlnp | grep :9666
# 或
sudo lsof -i :9666

# 输出示例：
# tcp  0  0  0.0.0.0:9666  0.0.0.0:*  LISTEN  12345/python3

# 2. 停止该进程
sudo kill 12345

# 或强制停止
sudo kill -9 12345

# 3. 重启 webhook-server
sudo systemctl restart webhook-server

# 4. 检查状态
sudo systemctl status webhook-server
```

### 方案 2：更改 webhook-server 端口

```bash
# 1. 编辑 systemd 服务文件
sudo vim /etc/systemd/system/webhook-server.service

# 2. 修改 PORT 环境变量
# 找到这一行：
Environment="PORT=9666"

# 改为：
Environment="PORT=9001"

# 3. 重新加载并重启
sudo systemctl daemon-reload
sudo systemctl restart webhook-server

# 4. 验证
curl http://localhost:9001/health

# 5. 更新防火墙规则
sudo firewall-cmd --permanent --remove-port=9000/tcp
sudo firewall-cmd --permanent --add-port=9001/tcp
sudo firewall-cmd --reload

# 6. 更新 GitHub Webhook 配置
# GitHub Settings → Webhooks → Edit
# 修改 URL: http://your-server:9001/webhook
```

---

## 详细排查步骤

### 步骤 1：确认端口占用

```bash
# 方法 1：使用 netstat
sudo netstat -tlnp | grep :9666

# 方法 2：使用 lsof
sudo lsof -i :9666

# 方法 3：使用 ss
sudo ss -tlnp | grep :9666
```

### 步骤 2：查看进程详情

```bash
# 假设进程 PID 是 12345
ps aux | grep 12345

# 查看进程启动命令
sudo cat /proc/12345/cmdline | tr '\0' ' '
echo
```

### 步骤 3：检查是否是旧的 webhook-server

```bash
# 查看所有 webhook-server 相关进程
ps aux | grep webhook-server

# 查看 systemd 服务状态
sudo systemctl status webhook-server
```

**可能原因：**
- 旧的 webhook-server 进程没有正确停止
- 手动运行了 webhook-server.py 没有关闭
- 其他服务也使用了 9000 端口

### 步骤 4：清理所有 webhook-server 进程

```bash
# 停止 systemd 服务
sudo systemctl stop webhook-server

# 杀死所有相关进程
sudo pkill -f webhook-server

# 等待几秒
sleep 2

# 验证没有进程占用端口
sudo netstat -tlnp | grep :9666

# 如果还有，强制杀死
sudo lsof -ti :9666 | xargs sudo kill -9

# 重新启动服务
sudo systemctl start webhook-server
```

---

## 常见占用 9000 端口的程序

| 程序 | 说明 | 解决方案 |
|------|------|----------|
| **旧的 webhook-server** | 之前运行的实例 | `sudo pkill -f webhook-server` |
| **PHPMyAdmin** | 默认使用 9000 | 修改其配置或更改 webhook 端口 |
| **PHP-FPM** | 某些配置使用 9000 | 修改 php-fpm 配置 |
| **PortainerPortainer** | 某些版本使用 9000 | 修改其端口 |
| **手动运行的 Python 脚本** | 测试时运行的 | 查找并停止 |

---

## 推荐配置

### 使用不常见的端口

```bash
# 推荐端口：9000-9999 之间未被占用的端口
# 检查端口是否可用
nc -zv localhost 9000  # 如果失败，说明端口空闲

# 建议端口
9000  # webhook-server（默认）
9001  # 备选 1
9002  # 备选 2
9090  # 备选 3
```

### 配置端口的位置

1. **systemd 服务文件**
   ```
   /etc/systemd/system/webhook-server.service
   Environment="PORT=9666"
   ```

2. **直接运行时**
   ```bash
   PORT=9001 python3 /opt/simple-go-app/webhook-server.py
   ```

3. **环境变量文件**（推荐）
   ```bash
   # 创建配置文件
   sudo tee /etc/default/webhook-server > /dev/null <<EOF
   PORT=9001
   WEBHOOK_SECRET=your-secret-here
   DEPLOY_SCRIPT=/opt/simple-go-app/deploy/deploy.sh
   ENVIRONMENT=prod
   EOF

   # 修改 systemd 服务使用配置文件
   # 在 [Service] 部分添加：
   EnvironmentFile=/etc/default/webhook-server
   ```

---

## 验证解决

```bash
# 1. 检查服务状态
sudo systemctl status webhook-server

# 应该显示：
# Active: active (running)

# 2. 检查端口监听
sudo netstat -tlnp | grep :9666

# 应该显示：
# tcp  0  0  0.0.0.0:9666  0.0.0.0:*  LISTEN  xxxxx/python3

# 3. 测试健康检查
curl http://localhost:9666/health

# 应该返回：
# {
#   "status": "healthy",
#   "timestamp": "...",
#   "queue_size": 0
# }

# 4. 查看日志
sudo journalctl -u webhook-server -n 50

# 应该看到：
# 🚀 Webhook server starting on port 9666...
```

---

## 防火墙配置

如果更改了端口，需要更新防火墙规则：

### firewalld (CentOS/RHEL)

```bash
# 移除旧端口
sudo firewall-cmd --permanent --remove-port=9000/tcp

# 添加新端口
sudo firewall-cmd --permanent --add-port=9001/tcp

# 重新加载
sudo firewall-cmd --reload

# 验证
sudo firewall-cmd --list-ports
```

### iptables

```bash
# 删除旧规则
sudo iptables -D INPUT -p tcp --dport 9666 -j ACCEPT

# 添加新规则
sudo iptables -A INPUT -p tcp --dport 9001 -j ACCEPT

# 保存
sudo iptables-save | sudo tee /etc/sysconfig/iptables
```

### 云服务器安全组

别忘了更新云服务器的安全组规则：

- **AWS**: EC2 → Security Groups → Edit inbound rules
- **阿里云**: ECS → 安全组 → 配置规则
- **腾讯云**: CVM → 安全组 → 修改规则

---

## 自动化脚本

创建一个自动查找可用端口的脚本：

```bash
#!/bin/bash
# find-available-port.sh

START_PORT=9666
END_PORT=9099

for port in $(seq $START_PORT $END_PORT); do
    if ! sudo netstat -tlnp | grep -q ":$port "; then
        echo "✅ 可用端口: $port"
        echo ""
        echo "修改命令："
        echo "sudo sed -i 's/PORT=.*/PORT=$port/' /etc/systemd/system/webhook-server.service"
        echo "sudo systemctl daemon-reload"
        echo "sudo systemctl restart webhook-server"
        exit 0
    fi
done

echo "❌ 未找到可用端口 ($START_PORT-$END_PORT)"
exit 1
```

使用：
```bash
chmod +x find-available-port.sh
sudo ./find-available-port.sh
```

---

## 总结

**推荐解决方案：**

1. **首选**：停止占用端口的旧进程
   ```bash
   sudo pkill -f webhook-server
   sudo systemctl restart webhook-server
   ```

2. **备选**：更改端口为 9001
   ```bash
   sudo sed -i 's/PORT=9666/PORT=9001/' /etc/systemd/system/webhook-server.service
   sudo systemctl daemon-reload
   sudo systemctl restart webhook-server
   ```

**验证成功：**
```bash
curl http://localhost:9666/health  # 或新端口
```

返回 JSON 即表示成功！
