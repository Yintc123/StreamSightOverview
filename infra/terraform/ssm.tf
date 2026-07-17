# Datastore credentials the ECS task needs at runtime, stored as SecureString.
# The ECS execution role reads these and injects them as container env vars.
resource "aws_ssm_parameter" "db_password" {
  name  = "/${var.project}/db_password"
  type  = "SecureString"
  value = var.db_password
}

resource "aws_ssm_parameter" "redis_password" {
  name  = "/${var.project}/redis_password"
  type  = "SecureString"
  value = var.redis_password
}
