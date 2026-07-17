terraform {
  required_version = ">= 1.6"

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

  # Remote state for CI/CD. Provide values via `-backend-config=backend.hcl`
  # (see backend.hcl.example). Create the S3 bucket + DynamoDB lock table once
  # before the first `terraform init` — see README.md.
  backend "s3" {}
}
