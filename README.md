# StreamSight

全端串流監控平台，包含 FastAPI 後端、Next.js 前端、Streamlit 儀表板，以及 MariaDB、Redis 與 Prometheus exporter。

## 架構總覽

```
Browser
  └── Frontend (Next.js BFF) :3000
        ├── Backend (FastAPI)  :8000
        │     ├── MariaDB      :3306
        │     └── Redis        :6379
        └── Streamlit          :8501
              └── Backend (FastAPI)

Prometheus Exporters
  ├── node-exporter   :9100  （主機系統指標）
  └── mysqld-exporter :9104  （MariaDB 指標）
```

## 前置需求

| 工具 | 最低版本 |
|------|---------|
| Git | 任意 |
| Docker Desktop（或 Docker Engine + Compose Plugin）| Docker 24+ |

## 快速啟動

### 1. Clone 本 repo

```bash
git clone https://github.com/Yintc123/StreamSight.git
cd StreamSight
```

### 2. 執行初始化腳本

腳本會自動 clone 三個子專案、互動式設定管理員帳號，並產生 `.env`（含隨機 secrets）。

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
  Password:                   ← 輸入時不顯示字元
  確認密碼:
```

### 3. 啟動全部服務

```bash
docker compose up -d
```

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

## 常用指令

```bash
# 只啟動特定服務
docker compose up -d backend streamlit

# 追蹤某服務的 log
docker compose logs -f frontend

# 重新 build 並啟動（修改了 source code 後）
docker compose up -d --build backend

# 停止並清除所有 volumes（會刪除資料庫資料）
docker compose down -v
```

## 環境變數說明

`.env` 由 `setup.sh` / `setup.ps1` 自動從 `.env.example` 產生，以下為常見需手動調整的欄位：

| 變數 | 預設值 | 說明 |
|------|-------|------|
| `DB_PASSWORD` | `streamsight` | MariaDB 應用帳號密碼 |
| `DB_ROOT_PASSWORD` | `root` | MariaDB root 密碼 |
| `REDIS_PASSWORD` | （空） | Redis 密碼，留空表示不啟用認證 |
| `ALLOWED_ORIGINS` | `http://localhost:3000,...` | CORS 允許的來源，多個以逗號分隔 |
| `NEXT_PUBLIC_APP_NAME` | `StreamSight` | 前端顯示名稱（改動後需重新 build image） |

> **注意**：`ENCRYPTION_KEY`、`JWT_SECRET_KEY`、`REFRESH_TOKEN_HASH_SECRET`、`SESSION_SECRET` 這四個 secrets 由腳本自動產生（48-byte random base64），**不要手動填入或提交到版本控制**。

## 子專案

| 目錄 | Repo | 說明 |
|------|------|------|
| `StreamSightBackend` | [Yintc123/StreamSightBackend](https://github.com/Yintc123/StreamSightBackend) | FastAPI 後端 API |
| `StreamSightFrontend` | [Yintc123/StreamSightFrontend](https://github.com/Yintc123/StreamSightFrontend) | Next.js BFF + 前端 |
| `StreamSightStreamlit` | [Yintc123/StreamSightStreamlit](https://github.com/Yintc123/StreamSightStreamlit) | Streamlit 儀表板 |

各子專案的本機開發說明請參閱各自 repo 的 README。

## 常見問題

**Q: `docker compose up` 後 backend 一直 restart？**
先確認 MariaDB 是否已 healthy：`docker compose ps`，若還在 starting 請等幾秒再試。

**Q: 修改了前端 `NEXT_PUBLIC_*` 變數沒有生效？**
這類變數在 build 階段注入，需重新 build image：`docker compose up -d --build frontend`。

**Q: Windows 上執行 `setup.ps1` 出現「無法執行指令碼」？**
以系統管理員身份執行：`Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser`，然後重試。
