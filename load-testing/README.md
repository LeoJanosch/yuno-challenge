# Load Testing for Voyager Gateway

This directory contains k6 load testing scripts to simulate Black Friday traffic patterns.

## Prerequisites

1. Install k6: https://k6.io/docs/getting-started/installation/

```bash
# macOS
brew install k6

# Linux
sudo gpg -k
sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | sudo tee /etc/apt/sources.list.d/k6.list
sudo apt-get update
sudo apt-get install k6
```

## Running Tests

### Quick Test (Local)

```bash
# Start the service first
docker-compose up -d voyager-gateway

# Run load test
k6 run load-test.js
```

### Against Staging/Production

```bash
# Set the target URL
export BASE_URL=https://gateway-staging.yuno.co

# Run with specific scenario
k6 run --env BASE_URL=$BASE_URL load-test.js
```

### Specific Scenarios

```bash
# Normal traffic only (2 minutes)
k6 run --env BASE_URL=http://localhost:8080 \
  --scenario normal_traffic \
  load-test.js

# Peak load only (5 minutes)
k6 run --env BASE_URL=http://localhost:8080 \
  --scenario peak_load \
  load-test.js

# Spike test only
k6 run --env BASE_URL=http://localhost:8080 \
  --scenario spike_test \
  load-test.js
```

## Test Scenarios

| Scenario | Description | Duration | Rate |
|----------|-------------|----------|------|
| `normal_traffic` | Baseline traffic | 2m | 1K req/s |
| `traffic_ramp` | Gradual ramp-up | 6m | 1K → 3K req/s |
| `peak_load` | Sustained peak | 5m | 3K req/s |
| `spike_test` | Sudden burst | 1m | 5K req/s spike |

## SLO Thresholds

The tests verify these SLOs:

- **Success Rate**: > 99%
- **P99 Latency**: < 500ms
- **Error Rate**: < 1%

## Interpreting Results

```
📊 SLO COMPLIANCE:
----------------------------------------
  ✅ Success Rate: 99.87% (SLO: 99%)
  ✅ P99 Latency: 234.56ms (SLO: 500ms)

📈 TRAFFIC SUMMARY:
----------------------------------------
  Total Requests: 1,234,567
  Approved: 1,210,000
  Declined: 24,567
```

## Scaling for Production Load

To simulate full Black Friday load (45K req/s), you need multiple k6 instances:

```bash
# Use k6 cloud or distributed execution
k6 cloud run load-test.js

# Or run multiple local instances
for i in {1..10}; do
  k6 run --env BASE_URL=$BASE_URL load-test.js &
done
wait
```

## Output Files

- `load-test-results.json` - Full metrics in JSON format
- Console output with summary statistics
