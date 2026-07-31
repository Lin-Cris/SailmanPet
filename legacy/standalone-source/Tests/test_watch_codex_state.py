from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).parents[1] / "Scripts"))

from watch_codex_state import CodexStateWatcher  # noqa: E402


class CodexStateWatcherTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.sessions = self.root / "sessions" / "2026" / "07" / "29"
        self.sessions.mkdir(parents=True)
        self.rollout = self.sessions / "rollout-test.jsonl"
        self.state_file = self.root / "state.json"
        self.watcher = CodexStateWatcher(
            self.root / "sessions",
            self.state_file,
            stale_seconds=3600,
        )

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def append(self, record: dict) -> None:
        with self.rollout.open("a", encoding="utf-8") as handle:
            json.dump(record, handle)
            handle.write("\n")

    def test_cli_turn_transitions_between_states(self) -> None:
        self.append(
            {
                "type": "session_meta",
                "payload": {"originator": "Codex CLI", "source": "cli"},
            }
        )
        self.append({"type": "event_msg", "payload": {"type": "task_started"}})
        self.assertEqual(self.watcher.poll_once(), "coding")

        self.append(
            {"type": "event_msg", "payload": {"type": "entered_review_mode"}}
        )
        self.assertEqual(self.watcher.poll_once(), "review")

        self.append({"type": "event_msg", "payload": {"type": "task_complete"}})
        self.assertEqual(self.watcher.poll_once(), "idle")

    def test_desktop_session_is_ignored(self) -> None:
        self.append(
            {
                "type": "session_meta",
                "payload": {"originator": "Codex Desktop", "source": "vscode"},
            }
        )
        self.append({"type": "event_msg", "payload": {"type": "task_started"}})
        self.assertEqual(self.watcher.poll_once(), "idle")

    def test_codex_exec_session_is_treated_as_cli(self) -> None:
        self.append(
            {
                "type": "session_meta",
                "payload": {"originator": "Codex Desktop", "source": "exec"},
            }
        )
        self.append({"type": "event_msg", "payload": {"type": "task_started"}})
        self.assertEqual(self.watcher.poll_once(), "coding")


if __name__ == "__main__":
    unittest.main()
