variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "ap-northeast-2"
}

variable "project" {
  description = "Name prefix for all resources."
  type        = string
  default     = "streamsight"
}

variable "github_repo" {
  description = "owner/name of the GitHub repo allowed to assume the CI roles via OIDC."
  type        = string
  default     = "Yintc123/StreamSightOverview"
}

variable "deploy_branch" {
  description = "Only OIDC tokens from this branch may assume the CI/deploy roles. Restricts CI/CD to this branch across all apps."
  type        = string
  default     = "main"
}

variable "container_port" {
  description = "Port the Go server listens on."
  type        = number
  default     = 8080
}

variable "cloudfront_price_class" {
  description = "CloudFront edge coverage. PriceClass_200 includes Asia; _100 is US/EU only (cheapest)."
  type        = string
  default     = "PriceClass_200"
}

variable "image_tag" {
  description = "ECR image tag used at bootstrap. The app pipeline overrides this on each deploy."
  type        = string
  default     = "latest"
}

# ---- Datastore EC2 ----

variable "ec2_instance_type" {
  # t3.micro is free-tier eligible (750 hrs/mo for 12 months). 1 GiB RAM is
  # tight for MariaDB + Redis; bump to t3.small if you hit memory pressure.
  type    = string
  default = "t3.micro"
}

variable "data_volume_size" {
  description = "EBS data volume (GiB) for MariaDB + Redis persistence."
  type        = number
  default     = 10
}

variable "ssh_ingress_cidr" {
  description = "CIDR allowed to SSH to the datastore EC2 (e.g. your.ip/32). Empty disables SSH."
  type        = string
  default     = ""
}

variable "key_pair_name" {
  description = "Existing EC2 key pair name for SSH. Empty = no key."
  type        = string
  default     = ""
}

# ---- Datastore credentials (sensitive) ----

variable "db_name" {
  type    = string
  default = "streamsight"
}

variable "db_user" {
  type    = string
  default = "streamsight"
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "db_root_password" {
  type      = string
  sensitive = true
}

variable "redis_password" {
  type      = string
  sensitive = true
}

# ---- App secrets (optional; a SecureString is created in SSM only when set).
# Injected into the backend/frontend ECS tasks when those services deploy. ----

variable "encryption_key" {
  description = "Backend AES-256 column encryption key (>= 32 chars)."
  type        = string
  default     = ""
  sensitive   = true
}

variable "jwt_secret_key" {
  description = "Backend JWT signing secret (>= 32 chars)."
  type        = string
  default     = ""
  sensitive   = true
}

variable "refresh_token_hash_secret" {
  description = "Backend refresh-token hash pepper (>= 32 chars, distinct from jwt_secret_key)."
  type        = string
  default     = ""
  sensitive   = true
}

variable "session_secret" {
  description = "Frontend iron-session signing secret (>= 32 chars)."
  type        = string
  default     = ""
  sensitive   = true
}

variable "initial_admin_password_hash" {
  description = "Backend super-admin argon2id password hash (INITIAL_ADMIN_PASSWORD_HASH). Pre-hash the password — plaintext never touches SSM/state. Enables the config-backed super admin together with the username."
  type        = string
  default     = ""
  sensitive   = true
}

variable "initial_admin_username" {
  description = "Backend super-admin username (INITIAL_ADMIN_USERNAME). Stored in SSM alongside the hash (same mechanism), created only when the hash is set."
  type        = string
  default     = "admin"
}

variable "initial_admin_name" {
  description = "Backend super-admin display name (INITIAL_ADMIN_NAME; optional, empty → username). Stored in SSM alongside the hash, created only when the hash is set."
  type        = string
  default     = "Administrator"
}

# ---- ECS service sizing ----

variable "desired_count" {
  type    = number
  default = 1
}

variable "task_cpu" {
  type    = number
  default = 256
}

variable "task_memory" {
  type    = number
  default = 512
}
