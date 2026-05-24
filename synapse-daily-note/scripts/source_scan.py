#!/usr/bin/env python3
"""source_scan.py — Extract function/class signatures from source files.
Supports Python (ast), JS/TS (regex), Go (regex). Outputs Markdown Connection Points.

Usage:
  python3 source_scan.py --project <root> --output <dir> [--scan-depth 2]
  python3 source_scan.py --file <path>                 # Single file mode
"""

import ast
import json
import os
import re
import sys
import argparse
from pathlib import Path


def scan_python(filepath):
    """Extract function and class signatures from a Python file using ast."""
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            source = f.read()
        tree = ast.parse(source)
    except (SyntaxError, UnicodeDecodeError):
        return []

    results = []
    for node in ast.walk(tree):
        if isinstance(node, ast.FunctionDef):
            args = [a.arg for a in node.args.args]
            returns = ""
            if node.returns:
                try:
                    returns = ast.unparse(node.returns)
                except AttributeError:
                    returns = "Any"
            signature = f"def {node.name}({', '.join(args)})"
            if returns:
                signature += f" -> {returns}"
            decorators = []
            for d in node.decorator_list:
                if isinstance(d, ast.Name):
                    decorators.append(f"@{d.id}")
                elif isinstance(d, ast.Attribute):
                    try:
                        decorators.append(f"@{ast.unparse(d)}")
                    except AttributeError:
                        decorators.append(f"@{d.attr}")
            results.append({
                "type": "function",
                "name": node.name,
                "signature": signature,
                "line": node.lineno,
                "decorators": decorators,
                "exported": not node.name.startswith('_')
            })
        elif isinstance(node, ast.ClassDef):
            bases = []
            for b in node.bases:
                try:
                    bases.append(ast.unparse(b))
                except AttributeError:
                    if isinstance(b, ast.Name):
                        bases.append(b.id)
                    else:
                        bases.append("...")
            bases_str = f"({', '.join(bases)})" if bases else ""
            results.append({
                "type": "class",
                "name": node.name,
                "signature": f"class {node.name}{bases_str}",
                "line": node.lineno,
                "decorators": [],
                "exported": not node.name.startswith('_')
            })
    return results


_JS_FUNC_RE = re.compile(
    r'(?:export\s+)?(?:async\s+)?function\s+(\w+)\s*\(([^)]*)\)',
    re.MULTILINE
)
_JS_ARROW_RE = re.compile(
    r'(?:export\s+)?(?:const|let|var)\s+(\w+)\s*=\s*(?:async\s+)?\(([^)]*)\)\s*=>',
    re.MULTILINE
)
_JS_CLASS_RE = re.compile(
    r'(?:export\s+)?class\s+(\w+)(?:\s+extends\s+(\w+))?',
    re.MULTILINE
)
_TS_DECORATOR = re.compile(r'@(\w+)')

_GO_FUNC_RE = re.compile(r'func\s+(?:\((\w+)\s+\*?(\w+)\)\s+)?(\w+)\s*\(([^)]*)\)')


def scan_javascript(filepath):
    """Extract exported function/class signatures from JS/TS files using regex."""
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            source = f.read()
    except UnicodeDecodeError:
        return []

    results = []
    lines = source.split('\n')

    for match in _JS_FUNC_RE.finditer(source):
        name = match.group(1)
        params = match.group(2).strip()
        lineno = source[:match.start()].count('\n') + 1
        decorator = ""
        if lineno > 1 and lineno - 2 < len(lines):
            prev = lines[lineno - 2].strip()
            dm = _TS_DECORATOR.match(prev)
            if dm:
                decorator = f"@{dm.group(1)}"
        results.append({
            "type": "function",
            "name": name,
            "signature": f"function {name}({params})",
            "line": lineno,
            "decorators": [decorator] if decorator else [],
            "exported": True
        })

    for match in _JS_ARROW_RE.finditer(source):
        name = match.group(1)
        params = match.group(2).strip()
        lineno = source[:match.start()].count('\n') + 1
        if name.startswith('_') or name[0].islower():
            continue
        results.append({
            "type": "function",
            "name": name,
            "signature": f"const {name} = ({params}) => ...",
            "line": lineno,
            "decorators": [],
            "exported": True
        })

    for match in _JS_CLASS_RE.finditer(source):
        name = match.group(1)
        parent = match.group(2)
        lineno = source[:match.start()].count('\n') + 1
        sig = f"class {name}"
        if parent:
            sig += f" extends {parent}"
        results.append({
            "type": "class",
            "name": name,
            "signature": sig,
            "line": lineno,
            "decorators": [],
            "exported": True
        })

    return results


def scan_go(filepath):
    """Extract exported function/method signatures from Go files using regex."""
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            source = f.read()
    except UnicodeDecodeError:
        return []

    results = []
    for match in _GO_FUNC_RE.finditer(source):
        recv_type = match.group(2)
        name = match.group(3)
        params = match.group(4).strip() if match.group(4) else ""
        lineno = source[:match.start()].count('\n') + 1
        exported = name[0].isupper() if name else False
        if recv_type:
            sig = f"func ({recv_type}) {name}({params})"
        else:
            sig = f"func {name}({params})"
        results.append({
            "type": "function",
            "name": name,
            "signature": sig,
            "line": lineno,
            "decorators": [],
            "exported": exported
        })

    return results


SCANNERS = {
    '.py': scan_python,
    '.ts': scan_javascript,
    '.tsx': scan_javascript,
    '.js': scan_javascript,
    '.jsx': scan_javascript,
    '.mjs': scan_javascript,
    '.go': scan_go,
}


def scan_file(filepath):
    ext = os.path.splitext(filepath)[1].lower()
    scanner = SCANNERS.get(ext)
    if not scanner:
        return []
    return scanner(filepath)


def scan_directory(project_root, scan_depth=2):
    """Scan src/ directories for source files and extract public interfaces."""
    results = {}
    src_dir = os.path.join(project_root, 'src')
    if not os.path.isdir(src_dir):
        for alt in ['app', 'lib', 'internal', 'cmd', 'handlers', 'routes', 'controllers']:
            alt_path = os.path.join(project_root, alt)
            if os.path.isdir(alt_path):
                src_dir = alt_path
                break
        else:
            src_dir = project_root

    for root, dirs, files in os.walk(src_dir):
        depth = len(os.path.relpath(root, src_dir).split(os.sep))
        rel_root = os.path.relpath(root, src_dir)
        if rel_root == '.':
            depth = 0
        if depth > scan_depth:
            dirs.clear()
            continue
        dirs[:] = [d for d in dirs if not d.startswith('.') and d not in (
            'node_modules', '__pycache__', 'venv', '.venv', 'dist', 'build',
            'target', '.git', 'vendor', 'migrations', 'tests', '__tests__',
            'test', 'spec', 'coverage', '.next', '.nuxt', 'obj'
        )]
        for f in files:
            ext = os.path.splitext(f)[1].lower()
            if ext in SCANNERS:
                filepath = os.path.join(root, f)
                symbols = scan_file(filepath)
                if symbols:
                    public = [s for s in symbols if s.get('exported', True)]
                    if public:
                        results[os.path.relpath(filepath, project_root)] = public

    return results


def format_connection_points(symbols, source_file):
    """Format extracted symbols as Connection Points markdown block."""
    lines = ["", "## Auto-Detected Interfaces", "",
              f"<!-- auto-detected from {source_file}, please verify -->", ""]
    for s in symbols:
        ref = f"src/{source_file}:{s['line']}" if not source_file.startswith('src/') else f"{source_file}:{s['line']}"
        lines.append(f"- **{s['type'].capitalize()}**: `{s['signature']}`  <!-- @ref: {ref} -->")
    lines.append("")
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="Extract source code interfaces")
    parser.add_argument('--project', help='Project root directory')
    parser.add_argument('--file', help='Single file to scan')
    parser.add_argument('--output', help='Output directory for Connection Points fragments')
    parser.add_argument('--scan-depth', type=int, default=2, help='Max directory depth for scan')
    parser.add_argument('--json', action='store_true', help='Output JSON instead of markdown')
    args = parser.parse_args()

    if args.file:
        results = {args.file: scan_file(args.file)}
    elif args.project:
        results = scan_directory(args.project, args.scan_depth)
    else:
        print("Error: --project or --file required", file=sys.stderr)
        sys.exit(1)

    if args.json:
        print(json.dumps(results, indent=2, ensure_ascii=False))
    elif args.output and args.project:
        os.makedirs(args.output, exist_ok=True)
        for filepath, symbols in results.items():
            fragment = format_connection_points(symbols, filepath)
            safe_name = filepath.replace('/', '_').replace('\\', '_').replace('.', '_')
            frag_path = os.path.join(args.output, f"{safe_name}.md")
            with open(frag_path, 'w', encoding='utf-8') as f:
                f.write(fragment)
        print(f"Extracted {sum(len(v) for v in results.values())} symbols from {len(results)} files")
    else:
        for filepath, symbols in results.items():
            print(f"\n{filepath} ({len(symbols)} symbols):")
            for s in symbols:
                print(f"  {s['type']:8s}  {s['signature']}")

if __name__ == '__main__':
    main()
