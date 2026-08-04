data "aws_caller_identity" "current" {}

resource "aws_iam_role" "eks_tester_readonly" {
  name = "kubernetes-multicloud-eks-tester-readonly"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = data.aws_caller_identity.current.arn }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "eks_tester_readonly_describe" {
  name = "eks-describe-cluster"
  role = aws_iam_role.eks_tester_readonly.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "eks:DescribeCluster"
      Resource = module.eks.cluster_arn
    }]
  })
}

resource "aws_eks_access_entry" "tester_readonly" {
  cluster_name      = module.eks.cluster_name
  principal_arn     = aws_iam_role.eks_tester_readonly.arn
  kubernetes_groups = ["prod-viewers"]
}