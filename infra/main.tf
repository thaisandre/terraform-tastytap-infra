provider "aws" {
  region = var.region
}

data "aws_availability_zones" "available" {}

# vpc

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.0.0"

  name                  = "tastytap-vpc"
  cidr                  = var.vpc_cidr
  azs                   = slice(data.aws_availability_zones.available.names, 0, 2)
  public_subnets        = var.public_subnets
  private_subnets       = var.private_subnets
  enable_nat_gateway    = true
  single_nat_gateway    = true
  create_igw            = true

  public_subnet_tags = {
    "Name"                                      = "tastytap-vpc-public"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                    = 1
  }

  private_subnet_tags = {
    "Name"                                      = "tastytap-vpc-private"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"           = 1
  }

  tags = {
    Name = "tastytap-vpc"
  }

  map_public_ip_on_launch = false
}

# eks

resource "aws_eks_cluster" "tastytap_cluster" {
  name     = var.cluster_name
  role_arn = aws_iam_role.eks_role.arn

  vpc_config {
    subnet_ids = module.vpc.private_subnets
  }

  depends_on = [aws_iam_role_policy_attachment.eks_policy]
}

resource "aws_iam_role" "eks_role" {
  name = "eks_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Principal = {
        Service = "eks.amazonaws.com"
      }
      Effect    = "Allow"
      Sid       = ""
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_policy" {
  role       = aws_iam_role.eks_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role" "eks_node_group_role" {
  name = "eks_node_group_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Effect    = "Allow"
      Sid       = ""
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_node_group_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node_group_role.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node_group_role.name
}

resource "aws_iam_role_policy_attachment" "eks_registry_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node_group_role.name
}

resource "aws_eks_node_group" "tastytap_node_group" {
  cluster_name    = aws_eks_cluster.tastytap_cluster.name
  node_group_name = "tastytap-node-group"
  node_role_arn   = aws_iam_role.eks_node_group_role.arn
  subnet_ids      = module.vpc.private_subnets

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }

  instance_types = ["t3.small"]

  depends_on = [aws_eks_cluster.tastytap_cluster]
}

# ecr

resource "aws_ecr_repository" "tastytap_repository" {
  name                 = "tastytap"
  image_tag_mutability = "MUTABLE"
}

resource "aws_iam_role_policy_attachment" "eks_ecr_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node_group_role.name
}

resource "null_resource" "cleanup_ecr" {
  depends_on = [aws_ecr_repository.tastytap_repository]

  provisioner "local-exec" {
    command = <<EOT
      aws ecr list-images --repository-name tastytap --query 'imageIds[*]' --output json | jq -c '.[]' | while read img; do
          aws ecr batch-delete-image --repository-name tastytap --image-ids "$img"
      done
    EOT
  }
}

resource "aws_security_group" "vpc-link-sg" {
  name   = "vpc-link-sg"
  vpc_id = module.vpc.vpc_id

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }
}

resource "aws_apigatewayv2_vpc_link" "vpc-link" {
  name               = "vpc-link"
  security_group_ids = [aws_security_group.vpc-link-sg.id]
  subnet_ids         = module.vpc.private_subnets
}

# nlb

resource "aws_lb" "tastytap_nlb" {
  name               = "tastytap-nlb"
  internal           = false
  load_balancer_type = "network"
  security_groups    = [aws_security_group.nlb_sg.id]
  subnets            = module.vpc.public_subnets 

  enable_deletion_protection = false
  enable_cross_zone_load_balancing = true

  tags = {
    Name = "tastytap-nlb"
  }
}

resource "aws_lb_target_group" "tastytap_target_group" {
  name     = "tastytap-target-group"
  port     = 80
  protocol = "TCP"
  vpc_id   = module.vpc.vpc_id

  health_check {
    interval            = 30
    protocol            = "TCP"
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = "tastytap-target-group"
  }
}

resource "aws_lb_listener" "tastytap_listener" {
  load_balancer_arn = aws_lb.tastytap_nlb.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.tastytap_target_group.arn
  }
}

resource "aws_security_group" "nlb_sg" {
  name        = "tastytap-nlb-sg"
  description = "Security group for NLB"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}