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

output "terraform_role_arns" {
  description = "Per-app OIDC Terraform-CI role ARN. Set each app repo's TF_ROLE_ARN secret to its own value; the app repos need no local bootstrap."
  value       = { for k, r in aws_iam_role.app_terraform : k => r.arn }
}

# --- Service discovery (shared by all app stacks) ---

output "service_discovery_namespace_id" {
  description = "Cloud Map private DNS namespace ID. App stacks look this up via aws_service_discovery_dns_namespace to register their own services."
  value       = aws_service_discovery_private_dns_namespace.main.id
}

output "internal_sg_id" {
  description = "Security group for VPC-internal ECS-to-ECS traffic. App stacks attach this alongside their own SG so tasks can call each other via Cloud Map DNS."
  value       = aws_security_group.internal.id
}

# --- Infra pipeline (not an app) ---

output "terraform_role_arn" {
  description = "OIDC role for the Terraform CI pipeline. Set as TF_ROLE_ARN in the overview repo."
  value       = aws_iam_role.github_terraform.arn
}
