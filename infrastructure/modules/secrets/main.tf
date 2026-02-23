# Secrets Management Module for Voyager Gateway
# Manages payment processor API credentials with rotation support

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# KMS key for encrypting secrets
resource "aws_kms_key" "secrets" {
  description             = "KMS key for Voyager Gateway secrets"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Name        = "${var.environment}-voyager-secrets-key"
    Environment = var.environment
    Service     = "voyager-gateway"
    Compliance  = "pci-dss"
  }
}

resource "aws_kms_alias" "secrets" {
  name          = "alias/${var.environment}-voyager-secrets"
  target_key_id = aws_kms_key.secrets.key_id
}

# Stripe API credentials
resource "aws_secretsmanager_secret" "stripe" {
  name        = "${var.environment}/voyager-gateway/stripe"
  description = "Stripe payment processor credentials"
  kms_key_id  = aws_kms_key.secrets.arn

  tags = {
    Environment = var.environment
    Service     = "voyager-gateway"
    Processor   = "stripe"
  }
}

resource "aws_secretsmanager_secret_version" "stripe" {
  secret_id = aws_secretsmanager_secret.stripe.id
  secret_string = jsonencode({
    api_key        = var.stripe_api_key
    webhook_secret = var.stripe_webhook_secret
  })
}

# Enable automatic rotation for Stripe credentials
resource "aws_secretsmanager_secret_rotation" "stripe" {
  count               = var.enable_secret_rotation ? 1 : 0
  secret_id           = aws_secretsmanager_secret.stripe.id
  rotation_lambda_arn = var.rotation_lambda_arn

  rotation_rules {
    automatically_after_days = var.rotation_days
  }
}

# Adyen API credentials
resource "aws_secretsmanager_secret" "adyen" {
  name        = "${var.environment}/voyager-gateway/adyen"
  description = "Adyen payment processor credentials"
  kms_key_id  = aws_kms_key.secrets.arn

  tags = {
    Environment = var.environment
    Service     = "voyager-gateway"
    Processor   = "adyen"
  }
}

resource "aws_secretsmanager_secret_version" "adyen" {
  secret_id = aws_secretsmanager_secret.adyen.id
  secret_string = jsonencode({
    api_key         = var.adyen_api_key
    merchant_account = var.adyen_merchant_account
  })
}

# MercadoPago API credentials
resource "aws_secretsmanager_secret" "mercadopago" {
  name        = "${var.environment}/voyager-gateway/mercadopago"
  description = "MercadoPago payment processor credentials"
  kms_key_id  = aws_kms_key.secrets.arn

  tags = {
    Environment = var.environment
    Service     = "voyager-gateway"
    Processor   = "mercadopago"
  }
}

resource "aws_secretsmanager_secret_version" "mercadopago" {
  secret_id = aws_secretsmanager_secret.mercadopago.id
  secret_string = jsonencode({
    access_token = var.mercadopago_access_token
    public_key   = var.mercadopago_public_key
  })
}

# IAM policy for reading secrets (to be attached to EKS pod role)
resource "aws_iam_policy" "secrets_read" {
  name        = "${var.environment}-voyager-secrets-read"
  description = "Allow reading Voyager Gateway secrets"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          aws_secretsmanager_secret.stripe.arn,
          aws_secretsmanager_secret.adyen.arn,
          aws_secretsmanager_secret.mercadopago.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = [
          aws_kms_key.secrets.arn
        ]
      }
    ]
  })

  tags = {
    Environment = var.environment
    Service     = "voyager-gateway"
  }
}
