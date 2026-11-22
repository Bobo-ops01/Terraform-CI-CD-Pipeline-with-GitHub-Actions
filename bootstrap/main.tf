terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

locals {
  github_repo        = "Bobo-ops01/Terraform-CI-CD-Pipeline-with-GitHub-Actions"
  state_bucket       = "bobo-ops01-tf-cicd-state-use1"
  demo_bucket_prefix = "bobo-ops01-tf-cicd-demo"
}

# Remote state bucket (versioned, encrypted, private)
resource "aws_s3_bucket" "state" {
  bucket = local.state_bucket
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# GitHub OIDC trust: no long-lived AWS keys stored in GitHub
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # Required by older provider versions; AWS no longer uses it for GitHub
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:Bobo-ops01@192600435/Terraform-CI-CD-Pipeline-with-GitHub-Actions@1461938826:pull_request",
        "repo:Bobo-ops01@192600435/Terraform-CI-CD-Pipeline-with-GitHub-Actions@1461938826:environment:production",
      ]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = "github-actions-terraform"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

# Least privilege: state bucket access plus the demo buckets only
data "aws_iam_policy_document" "permissions" {
  statement {
    sid       = "StateBucketList"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn]
  }
  statement {
    sid       = "StateObjects"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.state.arn}/*"]
  }
  statement {
    sid     = "DemoBuckets"
    actions = ["s3:*"]
    resources = [
      "arn:aws:s3:::${local.demo_bucket_prefix}-*",
      "arn:aws:s3:::${local.demo_bucket_prefix}-*/*",
    ]
  }
}

resource "aws_iam_role_policy" "permissions" {
  name   = "terraform-pipeline-permissions"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.permissions.json
}

output "role_arn" {
  value = aws_iam_role.github_actions.arn
}

output "state_bucket" {
  value = aws_s3_bucket.state.id
}
