# Development Environment Configuration for Voyager Gateway
# Smaller, cost-optimized configuration for development and testing

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = "dev"
      Service     = "voyager-gateway"
      ManagedBy   = "terraform"
      Team        = "platform-engineering"
    }
  }
}

locals {
  environment = "dev"
}

# Networking Module
module "networking" {
  source = "../../modules/networking"

  environment        = local.environment
  vpc_cidr           = "10.1.0.0/16"
  availability_zones = ["us-east-1a", "us-east-1b"]
  enable_nat_gateway = true
}

# Secrets Management Module
module "secrets" {
  source = "../../modules/secrets"

  environment            = local.environment
  enable_secret_rotation = false
}

# Kubernetes (EKS) Module - smaller for dev
module "kubernetes" {
  source = "../../modules/kubernetes"

  environment             = local.environment
  vpc_id                  = module.networking.vpc_id
  private_subnet_ids      = module.networking.private_subnet_ids
  kubernetes_version      = "1.28"
  secrets_read_policy_arn = module.secrets.secrets_read_policy_arn

  # Smaller node group for dev
  standard_instance_types = ["t3.medium", "t3.large"]
  standard_desired_size   = 2
  standard_min_size       = 1
  standard_max_size       = 5

  # No high-traffic nodes for dev
  high_traffic_desired_size = 0
  high_traffic_min_size     = 0
  high_traffic_max_size     = 0
}

# Monitoring Module
module "monitoring" {
  source = "../../modules/monitoring"

  environment        = local.environment
  aws_region         = var.aws_region
  log_retention_days = 7

  # More relaxed SLOs for dev
  slo_success_rate   = 99.0
  slo_latency_p99_ms = 1000
}
