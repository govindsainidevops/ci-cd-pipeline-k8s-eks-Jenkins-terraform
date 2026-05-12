module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = "1.29"

  vpc_id                         = module.vpc.vpc_id
  subnet_ids                     = module.vpc.private_subnets
  cluster_endpoint_public_access = true

  eks_managed_node_groups = {
    devops_nodes = {
      min_size       = 1
      max_size       = 5
      desired_size   = var.desired_nodes
      instance_types = [var.node_instance_type]

      iam_role_additional_policies = {
        AmazonEC2ContainerRegistryReadOnly = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
      }
    }
  }

  # lifecycle block is NOT valid inside module{} — use a null_resource guard instead
  tags = {
    Environment = "dev"
    Project     = "devops-pipeline"
  }
}

# Accidental deletion guard — destroying this resource will fail with a clear message
resource "null_resource" "prevent_eks_destroy" {
  triggers = {
    cluster_name = module.eks.cluster_name
  }

  lifecycle {
    prevent_destroy = true
  }
}