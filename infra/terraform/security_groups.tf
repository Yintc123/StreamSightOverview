# Public ALB: HTTP from the internet.
resource "aws_security_group" "alb" {
  name_prefix = "${var.project}-alb-"
  description = "ALB ingress"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTP"
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

  tags = { Name = "${var.project}-alb" }
  lifecycle { create_before_destroy = true }
}

# ECS tasks: only the ALB may reach the container port.
resource "aws_security_group" "ecs" {
  name_prefix = "${var.project}-ecs-"
  description = "ECS service tasks"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "From ALB"
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-ecs" }
  lifecycle { create_before_destroy = true }
}

# Datastore EC2: MariaDB/Redis reachable only from the ECS tasks (plus optional SSH).
resource "aws_security_group" "datastore" {
  name_prefix = "${var.project}-datastore-"
  description = "MariaDB + Redis on EC2"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "MariaDB from ECS"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
  }

  ingress {
    description     = "Redis from ECS"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
  }

  dynamic "ingress" {
    for_each = var.ssh_ingress_cidr == "" ? [] : [var.ssh_ingress_cidr]
    content {
      description = "SSH"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-datastore" }
  lifecycle { create_before_destroy = true }
}
