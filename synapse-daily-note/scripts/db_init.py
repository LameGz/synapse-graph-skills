#!/usr/bin/env python3
"""db_init.py — Initialize SQLite cache database for Synapse memory graph.

Usage:
  python3 db_init.py --db <path-to-memory.db> [--force]
"""

import argparse
import os
import sqlite3
import sys


SCHEMA = """
CREATE TABLE IF NOT EXISTS nodes (
    id TEXT PRIMARY KEY,
    type TEXT NOT NULL,
    status TEXT NOT NULL,
    summary TEXT NOT NULL,
    depends_on TEXT NOT NULL DEFAULT '[]',
    auto_linked TEXT NOT NULL DEFAULT '[]',
    tags TEXT NOT NULL DEFAULT '[]',
    aliases TEXT NOT NULL DEFAULT '[]',
    updated TEXT NOT NULL,
    file_path TEXT NOT NULL,
    line_count INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS edges (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    source TEXT NOT NULL,
    target TEXT NOT NULL,
    kind TEXT NOT NULL CHECK(kind IN ('depends_on', 'auto_linked', 'blocks')),
    UNIQUE(source, target, kind)
);

CREATE TABLE IF NOT EXISTS cooccurrence (
    node_a TEXT NOT NULL,
    node_b TEXT NOT NULL,
    touch_count INTEGER NOT NULL DEFAULT 1,
    last_touch TEXT NOT NULL,
    PRIMARY KEY (node_a, node_b)
);

CREATE TABLE IF NOT EXISTS staleness (
    node_id TEXT PRIMARY KEY,
    stale_since TEXT NOT NULL,
    reason TEXT NOT NULL,
    affected_refs TEXT NOT NULL DEFAULT '[]'
);

CREATE VIRTUAL TABLE IF NOT EXISTS nodes_fts USING fts5(
    id, summary, tags, aliases,
    content='nodes', content_rowid='rowid'
);

-- Triggers to keep FTS in sync
CREATE TRIGGER IF NOT EXISTS nodes_ai AFTER INSERT ON nodes BEGIN
    INSERT INTO nodes_fts(rowid, id, summary, tags, aliases)
    VALUES (new.rowid, new.id, new.summary, new.tags, new.aliases);
END;

CREATE TRIGGER IF NOT EXISTS nodes_ad AFTER DELETE ON nodes BEGIN
    INSERT INTO nodes_fts(nodes_fts, rowid, id, summary, tags, aliases)
    VALUES ('delete', old.rowid, old.id, old.summary, old.tags, old.aliases);
END;

CREATE TRIGGER IF NOT EXISTS nodes_au AFTER UPDATE ON nodes BEGIN
    INSERT INTO nodes_fts(nodes_fts, rowid, id, summary, tags, aliases)
    VALUES ('delete', old.rowid, old.id, old.summary, old.tags, old.aliases);
    INSERT INTO nodes_fts(rowid, id, summary, tags, aliases)
    VALUES (new.rowid, new.id, new.summary, new.tags, new.aliases);
END;

CREATE INDEX IF NOT EXISTS idx_edges_source ON edges(source);
CREATE INDEX IF NOT EXISTS idx_edges_target ON edges(target);
CREATE INDEX IF NOT EXISTS idx_edges_kind ON edges(kind);
CREATE INDEX IF NOT EXISTS idx_cooccurrence_touch ON cooccurrence(touch_count DESC);
CREATE INDEX IF NOT EXISTS idx_staleness_node ON staleness(node_id);
"""


def init_db(db_path, force=False):
    if os.path.exists(db_path):
        if force:
            os.remove(db_path)
        else:
            print(f"Database already exists: {db_path}")
            print("Use --force to overwrite")
            return False

    os.makedirs(os.path.dirname(db_path), exist_ok=True)

    conn = sqlite3.connect(db_path)
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA foreign_keys=ON")
    conn.executescript(SCHEMA)
    conn.commit()
    conn.close()

    print(f"Database initialized: {db_path}")
    return True


def main():
    parser = argparse.ArgumentParser(description="Initialize Synapse SQLite cache")
    parser.add_argument('--db', required=True, help='Path to memory.db')
    parser.add_argument('--force', action='store_true', help='Overwrite existing DB')
    args = parser.parse_args()

    if init_db(args.db, args.force):
        sys.exit(0)
    else:
        sys.exit(1)


if __name__ == '__main__':
    main()
