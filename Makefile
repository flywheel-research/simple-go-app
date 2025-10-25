.PHONY: help build run test clean deploy rollback

# 变量定义
APP_NAME := simple-go-app
VERSION := $(shell git describe --tags --always --dirty)
BUILD_TIME := $(shell date -u '+%Y-%m-%d_%H:%M:%S')
GIT_COMMIT := $(shell git rev-parse --short HEAD)
LDFLAGS := -s -w -X main.Version=$(VERSION) -X main.BuildTime=$(BUILD_TIME) -X main.GitCommit=$(GIT_COMMIT)

# 默认目标
help:
	@echo "Simple Go App - Makefile 使用说明"
	@echo ""
	@echo "使用方法："
	@echo "  make <target>"
	@echo ""
	@echo "可用目标："
	@echo "  build         - 编译应用（当前平台）"
	@echo "  build-linux   - 编译 Linux AMD64 版本"
	@echo "  build-all     - 编译所有平台版本"
	@echo "  run           - 运行应用"
	@echo "  test          - 运行测试"
	@echo "  clean         - 清理编译文件"
	@echo "  deploy        - 部署到服务器"
	@echo "  rollback      - 回滚到上一个版本"
	@echo ""
	@echo "示例："
	@echo "  make build"
	@echo "  make build-linux"
	@echo "  make deploy VERSION=v1.0.0 ENV=prod"
	@echo ""

# 编译当前平台
build:
	@echo "🔨 编译 $(APP_NAME)..."
	go build -ldflags="$(LDFLAGS)" -o $(APP_NAME) .
	@echo "✅ 编译完成: $(APP_NAME)"
	@echo "📦 版本: $(VERSION)"

# 编译 Linux AMD64
build-linux:
	@echo "🔨 编译 Linux AMD64 版本..."
	GOOS=linux GOARCH=amd64 go build -ldflags="$(LDFLAGS)" -o $(APP_NAME)-linux-amd64 .
	@echo "✅ 编译完成: $(APP_NAME)-linux-amd64"

# 编译所有平台
build-all:
	@echo "🔨 编译所有平台版本..."
	@echo "  - Linux AMD64"
	GOOS=linux GOARCH=amd64 go build -ldflags="$(LDFLAGS)" -o $(APP_NAME)-linux-amd64 .
	@echo "  - Linux ARM64"
	GOOS=linux GOARCH=arm64 go build -ldflags="$(LDFLAGS)" -o $(APP_NAME)-linux-arm64 .
	@echo "  - macOS AMD64"
	GOOS=darwin GOARCH=amd64 go build -ldflags="$(LDFLAGS)" -o $(APP_NAME)-darwin-amd64 .
	@echo "  - macOS ARM64"
	GOOS=darwin GOARCH=arm64 go build -ldflags="$(LDFLAGS)" -o $(APP_NAME)-darwin-arm64 .
	@echo "✅ 所有平台编译完成"
	@ls -lh $(APP_NAME)-*

# 运行应用
run: build
	@echo "🚀 启动 $(APP_NAME)..."
	./$(APP_NAME)

# 运行测试
test:
	@echo "🧪 运行测试..."
	go test -v ./...

# 运行测试（带覆盖率）
test-cover:
	@echo "🧪 运行测试（带覆盖率）..."
	go test -cover ./...
	go test -coverprofile=coverage.out ./...
	go tool cover -html=coverage.out -o coverage.html
	@echo "📊 覆盖率报告: coverage.html"

# 清理
clean:
	@echo "🧹 清理编译文件..."
	rm -f $(APP_NAME)
	rm -f $(APP_NAME)-*
	rm -f coverage.out coverage.html
	@echo "✅ 清理完成"

# 本地测试（模拟部署）
local-test: build-linux
	@echo "🧪 本地测试..."
	./$(APP_NAME)-linux-amd64 &
	@sleep 2
	@echo "  - 测试根路径"
	curl http://localhost:8080/
	@echo ""
	@echo "  - 测试健康检查"
	curl http://localhost:8080/health
	@echo ""
	@echo "  - 测试版本信息"
	curl http://localhost:8080/version
	@echo ""
	@pkill $(APP_NAME)-linux-amd64 || true
	@echo "✅ 本地测试完成"

# 创建 Git Tag
tag:
	@if [ -z "$(TAG)" ]; then \
		echo "❌ 错误: 请指定 TAG"; \
		echo "使用方法: make tag TAG=v1.0.0"; \
		exit 1; \
	fi
	@echo "🏷️  创建 Tag: $(TAG)"
	git tag $(TAG)
	git push origin $(TAG)
	@echo "✅ Tag 已推送到 GitHub"

# 创建 Dev Tag
tag-dev:
	@if [ -z "$(TAG)" ]; then \
		echo "❌ 错误: 请指定 TAG"; \
		echo "使用方法: make tag-dev TAG=v1.0.0"; \
		exit 1; \
	fi
	@echo "🏷️  创建 Dev Tag: $(TAG)-dev"
	git tag $(TAG)-dev
	git push origin $(TAG)-dev
	@echo "✅ Dev Tag 已推送到 GitHub"

# 部署到服务器
deploy:
	@if [ -z "$(VERSION)" ]; then \
		echo "❌ 错误: 请指定 VERSION"; \
		echo "使用方法: make deploy VERSION=v1.0.0 ENV=prod SERVER=192.168.1.100"; \
		exit 1; \
	fi
	@if [ -z "$(ENV)" ]; then \
		echo "❌ 错误: 请指定 ENV"; \
		echo "使用方法: make deploy VERSION=v1.0.0 ENV=prod SERVER=192.168.1.100"; \
		exit 1; \
	fi
	@if [ -z "$(SERVER)" ]; then \
		echo "❌ 错误: 请指定 SERVER"; \
		echo "使用方法: make deploy VERSION=v1.0.0 ENV=prod SERVER=192.168.1.100"; \
		exit 1; \
	fi
	@echo "🚀 部署到服务器..."
	@echo "  - 版本: $(VERSION)"
	@echo "  - 环境: $(ENV)"
	@echo "  - 服务器: $(SERVER)"
	scp deploy/deploy.sh ecs-user@$(SERVER):/tmp/
	ssh ecs-user@$(SERVER) "chmod +x /tmp/deploy.sh && sudo /tmp/deploy.sh $(VERSION) $(ENV)"
	@echo "✅ 部署完成"

# 回滚
rollback:
	@if [ -z "$(SERVER)" ]; then \
		echo "❌ 错误: 请指定 SERVER"; \
		echo "使用方法: make rollback SERVER=192.168.1.100 [VERSION=v1.0.0]"; \
		exit 1; \
	fi
	@echo "↩️  回滚服务器..."
	@echo "  - 服务器: $(SERVER)"
	scp deploy/rollback.sh ecs-user@$(SERVER):/tmp/
	ssh ecs-user@$(SERVER) "chmod +x /tmp/rollback.sh && sudo /tmp/rollback.sh $(VERSION)"
	@echo "✅ 回滚完成"

# 灰度发布
canary:
	@if [ -z "$(VERSION)" ]; then \
		echo "❌ 错误: 请指定 VERSION"; \
		echo "使用方法: make canary VERSION=v1.0.0 STAGE=1"; \
		exit 1; \
	fi
	@if [ -z "$(STAGE)" ]; then \
		echo "❌ 错误: 请指定 STAGE (1=10%, 2=50%, 3=100%)"; \
		echo "使用方法: make canary VERSION=v1.0.0 STAGE=1"; \
		exit 1; \
	fi
	@echo "🕯️  灰度发布..."
	@echo "  - 版本: $(VERSION)"
	@echo "  - 阶段: $(STAGE)"
	./deploy/canary-deploy.sh $(VERSION) $(STAGE)
	@echo "✅ 灰度发布完成"

# 查看版本
version:
	@echo "📦 当前版本信息:"
	@echo "  - 版本: $(VERSION)"
	@echo "  - 构建时间: $(BUILD_TIME)"
	@echo "  - Git Commit: $(GIT_COMMIT)"

# 查看服务状态
status:
	@if [ -z "$(SERVER)" ]; then \
		echo "❌ 错误: 请指定 SERVER"; \
		echo "使用方法: make status SERVER=192.168.1.100"; \
		exit 1; \
	fi
	@echo "📊 查看服务状态..."
	@echo "  - 服务器: $(SERVER)"
	@ssh ecs-user@$(SERVER) "sudo supervisorctl status $(APP_NAME)"
	@echo ""
	@echo "📝 查看版本信息..."
	@ssh ecs-user@$(SERVER) "curl -s http://localhost:8080/version | jq ."
	@echo ""
	@echo "🏥 查看健康状态..."
	@ssh ecs-user@$(SERVER) "curl -s http://localhost:8080/health | jq ."

# 查看日志
logs:
	@if [ -z "$(SERVER)" ]; then \
		echo "❌ 错误: 请指定 SERVER"; \
		echo "使用方法: make logs SERVER=192.168.1.100"; \
		exit 1; \
	fi
	@echo "📝 查看日志..."
	@echo "  - 服务器: $(SERVER)"
	ssh ecs-user@$(SERVER) "sudo tail -f /var/log/$(APP_NAME).log"

# 安装依赖
deps:
	@echo "📦 安装依赖..."
	go mod download
	go mod tidy
	@echo "✅ 依赖安装完成"

# 格式化代码
fmt:
	@echo "🎨 格式化代码..."
	go fmt ./...
	@echo "✅ 代码格式化完成"

# 代码检查
lint:
	@echo "🔍 代码检查..."
	golangci-lint run
	@echo "✅ 代码检查完成"

# 安装开发工具
install-tools:
	@echo "🔧 安装开发工具..."
	go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest
	@echo "✅ 开发工具安装完成"

# 完整发布流程（示例）
release: clean deps test build-all
	@echo "🎉 准备发布..."
	@echo ""
	@echo "下一步："
	@echo "  1. 确认所有测试通过"
	@echo "  2. 创建 Tag: make tag TAG=v1.0.0"
	@echo "  3. GitHub Actions 会自动构建和发布"
	@echo "  4. 部署到 Dev: make deploy VERSION=v1.0.0 ENV=dev SERVER=..."
	@echo "  5. 部署到 Staging: make deploy VERSION=v1.0.0 ENV=staging SERVER=..."
	@echo "  6. 灰度发布到生产: make canary VERSION=v1.0.0 STAGE=1"
	@echo ""
