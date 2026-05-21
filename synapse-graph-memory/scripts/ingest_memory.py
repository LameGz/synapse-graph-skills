#!/usr/bin/env python3
import argparse
import json
import re
from datetime import date
from pathlib import Path

API_RE = re.compile(r"\b(GET|POST|PUT|DELETE|PATCH)\s+(/[A-Za-z0-9_/{}/:-]+)")
FIELD_RE = re.compile(r"\b([a-zA-Z_][a-zA-Z0-9_]*(?:_token|_id|_in|_at|_url|_key)?)\b")
COMPONENT_RE = re.compile(r"\b([A-Z][A-Za-z0-9]+(?:Card|Feed|Panel|Page|View|Form|Button|Modal|List|Table))\b")
ROUTE_RE = re.compile(r"(?<![A-Za-z0-9_])(/[A-Za-z0-9_/-]+)")

STOP_FIELDS = {"GET", "POST", "PUT", "DELETE", "PATCH", "Login", "None"}
TOPIC_ALIASES = {
    "login": ["登录", "login", "signin", "auth"],
    "auth": ["鉴权", "认证", "auth", "token", "jwt"],
    "dashboard": ["仪表盘", "dashboard"],
    "checkout": ["结账", "checkout"],
    "payment": ["支付", "payment"],
    "ui": ["UI", "组件", "页面", "前端"],
}


def read_frontmatter(path: Path):
    text = path.read_text(encoding="utf-8")
    if not text.startswith("---"):
        return {}, text
    parts = text.split("---", 2)
    if len(parts) < 3:
        return {}, text
    fm_text, body = parts[1], parts[2]
    fm = {}
    current = None
    for line in fm_text.splitlines():
        if not line.strip():
            continue
        if re.match(r"^[A-Za-z_]+:", line):
            key, value = line.split(":", 1)
            key = key.strip()
            value = value.strip()
            current = key
            if value.startswith("[") and value.endswith("]"):
                fm[key] = [v.strip().strip('"\'') for v in value[1:-1].split(",") if v.strip()]
            elif value:
                fm[key] = value.strip('"')
            else:
                fm[key] = []
        elif current and line.strip().startswith("-"):
            fm.setdefault(current, [])
            fm[current].append(line.strip()[1:].strip().strip('"'))
    return fm, body


def load_nodes(project: Path):
    nodes = []
    meta = project / "meta"
    if not meta.exists():
        return nodes
    for path in sorted(meta.glob("*.md")):
        fm, body = read_frontmatter(path)
        nodes.append({"path": path.relative_to(project).as_posix(), "frontmatter": fm, "body": body})
    return nodes


def extract(text: str):
    endpoints = [f"{m.group(1)} {m.group(2)}" for m in API_RE.finditer(text)]
    routes = sorted(set(m.group(1) for m in ROUTE_RE.finditer(text) if not any(ep.endswith(m.group(1)) for ep in endpoints)))
    fields = sorted(set(m.group(1) for m in FIELD_RE.finditer(text) if m.group(1) not in STOP_FIELDS and ("_" in m.group(1) or m.group(1).islower())))
    components = sorted(set(m.group(1) for m in COMPONENT_RE.finditer(text)))
    topics = []
    lower = text.lower()
    for topic, aliases in TOPIC_ALIASES.items():
        if any(alias.lower() in lower for alias in aliases):
            topics.append(topic)
    return {"api_endpoints": endpoints, "routes": routes, "fields": fields, "components": components, "topics": sorted(set(topics))}


def choose_target(nodes, extracted):
    scores = []
    terms = set(extracted["topics"] + extracted["api_endpoints"] + extracted["routes"] + extracted["components"])
    for node in nodes:
        fm = node["frontmatter"]
        haystack = " ".join([
            str(fm.get("id", "")),
            " ".join(fm.get("tags", []) if isinstance(fm.get("tags"), list) else []),
            " ".join(fm.get("aliases", []) if isinstance(fm.get("aliases"), list) else []),
            node["body"],
        ]).lower()
        score = 0
        for term in terms:
            if term and term.lower() in haystack:
                score += 3 if term.startswith(("GET ", "POST ", "PUT ", "DELETE ", "PATCH ")) else 1
        node_id = str(fm.get("id", ""))
        node_type = str(fm.get("type", ""))
        if node_id.startswith("feat_") or node_type == "feature":
            score += 5
        scores.append((score, node["path"]))
    scores.sort(reverse=True)
    if scores and scores[0][0] > 0:
        return "update_node", scores[0][1]
    topic = extracted["topics"][0] if extracted["topics"] else "project-note"
    return "create_node", f"meta/feat_{topic}.md"


def edge_candidates(nodes, target_path, extracted):
    candidates = []
    target_endpoints = set(extracted["api_endpoints"])
    target_terms = set(extracted["topics"] + extracted["fields"] + extracted["components"])
    for node in nodes:
        if node["path"] == target_path:
            continue
        evidence = []
        score = 0
        for ep in target_endpoints:
            if ep in node["body"]:
                score += 80
                evidence.append(f"exact endpoint match: {ep}")
        fm = node["frontmatter"]
        tags = set(fm.get("tags", []) if isinstance(fm.get("tags"), list) else [])
        aliases = set(fm.get("aliases", []) if isinstance(fm.get("aliases"), list) else [])
        overlap = sorted(target_terms.intersection(tags.union(aliases)))
        if overlap:
            score += min(len(overlap) * 10, 20)
            evidence.append("tag/alias overlap: " + ", ".join(overlap))
        if score >= 30:
            candidates.append({
                "from": target_path,
                "to": node["path"],
                "confidence": round(score / 10, 1),
                "evidence": evidence,
                "apply_to": "auto_linked" if score >= 80 else "review",
            })
    candidates.sort(key=lambda item: item["confidence"], reverse=True)
    return candidates


def suggested_frontmatter(target_path, extracted):
    node_id = Path(target_path).stem
    node_type = "feature" if node_id.startswith("feat_") else "module"
    tags = extracted["topics"] or [node_id.replace("feat_", "").replace("mod_", "")]
    return {
        "id": node_id,
        "type": node_type,
        "status": "in-progress",
        "updated": date.today().isoformat(),
        "summary": f"Natural-language memory node for {node_id}.",
        "depends_on": [],
        "auto_linked": [],
        "tags": tags,
        "aliases": [],
    }


def main():
    parser = argparse.ArgumentParser(description="Convert natural-language project memory into a Synapse proposal.")
    parser.add_argument("--project", default=".")
    parser.add_argument("--text", required=True)
    args = parser.parse_args()

    project = Path(args.project).resolve()
    nodes = load_nodes(project)
    extracted = extract(args.text)
    action, target = choose_target(nodes, extracted)
    proposal = {
        "version": 1,
        "action": action,
        "target_node": target,
        "raw_text": args.text,
        "extracted": extracted,
        "suggested_frontmatter": suggested_frontmatter(target, extracted),
        "node_update": {
            "current_state_bullets": [args.text],
            "change_log_entry": {
                "date": date.today().isoformat(),
                "context": "Natural-language memory ingestion",
                "change": args.text,
                "impact": "Updates project memory graph context",
                "affected": target,
            },
        },
        "edge_candidates": edge_candidates(nodes, target, extracted),
    }
    print(json.dumps(proposal, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
