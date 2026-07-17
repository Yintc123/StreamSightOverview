# StreamSightGoServer

A minimal Go + Gin service exposing health checks for the server itself, MariaDB, and Redis.

## Endpoints

| Method | Path       | Purpose                                                        |
|--------|------------|---------------------------------------------------------------|
| GET    | `/healthz` | Liveness — process is up (no external deps). Use for ECS/ALB liveness. |
| GET    | `/readyz`  | Readiness — pings DB + Redis. Returns `503` if any is down.    |

`/readyz` response:

```json
{ "status": "ok", "checks": { "server": "ok", "db": "ok", "redis": "ok" } }
```

## Run locally

```bash
# start MariaDB + Redis
docker compose -f ../infra/docker-compose.yml up -d

cp .env.example .env   # optional; defaults already match infra/
export $(grep -v '^#' .env | xargs)   # or use a dotenv loader
go run .

curl localhost:8080/healthz
curl localhost:8080/readyz
```

## Configuration

All via environment variables — see `.env.example`. Defaults match `infra/docker-compose.yml`.

## Docker

```bash
docker build -t streamsight-go-server .
docker run --rm -p 8080:8080 --env-file .env streamsight-go-server
```
