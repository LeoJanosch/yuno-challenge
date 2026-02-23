// k6 Load Testing Script for Voyager Gateway
// Simulates Black Friday traffic patterns (up to 45K req/sec)

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter, Rate, Trend } from 'k6/metrics';
import { randomItem, randomIntBetween } from 'https://jslib.k6.io/k6-utils/1.2.0/index.js';

// Custom metrics
const authorizationSuccessRate = new Rate('authorization_success_rate');
const authorizationLatency = new Trend('authorization_latency', true);
const authorizationTotal = new Counter('authorization_total');
const authorizationApproved = new Counter('authorization_approved');
const authorizationDeclined = new Counter('authorization_declined');

// Test configuration
const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';

// Test data
const MERCHANTS = [
  'merchant_001', 'merchant_002', 'merchant_003', 'merchant_004', 'merchant_005',
  'merchant_006', 'merchant_007', 'merchant_008', 'merchant_009', 'merchant_010'
];

const CURRENCIES = ['USD', 'EUR', 'BRL', 'MXN', 'COP', 'ARS', 'CLP', 'PEN'];

// Traffic patterns
export const options = {
  scenarios: {
    // Scenario 1: Normal traffic baseline (15K req/sec equivalent)
    normal_traffic: {
      executor: 'constant-arrival-rate',
      rate: 1000, // Scaled down for local testing
      timeUnit: '1s',
      duration: '2m',
      preAllocatedVUs: 100,
      maxVUs: 500,
      startTime: '0s',
      tags: { scenario: 'normal' },
    },
    
    // Scenario 2: Traffic ramp-up (simulating Black Friday start)
    traffic_ramp: {
      executor: 'ramping-arrival-rate',
      startRate: 1000,
      timeUnit: '1s',
      preAllocatedVUs: 200,
      maxVUs: 1000,
      stages: [
        { target: 1500, duration: '1m' },
        { target: 2000, duration: '1m' },
        { target: 3000, duration: '2m' }, // Peak (scaled 45K equivalent)
        { target: 2000, duration: '1m' },
        { target: 1000, duration: '1m' },
      ],
      startTime: '2m',
      tags: { scenario: 'ramp' },
    },
    
    // Scenario 3: Sustained peak load
    peak_load: {
      executor: 'constant-arrival-rate',
      rate: 3000,
      timeUnit: '1s',
      duration: '5m',
      preAllocatedVUs: 500,
      maxVUs: 2000,
      startTime: '8m',
      tags: { scenario: 'peak' },
    },
    
    // Scenario 4: Spike test (sudden traffic burst)
    spike_test: {
      executor: 'ramping-arrival-rate',
      startRate: 1000,
      timeUnit: '1s',
      preAllocatedVUs: 200,
      maxVUs: 3000,
      stages: [
        { target: 5000, duration: '10s' }, // Sudden spike
        { target: 5000, duration: '30s' }, // Sustain spike
        { target: 1000, duration: '20s' }, // Return to normal
      ],
      startTime: '13m',
      tags: { scenario: 'spike' },
    },
  },
  
  thresholds: {
    // SLO Thresholds
    'authorization_success_rate': ['rate>0.99'],  // 99% success rate
    'authorization_latency': ['p(99)<500'],        // P99 < 500ms
    'http_req_failed': ['rate<0.01'],              // Less than 1% failed requests
    'http_req_duration': ['p(95)<300', 'p(99)<500'], // Latency thresholds
  },
};

// Generate random transaction
function generateTransaction() {
  return {
    merchant_id: randomItem(MERCHANTS),
    amount: randomIntBetween(10, 10000) + Math.random(),
    currency: randomItem(CURRENCIES),
    card_token: `tok_${Date.now()}_${randomIntBetween(1000, 9999)}`,
    transaction_id: `txn_${Date.now()}_${randomIntBetween(10000, 99999)}`,
  };
}

// Main test function
export default function () {
  const transaction = generateTransaction();
  
  const payload = JSON.stringify(transaction);
  
  const params = {
    headers: {
      'Content-Type': 'application/json',
      'X-Request-ID': `req_${Date.now()}_${randomIntBetween(1000, 9999)}`,
      'X-Merchant-ID': transaction.merchant_id,
    },
    tags: {
      merchant: transaction.merchant_id,
      currency: transaction.currency,
    },
  };
  
  const startTime = Date.now();
  const response = http.post(`${BASE_URL}/authorize`, payload, params);
  const latency = Date.now() - startTime;
  
  // Record metrics
  authorizationTotal.add(1);
  authorizationLatency.add(latency);
  
  // Check response
  const isSuccess = check(response, {
    'status is 200 or 402': (r) => r.status === 200 || r.status === 402,
    'response has transaction_id': (r) => {
      try {
        const body = JSON.parse(r.body);
        return body.transaction_id !== undefined;
      } catch {
        return false;
      }
    },
    'response time < 500ms': (r) => r.timings.duration < 500,
  });
  
  // Track authorization result
  if (response.status === 200) {
    authorizationApproved.add(1);
    authorizationSuccessRate.add(true);
  } else if (response.status === 402) {
    authorizationDeclined.add(1);
    authorizationSuccessRate.add(true); // Decline is still a successful processing
  } else {
    authorizationSuccessRate.add(false);
  }
  
  // Small random sleep to simulate realistic user behavior
  sleep(Math.random() * 0.1);
}

// Setup function - runs once before test
export function setup() {
  console.log(`Starting load test against: ${BASE_URL}`);
  
  // Verify service is reachable
  const healthResponse = http.get(`${BASE_URL}/health/ready`);
  
  if (healthResponse.status !== 200) {
    console.error('Service health check failed!');
    console.error(`Status: ${healthResponse.status}`);
    console.error(`Body: ${healthResponse.body}`);
  }
  
  return {
    startTime: new Date().toISOString(),
    baseUrl: BASE_URL,
  };
}

// Teardown function - runs once after test
export function teardown(data) {
  console.log(`Load test completed.`);
  console.log(`Started at: ${data.startTime}`);
  console.log(`Ended at: ${new Date().toISOString()}`);
}

// Handle summary
export function handleSummary(data) {
  return {
    'stdout': textSummary(data, { indent: ' ', enableColors: true }),
    'load-test-results.json': JSON.stringify(data, null, 2),
  };
}

// Text summary helper
function textSummary(data, options) {
  const metrics = data.metrics;
  
  let summary = '\n';
  summary += '='.repeat(60) + '\n';
  summary += '  VOYAGER GATEWAY LOAD TEST RESULTS\n';
  summary += '='.repeat(60) + '\n\n';
  
  // SLO Summary
  summary += '📊 SLO COMPLIANCE:\n';
  summary += '-'.repeat(40) + '\n';
  
  if (metrics.authorization_success_rate) {
    const rate = metrics.authorization_success_rate.values.rate * 100;
    const status = rate >= 99 ? '✅' : '❌';
    summary += `  ${status} Success Rate: ${rate.toFixed(2)}% (SLO: 99%)\n`;
  }
  
  if (metrics.authorization_latency) {
    const p99 = metrics.authorization_latency.values['p(99)'];
    const status = p99 < 500 ? '✅' : '❌';
    summary += `  ${status} P99 Latency: ${p99.toFixed(2)}ms (SLO: 500ms)\n`;
  }
  
  summary += '\n📈 TRAFFIC SUMMARY:\n';
  summary += '-'.repeat(40) + '\n';
  
  if (metrics.authorization_total) {
    summary += `  Total Requests: ${metrics.authorization_total.values.count}\n`;
  }
  if (metrics.authorization_approved) {
    summary += `  Approved: ${metrics.authorization_approved.values.count}\n`;
  }
  if (metrics.authorization_declined) {
    summary += `  Declined: ${metrics.authorization_declined.values.count}\n`;
  }
  
  summary += '\n';
  return summary;
}
