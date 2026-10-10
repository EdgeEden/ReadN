#!/usr/bin/env python3
"""
Pre-commit hook handler for ReadN.
Automatically increments the patch version (e.g. 1.1.0 -> 1.1.1)
when any project file is modified and committed.
"""

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def main():
    # Check staged files
    cmd = ["git", "diff", "--cached", "--name-only"]
    try:
        res = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, check=True)
    except Exception:
        sys.exit(0)

    staged_files = [f.strip().replace("\\", "/") for f in res.stdout.strip().splitlines() if f.strip()]
    if not staged_files:
        sys.exit(0)

    # Exclude version metadata files
    ignored_patterns = (
        "frontend/lib/config/app_version.dart",
        "frontend/pubspec.yaml",
        "frontend/pubspec.lock",
        "backend/app/main.py",
        "backend/app/config.py",
        "scripts/bump_version.py",
        "scripts/git_pre_commit.py",
        "scripts/install_hooks.py",
    )
    code_changes = [f for f in staged_files if not any(f == p or f.endswith(p) for p in ignored_patterns)]

    if code_changes:
        print(f"[Auto-Version] {len(code_changes)} modified file(s) detected. Auto-incrementing patch version...")
        bump_cmd = [sys.executable, str(ROOT / "scripts" / "bump_version.py")]
        subprocess.run(bump_cmd, cwd=ROOT, check=True)

        # Stage the updated version files
        add_files = [
            "frontend/lib/config/app_version.dart",
            "frontend/pubspec.yaml",
            "backend/app/main.py",
            "backend/app/config.py",
        ]
        # Only add files that exist
        existing_add = [f for f in add_files if (ROOT / f).exists()]
        if existing_add:
            add_cmd = ["git", "add"] + existing_add
            subprocess.run(add_cmd, cwd=ROOT, check=True)
            print("[Auto-Version] Staged updated version files for commit.")


if __name__ == "__main__":
    main()

