"""Generic fallback host adapter.

For hosts with neither hooks nor AGENTS.md support: writes a standalone
instruction file the user (or a wrapper script) can wire up manually, and
prints the same protocol to stdout.
"""

from __future__ import annotations

from pathlib import Path

NAME = "generic"
ALIASES = ["manual"]

TEMPLATE = Path(__file__).resolve().parent.parent / "agents-section.md"


def describe() -> str:
    return "Generic: writes .synapse/agent-instructions.md for manual wiring"


def detect(project: Path) -> bool:
    return False  # never auto-detected; explicit choice only


def install(project: Path, synapse_root: Path) -> list[str]:
    out = project / ".synapse" / "agent-instructions.md"
    out.parent.mkdir(parents=True, exist_ok=True)
    body = TEMPLATE.read_text(encoding="utf-8").replace("{engine}", synapse_root.as_posix())
    for marker in ("<!-- synapse:begin -->", "<!-- synapse:end -->"):
        body = body.replace(marker + "\n", "")
    out.write_text(body.lstrip(), encoding="utf-8")
    print(out.read_text(encoding="utf-8"))
    return [".synapse/agent-instructions.md"]
