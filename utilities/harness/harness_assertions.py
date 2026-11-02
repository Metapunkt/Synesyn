"""Assertion engine for structured Synesyn harness artifacts."""

from __future__ import annotations

import re
from typing import Any


_BENIGN_ERROR_PATTERNS = [
    r"Logging service not available",
    r"push_error",
    r"variant_utility\.cpp",
]


def extract_errors(log_text: str) -> list[str]:
    """Return unexpected Godot ERROR lines."""
    errors = []
    for line in log_text.splitlines():
        if "ERROR:" not in line:
            continue
        if any(re.search(pattern, line) for pattern in _BENIGN_ERROR_PATTERNS):
            continue
        errors.append(line.strip())
    return errors


_MISSING = object()


def _lookup_path(snapshot: dict[str, Any], path: str) -> Any:
    """Resolve a dotted path such as 'workshop_catalyst.thinking_map.node_count'."""
    current: Any = snapshot
    for segment in path.split("."):
        if not isinstance(current, dict) or segment not in current:
            return _MISSING
        current = current[segment]
    return current


def _check_snapshot_field(assertion: dict[str, Any], snapshot: dict[str, Any]) -> tuple[bool, str]:
    path = str(assertion.get("path", "")).strip()
    if not path:
        return False, "assertion is missing 'path'"
    actual = _lookup_path(snapshot, path)
    if actual is _MISSING:
        return False, f"{path} is absent from the snapshot"

    if "min" in assertion:
        expected = float(assertion["min"])
        try:
            numeric = float(actual)
        except (TypeError, ValueError):
            return False, f"{path}={actual!r} is not numeric"
        return numeric >= expected, f"{path}={actual}" + ("" if numeric >= expected else f" < {expected:g}")
    if "equals" in assertion:
        expected_value = assertion["equals"]
        matches = actual == expected_value
        return matches, f"{path}={actual!r}" + ("" if matches else f", expected {expected_value!r}")
    if "contains" in assertion:
        needle = str(assertion["contains"])
        matches = needle.lower() in str(actual).lower()
        return matches, (
            f"{path} contains {needle!r}" if matches else f"{needle!r} not in {path}={str(actual)[:80]!r}"
        )
    # Default: the field must be present and truthy/non-empty.
    matches = bool(actual)
    return matches, f"{path}={str(actual)[:80]!r}" + ("" if matches else " (empty)")


def _result(assertion: dict[str, Any], ok: bool, detail: str) -> dict[str, Any]:
    assertion_type = str(assertion["type"])
    return {
        "name": str(assertion.get("name", assertion_type.replace("_", "-"))),
        "type": assertion_type,
        "ok": ok,
        "detail": detail,
    }


def run_assertions(
    scene_logs: dict[str, Any],
    godot_log: str,
    assertions: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    """Evaluate normalized assertion objects against harness artifacts."""
    story = scene_logs.get("story_log", {})
    if not isinstance(story, dict):
        story = {}
    log_count = int(story.get("count", 0))
    last_entry = story.get("last_entry", {})
    if not isinstance(last_entry, dict):
        last_entry = {}
    tail = story.get("tail", [])
    if not isinstance(tail, list):
        tail = []
    last_sender = str(last_entry.get("sender", "")).strip()
    last_message = str(last_entry.get("message", "")).strip()
    results: list[dict[str, Any]] = []

    for assertion in assertions:
        assertion_type = str(assertion["type"])
        value = assertion.get("value")

        if assertion_type == "min_story_log":
            expected = int(value)
            results.append(
                _result(
                    assertion,
                    log_count >= expected,
                    f"count={log_count}" if log_count >= expected else f"count={log_count} < {expected}",
                )
            )
        elif assertion_type == "exact_story_log":
            expected = int(value)
            results.append(
                _result(
                    assertion,
                    log_count == expected,
                    f"count={log_count}"
                    if log_count == expected
                    else f"count={log_count} != {expected}",
                )
            )
        elif assertion_type == "last_sender":
            expected = str(value).strip()
            matches = last_sender.lower() == expected.lower()
            results.append(
                _result(
                    assertion,
                    matches,
                    f"sender='{last_sender}'"
                    if matches
                    else f"got '{last_sender}', expected '{expected}'",
                )
            )
        elif assertion_type == "last_sender_in":
            if isinstance(value, str):
                allowed_display = [item.strip() for item in value.split(",") if item.strip()]
            elif isinstance(value, list):
                allowed_display = [str(item).strip() for item in value]
            else:
                allowed_display = []
            allowed = {item.lower() for item in allowed_display}
            matches = last_sender.lower() in allowed
            results.append(
                _result(
                    assertion,
                    matches,
                    f"sender='{last_sender}'"
                    if matches
                    else f"got '{last_sender}', allowed: {allowed_display}",
                )
            )
        elif assertion_type == "last_message_contains":
            needle = str(value)
            matches = needle.lower() in last_message.lower()
            preview = last_message[:120].replace("\n", " ")
            results.append(
                _result(
                    assertion,
                    matches,
                    f"found '{needle}' in message"
                    if matches
                    else f"'{needle}' not found in: '{preview}...'",
                )
            )
        elif assertion_type == "scenario_contains":
            actual = str(scene_logs.get("scenario", ""))
            expected = str(value)
            matches = expected.lower() in actual.lower()
            results.append(
                _result(
                    assertion,
                    matches,
                    f"scenario='{actual}'"
                    if matches
                    else f"got '{actual}', expected to contain '{expected}'",
                )
            )
        elif assertion_type == "no_errors":
            errors = extract_errors(godot_log)
            results.append(
                _result(
                    assertion,
                    not errors,
                    "no unexpected ERROR: lines in log"
                    if not errors
                    else f"{len(errors)} error(s): {errors[:3]}",
                )
            )
        elif assertion_type == "log_not_contains":
            needle = str(value)
            hits = [line.strip() for line in godot_log.splitlines() if needle.lower() in line.lower()]
            results.append(
                _result(
                    assertion,
                    bool(needle) and not hits,
                    f"'{needle}' absent from log"
                    if needle and not hits
                    else f"{len(hits)} line(s) contain '{needle}': {hits[:2]}",
                )
            )
        elif assertion_type in {"min_unique_senders", "exact_unique_senders"}:
            senders = {
                str(entry.get("sender", "")).strip()
                for entry in tail
                if isinstance(entry, dict) and str(entry.get("sender", "")).strip()
            }
            if assertion.get("exclude_system", True):
                system_senders = {
                    "narrator",
                    "unknown peer",
                    "facilitator note",
                    "session record",
                }
                senders = {sender for sender in senders if sender.lower() not in system_senders}
            excluded = {
                str(sender).strip().lower()
                for sender in assertion.get("exclude_senders", [])
                if str(sender).strip()
            }
            senders = {sender for sender in senders if sender.lower() not in excluded}
            expected = int(value)
            matches = (
                len(senders) >= expected
                if assertion_type == "min_unique_senders"
                else len(senders) == expected
            )
            comparison = "at least" if assertion_type == "min_unique_senders" else "exactly"
            results.append(
                _result(
                    assertion,
                    matches,
                    f"{comparison} {expected} sender(s) in tail: {sorted(senders)}"
                    if matches
                    else (
                        f"got {len(senders)} distinct sender(s), expected {comparison} "
                        f"{expected}: {sorted(senders)}"
                    ),
                )
            )
        elif assertion_type == "snapshot_field":
            ok, detail = _check_snapshot_field(assertion, scene_logs)
            results.append(_result(assertion, ok, detail))
        elif assertion_type == "exact_sender_occurrences":
            expected = int(value)
            expected_sender = str(assertion.get("sender", "")).strip()
            occurrence_count = sum(
                1
                for entry in tail
                if isinstance(entry, dict)
                and str(entry.get("sender", "")).strip().lower()
                == expected_sender.lower()
            )
            matches = bool(expected_sender) and occurrence_count == expected
            results.append(
                _result(
                    assertion,
                    matches,
                    (
                        f"sender '{expected_sender}' occurred {occurrence_count} time(s)"
                        if matches
                        else (
                            f"sender '{expected_sender}' occurred {occurrence_count} "
                            f"time(s), expected {expected}"
                        )
                    ),
                )
            )

    return results


def merge_assertions(
    embedded: list[dict[str, Any]],
    cli_assertions: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    """Merge assertions, letting explicit CLI checks replace matching embedded types."""
    cli_types = {str(assertion["type"]) for assertion in cli_assertions}
    return [
        assertion for assertion in embedded if str(assertion.get("type")) not in cli_types
    ] + cli_assertions
