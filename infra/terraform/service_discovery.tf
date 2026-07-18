# =====================================================================
# VPC-internal service discovery (AWS Cloud Map)
#
# Exposes a private DNS namespace (streamsight.local) so ECS tasks can
# call each other via stable names without going through CloudFront.
# CloudFront URLs change on every rebuild; these DNS names never do.
#
# Each app's Terraform stack registers its own service entry:
#   frontend.streamsight.local  → Next.js BFF     (port 3000)
#   backend.streamsight.local   → FastAPI backend  (port 8000)
#   streamlit.streamsight.local → Streamlit        (port 8501)
#
# To participate, a task joins aws_security_group.internal alongside its
# own SG. The self-referencing ingress rule lets any member reach any
# other member — no per-service rule changes as apps are added.
# =====================================================================

resource "aws_service_discovery_private_dns_namespace" "main" {
  name        = "${var.project}.local"
  description = "Private DNS for VPC-internal ECS service discovery"
  vpc         = data.aws_vpc.default.id

  tags = { Name = "${var.project}-namespace" }
}

# All ECS tasks that need VPC-internal access join this SG.
# Self-referencing ingress: any member can reach any other member on all
# TCP ports. Each app's own SG still gates its external ingress (ALB etc.);
# this SG is purely additive.
resource "aws_security_group" "internal" {
  name_prefix = "${var.project}-internal-"
  description = "VPC-internal ECS-to-ECS traffic (Cloud Map)"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "All TCP from tasks in this SG"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-internal" }
  lifecycle { create_before_destroy = true }
}
