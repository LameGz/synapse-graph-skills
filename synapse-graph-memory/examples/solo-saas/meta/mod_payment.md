---
id: mod_payment
type: module
status: stable
updated: 2026-05-12
summary: Payment module receives callbacks and updates subscription records.
depends_on: [meta/mod_user-account.md]
auto_linked: []
tags: [payment, subscription, billing]
aliases: [checkout, billing]
---

# Payment

## Current State
- `POST /api/v1/payment/callback` marks successful subscription payments.

## Key Decisions
- [2026-05-12] Payment callbacks update subscription status asynchronously.

## Cross-Module Connection Points
- **Endpoint**: POST /api/v1/payment/callback
- **Table**: Subscription
- **Writes**: `User.subscriptionStatus`

## Open Issues
None.

## Change Log
- [2026-05-12] **Context**: Billing flow.
  **Change**: Connected payment callback to subscription status update.
  **Impact**: Account and subscription features reflect paid plans.
  **Affected**: mod_user-account, feat_subscription
