#!/usr/bin/env python3
"""
Installs git hooks for automated versioning in ReadN repository.
"""

from pathlib import Path
import os
import stat

ROOT = Path(__file__).resolve().parent.parent
HOOKS_DIR = ROOT / ".git" / "hooks"
PRE_COMMIT_HOOK = HOOKS_DIR / "pre-commit"

HOOK_CONTENT = """#!/bin/sh
# ReadN Automated Version Bump Hook
if command -v python3 >/dev/null 2>&1; then
    python3 scripts/git_pre_commit.py
elif command -v python >/dev/null 2>&1; then
    python scripts/git_pre_commit.py
elif command -v py >/dev/null 2>&1; then
    py scripts/git_pre_commit.py
fi
exit 0
"""


def install_hooks():
    if not HOOKS_DIR.exists():
        print(f"Error: {HOOKS_DIR} does not exist. Is this a git repository?")
        return False

    PRE_COMMIT_HOOK.write_text(HOOK_CONTENT.replace("\r\n", "\n"), encoding="utf-8")
    
    # Make executable on Unix/Linux
    try:
        st = os.stat(PRE_COMMIT_HOOK)
        os.chmod(PRE_COMMIT_HOOK, st.st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)
    except Exception:
        pass

    print(f"[Auto-Version] Successfully installed pre-commit hook at: {PRE_COMMIT_HOOK}")
    return True


if __name__ == "__main__":
    install_hooks()

