package main

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/exec"
	"strings"
	"time"
)

type ReleasePayload struct {
	Action  string `json:"action"`
	Release struct {
		TagName    string `json:"tag_name"`
		Name       string `json:"name"`
		Draft      bool   `json:"draft"`
		Prerelease bool   `json:"prerelease"`
	} `json:"release"`
	Repository struct {
		FullName string `json:"full_name"`
	} `json:"repository"`
}

type DeploymentStatus struct {
	Version   string    `json:"version"`
	Status    string    `json:"status"`
	StartTime time.Time `json:"start_time"`
	EndTime   time.Time `json:"end_time,omitempty"`
	Error     string    `json:"error,omitempty"`
}

var (
	webhookSecret   = os.Getenv("WEBHOOK_SECRET")
	deployScript    = os.Getenv("DEPLOY_SCRIPT")
	environment     = os.Getenv("ENVIRONMENT")
	currentDeploy   *DeploymentStatus
	deploymentQueue = make(chan string, 10)
)

func init() {
	if deployScript == "" {
		deployScript = "/opt/simple-go-app/deploy/deploy.sh"
	}
	if environment == "" {
		environment = "prod"
	}
}

func verifySignature(payload []byte, signature string) bool {
	if webhookSecret == "" {
		log.Println("⚠️  WARNING: No webhook secret configured, signature verification disabled")
		return true
	}

	if signature == "" {
		log.Println("❌ No signature provided")
		return false
	}

	// Remove "sha256=" prefix
	signature = strings.TrimPrefix(signature, "sha256=")

	mac := hmac.New(sha256.New, []byte(webhookSecret))
	mac.Write(payload)
	expectedMAC := hex.EncodeToString(mac.Sum(nil))

	valid := hmac.Equal([]byte(signature), []byte(expectedMAC))
	if !valid {
		log.Printf("❌ Signature mismatch: expected=%s, got=%s\n", expectedMAC, signature)
	}

	return valid
}

func handleWebhook(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// 读取请求体
	body, err := io.ReadAll(r.Body)
	if err != nil {
		log.Printf("❌ Failed to read body: %v\n", err)
		http.Error(w, "Failed to read body", http.StatusBadRequest)
		return
	}
	defer r.Body.Close()

	// 获取事件类型
	eventType := r.Header.Get("X-GitHub-Event")
	log.Printf("📥 Received webhook: %s\n", eventType)

	// 只处理 release 事件
	if eventType != "release" {
		log.Printf("⏩ Ignoring event type: %s\n", eventType)
		w.WriteHeader(http.StatusOK)
		fmt.Fprintf(w, "Event type %s ignored\n", eventType)
		return
	}

	// 验证签名
	signature := r.Header.Get("X-Hub-Signature-256")
	if !verifySignature(body, signature) {
		log.Println("❌ Invalid signature")
		http.Error(w, "Invalid signature", http.StatusUnauthorized)
		return
	}

	// 解析 payload
	var payload ReleasePayload
	if err := json.Unmarshal(body, &payload); err != nil {
		log.Printf("❌ Invalid JSON: %v\n", err)
		http.Error(w, "Invalid JSON", http.StatusBadRequest)
		return
	}

	// 只处理 published 事件
	if payload.Action != "published" {
		log.Printf("⏩ Ignoring action: %s\n", payload.Action)
		w.WriteHeader(http.StatusOK)
		fmt.Fprintf(w, "Action %s ignored\n", payload.Action)
		return
	}

	// 忽略 draft 和 prerelease
	if payload.Release.Draft {
		log.Println("⏩ Ignoring draft release")
		w.WriteHeader(http.StatusOK)
		fmt.Fprintf(w, "Draft release ignored\n")
		return
	}

	if payload.Release.Prerelease {
		log.Println("⏩ Ignoring prerelease")
		w.WriteHeader(http.StatusOK)
		fmt.Fprintf(w, "Prerelease ignored\n")
		return
	}

	version := payload.Release.TagName
	repo := payload.Repository.FullName

	log.Printf("🚀 New release detected: %s from %s\n", version, repo)

	// 加入部署队列
	select {
	case deploymentQueue <- version:
		log.Printf("✅ Version %s added to deployment queue\n", version)
	default:
		log.Printf("⚠️  Deployment queue full, skipping %s\n", version)
		http.Error(w, "Deployment queue full", http.StatusServiceUnavailable)
		return
	}

	w.WriteHeader(http.StatusOK)
	fmt.Fprintf(w, "Deployment triggered for version: %s\n", version)
}

func deployWorker() {
	for version := range deploymentQueue {
		deployNewVersion(version)
	}
}

func deployNewVersion(version string) {
	log.Printf("🔄 Starting deployment for version: %s\n", version)

	currentDeploy = &DeploymentStatus{
		Version:   version,
		Status:    "deploying",
		StartTime: time.Now(),
	}

	// 执行部署脚本
	cmd := exec.Command(deployScript, version, environment)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	if err := cmd.Run(); err != nil {
		log.Printf("❌ Deployment failed: %v\n", err)
		currentDeploy.Status = "failed"
		currentDeploy.Error = err.Error()
		currentDeploy.EndTime = time.Now()
		return
	}

	currentDeploy.Status = "success"
	currentDeploy.EndTime = time.Now()
	duration := currentDeploy.EndTime.Sub(currentDeploy.StartTime)

	log.Printf("✅ Deployment completed successfully: %s (took %v)\n", version, duration)
}

func handleHealth(w http.ResponseWriter, r *http.Request) {
	status := map[string]interface{}{
		"status":     "healthy",
		"timestamp":  time.Now().Format(time.RFC3339),
		"queue_size": len(deploymentQueue),
	}

	if currentDeploy != nil {
		status["current_deployment"] = currentDeploy
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(status)
}

func handleStatus(w http.ResponseWriter, r *http.Request) {
	if currentDeploy == nil {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{
			"status": "no deployment",
		})
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(currentDeploy)
}

func logRequest(handler http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		handler(w, r)
		log.Printf("📊 %s %s from %s (took %v)\n",
			r.Method,
			r.URL.Path,
			r.RemoteAddr,
			time.Since(start))
	}
}

func main() {
	// 启动部署 worker
	go deployWorker()

	http.HandleFunc("/webhook", logRequest(handleWebhook))
	http.HandleFunc("/health", logRequest(handleHealth))
	http.HandleFunc("/status", logRequest(handleStatus))

	port := os.Getenv("PORT")
	if port == "" {
		port = "9000"
	}

	log.Printf("🚀 Webhook server starting on port %s...\n", port)
	log.Printf("📝 Configuration:\n")
	log.Printf("   - Deploy Script: %s\n", deployScript)
	log.Printf("   - Environment: %s\n", environment)
	log.Printf("   - Webhook Secret: %s\n", func() string {
		if webhookSecret != "" {
			return "configured ✅"
		}
		return "not configured ⚠️"
	}())

	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Fatal(err)
	}
}
