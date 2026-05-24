#!/usr/bin/env python3
"""db_index.py — Index meta/*.md nodes into SQLite cache.

Reads frontmatter from Markdown nodes and writes to SQLite.
Markdown files remain the source of truth; SQLite is a derived cache.

Usage:
  python3 db_index.py --project <root> --db <memory.db> [--full] [--changed <node_id>]
"""

import argparse
import json
import os
import re
import sqlite3
import sys
from datetime import datetime, timezone


def parse_frontmatter(filepath):
    """Extract YAML frontmatter from a Markdown file."""
    try:
        with open(filepath, 'r', encoding='utf-8-sig') as f:
            content = f.read()
    except (FileNotFoundError, UnicodeDecodeError):
        return None

    fm_match = re.match(r'^---\s*\n(.*?)\n---', content, re.DOTALL)
    if not fm_match:
        return None

    fm_text = fm_match.group(1)
    data = {}
    current_key = None
    current_list = []

    for line in fm_text.split('\n'):
        kv_match = re.match(r'^(\w+):\s*(.*)', line)
        if kv_match:
            if current_key and current_list:
                data[current_key] = current_list
                current_list = []
                current_key = None

            key = kv_match.group(1)
            value = kv_match.group(2).strip().strip('"').strip("'")

            if value.startswith('[') and value.endswith(']'):
                inner = value[1:-1]
                data[key] = [v.strip().strip('"').strip("'") for v in inner.split(',') if v.strip()]
                current_key = None
            elif value == '' or value == '[]':
                current_key = key
                current_list = []
            else:
                data[key] = value
                current_key = None
        elif re.match(r'^\s+-\s+', line) and current_key:
            item = re.sub(r'^\s+-\s+', '', line).strip().strip('"').strip("'")
            if item:
                current_list.append(item)

    if current_key and current_list:
        data[current_key] = current_list

    line_count = len(content.split('\n'))
    data['_line_count'] = line_count

    return data


def index_node(conn, filepath, project_root):
    """Index a single meta/*.md node into SQLite."""
    fm = parse_frontmatter(filepath)
    if not fm or 'id' not in fm:
        return None

    node_id = fm['id']
    rel_path = os.path.relpath(filepath, project_root)

    conn.execute("""
        INSERT OR REPLACE INTO nodes (id, type, status, summary, depends_on, auto_linked,
                                       tags, aliases, updated, file_path, line_count)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """, (
        node_id,
        fm.get('type', 'unknown'),
        fm.get('status', 'unknown'),
        fm.get('summary', ''),
        json.dumps(fm.get('depends_on', []), ensure_ascii=False),
        json.dumps(fm.get('auto_linked', []), ensure_ascii=False),
        json.dumps(fm.get('tags', []), ensure_ascii=False),
        json.dumps(fm.get('aliases', []), ensure_ascii=False),
        fm.get('updated', datetime.now(timezone.utc).strftime('%Y-%m-%d')),
        rel_path,
        fm.get('_line_count', 0)
    ))

    # Index edges
    for dep in fm.get('depends_on', []):
        if dep:
            dep_id = dep.replace('meta/', '').replace('.md', '')
            conn.execute("""
                INSERT OR IGNORE INTO edges (source, target, kind)
                VALUES (?, ?, 'depends_on')
            """, (node_id, dep_id))

    for link in fm.get('auto_linked', []):
        if link:
            link_id = link.replace('meta/', '').replace('.md', '')
            conn.execute("""
                INSERT OR IGNORE INTO edges (source, target, kind)
                VALUES (?, ?, 'auto_linked')
            """, (node_id, link_id))

    return node_id


def compute_blocks(conn):
    """Compute reverse edges (blocks) from depends_on and auto_linked edges."""
    conn.execute("DELETE FROM edges WHERE kind = 'blocks'")
    conn.execute("""
        INSERT OR IGNORE INTO edges (source, target, kind)
        SELECT target, source, 'blocks'
        FROM edges
        WHERE kind IN ('depends_on', 'auto_linked')
    """)


def index_all(project_root, db_path, full=False):
    """Index all meta/*.md files into SQLite."""
    meta_dir = os.path.join(project_root, 'meta')
    if not os.path.isdir(meta_dir):
        print(f"No meta/ directory at {meta_dir}")
        return

    conn = sqlite3.connect(db_path)

    if full:
        conn.execute("DELETE FROM nodes")
        conn.execute("DELETE FROM edges")
        conn.execute("DELETE FROM cooccurrence")

    indexed = 0
    for f in sorted(os.listdir(meta_dir)):
        if not f.endswith('.md'):
            continue
        if f == 'MEMORY_MAP.md':
            continue
        filepath = os.path.join(meta_dir, f)
        node_id = index_node(conn, filepath, project_root)
        if node_id:
            indexed += 1

    compute_blocks(conn)
    conn.commit()
    conn.close()

    print(f"Indexed {indexed} nodes into {db_path}")


def main():
    parser = argparse.ArgumentParser(description="Index Synapse nodes into SQLite")
    parser.add_argument('--project', required=True, help='Project root')
    parser.add_argument('--db', required=True, help='Path to memory.db')
    parser.add_argument('--full', action='store_true', help='Full rebuild')
    parser.add_argument('--changed', help='Single node ID to re-index')
    args = parser.parse_args()

    if args.changed:
        meta_dir = os.path.join(args.project, 'meta')
        filepath = os.path.join(meta_dir, f"{args.changed}.md")
        if not os.path.exists(filepath):
            print(f"Node not found: {args.changed}", file=sys.stderr)
            sys.exit(1)
        conn = sqlite3.connect(args.db)
        node_id = index_node(conn, filepath, args.project)
        if node_id:
            compute_blocks(conn)
            conn.commit()
            print(f"Re-indexed: {node_id}")
        conn.close()
    else:
        index_all(args.project, args.db, full=args.full)


if __name__ == '__main__':
    main()
