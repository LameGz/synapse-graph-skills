#!/usr/bin/env python3
import subprocess
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = REPO_ROOT / "synapse-graph-memory" / "scripts" / "project_resume.py"
PROJECT = REPO_ROOT / "synapse-graph-memory" / "examples" / "solo-saas"


def test_resume_prints_project_context():
    result = subprocess.run(
        [sys.executable, str(SCRIPT), "--project", str(PROJECT)],
        capture_output=True,
        text=True,
        check=True,
    )
    output = result.stdout
    assert "Synapse Project Resume" in output
    assert "Current Focus" in output
    assert "Recent Changes" in output
    assert "Open Issues" in output
    assert "Suggested Next Actions" in output
    assert "feat_login" in output


def test_resume_json_mode():
    result = subprocess.run(
        [sys.executable, str(SCRIPT), "--project", str(PROJECT), "--focus", "payment", "--json"],
        capture_output=True,
        text=True,
        check=True,
    )
    output = result.stdout
    assert '"focus": "payment"' in output
    assert '"current_focus"' in output
    assert '"recent_changes"' in output


def test_help_includes_examples():
    result = subprocess.run(
        [sys.executable, str(SCRIPT), "--help"],
        capture_output=True,
        text=True,
        check=True,
    )
    assert "Examples:" in result.stdout
    assert "project_resume.py --project" in result.stdout


if __name__ == "__main__":
    test_resume_prints_project_context()
    test_resume_json_mode()
    test_help_includes_examples()
    print("project_resume: OK")
