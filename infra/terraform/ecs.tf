resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.project}"
  retention_in_days = 14
}

resource "aws_ecs_cluster" "main" {
  name = var.project

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecs_task_definition" "app" {
  family                   = var.project
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name      = var.project
    image     = "${aws_ecr_repository.app.repository_url}:${var.image_tag}"
    essential = true

    portMappings = [{
      containerPort = var.container_port
      protocol      = "tcp"
    }]

    environment = [
      { name = "PORT", value = tostring(var.container_port) },
      { name = "DB_HOST", value = aws_instance.datastore.private_ip },
      { name = "DB_PORT", value = "3306" },
      { name = "DB_USER", value = var.db_user },
      { name = "DB_NAME", value = var.db_name },
      { name = "REDIS_HOST", value = aws_instance.datastore.private_ip },
      { name = "REDIS_PORT", value = "6379" },
      { name = "REDIS_DB", value = "0" },
    ]

    secrets = [
      { name = "DB_PASSWORD", valueFrom = aws_ssm_parameter.db_password.arn },
      { name = "REDIS_PASSWORD", valueFrom = aws_ssm_parameter.redis_password.arn },
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.app.name
        "awslogs-region"        = var.region
        "awslogs-stream-prefix" = "app"
      }
    }
  }])
}

resource "aws_ecs_service" "app" {
  name            = var.project
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = true # required to pull from ECR in the default VPC (no NAT)
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = var.project
    container_port   = var.container_port
  }

  health_check_grace_period_seconds = 60

  depends_on = [aws_lb_listener.http, aws_volume_attachment.data]

  # The app pipeline updates task_definition (new image) and may scale
  # desired_count; don't let `terraform apply` revert those.
  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }
}
