# Monitoring Module for Voyager Gateway
# Configures CloudWatch dashboards and alarms for SLO-based alerting

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# SNS Topic for alerts
resource "aws_sns_topic" "alerts" {
  name = "${var.environment}-voyager-alerts"

  tags = {
    Environment = var.environment
    Service     = "voyager-gateway"
  }
}

# SNS Topic subscription (email)
resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# CloudWatch Log Group for Voyager Gateway
resource "aws_cloudwatch_log_group" "voyager_gateway" {
  name              = "/aws/eks/${var.environment}/voyager-gateway"
  retention_in_days = var.log_retention_days

  tags = {
    Environment = var.environment
    Service     = "voyager-gateway"
  }
}

# CloudWatch Dashboard for Voyager Gateway
resource "aws_cloudwatch_dashboard" "voyager_gateway" {
  dashboard_name = "${var.environment}-voyager-gateway"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 1
        properties = {
          markdown = "# Voyager Gateway - Payment Authorization Service\n**Environment:** ${var.environment} | **SLO Target:** ${var.slo_success_rate}% success rate, P99 < ${var.slo_latency_p99_ms}ms"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 1
        width  = 8
        height = 6
        properties = {
          title  = "Authorization Success Rate (SLO: ${var.slo_success_rate}%)"
          view   = "timeSeries"
          region = var.aws_region
          metrics = [
            ["Voyager", "AuthorizationSuccessRate", "Environment", var.environment]
          ]
          annotations = {
            horizontal = [
              {
                value = var.slo_success_rate
                label = "SLO Target"
                color = "#2ca02c"
              },
              {
                value = var.slo_success_rate - 1
                label = "Warning"
                color = "#ff7f0e"
              }
            ]
          }
          period = 60
          stat   = "Average"
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 1
        width  = 8
        height = 6
        properties = {
          title  = "Latency Percentiles"
          view   = "timeSeries"
          region = var.aws_region
          metrics = [
            ["Voyager", "AuthorizationLatency", "Environment", var.environment, { stat = "p50", label = "P50" }],
            ["...", { stat = "p95", label = "P95" }],
            ["...", { stat = "p99", label = "P99" }]
          ]
          annotations = {
            horizontal = [
              {
                value = var.slo_latency_p99_ms
                label = "SLO P99 Target"
                color = "#d62728"
              }
            ]
          }
          period = 60
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 1
        width  = 8
        height = 6
        properties = {
          title  = "Request Throughput"
          view   = "timeSeries"
          region = var.aws_region
          metrics = [
            ["Voyager", "AuthorizationRequests", "Environment", var.environment, { stat = "Sum", label = "Requests/min" }]
          ]
          period = 60
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 7
        width  = 12
        height = 6
        properties = {
          title  = "Errors by Type"
          view   = "timeSeries"
          region = var.aws_region
          metrics = [
            ["Voyager", "AuthorizationErrors", "ErrorType", "processor_timeout", "Environment", var.environment],
            ["...", "ErrorType", "card_declined", "..."],
            ["...", "ErrorType", "insufficient_funds", "..."],
            ["...", "ErrorType", "invalid_card", "..."]
          ]
          period = 60
          stat   = "Sum"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 7
        width  = 12
        height = 6
        properties = {
          title  = "Throughput by Processor"
          view   = "timeSeries"
          region = var.aws_region
          metrics = [
            ["Voyager", "AuthorizationRequests", "Processor", "stripe", "Environment", var.environment],
            ["...", "Processor", "adyen", "..."],
            ["...", "Processor", "mercadopago", "..."]
          ]
          period = 60
          stat   = "Sum"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 13
        width  = 8
        height = 6
        properties = {
          title  = "CPU Utilization"
          view   = "timeSeries"
          region = var.aws_region
          metrics = [
            ["AWS/EKS", "pod_cpu_utilization", "ClusterName", "${var.environment}-voyager-cluster", "Namespace", "voyager"]
          ]
          period = 60
          stat   = "Average"
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 13
        width  = 8
        height = 6
        properties = {
          title  = "Memory Utilization"
          view   = "timeSeries"
          region = var.aws_region
          metrics = [
            ["AWS/EKS", "pod_memory_utilization", "ClusterName", "${var.environment}-voyager-cluster", "Namespace", "voyager"]
          ]
          period = 60
          stat   = "Average"
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 13
        width  = 8
        height = 6
        properties = {
          title  = "Active Pods"
          view   = "timeSeries"
          region = var.aws_region
          metrics = [
            ["AWS/EKS", "pod_number_of_running_pods", "ClusterName", "${var.environment}-voyager-cluster", "Namespace", "voyager"]
          ]
          period = 60
          stat   = "Average"
        }
      }
    ]
  })
}

# CloudWatch Alarm - Success Rate SLO Violation Warning
resource "aws_cloudwatch_metric_alarm" "success_rate_warning" {
  alarm_name          = "${var.environment}-voyager-success-rate-warning"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "AuthorizationSuccessRate"
  namespace           = "Voyager"
  period              = 300
  statistic           = "Average"
  threshold           = var.slo_success_rate - 0.5
  alarm_description   = "Success rate approaching SLO violation"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    Environment = var.environment
  }

  tags = {
    Environment = var.environment
    Service     = "voyager-gateway"
    AlertType   = "slo-warning"
  }
}

# CloudWatch Alarm - Success Rate SLO Violation Critical
resource "aws_cloudwatch_metric_alarm" "success_rate_critical" {
  alarm_name          = "${var.environment}-voyager-success-rate-critical"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "AuthorizationSuccessRate"
  namespace           = "Voyager"
  period              = 60
  statistic           = "Average"
  threshold           = var.slo_success_rate - 1
  alarm_description   = "Success rate SLO violation - immediate action required"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    Environment = var.environment
  }

  tags = {
    Environment = var.environment
    Service     = "voyager-gateway"
    AlertType   = "slo-critical"
  }
}

# CloudWatch Alarm - P99 Latency SLO
resource "aws_cloudwatch_metric_alarm" "latency_p99" {
  alarm_name          = "${var.environment}-voyager-latency-p99"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "AuthorizationLatency"
  namespace           = "Voyager"
  period              = 60
  extended_statistic  = "p99"
  threshold           = var.slo_latency_p99_ms
  alarm_description   = "P99 latency exceeding SLO threshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    Environment = var.environment
  }

  tags = {
    Environment = var.environment
    Service     = "voyager-gateway"
    AlertType   = "slo-latency"
  }
}

# CloudWatch Alarm - High Error Rate by Processor
resource "aws_cloudwatch_metric_alarm" "processor_errors" {
  for_each = toset(["stripe", "adyen", "mercadopago"])

  alarm_name          = "${var.environment}-voyager-${each.key}-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "AuthorizationErrors"
  namespace           = "Voyager"
  period              = 300
  statistic           = "Sum"
  threshold           = 100
  alarm_description   = "High error rate for ${each.key} processor"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    Environment = var.environment
    Processor   = each.key
  }

  tags = {
    Environment = var.environment
    Service     = "voyager-gateway"
    Processor   = each.key
    AlertType   = "processor-health"
  }
}
