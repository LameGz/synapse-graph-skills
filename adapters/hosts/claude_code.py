"""Claude Code host adapter.

Registers Synapse as lifecycle hooks in the project's .claude/settings.json:
  - SessionEnd   -> session-end.sh       (auto-record + MAP rebuild, once per session)
  - UserPromptSubmit -> prefetch_context.py (seamless memory prefetch into context)
  - PreToolUse (Read)        -> pre-read-check.sh  (MAP-first protocol nudge)
  - PreToolUse (Write|Edit)  -> pre-modify-check.sh (impact surface warning)
  - PostToolUse (Write|Edit) -> post-tool-use.sh   (node frontmatter validation)

Existing user hooks are preserved; Synapse entries are appended idempotently.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

NAME = "claude-code"
ALIASES = ["claude"]


def describe() -> str:
    return "Claude Code: hooks in .claude/settings.json (full lifecycle support)"


def detect(project: Path) -> bool:
    return (project / ".claude").is_dir()


def _hook_cmd(command: str, timeout: int | None = None) -> dict:
    hook = {"type": "command", "command": command}
    if timeout is not None:
        hook["timeout"] = timeout
    return hook


def _merge_hooks(settings: dict, hooks: dict) -> dict:
    for event, entries in hooks.items():
        bucket = settings.setdefault("hooks", {}).setdefault(event, [])
        def script(command):
            match = re.search(r'"([^"\n]+/scripts/(?:hooks/)?[^"\n]+)"', command or "")
            return match.group(1) if match else None
        managed = {script(h.get("command")) for entry in entries for h in entry.get("hooks", [])}
        # Replace our prior commands (including old env names/timeouts), preserving user hooks.
        kept = []
        for entry in bucket:
            hooks = [h for h in entry.get("hooks", []) if script(h.get("command")) not in managed]
            if hooks:
                kept.append({**entry, "hooks": hooks})
        bucket[:] = entries + kept
    return settings


def install(project: Path, synapse_root: Path) -> list[str]:
    hooks_dir = synapse_root / "scripts" / "hooks"
    scripts_dir = synapse_root / "scripts"
    py = "python"
    bash = "bash"

    root = synapse_root.as_posix()
    hooks = {
        "SessionEnd": [
            {"matcher": "", "hooks": [_hook_cmd(f'{bash} "{root}/scripts/hooks/session-end.sh"', timeout=60)]},
        ],
        "UserPromptSubmit": [
            {
                "matcher": "",
                "hooks": [
                    _hook_cmd(
                        f'{py} "{scripts_dir.as_posix()}/prefetch_context.py" '
                        f'--project "${{CLAUDE_PROJECT_DIR}}"'
                    )
                ],
            },
        ],
        "PreToolUse": [
            {"matcher": "Read", "hooks": [_hook_cmd(f'{bash} "{root}/scripts/hooks/pre-read-check.sh"')]},
            {"matcher": "Write|Edit", "hooks": [_hook_cmd(f'{bash} "{root}/scripts/hooks/pre-modify-check.sh"')]},
        ],
        "PostToolUse": [
            {"matcher": "Write|Edit", "hooks": [_hook_cmd(f'{bash} "{root}/scripts/hooks/post-tool-use.sh"')]},
        ],
    }

    settings_path = project / ".claude" / "settings.json"
    settings_path.parent.mkdir(parents=True, exist_ok=True)
    if settings_path.exists():
        settings = json.loads(settings_path.read_text(encoding="utf-8-sig"))
    else:
        settings = {}
    settings = _merge_hooks(settings, hooks)
    settings_path.write_text(json.dumps(settings, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return [".claude/settings.json"]
