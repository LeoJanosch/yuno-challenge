variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "alert_email" {
  description = "Email for alert notifications"
  type        = string
  default     = ""
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

# SLO Configuration
variable "slo_success_rate" {
  description = "SLO target for success rate percentage"
  type        = number
  default     = 99.9
}

variable "slo_latency_p99_ms" {
  description = "SLO target for P99 latency in milliseconds"
  type        = number
  default     = 500
}
