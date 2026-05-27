#!/usr/bin/env python3
"""Persistent review queue for Synapse memory proposals."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from datetime import datetime, timezone
from pathlib import Path


INBOX_VERSION = 1


def inbox_path(project: Path) -> Path:
    return project / ".synapse" / "inbox.json"


def normalize_content(content: str) -> str:
    normalized = re.sub(r"\s+", " ", content.strip().lower())
    return normalized.strip(" .。!！?？")


def item_key(item: dict) -> str:
    return "|".join(
        [
            str(item.get("target_node", "unknown")),
            str(item.get("change_type", "change_log")),
            normalize_content(str(item.get("content", ""))),
        ]
    )


def make_id(item: dict) -> str:
    return hashlib.sha1(item_key(item).encode("utf-8")).hexdigest()[:12]


def load_inbox(project: Path) -> dict:
    path = inbox_path(project)
    if not path.exists():
        return {"version": INBOX_VERSION, "items": []}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {"version": INBOX_VERSION, "items": []}
    data.setdefault("version", INBOX_VERSION)
    data.setdefault("items", [])
    return data


def save_inbox(project: Path, data: dict) -> None:
    path = inbox_path(project)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def coerce_evidence(value) -> list[str]:
    if value is None or value == "":
        return []
    if isinstance(value, list):
        return [str(item) for item in value if str(item)]
    return [str(value)]


def proposal_to_item(proposal: dict) -> dict:
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    item = {
        "target_node": proposal.get("target_node", "unknown"),
        "change_type": proposal.get("change_type", "change_log"),
        "content": str(proposal.get("content", "")).strip(),
        "confidence": int(proposal.get("confidence", 0) or 0),
        "source": proposal.get("source", "unknown"),
        "evidence": coerce_evidence(proposal.get("evidence")),
        "created_at": proposal.get("created_at", now),
    }
    item["id"] = proposal.get("id") or make_id(item)
    return item


def add_item(project: Path | str, proposal: dict) -> str:
    project = Path(project)
    item = proposal_to_item(proposal)
    if not item["content"]:
        return "ignored"
    data = load_inbox(project)
    key = item_key(item)
    for existing in data["items"]:
        if item_key(existing) == key:
            existing["confidence"] = max(int(existing.get("confidence", 0)), item["confidence"])
            evidence = existing.setdefault("evidence", [])
            for line in item["evidence"]:
                if line not in evidence:
                    evidence.append(line)
            sources = set(str(existing.get("source", "")).split(", "))
            sources.add(str(item.get("source", "unknown")))
            existing["source"] = ", ".join(sorted(source for source in sources if source))
            save_inbox(project, data)
            return "duplicate"
    data["items"].append(item)
    save_inbox(project, data)
    return "queued"


def section_bounds(lines: list[str], heading: str) -> tuple[int | None, int | None]:
    start = next((idx for idx, line in enumerate(lines) if line.strip() == heading), None)
    if start is None:
        return None, None
    end = len(lines)
    for idx in range(start + 1, len(lines)):
        if lines[idx].startswith("## "):
            end = idx
            break
    return start, end


def insert_bullet(text: str, heading: str, bullet: str) -> str:
    lines = text.splitlines()
    start, end = section_bounds(lines, heading)
    if start is None:
        lines.extend(["", heading])
        start, end = len(lines) - 1, len(lines)
    entry = f"- {bullet}"
    if entry in lines[start + 1 : end]:
        return "\n".join(lines).rstrip() + "\n"
    if any(line.strip() == "None." for line in lines[start + 1 : end]):
        none_idx = next(idx for idx in range(start + 1, end) if lines[idx].strip() == "None.")
        lines[none_idx : none_idx + 1] = [entry]
    else:
        lines[end:end] = [entry]
    return "\n".join(lines).rstrip() + "\n"


def target_path(project: Path, target_node: str) -> Path:
    name = target_node
    if name.startswith("meta/"):
        return project / name
    if name.endswith(".md"):
        return project / "meta" / Path(name).name
    return project / "meta" / f"{name}.md"


def apply_to_node(project: Path, item: dict) -> bool:
    path = target_path(project, str(item.get("target_node", "unknown")))
    if not path.exists():
        return False
    text = path.read_text(encoding="utf-8")
    change_type = item.get("change_type", "change_log")
    content = str(item.get("content", "")).strip()
    if not content:
        return False
    if change_type == "open_issue":
        updated = insert_bullet(text, "## Open Issues", content)
    elif change_type == "key_decision":
        updated = insert_bullet(text, "## Key Decisions", content)
    else:
        today = datetime.now().strftime("%Y-%m-%d")
        updated = insert_bullet(text, "## Change Log", f"[{today}] {content}")
    path.write_text(updated, encoding="utf-8")
    return True


def apply_items(project: Path | str, limit: int | None = None) -> int:
    project = Path(project)
    data = load_inbox(project)
    remaining = []
    applied = 0
    for item in data["items"]:
        if limit is not None and applied >= limit:
            remaining.append(item)
            continue
        if apply_to_node(project, item):
            applied += 1
        else:
            remaining.append(item)
    data["items"] = remaining
    save_inbox(project, data)
    return applied


def load_proposals(path: Path) -> list[dict]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if isinstance(data, dict) and "proposals" in data:
        return list(data["proposals"])
    if isinstance(data, dict):
        return [data]
    if isinstance(data, list):
        return data
    return []


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Manage Synapse memory inbox.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""Examples:
  memory_inbox.py list --project .
  memory_inbox.py add --project . --proposal .synapse/proposal.json
  memory_inbox.py apply --project . --limit 5
  memory_inbox.py clear --project .
""",
    )
    sub = parser.add_subparsers(dest="command", required=True)
    for name in ["add", "list", "apply", "clear"]:
        p = sub.add_parser(name)
        p.add_argument("--project", default=".")
    sub.choices["add"].add_argument("--proposal", required=True)
    sub.choices["apply"].add_argument("--limit", type=int)
    args = parser.parse_args()

    project = Path(args.project).resolve()
    if args.command == "add":
        proposal_path = Path(args.proposal)
        if not proposal_path.exists():
            raise SystemExit(f"Proposal not found: {proposal_path}")
        counts = {"queued": 0, "duplicate": 0, "ignored": 0}
        for proposal in load_proposals(proposal_path):
            counts[add_item(project, proposal)] += 1
        print(f"Inbox add: queued={counts['queued']} duplicate={counts['duplicate']} ignored={counts['ignored']}")
    elif args.command == "list":
        data = load_inbox(project)
        print(f"Synapse Memory Inbox: {len(data['items'])} item(s)")
        for item in data["items"][:20]:
            print(f"- {item['id']} [{item.get('change_type')}] {item.get('target_node')}: {item.get('content')}")
    elif args.command == "apply":
        print(f"Inbox applied: {apply_items(project, args.limit)}")
    elif args.command == "clear":
        save_inbox(project, {"version": INBOX_VERSION, "items": []})
        print("Inbox cleared.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
