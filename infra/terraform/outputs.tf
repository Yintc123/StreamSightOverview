output "cloudfront_url" {
  description = "Public HTTPS URL of the API — hit this."
  value       = "https://${aws_cloudfront_distribution.app.domain_name}"
}

output "alb_dns_name" {
  description = "ALB origin hostname. Direct access is blocked (403) — go through cloudfront_url."
  value       = aws_lb.app.dns_name
}

output "ecs_cluster" {
  value = aws_ecs_cluster.main.name
}

output "datastore_private_ip" {
  value = aws_instance.datastore.private_ip
}

# --- Per-app, one key each (overview + frontend + backend + streamlit) ---

output "deploy_role_arns" {
  description = "Per-app OIDC deploy role ARN. Set each repo's CI to assume its own value."
  value = merge(
    { overview = aws_iam_role.github_deploy.arn },
    { for k, r in aws_iam_role.app_deploy : k => r.arn },
  )
}

output "ecr_repository_urls" {
  description = "Per-app ECR repository URL."
  value = merge(
    { overview = aws_ecr_repository.app.repository_url },
    { for k, r in aws_ecr_repository.apps : k => r.repository_url },
  )
}

# --- Infra pipeline (not an app) ---

output "terraform_role_arn" {
  description = "OIDC role for the Terraform CI pipeline. Set as TF_ROLE_ARN in the overview repo."
  value       = aws_iam_role.github_terraform.arn
}
