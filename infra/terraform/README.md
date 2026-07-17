# StreamSight — Terraform deployment

Deploys:

- **StreamSightGoServer** → ECS **Fargate** behind a public **ALB** (health check on `/readyz`)
- **MariaDB + Redis** → single **EC2** running `docker-compose`, data on a dedicated **EBS** volume
- **ECR** for the image, **SSM Parameter Store** for secrets, **GitHub OIDC** roles for CI/CD

Everything runs in the account's **default VPC**. Fargate tasks get a public IP (needed to
pull from ECR without a NAT gateway) but are only reachable through the ALB security group.

```
Internet ──► ALB ──► ECS Fargate (Go) ──► EC2 (MariaDB + Redis, EBS)
                         only ALB SG            only ECS SG on 3306/6379
```

**Requires Terraform >= 1.15** (state locking uses S3 natively via `use_lockfile`; no DynamoDB).
CI pins `1.15.8`.

## One-time bootstrap

The CI roles and remote state must exist before CI can run, so the **first apply is local**
with your own admin credentials.

1. **Create the state backend** — just an S3 bucket. State locking is native to S3
   (`use_lockfile`), so **no DynamoDB table is needed**. Then copy the config:

   ```bash
   aws s3api create-bucket --bucket streamsight-tfstate-<unique> --region ap-northeast-1 \
     --create-bucket-configuration LocationConstraint=ap-northeast-1
   aws s3api put-bucket-versioning --bucket streamsight-tfstate-<unique> \
     --versioning-configuration Status=Enabled

   cp backend.hcl.example backend.hcl   # edit the bucket name
   cp terraform.tfvars.example terraform.tfvars   # set the 3 passwords
   ```

2. **Apply:**

   ```bash
   terraform init -backend-config=backend.hcl
   terraform apply
   ```

3. **Wire up GitHub** using the outputs:

   | GitHub secret       | Value                                   |
   |---------------------|-----------------------------------------|
   | `TF_ROLE_ARN`       | `terraform output github_terraform_role_arn` |
   | `DEPLOY_ROLE_ARN`   | `terraform output github_deploy_role_arn`    |
   | `DB_PASSWORD`       | same as `db_password`                   |
   | `DB_ROOT_PASSWORD`  | same as `db_root_password`              |
   | `REDIS_PASSWORD`    | same as `redis_password`                |

   Also commit `backend.hcl` (no secrets) so the `terraform.yml` workflow can `init`.

4. **First image.** The ECS service can't stabilise until an image exists. Either let the
   `deploy.yml` workflow run (push to `main`), or push once manually:

   ```bash
   aws ecr get-login-password --region ap-northeast-1 \
     | docker login --username AWS --password-stdin "$(terraform output -raw ecr_repository_url | cut -d/ -f1)"
   docker build -t "$(terraform output -raw ecr_repository_url):latest" ../../StreamSightGoServer
   docker push "$(terraform output -raw ecr_repository_url):latest"
   ```

## Day-to-day

- **Change infra** → edit `*.tf`, open a PR (CI runs `plan`), merge to `main` (CI runs `apply`).
- **Change the app** → push `StreamSightGoServer/**`; `deploy.yml` builds, pushes, and rolls
  out a new task revision. Terraform ignores `task_definition`/`desired_count` so it won't revert it.

Get the URL: `terraform output alb_dns_name` → `http://<dns>/readyz`.

## Notes / trade-offs

- MariaDB/Redis on one EC2 is **not HA**. Data lives on the EBS `data` volume (survives instance
  replacement) — enable EBS snapshots for backups. Production-grade = swap to RDS + ElastiCache.
- ALB is **HTTP only**. Add an ACM cert + `443` listener (and Route53) for HTTPS.
- `github_terraform` role uses `AdministratorAccess` for a simple bootstrap — tighten later.
- Credentials are embedded in EC2 `user_data` (visible to `ec2:DescribeInstanceAttribute`).
  Fine for a small setup; move to SSM-fetched config if that matters.
