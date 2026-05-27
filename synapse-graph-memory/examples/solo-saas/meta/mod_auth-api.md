---
id: mod_auth-api
type: module
status: stable
updated: 2026-05-11
summary: Auth API exposes login and refresh endpoints for session management.
depends_on: []
auto_linked: []
tags: [auth, login, jwt, refresh]
aliases: [authentication, signin]
---

# Auth API

## Current State
- `POST /api/v1/auth/login` returns access and refresh tokens.
- `POST /api/v1/auth/refresh` rotates the refresh token.

## Key Decisions
- [2026-05-10] Keep refresh tokens server-validated for revocation support.

## Cross-Module Connection Points
- **Endpoint**: POST /api/v1/auth/login
- **Endpoint**: POST /api/v1/auth/refresh
- **Response**: `{ access_token: string, refresh_token: string }`

## Open Issues
None.

## Change Log
- [2026-05-11] **Context**: Login integration.
  **Change**: Added refresh endpoint documentation for session renewal.
  **Impact**: Login and account flows can renew sessions.
  **Affected**: feat_login
