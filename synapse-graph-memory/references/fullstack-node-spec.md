# Full-Stack Node Specification (V3.3)

> Loaded on-demand when full-stack node types (db_/api_/ui_/dep_) are present.
> For base node types (proj_/mod_/feat_), see `node-spec.md`.

## Node Types

Synapse has seven node types overall: `project`, `module`, `feature`, plus the four full-stack types below.

| Prefix | Type | Purpose | Granularity |
|--------|------|---------|-------------|
| `db_` | database_table | Database table with business-logic columns | One node per table |
| `api_` | api_endpoint_group | Group of API endpoints (one router file) | One node per router file |
| `ui_` | ui_page | Frontend page or major tab section | One node per page; split tabs if domain overlap < 30% |
| `dep_` | deployment | Deployment unit as terminal anchor | One node per deployment unit (max 5) |

## Patch Rules

### P1: db_ Nodes — Skeleton Fields Only

Columns table must only list business-logic fields (those referenced in WHERE/JOIN/IF
conditions in application code). Audit fields (created_at, updated_at, remark, etc.)
must be omitted or replaced with `... (省略 N 个辅助字段)`.

### P2: ui_ Nodes — Tab-Level Exception

When a single page aggregates 3+ unrelated business domains AND the resulting
`depends_on` overlap between them is < 30%, split into `ui_<page>-<tab>` nodes.

### P3: Bidirectional Edges — Single Source of Truth

`depends_on` in YAML frontmatter is the ONLY write source for graph edges.
Reverse edges in `## Connection Points` sections are READ-ONLY display text
auto-injected by the engine. The post-tool-use hook REJECTS manual `blocks`
or reverse-dependency YAML entries.

### P4: dep_ Nodes — Terminal Anchors, Not Deployment Docs

dep_ nodes record WHAT communicates in the deployment environment, not HOW to deploy.
Focus on Environment Bridges — which env vars connect services.

---

## db_ Node Template

```yaml
---
id: db_orders
type: database_table
engine: InnoDB
depends_on: []
auto_linked: [api_order-routes, feat_payment]
tags: [order, payment, transaction]
summary: 订单主表，记录每笔交易的状态和金额
---
## Columns (仅业务骨架字段，辅助字段省略)
| 列名 | 类型 | 约束 | 说明 |
|------|------|------|------|
| id | BIGINT | PK | |
| user_id | BIGINT | FK → users.id | |
| status | ENUM(...) | NOT NULL | 支付状态流转 |
| amount | DECIMAL(10,2) | NOT NULL | |
| ... | ... | (省略 12 个辅助字段) | |

## Connection Points
- **写入方**: api_order-routes (POST /orders, PUT /orders/:id/status)
- **读取方**: api_payment-routes, api_report-routes

## Change Log
- 2026-05-24: Auto-detected (init.sh --fullstack)
```

## api_ Node Template

```yaml
---
id: api_payment-routes
type: api_endpoint_group
framework: FastAPI
source: src/routes/payment.py
depends_on: [mod_alipay-sdk, db_orders, db_transactions]
auto_linked: [feat_payment, ui_checkout-page]
summary: 支付相关接口：扫码支付、回调通知、退款、查询
---
## Endpoints
| 方法 | 路径 | 说明 | 状态 |
|------|------|------|------|
| POST | /api/v1/payments/qr | 生成扫码支付二维码 | done |
| POST | /api/v1/payments/callback | 支付宝回调通知 | done |
| POST | /api/v1/payments/refund | 申请退款 | todo |

## Connection Points
- **读写**: db_orders (orders 表), db_transactions (transaction_log 表)
- **调用**: mod_alipay-sdk (支付宝 API 封装)

## Change Log
- 2026-05-24: Auto-detected (init.sh --fullstack)
```

## ui_ Node Template

```yaml
---
id: ui_checkout-page
type: ui_page
framework: React 18 + Tailwind
source: src/pages/Checkout.tsx
depends_on: [mod_design-system, api_payment-routes, api_cart-routes]
auto_linked: [feat_payment, db_orders]
summary: 结算页面：购物车清单 → 选择支付方式 → 扫码支付 → 等待回调
---
## States
- cart_loaded → payment_pending → payment_success | payment_failed | payment_timeout

## API 调用
- GET /api/v1/cart (页面加载)
- POST /api/v1/payments/qr (点击支付)
- GET /api/v1/payments/status/:order_id (轮询支付结果)

## Change Log
- 2026-05-24: Auto-detected (init.sh --fullstack)
```

## dep_ Node Template

```yaml
---
id: dep_container-config
type: deployment
depends_on: [db_orders, db_users]
auto_linked: [api_payment-routes]
tags: [docker, postgres, redis]
summary: 生产环境容器编排，app + postgres + redis 通过 docker-compose 网络互通
---
## Environment Bridges
| 变量 | 连接 | 说明 |
|------|------|------|
| DATABASE_URL | api_* → db_* | postgres://user:pass@postgres:5432/mydb |
| REDIS_URL | api_payment-routes → redis | redis://redis:6379/0 (支付状态缓存) |

## Change Log
- 2026-05-24: Auto-detected (init.sh --fullstack)
```
