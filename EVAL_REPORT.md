# Synapse Graph Skills — Eval Report

**Date**: 2026-05-21  
**Model**: deepseek-v4-pro  
**Test Fixture**: Synapse-Solo/examples/solo-saas (8 nodes)

---

## Skills Covered

| Skill | Files | .skill Size |
|---|---|---|
| synapse-graph-memory (core) | 24 | 66 KB |
| synapse-timeline | 4 | 5.5 KB |
| synapse-daily-note | 9 | 26 KB |
| synapse-init | 16 | 43 KB |

---

## Eval 1: Status Query

**Prompt**: "登录功能做得怎么样了？"

| Metric | With Skill | Without Skill | Delta |
|--------|-----------|---------------|-------|
| Tokens | 34,014 | 34,605 | -1.7% |
| Duration | 140s | 156s | -10.3% |
| Files Read | 6 | 12 | **-50%** |
| Irrelevant Files | 0 | 5 | key win |
| Assertions | 4/4 | 3/4 | |

With-skill path: SKILL.md → MEMORY_MAP.md → feat_login → BFS(depth 1): mod_auth-api + mod_design-system
Without-skill path: MEMORY_MAP.* → ALL 8 meta/*.md → README → 2 cache files

---

## Eval 3: Cross-Module Impact

**Prompt**: "改 mod_user-account 会影响哪些功能？"

| Metric | With Skill | Without Skill | Delta |
|--------|-----------|---------------|-------|
| Tokens | 38,625 | 37,620 | +2.7% |
| Duration | 240s | 211s | +13.7% |
| Files Read | 10 | 14 | **-28.6%** |
| Irrelevant Files | 0 | 4 | key win |
| Assertions | 4/4 | 3/4 | |

Both correctly identified: feat_subscription, feat_admin-notification (direct), mod_payment, mod_notification (indirect), feat_login/mod_auth-api/mod_design-system (unaffected).

With-skill bonus: per-field risk assessment (rename vs add vs delete for each of active_plan_id, plan_expires_at, subscription_status).

---

## Aggregate

| | With Skill | Without Skill |
|---|---|---|
| Mean Files | **8.0** | 13.0 |
| Mean Irrelevant | **0.0** | 4.5 |
| Pass Rate | **100%** | 62.5% |

**Key**: File reading discipline, not token savings. Without-skill loads cache files, both MAP formats, and all nodes "just to be safe".

---

Detailed run data: `synapse-graph-memory-workspace/iteration-1/`