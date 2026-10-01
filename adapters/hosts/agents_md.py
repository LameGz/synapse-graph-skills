"""AGENTS.md-spec host adapter (Codex CLI, Gemini CLI, Pi, Zed, OpenCode, ...).

These hosts read repository instructions from AGENTS.md (Gemini CLI also
honors GEMINI.md) but expose no hook system, so integration is
instruction-driven: a managed Synapse section teaches the agent to
  1. restore project context at session start  (project_resume.py)
  2. prefetch matching memory for the user's ask (prefetch_context.py)
  3. record durable work before finishing a turn (auto_observe.py + memory_inbox.py)
  4. use query_timeline.sh for status/timeline queries

The section lives between BEGIN/END markers and is replaced on reinstall.
"""

from __future__ import annotations

from pathlib import Path

NAME = "agents-md"
ALIASES = ["codex", "gemini-cli", "gemini", "pi", "zed", "opencode", "cursor"]

BEGIN = "<!-- synapse:begin -->"
END = "<!-- synapse:end -->"
TEMPLATE = Path(__file__).resolve().parent.parent / "agents-section.md"


def describe() -> str:
    return "AGENTS.md-spec hosts (Codex/Gemini CLI/Pi/...): managed instruction section"


def detect(project: Path) -> bool:
    return (project / "AGENTS.md").is_file()


def _doc_file(host_key: str) -> str:
    return "GEMINI.md" if host_key in ("gemini-cli", "gemini") else "AGENTS.md"


def _section(synapse_root: Path) -> str:
    return TEMPLATE.read_text(encoding="utf-8").replace("{engine}", synapse_root.as_posix())


def install(project: Path, synapse_root: Path, host_key: str = "agents-md") -> list[str]:
    doc = project / _doc_file(host_key)
    section = _section(synapse_root)
    if doc.exists():
        text = doc.read_text(encoding="utf-8-sig")
        if BEGIN in text and END in text:
            head, rest = text.split(BEGIN, 1)
            _, tail = rest.split(END, 1)
            new_text = head + section + tail
        else:
            new_text = text.rstrip() + "\n\n" + section + "\n"
    else:
        new_text = f"# Agent Instructions\n\n{section}\n"
    doc.write_text(new_text, encoding="utf-8")
    return [doc.name]
