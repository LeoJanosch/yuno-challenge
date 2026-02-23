#!/bin/bash
# Simulate failure scenarios for Voyager Gateway
# Used to demonstrate automated rollback and alerting

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

BASE_URL="${BASE_URL:-http://localhost:8080}"

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║         VOYAGER GATEWAY - FAILURE SIMULATION              ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

show_menu() {
    echo "Select a failure scenario to simulate:"
    echo ""
    echo "  1) High latency (slow responses)"
    echo "  2) High error rate (increased failures)"
    echo "  3) Service degradation (partial failure)"
    echo "  4) Reset to normal operation"
    echo "  5) Deploy bad version (triggers rollback)"
    echo "  6) Exit"
    echo ""
}

simulate_high_latency() {
    echo -e "${YELLOW}🐌 Simulating high latency...${NC}"
    
    # In a real scenario, this would update environment variables
    # For local testing, we restart with different config
    docker-compose stop voyager-gateway
    BASE_LATENCY_MS=2000 docker-compose up -d voyager-gateway
    
    echo "Service restarted with 2000ms base latency"
    echo ""
    echo "Monitor the Grafana dashboard to see P99 latency increase:"
    echo "  http://localhost:3000/d/voyager-gateway"
    echo ""
    echo "This should trigger:"
    echo "  • VoyagerLatencyP99Warning alert"
    echo "  • VoyagerLatencyP99Critical alert (if sustained)"
    echo ""
}

simulate_high_error_rate() {
    echo -e "${RED}💥 Simulating high error rate...${NC}"
    
    docker-compose stop voyager-gateway
    FAILURE_RATE=0.15 docker-compose up -d voyager-gateway
    
    echo "Service restarted with 15% failure rate"
    echo ""
    echo "Monitor the Grafana dashboard to see success rate drop:"
    echo "  http://localhost:3000/d/voyager-gateway"
    echo ""
    echo "This should trigger:"
    echo "  • VoyagerSuccessRateSLOWarning alert"
    echo "  • VoyagerSuccessRateSLOCritical alert"
    echo ""
}

simulate_degradation() {
    echo -e "${YELLOW}⚠️ Simulating service degradation...${NC}"
    
    docker-compose stop voyager-gateway
    FAILURE_RATE=0.08 BASE_LATENCY_MS=500 docker-compose up -d voyager-gateway
    
    echo "Service restarted with moderate degradation:"
    echo "  • 8% failure rate"
    echo "  • 500ms base latency"
    echo ""
    echo "This simulates a partially degraded state that approaches SLO boundaries."
    echo ""
}

reset_to_normal() {
    echo -e "${GREEN}✅ Resetting to normal operation...${NC}"
    
    docker-compose down voyager-gateway
    docker-compose up -d voyager-gateway
    
    echo "Service restarted with default configuration:"
    echo "  • 2% failure rate"
    echo "  • 50ms base latency"
    echo ""
    
    # Reset metrics
    curl -s -X POST "$BASE_URL/reset" > /dev/null 2>&1 || true
    echo "Metrics reset."
}

simulate_bad_deployment() {
    echo -e "${RED}🚨 Simulating bad deployment...${NC}"
    echo ""
    echo "This scenario demonstrates the canary rollback process."
    echo ""
    echo "In a real Kubernetes environment with Argo Rollouts:"
    echo ""
    echo "1. A new version with FAILURE_RATE=0.5 would be deployed"
    echo "2. Canary analysis would detect the high error rate"
    echo "3. Rollout would be automatically aborted"
    echo "4. Traffic would be shifted back to the stable version"
    echo ""
    echo "To simulate locally:"
    echo ""
    echo "# Terminal 1: Watch the rollout"
    echo "kubectl argo rollouts get rollout voyager-gateway -n voyager -w"
    echo ""
    echo "# Terminal 2: Deploy bad version"
    echo "kubectl argo rollouts set image voyager-gateway \\"
    echo "  voyager-gateway=voyager-gateway:bad-version -n voyager"
    echo ""
    echo "# Terminal 3: Watch analysis"
    echo "kubectl get analysisrun -n voyager -w"
    echo ""
    
    # For local docker demonstration
    echo "For local Docker demonstration, running degraded version..."
    docker-compose stop voyager-gateway
    FAILURE_RATE=0.5 APP_VERSION=2.0.0-bad docker-compose up -d voyager-gateway
    
    echo ""
    echo "Bad version deployed. Check metrics at:"
    echo "  http://localhost:8080/health/ready"
    echo "  http://localhost:3000/d/voyager-gateway"
    echo ""
    echo -e "${YELLOW}Note: In production, Argo Rollouts would automatically rollback.${NC}"
    echo "To manually rollback, run: ./scripts/simulate-failure.sh and select option 4"
}

# Main loop
while true; do
    show_menu
    read -p "Enter your choice [1-6]: " choice
    echo ""
    
    case $choice in
        1) simulate_high_latency ;;
        2) simulate_high_error_rate ;;
        3) simulate_degradation ;;
        4) reset_to_normal ;;
        5) simulate_bad_deployment ;;
        6) echo "Exiting..."; exit 0 ;;
        *) echo -e "${RED}Invalid option${NC}" ;;
    esac
    
    echo ""
    read -p "Press Enter to continue..."
    echo ""
done
