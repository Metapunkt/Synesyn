from __future__ import annotations

import sys
import unittest
from pathlib import Path


SCRIPTS_DIR = Path(__file__).resolve().parents[1]
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

from harness_assertions import merge_assertions, run_assertions
from harness_spec_utils import SpecValidationError, prepare_spec


class HarnessSpecUtilsTests(unittest.TestCase):
    def test_expands_nested_parameterized_sequences(self) -> None:
        spec = {
            "scene_path": "res://test.tscn",
            "action_sequences": {
                "send": {
                    "parameters": ["message"],
                    "actions": [{
                        "type": "call_scene_method",
                        "method": "test_send_user_message",
                        "args": ["{{message}}"],
                    }],
                },
                "turn": {
                    "parameters": ["message", "seconds"],
                    "actions": [
                        {"use": "send", "with": {"message": "{{message}}"}},
                        {"type": "wait_seconds", "seconds": "{{seconds}}"},
                    ],
                },
            },
            "post_actions": [{
                "use": "turn",
                "with": {"message": "Hello", "seconds": 12.5},
            }],
            "assertions": [{"type": "no_errors"}],
        }

        prepared = prepare_spec(spec, Path.cwd())

        self.assertEqual(
            prepared["post_actions"],
            [
                {
                    "type": "call_scene_method",
                    "method": "test_send_user_message",
                    "args": ["Hello"],
                },
                {"type": "wait_seconds", "seconds": 12.5},
            ],
        )
        self.assertNotIn("action_sequences", prepared)

    def test_rejects_sequence_cycles(self) -> None:
        spec = {
            "scene_path": "res://test.tscn",
            "action_sequences": {
                "first": [{"use": "second"}],
                "second": [{"use": "first"}],
            },
            "post_actions": [{"use": "first"}],
        }

        with self.assertRaisesRegex(SpecValidationError, "cycle detected"):
            prepare_spec(spec, Path.cwd())

    def test_rejects_unknown_action_type(self) -> None:
        spec = {
            "scene_path": "res://test.tscn",
            "post_actions": [{"type": "click_magic_button"}],
        }

        with self.assertRaisesRegex(SpecValidationError, "unsupported"):
            prepare_spec(spec, Path.cwd())

    def test_embedded_assertions_and_cli_override(self) -> None:
        embedded = [
            {"type": "min_story_log", "value": 3},
            {"type": "no_errors"},
        ]
        cli = [{"type": "min_story_log", "value": 5}]
        assertions = merge_assertions(embedded, cli)
        scene_logs = {
            "story_log": {
                "count": 4,
                "last_entry": {"sender": "Alice", "message": "Hello"},
                "tail": [{"sender": "Alice"}],
            }
        }

        results = run_assertions(scene_logs, "", assertions)

        self.assertEqual([item["type"] for item in results], ["no_errors", "min_story_log"])
        self.assertTrue(results[0]["ok"])
        self.assertFalse(results[1]["ok"])

    def test_log_not_contains_fails_on_any_matching_line(self) -> None:
        assertion = {"type": "log_not_contains", "value": "hub client created"}
        clean = run_assertions({}, "StoryStage: Voice integration ready\n", [assertion])
        dirty = run_assertions({}, "StoryStage: vis_story Hub Client created\n", [assertion])

        self.assertTrue(clean[0]["ok"])
        self.assertFalse(dirty[0]["ok"])

    def test_exact_unique_senders_supports_explicit_exclusions(self) -> None:
        assertions = [{
            "type": "exact_unique_senders",
            "value": 1,
            "exclude_system": False,
            "exclude_senders": ["Facilitator", "Narrator"],
        }]
        scene_logs = {
            "story_log": {
                "count": 4,
                "last_entry": {"sender": "Session Record", "message": "Summary"},
                "tail": [
                    {"sender": "Narrator"},
                    {"sender": "Facilitator"},
                    {"sender": "Session Record"},
                    {"sender": "Session Record"},
                ],
            }
        }

        results = run_assertions(scene_logs, "", assertions)

        self.assertTrue(results[0]["ok"])
        self.assertIn("Session Record", results[0]["detail"])

    def test_exact_sender_occurrences_counts_tail_entries(self) -> None:
        assertion = {
            "type": "exact_sender_occurrences",
            "sender": "Session Record",
            "value": 2,
        }
        scene_logs = {
            "story_log": {
                "count": 4,
                "last_entry": {"sender": "Session Record", "message": "Second"},
                "tail": [
                    {"sender": "Facilitator"},
                    {"sender": "Session Record"},
                    {"sender": "Facilitator"},
                    {"sender": "Session Record"},
                ],
            }
        }

        results = run_assertions(scene_logs, "", [assertion])

        self.assertTrue(results[0]["ok"])


if __name__ == "__main__":
    unittest.main()
