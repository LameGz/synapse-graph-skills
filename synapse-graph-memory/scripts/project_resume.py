#!/usr/bin/env python3
"""Summarize a Synapse project from MEMORY_MAP.json with minimal node reads."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def load_map(project: Path) -> dict:
    path = project / "MEMORY_MAP.json"
    if not path.exists():
        raise SystemExit(f"MEMORY_MAP.json not found: {path}")
    return json.loads(path.read_text(encoding="utf-8-sig"))


def matches_focus(node: dict, focus: str | None) -> bool:
    if not focus:
        return True
    focus_l = focus.lower()
    haystack = " ".join(
        [
            str(node.get("id", "")),
            str(node.get("summary", "")),
            " ".join(node.get("tags", [])),
            " ".join(node.get("aliases", [])),
        ]
    ).lower()
    return focus_l in haystack


def build_resume(project: Path, focus: str | None = None) -> dict:
    data = load_map(project)
    nodes = [node for node in data.get("nodes", []) if matches_focus(node, focus)]
    if not nodes and focus:
        nodes = data.get("nodes", [])
    current_focus = sorted(
        [node for node in nodes if node.get("status") == "in-progress"],
        key=lambda node: node.get("updated", ""),
        reverse=True,
    )[:5]
    recent_changes = []
    for node in nodes:
        for entry in node.get("changelog", []):
            recent_changes.append(
                {
                    "date": entry.get("date", ""),
                    "node": node.get("id", ""),
                    "summary": entry.get("summary", ""),
                }
            )
    recent_changes = sorted(recent_changes, key=lambda item: item["date"], reverse=True)[:8]
    open_issue_nodes = [
        {
            "id": node.get("id", ""),
            "path": node.get("path", node.get("rel", "")),
            "open_issue_count": len(node.get("open_issues", [])),
            "summary": node.get("summary", ""),
        }
        for node in nodes
        if node.get("open_issues")
    ]
    open_issue_nodes.sort(key=lambda item: item["open_issue_count"], reverse=True)
    actions = []
    if open_issue_nodes:
        actions.append(f"Review open issues in {open_issue_nodes[0]['id']}")
    if current_focus:
        actions.append(f"Continue {current_focus[0]['id']} from its latest Change Log entry")
    actions.append("Run doctor before editing memory nodes")
    return {
        "focus": focus or "all",
        "stats": data.get("stats", {}),
        "current_focus": current_focus,
        "recent_changes": recent_changes,
        "open_issues": open_issue_nodes[:8],
        "suggested_next_actions": actions,
    }


def render_text(resume: dict) -> str:
    lines = [
        "Synapse Project Resume",
        "======================",
        "",
        f"Focus: {resume['focus']}",
        "",
        "Current Focus",
        "-------------",
    ]
    if resume["current_focus"]:
        for node in resume["current_focus"]:
            lines.append(f"- {node.get('id')} ({node.get('status')}, updated {node.get('updated')}) - {node.get('summary')}")
    else:
        lines.append("- No in-progress nodes found.")
    lines.extend(["", "Recent Changes", "--------------"])
    if resume["recent_changes"]:
        for item in resume["recent_changes"]:
            lines.append(f"- [{item['date']}] {item['node']}: {item['summary']}")
    else:
        lines.append("- No recent Change Log entries found.")
    lines.extend(["", "Open Issues", "-----------"])
    if resume["open_issues"]:
        for item in resume["open_issues"]:
            lines.append(f"- {item['id']}: {item['open_issue_count']} open issue(s) - {item['path']}")
    else:
        lines.append("- No open issues indexed.")
    lines.extend(["", "Suggested Next Actions", "----------------------"])
    for action in resume["suggested_next_actions"]:
        lines.append(f"- {action}")
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description="Resume a Synapse project from MEMORY_MAP.json.")
    parser.add_argument("--project", default=".")
    parser.add_argument("--focus")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    resume = build_resume(Path(args.project).resolve(), args.focus)
    if args.json:
        print(json.dumps(resume, ensure_ascii=False, indent=2))
    else:
        print(render_text(resume), end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
