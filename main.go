package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"
)

// 版本信息（编译时注入）
var (
	Version   = "dev"
	BuildTime = "unknown"
	GitCommit = "unknown"
)

// VersionInfo 版本信息结构
type VersionInfo struct {
	Version   string `json:"version"`
	BuildTime string `json:"build_time"`
	GitCommit string `json:"git_commit"`
	Uptime    string `json:"uptime"`
}

var startTime = time.Now()

func main() {
	port := getEnv("PORT", "8080")

	http.HandleFunc("/", handleRoot)
	http.HandleFunc("/health", handleHealth)
	http.HandleFunc("/version", handleVersion)

	log.Printf("🚀 Server starting on port %s", port)
	log.Printf("📦 Version: %s", Version)
	log.Printf("⏰ Build Time: %s", BuildTime)
	log.Printf("🔖 Git Commit: %s", GitCommit)

	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Fatal(err)
	}
}

func handleRoot(w http.ResponseWriter, r *http.Request) {
	fmt.Fprintf(w, "Hello from Simple Go App v%s!\n", Version)
}

func handleHealth(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{
		"status": "healthy",
	})
}

func handleVersion(w http.ResponseWriter, r *http.Request) {
	uptime := time.Since(startTime)
	info := VersionInfo{
		Version:   Version,
		BuildTime: BuildTime,
		GitCommit: GitCommit,
		Uptime:    uptime.String(),
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(info)
}

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}
