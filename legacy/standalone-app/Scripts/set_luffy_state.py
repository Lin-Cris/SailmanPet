#!/usr/bin/env python3
"""Set or clear the manual Luffy pet state override."""

from __future__ import annotations

import argparse
import os
from pathlib import Path

from watch_codex_state import write_state


def main() -> int:
    project_directory = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser()
    parser.add_argument("state", choices=("idle", "coding", "review"))
    parser.add_argument(
        "--file",
        type=Path,
        default=project_directory / ".runtime" / "luffy-pet-override.json",
    )
    parser.add_argument("--pid", type=int)
    args = parser.parse_args()

    if args.state == "idle":
        try:
            args.file.unlink()
        except FileNotFoundError:
            pass
        return 0

    write_state(
        args.file,
        args.state,
        source="manual-override",
        pid=args.pid,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
