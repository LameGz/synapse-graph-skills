---
id: feat_login
type: feature
status: in-progress
updated: 2026-05-11
summary: Login feature connects the UI form to auth API tokens.
depends_on:
  - meta/mod_auth-api.md
auto_linked: []
tags:
  - auth
  - login
  - frontend
aliases:
  - signin
---

# Login

## Current State
- Login form posts credentials to `POST /api/v1/auth/login`.
- Session persistence is wired through refresh token renewal.

## Key Decisions
- [2026-05-11] Keep the login page thin and let the auth API own token rotation.

## Cross-Module Connection Points
- **Endpoint**: POST /api/v1/auth/login
- **Endpoint**: POST /api/v1/auth/refresh
- **Consumes**: `access_token`, `refresh_token`

## Open Issues
- Add frontend password strength validation.

## Change Log
- [2026-05-11] **Context**: Natural-language memory ingestion.
  **Change**: Connected login page to `POST /api/v1/auth/login`.
  **Impact**: Users can authenticate from the UI.
  **Affected**: mod_auth-api
