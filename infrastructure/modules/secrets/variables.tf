variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

# Stripe credentials
variable "stripe_api_key" {
  description = "Stripe API key"
  type        = string
  sensitive   = true
  default     = "sk_test_placeholder"
}

variable "stripe_webhook_secret" {
  description = "Stripe webhook signing secret"
  type        = string
  sensitive   = true
  default     = "whsec_placeholder"
}

# Adyen credentials
variable "adyen_api_key" {
  description = "Adyen API key"
  type        = string
  sensitive   = true
  default     = "adyen_test_placeholder"
}

variable "adyen_merchant_account" {
  description = "Adyen merchant account"
  type        = string
  default     = "YunoMerchant"
}

# MercadoPago credentials
variable "mercadopago_access_token" {
  description = "MercadoPago access token"
  type        = string
  sensitive   = true
  default     = "mp_test_placeholder"
}

variable "mercadopago_public_key" {
  description = "MercadoPago public key"
  type        = string
  default     = "mp_public_placeholder"
}

# Rotation settings
variable "enable_secret_rotation" {
  description = "Enable automatic secret rotation"
  type        = bool
  default     = false
}

variable "rotation_lambda_arn" {
  description = "ARN of the Lambda function for secret rotation"
  type        = string
  default     = ""
}

variable "rotation_days" {
  description = "Number of days between automatic secret rotations"
  type        = number
  default     = 30
}
