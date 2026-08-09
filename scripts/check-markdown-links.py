#!/usr/bin/env python3
"""Verify tracked Markdown file links without making network requests."""

from __future__ import annotations

import pathlib
import re
import subprocess
import sys


def main() -> int:
    files = [
        pathlib.Path(path)
        for path in subprocess.check_output(
            ["git", "ls-files", "*.md"], text=True
        ).splitlines()
    ]
    missing: list[str] = []
    for document in files:
        text = document.read_text(encoding="utf-8")
        for target in re.findall(r"\[[^]]*\]\(([^)]+)\)", text):
            if target.startswith(("http://", "https://", "mailto:", "#")):
                continue
            path = target.split("#", 1)[0]
            if path and not (document.parent / path).resolve().exists():
                missing.append(f"{document}: {target}")
    if missing:
        print("broken local Markdown links:", file=sys.stderr)
        print("\n".join(missing), file=sys.stderr)
        return 1
    print(f"Markdown links passed ({len(files)} tracked documents)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
