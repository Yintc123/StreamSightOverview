# StreamSight

全端串流監控平台（Overview repo）。整合 FastAPI 後端、Next.js BFF 前端、Streamlit 儀表板與 Go 健康檢查服務，搭配 MariaDB、Redis 與 Prometheus exporters，提供資料記錄管理、即時串流監控、RBAC 權限管理與系統可觀測性。

## 專案介紹

StreamSight 由四個應用子專案與共用基礎設施組成：

| 目錄 | Repo | 角色 |
|------|------|------|
| `StreamSightBackend` | [Yintc123/StreamSightBackend](https://github.com/Yintc123/StreamSightBackend) | FastAPI 非同步後端：認證（JWT + Argon2id）、Admin RBAC、資料記錄 CRUD、即時串流、WebSocket 推播、監控 |
| `StreamSightFrontend` | [Yintc123/StreamSightFrontend](https://github.com/Yintc123/StreamSightFrontend) | Next.js 16 前端 + BFF：Route Handlers 對外隱藏真後端，iron-session + Redis session、CSRF 防護、CMS 管理後台 |
| `StreamSightStreamlit` | [Yintc123/StreamSightStreamlit](https://github.com/Yintc123/StreamSightStreamlit) | Streamlit 儀表板：資料管理、即時監控、資料分析、系統管理；純 API Client 不直連 DB，登入委派主前端（JWT 不進瀏覽器） |
| `StreamSightGoServer` | （本 repo 內含） | Go + Gin 健康檢查服務：`/healthz`（liveness）、`/readyz`（DB + Redis readiness） |

### 架構總覽

```
Browser
  └── Frontend (Next.js BFF) :3000
        ├── Backend (FastAPI)  :8000
        │     ├── MariaDB      :3306
        │     └── Redis        :6379
        └── Streamlit          :8501
              └── Backend (FastAPI)（REST + WebSocket）

Prometheus Exporters
  ├── node-exporter   :9100  （主機系統指標）
  └── mysqld-exporter :9104  （MariaDB 指標）

Go Server :8080（獨立健康檢查服務，選用；搭配 infra/docker-compose.yml）
```

安全設計重點：瀏覽器永遠拿不到後端 JWT——只持有 BFF 的加密 session cookie；Streamlit 以同一顆 cookie 向 BFF 換取短命 access token（token 交換，見 Streamlit repo ADR 0003）。

## 技術棧說明

| 子專案 | 主要技術 |
|--------|---------|
| Backend | Python 3.13+ / uv、FastAPI + Uvicorn、SQLAlchemy 2.x (async) + Alembic、MariaDB（asyncmy）、Redis（快取 / Pub-Sub / Streams）、Argon2id、AES-256-CBC 欄位加密、PyJWT、Prometheus client；Ruff + Pyright + pytest |
| Frontend | Next.js 16（App Router）、React 19.2、TypeScript、TailwindCSS v4、TanStack Query v5、Zod v4、iron-session v8 + Redis（ioredis）、OpenTelemetry；Vitest + MSW + Playwright、pnpm 11.6.0 |
| Streamlit | Python 3.9+ / uv、Streamlit（`st.navigation` 多頁面）、pydantic-settings、WebSocket client；pytest + `AppTest` |
| Go Server | Go + Gin、MariaDB / Redis 連線探測 |
| 基礎設施 | Docker Compose、MariaDB 11.7、Redis 7、prom/node-exporter、prom/mysqld-exporter |

各子專案均採嚴格 TDD 開發，附完整測試、CI 與架構決策記錄（ADR / specs），詳見各自 repo 的 `docs/`。

## 前置需求

| 工具 | 最低版本 |
|------|---------|
| Git | 任意 |
| Docker Desktop（或 Docker Engine + Compose Plugin）| Docker 24+ |

僅整合部署時只需要 Docker；要在本機直接跑各子專案開發，另需 Python 3.13+ / [uv](https://docs.astral.sh/uv/)（Backend、Streamlit）、Node.js 22+ / pnpm 11.6.0（Frontend）、Go（GoServer）。

## 本地運行步驟

### 1. Clone 本 repo

```bash
git clone https://github.com/Yintc123/StreamSight.git
cd StreamSight
```

### 2. 執行初始化腳本（產生 `.env`）

腳本會自動 clone 三個應用子專案、互動式設定初始管理員帳號，並以 `.env.example` 為基底產生根目錄 `.env`（含四組隨機 secrets）。

**macOS / Linux**

```bash
sh setup.sh
```

**Windows（PowerShell）**

```powershell
# 首次執行需先解除限制
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

.\setup.ps1
```

腳本執行過程中會詢問：

```
--- 初始管理員設定 ---
  Username [admin]:           ← 直接 Enter 使用預設值
  Display name [Administrator]:
  Password:                   ← 輸入時不顯示字元（8–128 字元）
  確認密碼:
```

腳本會將你的輸入寫入 `.env` 的 `INITIAL_ADMIN_USERNAME` / `INITIAL_ADMIN_NAME` / `INITIAL_ADMIN_PASSWORD`，並自動產生 `ENCRYPTION_KEY`、`JWT_SECRET_KEY`、`REFRESH_TOKEN_HASH_SECRET`、`SESSION_SECRET` 四組 48-byte 隨機 secrets（詳見下方「測試帳號資訊」）。

### 3. 啟動全部服務

```bash
docker compose up -d
```

Backend 容器啟動時會自動執行 `alembic upgrade head`（含 seed 假資料）並依 `INITIAL_ADMIN_*` 建立 root 管理員，無需手動跑 migration。

啟動完成後各服務位址：

| 服務 | 位址 |
|------|------|
| Frontend（Next.js） | http://localhost:3000 |
| Backend（FastAPI）  | http://localhost:8000 |
| Streamlit 儀表板   | http://localhost:8501 |
| MariaDB            | localhost:3306 |
| Redis              | localhost:6379 |
| node-exporter      | http://localhost:9100/metrics |
| mysqld-exporter    | http://localhost:9104/metrics |

打開 http://localhost:3000 以初始管理員帳密登入即可進入 CMS 後台。

### 子專案本機開發（非 Docker）

各子專案可獨立於本機開發（基礎設施可用 `infra/docker-compose.yml` 只起 MariaDB + Redis）：

```bash
# 只啟動 MariaDB + Redis
docker compose -f infra/docker-compose.yml up -d

# Backend
cd StreamSightBackend && uv sync --dev && uv run alembic upgrade head
uv run uvicorn app.main:app --reload            # → :8000

# Frontend（mock 模式不需後端與 Redis）
cd StreamSightFrontend && pnpm install
cp .env.example .env.local                      # 填 SESSION_SECRET，開發可設 USE_MOCK=1
pnpm dev                                        # → :3000

# Streamlit（預設 USE_MOCK=true，離線可跑）
cd StreamSightStreamlit && uv sync
cp .env.example .env
uv run streamlit run app.py                     # → :8501

# Go Server
cd StreamSightGoServer
cp .env.example .env && export $(grep -v '^#' .env | xargs)
go run .                                        # → :8080
```

詳細開發流程（測試、lint、TDD 規範）請參閱各子專案 README。

## Docker 部署指令

```bash
# 啟動全部服務（背景執行）
docker compose up -d

# 只啟動特定服務（依賴會自動帶起，如 backend → mariadb、redis）
docker compose up -d backend streamlit

# 查看服務狀態 / 健康檢查
docker compose ps

# 追蹤某服務的 log
docker compose logs -f frontend

# 修改 source code 後重新 build 並啟動
docker compose up -d --build backend

# 重啟服務
docker compose restart backend

# 停止全部服務
docker compose down

# 停止並清除所有 volumes（會刪除資料庫資料）
docker compose down -v
```

單一子專案的獨立 `docker build` / `docker run` 指令，見各子專案 README 的 Docker 章節。

## API 文件連結

| 文件 | 連結 | 說明 |
|------|------|------|
| Backend Swagger UI | <http://localhost:8000/docs> | FastAPI 自動生成的互動式文件（可直接發送請求） |
| Backend ReDoc | <http://localhost:8000/redoc> | 同一份 OpenAPI 的閱讀版 |
| OpenAPI Schema | <http://localhost:8000/openapi.json> | 機器可讀 OpenAPI 3.1 規格（可匯入 Postman / codegen） |
| Backend API 端點總表 | [StreamSightBackend/README.md](./StreamSightBackend/README.md#api-端點) | `/auth`、`/users`、`/admin`、`/records`、`/realtime`、`/ws`、`/monitoring`、`/health` |
| BFF Route Handlers | [StreamSightFrontend/README.md](./StreamSightFrontend/README.md#頁面與-bff-route-總覽) | 瀏覽器實際呼叫的 `/api/*`（登入、session、CSRF、CMS 管理） |
| Go Server 端點 | [StreamSightGoServer/README.md](./StreamSightGoServer/README.md) | `GET /healthz`、`GET /readyz` |

> 瀏覽器端一律走 BFF（`/api/*`）；Backend 為內網 domain API，文件位址以本機 `docker compose` 部署（port 8000）為準。

## 測試帳號資訊

> ⚠️ 以下帳號僅供**開發 / 展示環境**使用，正式環境部署前應更換所有密碼並移除 seed migration。

### 初始管理員（Root Admin）— 由 `setup.sh` / `setup.ps1` 產生到 `.env`

**本專案不內建任何寫死的管理員帳密。** 初始管理員帳密必須透過初始化腳本產生：

1. 執行 `sh setup.sh`（macOS / Linux）或 `.\setup.ps1`（Windows）。
2. 腳本互動式詢問 Username（預設 `admin`）、Display name 與 Password（8–128 字元，輸入不回顯，需確認兩次）。
3. 腳本將結果寫入根目錄 `.env`：

   ```env
   INITIAL_ADMIN_USERNAME=admin        # 你輸入的帳號（自動轉小寫）
   INITIAL_ADMIN_NAME=Administrator    # 顯示名稱
   INITIAL_ADMIN_PASSWORD=********     # 你輸入的密碼
   ```

4. Backend 首次啟動時讀取這三個變數，自動在 DB upsert 一個 `ROOT` 角色的管理員（受保護，不可透過 API 降級或停用）。

之後即可用這組帳密登入：

| 入口 | 位址 |
|------|------|
| 前端 CMS | http://localhost:3000 （首頁登入卡） |
| 後端 API | `POST http://localhost:8000/admin/auth/login` |

若要重設帳密：修改 `.env` 的 `INITIAL_ADMIN_*` 後 `docker compose up -d --build backend`（或重新執行 setup 腳本覆蓋 `.env`）。`.env` 含密碼與 secrets，**已被 gitignore，切勿提交到版本控制**。

### Seed Admin（migration 自動種入）

Backend 執行 `alembic upgrade head`（容器啟動時自動執行）會種入 10 位測試 Admin，**共用密碼 `SeedAdmin#2026!`**，供 RBAC 權限展示：

| 帳號 | 角色 | | 帳號 | 角色 |
|------|------|-|------|------|
| `seed_admin_01` | VIEWER | | `seed_admin_06` | EDITOR |
| `seed_admin_02` | EDITOR | | `seed_admin_07` | SUPER_ADMIN |
| `seed_admin_03` | SUPER_ADMIN | | `seed_admin_08` | SUPER_ADMIN |
| `seed_admin_04` | VIEWER | | `seed_admin_09` | VIEWER |
| `seed_admin_05` | EDITOR | | `seed_admin_10` | EDITOR |

同一批 migration 亦會種入 300 筆測試 Records，供列表、搜尋與分頁展示。角色權限：`VIEWER` 唯讀、`EDITOR` 可增改刪資料、`SUPER_ADMIN` 可管理其他 Admin。移除方式見 [Backend README](./StreamSightBackend/README.md#測試帳號)。

### Frontend Mock 模式帳號（僅 `USE_MOCK=1`）

Frontend 單獨以 mock 模式開發時（不接真後端），login handler 不驗證帳密——任意帳密皆可登入，登入後固定為 root 管理員身分。e2e 測試慣例使用 `admin` / `admin-dev-password-change-me`。整合部署（`docker compose up -d`）走真後端，此帳號無效。

## 環境變數說明

`.env` 由 `setup.sh` / `setup.ps1` 自動從 `.env.example` 產生，以下為常見需手動調整的欄位：

| 變數 | 預設值 | 說明 |
|------|-------|------|
| `INITIAL_ADMIN_USERNAME` / `_NAME` / `_PASSWORD` | 由腳本互動設定 | 初始管理員（Backend 首次啟動 upsert） |
| `DB_PASSWORD` | `streamsight` | MariaDB 應用帳號密碼 |
| `DB_ROOT_PASSWORD` | `root` | MariaDB root 密碼 |
| `REDIS_PASSWORD` | （空） | Redis 密碼，留空表示不啟用認證 |
| `ALLOWED_ORIGINS` | `http://localhost:3000,...` | CORS / CSRF 允許的來源，多個以逗號分隔 |
| `NEXT_PUBLIC_APP_NAME` | `StreamSight` | 前端顯示名稱（build-time 注入，改動後需重新 build image） |

> **注意**：`ENCRYPTION_KEY`、`JWT_SECRET_KEY`、`REFRESH_TOKEN_HASH_SECRET`、`SESSION_SECRET` 這四個 secrets 由腳本自動產生（48-byte random base64），**不要手動填入或提交到版本控制**。其中 `ENCRYPTION_KEY` 一旦有資料寫入即不可更改，否則既有加密欄位將無法解密。

完整變數清單見 [`.env.example`](./.env.example)（含分組說明），各子專案的進階參數見其 README。

## 常見問題

**Q: `docker compose up` 後 backend 一直 restart？**
先確認 MariaDB 是否已 healthy：`docker compose ps`，若還在 starting 請等幾秒再試。

**Q: 修改了前端 `NEXT_PUBLIC_*` 變數沒有生效？**
這類變數在 build 階段注入，需重新 build image：`docker compose up -d --build frontend`。

**Q: Windows 上執行 `setup.ps1` 出現「無法執行指令碼」？**
執行 `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser` 後重試。

**Q: 忘記初始管理員密碼？**
修改 `.env` 的 `INITIAL_ADMIN_PASSWORD` 後重啟 backend（`docker compose restart backend`），啟動時會 upsert 更新密碼。

## 子專案文件

各子專案的完整開發說明（測試、TDD 規範、架構決策、規格書）：

- [StreamSightBackend/README.md](./StreamSightBackend/README.md) — API 端點、RBAC、安全機制、`docs/decisions` 與 `docs/specs`
- [StreamSightFrontend/README.md](./StreamSightFrontend/README.md) — BFF 骨架能力、部署（ECS / Terraform）、`docs/architecture.md` 與 ADR
- [StreamSightStreamlit/README.md](./StreamSightStreamlit/README.md) — 頁面結構、認證流程（token 交換）、ADR
- [StreamSightGoServer/README.md](./StreamSightGoServer/README.md) — 健康檢查端點與設定
