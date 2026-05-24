#!/usr/bin/env python3
"""auto_observe.py — Extract memory-worthy signals from a coding session.

Reads git diff and an optional conversation transcript, outputs JSON proposals
that synapse_note.sh can ingest directly.

Usage:
  python3 auto_observe.py --project <root> [--transcript <file>] [--min-confidence 40]
  python3 auto_observe.py --project <root> --changed-file <path>
"""

import argparse
import json
import os
import re
import subprocess
import sys
from datetime import datetime


def get_git_diff(project_root):
    """Get staged + unstaged diff for source files."""
    try:
        result = subprocess.run(
            ['git', '-C', project_root, 'diff', 'HEAD', '--', 'src/', 'app/', 'lib/',
             'prisma/', 'migrations/', 'routes/', 'handlers/', 'controllers/',
             'components/', 'pages/', 'views/'],
            capture_output=True, text=True, timeout=5
        )
        return result.stdout
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return ''


def get_changed_files(project_root):
    """Get list of changed source files from git."""
    try:
        result = subprocess.run(
            ['git', '-C', project_root, 'diff', '--name-only', 'HEAD', '--diff-filter=ACMR',
             'src/', 'app/', 'lib/', 'prisma/'],
            capture_output=True, text=True, timeout=5
        )
        return [f.strip() for f in result.stdout.split('\n') if f.strip()]
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return []


def get_new_files(project_root):
    """Get untracked source files."""
    try:
        result = subprocess.run(
            ['git', '-C', project_root, 'ls-files', '--others', '--exclude-standard',
             'src/', 'app/', 'lib/', 'prisma/'],
            capture_output=True, text=True, timeout=5
        )
        return [f.strip() for f in result.stdout.split('\n') if f.strip()]
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return []


# ─── File → Node mapping heuristics ───────────────────────────────────

NODE_MAP_RULES = [
    (r'prisma/schema\.prisma', '__all_db__'),
    (r'(?:src|app)/routes/(\w+)\.(?:py|ts|js|go)', lambda m: f'api_{m.group(1)}-routes'),
    (r'(?:src|app)/controllers/(\w+)\.(?:py|ts|js|go)', lambda m: f'api_{m.group(1)}-routes'),
    (r'app/api/(\w+)/route\.ts', lambda m: f'api_{m.group(1)}-routes'),
    (r'(?:src|app)/handlers/(\w+)\.(?:py|ts|js|go)', lambda m: f'api_{m.group(1)}-routes'),
    (r'(?:src|app)/pages/(\w+)\.(?:tsx|jsx|vue|svelte)', lambda m: f'ui_{m.group(1).lower()}-page'),
    (r'app/(\w+)/page\.tsx', lambda m: f'ui_{m.group(1).lower()}-page'),
    (r'(?:src|app)/views/(\w+)\.(?:vue|svelte)', lambda m: f'ui_{m.group(1).lower()}-page'),
    (r'(?:src|app)/models/(\w+)\.py', lambda m: f'mod_{m.group(1).lower()}'),
    (r'(?:src|app)/models/(\w+)\.ts', lambda m: f'mod_{m.group(1).lower()}'),
    (r'(?:src|app)/services/(\w+)\.(?:py|ts|go)', lambda m: f'mod_{m.group(1).lower()}'),
    (r'(?:src|app)/middleware/(\w+)\.(?:py|ts|go)', lambda m: f'mod_{m.group(1).lower()}'),
    (r'(?:src|app)/auth/', '__mod_auth__'),
    (r'(?:src|app)/payment/', '__mod_payment__'),
    (r'(?:src|app)/components/', 'mod_design-system'),
    (r'Dockerfile', 'dep_container-config'),
    (r'docker-compose', 'dep_container-config'),
    (r'k8s/', 'dep_k8s'),
    (r'deploy/', 'dep_k8s'),
    (r'\.env\.', 'dep_container-config'),
]


def infer_target_nodes(changed_files):
    """Map changed source files to likely meta/ node IDs."""
    nodes = set()
    details = {}
    for f in changed_files:
        matched = False
        for pattern, target in NODE_MAP_RULES:
            m = re.search(pattern, f)
            if m:
                if callable(target):
                    node_id = target(m)
                else:
                    node_id = target
                if node_id in ('__all_db__', '__mod_auth__', '__mod_payment__'):
                    node_id = node_id.replace('__', '')
                nodes.add(node_id)
                details[f] = node_id
                matched = True
                break
        if not matched:
            parts = f.replace('\\', '/').split('/')
            if len(parts) >= 2:
                candidate = parts[-2]
                if candidate not in ('src', 'app', 'lib', '.', '..'):
                    node_id = f'mod_{candidate}'
                    nodes.add(node_id)
                    details[f] = node_id
    return list(nodes), details


# ─── Conversation signal extraction ───────────────────────────────────

DECISION_PATTERNS = [
    (re.compile(r'(?:决定|就用|选|定下来|定了|确定|确定了|最终方案|确认用)\S{0,20}?([一-鿿\w]{2,40})'), 'key_decision', 85),
    (re.compile(r"(?:we'll\s+(?:use|go\s+with)|decided\s+on|let's\s+(?:use|do)|going\s+with)\s+([A-Za-z][\w\s]{2,50})"), 'key_decision', 85),
]

BLOCKED_PATTERNS = [
    (re.compile(r'(?:还差|还没做|没做|缺|缺少|待确认|待定|blocked|pending|TODO|FIXME)\S{0,20}?([一-鿿\w]{2,60})'), 'open_issue', 70),
    (re.compile(r"(?:still\s+need|haven't|not\s+yet|remaining|needs?\s+to\s+be)\s+([\w\s]{3,50})"), 'open_issue', 70),
]

PROGRESS_PATTERNS = [
    (re.compile(r'(?:接好了|完成了|做好了|写好了|修了|修好了|实现了|新增了|加了|改了|更新了)\s*([一-鿿\w\s]{3,60})'), 'change_log', 80),
    (re.compile(r"(?:added|implemented|fixed|built|created|finished|completed|wired\s+up)\s+([\w\s]{3,60})"), 'change_log', 80),
]


def extract_conversation_signals(transcript_text):
    """Scan conversation text for decision/blocked/progress signals."""
    proposals = []
    for regex, change_type, base_confidence in DECISION_PATTERNS:
        for m in regex.finditer(transcript_text):
            content = m.group(1).strip()
            if len(content) < 2:
                continue
            proposals.append({
                'change_type': change_type,
                'content': f'决定: {content}',
                'confidence': base_confidence,
                'evidence': f'对话匹配: "{m.group(0)[:80]}"',
                'source': 'conversation'
            })
    for regex, change_type, base_confidence in BLOCKED_PATTERNS:
        for m in regex.finditer(transcript_text):
            content = m.group(1).strip()
            if len(content) < 2:
                continue
            proposals.append({
                'change_type': change_type,
                'content': f'待完成: {content}',
                'confidence': base_confidence,
                'evidence': f'对话匹配: "{m.group(0)[:80]}"',
                'source': 'conversation'
            })
    for regex, change_type, base_confidence in PROGRESS_PATTERNS:
        for m in regex.finditer(transcript_text):
            content = m.group(1).strip()
            if len(content) < 2:
                continue
            proposals.append({
                'change_type': change_type,
                'content': content,
                'confidence': base_confidence,
                'evidence': f'对话匹配: "{m.group(0)[:80]}"',
                'source': 'conversation'
            })
    return proposals


# ─── Diff analysis ────────────────────────────────────────────────────

def extract_diff_signals(diff_text, changed_files, node_map):
    """Analyze git diff for structural changes worth recording."""
    proposals = []
    for f in changed_files:
        if f not in node_map:
            continue
        target = node_map[f]
        proposals.append({
            'change_type': 'change_log',
            'content': f'源码变更: {f}',
            'confidence': 90,
            'evidence': f'git 文件变更: {f}',
            'source': 'git_diff',
            'target_node': target
        })

    route_additions = re.findall(
        r'^\+\s*(?:@(?:router|app|bp)\.(?:get|post|put|delete|patch)|router\.(?:get|post|put|delete|patch)|app\.(?:get|post|put|delete|patch))\s*\([\'"]([^\'"]+)[\'"]',
        diff_text, re.MULTILINE
    )
    for path in route_additions:
        proposals.append({
            'change_type': 'connection_point',
            'content': f'新增 API 端点: {path}',
            'confidence': 95,
            'evidence': f'git diff 检测到新增路由: {path}',
            'source': 'git_diff'
        })

    if re.search(r'prisma/schema\.prisma', diff_text):
        new_fields = re.findall(r'^\+\s{2,}(\w+)\s+(\w+(?:\[\])?)', diff_text, re.MULTILINE)
        new_models = re.findall(r'^\+\s*model\s+(\w+)', diff_text, re.MULTILINE)
        if new_fields:
            proposals.append({
                'change_type': 'connection_point',
                'content': f'Schema 字段变更: {", ".join(f"{n}({t})" for n, t in new_fields[:5])}',
                'confidence': 95,
                'evidence': 'git diff Prisma schema 字段变更',
                'source': 'git_diff',
                'target_node': 'all_db_'
            })
        if new_models:
            for model in new_models:
                proposals.append({
                    'change_type': 'change_log',
                    'content': f'新增数据库表: {model}',
                    'confidence': 95,
                    'evidence': f'git diff Prisma 新增 model {model}',
                    'source': 'git_diff',
                    'target_node': f'db_{model.lower()}'
                })

    return proposals


# ─── Deduplication & merge ────────────────────────────────────────────

def merge_proposals(proposals):
    """Merge duplicate proposals by keeping highest confidence."""
    seen = {}
    for p in proposals:
        key = (p.get('target_node', ''), p['change_type'], p['content'][:80])
        if key in seen:
            if p['confidence'] > seen[key]['confidence']:
                seen[key] = p
        else:
            seen[key] = p
    return sorted(seen.values(), key=lambda x: x['confidence'], reverse=True)


# ─── Main ─────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description='Auto-observe session signals')
    parser.add_argument('--project', required=True, help='Project root')
    parser.add_argument('--transcript', help='Conversation transcript file')
    parser.add_argument('--min-confidence', type=int, default=40,
                       help='Minimum confidence to include (default: 40)')
    parser.add_argument('--changed-file', help='Single changed file (hook mode)')
    parser.add_argument('--output', help='Output JSON file (default: stdout)')
    args = parser.parse_args()

    proposals = []

    diff_text = get_git_diff(args.project)
    if diff_text:
        changed = get_changed_files(args.project) + get_new_files(args.project)
        if changed:
            target_nodes, node_map = infer_target_nodes(changed)
            diff_proposals = extract_diff_signals(diff_text, changed, node_map)
            proposals.extend(diff_proposals)

    if args.changed_file:
        target_nodes, node_map = infer_target_nodes([args.changed_file])
        for node_id in target_nodes:
            proposals.append({
                'change_type': 'change_log',
                'content': f'源码变更: {args.changed_file}',
                'confidence': 90,
                'evidence': f'PostToolUse hook: {args.changed_file}',
                'source': 'hook',
                'target_node': node_id.replace('__', '')
            })

    transcript_text = ''
    if args.transcript and os.path.exists(args.transcript):
        try:
            with open(args.transcript, 'r', encoding='utf-8') as f:
                transcript_text = f.read()
        except UnicodeDecodeError:
            try:
                with open(args.transcript, 'r', encoding='utf-8-sig') as f:
                    transcript_text = f.read()
            except Exception:
                pass
        conv_proposals = extract_conversation_signals(transcript_text)
        proposals.extend(conv_proposals)

    proposals = merge_proposals(proposals)
    proposals = [p for p in proposals if p['confidence'] >= args.min_confidence]

    today = datetime.now().strftime('%Y-%m-%d')
    for p in proposals:
        p['date'] = today

    result = {
        'date': today,
        'count': len(proposals),
        'proposals': proposals
    }

    if args.output:
        os.makedirs(os.path.dirname(args.output) or '.', exist_ok=True)
        with open(args.output, 'w', encoding='utf-8') as f:
            json.dump(result, f, indent=2, ensure_ascii=False)
        print(f"Auto-observed {len(proposals)} signal(s) -> {args.output}")
    else:
        print(json.dumps(result, indent=2, ensure_ascii=False))


if __name__ == '__main__':
    main()
