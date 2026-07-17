variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "ap-northeast-1"
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

variable "container_port" {
  description = "Port the Go server listens on."
  type        = number
  default     = 8080
}

variable "image_tag" {
  description = "ECR image tag used at bootstrap. The app pipeline overrides this on each deploy."
  type        = string
  default     = "latest"
}

# ---- Datastore EC2 ----

variable "ec2_instance_type" {
  type    = string
  default = "t3.small"
}

variable "data_volume_size" {
  description = "EBS data volume (GiB) for MariaDB + Redis persistence."
  type        = number
  default     = 20
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
