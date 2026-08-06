#!/usr/bin/env python3
"""Capture the moderngekko-run game window region to a PNG.

Uses screencapture for the full desktop then crops to the known on-screen
game window region (fixed rectangle in points), so evidence files are compact
and game-focused even when other windows overlap the desktop.
"""

from __future__ import annotations

import argparse
import datetime
import subprocess
import sys
from pathlib import Path


# On-screen game window rectangle in points (Retina 2x on this host).
GAME_X0, GAME_Y0, GAME_X1, GAME_Y1 = 140, 90, 900, 1030


def capture(out_path: Path) -> Path:
    full = out_path.with_name(out_path.stem + ".full.png")
    subprocess.run(["screencapture", "-x", str(full)], check=True)
    try:
        from PIL import Image
    except ImportError:
        full.replace(out_path)
        return out_path
    img = Image.open(full)
    scale = 2 if img.width >= 2500 else 1
    crop = img.crop(
        (
            GAME_X0 * scale,
            GAME_Y0 * scale,
            GAME_X1 * scale,
            GAME_Y1 * scale,
        )
    )
    crop.save(out_path)
    full.unlink(missing_ok=True)
    return out_path


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", type=Path, default=None, help="output PNG path")
    args = ap.parse_args()
    if args.out is None:
        stamp = datetime.datetime.now().strftime("%Y-%m-%d-%H%M%S")
        args.out = Path(f"/tmp/sunpad-{stamp}.png")
    capture(args.out)
    print(args.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
