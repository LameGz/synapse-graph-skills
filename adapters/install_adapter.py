#!/usr/bin/env python3
"""install_adapter.py — Pluggable host adapter installer for Synapse.

Different agent hosts integrate with Synapse in different ways, but the
memory policy always lives in the shared scripts — adapters only normalize
lifecycle events (detect / register hooks or instructions / prefetch /
record). Adding a new host means dropping a module into ``hosts/`` that
exposes ``NAME``, ``ALIASES``, ``detect()`` and ``install()``.

Usage:
  python adapters/install_adapter.py list
  python adapters/install_adapter.py auto --project .
  python adapters/install_adapter.py claude-code --project .
  python adapters/install_adapter.py codex --project .
  python adapters/install_adapter.py gemini-cli --project .
  python adapters/install_adapter.py pi --project .
  python adapters/install_adapter.py generic --project .

Options:
  --synapse-root <dir>  Path to the synapse-graph-memory skill
                        (default: <repo>/synapse-graph-memory, falling back to
                        ~/.claude/skills/synapse-graph-memory)
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

ADAPTERS_DIR = Path(__file__).resolve().parent
HOSTS_DIR = ADAPTERS_DIR / "hosts"
MARKER = Path(".synapse") / "adapter.json"


def discover_hosts() -> dict[str, dict]:
    """Import every hosts/*.py and index them by NAME and ALIASES."""
    hosts: dict[str, dict] = {}
    if not HOSTS_DIR.is_dir():
        return hosts
    for path in sorted(HOSTS_DIR.glob("*.py")):
        if path.name.startswith("_"):
            continue
        spec = importlib.util.spec_from_file_location(f"synapse_host_{path.stem}", path)
        if spec is None or spec.loader is None:
            continue
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        entry = {
            "name": getattr(module, "NAME", path.stem),
            "aliases": list(getattr(module, "ALIASES", [])),
            "detect": getattr(module, "detect", lambda project: False),
            "install": getattr(module, "install", None),
            "describe": getattr(module, "describe", lambda: ""),
            "module": path.stem,
        }
        if entry["install"] is None:
            continue
        host_entry = dict(entry)
        host_entry["describe"] = entry["describe"]()
        hosts[entry["name"]] = host_entry
        for alias in entry["aliases"]:
            hosts.setdefault(alias, host_entry)
    return hosts


def resolve_synapse_root(arg: str | None) -> Path:
    candidates = []
    if arg:
        candidates.append(Path(arg))
    candidates.append(ADAPTERS_DIR.parent / "synapse-graph-memory")
    home_skills = Path.home() / ".claude" / "skills" / "synapse-graph-memory"
    candidates.append(home_skills)
    for cand in candidates:
        if (cand / "scripts").is_dir():
            return cand.resolve()
    raise SystemExit(
        "synapse-graph-memory skill not found. Pass --synapse-root <dir> "
        f"(tried: {', '.join(str(c) for c in candidates)})"
    )


def write_marker(project: Path, host: str, synapse_root: Path) -> Path:
    marker = project / MARKER
    marker.parent.mkdir(parents=True, exist_ok=True)
    marker.write_text(
        json.dumps(
            {
                "host": host,
                "synapse_root": str(synapse_root),
                "installed_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    return marker


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("host", help="Host adapter name, alias, 'auto' (detect), or 'list'")
    parser.add_argument("--project", default=".", help="Target project root (default: cwd)")
    parser.add_argument("--synapse-root", help="Path to synapse-graph-memory skill")
    args = parser.parse_args()

    hosts = discover_hosts()
    if args.host == "list":
        print("Available host adapters:")
        seen: set[str] = set()
        for entry in hosts.values():
            if entry["name"] in seen:
                continue
            seen.add(entry["name"])
            aliases = ", ".join(entry["aliases"])
            print(f"  {entry['name']:<14} aliases: {aliases:<28} {entry['describe']}")
        return 0

    synapse_root = resolve_synapse_root(args.synapse_root)
    project = Path(args.project).resolve()

    if args.host == "auto":
        chosen = None
        for entry in hosts.values():
            try:
                if entry["detect"](project):
                    chosen = entry
                    break
            except Exception:
                continue
        if chosen is None:
            chosen = hosts["generic"]
        host_key = chosen["name"]
        print(f"Auto-detected host: {host_key}")
    else:
        chosen = hosts.get(args.host)
        if chosen is None:
            print(f"Unknown host: {args.host}. Use 'list' to see options.", file=sys.stderr)
            return 2
        host_key = args.host

    try:
        written = chosen["install"](project, synapse_root, host_key)
    except TypeError:
        written = chosen["install"](project, synapse_root)
    marker = write_marker(project, chosen["name"], synapse_root)
    written.append(str(marker.relative_to(project)))

    print(f"Installed Synapse adapter for '{chosen['name']}' in {project}")
    for item in written:
        print(f"  wrote: {item}")
    print(f"Memory engine: {synapse_root}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
