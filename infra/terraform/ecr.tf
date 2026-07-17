locals {
  # This stack (the "overview" repo) deploys the Go server. Name its app-specific
  # resources streamsight-overview to match the streamsight-<app> siblings; the
  # shared layer (SSM /streamsight/, cluster, ALB, CloudFront) keeps var.project.
  overview_app = "${var.project}-overview"
}

resource "aws_ecr_repository" "app" {
  name                 = local.overview_app
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep only the last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}
