output "cluster_name" {
  value = aws_eks_cluster.tastytap_cluster.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.tastytap_cluster.endpoint
}

output "cluster_arn" {
  value = aws_eks_cluster.tastytap_cluster.arn
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "vpc_name" {
  value = module.vpc.name
}

output "public_subnet_ids" {
  value = module.vpc.public_subnets
}

output "private_subnet_ids" {
  value = module.vpc.private_subnets
}