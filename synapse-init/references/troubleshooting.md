# Troubleshooting

## "Error: requires bash 4+"

Current bash is too old. Fix:
- **macOS**: `brew install bash` then run with `/opt/homebrew/bin/bash` or `/usr/local/bin/bash`
- **Linux**: `sudo apt install bash` (most distros already have 4+)
- **Windows**: Use Git Bash or WSL (native PowerShell cannot run bash scripts)

## "permission denied" on scripts

Scripts need execute permission:
```bash
chmod +x scripts/*.sh scripts/hooks/*.sh
```

## "python3: command not found"

The `merge_settings()` function needs Python. Either:
- Install Python 3: `brew install python3` (macOS) or `apt install python3` (Linux)
- On Windows with Python from Microsoft Store: make sure `python3.exe` is in PATH

Without Python: init still works — hooks are registered via file copy if `.claude/settings.json` doesn't exist. If it exists and needs merging, the script prints manual merge instructions.

## "MEMORY_MAP.md not found" after init

This means `generate_memory_map.sh` failed silently. Run it manually:
```bash
bash scripts/generate_memory_map.sh --project . --full
```
Check for parse errors in meta/*.md frontmatter.

## Running init on an already-initialized project (idempotency)

Init is designed to be safe to re-run:
- Existing `meta/*.md` nodes → skipped ("already exists")
- Existing `scripts/*.sh` → skipped
- Existing hooks in `.claude/settings.json` → skipped if already registered
- `MEMORY_MAP.md` → regenerated (always fresh)

No data loss.

## "No standard directories detected" / single mod_project

The project doesn't have any of the 10 well-known directory patterns. This is expected for:
- Monorepo roots
- Very small projects
- Non-standard directory layouts

Solution: manually create `meta/mod_*.md` nodes for each module, then re-run init (it will skip existing nodes) or just run `generate_memory_map.sh` to build the index.

## Hook not working after init

Check:
1. `.claude/settings.json` has the hook entries under `"hooks"."PreToolUse"` and `"hooks"."Stop"`
2. Hook scripts exist and are executable: `ls -la scripts/hooks/`
3. Restart Claude Code session (hooks are loaded on session start)
