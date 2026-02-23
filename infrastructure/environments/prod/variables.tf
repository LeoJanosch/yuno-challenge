variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "kubernetes_version" {
  description = "Kubernetes version for EKS"
  type        = string
  default     = "1.28"
}

# Processor credentials (should be passed via environment or tfvars)
variable "stripe_api_key" {
  description = "Stripe API key"
  type        = string
  sensitive   = true
  default     = ""
}

variable "stripe_webhook_secret" {
  description = "Stripe webhook secret"
  type        = string
  sensitive   = true
  default     = ""
}

variable "adyen_api_key" {
  description = "Adyen API key"
  type        = string
  sensitive   = true
  default     = ""
}

variable "adyen_merchant_account" {
  description = "Adyen merchant account"
  type        = string
  default     = "YunoMerchant"
}

variable "mercadopago_access_token" {
  description = "MercadoPago access token"
  type        = string
  sensitive   = true
  default     = ""
}

variable "mercadopago_public_key" {
  description = "MercadoPago public key"
  type        = string
  default     = ""
}

# Secret rotation
variable "enable_secret_rotation" {
  description = "Enable automatic secret rotation"
  type        = bool
  default     = true
}

variable "rotation_lambda_arn" {
  description = "ARN of rotation Lambda function"
  type        = string
  default     = ""
}

# Alerting
variable "alert_email" {
  description = "Email for alert notifications"
  type        = string
  default     = ""
}
