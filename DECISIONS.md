# Design Decisions

This document explains the key architectural and implementation decisions made for the Voyager Gateway deployment infrastructure.

## Table of Contents

1. [Deployment Strategy](#deployment-strategy)
2. [Infrastructure as Code](#infrastructure-as-code)
3. [Secrets Management](#secrets-management)
4. [Observability & SLOs](#observability--slos)
5. [Failure Handling](#failure-handling)
6. [Tool Choices](#tool-choices)
7. [Trade-offs & Future Improvements](#trade-offs--future-improvements)

---

## Deployment Strategy

### Decision: Canary Deployment with Argo Rollouts

**Choice:** Canary deployment (5% → 10% → 25% → 50% → 75% → 100%)

**Alternatives Considered:**

| Strategy | Pros | Cons |
|----------|------|------|
| **Blue-Green** | Instant rollback, simple | 2x infrastructure cost, no gradual validation |
| **Rolling** | Simple, no extra infra | No traffic-percentage validation, slow rollback |
| **Canary** | Gradual validation, minimal blast radius | More complex, longer deploy time |

**Why Canary?**

Given Yuno's requirements—a high-traffic payment service (45K req/sec) that cannot tolerate customer-visible errors but needs to deploy multiple times per day—canary deployment provides the best balance:

1. **Minimizes Blast Radius**: At 5% traffic, even a catastrophic bug affects only ~2,250 req/sec initially, compared to 22,500 req/sec with 50% blue-green switch.

2. **Business Metric Validation**: Each canary step includes automated analysis of success rate and latency, not just "is the pod running."

3. **Fast Rollback**: Argo Rollouts can abort and rollback in seconds when analysis fails, much faster than the 3-minute manual rollback from the 2023 incident.

4. **Cost Efficiency**: Unlike blue-green, we don't need to maintain 2x infrastructure permanently.

5. **Multiple Daily Deploys**: The gradual rollout (~20 minutes total) allows multiple deploys per day while maintaining safety.

### Canary Step Configuration

```
Step 1: 5%  traffic → 2 min pause + analysis
Step 2: 10% traffic → 2 min pause + analysis  
Step 3: 25% traffic → 3 min pause + analysis
Step 4: 50% traffic → 5 min pause + analysis
Step 5: 75% traffic → 5 min pause + analysis
Step 6: 100% traffic → 2 min final validation
```

**Rationale:**
- Early steps (5%, 10%) have shorter pauses to quickly catch obvious failures
- Later steps (50%, 75%) have longer pauses as more traffic means more confidence needed
- Total deployment time: ~20 minutes (acceptable for multiple daily deploys)

---

## Infrastructure as Code

### Decision: Terraform with Modular Structure

**Why Terraform?**

1. **Industry Standard**: Well-documented, large community, extensive provider support
2. **State Management**: Built-in state tracking for drift detection
3. **Multi-Cloud Ready**: Can extend to GCP/Azure if needed
4. **Modular**: Supports reusable modules for DRY infrastructure

### Module Structure

```
infrastructure/
├── modules/
│   ├── networking/     # VPC, subnets, security groups
│   ├── kubernetes/     # EKS cluster, node groups
│   ├── secrets/        # Secrets Manager, KMS
│   └── monitoring/     # CloudWatch dashboards, alarms
└── environments/
    ├── dev/            # Development (smaller, cheaper)
    └── prod/           # Production (HA, multi-AZ)
```

**Why This Structure?**

1. **Reusability**: Same modules for dev/staging/prod with different parameters
2. **Separation of Concerns**: Each module handles one domain
3. **Team Ownership**: Different teams can own different modules
4. **Blast Radius**: Changes to monitoring don't affect networking

### Network Design

```
VPC (10.0.0.0/16)
├── Public Subnets (ALB, NAT Gateway)
│   ├── us-east-1a: 10.0.0.0/20
│   ├── us-east-1b: 10.0.16.0/20
│   └── us-east-1c: 10.0.32.0/20
└── Private Subnets (EKS nodes, payment service)
    ├── us-east-1a: 10.0.48.0/20
    ├── us-east-1b: 10.0.64.0/20
    └── us-east-1c: 10.0.80.0/20
```

**PCI-DSS Considerations:**
- Payment service in private subnets (not directly internet-accessible)
- Security groups restrict traffic to necessary ports only
- All data encrypted in transit (TLS) and at rest (KMS)

---

## Secrets Management

### Decision: AWS Secrets Manager + External Secrets Operator

**Why Not Kubernetes Secrets Alone?**

1. **Rotation**: K8s secrets require pod restart for rotation
2. **Encryption**: K8s secrets are base64 encoded, not encrypted at rest by default
3. **Audit**: AWS Secrets Manager provides CloudTrail audit logs
4. **Access Control**: IAM policies provide fine-grained access control

### Rotation Without Downtime

```yaml
# External Secrets configuration
spec:
  refreshInterval: 1m  # Check for updates every minute
  target:
    creationPolicy: Owner
```

**Flow:**
1. Secret rotated in AWS Secrets Manager (via Lambda or manual)
2. External Secrets Operator detects change within 1 minute
3. Kubernetes Secret updated
4. Application reads new secret (via env var or file watch)
5. No pod restart needed

### Mock Processor Credentials

For this exercise, I've configured three mock processors:
- **Stripe**: `prod/voyager-gateway/stripe`
- **Adyen**: `prod/voyager-gateway/adyen`
- **MercadoPago**: `prod/voyager-gateway/mercadopago`

Each stores:
- API key
- Webhook secret (where applicable)
- Merchant account ID

---

## Observability & SLOs

### SLO Definition

**Primary SLO:** 99.9% of authorization requests complete successfully with P99 latency under 500ms, measured over any 5-minute window.

**Why This SLO?**

1. **99.9% Success Rate**: 
   - At 45K req/sec, 99.9% means ~45 failures/second max
   - This allows for normal processor declines without alerting
   - Lower than 99.9% indicates a systemic issue, not normal business

2. **500ms P99 Latency**:
   - Payment UX research shows abandonment increases significantly >1s
   - 500ms gives headroom for processor latency variance
   - P99 (not P50) catches tail latency issues that affect real users

### Multi-Level Observability

The dashboard is designed for rapid incident diagnosis:

| Section | Answers | Metrics |
|---------|---------|---------|
| **SLO Overview** | Are we meeting SLOs? | Success rate gauge, P99 latency gauge |
| **Business Metrics** | Is the problem in our code? | Authorization trends, declines by processor |
| **Infrastructure** | Is it a capacity issue? | CPU, Memory, Pod count |
| **Processor Health** | Is a processor down? | Throughput by processor, timeout rates |

### Alert Timing

Alerts fire **before** SLO violation:

```
SLO Target: 99.9%
├── Warning Alert: 99.5% (0.4% buffer)
└── Critical Alert: 99.0% (0.9% buffer)
```

**Why?** On Black Friday at 11:30 PM, we want to know about degradation while there's still time to act, not after merchants are already impacted.

---

## Failure Handling

### Scenario 1: New Deployment Introduces a Bug

**Detection:**
- Canary analysis checks success rate every 30 seconds
- If success rate < 98% for 2 consecutive checks, analysis fails

**Response:**
1. Argo Rollouts automatically aborts the rollout
2. Canary pods are scaled down
3. All traffic returns to stable version
4. Alert sent to on-call engineer
5. **Time to recovery: < 30 seconds**

### Scenario 2: Payment Processor API Goes Down

**Detection:**
- `VoyagerProcessorTimeouts` alert fires when timeout rate > 5%
- `VoyagerProcessorDown` alert fires when no traffic to processor for 5 min

**Response:**
1. Alert notifies on-call engineer
2. Dashboard shows which processor is affected
3. Engineer can:
   - Disable processor routing (if configurable)
   - Check processor status page
   - Contact processor support
4. **No automatic action** - processor issues don't trigger rollback (it's not our code)

### Scenario 3: Availability Zone Failure

**Detection:**
- Kubernetes node health checks fail
- Pod Disruption Budget prevents cascade

**Response:**
1. Kubernetes reschedules pods to healthy AZs
2. HPA may scale up to compensate
3. ALB health checks route traffic away from unhealthy pods
4. **Time to recovery: 1-2 minutes** (pod startup time)

**Mitigation:**
- Pods spread across 3 AZs via `topologySpreadConstraints`
- PodDisruptionBudget ensures 80% minimum availability
- Node groups in multiple AZs

---

## Tool Choices

### Infrastructure Stack Justification

| Component | Choice | Justification |
|-----------|--------|---------------|
| **Cloud** | AWS | Most common, well-documented, native EKS/Secrets Manager integration |
| **Orchestration** | Kubernetes (EKS) | Industry standard for high-traffic services, excellent ecosystem |
| **Deployment** | Argo Rollouts | Best-in-class canary/blue-green, native K8s, Prometheus integration |
| **IaC** | Terraform | Industry standard, modular, multi-cloud capable |
| **CI/CD** | GitHub Actions | Native GitHub integration, simple YAML, good secrets handling |
| **Secrets** | AWS Secrets Manager + ESO | Rotation support, audit logs, K8s integration |
| **Monitoring** | Prometheus + Grafana | De facto standard, excellent K8s integration, free |
| **Load Testing** | k6 | Modern, scriptable, good reporting, Grafana integration |

### Why Not...

**Istio for traffic splitting?**
- Added complexity for this use case
- Argo Rollouts + Nginx Ingress achieves same result with less overhead
- Could be added later for service mesh benefits

**CloudWatch instead of Prometheus?**
- Prometheus has better K8s integration
- More flexible query language (PromQL)
- Argo Rollouts has native Prometheus support for analysis
- CloudWatch still used for infrastructure-level monitoring

**ArgoCD instead of GitHub Actions?**
- GitHub Actions simpler for this scope
- ArgoCD would be better for GitOps at scale
- Could be added as the platform grows

---

## Trade-offs & Future Improvements

### Trade-offs Due to Time Constraints

1. **Single Region**: Production would need multi-region for true HA
2. **Mock Service**: Real payment gateway would need actual processor integration
3. **Simplified Terraform**: Production would need remote state, workspaces, more modules
4. **Basic Load Testing**: Production would need distributed load testing infrastructure
5. **Manual Approval**: Could add more sophisticated approval gates (Slack, PagerDuty)

### Production Improvements

If I had more time, I would add:

1. **Multi-Region Failover** (Stretch Goal)
   - Deploy to us-east-1 and us-west-2
   - Route53 health checks for automatic failover
   - Cross-region database replication

2. **Enhanced Security**
   - Network policies for pod-to-pod traffic
   - Pod Security Standards enforcement
   - Regular vulnerability scanning in CI/CD
   - Secrets rotation Lambda function

3. **Cost Optimization**
   - Spot instances for non-critical workloads
   - Cluster autoscaler for node scaling
   - Reserved instances for baseline capacity

4. **Observability Enhancements**
   - Distributed tracing (Jaeger/X-Ray)
   - Log aggregation (Loki/CloudWatch Logs)
   - Error tracking (Sentry)
   - SLO dashboards with error budget burn rate

5. **Chaos Engineering**
   - Chaos Monkey for random pod termination
   - Litmus for controlled chaos experiments
   - Regular game days before Black Friday

### What I Would Do Differently in Production

1. **More Analysis Metrics**: Add business-specific metrics (e.g., success rate by merchant tier, latency by transaction amount)

2. **Canary Comparison**: Compare canary metrics against stable version, not just thresholds (relative vs absolute)

3. **Feature Flags**: Integrate with LaunchDarkly/Unleash for feature-level rollouts independent of deployment

4. **Database Migrations**: Add migration step with rollback capability

5. **Dependency Health**: Add circuit breakers for processor calls, health checks for downstream dependencies

---

## Summary

This solution addresses the core requirements from the Black Friday 2023 incident:

| Root Cause | Solution |
|------------|----------|
| "Kill-and-replace" deployment | Canary rollout with gradual traffic shift |
| No health checking between stages | Automated analysis at each canary step |
| Only infrastructure metrics | Business metrics (success rate, latency) in analysis |
| Configuration error at 100% traffic | Caught at 5% traffic with automated rollback |
| 3-minute manual rollback | < 30 second automatic rollback |

The infrastructure is designed to handle 45K req/sec Black Friday traffic with zero customer-visible downtime, while allowing multiple deployments per day with confidence.
