#!/usr/bin/env python3
import importlib.util
import json
import subprocess
import sys
import tempfile
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = REPO_ROOT / "synapse-graph-memory" / "scripts" / "memory_inbox.py"


def load_module():
    spec = importlib.util.spec_from_file_location("memory_inbox", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_add_deduplicates_and_merges_evidence():
    inbox = load_module()
    with tempfile.TemporaryDirectory() as tmp:
        project = Path(tmp)
        first = {
            "target_node": "mod_auth",
            "change_type": "open_issue",
            "content": " Need to verify refresh token expiry. ",
            "confidence": 62,
            "source": "conversation",
            "evidence": "user said not yet",
        }
        second = {
            "target_node": "mod_auth",
            "change_type": "open_issue",
            "content": "need to verify refresh token expiry",
            "confidence": 71,
            "source": "git_diff",
            "evidence": "diff touched auth/routes.ts",
        }

        first_result = inbox.add_item(project, first)
        second_result = inbox.add_item(project, second)

        data = json.loads((project / ".synapse" / "inbox.json").read_text(encoding="utf-8"))
        assert first_result == "queued"
        assert second_result == "duplicate"
        assert data["version"] == 1
        assert len(data["items"]) == 1
        item = data["items"][0]
        assert item["confidence"] == 71
        assert item["evidence"] == ["user said not yet", "diff touched auth/routes.ts"]


def test_apply_item_writes_node_and_removes_from_inbox():
    inbox = load_module()
    with tempfile.TemporaryDirectory() as tmp:
        project = Path(tmp)
        (project / "meta").mkdir()
        node = project / "meta" / "mod_auth.md"
        node.write_text(
            """---
id: mod_auth
type: module
status: in-progress
updated: 2026-05-01
summary: Auth module.
depends_on: []
tags: [auth]
---

# Auth

## Current State
- Existing state

## Key Decisions
None.

## Cross-Module Connection Points
None.

## Open Issues
None.

## Change Log
None.
""",
            encoding="utf-8",
        )
        inbox.add_item(
            project,
            {
                "target_node": "mod_auth",
                "change_type": "open_issue",
                "content": "Verify refresh token expiry.",
                "confidence": 66,
                "source": "conversation",
                "evidence": "manual test",
            },
        )

        applied = inbox.apply_items(project, limit=1)

        assert applied == 1
        updated = node.read_text(encoding="utf-8")
        assert "- Verify refresh token expiry." in updated
        data = json.loads((project / ".synapse" / "inbox.json").read_text(encoding="utf-8"))
        assert data["items"] == []


def test_help_includes_examples():
    result = subprocess.run(
        [sys.executable, str(SCRIPT), "--help"],
        capture_output=True,
        text=True,
        check=True,
    )
    assert "Examples:" in result.stdout
    assert "memory_inbox.py list" in result.stdout


if __name__ == "__main__":
    test_add_deduplicates_and_merges_evidence()
    test_apply_item_writes_node_and_removes_from_inbox()
    test_help_includes_examples()
    print("memory_inbox: OK")
