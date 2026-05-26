---
id: feat_subscription
type: feature
status: in-progress
updated: 2026-05-12
summary: Subscription feature displays paid plan state from user account and payment modules.
depends_on: [meta/mod_user-account.md, meta/mod_payment.md]
auto_linked: []
tags: [subscription, payment, billing]
aliases: [member, plan]
---

# Subscription

## Current State
- Subscription page reads `User.subscriptionStatus`.
- Successful payment callbacks unlock paid plan access.

## Key Decisions
- [2026-05-12] Use account status as the UI source of truth.

## Cross-Module Connection Points
- **Reads**: `User.subscriptionStatus`
- **Endpoint**: POST /api/v1/payment/callback

## Open Issues
- Add downgrade flow for canceled plans.

## Change Log
- [2026-05-12] **Context**: Subscription payment integration.
  **Change**: Wired payment callback result into subscription state.
  **Impact**: Paid plan activation is visible in account UI.
  **Affected**: mod_payment, mod_user-account
