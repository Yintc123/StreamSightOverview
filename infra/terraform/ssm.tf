# =====================================================================
# Secrets in SSM Parameter Store (SecureString, free standard tier).
#
# Namespaced so the three apps can share cleanly:
#   /streamsight/shared/*    db + redis creds — Go and Backend hit the same
#                            MariaDB (user "streamsight"); Go/Backend/Frontend
#                            share the one Redis (separated by key prefix)
#   /streamsight/backend/*   backend-only secrets
#   /streamsight/frontend/*  frontend-only secrets
#
# Each app's ECS execution role is granted read on only the paths it needs
# (least privilege). The Go server reads just the shared/ params today; the
# backend/frontend grants + task-def injection are added when those services
# are deployed.
# =====================================================================

# --- Shared datastore credentials (required — the Go server needs them now) ---
resource "aws_ssm_parameter" "db_password" {
  name  = "/${var.project}/shared/db_password"
  type  = "SecureString"
  value = var.db_password
}

resource "aws_ssm_parameter" "redis_password" {
  name  = "/${var.project}/shared/redis_password"
  type  = "SecureString"
  value = var.redis_password
}

# --- App-specific secrets ---
# Created only when a value is supplied, so they can be filled now or later
# without blocking the Go-server bootstrap. nonsensitive() is used only to test
# emptiness (for_each keys can't derive from sensitive values); the value stays
# sensitive.
locals {
  # The super-admin username/name are gated on the password hash so the whole
  # trio lands together (and none appears without it). They go through the same
  # map/resource as every other app secret — SecureString, one gate, one
  # aws_ssm_parameter.app. The password is stored ONLY as an argon2id hash
  # (INITIAL_ADMIN_PASSWORD_HASH) — plaintext never touches SSM or state.
  app_secrets = merge({
    "backend/encryption_key"              = var.encryption_key
    "backend/jwt_secret_key"              = var.jwt_secret_key
    "backend/refresh_token_hash_secret"   = var.refresh_token_hash_secret
    "backend/initial_admin_password_hash" = var.initial_admin_password_hash
    "frontend/session_secret"             = var.session_secret
    }, nonsensitive(var.initial_admin_password_hash) == "" ? {} : {
    "backend/initial_admin_username" = var.initial_admin_username
    "backend/initial_admin_name"     = var.initial_admin_name
  })
  app_secrets_set = { for k, v in local.app_secrets : k => v if nonsensitive(v) != "" }
}

resource "aws_ssm_parameter" "app" {
  for_each = local.app_secrets_set

  name  = "/${var.project}/${each.key}"
  type  = "SecureString"
  value = each.value
}
