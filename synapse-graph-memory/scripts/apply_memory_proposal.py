#!/usr/bin/env python3
import argparse
import json
from pathlib import Path


SECTION_ORDER = [
    "## Current State",
    "## Key Decisions",
    "## Cross-Module Connection Points",
    "## Open Issues",
    "## Change Log",
]


def format_scalar(value):
    if isinstance(value, str):
        if value == "":
            return '""'
        if any(ch in value for ch in [":", "#", "[", "]", "{", "}"]):
            return json.dumps(value, ensure_ascii=False)
        return value
    return json.dumps(value, ensure_ascii=False)


def format_frontmatter(frontmatter):
    lines = ["---"]
    for key, value in frontmatter.items():
        if isinstance(value, list):
            if value:
                lines.append(f"{key}:")
                lines.extend(f"  - {item}" for item in value)
            else:
                lines.append(f"{key}: []")
        else:
            lines.append(f"{key}: {format_scalar(value)}")
    lines.append("---")
    return "\n".join(lines)


def split_frontmatter(text):
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
            frontmatter[current].append(line.strip()[1:].strip())
            continue
        if ":" in line:
            key, raw = line.split(":", 1)
            key = key.strip()
            value = raw.strip()
            current = key
            if value == "[]":
                frontmatter[key] = []
            elif value.startswith("[") and value.endswith("]"):
                frontmatter[key] = [item.strip().strip('"\'') for item in value[1:-1].split(",") if item.strip()]
            elif value:
                frontmatter[key] = value.strip('"')
            else:
                frontmatter[key] = []
    return frontmatter, parts[2].lstrip("\n")


def create_body(proposal):
    frontmatter = proposal.get("suggested_frontmatter", {})
    title = frontmatter.get("summary") or frontmatter.get("id") or Path(proposal["target_node"]).stem
    bullets = proposal.get("node_update", {}).get("current_state_bullets", [])
    change = proposal.get("node_update", {}).get("change_log_entry", {})
    lines = [
        f"# {title}",
        "",
        "## Current State",
    ]
    lines.extend(f"- {bullet}" for bullet in bullets)
    lines.extend([
        "",
        "## Key Decisions",
        "None.",
        "",
        "## Cross-Module Connection Points",
        "None.",
        "",
        "## Open Issues",
        "None.",
        "",
        "## Change Log",
    ])
    if change:
        lines.extend(format_change_log(change))
    else:
        lines.append("None.")
    return "\n".join(lines) + "\n"


def section_bounds(lines, heading):
    start = next((i for i, line in enumerate(lines) if line.strip() == heading), None)
    if start is None:
        return None, None
    end = len(lines)
    for i in range(start + 1, len(lines)):
        if lines[i].startswith("## "):
            end = i
            break
    return start, end


def existing_bullet_values(lines, start, end):
    values = set()
    if start is None:
        return values
    for line in lines[start + 1:end]:
        stripped = line.strip()
        if stripped.startswith("- "):
            values.add(stripped[2:])
    return values


def insert_current_state(lines, bullets):
    start, end = section_bounds(lines, "## Current State")
    if start is None:
        lines.extend(["", "## Current State"])
        start, end = len(lines) - 1, len(lines)
    existing = existing_bullet_values(lines, start, end)
    additions = [f"- {bullet}" for bullet in bullets if bullet not in existing]
    if additions:
        lines[end:end] = additions
    return lines


def format_change_log(change):
    date = change.get("date", "unknown-date")
    entry = [f"- [{date}] {change.get('change', '').strip()}"]
    if change.get("context"):
        entry.append(f"  - **Context**: {change['context']}")
    if change.get("impact"):
        entry.append(f"  - **Impact**: {change['impact']}")
    if change.get("affected"):
        entry.append(f"  - **Affected**: {change['affected']}")
    return entry


def insert_change_log(lines, change):
    if not change:
        return lines
    start, end = section_bounds(lines, "## Change Log")
    if start is None:
        lines.extend(["", "## Change Log"])
        start, end = len(lines) - 1, len(lines)
    entry = format_change_log(change)
    if entry[0] not in lines[start + 1:end]:
        lines[end:end] = entry
    return lines


def add_edges(frontmatter, proposal, edge_mode):
    if edge_mode == "none":
        return frontmatter

    target_key = "depends_on" if edge_mode == "explicit" else "auto_linked"
    existing = list(frontmatter.get(target_key, []))
    for edge in proposal.get("edge_candidates", []):
        if edge_mode == "auto" and edge.get("apply_to") != "auto_linked":
            continue
        target = edge.get("to")
        if target and target not in existing:
            existing.append(target)
    frontmatter[target_key] = existing
    return frontmatter


def edge_evidence_lines(proposal):
    lines = []
    for edge in proposal.get("edge_candidates", []):
        if edge.get("apply_to") != "auto_linked":
            continue
        target = edge.get("to")
        evidence = "; ".join(edge.get("evidence", []))
        if target and evidence:
            lines.append(f"- **Auto-linked** `{target}`: {evidence}")
    return lines


def insert_edge_evidence(lines, proposal):
    additions = [line for line in edge_evidence_lines(proposal) if line not in lines]
    if not additions:
        return lines
    start, end = section_bounds(lines, "## Cross-Module Connection Points")
    if start is None:
        lines.extend(["", "## Cross-Module Connection Points"])
        start, end = len(lines) - 1, len(lines)
    if end == start + 1:
        lines[end:end] = additions
    elif any(line.strip() == "None." for line in lines[start + 1:end]):
        first_none = next(i for i in range(start + 1, end) if lines[i].strip() == "None.")
        lines[first_none:first_none + 1] = additions
    else:
        lines[end:end] = additions
    return lines


def insert_edge_review_issues(lines, proposal):
    additions = []
    for edge in proposal.get("edge_candidates", []):
        target = edge.get("to")
        if not target:
            continue
        evidence = "; ".join(edge.get("evidence", []))
        line = f"- Review potential edge to `{target}`"
        if evidence:
            line += f": {evidence}"
        additions.append(line)
    additions = [line for line in additions if line not in lines]
    if not additions:
        return lines
    start, end = section_bounds(lines, "## Open Issues")
    if start is None:
        lines.extend(["", "## Open Issues"])
        start, end = len(lines) - 1, len(lines)
    if any(line.strip() == "None." for line in lines[start + 1:end]):
        first_none = next(i for i in range(start + 1, end) if lines[i].strip() == "None.")
        lines[first_none:first_none + 1] = additions
    else:
        lines[end:end] = additions
    return lines


def apply_proposal(project, proposal, edge_mode):
    target = project / proposal["target_node"]
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists():
        frontmatter, body = split_frontmatter(target.read_text(encoding="utf-8"))
    else:
        frontmatter = dict(proposal.get("suggested_frontmatter", {}))
        body = create_body(proposal)

    frontmatter = add_edges(frontmatter, proposal, edge_mode)
    lines = body.splitlines()
    node_update = proposal.get("node_update", {})
    lines = insert_current_state(lines, node_update.get("current_state_bullets", []))
    if edge_mode == "issue":
        lines = insert_edge_review_issues(lines, proposal)
    elif edge_mode != "none":
        lines = insert_edge_evidence(lines, proposal)
    lines = insert_change_log(lines, node_update.get("change_log_entry", {}))
    text = format_frontmatter(frontmatter) + "\n\n" + "\n".join(lines).rstrip() + "\n"
    target.write_text(text, encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description="Apply a Synapse memory proposal to Markdown nodes.")
    parser.add_argument("--project", default=".")
    parser.add_argument("--proposal", required=True)
    parser.add_argument("--edge-mode", choices=["auto", "explicit", "none", "issue"], default="auto")
    args = parser.parse_args()

    project = Path(args.project).resolve()
    proposal = json.loads(Path(args.proposal).read_text(encoding="utf-8-sig"))
    apply_proposal(project, proposal, args.edge_mode)


if __name__ == "__main__":
    main()
