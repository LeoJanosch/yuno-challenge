# Production Environment Configuration for Voyager Gateway
# This is the main entry point for deploying the production infrastructure

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Backend configuration for state management
  # Uncomment and configure for production use
  # backend "s3" {
  #   bucket         = "yuno-terraform-state"
  #   key            = "voyager-gateway/prod/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-locks"
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = "prod"
      Service     = "voyager-gateway"
      ManagedBy   = "terraform"
      Team        = "platform-engineering"
    }
  }
}

locals {
  environment = "prod"
}

# Networking Module
module "networking" {
  source = "../../modules/networking"

  environment        = local.environment
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
  enable_nat_gateway = true
}

# Secrets Management Module
module "secrets" {
  source = "../../modules/secrets"

  environment              = local.environment
  stripe_api_key           = var.stripe_api_key
  stripe_webhook_secret    = var.stripe_webhook_secret
  adyen_api_key            = var.adyen_api_key
  adyen_merchant_account   = var.adyen_merchant_account
  mercadopago_access_token = var.mercadopago_access_token
  mercadopago_public_key   = var.mercadopago_public_key
  enable_secret_rotation   = var.enable_secret_rotation
  rotation_lambda_arn      = var.rotation_lambda_arn
}

# Kubernetes (EKS) Module
module "kubernetes" {
  source = "../../modules/kubernetes"

  environment             = local.environment
  vpc_id                  = module.networking.vpc_id
  private_subnet_ids      = module.networking.private_subnet_ids
  kubernetes_version      = var.kubernetes_version
  secrets_read_policy_arn = module.secrets.secrets_read_policy_arn

  # Standard node group for normal traffic
  standard_instance_types = ["t3.xlarge", "t3.2xlarge"]
  standard_desired_size   = 5
  standard_min_size       = 3
  standard_max_size       = 15

  # High-traffic node group for Black Friday
  high_traffic_instance_types = ["c5.4xlarge", "c5.9xlarge"]
  high_traffic_desired_size   = 0
  high_traffic_min_size       = 0
  high_traffic_max_size       = 30
}

# Monitoring Module
module "monitoring" {
  source = "../../modules/monitoring"

  environment        = local.environment
  aws_region         = var.aws_region
  alert_email        = var.alert_email
  log_retention_days = 90

  # SLO Configuration for production
  slo_success_rate   = 99.9
  slo_latency_p99_ms = 500
}
