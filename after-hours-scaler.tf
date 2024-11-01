locals {
  cluster_name = "dev-cluster-1"
  aws_region = "eu-west-2"
  account_id = "123456789012"
  cluster_oidc_provider_arn = ""
  cluster_oidc_issuer_url = ""
}

# Policy to allow the service account to assume the role
data "aws_iam_policy_document" "sa_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.cluster_oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${trimprefix(local.cluster_oidc_issuer_url, "https://")}:sub"
      values   = ["system:serviceaccount:after-hours-scaler:after-hours-scaler"]
    }
  }
}

# IAM role for the service account
resource "aws_iam_role" "this" {
  name               = "${local.cluster_name}-after-hours-scaler"
  description        = "${local.cluster_name}-after-hours-scaler service account role"
  assume_role_policy = data.aws_iam_policy_document.sa_assume.json
}

# Policy to allow terminating ec2 instances
data "aws_iam_policy_document" "cluster_scaler" {
  statement {
    actions = [
      "ec2:DescribeInstances"
    ]
    resources = ["*"]
  }
  statement {
    actions = [
      "ec2:TerminateInstances"
    ]
    resources = [
      "arn:aws:ec2:${local.aws_region}:${local.account_id}:instance/*"
    ]
    condition {
      test     = "StringLike"
      variable = "ec2:ResourceTag/environment"
      values   = [local.cluster_name]
    }
    condition {
      test     = "StringLike"
      variable = "ec2:ResourceTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
  }
}

# Attach the policy to the role
resource "aws_iam_role_policy" "this" {
  name   = "${local.cluster_name}-after-hours-scaler"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.cluster_scaler.json
}

resource "kubernetes_namespace" "after-hours-scaler" {
  metadata {
    name = "after-hours-scaler"
  }
}

resource "kubernetes_config_map" "after-hours-scaler" {
  metadata {
    name      = "cluster-config"
    namespace = resource.kubernetes_namespace.after-hours-scaler[0].metadata[0].name
  }
  data = {
    "CLUSTER_NAME" = local.cluster_name
  }
}
