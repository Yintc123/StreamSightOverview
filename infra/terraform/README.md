# StreamSight — Terraform deployment

Deploys:

- **CloudFront** → **ALB** → ECS **Fargate** (Go server, health check on `/readyz`)
- **MariaDB + Redis** → single **EC2** running `docker-compose`, data on a dedicated **EBS** volume
- **ECR** for the image, **SSM Parameter Store** for secrets, **GitHub OIDC** roles for CI/CD

HTTPS is served for free on CloudFront's default `*.cloudfront.net` domain. The ALB is
**not public**: its security group only allows CloudFront's edge IP ranges, and the listener
only forwards requests carrying a secret `X-Origin-Verify` header that CloudFront injects — so
the ALB can't be bypassed. Everything else runs in the account's **default VPC**; Fargate tasks
get a public IP (to pull from ECR without a NAT gateway) but are reachable only via the ALB SG.

```
Internet ──HTTPS──► CloudFront ──HTTP+secret header──► ALB ──► ECS Fargate (Go) ──► EC2 (MariaDB + Redis, EBS)
                    *.cloudfront.net    CF edge IPs only            only ALB SG          only ECS SG on 3306/6379
```

**Requires Terraform >= 1.15** (state locking uses S3 natively via `use_lockfile`; no DynamoDB).
CI pins `1.15.8`.

## One-time bootstrap

The CI roles and remote state must exist before CI can run, so the **first apply is local**
with your own admin credentials.

1. **Create the state backend** — just an S3 bucket. State locking is native to S3
   (`use_lockfile`), so **no DynamoDB table is needed**. Then copy the config:

   ```bash
   aws s3api create-bucket --bucket streamsight-tfstate-<unique> --region ap-northeast-2 \
     --create-bucket-configuration LocationConstraint=ap-northeast-2
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
   aws ecr get-login-password --region ap-northeast-2 \
     | docker login --username AWS --password-stdin "$(terraform output -raw ecr_repository_url | cut -d/ -f1)"
   docker build -t "$(terraform output -raw ecr_repository_url):latest" ../../StreamSightGoServer
   docker push "$(terraform output -raw ecr_repository_url):latest"
   ```

## Day-to-day

- **Change infra** → edit `*.tf`, open a PR (CI runs `plan`), merge to `main` (CI runs `apply`).
- **Change the app** → push `StreamSightGoServer/**`; `deploy.yml` builds, pushes, and rolls
  out a new task revision. Terraform ignores `task_definition`/`desired_count` so it won't revert it.

Get the URL: `terraform output cloudfront_url` → `https://<id>.cloudfront.net/readyz`.
(A new CloudFront distribution takes ~5–15 min to finish deploying after the first `apply`.)

## Cost

Tuned for minimum cost (~$22–25/mo, ap-northeast-2, low traffic):

- **ALB ~$18/mo is the fixed floor** — unavoidable while using Fargate (CloudFront needs a
  stable origin and Fargate task IPs are ephemeral). Dropping it means co-locating the Go
  container on the EC2 and pointing CloudFront straight at it.
- **Fargate Spot** (~70% cheaper than on-demand), **EC2 `t3.micro`** (free-tier eligible),
  **Container Insights disabled**, **EBS 10 GiB**, **7-day** log retention.
- No NAT gateway, no Elastic IP, no DynamoDB. CloudFront stays within its 1 TB/mo free tier.
- Region is **Seoul `ap-northeast-2`** — cheaper than Tokyo at similar latency to Taiwan.
  Mumbai `ap-south-1` is cheapest overall but ~100 ms away; Sydney/Hong Kong are pricier. To
  change region, update `var.region` + the workflows' `AWS_REGION` + `backend.hcl`.

## Secrets (SSM Parameter Store)

Secrets are SecureString params (KMS-encrypted, free standard tier), namespaced so the
three apps can **share cleanly**:

| Path | Value | Who reads it |
|------|-------|--------------|
| `/streamsight/shared/db_password` | app DB user password | Go, Backend |
| `/streamsight/shared/redis_password` | Redis password | Go, Backend, Frontend |
| `/streamsight/backend/encryption_key` | AES-256 column key | Backend |
| `/streamsight/backend/jwt_secret_key` | JWT signing | Backend |
| `/streamsight/backend/refresh_token_hash_secret` | refresh-token pepper | Backend |
| `/streamsight/frontend/session_secret` | iron-session signing | Frontend |

**Sharing model**: shared datastore creds live under `shared/` and are read by every app
that connects (Go + Backend hit the same MariaDB user; all three share the one Redis,
separated by `REDIS_KEY_PREFIX`). App-specific secrets live under `backend/` / `frontend/`
and are read only by that app's ECS execution role — **least privilege via path**, e.g. the
backend role gets `ssm:GetParameters` on `/streamsight/shared/*` + `/streamsight/backend/*`.

Notes:
- Only **secrets** go here. Non-secret config (hosts, ports, timeouts, `NEXT_PUBLIC_*`,
  algorithm names, token lifetimes) stays as plain task-def env / build-time env.
- `db_root_password` is **not** in SSM — only EC2 `user_data` uses it to init MariaDB.
- KMS: params use the AWS-managed `alias/aws/ssm` key (free); no extra `kms:Decrypt` grant
  needed. A customer-managed key would require explicit grants.
- Today only the Go server is deployed, so only the `shared/` params are read. The
  backend/frontend params are created now (when a value is set) and get their task-def
  injection + IAM read grants when those services are added to this Terraform.

## Multi-repo deploys (frontend / backend / streamlit)

Each app lives in its own GitHub repo and deploys to ECS with its own CI. `apps.tf`
provisions, per app (`var.ecs_apps`):

- an **ECR repo** (`streamsight-<app>`),
- an **OIDC deploy role** (`streamsight-<app>-deploy`) trusted only by that repo
  (`repo:<owner>/<repo>:*`) — scoped to push its ECR + update its ECS service. No AWS keys
  in GitHub.
- an **ECS execution role** (`streamsight-<app>-execution`) that can read only
  `/streamsight/shared/*` + its own `/streamsight/<app>/*` — this is how the apps **share
  SSM** under least privilege.

Wire-up per repo: set the repo's CI to assume its role from `terraform output
app_deploy_role_arns`, pushing to `terraform output app_ecr_repository_urls`.

> If a real GitHub repo name differs from the default, override `ecs_apps` in
> `terraform.tfvars`. The ECS **services + task defs + public routing** are added later
> (they need per-app exposure decisions); the ECR + roles above work immediately.

## Notes / trade-offs

- MariaDB/Redis on one EC2 is **not HA**. Data lives on the EBS `data` volume (survives instance
  replacement) — enable EBS snapshots for backups. Production-grade = swap to RDS + ElastiCache.
- **Fargate Spot** tasks can be reclaimed (short gap while ECS reschedules). Set the service to
  `FARGATE` for zero interruption at higher cost.
- HTTPS is on the **default `*.cloudfront.net` domain**. For a custom domain, add an ACM cert in
  **us-east-1**, set it as the CloudFront `viewer_certificate` + `aliases`, and add a DNS record.
- CloudFront → ALB is **HTTP** (the ALB has no cert). It's protected by the CloudFront-only SG
  prefix list + secret `X-Origin-Verify` header, but the CF↔origin hop isn't encrypted. For that,
  put a cert/domain on the ALB and switch the origin to `https-only`.
- `github_terraform` role uses `AdministratorAccess` for a simple bootstrap — tighten later.
- Credentials are embedded in EC2 `user_data` (visible to `ec2:DescribeInstanceAttribute`).
  Fine for a small setup; move to SSM-fetched config if that matters.
