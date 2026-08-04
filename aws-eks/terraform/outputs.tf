output "vpc_id" {
  value = module.vpc.vpc_id
}

output "private_subnet_ids" {
  value = module.vpc.private_subnets
}

output "public_subnet_ids" {
  value = module.vpc.public_subnets
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "cluster_autoscaler_role_arn" {
  value = module.cluster_autoscaler_irsa.iam_role_arn
}
output "alb_controller_role_arn" {
  value = module.load_balancer_controller_irsa.iam_role_arn
}

output "eks_tester_readonly_role_arn" {
  value = aws_iam_role.eks_tester_readonly.arn
}