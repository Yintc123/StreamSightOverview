# ADR 0002：Infra Monitoring 硬體資源評估

- **狀態**：Accepted
- **日期**：2026-07-18
- **範圍**：`infra/terraform/`（EC2 datastore）、`infra/terraform/templates/compose.yml.tftpl`

---

## 背景（Context）

規格書 `StreamSightBackend/docs/specs/infra-monitoring.md` 定義新增 `node-exporter` 與 `mysqld-exporter` 兩個容器至 EC2 datastore，供 FastAPI `InfraSampler` background task 每 5 秒輪詢，採集 OS 層與 MariaDB 引擎層指標。

評估新增這兩個 exporter 後，現有 EC2（`t3.micro`）及 ECS Fargate task 是否需要硬體升級。

---

## 現有基礎設施規格

| 元件 | 規格 | 用途 |
|---|---|---|
| EC2 datastore | `t3.micro`（1 vCPU、1 GiB RAM）、EBS 8 GiB root + 10 GiB data（gp3） | 跑 MariaDB + Redis（Docker Compose） |
| ECS Fargate task | 256 CPU unit（0.25 vCPU）、512 MB | 跑 FastAPI（StreamSightBackend） |

> EC2 規格選型背景見 [ADR 0001 §D4](./0001-infra-cost-optimization.md)：t3.micro 選 free tier，規格已被標注「1 GiB RAM 對 MariaDB + Redis 較緊，記憶體壓力大時升 t3.small」。

---

## 新增元件的資源需求評估

### EC2（新增 node-exporter + mysqld-exporter）

| 元件 | 預估 RSS | CPU 影響 | 磁碟影響 |
|---|---|---|---|
| OS + Docker daemon（現有） | ~150 MB | — | — |
| MariaDB（現有，128 MB buffer pool + 業務） | ~300 MB | — | EBS data |
| Redis（現有） | ~50 MB | — | EBS data |
| **現有合計** | **~500 MB** | | |
| `node-exporter`（靜態二進位，讀 `/proc`、`/sys`） | ~25 MB | 可忽略 | 無 |
| `mysqld-exporter`（輕量，每 5s 查 MariaDB） | ~25 MB | 可忽略 | 無 |
| **新增後合計** | **~550 MB** | | |
| **剩餘餘裕** | **~470 MB** | | |

**結論**：兩個 exporter 合計約 50 MB RSS，EC2 在現有 1 GiB RAM 下有足夠餘裕，**不需升級**。

CPU 方面：`node-exporter` 只讀 Linux procfs（幾乎零 CPU）；`mysqld-exporter` 每 5 秒跑數個 lightweight query，對 MariaDB 無可量測影響。

### ECS Fargate（FastAPI + InfraSampler background task）

| 項目 | 影響 |
|---|---|
| 記憶體 | InfraSampler 僅持前次快照 dict（<1 KB），negligible |
| CPU | 每 5s 兩個 HTTP request + JSON parse + Redis write，遠低於 0.25 vCPU |
| 網路 | 每 5s 兩個 internal HTTP request（exporter payload 約 10–50 KB），可忽略 |

**結論**：256 CPU / 512 MB 完全足夠，**不需升級**。

---

## 決策（Decisions）

### D1. EC2 不升級，維持 t3.micro

新增兩個 exporter 後記憶體合計約 550 MB，距 1 GiB 上限仍有 ~470 MB 餘裕。首期流量低，MariaDB buffer pool 不會膨脹到使用大量記憶體。維持 t3.micro。

### D2. ECS Fargate task 不調整

InfraSampler 的資源佔用遠低於現有 256 CPU / 512 MB 配置的容量，無需調整。

### D3. 同步更新 compose.yml.tftpl

`infra/docker-compose.yml`（本機）已加入兩個 exporter，同步更新正式環境使用的 `infra/terraform/templates/compose.yml.tftpl`，確保 `terraform apply` 後 EC2 上的 compose 與本機一致。

注意：tftpl 中 node-exporter `mount-points-exclude` 正規表達式的 `$` 需寫成 `$$$$`（Terraform `$$$$` → 渲染後 `$$` → Docker Compose 解為字面 `$`）。

---

## 何時該重新檢視（Revisit triggers）

- **MariaDB 記憶體壓力上升**（業務量成長、buffer pool 配置調高）→ 評估升 `t3.small`（2 GiB RAM，~$15/月）。
- **採集頻率提高**（< 5s）→ 重新評估 mysqld-exporter 對 MariaDB 的查詢負擔。
- **多個 FastAPI 實例部署**→ 每個實例都有 InfraSampler，exporter 會承受 N 倍輪詢請求；若有需要，參照 `infra-monitoring.md §1 非目標` 加 leader lease 或限制實例數。

---

## 相關檔案

- `infra/terraform/variables.tf`（`ec2_instance_type`、`task_cpu`、`task_memory` 定義）
- `infra/terraform/ec2_datastores.tf`（EC2 resource）
- `infra/terraform/ecs.tf`（Fargate task definition）
- `infra/terraform/templates/compose.yml.tftpl`（EC2 上實際執行的 compose）
- `infra/docker-compose.yml`（本機對應 compose）
- `StreamSightBackend/docs/specs/infra-monitoring.md`（Infra Monitoring 模組規格）
- `docs/decision/0001-infra-cost-optimization.md`（EC2 規格選型背景）
