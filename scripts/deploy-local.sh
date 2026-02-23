#!/bin/bash
# Local deployment script for Voyager Gateway
# This script sets up the complete local environment for testing

set -e

echo "🚀 Deploying Voyager Gateway locally..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check prerequisites
check_prerequisites() {
    echo "📋 Checking prerequisites..."
    
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}❌ Docker is not installed${NC}"
        exit 1
    fi
    
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        echo -e "${RED}❌ Docker Compose is not installed${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ All prerequisites met${NC}"
}

# Build the application
build_app() {
    echo "🔨 Building Voyager Gateway..."
    docker-compose build voyager-gateway
    echo -e "${GREEN}✅ Build complete${NC}"
}

# Start services
start_services() {
    echo "🚀 Starting services..."
    docker-compose up -d
    echo -e "${GREEN}✅ Services started${NC}"
}

# Wait for service to be healthy
wait_for_health() {
    echo "⏳ Waiting for service to be healthy..."
    
    max_attempts=30
    attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if curl -s http://localhost:8080/health/ready > /dev/null 2>&1; then
            echo -e "${GREEN}✅ Service is healthy${NC}"
            return 0
        fi
        
        attempt=$((attempt + 1))
        echo "  Attempt $attempt/$max_attempts..."
        sleep 2
    done
    
    echo -e "${RED}❌ Service failed to become healthy${NC}"
    exit 1
}

# Show status
show_status() {
    echo ""
    echo "📊 Service Status:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    echo ""
    echo "🌐 Endpoints:"
    echo "  • Voyager Gateway: http://localhost:8080"
    echo "  • Health Check:    http://localhost:8080/health/ready"
    echo "  • Metrics:         http://localhost:8080/metrics"
    echo "  • Prometheus:      http://localhost:9090"
    echo "  • Grafana:         http://localhost:3000 (admin/admin)"
    echo ""
    
    # Show health status
    echo "📈 Health Check:"
    curl -s http://localhost:8080/health/ready | jq . 2>/dev/null || echo "Service not responding"
    echo ""
}

# Test authorization endpoint
test_authorization() {
    echo "🧪 Testing authorization endpoint..."
    
    response=$(curl -s -X POST http://localhost:8080/authorize \
        -H "Content-Type: application/json" \
        -d '{
            "merchant_id": "test_merchant",
            "amount": 99.99,
            "currency": "USD",
            "card_token": "tok_test_123",
            "transaction_id": "txn_test_001"
        }')
    
    echo "Response:"
    echo "$response" | jq . 2>/dev/null || echo "$response"
    echo ""
    
    status=$(echo "$response" | jq -r '.status' 2>/dev/null)
    if [ "$status" == "approved" ] || [ "$status" == "declined" ]; then
        echo -e "${GREEN}✅ Authorization test passed${NC}"
    else
        echo -e "${YELLOW}⚠️ Unexpected response${NC}"
    fi
}

# Main execution
main() {
    echo ""
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║           VOYAGER GATEWAY - LOCAL DEPLOYMENT              ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo ""
    
    check_prerequisites
    build_app
    start_services
    wait_for_health
    show_status
    test_authorization
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${GREEN}🎉 Deployment complete!${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. View metrics: http://localhost:3000"
    echo "  2. Run load tests: cd load-testing && k6 run load-test.js"
    echo "  3. Stop services: docker-compose down"
    echo ""
}

main "$@"
