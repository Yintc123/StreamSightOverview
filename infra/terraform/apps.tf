# =====================================================================
# Frontend / Backend / Streamlit — each deploys to ECS from its own GitHub
# repo. This file provisions, per app:
#   - an ECR repository
#   - an OIDC deploy role trusted by that repo (push its ECR + update its ECS
#     service), so the repo's CI needs no long-lived AWS keys
#   - an ECS execution role that can read only the SSM namespaces it needs
#     (shared/ + its own) — least-privilege shared secrets
#
# The ECS services + task defs + public routing are added later (they need
# per-app exposure decisions). Everything here is usable now: each repo's CI
# can authenticate and push images immediately.
# =====================================================================

variable "ecs_apps" {
  description = "Apps deployed to ECS from their own repos. github_repo is owner/name for OIDC trust; ssm_namespaces are the /<project>/<ns>/ paths the app's execution role may read."
  type = map(object({
    github_repo    = string
    ssm_namespaces = list(string)
  }))
  default = {
    frontend = {
      github_repo    = "Yintc123/StreamSightFrontend"
      ssm_namespaces = ["shared", "frontend"]
    }
    backend = {
      github_repo    = "Yintc123/StreamSightBackend"
      ssm_namespaces = ["shared", "backend"]
    }
    streamlit = {
      github_repo    = "Yintc123/StreamSightStreamlit"
      ssm_namespaces = ["shared", "streamlit"]
    }
  }
}

# ---- ECR per app ----
resource "aws_ecr_repository" "apps" {
  for_each             = var.ecs_apps
  name                 = "${var.project}-${each.key}"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "apps" {
  for_each   = aws_ecr_repository.apps
  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep only the last 10 images"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 10 }
      action       = { type = "expire" }
    }]
  })
}

# ---- Execution role per app (reads shared/ + own SSM namespace) ----
resource "aws_iam_role" "app_execution" {
  for_each           = var.ecs_apps
  name               = "${var.project}-${each.key}-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

resource "aws_iam_role_policy_attachment" "app_execution_managed" {
  for_each   = var.ecs_apps
  role       = aws_iam_role.app_execution[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "app_execution_ssm" {
  for_each = var.ecs_apps
  statement {
    actions = ["ssm:GetParameters"]
    resources = [
      for ns in each.value.ssm_namespaces :
      "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/${var.project}/${ns}/*"
    ]
  }
}

resource "aws_iam_role_policy" "app_execution_ssm" {
  for_each = var.ecs_apps
  name     = "ssm-read"
  role     = aws_iam_role.app_execution[each.key].id
  policy   = data.aws_iam_policy_document.app_execution_ssm[each.key].json
}

# ---- OIDC deploy role per app (trusted by that repo) ----
data "aws_iam_policy_document" "app_deploy_assume" {
  for_each = var.ecs_apps
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      # Same immutable-ID subject format as the overview role (see iam.tf).
      values = ["repo:${replace(each.value.github_repo, "/", "@*/")}@*:ref:refs/heads/${var.deploy_branch}"]
    }
  }
}

resource "aws_iam_role" "app_deploy" {
  for_each           = var.ecs_apps
  name               = "${var.project}-${each.key}-deploy"
  assume_role_policy = data.aws_iam_policy_document.app_deploy_assume[each.key].json
}

data "aws_iam_policy_document" "app_deploy" {
  for_each = var.ecs_apps

  statement {
    sid       = "EcrAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "EcrPushPull"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = [aws_ecr_repository.apps[each.key].arn]
  }

  # Register/Describe task definitions don't support resource-level scoping.
  statement {
    sid = "EcsDeploy"
    actions = [
      "ecs:DescribeServices",
      "ecs:DescribeTaskDefinition",
      "ecs:RegisterTaskDefinition",
      "ecs:UpdateService",
      "ecs:DescribeTasks",
      "ecs:ListTasks",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "PassRoles"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.app_execution[each.key].arn, aws_iam_role.ecs_task.arn]
  }
}

resource "aws_iam_role_policy" "app_deploy" {
  for_each = var.ecs_apps
  name     = "deploy"
  role     = aws_iam_role.app_deploy[each.key].id
  policy   = data.aws_iam_policy_document.app_deploy[each.key].json
}

# Outputs (deploy_role_arns / ecr_repository_urls) are unified across all four
# apps in outputs.tf.
