terraform {
  required_version = ">= 1.15"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  # Remote state in S3 with native S3 state locking (use_lockfile, Terraform
  # 1.10+) — no DynamoDB table required. Bucket/key/region are supplied via
  # `-backend-config=backend.hcl` (see backend.hcl.example); create the bucket
  # once before the first `terraform init` — see README.md.
  backend "s3" {
    use_lockfile = true
  }
}
