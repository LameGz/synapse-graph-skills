#!/usr/bin/env python3
"""prefetch_context.py — Seamless memory prefetch (the "read" side of v2).

Designed for a UserPromptSubmit-style hook: receives the user's prompt,
scores memory nodes against it, and prints a compact context block to
stdout. Hosts that add hook stdout to the conversation get relevant
memory injected without the user ever asking for it.

Usage:
  # Claude Code UserPromptSubmit hook (reads {"prompt": ...} JSON on stdin):
  python scripts/prefetch_context.py --project .

  # Generic hosts / wrappers:
  python scripts/prefetch_context.py --project . --prompt "支付做得怎么样了？"

Output contract: always exit 0; print nothing when nothing matches, so
hosts without context injection are unaffected.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

# Rough token budget for the injected block (CJK chars ≈ 1 token each;
# ASCII words ≈ 1.3 tokens). Kept deliberately small: this runs every turn.
DEFAULT_BUDGET_TOKENS = 450
MAX_NODES = 5
STOP_TOKENS = {
    "the", "a", "an", "and", "or", "of", "to", "in", "on", "for", "is",
    "are", "was", "be", "how", "what", "which", "does", "do", "did",
    "的", "了", "吗", "呢", "是", "在", "和", "与", "怎么", "如何",
    "哪些", "什么", "这个", "那个", "还有", "有没有", "一下", "请",
}


def load_map(project: Path) -> dict:
    path = project / "MEMORY_MAP.json"
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8-sig"))
    except (json.JSONDecodeError, UnicodeDecodeError, OSError):
        return {}


def tokenize(text: str) -> list[str]:
    """Split a mixed Chinese/ASCII prompt into matchable tokens."""
    tokens = []
    for raw in re.split(r"[\s,，。?!？;；:：/\\()（）\[\]{}\"']+", text.lower()):
        raw = raw.strip()
        if not raw or raw in STOP_TOKENS:
            continue
        tokens.append(raw)
        # CJK: also add 2-gram slices so partial names still match tags like 支付
        if re.search(r"[一-鿿]", raw) and len(raw) > 2:
            tokens.extend(raw[i:i + 2] for i in range(len(raw) - 1))
    seen: set[str] = set()
    return [t for t in tokens if not (t in seen or seen.add(t))]


TOPIC_ALIASES = {
    # Chinese prompt tokens → canonical English tags/ids used in memory nodes.
    # Mirrors ingest_memory.TOPIC_ALIASES so retrieval and writing agree.
    "登录": ["login", "signin"],
    "鉴权": ["auth"],
    "认证": ["auth", "token", "jwt"],
    "令牌": ["token", "jwt"],
    "支付": ["payment"],
    "结账": ["checkout"],
    "仪表盘": ["dashboard"],
    "组件": ["ui", "design"],
    "页面": ["ui", "page"],
    "前端": ["ui", "frontend"],
    "数据库": ["db", "database"],
    "部署": ["deploy"],
}


def expand_aliases(tokens: list[str]) -> list[str]:
    expanded = list(tokens)
    for token in tokens:
        expanded.extend(TOPIC_ALIASES.get(token, []))
    return expanded


def fts5_scores(db_path: Path, tokens: list[str]) -> dict[str, float]:
    """Optional BM25 boost from the SQLite FTS5 cache (absent db is fine)."""
    if not db_path.exists():
        return {}
    try:
        import sqlite3

        match = " OR ".join(
            '"%s"' % t.replace('"', '""') for t in tokens[:12] if t
        )
        if not match:
            return {}
        conn = sqlite3.connect(str(db_path))
        conn.row_factory = sqlite3.Row
        rows = conn.execute(
            "SELECT id, bm25(nodes_fts) AS rank FROM nodes_fts "
            "WHERE nodes_fts MATCH ? ORDER BY rank LIMIT 10",
            (match,),
        ).fetchall()
        conn.close()
        return {row["id"]: -float(row["rank"]) for row in rows}
    except Exception:
        return {}


def score_nodes(data: dict, tokens: list[str], fts: dict[str, float]) -> list[dict]:
    scores: dict[str, float] = {}
    for node in data.get("nodes", []):
        if not isinstance(node, dict) or not node.get("id"):
            continue
        nid = str(node["id"])
        score = 0.0
        tag_alias = {str(v).lower() for v in node.get("tags", []) + node.get("aliases", [])}
        haystacks = (
            nid.lower(),
            str(node.get("summary", "")).lower(),
            tag_alias,
            {str(k).lower() for k in node.get("keywords", [])},
        )
        for token in tokens:
            if token in tag_alias:
                score += 5.0
            elif token in nid.lower():
                score += 4.0
            elif token in {k for k in haystacks[3]}:
                score += 2.0
            elif token in haystacks[1]:
                score += 1.0
        score += min(fts.get(nid, 0.0), 6.0)  # BM25 boost, bounded
        if score > 0:
            scores[nid] = score
    ranked = sorted(scores.items(), key=lambda kv: kv[1], reverse=True)[:MAX_NODES]
    by_id = {str(n.get("id")): n for n in data.get("nodes", []) if isinstance(n, dict)}
    matched = []
    for nid, s in ranked:
        if nid in by_id:
            node = dict(by_id[nid])
            node["_score"] = s
            matched.append(node)
    return matched


def render(nodes: list[dict], budget: int) -> str:
    lines = ["[synapse] Relevant memory nodes (auto-prefetched; read MAP or node files for detail):"]
    used = 25
    emitted = 0
    for node in nodes:
        issues = len(node.get("open_issues", []) or [])
        deps = node.get("depends_on", []) or []
        line = f"- {node['id']} ({node.get('status', '?')}"
        if node.get("updated"):
            line += f", updated {node['updated']}"
        line += f", ~{node.get('tokens', '?')} tok"
        if issues:
            line += f", {issues} open issue(s)"
        line += f") {node.get('summary', '')}".rstrip()
        if deps:
            line += f" | depends_on: {', '.join(str(d) for d in deps[:3])}"
        cost = len(line) // 3 + 1  # crude CJK-aware token estimate
        if emitted and used + cost > budget:
            break
        lines.append(line)
        used += cost
        emitted += 1
    if emitted == 0:
        return ""
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="Prefetch relevant Synapse memory for a prompt.")
    parser.add_argument("--project", default=".")
    parser.add_argument("--prompt", help="User prompt (default: read hook JSON or plain text from stdin)")
    parser.add_argument("--budget-tokens", type=int, default=DEFAULT_BUDGET_TOKENS)
    parser.add_argument("--db", help="Optional SQLite FTS5 cache path (default: <project>/.synapse/cache/memory.db)")
    args = parser.parse_args()

    prompt = args.prompt
    if not prompt and not sys.stdin.isatty():
        raw = sys.stdin.read().strip()
        if raw:
            try:
                payload = json.loads(raw)
                prompt = str(payload.get("prompt", ""))
            except json.JSONDecodeError:
                prompt = raw  # plain text piped in

    project = Path(args.project).resolve()
    if not prompt or not (project / "MEMORY_MAP.json").exists():
        return 0

    tokens = tokenize(prompt)
    if not tokens:
        return 0
    tokens = expand_aliases(tokens)

    db_path = Path(args.db) if args.db else project / ".synapse" / "cache" / "memory.db"
    fts = fts5_scores(db_path, tokens)
    nodes = score_nodes(load_map(project), tokens, fts)
    if not nodes:
        return 0

    text = render(nodes, args.budget_tokens)
    if text:
        print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
