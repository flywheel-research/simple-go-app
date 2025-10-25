#!/usr/bin/env python3
"""
GitHub Release Webhook Server
接收 GitHub Release webhook，自动触发部署
"""

import os
import sys
import hmac
import hashlib
import json
import subprocess
import logging
from datetime import datetime
from http.server import HTTPServer, BaseHTTPRequestHandler
from threading import Thread, Lock
from queue import Queue, Full
import time

# 配置
WEBHOOK_SECRET = os.getenv('WEBHOOK_SECRET', 'bbzhu')
DEPLOY_SCRIPT = os.getenv('DEPLOY_SCRIPT', '/opt/simple-go-app/deploy/deploy.sh')
ENVIRONMENT = os.getenv('ENVIRONMENT', 'prod')
PORT = int(os.getenv('PORT', '9666'))

# 部署队列和状态
deployment_queue = Queue(maxsize=10)
current_deploy = None
deploy_lock = Lock()

# 日志配置
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler('/var/log/webhook-server.log')
    ]
)
logger = logging.getLogger(__name__)


def verify_signature(payload, signature):
    """验证 GitHub webhook 签名"""
    if not WEBHOOK_SECRET:
        logger.warning("⚠️  WARNING: No webhook secret configured, signature verification disabled")
        return True

    if not signature:
        logger.error("❌ No signature provided")
        return False

    # GitHub 使用 sha256=xxx 格式
    if signature.startswith('sha256='):
        signature = signature[7:]
    elif signature.startswith('sha1='):
        # 兼容旧版本
        signature = signature[5:]

    # 计算期望的签名
    mac = hmac.new(
        WEBHOOK_SECRET.encode('utf-8'),
        msg=payload,
        digestmod=hashlib.sha256
    )
    expected_sig = mac.hexdigest()

    # 常量时间比较，防止时序攻击
    valid = hmac.compare_digest(signature, expected_sig)

    if not valid:
        logger.error(f"❌ Signature mismatch: expected={expected_sig}, got={signature}")

    return valid


def deploy_worker():
    """部署工作线程"""
    logger.info("🔄 Deployment worker started")

    while True:
        try:
            version = deployment_queue.get()
            if version is None:  # 停止信号
                break

            deploy_new_version(version)
            deployment_queue.task_done()
        except Exception as e:
            logger.error(f"❌ Worker error: {e}")


def deploy_new_version(version):
    """执行部署"""
    global current_deploy

    logger.info(f"🔄 Starting deployment for version: {version}")

    with deploy_lock:
        current_deploy = {
            'version': version,
            'status': 'deploying',
            'start_time': datetime.now().isoformat(),
            'end_time': None,
            'error': None
        }

    try:
        # 执行部署脚本
        cmd = [DEPLOY_SCRIPT, version, ENVIRONMENT]
        logger.info(f"📝 Executing: {' '.join(cmd)}")

        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=600  # 10分钟超时
        )

        if result.returncode == 0:
            with deploy_lock:
                current_deploy['status'] = 'success'
                current_deploy['end_time'] = datetime.now().isoformat()

            duration = (datetime.fromisoformat(current_deploy['end_time']) -
                       datetime.fromisoformat(current_deploy['start_time'])).total_seconds()

            logger.info(f"✅ Deployment completed successfully: {version} (took {duration:.2f}s)")
            logger.info(f"📤 STDOUT:\n{result.stdout}")
        else:
            error_msg = f"Exit code: {result.returncode}\nSTDERR: {result.stderr}"

            with deploy_lock:
                current_deploy['status'] = 'failed'
                current_deploy['error'] = error_msg
                current_deploy['end_time'] = datetime.now().isoformat()

            logger.error(f"❌ Deployment failed: {version}")
            logger.error(f"📤 STDOUT:\n{result.stdout}")
            logger.error(f"📤 STDERR:\n{result.stderr}")

    except subprocess.TimeoutExpired:
        error_msg = "Deployment timeout (>10 minutes)"

        with deploy_lock:
            current_deploy['status'] = 'failed'
            current_deploy['error'] = error_msg
            current_deploy['end_time'] = datetime.now().isoformat()

        logger.error(f"❌ Deployment timeout: {version}")

    except Exception as e:
        error_msg = str(e)

        with deploy_lock:
            current_deploy['status'] = 'failed'
            current_deploy['error'] = error_msg
            current_deploy['end_time'] = datetime.now().isoformat()

        logger.error(f"❌ Deployment error: {e}")


class WebhookHandler(BaseHTTPRequestHandler):
    """Webhook HTTP 请求处理器"""

    def log_message(self, format, *args):
        """重定向日志到 logger"""
        logger.info(f"{self.address_string()} - {format % args}")

    def do_GET(self):
        """处理 GET 请求"""
        if self.path == '/health':
            self.handle_health()
        elif self.path == '/status':
            self.handle_status()
        else:
            self.send_error(404, "Not Found")

    def do_POST(self):
        """处理 POST 请求"""
        if self.path == '/webhook':
            self.handle_webhook()
        else:
            self.send_error(404, "Not Found")

    def handle_webhook(self):
        """处理 GitHub webhook"""
        try:
            # 读取请求体
            content_length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(content_length)

            # 获取事件类型
            event_type = self.headers.get('X-GitHub-Event', '')
            logger.info(f"📥 Received webhook: {event_type}")

            # 只处理 release 事件
            if event_type != 'release':
                logger.info(f"⏩ Ignoring event type: {event_type}")
                self.send_response(200)
                self.send_header('Content-Type', 'text/plain')
                self.end_headers()
                self.wfile.write(f"Event type {event_type} ignored\n".encode())
                return

            # 验证签名
            signature = self.headers.get('X-Hub-Signature-256', '')
            if not verify_signature(body, signature):
                logger.error("❌ Invalid signature")
                self.send_error(401, "Invalid signature")
                return

            # 解析 payload
            try:
                payload = json.loads(body)
            except json.JSONDecodeError as e:
                logger.error(f"❌ Invalid JSON: {e}")
                self.send_error(400, "Invalid JSON")
                return

            # 只处理 published 事件
            if payload.get('action') != 'published':
                action = payload.get('action', 'unknown')
                logger.info(f"⏩ Ignoring action: {action}")
                self.send_response(200)
                self.send_header('Content-Type', 'text/plain')
                self.end_headers()
                self.wfile.write(f"Action {action} ignored\n".encode())
                return

            # 获取 release 信息
            release = payload.get('release', {})

            # 忽略 draft 和 prerelease
            if release.get('draft', False):
                logger.info("⏩ Ignoring draft release")
                self.send_response(200)
                self.send_header('Content-Type', 'text/plain')
                self.end_headers()
                self.wfile.write(b"Draft release ignored\n")
                return

            if release.get('prerelease', False):
                logger.info("⏩ Ignoring prerelease")
                self.send_response(200)
                self.send_header('Content-Type', 'text/plain')
                self.end_headers()
                self.wfile.write(b"Prerelease ignored\n")
                return

            version = release.get('tag_name', '')
            repo = payload.get('repository', {}).get('full_name', '')

            if not version:
                logger.error("❌ No version in payload")
                self.send_error(400, "No version in payload")
                return

            logger.info(f"🚀 New release detected: {version} from {repo}")

            # 加入部署队列
            try:
                deployment_queue.put(version, block=False)
                logger.info(f"✅ Version {version} added to deployment queue")

                self.send_response(200)
                self.send_header('Content-Type', 'text/plain')
                self.end_headers()
                self.wfile.write(f"Deployment triggered for version: {version}\n".encode())

            except Full:
                logger.warning(f"⚠️  Deployment queue full, skipping {version}")
                self.send_error(503, "Deployment queue full")

        except Exception as e:
            logger.error(f"❌ Error handling webhook: {e}")
            self.send_error(500, f"Internal server error: {str(e)}")

    def handle_health(self):
        """健康检查"""
        status = {
            'status': 'healthy',
            'timestamp': datetime.now().isoformat(),
            'queue_size': deployment_queue.qsize()
        }

        if current_deploy:
            with deploy_lock:
                status['current_deployment'] = current_deploy.copy()

        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(status, indent=2).encode())

    def handle_status(self):
        """部署状态"""
        if current_deploy is None:
            status = {'status': 'no deployment'}
        else:
            with deploy_lock:
                status = current_deploy.copy()

        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(status, indent=2).encode())


def main():
    """主函数"""
    # 检查部署脚本是否存在
    if not os.path.exists(DEPLOY_SCRIPT):
        logger.warning(f"⚠️  Deploy script not found: {DEPLOY_SCRIPT}")

    # 启动部署工作线程
    worker_thread = Thread(target=deploy_worker, daemon=True)
    worker_thread.start()

    # 启动 HTTP 服务器
    server = HTTPServer(('0.0.0.0', PORT), WebhookHandler)

    logger.info(f"🚀 Webhook server starting on port {PORT}...")
    logger.info(f"📝 Configuration:")
    logger.info(f"   - Deploy Script: {DEPLOY_SCRIPT}")
    logger.info(f"   - Environment: {ENVIRONMENT}")
    logger.info(f"   - Webhook Secret: {'configured ✅' if WEBHOOK_SECRET else 'not configured ⚠️'}")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        logger.info("\n🛑 Shutting down...")
        deployment_queue.put(None)  # 停止工作线程
        server.shutdown()
        logger.info("✅ Server stopped")


if __name__ == '__main__':
    main()
