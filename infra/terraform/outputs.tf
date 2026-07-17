output "alb_dns_name" {
  description = "Public URL of the Go API (http://<this>)."
  value       = aws_lb.app.dns_name
}

output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}

output "ecs_cluster" {
  value = aws_ecs_cluster.main.name
}

output "ecs_service" {
  value = aws_ecs_service.app.name
}

output "datastore_private_ip" {
  value = aws_instance.datastore.private_ip
}

output "github_deploy_role_arn" {
  description = "Set as the DEPLOY_ROLE_ARN secret for deploy.yml."
  value       = aws_iam_role.github_deploy.arn
}

output "github_terraform_role_arn" {
  description = "Set as the TF_ROLE_ARN secret for terraform.yml."
  value       = aws_iam_role.github_terraform.arn
}
