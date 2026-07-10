# Synapse v2 Dual-Host Foundation Design

> Date: 2026-07-10
>
> Status: Approved in design review
>
> Scope: First implementation slice for a shared Codex and Claude Code foundation

## 1. Summary

Synapse v2 will invert the v1.5 write path: the host LLM owns semantic judgment and emits a structured Proposal, while a deterministic Python core owns validation, routing, mutation, indexing, recovery, and audit. The same plugin tree will support Codex and Claude Code through two manifests and thin host-specific hook configurations.

The first implementation slice will deliver a working vertical path:

```text
LLM Proposal -> validate -> policy -> transactional apply or Inbox -> MAP rebuild -> receipt
```

It will also repair the repository's current CI gates, preserve v1.5 data and entry points, and establish the automatic recording lifecycle shared by both hosts.

## 2. Context and Current-State Findings

The repository is a v1.5 skill suite with four separately distributed skills and substantial source duplication. The tracked Python and shell sources contain approximately 20,518 lines, while content-hash deduplication leaves approximately 9,407 unique lines.

Python migration has already begun: `generate_memory_map.sh` delegates normal MAP builds to `generate_memory_map.py`. V2 should consolidate this work instead of rewriting a second independent engine.

The review found several concrete reliability gaps:

- GitHub workflows watch a nonexistent `skills/**` tree while the actual skills live at repository root.
- Workflow branch filters use `main`, while the repository currently uses `master`.
- Some lint steps are deliberately non-blocking through `continueOnError` or `|| true`.
- The current eval runner validates fixture shape but does not execute real Agent evaluations.
- Eval fixtures contain author-machine absolute paths.
- A SQLite-backed trace fails because the connection is closed before traversal uses it.
- Some tests invoke `python` directly and fail in environments that expose only `python3`.
- Corrupt Inbox JSON is silently treated as an empty Inbox, creating a data-loss path.

The working tree already contains unrelated user changes. All implementation work must preserve them and stage only files belonging to this effort.

## 3. Goals

1. Provide one deterministic, pure-stdlib Python runtime for Codex and Claude Code.
2. Make Proposal JSON the only semantic write interface used by Agents.
3. Make the Python core the only component allowed to mutate `meta/*.md`, Inbox, MAP, and audit state.
4. Automatically request a Proposal after durable code changes, with at most one continuation per turn.
5. Preserve v1.5 `meta/*.md`, frontmatter, MAP, and Inbox assets.
6. Make every deterministic claim reproducible in Windows, Ubuntu, and macOS CI.
7. Keep live LLM evaluations separate from offline correctness tests and report their provenance honestly.

## 4. Non-Goals for the First Slice

The following work remains outside this slice:

- Memory garbage collection, archival, staleness scoring, and semantic contradiction classification.
- Migration of every legacy CLI command into the new package.
- Interactive graph visualization.
- AST or codegraph bridge work.
- Cross-project global indexes or team collaboration.
- Removal of the four v1.5 skill directories.
- Declaring the 90% proposal-accuracy or 5% wrong-node targets achieved before a statistically meaningful live eval exists.

## 5. Design Principles

- The LLM performs semantic interpretation; scripts do not infer meaning from keyword lists.
- Scripts validate deterministic facts, preconditions, references, and exact values.
- Markdown nodes remain the human-readable source of truth.
- MAP files and SQLite are derived indexes and are always rebuildable.
- Host adapters normalize lifecycle events but contain no memory policy.
- Ambiguous or unprovable changes go to Inbox instead of being guessed.
- Runtime dependencies remain Python standard library only; test and lint tools may be development dependencies.

## 6. Architecture

```text
Codex ------> .codex-plugin/plugin.json -----> hooks/codex.json ---+
                                                                   |
Claude Code -> .claude-plugin/plugin.json ----> hooks/claude.json --+-> host adapter
                                                                   |
Shared synapse-memory Skill ---------------------------------------+
                                                                   v
                                      Proposal JSON -> deterministic core
                                                      | validate
                                                      | policy
                                                      | render
                                                      | transaction
                                                      | map
                                                      | inbox/audit
                                                      v
                                        meta/*.md + MEMORY_MAP.* + .synapse/
```

### 6.1 Proposed Repository Layout

```text
synapse-graph-skills/
├── synapse/
│   ├── .codex-plugin/plugin.json
│   ├── .claude-plugin/plugin.json
│   ├── skills/
│   │   ├── synapse-memory/SKILL.md
│   │   └── synapse-init/SKILL.md
│   ├── hooks/
│   │   ├── codex.json
│   │   ├── claude.json
│   │   ├── launch.mjs
│   │   ├── launch.sh
│   │   ├── launch.ps1
│   │   └── runner.py
│   ├── core/synapse/
│   │   ├── __init__.py
│   │   ├── __main__.py
│   │   ├── cli.py
│   │   ├── proposal.py
│   │   ├── policy.py
│   │   ├── renderer.py
│   │   ├── transaction.py
│   │   ├── map_builder.py
│   │   ├── inbox.py
│   │   ├── audit.py
│   │   └── host.py
│   └── schemas/proposal.schema.json
├── .agents/plugins/marketplace.json
├── .claude-plugin/marketplace.json
└── tests/v2/
```

The nested `synapse/` directory is the distributable plugin root. Marketplace catalogs live at the repository paths expected by their respective hosts and point to that plugin root.

### 6.2 Responsibility Boundaries

| Component | Responsibility | Forbidden responsibility |
| --- | --- | --- |
| `synapse-memory` Skill | Retrieval protocol, semantic target selection, Proposal authoring | Direct edits to memory nodes |
| Host manifests and hook JSON | Platform registration and command invocation | Memory policy or Markdown parsing |
| `hooks/runner.py` | Normalize host input and format host output | Semantic inference |
| Proposal validator | Structural and deterministic domain validation | Guessing intent |
| Policy engine | Confidence routing and objective downgrades | Rewriting Proposal meaning |
| Renderer | Pure in-memory node transformation | Filesystem mutation |
| Transaction manager | Lock, stage, commit, rollback, recovery | Semantic decisions |
| MAP builder | Produce derived indexes from future node state | Mutate source nodes |

Claude Code invokes hooks through the small dependency-free Node launcher because its documented exec form is portable across supported operating systems. The launcher discovers `python3`, `python`, or `py -3` and delegates to `runner.py`. Codex uses `launch.sh` on macOS/Linux and its `commandWindows` override to call `launch.ps1` on Windows; both launchers perform the same interpreter discovery. These launchers contain no Synapse policy.

## 7. Proposal Protocol

### 7.1 Envelope

```json
{
  "schema_version": "2.0",
  "proposal_id": "codex-session-turn",
  "source": {
    "host": "codex",
    "session_id": "session-id",
    "turn_id": "turn-id",
    "git_head": "commit-sha"
  },
  "memory_revision": "sha256-of-current-memory",
  "operations": [
    {
      "id": "op-001",
      "action": "append_changelog",
      "target": "api_auth-routes",
      "payload": {
        "text": "Connected POST /api/v1/auth/login and return JWT.",
        "exact_values": ["POST /api/v1/auth/login"],
        "refs": [
          {"path": "src/auth/routes.ts", "line": 45}
        ]
      },
      "evidence": {
        "changed_files": ["src/auth/routes.ts"],
        "quotes": ["router.post('/api/v1/auth/login')"]
      },
      "confidence": 0.93,
      "rationale": "The changed route belongs to the authentication API node.",
      "review_flags": []
    }
  ]
}
```

### 7.2 Envelope Rules

- `schema_version` is exactly `2.0` for this protocol.
- `proposal_id` is stable across retries and uniquely identifies the receipt.
- `proposal_id` and `memory_revision` are issued by `synapse proposal context`; the Agent copies rather than invents them.
- `source.host` is `codex`, `claude`, or `manual`.
- `source.turn_id` is optional because not every host exposes a stable turn identifier. The host adapter maintains a normalized pending-turn key when it is absent.
- `confidence` is a number from `0.0` through `1.0`.
- `target` is a node ID, never a filesystem path.
- `payload.exact_values` is always present and may be empty only when the operation contains no literal engineering value.
- Every non-empty exact value must appear verbatim in `payload.text` and in the rendered memory entry. Evidence is validated independently because source syntax may represent the same fact differently, such as `router.post(...)` versus `POST /path`.
- `rationale` and `evidence` are mandatory.
- Evidence contains at least one changed file or source quote.
- `review_flags` is an array drawn from `target_ambiguity`, `semantic_conflict`, `incomplete_evidence`, and `user_review_requested`; any non-empty value forces Inbox routing.
- Paths are project-relative and cannot traverse above the project root.
- Unknown fields, invalid node types, invalid line numbers, and oversized values fail validation.
- A Proposal can create a node and reference it later in the same transaction.

The public JSON Schema documents the wire contract and supports editor tooling. The Python core implements a strict, dependency-free domain validator because Python's standard library does not include a complete JSON Schema engine.

### 7.3 Supported Operations

| Action | Deterministic behavior |
| --- | --- |
| `append_changelog` | Append one dated change entry |
| `update_state` | Add state or replace an exact old value with an exact new value |
| `add_issue` | Add a non-duplicate Open Issue |
| `resolve_issue` | Resolve an exactly matched Open Issue |
| `record_decision` | Append a Key Decision |
| `create_node` | Create a node that satisfies the existing node contract |
| `add_edge` | Add a valid, non-self-referencing explicit edge |
| `update_connection_point` | Add or exactly replace a connection point |

Replacement and resolution operations must include exact preconditions. The core never uses fuzzy matching to decide which existing text to remove.

## 8. Routing Policy

Validation produces one of three routes:

| Condition | Route |
| --- | --- |
| Effective confidence at least `0.85` and every safety check passes | Apply automatically |
| Effective confidence from `0.60` through `0.849...` | Inbox |
| Effective confidence below `0.60` or structurally invalid | Reject and audit |

Objective policy overrides Agent confidence:

- `create_node` and `add_edge` always enter Inbox during the initial v2 release.
- A stale base revision or any declared review flag enters Inbox.
- Absent or empty evidence, missing exact-value propagation into the Proposal text or final rendering, or invalid protocol structure is rejected. `incomplete_evidence` means non-empty evidence exists but the Agent considers it insufficient for automatic application.
- An operation whose deterministic precondition does not match current memory enters Inbox with a conflict code.
- A normalized operation fingerprint prevents duplicate application.

The validator returns structured results containing `ok`, `code`, `message`, `operation_id`, `recoverable`, and `route`.

## 9. Dual-Host Automatic Recording

Both hosts use the lowest common lifecycle contract: `SessionStart` and turn-scoped `Stop`. `PostToolUse` is not required for correctness because the two hosts expose different edit inputs and shell or external edits can bypass it.

### 9.1 SessionStart

The hook:

1. Runs transaction recovery before reading memory.
2. Builds a project digest capped at approximately 300 tokens.
3. Captures the current Git HEAD.
4. Captures dirty and untracked paths plus their content hashes.
5. Captures the current `memory_revision`, defined as SHA-256 over sorted project-relative node paths and their raw bytes; derived MAP and SQLite files are excluded.
6. Injects the digest and Proposal-writing rule as additional developer context.

### 9.2 Stop State Machine

At the first Stop in a turn:

1. Compare the current repository with the rolling session baseline initially captured at SessionStart.
2. Detect uncommitted changes, new and removed files, commits made during the session, and further edits to files that were already dirty.
3. Ignore configured generated and Synapse-owned paths.
4. If there is no durable change and no explicit Proposal, finish normally.
5. If durable code changes exist and there is no receipt for this turn, return a single continuation request instructing the Agent to produce and submit a Proposal.

During the continuation, the Agent obtains bounded evidence through `synapse proposal context`, creates a Proposal, and submits it through the core. Submission validates, routes, applies or queues, rebuilds the MAP when needed, and writes a receipt.

At the second Stop, the hook sees `stop_hook_active` or the turn receipt and always exits normally. If the Agent failed to submit, the core records `missed_proposal`; it does not create another continuation loop.

Every successful, Inbox, rejected, or user-skipped receipt advances the session's repository baseline to the current non-Synapse files. This makes the baseline rolling across turns and prevents a later turn from rediscovering changes already accounted for. A `missed_proposal` does not advance the baseline, so the unrecorded change remains eligible for a later turn.

Pure discussion decisions are handled by the injected Skill rule during the normal turn. The deterministic hook does not reintroduce keyword-based natural-language inference.

### 9.3 Project Configuration

```json
{
  "auto_record": true,
  "auto_apply_threshold": 0.85,
  "require_proposal_on_code_change": true,
  "ignored_paths": ["dist/", "build/", ".synapse/", "meta/", "MEMORY_MAP.md", "MEMORY_MAP.json"],
  "max_diff_bytes": 32768
}
```

An environment override can disable automatic recording. An explicit record request always invokes the Proposal workflow unless the user has said not to record the current work.

## 10. Transaction Model

Filesystem replacement is atomic per file, not across a collection of files. Synapse therefore implements a journaled, recoverable multi-file transaction.

### 10.1 Commit Protocol

1. Acquire `.synapse/locks/write.lock` using exclusive creation and record process metadata.
2. Recheck `memory_revision` after acquiring the lock.
3. Apply every operation to an in-memory future graph.
4. Run node parsing, reference integrity, duplicate ID, dead edge, self-edge, and configured cycle checks against the future graph.
5. Render affected nodes, MAP files, and audit output to temporary files on the same filesystem as their destinations.
6. Save a transaction journal and original bytes under `.synapse/transactions/<proposal-id>/`.
7. Flush temporary content and commit destinations with `os.replace`.
8. Record the receipt and remove transaction state only after all destinations succeed.

If a commit step fails, the transaction manager restores every destination already replaced. If the process stops unexpectedly, the next CLI invocation, SessionStart, or `doctor --recover` completes the rollback before other work proceeds.

### 10.2 Deterministic Conflict Boundary

The core detects only conflicts it can prove:

- Exact replacement text no longer exists.
- An issue selected for resolution no longer exists exactly.
- A node or edge precondition is invalid.
- The memory revision changed.
- An exact value is absent from the Proposal text or final rendering.
- Multiple operations in the same Proposal make incompatible changes.

Potential semantic contradictions that cannot be proven deterministically are declared by the Agent through the `semantic_conflict` review flag and sent to Inbox.

### 10.3 Failure Policy

- Corrupt node frontmatter or Inbox JSON blocks writes and is never silently reset.
- MAP build failure rolls back source-node changes.
- Active locks are not force-removed.
- A stale lock is removed only after process-liveness checks or explicit recovery.
- Repeating a known `proposal_id` returns its existing receipt.
- Audit records contain summaries, hashes, routes, and error codes rather than full transcripts or complete sensitive diffs.

## 11. Testing Strategy

Runtime code uses only the Python standard library. Development dependencies may include `pytest`, coverage tooling, and `ruff`.

### 11.1 Offline Test Layers

| Layer | Coverage |
| --- | --- |
| Unit | Protocol parsing, domain rules, policy, rendering, dedupe, MAP building |
| Contract | Codex and Claude hook fixtures normalize to the same host event and outcome |
| Transaction | Lock contention, injected failure at every commit step, rollback, recovery, retry |
| Integration | End-to-end Proposal flow on a temporary copy of `solo-saas` |
| Golden | V1.5-compatible node and MAP representation |
| State machine | No-change exit, one continuation, receipt exit, missed-Proposal exit |
| Regression | SQLite trace lifetime and Python launcher discovery |

All tests use temporary fixture copies and never rewrite repository examples.

### 11.2 Live Agent Evals

- Pull requests run deterministic offline tests and recorded trace conformance tests.
- Nightly and manually dispatched jobs run both `claude -p` and `codex exec` against shared fixtures.
- Platform-specific runners normalize outputs into one trace format.
- Release candidates require a live dual-host report for the exact release commit.
- `EVAL_REPORT.md` records commit, Agent version, model, sample size, invocation, and summarized results.
- Accuracy and wrong-node targets are reported as goals until sample size and reproducibility justify using them as release gates.

## 12. CI Design

The rebuilt workflows contain four blocking stages:

1. `validate`: JSON, Proposal Schema, both manifests, internal documentation links, and absolute-path scans.
2. `lint`: `ruff` plus `shellcheck` for remaining compatibility shims, with no ignored failures.
3. `test`: Windows, Ubuntu, and macOS using Python 3.10 and Python 3.14.
4. `integration`: vertical slice, rollback and recovery, and legacy compatibility.

Workflow paths target `synapse/**`, `tests/**`, relevant docs, and workflow files. Branch filters match the repository's actual default branch. Python-launch tests cover `python3`, `python`, and Windows `py -3` discovery behavior.

## 13. Compatibility and Migration

- Existing `meta/*.md`, frontmatter, `MEMORY_MAP.md`, `MEMORY_MAP.json`, and `.synapse/inbox.json` remain valid inputs.
- The four v1.5 skill directories remain in the repository during the first slice.
- Legacy entry points gain compatibility tests and later become shims that delegate to the v2 core.
- Legacy direct-write commands display deprecation guidance before removal in a later release.
- The v2 plugin is developed alongside v1.5 until golden and migration tests demonstrate equivalent data behavior.
- User data is never migrated in place without a dry run and backup; the migration command itself is outside the first slice.

## 14. First-Slice Acceptance Criteria

The slice is complete only when all of the following are demonstrated:

1. The same Proposal fixture produces equivalent behavior through Codex and Claude host adapters.
2. `solo-saas` completes Proposal validation, policy routing, transactional application or Inbox routing, and MAP generation.
3. Windows, Ubuntu, and macOS deterministic CI jobs pass.
4. Injected failure at any transaction stage leaves every affected file identical to its pre-transaction bytes.
5. An interrupted transaction is recovered before subsequent writes.
6. A duplicate Proposal does not create duplicate memory.
7. A turn with code changes requests at most one continuation.
8. Corrupt Inbox state fails closed and preserves the corrupt bytes for diagnosis.
9. Existing v1.5 data and tested legacy entry points remain usable.
10. README performance or accuracy claims link to reproducible commands and a specific report commit, or are removed.

## 15. Risks and Mitigations

| Risk | Mitigation |
| --- | --- |
| Codex or Claude hook schema changes | Keep separate thin hook JSON and shared normalized host events |
| Agent skips Proposal generation | One Stop continuation for code changes plus a `missed_proposal` audit event |
| Agent overstates confidence | Objective policy downgrades and structural actions routed to Inbox |
| Multi-file crash leaves partial state | Same-filesystem staging, journal, backup, and startup recovery |
| Scope expands into a full rewrite | Preserve legacy paths and limit the slice to validate/apply/map/host/CI |
| Live eval secrets unavailable on fork PRs | Keep PR gates offline; run live evals in trusted nightly and release contexts |
| Cross-platform Python command names differ | Test interpreter discovery and provide host-specific launch configuration |

## 16. Authoritative Platform References

- Codex plugin structure: <https://developers.openai.com/codex/plugins/build>
- Codex lifecycle hooks: <https://learn.chatgpt.com/codex/hooks>
- Codex advanced configuration: <https://developers.openai.com/codex/config-advanced>
- Claude Code plugin reference: <https://code.claude.com/docs/en/plugins-reference>
- Claude Code hook reference: <https://code.claude.com/docs/en/hooks>
- Supported Python versions: <https://devguide.python.org/versions/>
