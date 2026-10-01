#!/usr/bin/env python3
"""Fast edge suggestion pass for Synapse memory nodes."""

from __future__ import annotations

import argparse
import re
from dataclasses import dataclass, field
from pathlib import Path


API_RE = re.compile(r"\b(GET|POST|PUT|DELETE|PATCH)\s+(/[a-zA-Z0-9_/{}:-]+)")
TABLE_RE = re.compile(r"\*\*[Tt]able\*\*:\s*([a-zA-Z_][a-zA-Z0-9_]*)")
STATE_RE = re.compile(r"shared state via ([a-zA-Z_][a-zA-Z0-9_]*)", re.IGNORECASE)


@dataclass
class Node:
    rel: str
    id: str
    depends_on: list[str] = field(default_factory=list)
    tags: list[str] = field(default_factory=list)
    identifiers: list[tuple[str, str]] = field(default_factory=list)


def parse_scalar(value: str):
    value = value.strip()
    if value == "[]":
        return []
    if value.startswith("[") and value.endswith("]"):
        return [item.strip().strip("\"'") for item in value[1:-1].split(",") if item.strip()]
    return value.strip("\"'")


def split_frontmatter(text: str):
    if not text.startswith("---"):
        return {}, text
    parts = text.split("---", 2)
    if len(parts) < 3:
        return {}, text
    frontmatter = {}
    current = None
    for line in parts[1].splitlines():
        if not line.strip():
            continue
        if line.startswith(" ") and current and line.strip().startswith("-"):
            frontmatter.setdefault(current, [])
            frontmatter[current].append(line.strip()[1:].strip().strip("\"'"))
            continue
        if ":" in line:
            key, raw = line.split(":", 1)
            key = key.strip()
            value = raw.strip()
            current = key
            frontmatter[key] = parse_scalar(value) if value else []
    return frontmatter, parts[2].lstrip("\n")


def as_list(value) -> list[str]:
    if isinstance(value, list):
        return [str(item).strip() for item in value if str(item).strip()]
    if not value:
        return []
    return [str(value).strip()]


def extract_identifiers(body: str) -> list[tuple[str, str]]:
    identifiers = []
    identifiers.extend(("api", match.group(0)) for match in API_RE.finditer(body))
    identifiers.extend(("table", match.group(1)) for match in TABLE_RE.finditer(body))
    identifiers.extend(("state", match.group(1)) for match in STATE_RE.finditer(body))
    seen = set()
    unique = []
    for kind, value in identifiers:
        key = (kind, value)
        if key not in seen:
            seen.add(key)
            unique.append(key)
    return unique


def load_nodes(project: Path) -> list[Node]:
    nodes = []
    meta = project / "meta"
    if not meta.exists():
        return nodes
    for path in sorted(meta.glob("*.md")):
        if path.name == "MEMORY_MAP.md":
            continue
        text = path.read_text(encoding="utf-8-sig")
        fm, body = split_frontmatter(text)
        rel = path.relative_to(project).as_posix()
        nodes.append(
            Node(
                rel=rel,
                id=str(fm.get("id", path.stem)),
                depends_on=as_list(fm.get("depends_on", [])),
                tags=as_list(fm.get("tags", [])),
                identifiers=extract_identifiers(body),
            )
        )
    return nodes


def already_depends(source: Node, target: Node) -> bool:
    return target.rel in source.depends_on or target.id in source.depends_on


def render(nodes: list[Node]) -> str:
    lines = [
        "Synapse Edge Suggestions",
        "   (Agent: review each suggestion, add confirmed ones to depends_on)",
        "",
    ]
    suggestions = 0
    seen_pairs = set()

    for target in nodes:
        for kind, value in target.identifiers:
            for source in nodes:
                if source.rel == target.rel:
                    continue
                if already_depends(source, target):
                    continue
                if not any(identifier_value == value for _, identifier_value in source.identifiers):
                    continue
                key = (source.id, target.id)
                if key in seen_pairs:
                    continue
                seen_pairs.add(key)
                lines.append(f"Suggested edge: {source.id} depends_on {target.id}")
                lines.append(f"   Reason: {source.id}'s Connection Points reference {value} ({kind})")
                if source.tags:
                    lines.append(f"   Tags: {' '.join(source.tags)}")
                lines.append("")
                suggestions += 1

    lines.extend(["", "-- Tag-based cross-references (weaker signal, review carefully) --", ""])
    for target in nodes:
        target_tags = {tag.lower() for tag in target.tags if len(tag) >= 4}
        if not target_tags:
            continue
        for source in nodes:
            if source.rel == target.rel:
                continue
            if already_depends(source, target):
                continue
            shared = sorted(target_tags.intersection(tag.lower() for tag in source.tags))
            if not shared:
                continue
            key = (source.id, target.id)
            if key in seen_pairs:
                continue
            seen_pairs.add(key)
            tag = shared[0]
            lines.append(f"Suggested edge: {source.id} depends_on {target.id}")
            lines.append(f"   Reason: shared tag '{tag}' (weak signal; confirm manually)")
            lines.append("")
            suggestions += 1

    lines.append("------------------------------------------------------------")
    lines.append(f"Total suggestions: {suggestions}")
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description="Suggest Synapse graph edges.")
    parser.add_argument("--project", default=".")
    parser.add_argument("--proposal")
    args = parser.parse_args()

    project = Path(args.project).resolve()
    nodes = load_nodes(project)
    if not nodes:
        print("No meta/ directory found.")
        return 0
    print(render(nodes), end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
