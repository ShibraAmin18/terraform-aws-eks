locals {
  region      = "us-east-2"
  environment = "prod"
  name        = "skaf"
  additional_aws_tags = {
    Owner      = "SquareOps"
    Expires    = "Never"
    Department = "Engineering"
  }
  vpc_cidr = "10.10.0.0/16"
}

data "aws_availability_zones" "available" {}

module "key_pair_vpn" {
  source             = "squareops/keypair/aws"
  key_name           = format("%s-%s-vpn", local.environment, local.name)
  environment        = local.environment
  ssm_parameter_path = format("%s-%s-vpn", local.environment, local.name)
}

module "key_pair_eks" {
  source             = "squareops/keypair/aws"
  key_name           = format("%s-%s-eks", local.environment, local.name)
  environment        = local.environment
  ssm_parameter_path = format("%s-%s-eks", local.environment, local.name)
}

module "vpc" {
  source                                          = "squareops/vpc/aws"
  environment                                     = local.environment
  name                                            = local.name
  vpc_cidr                                        = local.vpc_cidr
  availability_zones                              = 2
  public_subnet_enabled                           = true
  private_subnet_enabled                          = true
  database_subnet_enabled                         = true
  intra_subnet_enabled                            = true
  one_nat_gateway_per_az                          = true
  vpn_server_enabled                              = false
  vpn_server_instance_type                        = "t3a.small"
  vpn_key_pair_name                               = module.key_pair_vpn.key_pair_name
  flow_log_enabled                                = true
  flow_log_max_aggregation_interval               = 60
  flow_log_cloudwatch_log_group_retention_in_days = 90
}

module "eks" {
  source                               = "squareops/eks/aws"
  name                                 = local.name
  vpc_id                               = module.vpc.vpc_id
  environment                          = local.environment
  kms_key_arn                          = "arn:aws:kms:us-east-2:222222222222:key/kms_key_arn"
  cluster_version                      = "1.23"
  cluster_log_types                    = ["api", "scheduler"]
  cluster_log_retention_in_days        = 30
  cluster_endpoint_public_access       = true
  cluster_endpoint_public_access_cidrs = ["0.0.0.0/0"]
}

module "managed_node_group_production" {
  source                 = "squareops/eks/aws//modules/managed-nodegroup"
  depends_on             = [module.vpc, module.eks]
  name                   = "Infra"
  min_size               = 1
  max_size               = 3
  desired_size           = 1
  subnet_ids             = [module.vpc.private_subnets[0]]
  environment            = local.environment
  kms_key_arn            = "arn:aws:kms:us-east-2:222222222222:key/kms_key_arn"
  capacity_type          = "ON_DEMAND"
  instance_types         = ["t3a.large", "t2.large", "t2.xlarge", "t3.large", "m5.large"]
  kms_policy_arn         = module.eks.kms_policy_arn
  eks_cluster_name       = module.eks.cluster_name
  worker_iam_role_name   = module.eks.worker_iam_role_name
  eks_nodes_keypair_name = module.key_pair_eks.key_pair_name
  k8s_labels = {
    "Infra-Services" = "true"
  }
  tags = local.additional_aws_tags
}
