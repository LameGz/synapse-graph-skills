---
id: feat_admin-notification
type: feature
status: in-progress
updated: 2026-05-12
summary: Admin notifications alert operators when subscription state changes.
depends_on: [meta/mod_user-account.md]
auto_linked: []
tags: [admin, notification, subscription]
aliases: [alerts]
---

# Admin Notification

## Current State
- Admin notification flow listens for subscription status changes.

## Key Decisions
- [2026-05-12] Emit admin notifications after account state changes are committed.

## Cross-Module Connection Points
- **Reads**: `User.subscriptionStatus`
- **Event**: `subscription.changed`

## Open Issues
None.

## Change Log
- [2026-05-12] **Context**: Admin visibility.
  **Change**: Added admin notification memory for subscription changes.
  **Impact**: Operators can track paid plan activations.
  **Affected**: mod_user-account
