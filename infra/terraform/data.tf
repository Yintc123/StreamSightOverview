data "aws_caller_identity" "current" {}

# Use the account's default VPC and its subnets (one public subnet per AZ).
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# The datastore EC2 lives in the first subnet; its EBS volume must share that AZ.
data "aws_subnet" "datastore" {
  id = data.aws_subnets.default.ids[0]
}

# Latest Amazon Linux 2023 AMI (x86_64) via the public SSM parameter.
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}
