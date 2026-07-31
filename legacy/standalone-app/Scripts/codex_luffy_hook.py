#!/usr/bin/env python3
"""Map native Codex lifecycle hooks onto Luffy Pet's automatic state file."""

from __future__ import annotations

import json
import sys
import time
from pathlib import Path

from watch_codex_state import write_state


def main() -> int:
    try:
        event = json.load(sys.stdin)
    except (json.JSONDecodeError, OSError):
        # Hooks must never interfere with a Codex turn.
        return 0

    hook_name = event.get("hook_event_name")
    if hook_name in {"SessionStart", "UserPromptSubmit"}:
        state = "coding"
    elif hook_name in {"Stop", "SessionEnd"}:
        state = "idle"
    else:
        return 0

    project_directory = Path(__file__).resolve().parents[1]
    with (project_directory / ".runtime" / "codex-hook.log").open(
        "a", encoding="utf-8"
    ) as log:
        log.write(
            f"{time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())} "
            f"event={hook_name} state={state} session={event.get('session_id', '')}\n"
        )
    write_state(
        project_directory / ".runtime" / "luffy-pet-state.json",
        state,
        source="codex-native-hook",
        session=event.get("session_id"),
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
