#!/usr/bin/env bash
# benchmark.sh — Measure Synapse token efficiency vs flat-file baseline.
# Usage:
#   bash scripts/benchmark.sh setup    — create test project + flat equivalent
#   bash scripts/benchmark.sh run      — simulate retrieval and report savings
#   bash scripts/benchmark.sh clean    — remove test artifacts
set -euo pipefail

if (( BASH_VERSINFO[0] < 4 )); then
  echo "Error: requires bash 4+ (current: $BASH_VERSION)" >&2
  echo "macOS: brew install bash; ensure /opt/homebrew/bin or /usr/local/bin in PATH" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BENCH_DIR="${SCRIPT_DIR}/../.benchmark"
META_DIR="${BENCH_DIR}/meta"
FLAT_FILE="${BENCH_DIR}/rolling_summary.md"

# ─── Test project definition ──────────────────────────────────────────
# 10 modules simulating a realistic e-commerce app with cross-dependencies
setup() {
  echo "=== Synapse Benchmark Setup ==="
  rm -rf "$BENCH_DIR"
  mkdir -p "${BENCH_DIR}/meta/archive" "${BENCH_DIR}/scripts"

  # Copy generation script
  cp "${SCRIPT_DIR}/generate_memory_map.sh" "${BENCH_DIR}/scripts/" 2>/dev/null || true

  # ─── Create test nodes ──────────────────────────────────────────────
  # Each node: ~150-300 bytes of realistic content

  cat > "${META_DIR}/mod_auth-api.md" << 'EOF'
---
id: mod_auth-api
type: module
status: stable
updated: 2026-05-01
depends_on:
  - meta/mod_db-schema.md
tags: [auth, api, jwt]
---

# Auth API

## Current State
POST /api/v1/auth/login — accepts { email, password } → { access_token, refresh_token, expires_in: 900 }
POST /api/v1/auth/refresh — accepts { refresh_token } → { access_token, expires_in: 900 }
POST /api/v1/auth/logout — invalidates refresh_token server-side
JWT signed with RS256, public key at /.well-known/jwks.json
Rate limit: 10 req/min per IP for /login, 60 req/min for /refresh

## Key Decisions
- 2026-04-15 RS256 over HS256 — enables microservice verification without shared secret
- 2026-04-20 Refresh token rotation — each refresh invalidates previous token

## Cross-Module Connection Points

### To mod_db-schema
- **Table**: users (id UUID PK, email VARCHAR UNIQUE, password_hash VARCHAR, created_at TIMESTAMP)
- **Table**: refresh_tokens (id UUID PK, user_id FK→users, token_hash VARCHAR, expires_at TIMESTAMP, revoked BOOL)
- **Expected**: read access to users for login verification, read/write to refresh_tokens

## Open Issues
None.

## Change Log
- 2026-05-01 Initial creation for benchmark
EOF

  cat > "${META_DIR}/mod_db-schema.md" << 'EOF'
---
id: mod_db-schema
type: module
status: stable
updated: 2026-05-01
depends_on: []
tags: [database, schema, postgresql]
---

# Database Schema

## Current State
PostgreSQL 15. Primary database at db.internal:5432/production.
Connection pool: min 10, max 50 connections via pgBouncer.
Migrations managed by Flyway, versioned in db/migrations/.

## Key Decisions
- 2026-04-10 UUID PKs over auto-increment — avoids collision in multi-region
- 2026-04-12 JSONB for product metadata — flexible schema without migration

## Cross-Module Connection Points
None — infrastructure module, consumed by other modules.

## Open Issues
None.

## Change Log
- 2026-05-01 Initial creation for benchmark
EOF

  cat > "${META_DIR}/mod_payment.md" << 'EOF'
---
id: mod_payment
type: module
status: in-progress
updated: 2026-05-01
depends_on:
  - meta/mod_auth-api.md
  - meta/mod_db-schema.md
tags: [payment, stripe, billing]
---

# Payment Module

## Current State
Stripe integration via stripe-js v14. Webhook endpoint: POST /api/v1/payment/webhook.
Supported methods: card, alipay, wechat_pay.
Order creation: POST /api/v1/payment/orders — { items[], currency } → { order_id, client_secret }
Idempotency key: X-Idempotency-Key header required for order creation.

## Key Decisions
- 2026-04-25 Stripe over direct PSP — faster multi-method rollout

## Cross-Module Connection Points

### To mod_auth-api
- **Endpoint**: GET /api/v1/auth/session — validates user session before payment
- **Expected**: 200 { user_id, email } for valid token, 401 otherwise

### To mod_db-schema
- **Table**: orders (id UUID PK, user_id FK→users, stripe_pi VARCHAR, status ENUM, total INTEGER, currency VARCHAR)
- **Table**: order_items (id UUID PK, order_id FK→orders, product_id FK→products, quantity INT, unit_price INT)
- **Expected**: read/write access

## Open Issues
- [PENDING] Webhook signature verification timeout under load — investigating

## Change Log
- 2026-05-01 Initial creation for benchmark
EOF

  cat > "${META_DIR}/feat_checkout.md" << 'EOF'
---
id: feat_checkout
type: feature
status: in-progress
updated: 2026-05-01
depends_on:
  - meta/mod_payment.md
  - meta/mod_auth-api.md
  - meta/feat_cart.md
tags: [checkout, payment, cart]
---

# Checkout Flow

## Current State
3-step checkout: Cart review → Shipping → Payment.
URL: /checkout, /checkout/shipping, /checkout/payment.
Requires authenticated session (redirect to /login if no token).
Guest checkout: not yet supported.

## Key Decisions
- 2026-04-28 3-step over single-page — reduced cart abandonment in A/B test (12% improvement)

## Cross-Module Connection Points

### To mod_payment
- **Endpoint**: POST /api/v1/payment/orders — creates Stripe payment intent
- **Expected**: Returns order_id + client_secret for Stripe Elements mount

### To mod_auth-api
- **Endpoint**: GET /api/v1/auth/session — validates user before checkout
- **Expected**: 200 with user_id for address prefill

### To feat_cart
- Shared state via Zustand store: cart.items, cart.total
- Expected: cart is non-empty before entering checkout flow

## Open Issues
- Guest checkout blocked by auth requirement — needs product decision

## Change Log
- 2026-05-01 Initial creation for benchmark
EOF

  cat > "${META_DIR}/feat_cart.md" << 'EOF'
---
id: feat_cart
type: feature
status: stable
updated: 2026-05-01
depends_on:
  - meta/mod_db-schema.md
tags: [cart, ui, state]
---

# Shopping Cart

## Current State
Client-side cart via Zustand persist middleware. Synced to server on user login.
Endpoint: GET/PUT /api/v1/cart — { items: [{ product_id, quantity }] }
Merge strategy on login: server cart ∪ local cart, server wins on conflict.
Max 50 unique items per cart.

## Key Decisions
- 2026-04-20 Zustand over Redux — smaller bundle, sufficient for cart complexity

## Cross-Module Connection Points

### To mod_db-schema
- **Table**: carts (user_id FK→users UNIQUE, items JSONB, updated_at TIMESTAMP)
- **Expected**: read/write access

## Open Issues
None.

## Change Log
- 2026-05-01 Initial creation for benchmark
EOF

  cat > "${META_DIR}/mod_frontend-routing.md" << 'EOF'
---
id: mod_frontend-routing
type: module
status: stable
updated: 2026-05-01
depends_on: []
tags: [frontend, routing, react]
---

# Frontend Routing

## Current State
React Router v6. Route tree:
/ → Home
/login → LoginPage
/signup → SignupPage
/products → ProductList
/products/:id → ProductDetail
/cart → CartPage
/checkout/* → CheckoutFlow (protected)
/account/* → AccountSettings (protected)
/admin/* → AdminPanel (protected, role=admin)
Protected routes wrapped in <RequireAuth> — redirects to /login?redirect=<original>

## Key Decisions
- 2026-04-10 React Router v6 over v5 — nested routes for checkout flow

## Cross-Module Connection Points
None — consumed by feature pages.

## Open Issues
None.

## Change Log
- 2026-05-01 Initial creation for benchmark
EOF

  cat > "${META_DIR}/mod_ui-components.md" << 'EOF'
---
id: mod_ui-components
type: module
status: stable
updated: 2026-05-01
depends_on: []
tags: [ui, components, design-system]
---

# UI Component Library

## Current State
Design system: "ShopUI" v2.1. Built on Tailwind CSS 3.4 + Radix UI primitives.
Key components: Button, Input, Select, Modal, Toast, Card, Badge, Table, Pagination.
Naming: PascalCase for components, useComponentName.tsx file convention.
All components accept className prop for Tailwind override.
Accessibility: WCAG 2.1 AA minimum, tested with axe-core in CI.

## Key Decisions
- 2026-04-05 Radix UI over Headless UI — better tree-shaking, more primitives
- 2026-04-08 All colors in Tailwind config tokens only — no hardcoded hex values

## Cross-Module Connection Points
None — consumed by all feature pages.

## Open Issues
None.

## Change Log
- 2026-05-01 Initial creation for benchmark
EOF

  cat > "${META_DIR}/feat_product-search.md" << 'EOF'
---
id: feat_product-search
type: feature
status: in-progress
updated: 2026-05-01
depends_on:
  - meta/mod_db-schema.md
  - meta/mod_ui-components.md
tags: [search, product, ui]
---

# Product Search

## Current State
Search endpoint: GET /api/v1/products/search?q={query}&page={n}&size={20}
Full-text search via PostgreSQL tsvector on products.name + products.description.
Facets: category, price_range, rating, in_stock.
Sort options: relevance, price_asc, price_desc, rating, newest.
Debounce input 300ms before API call.

## Key Decisions
- 2026-04-22 PostgreSQL FTS over Elasticsearch — sufficient for <100k products, avoids infra complexity

## Cross-Module Connection Points

### To mod_db-schema
- **Table**: products (id UUID PK, name VARCHAR, description TEXT, search_vector TSVECTOR, category_id FK, price INTEGER, stock INT, rating DECIMAL)
- **Expected**: read access, GIN index on search_vector

### To mod_ui-components
- Uses: Input (search bar), Card (product card), Badge (in-stock status), Pagination
- Expected: components render without layout shift during search

## Open Issues
- Search latency >500ms for broad queries — investigating GIN index optimization

## Change Log
- 2026-05-01 Initial creation for benchmark
EOF

  cat > "${META_DIR}/feat_user-profile.md" << 'EOF'
---
id: feat_user-profile
type: feature
status: stable
updated: 2026-05-01
depends_on:
  - meta/mod_auth-api.md
  - meta/mod_db-schema.md
  - meta/mod_ui-components.md
tags: [user, profile, account]
---

# User Profile

## Current State
Profile page: /account/profile
Fields: display_name, avatar_url, phone, default_shipping_address (JSON)
Avatar upload: POST /api/v1/users/me/avatar — multipart, max 2MB, auto-resize to 256x256
Password change: PUT /api/v1/users/me/password — requires current_password + new_password
Email change: PUT /api/v1/users/me/email — sends verification link to new email

## Key Decisions
- 2026-04-18 Avatar to S3 signed URL over base64 — saves DB space, faster page load

## Cross-Module Connection Points

### To mod_auth-api
- **Endpoint**: GET /api/v1/auth/session — validates current session
- **Expected**: 200 { user_id, email } for profile data fetch

### To mod_db-schema
- **Table**: user_profiles (user_id FK→users UNIQUE, display_name VARCHAR, avatar_key VARCHAR, phone VARCHAR, default_address JSONB)
- **Expected**: read/write access

### To mod_ui-components
- Uses: Input, Button, Modal (avatar crop), Toast (success/error feedback)
- Expected: form validation consistent with other forms in the app

## Open Issues
None.

## Change Log
- 2026-05-01 Initial creation for benchmark
EOF

  cat > "${META_DIR}/mod_api-gateway.md" << 'EOF'
---
id: mod_api-gateway
type: module
status: stable
updated: 2026-05-01
depends_on: []
tags: [api, gateway, middleware]
---

# API Gateway

## Current State
Express.js 4.18 behind Nginx reverse proxy.
Middleware stack (in order): cors, helmet, rate-limit, request-id, auth (JWT verification), validator (Zod schemas), handler.
Error format: { error: { code: NUMBER, message: STRING, request_id: STRING } }
All responses include X-Request-Id header for tracing.
Logging: structured JSON to stdout, consumed by Datadog.

## Key Decisions
- 2026-04-10 Zod over Joi — TypeScript-first, smaller bundle, composable schemas
- 2026-04-12 Request ID per request — enables distributed tracing across services

## Cross-Module Connection Points
None — consumed by all API modules.

## Open Issues
None.

## Change Log
- 2026-05-01 Initial creation for benchmark
EOF

  # ─── Generate MEMORY_MAP for benchmark project ──────────────────────
  if [ -f "${BENCH_DIR}/scripts/generate_memory_map.sh" ]; then
    cd "$BENCH_DIR" && bash scripts/generate_memory_map.sh 2>/dev/null || true
  fi

  # ─── Create flat-file equivalent ────────────────────────────────────
  echo "# Rolling Summary — Flat-File Equivalent" > "$FLAT_FILE"
  echo "" >> "$FLAT_FILE"
  echo "This file contains ALL information from ALL 10 modules above," >> "$FLAT_FILE"
  echo "simulating a RecallLoom-style rolling_summary.md." >> "$FLAT_FILE"
  echo "" >> "$FLAT_FILE"
  for f in "${META_DIR}"/*.md; do
    [ "$(basename "$f")" = "MEMORY_MAP.md" ] && continue
    echo "---" >> "$FLAT_FILE"
    cat "$f" >> "$FLAT_FILE"
    echo "" >> "$FLAT_FILE"
  done

  flat_size=$(wc -c < "$FLAT_FILE")
  node_count=$(find "$META_DIR" -maxdepth 1 -name '*.md' ! -name 'MEMORY_MAP.md' | wc -l | xargs)
  total_node_bytes=$(cat "$META_DIR"/*.md 2>/dev/null | wc -c)

  echo ""
  echo "Test project created:"
  echo "  Nodes: $node_count (total $(( total_node_bytes / 1024 )) KB)"
  echo "  Flat file: $(( flat_size / 1024 )) KB"
  echo "  Location: $BENCH_DIR"
}

# ─── Run benchmark ─────────────────────────────────────────────────────
run() {
  if [ ! -d "$BENCH_DIR" ]; then
    echo "Run 'bash scripts/benchmark.sh setup' first."
    exit 1
  fi

  echo "=== Synapse Retrieval Simulation ==="
  echo ""

  flat_size=$(wc -c < "$FLAT_FILE")
  flat_tokens=$(( flat_size / 4 ))  # rough estimate: ~4 chars per token

  # ─── Define test tasks and their expected node hits ──────────────────
  # Format: "Task Description|Primary Node|Expected Deps (comma-sep)|Depth-2 Nodes (comma-sep, tag-filtered)"

  declare -a TASKS=(
    "Fix button color on checkout page|meta/feat_checkout.md|meta/mod_payment.md,meta/mod_auth-api.md,meta/feat_cart.md|"
    "Add new field to user profile|meta/feat_user-profile.md|meta/mod_auth-api.md,meta/mod_db-schema.md,meta/mod_ui-components.md|"
    "Optimize product search query|meta/feat_product-search.md|meta/mod_db-schema.md,meta/mod_ui-components.md|"
    "Update JWT expiry time|meta/mod_auth-api.md|meta/mod_db-schema.md|"
    "Add new payment method|meta/mod_payment.md|meta/mod_auth-api.md,meta/mod_db-schema.md|meta/feat_checkout.md"
    "Add cart persistence across devices|meta/feat_cart.md|meta/mod_db-schema.md|meta/feat_checkout.md"
    "Login page 401 debugging (multi-domain)|meta/mod_auth-api.md,meta/feat_user-profile.md|meta/mod_db-schema.md,meta/mod_api-gateway.md,meta/mod_ui-components.md|"
    "COLD: login→checkout flow broken|meta/feat_checkout.md|meta/mod_auth-api.md,meta/mod_payment.md,meta/feat_cart.md|"
  )

  total_synapse_bytes=0
  total_synapse_files=0
  total_smart_flat_bytes=0
  task_count=${#TASKS[@]}

  for task_def in "${TASKS[@]}"; do
    IFS='|' read -r desc primary deps depth2 <<< "$task_def"

    # Calculate Synapse load
    node_bytes=0
    node_files=0
    relevant_bytes=0  # for smart flat: bytes of relevant nodes

    # Primary node(s)
    IFS=',' read -ra PRIMARY_ARR <<< "$primary"
    for p in "${PRIMARY_ARR[@]}"; do
      p=$(echo "$p" | xargs)
      if [ -f "${BENCH_DIR}/${p}" ]; then
        local pbytes
        pbytes=$(wc -c < "${BENCH_DIR}/${p}")
        node_bytes=$((node_bytes + pbytes))
        relevant_bytes=$((relevant_bytes + pbytes))
        node_files=$((node_files + 1))
      fi
    done

    # Depth-1 deps
    IFS=',' read -ra DEP_ARR <<< "$deps"
    for d in "${DEP_ARR[@]}"; do
      d=$(echo "$d" | xargs)
      [ -z "$d" ] && continue
      if [ -f "${BENCH_DIR}/${d}" ]; then
        local dbytes
        dbytes=$(wc -c < "${BENCH_DIR}/${d}")
        node_bytes=$((node_bytes + dbytes))
        relevant_bytes=$((relevant_bytes + dbytes))
        node_files=$((node_files + 1))
        # In modify tasks, only load Connection Points (~30% of file)
        case "$desc" in
          *"Update"*|*"Add"*|*"Optimize"*)
            node_bytes=$((node_bytes - dbytes * 70 / 100))
            ;;
        esac
      fi
    done

    # Depth-2 (tag-filtered, only if applicable)
    IFS=',' read -ra D2_ARR <<< "$depth2"
    for d2 in "${D2_ARR[@]}"; do
      d2=$(echo "$d2" | xargs)
      [ -z "$d2" ] && continue
      if [ -f "${BENCH_DIR}/${d2}" ]; then
        local d2bytes
        d2bytes=$(wc -c < "${BENCH_DIR}/${d2}")
        node_bytes=$((node_bytes + d2bytes))
        relevant_bytes=$((relevant_bytes + d2bytes))
        node_files=$((node_files + 1))
        # Depth-2: only load Connection Points (~25% of file)
        node_bytes=$((node_bytes - d2bytes * 75 / 100))
      fi
    done

    # MAP lookup overhead (estimate ~200 bytes per task)
    node_bytes=$((node_bytes + 200))

    syn_tokens=$(( node_bytes / 4 ))
    total_synapse_bytes=$((total_synapse_bytes + node_bytes))
    total_synapse_files=$((total_synapse_files + node_files))

    # Smart flat simulation: Agent searches flat file, reads relevant sections
    # Relevant content + 30% structural overhead (no clear boundaries) + 200 tok overview
    smart_flat_overhead=30
    smart_flat_bytes=$(( relevant_bytes + relevant_bytes * smart_flat_overhead / 100 + 200 * 4 ))
    [ "$smart_flat_bytes" -gt "$flat_size" ] && smart_flat_bytes=$flat_size
    total_smart_flat_bytes=$((total_smart_flat_bytes + smart_flat_bytes))

    savings=$(( (flat_size - node_bytes) * 100 / flat_size ))
    smart_savings=$(( (smart_flat_bytes - node_bytes) * 100 / smart_flat_bytes ))
    printf "%-48s | %2d f | %5d tok | %3d%% ↓ flat | %3d%% ↓ smart\n" \
      "${desc:0:48}" "$node_files" "$syn_tokens" "$savings" "$smart_savings"
  done

  avg_bytes=$((total_synapse_bytes / task_count))
  avg_files=$((total_synapse_files / task_count))
  avg_tokens=$(( avg_bytes / 4 ))
  avg_savings=$(( (flat_size - avg_bytes) * 100 / flat_size ))

  avg_smart_bytes=$((total_smart_flat_bytes / task_count))
  avg_smart_tokens=$(( avg_smart_bytes / 4 ))
  avg_smart_vs_flat=$(( (flat_size - avg_smart_bytes) * 100 / flat_size ))
  avg_smart_vs_syn=$(( (avg_smart_bytes - avg_bytes) * 100 / avg_smart_bytes ))

  echo ""
  echo "────────────────────────────────────────────────────────────────────"
  echo "AVERAGE: $avg_files files | $avg_tokens tokens"
  echo "  vs flat (dumb):   ${avg_savings}% reduction  — flat loads everything"
  echo "  vs flat (smart):  ${avg_smart_vs_syn}% reduction — flat searches + reads relevant only"
  echo ""
  echo "Flat baseline (dumb):  $(( flat_size / 1024 )) KB (~$flat_tokens tokens) — loaded for EVERY task"
  echo "Flat baseline (smart): $(( avg_smart_bytes / 1024 )) KB (~$avg_smart_tokens tokens) — searches, reads relevant"
  echo "Synapse avg:           $(( avg_bytes / 1024 )) KB (~$avg_tokens tokens) — varies by task"
  echo ""
  echo "=== How to verify with real Agent ==="
  echo "1. Copy the benchmark project to a real working directory"
  echo "2. Run identical tasks against both setups:"
  echo "   - Flat setup: cp .benchmark/rolling_summary.md meta/ and use RecallLoom"
  echo "   - Synapse setup: use .benchmark/meta/ with synapse-graph-memory skill loaded"
  echo "3. Count Read tool calls to meta/*.md in each session"
  echo "4. Compare actual Read counts against this simulation's predictions"
}

# ─── Clean test artifacts ──────────────────────────────────────────────
clean() {
  rm -rf "$BENCH_DIR"
  echo "Benchmark artifacts removed."
}

# ─── Main ──────────────────────────────────────────────────────────────
case "${1:-}" in
  setup) setup ;;
  run) run ;;
  clean) clean ;;
  *)
    echo "Usage: bash scripts/benchmark.sh {setup|run|clean}"
    echo ""
    echo "  setup  — Create a 10-module test project + flat-file equivalent"
    echo "  run    — Simulate 8 tasks and report token savings"
    echo "  clean  — Remove test artifacts"
    ;;
esac
