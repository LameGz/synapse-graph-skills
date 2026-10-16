#!/usr/bin/env python3
"""Session proposal transport: preserve targets; conversation signals require review."""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import uuid
from pathlib import Path

import memory_inbox


def partition(proposals, project, threshold=70):
    high, low = [], []
    for proposal in proposals:
        target = str(proposal.get('target_node') or 'unknown')
        try:
            known = memory_inbox.target_path(project, target).is_file()
        except SystemExit:
            known = False
        trusted = proposal.get('source') in ('git_diff', 'hook')
        (high if trusted and known and proposal.get('confidence', 0) >= threshold else low).append(proposal)
    return high, low


def write_partitions(directory, proposals, project, session_id):
    directory.mkdir(parents=True, exist_ok=True)
    high, low = partition(proposals, project)
    for name, values in [('auto_apply.json', high), ('needs_review.json', low)]:
        target = directory / name
        temporary = directory / (name + '.tmp')
        temporary.write_text(json.dumps({'session_id': session_id, 'proposals': values}, ensure_ascii=False, indent=2), encoding='utf-8')
        os.replace(temporary, target)
    return high, low


def apply_proposals(project, proposals):
    high, low = partition(proposals, project)
    applied = 0
    for proposal in high:
        # Apply the original structured target; do not turn it back into an NL query.
        if memory_inbox.apply_to_node(project, proposal):
            applied += 1
        else:
            low.append(proposal)
    for proposal in low:
        memory_inbox.add_item(project, proposal)
    return applied, len(low)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project', required=True)
    args = parser.parse_args()
    project = Path(args.project).resolve()
    raw = sys.stdin.read() if not sys.stdin.isatty() else ''
    try:
        payload = json.loads(raw) if raw.strip() else {}
    except ValueError:
        payload = {}
    if not isinstance(payload, dict):
        payload = {}
    scripts = Path(__file__).resolve().parent
    argv = [sys.executable, '-X', 'utf8', str(scripts / 'auto_observe.py'), '--project', str(project), '--min-confidence', '40']
    transcript = payload.get('transcript_path')
    if isinstance(transcript, str) and Path(transcript).is_file():
        argv += ['--transcript', transcript, '--transcript-user-only']
    result = subprocess.run(argv, check=True, capture_output=True, text=True, encoding='utf-8')
    proposals = json.loads(result.stdout).get('proposals', [])
    # One directory per invocation prevents overlapping sessions consuming each other's files.
    directory = project / '.claude/.synapse_cache/auto-proposals' / uuid.uuid4().hex
    write_partitions(directory, proposals, project, str(payload.get('session_id') or 'manual'))
    applied, queued = apply_proposals(project, proposals)
    if applied:
        subprocess.run([sys.executable, '-X', 'utf8', str(scripts / 'generate_memory_map.py'), '--project', str(project), '--full'], check=True)
    print(f'Synapse session memory: {applied} applied, {queued} queued for review')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
