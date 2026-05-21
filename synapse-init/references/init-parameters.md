# Init Parameters

## Stack Detection Heuristics

| Check | Files Searched | Detected Stack |
|---|---|---|
| Node.js | `package.json` | Checks deps: next → Next.js, react → React, vue → Vue, express → Express.js |
| Python | `pyproject.toml`, `requirements.txt` | fastapi → FastAPI, django → Django, flask → Flask |
| Go | `go.mod` | Uses module path as framework name |
| Rust | `Cargo.toml` | Rust |
| Java | `pom.xml`, `build.gradle` | Maven / Gradle |

First matching ecosystem file wins. If none match → `"unknown"`.

## Database Detection

| Check | File | Detected |
|---|---|---|
| Prisma | `prisma/schema.prisma` | PostgreSQL |
| Config grep | `*.toml`, `*.yaml`, `*.env` | postgres / mongodb / mysql keyword match |

## Module Inference — Directory to Module Mapping

| Directory | Module Name | Tags |
|---|---|---|
| `src/api/` | `mod_api` | `[api, backend, endpoints]` |
| `src/components/` | `mod_ui-components` | `[ui, components, frontend]` |
| `src/pages/` | `mod_frontend-routing` | `[frontend, routing, pages]` |
| `prisma/` | `mod_database` | `[database, prisma, schema]` |
| `src/auth/` | `mod_auth` | `[auth, security, login]` |
| `src/payment/` | `mod_payment` | `[payment, billing, stripe]` |
| `src/utils/` | `mod_utils` | `[utils, helpers, common]` |
| `src/services/` | `mod_services` | `[services, business-logic]` |
| `src/models/` | `mod_data-models` | `[models, data, schema]` |
| `src/middleware/` | `mod_middleware` | `[middleware, interceptors]` |

If no directory matches → single `mod_project` with fallback tags.

## Customizing Module Boundaries

To override auto-detection, pre-create the `meta/` directory with your desired module nodes before running init. The script skips existing nodes. Example:

```bash
mkdir -p meta
cp template.md meta/mod_custom-billing.md
# Edit mod_custom-billing.md with your tags and summary
bash scripts/init.sh  # Will skip the pre-existing node
```

## Hook Registration

Three merge strategies for `.claude/settings.json`:
1. **No existing settings** → copy `settings.template.json` directly
2. **Existing settings with no hooks** → merge hook entries via Python `json` module
3. **Existing settings with hooks** → skip if all 4 hook commands already registered

Requires `python3` for merge strategy 2. Without Python, user gets a manual merge instruction.
