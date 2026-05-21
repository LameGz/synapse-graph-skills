# Contributing to Synapse Graph Skills

## Skill Structure

Each skill follows the [skill-creator](https://docs.anthropic.com/claude-code) format:

```
skill-name/
├── SKILL.md          # Required: YAML frontmatter + markdown instructions
├── scripts/          # Executable automation (bash + Python stdlib)
├── references/       # Docs loaded on demand by the skill
├── assets/           # Templates and config files
└── evals/
    └── evals.json    # Test cases with assertions
```

## Adding a New Skill

1. Copy `skills/synapse-timeline/` as a template (it's the simplest at 4 files)
2. Fill in the YAML frontmatter:
   - `name`: kebab-case, prefix with `synapse-` if it's part of this ecosystem
   - `description`: intent-based, Chinese + English phrases matching real user queries
3. Write trigger patterns that are specific enough to avoid false positives
4. Add at least 4 eval cases to `evals/evals.json`:
   - 3 should-trigger cases
   - 1 should-not-trigger case
5. Bundle scripts using `SCRIPT_DIR` for same-directory references

## Description Guidelines

Descriptions must be **intent-based, not file-existence-based**:

```yaml
# Good — matches what users actually say
description: 用户询问某个功能/模块的状态、进度时激活。触发词包括"做得怎么样了"、"还差什么"、"会影响哪些功能"。

# Bad — checks for file existence, blocks triggering
description: Use when a project contains MEMORY_MAP.md and meta/ directory.
```

## Script Conventions

- All bash scripts: `#!/usr/bin/env bash`, `set -euo pipefail`
- Python scripts: `#!/usr/bin/env python3`, stdlib only (no pip deps)
- Same-directory references: `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"`
- All scripts must respond to `--help` with usage
- Exit codes: 0 = success, 1 = user error, 2 = dependency missing

## Eval Format

```json
{
  "skill_name": "synapse-xxx",
  "evals": [
    {
      "id": 1,
      "name": "descriptive-name",
      "prompt": "Realistic user query in Chinese or English",
      "expected_output": "What the skill should produce",
      "assertions": [
        {
          "name": "short-check-name",
          "description": "What this assertion verifies",
          "check": "content_contains | order_check | must_not_read | must_not_read_glob",
          "expected": "expected string or pattern"
        }
      ]
    }
  ]
}
```

## PR Checklist

- [ ] SKILL.md is under 200 lines (push detail to references/)
- [ ] Frontmatter has `name` and `description`
- [ ] Description uses intent-based triggers (Chinese + English)
- [ ] At least 4 eval cases in `evals/evals.json`
- [ ] Scripts pass `shellcheck -S warning`
- [ ] Python scripts use stdlib only
- [ ] `scripts/` files are executable (`chmod +x`)
- [ ] README updated if adding a new skill

## Running Tests

```bash
# Validate all JSON files
find . -name "*.json" -exec python3 -c "import json; json.load(open('{}'))" \;

# Lint shell scripts
find skills/ -name "*.sh" -exec shellcheck -x -S warning {} \;

# Run eval suite (requires Claude Code)
# See tests/test_runner.sh
bash tests/test_runner.sh --skill synapse-timeline
```

## Release Process

1. Update `release-advisory.json` with version bump
2. Tag: `git tag -a v1.x.0 -m "Release v1.x.0"`
3. Push tag: `git push origin v1.x.0`
4. CI packages `.skill` files and creates GitHub Release
5. Users install via: copy `.skill` to `.claude/skills/` or use Claude Code skill installer