#!/usr/bin/env python3
"""visualize.py — render MEMORY_MAP.json as a Mermaid graph.

Usage:
  python scripts/visualize.py              # reads MEMORY_MAP.json
  python scripts/visualize.py path/to/map.json

Output: Mermaid markdown block to stdout. Paste into README or docs.
"""
import json, sys, os

def main():
    map_path = "MEMORY_MAP.json"
    if len(sys.argv) > 1:
        map_path = sys.argv[1]

    if not os.path.isfile(map_path):
        print(f"File not found: {map_path}", file=sys.stderr)
        sys.exit(1)

    with open(map_path) as f:
        data = json.load(f)

    nodes = data.get("nodes", [])
    if not nodes:
        print("No nodes found.", file=sys.stderr)
        return

    print("```mermaid")
    print("graph TD")
    print("    classDef module fill:#e1f5fe,stroke:#01579b,stroke-width:2px;")
    print("    classDef feature fill:#f3e5f5,stroke:#4a148c,stroke-width:1px;")
    print("    classDef archived fill:#eeeeee,stroke:#757575,stroke-width:1px,stroke-dasharray: 5 5;")
    print()

    for n in nodes:
        nid = n["id"]
        ntype = n.get("type", "unknown")
        status = n.get("status", "unknown")
        tokens = n.get("tokens", 0)
        label = f"{nid}<br/>~{tokens} tok<br/>({status})"
        cls = "archived" if status == "archived" else ntype
        print(f'    {nid}["{label}"]:::{cls}')

    print()
    for n in nodes:
        src = n["id"]
        for dep in n.get("depends_on", []):
            dep_id = dep.replace("meta/", "").replace(".md", "")
            print(f"    {src} --> {dep_id}")

    print("```")

if __name__ == "__main__":
    main()
