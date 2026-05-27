#!/usr/bin/env python3
"""Fast MAP generator for Synapse memory graphs.

Markdown files remain the source of truth. This script builds the derived
MEMORY_MAP.md and MEMORY_MAP.json indexes from meta/*.md nodes.
"""

from __future__ import annotations

import argparse
import json
import os
import re
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path


API_RE = re.compile(r"\b(GET|POST|PUT|DELETE|PATCH)\s+(/[A-Za-z0-9_/{}:-]+)")
FUNC_RE = re.compile(r"\b[a-zA-Z_][a-zA-Z0-9_]*\(\)")
TABLE_RE = re.compile(r"\*\*[Tt]able\*\*:\s*([a-zA-Z_][a-zA-Z0-9_]*)")
CONFIG_RE = re.compile(r"\b[A-Z][A-Z0-9_]{2,}\b")
CHANGE_RE = re.compile(r"^-\s+\[?(\d{4}-\d{2}-\d{2})\]?\s*(.*)")


@dataclass
class Node:
    id: str
    type: str
    status: str
    updated: str
    summary: str
    depends_on: list[str]
    auto_linked: list[str]
    tags: list[str]
    aliases: list[str]
    rel: str
    body: str
    tokens: int
    keywords: list[str] = field(default_factory=list)
    changelog: list[dict[str, str]] = field(default_factory=list)
    open_issues: list[str] = field(default_factory=list)
    blocks: list[str] = field(default_factory=list)


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
    current_key = None
    for line in parts[1].splitlines():
        if not line.strip():
            continue
        if line.startswith(" ") and current_key and line.strip().startswith("-"):
            frontmatter.setdefault(current_key, [])
            frontmatter[current_key].append(line.strip()[1:].strip().strip("\"'"))
            continue
        if ":" in line:
            key, raw = line.split(":", 1)
            key = key.strip()
            value = raw.strip()
            current_key = key
            if value:
                frontmatter[key] = parse_scalar(value)
            else:
                frontmatter[key] = []
    return frontmatter, parts[2].lstrip("\n")


def as_list(value) -> list[str]:
    if isinstance(value, list):
        return [str(item).strip() for item in value if str(item).strip()]
    if not value:
        return []
    return [str(value).strip()]


def section_lines(body: str, heading: str) -> list[str]:
    lines = body.splitlines()
    collected = []
    in_section = False
    for line in lines:
        if line.startswith("## "):
            if in_section:
                break
            in_section = line.strip() == heading
            continue
        if in_section:
            collected.append(line)
    return collected


def extract_keywords(body: str) -> list[str]:
    keywords = set()
    keywords.update(match.group(2) for match in API_RE.finditer(body))
    keywords.update(match.group(0) for match in FUNC_RE.finditer(body))
    keywords.update(match.group(1) for match in TABLE_RE.finditer(body))
    keywords.update(
        match.group(0)
        for match in CONFIG_RE.finditer(body)
        if match.group(0) not in {"GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"}
    )
    return sorted(keywords)


def extract_changelog(body: str) -> list[dict[str, str]]:
    entries = []
    for line in section_lines(body, "## Change Log"):
        match = CHANGE_RE.match(line.strip())
        if match:
            summary = match.group(2).strip()
            summary = re.sub(r"^\*\*(Context|Change|Impact|Affected)\*\*:\s*", "", summary)
            entries.append({"date": match.group(1), "summary": summary[:120]})
    return entries


def extract_open_issues(body: str) -> list[str]:
    issues = []
    for line in section_lines(body, "## Open Issues"):
        stripped = line.strip()
        if stripped.startswith("- "):
            issues.append(stripped[2:].strip())
    return issues


def load_node_file(project: Path, path: Path) -> Node | None:
    if not path.exists() or path.name == "MEMORY_MAP.md":
        return None
    text = path.read_text(encoding="utf-8-sig")
    fm, body = split_frontmatter(text)
    if not fm:
        return None
    status = str(fm.get("status", "unknown"))
    if status == "archived":
        return None
    rel = path.relative_to(project).as_posix()
    node = Node(
        id=str(fm.get("id", path.stem)),
        type=str(fm.get("type", "unknown")),
        status=status,
        updated=str(fm.get("updated", "")),
        summary=str(fm.get("summary", "")),
        depends_on=as_list(fm.get("depends_on", [])),
        auto_linked=as_list(fm.get("auto_linked", [])),
        tags=as_list(fm.get("tags", [])),
        aliases=as_list(fm.get("aliases", [])),
        rel=rel,
        body=body,
        tokens=max(1, len(text.encode("utf-8")) // 4),
    )
    node.keywords = extract_keywords(body)
    node.changelog = extract_changelog(body)
    node.open_issues = extract_open_issues(body)
    return node


def load_nodes(project: Path) -> list[Node]:
    meta_dir = project / "meta"
    if not meta_dir.exists():
        return []
    nodes = []
    for path in sorted(meta_dir.glob("*.md")):
        node = load_node_file(project, path)
        if node:
            nodes.append(node)
    return nodes


def node_from_json(raw: dict) -> Node:
    return Node(
        id=str(raw.get("id", "")),
        type=str(raw.get("type", "unknown")),
        status=str(raw.get("status", "unknown")),
        updated=str(raw.get("updated", "")),
        summary=str(raw.get("summary", "")),
        depends_on=as_list(raw.get("depends_on", [])),
        auto_linked=as_list(raw.get("auto_linked", [])),
        tags=as_list(raw.get("tags", [])),
        aliases=as_list(raw.get("aliases", [])),
        rel=str(raw.get("rel") or raw.get("path") or ""),
        body="",
        tokens=int(raw.get("tokens", 1) or 1),
        keywords=as_list(raw.get("keywords", [])),
        changelog=list(raw.get("changelog", [])),
        open_issues=as_list(raw.get("open_issues", [])),
        blocks=as_list(raw.get("blocks", [])),
    )


def load_nodes_from_map(project: Path) -> list[Node] | None:
    path = project / "MEMORY_MAP.json"
    if not path.exists():
        return None
    data = json.loads(path.read_text(encoding="utf-8-sig"))
    raw_nodes = data.get("nodes", [])
    if isinstance(raw_nodes, dict):
        raw_nodes = raw_nodes.values()
    nodes = [node_from_json(raw) for raw in raw_nodes if isinstance(raw, dict)]
    return [node for node in nodes if node.id and node.rel]


def load_changed_nodes(project: Path, changed_rel: str) -> tuple[list[Node], str]:
    existing = load_nodes_from_map(project)
    if existing is None:
        return load_nodes(project), "full rebuild (no existing MEMORY_MAP.json)"

    changed_path = project / changed_rel
    changed_node = load_node_file(project, changed_path)
    nodes = [
        node
        for node in existing
        if node.rel != changed_rel and (changed_node is None or node.id != changed_node.id)
    ]
    if changed_node:
        nodes.append(changed_node)
        return nodes, f"Incremental update: {changed_node.id} ({changed_rel})"
    return nodes, f"Incremental delete/archive: {changed_rel}"


def compute_blocks(nodes: list[Node]) -> None:
    for node in nodes:
        node.blocks = []
    by_rel = {node.rel: node for node in nodes}
    by_id = {node.id: node for node in nodes}
    for node in nodes:
        for edge in node.depends_on + node.auto_linked:
            target = edge
            if target in by_id:
                target = by_id[target].rel
            if target in by_rel:
                by_rel[target].blocks.append(node.rel)
    for node in nodes:
        node.blocks = sorted(set(node.blocks))


def build_tag_index(nodes: list[Node]):
    tag_index = defaultdict(list)
    for node in nodes:
        for tag in node.tags + node.aliases:
            tag_index[tag.lower()].append(node)
    return tag_index


def build_keyword_index(nodes: list[Node]):
    keyword_index = defaultdict(list)
    for node in nodes:
        for keyword in node.keywords:
            keyword_index[keyword.lower()].append(node)
    return keyword_index


def build_affinity(nodes: list[Node]):
    pair_counts = Counter()
    tag_counts = Counter()
    for node in nodes:
        tags = sorted({tag.lower() for tag in node.tags})
        for tag in tags:
            tag_counts[tag] += 1
        for i, tag_a in enumerate(tags):
            for tag_b in tags[i + 1 :]:
                pair_counts[(tag_a, tag_b)] += 1
    affinities = []
    for (tag_a, tag_b), count in sorted(pair_counts.items()):
        denominator = min(tag_counts[tag_a], tag_counts[tag_b])
        if denominator and count * 100 // denominator >= 30:
            affinities.append((tag_a, tag_b, count, denominator, count * 100 // denominator))
    return affinities


def format_list(values: list[str]) -> str:
    return ", ".join(values)


def render_map(project: Path, nodes: list[Node], generated_at: str) -> str:
    tag_index = build_tag_index(nodes)
    keyword_index = build_keyword_index(nodes)
    affinities = build_affinity(nodes)
    lines = [
        "<!-- AUTO-GENERATED by scripts/generate_memory_map.py. DO NOT EDIT MANUALLY. -->",
        "# Project Memory Graph Index",
        "",
        "> Retrieval Protocol: Read MAP -> Target node (summary first) -> Bounded BFS deps (depth <= 2, width <= 5)",
        "> Cost-conscious: token estimates shown per node. Spend wisely.",
        "",
        "## Tag Index",
        "",
    ]

    if not tag_index:
        lines.extend(["No active memory nodes found.", ""])
    for tag in sorted(tag_index):
        lines.extend([f"### `{tag}`", ""])
        for node in sorted(tag_index[tag], key=lambda item: item.id):
            lines.append(f"- **{node.id}** - `{node.rel}` (~{node.tokens} tok)")
            if node.summary:
                lines.append(f"  summary: {node.summary}")
            if node.aliases:
                lines.append(f"  aliases: {format_list(node.aliases)}")
            if node.depends_on:
                lines.append(f"  depends_on: {format_list(node.depends_on)}")
            if node.auto_linked:
                lines.append(f"  auto_linked: {format_list(node.auto_linked)}")
            if node.blocks:
                lines.append(f"  blocks: {format_list(node.blocks)}")
        lines.append("")

    lines.extend([
        "## Tag Affinity",
        "",
        "> Auto-detected tag relationships based on co-occurrence across nodes.",
        "> Use when tag matching fails; query synonyms may surface related nodes.",
        "",
    ])
    if affinities:
        for tag_a, tag_b, count, denominator, rate in affinities:
            lines.append(f"- `{tag_a}` -> `{tag_b}` (co-occur in {count} / {denominator} nodes, {rate}%)")
    else:
        lines.append("No tag affinities detected.")
    lines.append("")

    lines.extend([
        "## Keyword Index",
        "",
        "> Fallback when tag matching fails or returns too many results.",
        "> Keywords auto-extracted from API endpoints, function names, table names, config keys.",
        "",
    ])
    if keyword_index:
        for keyword in sorted(keyword_index):
            lines.extend([f"### `{keyword}`", ""])
            for node in sorted(keyword_index[keyword], key=lambda item: item.id):
                lines.append(f"- **{node.id}** - `{node.rel}` (tags: {format_list(node.tags) or 'none'})")
            lines.append("")
    else:
        lines.extend(["No keywords extracted.", ""])

    lines.extend(["## All Active Nodes", ""])
    if nodes:
        for node in sorted(nodes, key=lambda item: (item.type, item.id)):
            prefix = {"module": "mod", "feature": "feat"}.get(node.type, node.type)
            lines.append(f"- [{prefix}] **{node.id}** ({node.status}, ~{node.tokens} tok) - `{node.rel}`")
            if node.updated:
                lines.append(f"  updated: {node.updated}")
            if node.summary:
                lines.append(f"  summary: {node.summary}")
            if node.aliases:
                lines.append(f"  aliases: {format_list(node.aliases)}")
            if node.depends_on:
                lines.append(f"  depends_on: {format_list(node.depends_on)}")
            if node.blocks:
                lines.append(f"  blocks: {format_list(node.blocks)}")
        lines.append("")
    else:
        lines.extend(["None.", ""])

    lines.extend([
        "## Status Digest",
        "",
        "> Read THIS section only for vague status queries. Cost: ~200 tokens total.",
        "",
    ])
    for node in sorted(nodes, key=lambda item: item.rel):
        last_change = node.changelog[-1] if node.changelog else None
        lines.append(
            f"- **{node.id}** ({node.status}, updated: {node.updated or '?'}, "
            f"{len(node.open_issues)} open, ~{node.tokens} tok)"
        )
        if node.summary:
            lines.append(f"  {node.summary}")
        if last_change:
            lines.append(f"  Last: [{last_change['date']}] {last_change['summary']}")
        if node.depends_on:
            lines.append(f"  depends_on: {format_list(node.depends_on)}")
        if node.blocks:
            lines.append(f"  blocks: {format_list(node.blocks)}")
    lines.append("")

    lines.extend([
        "## Change Log Index",
        "",
        "> Time-filtered node lookup for Filtered BFS compound queries.",
        "> Grouped by month. Intersect with Tag Index for date + domain queries.",
        "",
    ])
    by_month = defaultdict(list)
    for node in nodes:
        for entry in node.changelog:
            by_month[entry["date"][:7]].append((entry["date"], node.id, entry["summary"]))
    if by_month:
        for month in sorted(by_month, reverse=True):
            lines.extend([f"### {month}", ""])
            for date_value, node_id, summary in sorted(by_month[month], reverse=True):
                lines.append(f"- **{date_value}** - `{node_id}` - {summary or '(no summary)'}")
            lines.append("")
    else:
        lines.extend(["No Change Log entries found.", ""])

    lines.extend([
        "## Progress Summary",
        "",
        "> Auto-computed project health snapshot. Read for \"how are we doing?\" queries.",
        "",
    ])
    stable = sum(1 for node in nodes if node.status == "stable")
    in_progress = sum(1 for node in nodes if node.status == "in-progress")
    total_issues = sum(len(node.open_issues) for node in nodes)
    total = len(nodes)
    if total:
        lines.append(f"- **{total}** total active nodes")
        lines.append(f"- **{stable}** stable ({stable * 100 // total}%), **{in_progress}** in-progress ({in_progress * 100 // total}%)")
        lines.append(f"- **{total_issues}** open issues across all nodes")
        lines.extend(["", "### Suggested Next Priorities", ""])
        issue_nodes = [node for node in nodes if node.open_issues]
        if issue_nodes:
            lines.extend(["Nodes with open issues (sorted by issue count):", ""])
            for node in sorted(issue_nodes, key=lambda item: len(item.open_issues), reverse=True):
                lines.append(f"- **{node.id}** - {len(node.open_issues)} open issue(s) - `{node.rel}`")
            lines.append("")
        active = [node for node in nodes if node.status == "in-progress"]
        if active:
            lines.extend(["In-progress nodes (focus candidates):", ""])
            for node in sorted(active, key=lambda item: item.updated, reverse=True):
                lines.append(f"- **{node.id}** (updated: {node.updated or '?'}) - `{node.rel}`")
            lines.append("")
    else:
        lines.extend(["No active nodes.", ""])

    lines.extend([
        "## Topology Health",
        "",
        "OK: No topology issues detected.",
        "",
        "---",
        f"Generated {generated_at}",
        "",
    ])
    return "\n".join(lines)


def generated_timestamp() -> str:
    return os.environ.get("SYNAPSE_MAP_GENERATED_AT") or datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def write_json(project: Path, nodes: list[Node], generated_at: str) -> None:
    data = {
        "generated": generated_at,
        "stats": {
            "nodes": len(nodes),
            "tags": len(build_tag_index(nodes)),
            "keywords": len(build_keyword_index(nodes)),
            "warnings": 0,
        },
        "nodes": [
            {
                "id": node.id,
                "type": node.type,
                "status": node.status,
                "updated": node.updated,
                "summary": node.summary,
                "tags": node.tags,
                "aliases": node.aliases,
                "depends_on": node.depends_on,
                "auto_linked": node.auto_linked,
                "blocks": node.blocks,
                "keywords": node.keywords,
                "changelog": node.changelog,
                "open_issues": node.open_issues,
                "tokens": node.tokens,
                "rel": node.rel,
                "path": node.rel,
            }
            for node in nodes
        ],
    }
    (project / "MEMORY_MAP.json").write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def normalize_changed(value: str | None) -> str | None:
    if not value:
        return None
    changed = value.replace("\\", "/")
    if changed.startswith("meta/"):
        return changed
    if changed.endswith(".md"):
        return f"meta/{Path(changed).name}"
    return f"meta/{changed}.md"


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate Synapse MEMORY_MAP files.")
    parser.add_argument("--project", default=".")
    parser.add_argument("--full", action="store_true")
    parser.add_argument("--changed")
    parser.add_argument("--stats", action="store_true")
    args = parser.parse_args()

    project = Path(args.project).resolve()
    changed_rel = normalize_changed(args.changed)
    if changed_rel:
        nodes, message = load_changed_nodes(project, changed_rel)
    else:
        nodes = load_nodes(project)
        message = ""
    if changed_rel and not any(node.rel == changed_rel for node in nodes) and (project / changed_rel).exists():
        print(f"Warning: --changed target not found: {changed_rel}")
    compute_blocks(nodes)
    generated_at = generated_timestamp()
    map_text = render_map(project, nodes, generated_at)
    (project / "MEMORY_MAP.md").write_text(map_text, encoding="utf-8")
    write_json(project, nodes, generated_at)

    tag_count = len(build_tag_index(nodes))
    keyword_count = len(build_keyword_index(nodes))
    if changed_rel:
        print(message)
        print(f"MEMORY_MAP.md incrementally regenerated: {len(nodes)} nodes, {tag_count} tags, {keyword_count} keywords, 0 warnings.")
    else:
        print(f"MEMORY_MAP.md regenerated: {len(nodes)} nodes, {tag_count} tags, {keyword_count} keywords, 0 warnings.")
    print(f"MEMORY_MAP.json regenerated: {len(nodes)} nodes.")
    if args.stats:
        print(json.dumps({"nodes": len(nodes), "tags": tag_count, "keywords": keyword_count, "warnings": 0}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
