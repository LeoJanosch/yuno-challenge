# Kubernetes (EKS) Module for Voyager Gateway
# Provisions EKS cluster with managed node groups for payment service

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# IAM role for EKS cluster
resource "aws_iam_role" "eks_cluster" {
  name = "${var.environment}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
    }]
  })

  tags = {
    Environment = var.environment
    Service     = "voyager-gateway"
  }
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

# EKS Cluster
resource "aws_eks_cluster" "main" {
  name     = "${var.environment}-voyager-cluster"
  role_arn = aws_iam_role.eks_cluster.arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = var.enable_public_access
    security_group_ids      = [aws_security_group.eks_cluster.id]
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  tags = {
    Name        = "${var.environment}-voyager-cluster"
    Environment = var.environment
    Service     = "voyager-gateway"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy
  ]
}

# Security group for EKS cluster
resource "aws_security_group" "eks_cluster" {
  name        = "${var.environment}-eks-cluster-sg"
  description = "Security group for EKS cluster"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.environment}-eks-cluster-sg"
    Environment = var.environment
  }
}

# IAM role for EKS node group
resource "aws_iam_role" "eks_nodes" {
  name = "${var.environment}-eks-nodes-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  tags = {
    Environment = var.environment
    Service     = "voyager-gateway"
  }
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "eks_container_registry" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_nodes.name
}

# Attach secrets read policy to nodes
resource "aws_iam_role_policy_attachment" "eks_secrets_read" {
  count      = var.secrets_read_policy_arn != "" ? 1 : 0
  policy_arn = var.secrets_read_policy_arn
  role       = aws_iam_role.eks_nodes.name
}

# EKS Node Group - Standard workloads
resource "aws_eks_node_group" "standard" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.environment}-standard"
  node_role_arn   = aws_iam_role.eks_nodes.arn
  subnet_ids      = var.private_subnet_ids

  capacity_type  = "ON_DEMAND"
  instance_types = var.standard_instance_types

  scaling_config {
    desired_size = var.standard_desired_size
    max_size     = var.standard_max_size
    min_size     = var.standard_min_size
  }

  update_config {
    max_unavailable_percentage = 25
  }

  labels = {
    role        = "standard"
    environment = var.environment
  }

  tags = {
    Name        = "${var.environment}-standard-nodes"
    Environment = var.environment
    Service     = "voyager-gateway"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_container_registry
  ]
}

# EKS Node Group - High-traffic (for Black Friday surge)
resource "aws_eks_node_group" "high_traffic" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.environment}-high-traffic"
  node_role_arn   = aws_iam_role.eks_nodes.arn
  subnet_ids      = var.private_subnet_ids

  capacity_type  = "ON_DEMAND"
  instance_types = var.high_traffic_instance_types

  scaling_config {
    desired_size = var.high_traffic_desired_size
    max_size     = var.high_traffic_max_size
    min_size     = var.high_traffic_min_size
  }

  update_config {
    max_unavailable_percentage = 25
  }

  labels = {
    role        = "high-traffic"
    environment = var.environment
  }

  taint {
    key    = "workload"
    value  = "high-traffic"
    effect = "NO_SCHEDULE"
  }

  tags = {
    Name        = "${var.environment}-high-traffic-nodes"
    Environment = var.environment
    Service     = "voyager-gateway"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_container_registry
  ]
}

# OIDC provider for IRSA (IAM Roles for Service Accounts)
data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer

  tags = {
    Environment = var.environment
    Service     = "voyager-gateway"
  }
}
