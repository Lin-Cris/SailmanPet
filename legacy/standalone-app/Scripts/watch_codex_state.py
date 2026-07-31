#!/usr/bin/env python3
"""Translate persisted Codex CLI rollout events into Luffy pet states."""

from __future__ import annotations

import argparse
import json
import os
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any


@dataclass
class Session:
    offset: int = 0
    is_cli: bool | None = None
    active: bool = False
    review: bool = False
    updated_at: float = 0


def is_cli_metadata(payload: dict[str, Any]) -> bool:
    originator = str(payload.get("originator", "")).lower()
    source = str(payload.get("source", "")).lower()
    # `codex exec` persists sessions as source=exec on current CLI builds.
    # Treat it as CLI so the normal non-interactive command path receives the
    # same coding/review lifecycle as the interactive `codex` command.
    return source in {"cli", "exec"} or (
        "cli" in originator and "desktop" not in originator
    )


def apply_event(session: Session, record: dict[str, Any], now: float) -> bool:
    payload = record.get("payload")
    if not isinstance(payload, dict):
        return False

    if record.get("type") == "session_meta":
        session.is_cli = is_cli_metadata(payload)
        return True

    event = payload.get("type")
    if not isinstance(event, str) or session.is_cli is not True:
        return False

    if event == "task_started":
        session.active = True
        session.review = False
    elif event == "entered_review_mode":
        session.active = True
        session.review = True
    elif event == "exited_review_mode":
        session.active = True
        session.review = False
    elif event in {"task_complete", "turn_aborted", "session_end"}:
        session.active = False
        session.review = False
    elif event in {
        "patch_apply_begin",
        "patch_apply_end",
        "file_change",
        "agent_reasoning",
        "agent_message",
    }:
        session.active = True
    else:
        return False

    session.updated_at = now
    return True


class CodexStateWatcher:
    def __init__(
        self,
        sessions_root: Path,
        state_file: Path,
        stale_seconds: float = 900,
    ) -> None:
        self.sessions_root = sessions_root
        self.state_file = state_file
        self.stale_seconds = stale_seconds
        self.sessions: dict[Path, Session] = {}
        self.last_state: str | None = None

    def poll_once(self) -> str:
        now = time.time()
        for path in self.sessions_root.glob("**/rollout-*.jsonl"):
            self._read_updates(path, now)

        active = [
            (path, session)
            for path, session in self.sessions.items()
            if session.is_cli is True
            and session.active
            and now - session.updated_at <= self.stale_seconds
        ]
        if not active:
            state = "idle"
            source_session = None
        else:
            source_session, session = max(
                active,
                key=lambda item: item[1].updated_at,
            )
            state = "review" if session.review else "coding"

        if state != self.last_state:
            write_state(
                self.state_file,
                state,
                source="codex-rollout-jsonl",
                session=str(source_session) if source_session else None,
            )
            self.last_state = state
        return state

    def _read_updates(self, path: Path, now: float) -> None:
        session = self.sessions.setdefault(path, Session())
        try:
            size = path.stat().st_size
            if size < session.offset:
                session.offset = 0
            with path.open("r", encoding="utf-8") as handle:
                handle.seek(session.offset)
                while True:
                    start = handle.tell()
                    line = handle.readline()
                    if not line:
                        break
                    if not line.endswith("\n"):
                        handle.seek(start)
                        break
                    try:
                        record = json.loads(line)
                    except json.JSONDecodeError:
                        continue
                    apply_event(session, record, now)
                session.offset = handle.tell()
        except (OSError, UnicodeError):
            return


def write_state(
    path: Path,
    state: str,
    *,
    source: str,
    session: str | None = None,
    pid: int | None = None,
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    payload: dict[str, Any] = {
        "version": 1,
        "state": state,
        "source": source,
        "updatedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }
    if session is not None:
        payload["session"] = session
    if pid is not None:
        payload["pid"] = pid

    descriptor, temporary = tempfile.mkstemp(
        prefix=f".{path.name}.",
        dir=path.parent,
        text=True,
    )
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, ensure_ascii=False)
            handle.write("\n")
        os.replace(temporary, path)
    finally:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass


def parse_args() -> argparse.Namespace:
    codex_directory = Path(
        os.environ.get("CODEX_HOME", str(Path.home() / ".codex"))
    )
    project_directory = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--sessions-root",
        type=Path,
        default=codex_directory / "sessions",
    )
    parser.add_argument(
        "--state-file",
        type=Path,
        default=project_directory / ".runtime" / "luffy-pet-state.json",
    )
    parser.add_argument("--interval", type=float, default=0.5)
    parser.add_argument("--stale-seconds", type=float, default=900)
    parser.add_argument("--once", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    watcher = CodexStateWatcher(
        args.sessions_root,
        args.state_file,
        stale_seconds=args.stale_seconds,
    )
    try:
        while True:
            watcher.poll_once()
            if args.once:
                return 0
            time.sleep(max(0.1, args.interval))
    except KeyboardInterrupt:
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
