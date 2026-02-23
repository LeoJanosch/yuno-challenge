output "stripe_secret_arn" {
  description = "ARN of Stripe secret"
  value       = aws_secretsmanager_secret.stripe.arn
}

output "adyen_secret_arn" {
  description = "ARN of Adyen secret"
  value       = aws_secretsmanager_secret.adyen.arn
}

output "mercadopago_secret_arn" {
  description = "ARN of MercadoPago secret"
  value       = aws_secretsmanager_secret.mercadopago.arn
}

output "secrets_read_policy_arn" {
  description = "ARN of IAM policy for reading secrets"
  value       = aws_iam_policy.secrets_read.arn
}

output "kms_key_arn" {
  description = "ARN of KMS key for secrets encryption"
  value       = aws_kms_key.secrets.arn
}
