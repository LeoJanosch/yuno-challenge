#!/bin/bash
# Manual rollback script for Voyager Gateway
# Use this when automatic rollback hasn't triggered or for emergency rollback

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

NAMESPACE="${NAMESPACE:-voyager}"
ROLLOUT_NAME="${ROLLOUT_NAME:-voyager-gateway}"

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║          VOYAGER GATEWAY - MANUAL ROLLBACK                ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}❌ kubectl is not installed${NC}"
    exit 1
fi

# Check if argo rollouts plugin is available
if ! kubectl argo rollouts version &> /dev/null; then
    echo -e "${YELLOW}⚠️ Argo Rollouts kubectl plugin not found${NC}"
    echo "Installing..."
    curl -LO https://github.com/argoproj/argo-rollouts/releases/latest/download/kubectl-argo-rollouts-linux-amd64
    chmod +x kubectl-argo-rollouts-linux-amd64
    sudo mv kubectl-argo-rollouts-linux-amd64 /usr/local/bin/kubectl-argo-rollouts
fi

echo "📊 Current rollout status:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
kubectl argo rollouts get rollout $ROLLOUT_NAME -n $NAMESPACE || true
echo ""

echo -e "${YELLOW}⚠️ This will rollback to the previous stable version.${NC}"
echo ""
read -p "Are you sure you want to rollback? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Rollback cancelled."
    exit 0
fi

echo ""
echo "🔄 Initiating rollback..."

# Abort any in-progress rollout
echo "  → Aborting current rollout..."
kubectl argo rollouts abort $ROLLOUT_NAME -n $NAMESPACE 2>/dev/null || true

# Undo to previous version
echo "  → Rolling back to previous version..."
kubectl argo rollouts undo $ROLLOUT_NAME -n $NAMESPACE

echo ""
echo "⏳ Waiting for rollback to complete..."
kubectl argo rollouts status $ROLLOUT_NAME -n $NAMESPACE --timeout 5m

echo ""
echo -e "${GREEN}✅ Rollback completed successfully!${NC}"
echo ""

echo "📊 New rollout status:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
kubectl argo rollouts get rollout $ROLLOUT_NAME -n $NAMESPACE

echo ""
echo "🔍 Verifying service health..."
kubectl exec -n $NAMESPACE deploy/$ROLLOUT_NAME -- wget -qO- http://localhost:8080/health/ready | jq . 2>/dev/null || echo "Health check endpoint response received"

echo ""
echo -e "${GREEN}Rollback complete. Monitor the dashboard for stabilization.${NC}"
