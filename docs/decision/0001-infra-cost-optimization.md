# ADR 0001：基礎設施成本優化決策

- **狀態**：Accepted
- **日期**：2026-07-17
- **範圍**：`infra/terraform/`（StreamSightGoServer + MariaDB/Redis 的 AWS 部署）

---

## 背景（Context）

要把 Go Gin 服務 + MariaDB/Redis 部署到 AWS,並以 **Terraform + GitHub Actions** 管理。
目標是在維持既定架構(ECS Fargate 前面掛 ALB、再加 CloudFront 提供 HTTPS)的前提下,
**盡可能壓低每月固定成本**,適用於小流量 / 個人專案的階段。

## 架構總覽

```
Internet ──HTTPS──► CloudFront ──HTTP + 祕密 header──► ALB ──► ECS Fargate (Go)
                    *.cloudfront.net    只放 CF 邊緣 IP                 │
                                                                        ▼
                                          EC2 (docker-compose: MariaDB + Redis, EBS)
```

- Fargate task 以私有 IP 連同一 VPC 內 EC2 的 MariaDB/Redis,Security Group 限制只有 ECS 進得來。
- 全部跑在帳號的 **default VPC**(省去 NAT Gateway 成本)。

## 成本分析(ap-northeast-2、低流量、每月粗估)

| 項目 | 設定 | 月費粗估 | 備註 |
|------|------|---------|------|
| **ALB** | Application LB | **~$18** | 固定費用,**最大宗且省不掉**(見下) |
| EC2 | t3.micro | ~$0–7.5 | 首年 free tier 可近 $0 |
| Fargate | 0.25 vCPU / 0.5 GB,**Spot** | ~$3 | Spot 比 on-demand 省 ~70% |
| EBS | 8 + 10 GB gp3 | ~$1.5 | |
| CloudFront | PriceClass_200 | ~$0 | 1TB/月 永久免費額度內 |
| Container Insights | **停用** | $0 | 原本 enabled 會多收 CloudWatch 費 |
| NAT / EIP / DynamoDB | 無 | $0 | 刻意避開 |
| **合計** | | **~$22–25/mo** | ALB 佔大半 |

## 決策(Decisions）

### D1. 保留 Fargate + ALB,不收成單台 EC2
- **關鍵事實**:CloudFront 需要一個**穩定的網域**當 origin,而 Fargate task 的 public IP 每次
  部署都會變 —— 因此只要用 Fargate,就必須有 ALB(或 NLB,價格相近)頂著。**ALB 的 ~$18/mo
  是這個架構的結構性下限,無法在保留 Fargate 的情況下省掉。**
- 真正的「最小成本」是把 Go 容器改成跟 MariaDB/Redis 同一台 EC2、CloudFront 直指 EC2(~$8/mo,
  首年 free tier 近 $0),但這會**推翻 ECS 架構、且部署機制要重寫**。
- **取捨**:選擇保留 ECS 架構(部署乾淨、可水平擴展、CI/CD 已成形),接受 ALB 的固定成本。

### D2. Fargate 改用 Spot(FARGATE_SPOT）
- 比 on-demand 省 ~70%。
- **取捨**:Spot task 可能被回收,ECS 重排會有幾分鐘空窗。小服務可接受;要零中斷改回 `FARGATE`。

### D3. 停用 Container Insights
- Container Insights 是 CloudWatch 的**指標/儀表板**功能,會額外收費。
- **重點**:應用程式 log(Go 容器 stdout)走獨立的 CloudWatch Log Group `/ecs/streamsight`,
  **不受影響**;ECS 基本 CPU/記憶體指標仍免費。只損失聚合圖表。

### D4. EC2 t3.small → t3.micro、EBS data 20 → 10 GB
- t3.micro 為 free tier 資格機型(首年 750 hrs/月)。
- **取捨**:t3.micro 僅 1 GB RAM,MariaDB + Redis 同機較緊;記憶體壓力大時升 t3.small。

### D5. Region 選首爾 ap-northeast-2
- 亞洲 region 成本比較(便宜→貴):**孟買 ap-south-1**(最便宜但離台灣 ~100ms)>
  **首爾 ap-northeast-2**(便宜且延遲 ~40ms)> 東京 ap-northeast-1 > 新加坡 >
  **雪梨 ap-southeast-2 / 香港 ap-east-1**(偏貴)。
- 美國 us-east-1 最便宜(便宜 20~30%),但對台灣使用者 +150~200ms 延遲,不划算。
- **結論**:首爾是「便宜 + 低延遲」的甜蜜點,優於現況東京。
- **註**:region 這一刀每月僅差幾 %,遠不如 ALB 那筆固定費重要,屬小槓桿。

### D6. CloudFront 維持 PriceClass_200(含亞洲節點)
- CloudFront 有 1TB/月 的永久免費額度,小流量下 `_100` 與 `_200` 的**成本差幾乎為 0**,
  差別只在亞洲使用者延遲。故不為省錢犧牲延遲,保留含亞洲節點的 `_200`。

### D7. Terraform state 用 S3 原生鎖(use_lockfile),不建 DynamoDB
- Terraform 1.10+ 支援 S3 原生 state locking,鎖檔直接寫在同一個 S3 bucket。
- 少一個 DynamoDB 表要管、也少一點費用;bootstrap 更簡單。

## 被否決的替代方案

| 方案 | 為何否決 |
|------|---------|
| 收成單台 EC2(拿掉 ALB+Fargate) | 最便宜(~$8),但推翻 ECS 架構、部署要重寫。保留架構優先。 |
| Region 搬美國 us-east-1 | 便宜 20~30%,但台灣使用者延遲 +150~200ms,不值得。 |
| Region 用雪梨/香港 | 又貴又(雪梨)遠。 |
| CloudFront PriceClass_100 | 免費額度內成本差近 0,只換來亞洲延遲變差,無意義。 |
| DynamoDB state lock | Terraform 1.10+ 有 S3 原生鎖,多此一舉。 |

## 預估結果

- 從初版 **~$47/mo** 降到 **~$22–25/mo**(首年 free tier 可再更低)。
- 其中 **ALB ~$18** 是結構性下限。

## 何時該重新檢視（Revisit triggers）

- 流量成長到 Fargate Spot 中斷會影響使用者 → 改回 on-demand 或加 task 數。
- MariaDB/Redis 出現記憶體壓力 → EC2 升 t3.small,或轉 RDS + ElastiCache(進入 production-grade)。
- 需要自訂網域 → 在 **us-east-1** 簽 ACM 憑證接到 CloudFront。
- 要求資料庫高可用 / 自動備援 → 從單台 EC2 轉 RDS + ElastiCache。

## 相關檔案

- `infra/terraform/`(實作)
- `infra/terraform/README.md`(bootstrap 與 trade-off 說明)
