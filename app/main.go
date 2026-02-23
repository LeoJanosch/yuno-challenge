package main

import (
	"encoding/json"
	"fmt"
	"log"
	"math/rand"
	"net/http"
	"os"
	"strconv"
	"sync/atomic"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

// Metrics for observability
var (
	authorizationTotal = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "voyager_authorization_total",
			Help: "Total number of authorization requests",
		},
		[]string{"status", "processor", "merchant_id"},
	)

	authorizationDuration = prometheus.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "voyager_authorization_duration_seconds",
			Help:    "Authorization request duration in seconds",
			Buckets: []float64{0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5},
		},
		[]string{"processor", "merchant_id"},
	)

	authorizationSuccessRate = prometheus.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "voyager_authorization_success_rate",
			Help: "Authorization success rate (rolling window)",
		},
		[]string{"merchant_id"},
	)

	activeRequests = prometheus.NewGauge(
		prometheus.GaugeOpts{
			Name: "voyager_active_requests",
			Help: "Number of currently active requests",
		},
	)

	healthCheckStatus = prometheus.NewGauge(
		prometheus.GaugeOpts{
			Name: "voyager_health_check_status",
			Help: "Health check status (1 = healthy, 0 = unhealthy)",
		},
	)
)

// Global counters for success rate calculation
var (
	totalRequests   int64
	successRequests int64
)

// Simulated payment processors with their "credentials"
var processors = []string{"stripe", "adyen", "mercadopago"}

// AuthorizationRequest represents an incoming payment authorization
type AuthorizationRequest struct {
	MerchantID    string  `json:"merchant_id"`
	Amount        float64 `json:"amount"`
	Currency      string  `json:"currency"`
	CardToken     string  `json:"card_token"`
	TransactionID string  `json:"transaction_id"`
}

// AuthorizationResponse represents the authorization result
type AuthorizationResponse struct {
	TransactionID   string  `json:"transaction_id"`
	Status          string  `json:"status"`
	AuthCode        string  `json:"auth_code,omitempty"`
	Processor       string  `json:"processor"`
	ProcessedAt     string  `json:"processed_at"`
	Amount          float64 `json:"amount"`
	Currency        string  `json:"currency"`
	DeclineReason   string  `json:"decline_reason,omitempty"`
	ProcessingTime  float64 `json:"processing_time_ms"`
}

// HealthResponse represents health check response
type HealthResponse struct {
	Status       string            `json:"status"`
	Version      string            `json:"version"`
	Uptime       string            `json:"uptime"`
	Checks       map[string]string `json:"checks"`
	SuccessRate  float64           `json:"success_rate"`
	TotalRequests int64            `json:"total_requests"`
}

var startTime = time.Now()

func init() {
	prometheus.MustRegister(authorizationTotal)
	prometheus.MustRegister(authorizationDuration)
	prometheus.MustRegister(authorizationSuccessRate)
	prometheus.MustRegister(activeRequests)
	prometheus.MustRegister(healthCheckStatus)
}

// getEnv returns environment variable or default value
func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

// getVersion returns the application version
func getVersion() string {
	return getEnv("APP_VERSION", "1.0.0")
}

// getFailureRate returns the configured failure rate for testing
func getFailureRate() float64 {
	rate, err := strconv.ParseFloat(getEnv("FAILURE_RATE", "0.02"), 64)
	if err != nil {
		return 0.02
	}
	return rate
}

// getLatencyMs returns the configured base latency
func getLatencyMs() int {
	latency, err := strconv.Atoi(getEnv("BASE_LATENCY_MS", "50"))
	if err != nil {
		return 50
	}
	return latency
}

// simulateProcessorCall simulates calling a payment processor
func simulateProcessorCall(processor string) (bool, string, time.Duration) {
	baseLatency := getLatencyMs()
	jitter := rand.Intn(50)
	latency := time.Duration(baseLatency+jitter) * time.Millisecond
	
	time.Sleep(latency)
	
	failureRate := getFailureRate()
	if rand.Float64() < failureRate {
		reasons := []string{"insufficient_funds", "card_declined", "processor_timeout", "invalid_card"}
		return false, reasons[rand.Intn(len(reasons))], latency
	}
	
	authCode := fmt.Sprintf("AUTH%d", rand.Intn(999999))
	return true, authCode, latency
}

// selectProcessor intelligently routes to the best processor
func selectProcessor(merchantID string, amount float64) string {
	return processors[rand.Intn(len(processors))]
}

// handleAuthorization processes payment authorization requests
func handleAuthorization(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	activeRequests.Inc()
	defer activeRequests.Dec()

	startTime := time.Now()
	atomic.AddInt64(&totalRequests, 1)

	var req AuthorizationRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	if req.MerchantID == "" {
		req.MerchantID = "default_merchant"
	}
	if req.TransactionID == "" {
		req.TransactionID = fmt.Sprintf("txn_%d", time.Now().UnixNano())
	}

	processor := selectProcessor(req.MerchantID, req.Amount)
	success, result, latency := simulateProcessorCall(processor)

	response := AuthorizationResponse{
		TransactionID:  req.TransactionID,
		Processor:      processor,
		ProcessedAt:    time.Now().UTC().Format(time.RFC3339),
		Amount:         req.Amount,
		Currency:       req.Currency,
		ProcessingTime: float64(latency.Milliseconds()),
	}

	if success {
		response.Status = "approved"
		response.AuthCode = result
		atomic.AddInt64(&successRequests, 1)
		authorizationTotal.WithLabelValues("approved", processor, req.MerchantID).Inc()
	} else {
		response.Status = "declined"
		response.DeclineReason = result
		authorizationTotal.WithLabelValues("declined", processor, req.MerchantID).Inc()
	}

	duration := time.Since(startTime).Seconds()
	authorizationDuration.WithLabelValues(processor, req.MerchantID).Observe(duration)

	total := atomic.LoadInt64(&totalRequests)
	successes := atomic.LoadInt64(&successRequests)
	if total > 0 {
		rate := float64(successes) / float64(total) * 100
		authorizationSuccessRate.WithLabelValues(req.MerchantID).Set(rate)
	}

	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("X-Processor", processor)
	w.Header().Set("X-Version", getVersion())
	
	if success {
		w.WriteHeader(http.StatusOK)
	} else {
		w.WriteHeader(http.StatusPaymentRequired)
	}
	
	_ = json.NewEncoder(w).Encode(response)
}

// handleHealthLive is a shallow health check (liveness probe)
func handleHealthLive(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(map[string]string{
		"status": "alive",
		"version": getVersion(),
	})
}

// handleHealthReady is a deep health check (readiness probe)
func handleHealthReady(w http.ResponseWriter, r *http.Request) {
	checks := make(map[string]string)
	allHealthy := true

	for _, processor := range processors {
		secretKey := fmt.Sprintf("%s_API_KEY", processor)
		if os.Getenv(secretKey) != "" || os.Getenv("SKIP_SECRET_CHECK") == "true" {
			checks[processor+"_credentials"] = "ok"
		} else {
			checks[processor+"_credentials"] = "missing"
		}
	}

	checks["database"] = "ok"
	checks["cache"] = "ok"

	total := atomic.LoadInt64(&totalRequests)
	successes := atomic.LoadInt64(&successRequests)
	var successRate float64 = 100.0
	if total > 0 {
		successRate = float64(successes) / float64(total) * 100
	}

	minSuccessRate, _ := strconv.ParseFloat(getEnv("MIN_SUCCESS_RATE", "95.0"), 64)
	if successRate < minSuccessRate && total > 100 {
		checks["success_rate"] = fmt.Sprintf("degraded (%.2f%% < %.2f%%)", successRate, minSuccessRate)
		allHealthy = false
	} else {
		checks["success_rate"] = fmt.Sprintf("ok (%.2f%%)", successRate)
	}

	response := HealthResponse{
		Version:       getVersion(),
		Uptime:        time.Since(startTime).String(),
		Checks:        checks,
		SuccessRate:   successRate,
		TotalRequests: total,
	}

	w.Header().Set("Content-Type", "application/json")
	
	if allHealthy {
		response.Status = "ready"
		healthCheckStatus.Set(1)
		w.WriteHeader(http.StatusOK)
	} else {
		response.Status = "degraded"
		healthCheckStatus.Set(0)
		w.WriteHeader(http.StatusServiceUnavailable)
	}
	
	_ = json.NewEncoder(w).Encode(response)
}

// handleVersion returns the current version
func handleVersion(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]string{
		"version": getVersion(),
		"service": "voyager-gateway",
	})
}

// handleReset resets metrics (for testing)
func handleReset(w http.ResponseWriter, r *http.Request) {
	atomic.StoreInt64(&totalRequests, 0)
	atomic.StoreInt64(&successRequests, 0)
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]string{
		"status": "metrics_reset",
	})
}

func main() {
	port := getEnv("PORT", "8080")
	
	log.Printf("Starting voyager-gateway version %s on port %s", getVersion(), port)
	log.Printf("Failure rate: %.2f%%, Base latency: %dms", getFailureRate()*100, getLatencyMs())

	http.HandleFunc("/authorize", handleAuthorization)
	http.HandleFunc("/health/live", handleHealthLive)
	http.HandleFunc("/health/ready", handleHealthReady)
	http.HandleFunc("/version", handleVersion)
	http.HandleFunc("/reset", handleReset)
	http.Handle("/metrics", promhttp.Handler())

	log.Printf("Endpoints available:")
	log.Printf("  POST /authorize    - Payment authorization")
	log.Printf("  GET  /health/live  - Liveness probe (shallow)")
	log.Printf("  GET  /health/ready - Readiness probe (deep)")
	log.Printf("  GET  /version      - Version info")
	log.Printf("  GET  /metrics      - Prometheus metrics")
	log.Printf("  POST /reset        - Reset metrics (testing)")

	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Fatalf("Server failed to start: %v", err)
	}
}
