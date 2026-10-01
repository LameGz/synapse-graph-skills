#!/usr/bin/env python3
"""build_dist.py — Single-source build & sync for the Synapse skill suite.

The canonical scripts live in `synapse-graph-memory/scripts/` (plus its
hooks/). Dependent skills (`synapse-daily-note`, `synapse-init`,
`synapse-timeline`) receive synced copies at build time, per
`scripts/dist-manifest.json`. Files listed in a target's `keep` are never
overwritten (e.g. synapse-init's init.sh wrapper).

Usage:
  python scripts/build_dist.py            # sync scripts into skills
  python scripts/build_dist.py --check    # exit 1 if any target drifted (CI gate)
  python scripts/build_dist.py --package  # additionally rebuild the 4 .skill zips
"""

from __future__ import annotations

import argparse
import json
import sys
import zipfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
MANIFEST_PATH = REPO_ROOT / "scripts" / "dist-manifest.json"


def load_manifest() -> dict:
    data = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    if "source_skill" not in data or "targets" not in data:
        raise SystemExit(f"Invalid manifest: {MANIFEST_PATH}")
    return data


def shared_scripts(source_skill: Path) -> list[Path]:
    scripts_dir = source_skill / "scripts"
    files = sorted(
        p for p in scripts_dir.rglob("*")
        if p.is_file() and "__pycache__" not in p.parts
    )
    if not files:
        raise SystemExit(f"No scripts found under {scripts_dir}")
    return files


def rel_target(shared_file: Path, source_scripts: Path) -> Path:
    return shared_file.relative_to(source_scripts)


def sync(manifest: dict, check_only: bool) -> tuple[list[str], list[str]]:
    """Returns (changed, up_to_date) rel-path reports."""
    source = REPO_ROOT / manifest["source_skill"]
    source_scripts = source / "scripts"
    shared = shared_scripts(source)
    changed: list[str] = []
    up_to_date: list[str] = []

    for target_name, cfg in manifest["targets"].items():
        target = REPO_ROOT / target_name
        if not target.is_dir():
            raise SystemExit(f"Target skill missing: {target_name}")
        keep = set(cfg.get("keep", []))
        include = cfg.get("include", "*")
        for shared_file in shared:
            rel = rel_target(shared_file, source_scripts)
            if include != "*" and rel.as_posix() not in include:
                continue
            if rel.as_posix() in keep:
                continue
            dest = target / "scripts" / rel
            src_bytes = shared_file.read_bytes()
            if dest.exists() and dest.read_bytes() == src_bytes:
                up_to_date.append(f"{target_name}/scripts/{rel.as_posix()}")
                continue
            changed.append(f"{target_name}/scripts/{rel.as_posix()}")
            if not check_only:
                dest.parent.mkdir(parents=True, exist_ok=True)
                dest.write_bytes(src_bytes)

    return changed, up_to_date


def _excluded(rel_parts: tuple[str, ...], excludes: set[str]) -> bool:
    for i in range(len(rel_parts)):
        if "/".join(rel_parts[: i + 1]) in excludes:
            return True
    return False


def package(manifest: dict) -> list[Path]:
    excludes = set(manifest.get("package_exclude", []))
    zips: list[Path] = []
    for skill_name in [manifest["source_skill"], *manifest["targets"].keys()]:
        skill_dir = REPO_ROOT / skill_name
        if not skill_dir.is_dir():
            continue
        out = REPO_ROOT / f"{skill_name}.skill"
        with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
            for f in sorted(skill_dir.rglob("*")):
                if not f.is_file():
                    continue
                if "__pycache__" in f.parts or f.suffix == ".pyc" or f.name == ".DS_Store":
                    continue
                if _excluded(f.relative_to(skill_dir).parts, excludes):
                    continue
                zf.write(f, f.relative_to(REPO_ROOT).as_posix())
        zips.append(out)
    return zips


def main() -> int:
    parser = argparse.ArgumentParser(description="Sync and package Synapse skills.")
    parser.add_argument("--check", action="store_true", help="Fail if any target drifted; write nothing")
    parser.add_argument("--package", action="store_true", help="Also rebuild the .skill zips")
    args = parser.parse_args()

    manifest = load_manifest()
    changed, up_to_date = sync(manifest, check_only=args.check)

    if args.check:
        if changed:
            print("Drift detected — run `python scripts/build_dist.py` to fix:")
            for item in changed:
                print(f"  DRIFT: {item}")
            return 1
        print(f"build_dist check: {len(up_to_date)} synced files up to date.")
        return 0

    for item in changed:
        print(f"SYNCED: {item}")
    print(f"build_dist: {len(changed)} file(s) synced, {len(up_to_date)} already up to date.")

    if args.package:
        for z in package(manifest):
            print(f"PACKAGED: {z.name} ({z.stat().st_size // 1024} KB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
