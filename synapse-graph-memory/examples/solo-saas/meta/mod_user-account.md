---
id: mod_user-account
type: module
status: stable
updated: 2026-05-12
summary: User account module owns subscription status and account profile fields.
depends_on: []
auto_linked: []
tags: [user, account, subscription, payment]
aliases: [member, plan]
---

# User Account

## Current State
- User records include `subscriptionStatus` for plan gating.
- Subscription state is read by billing and admin notification flows.

## Key Decisions
- [2026-05-12] Store subscription status on the user record for fast reads.

## Cross-Module Connection Points
- **Table**: User
- **Field**: `subscriptionStatus`

## Open Issues
None.

## Change Log
- [2026-05-12] **Context**: Subscription rollout.
  **Change**: Added `subscriptionStatus` as the canonical account field.
  **Impact**: Subscription and admin notification features depend on this field.
  **Affected**: feat_subscription, feat_admin-notification
