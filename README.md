# Voyager Gateway - Zero-Downtime Deployment Infrastructure

**Challenge:** Design and implement deployment infrastructure for Yuno's core payment authorization service that can handle Black Friday traffic (45K req/sec) with zero customer-visible downtime.

## Quick Start

### Prerequisites

- Docker & Docker Compose
- kubectl (for Kubernetes deployment)
- Terraform >= 1.0 (for IaC)
- k6 (for load testing) - `brew install k6`

### Local Development

```bash
# 1. Clone and start services
git clone <repository-url>
cd voyager-gateway

# 2. Deploy locally with Docker Compose
./scripts/deploy-local.sh

# 3. Verify deployment
curl http://localhost:8080/health/ready

# 4. Access dashboards
# Voyager Gateway: http://localhost:8080
# Prometheus:      http://localhost:9090
# Grafana:         http://localhost:3000 (admin/admin)
```

### Test Authorization Endpoint

```bash
curl -X POST http://localhost:8080/authorize \
  -H "Content-Type: application/json" \
  -d '{
    "merchant_id": "merchant_001",
    "amount": 99.99,
    "currency": "USD",
    "card_token": "tok_test_123",
    "transaction_id": "txn_001"
  }'
```

## Project Structure

```
voyager-gateway/
├── app/                          # Go payment gateway service
│   ├── main.go                   # Application code
│   ├── Dockerfile                # Container definition
│   └── go.mod                    # Dependencies
├── infrastructure/               # Terraform IaC
│   ├── modules/
│   │   ├── networking/           # VPC, subnets, security groups
│   │   ├── kubernetes/           # EKS cluster configuration
│   │   ├── secrets/              # AWS Secrets Manager
│   │   └── monitoring/           # CloudWatch dashboards/alarms
│   └── environments/
│       ├── dev/                  # Development environment
│       └── prod/                 # Production environment
├── kubernetes/                   # Kubernetes manifests
│   ├── base/                     # Core resources
│   ├── canary/                   # Argo Rollouts configuration
│   └── monitoring/               # Prometheus/Grafana configs
├── .github/workflows/            # CI/CD pipeline
│   └── deploy.yaml               # GitHub Actions workflow
├── load-testing/                 # k6 load test scripts
├── scripts/                      # Helper scripts
├── docker-compose.yml            # Local development
├── README.md                     # This file
└── DECISIONS.md                  # Design decisions document
```

## Deployment Guide

### Option 1: Local Docker Compose (Development)

```bash
# Start all services
docker-compose up -d

# View logs
docker-compose logs -f voyager-gateway

# Stop services
docker-compose down
```

### Option 2: Kubernetes with Argo Rollouts (Production)

#### 1. Deploy Infrastructure with Terraform

```bash
cd infrastructure/environments/prod

# Initialize Terraform
terraform init

# Review the plan
terraform plan -var-file="secrets.tfvars"

# Apply infrastructure
terraform apply -var-file="secrets.tfvars"

# Get kubeconfig
aws eks update-kubeconfig --region us-east-1 --name prod-voyager-cluster
```

#### 2. Install Argo Rollouts

```bash
# Install Argo Rollouts controller
kubectl create namespace argo-rollouts
kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml

# Install kubectl plugin
brew install argoproj/tap/kubectl-argo-rollouts
```

#### 3. Deploy Application

```bash
# Create namespace and apply manifests
kubectl apply -f kubernetes/base/namespace.yaml
kubectl apply -f kubernetes/base/
kubectl apply -f kubernetes/canary/
kubectl apply -f kubernetes/monitoring/
```

#### 4. Trigger a Deployment

```bash
# Update image to trigger canary rollout
kubectl argo rollouts set image voyager-gateway \
  voyager-gateway=ghcr.io/yuno/voyager-gateway:v2.0.0 \
  -n voyager

# Watch the rollout progress
kubectl argo rollouts get rollout voyager-gateway -n voyager -w
```

## Monitoring & Observability

### Dashboards

| Dashboard | URL | Purpose |
|-----------|-----|---------|
| Grafana | http://localhost:3000 | Business metrics, SLOs |
| Prometheus | http://localhost:9090 | Raw metrics, queries |
| Voyager Metrics | http://localhost:8080/metrics | Application metrics |

### Key Metrics

| Metric | Description | SLO Target |
|--------|-------------|------------|
| `voyager_authorization_total` | Total authorization requests | - |
| `voyager_authorization_duration_seconds` | Request latency histogram | P99 < 500ms |
| `voyager_authorization_success_rate` | Success rate gauge | > 99.9% |
| `voyager_active_requests` | Current in-flight requests | - |

### Alerts

Alerts fire **before** SLO violation to allow proactive response:

| Alert | Condition | Severity |
|-------|-----------|----------|
| `VoyagerSuccessRateSLOWarning` | Success rate < 99.5% | Warning |
| `VoyagerSuccessRateSLOCritical` | Success rate < 99% | Critical |
| `VoyagerLatencyP99Warning` | P99 latency > 400ms | Warning |
| `VoyagerLatencyP99Critical` | P99 latency > 500ms | Critical |

## Canary Deployment Strategy

The deployment uses a progressive canary rollout:

```
5% → (2min + analysis) → 10% → (2min + analysis) → 25% → (3min + analysis) 
   → 50% → (5min + analysis) → 75% → (5min + analysis) → 100%
```

### Health Signals Checked

1. **Success Rate**: Must remain ≥ 99%
2. **P99 Latency**: Must remain < 500ms
3. **Error Rate**: Must remain < 5%
4. **Processor Timeouts**: Must remain < 1%

### Rollback Triggers

Automatic rollback occurs when:
- Success rate drops below 98%
- P99 latency exceeds 800ms
- Health check fails 3 consecutive times
- Any analysis step fails

## Simulating Failure Scenarios

### Simulate a Bad Deployment

```bash
./scripts/simulate-failure.sh
# Select option 5: "Deploy bad version"
```

### Watch Automatic Rollback

```bash
# Terminal 1: Watch rollout
kubectl argo rollouts get rollout voyager-gateway -n voyager -w

# Terminal 2: Watch analysis
kubectl get analysisrun -n voyager -w

# Terminal 3: Watch pods
kubectl get pods -n voyager -w
```

### Manual Rollback

```bash
# Using script
./scripts/rollback.sh

# Or directly with kubectl
kubectl argo rollouts abort voyager-gateway -n voyager
kubectl argo rollouts undo voyager-gateway -n voyager
```

## Load Testing

```bash
cd load-testing

# Quick test (local)
k6 run load-test.js

# Test against staging
BASE_URL=https://gateway-staging.yuno.co k6 run load-test.js

# Run specific scenario
k6 run --scenario peak_load load-test.js
```

### Traffic Scenarios

| Scenario | Rate | Duration | Purpose |
|----------|------|----------|---------|
| `normal_traffic` | 1K req/s | 2m | Baseline |
| `traffic_ramp` | 1K→3K req/s | 6m | Black Friday start |
| `peak_load` | 3K req/s | 5m | Sustained peak |
| `spike_test` | 5K req/s burst | 1m | Sudden traffic spike |

## Secrets Management

### Rotation Without Downtime

Secrets are managed via AWS Secrets Manager with External Secrets Operator:

```yaml
# kubernetes/base/external-secret.yaml
spec:
  refreshInterval: 1m  # Secrets refresh every minute
```

When a secret is rotated in AWS:
1. External Secrets Operator detects the change
2. Kubernetes Secret is updated
3. Pods receive new secret values (via volume mount or env reload)
4. No restart required

### Adding New Processor Credentials

```bash
# 1. Add secret to AWS Secrets Manager
aws secretsmanager create-secret \
  --name prod/voyager-gateway/new-processor \
  --secret-string '{"api_key":"xxx","webhook_secret":"yyy"}'

# 2. Update ExternalSecret manifest
# 3. Apply changes - no pod restart needed
```

## CI/CD Pipeline

The GitHub Actions workflow (`/.github/workflows/deploy.yaml`) provides:

1. **Build & Test**: Go tests, linting, Docker build
2. **Security Scan**: Trivy (container), Checkov (IaC)
3. **Deploy Dev**: Automatic on main branch
4. **Deploy Staging**: After dev success
5. **Deploy Prod**: Manual approval + canary rollout

### Triggering Deployment

```bash
# Automatic (push to main)
git push origin main

# Manual (specific environment)
gh workflow run deploy.yaml -f environment=prod
```

## Cost Optimization

### Autoscaling Configuration

| Time Period | Min Pods | Max Pods | Target CPU |
|-------------|----------|----------|------------|
| Normal | 5 | 15 | 70% |
| Black Friday | 20 | 100 | 60% |

### Estimated Costs (AWS us-east-1)

| Component | Normal Load | Black Friday Peak |
|-----------|-------------|-------------------|
| EKS Cluster | $73/month | $73/month |
| EC2 Nodes (t3.xlarge) | $450/month (5 nodes) | $2,700/month (30 nodes) |
| NAT Gateway | $32/month | $32/month |
| Load Balancer | $20/month | $20/month |
| **Total** | ~$575/month | ~$2,825/month |

## Troubleshooting

### Service Not Responding

```bash
# Check pod status
kubectl get pods -n voyager

# Check pod logs
kubectl logs -l app=voyager-gateway -n voyager --tail=100

# Check health endpoint
kubectl exec -n voyager deploy/voyager-gateway -- wget -qO- http://localhost:8080/health/ready
```

### Rollout Stuck

```bash
# Check rollout status
kubectl argo rollouts get rollout voyager-gateway -n voyager

# Check analysis runs
kubectl get analysisrun -n voyager

# Force abort and retry
kubectl argo rollouts abort voyager-gateway -n voyager
kubectl argo rollouts retry rollout voyager-gateway -n voyager
```

### High Error Rate

1. Check Grafana dashboard for error patterns
2. Review processor-specific metrics
3. Check if specific merchant is affected
4. Review recent deployments

```bash
# Check recent deployments
kubectl argo rollouts history voyager-gateway -n voyager

# Rollback if needed
kubectl argo rollouts undo voyager-gateway -n voyager
```

## API Reference

### POST /authorize

Authorization request endpoint.

**Request:**
```json
{
  "merchant_id": "string",
  "amount": 99.99,
  "currency": "USD",
  "card_token": "string",
  "transaction_id": "string"
}
```

**Response (200 - Approved):**
```json
{
  "transaction_id": "txn_001",
  "status": "approved",
  "auth_code": "AUTH123456",
  "processor": "stripe",
  "processed_at": "2024-11-10T15:30:00Z",
  "amount": 99.99,
  "currency": "USD",
  "processing_time_ms": 45.5
}
```

**Response (402 - Declined):**
```json
{
  "transaction_id": "txn_001",
  "status": "declined",
  "decline_reason": "insufficient_funds",
  "processor": "stripe",
  "processed_at": "2024-11-10T15:30:00Z"
}
```

### GET /health/live

Liveness probe (shallow check).

### GET /health/ready

Readiness probe (deep check with dependency verification).

### GET /metrics

Prometheus metrics endpoint.

## License

Internal use only - Yuno Platform Engineering Challenge
