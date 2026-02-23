variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs"
  type        = list(string)
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.28"
}

variable "enable_public_access" {
  description = "Enable public access to EKS API"
  type        = bool
  default     = true
}

variable "secrets_read_policy_arn" {
  description = "ARN of secrets read policy"
  type        = string
  default     = ""
}

# Standard node group settings
variable "standard_instance_types" {
  description = "Instance types for standard node group"
  type        = list(string)
  default     = ["t3.large", "t3.xlarge"]
}

variable "standard_desired_size" {
  description = "Desired number of standard nodes"
  type        = number
  default     = 3
}

variable "standard_min_size" {
  description = "Minimum number of standard nodes"
  type        = number
  default     = 2
}

variable "standard_max_size" {
  description = "Maximum number of standard nodes"
  type        = number
  default     = 10
}

# High-traffic node group settings (Black Friday)
variable "high_traffic_instance_types" {
  description = "Instance types for high-traffic node group"
  type        = list(string)
  default     = ["c5.2xlarge", "c5.4xlarge"]
}

variable "high_traffic_desired_size" {
  description = "Desired number of high-traffic nodes"
  type        = number
  default     = 0
}

variable "high_traffic_min_size" {
  description = "Minimum number of high-traffic nodes"
  type        = number
  default     = 0
}

variable "high_traffic_max_size" {
  description = "Maximum number of high-traffic nodes"
  type        = number
  default     = 20
}
