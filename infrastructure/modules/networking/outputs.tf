output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.payment_vpc.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.payment_vpc.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of public subnets"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of private subnets"
  value       = aws_subnet.private[*].id
}

output "voyager_gateway_security_group_id" {
  description = "Security group ID for Voyager Gateway"
  value       = aws_security_group.voyager_gateway.id
}

output "alb_security_group_id" {
  description = "Security group ID for ALB"
  value       = aws_security_group.alb.id
}
