"""Load, validate, and expand Synesyn harness run specs."""

from __future__ import annotations

import copy
import json
import re
from pathlib import Path
from typing import Any


PRE_ACTION_TYPES = {"call_autoload"}
POST_ACTION_TYPES = {
    "call_scene_method",
    "call_node_method",
    "set_node_property",
    "call_autoload",
    "wait_seconds",
    "wait_frames",
    "capture_screenshot",
    "mount_scene",
}
ASSERTION_TYPES = {
    "min_story_log",
    "exact_story_log",
    "last_sender",
    "last_sender_in",
    "last_message_contains",
    "scenario_contains",
    "no_errors",
    "log_not_contains",
    "min_unique_senders",
    "exact_unique_senders",
    "exact_sender_occurrences",
    "snapshot_field",
}
# snapshot_field is keyed by `path` plus an optional comparison, so it has no
# single `value` the way the story-log assertions do.
_ASSERTION_TYPES_WITHOUT_VALUE = {"no_errors", "snapshot_field"}
_EXACT_PARAMETER = re.compile(r"^\{\{([A-Za-z_][A-Za-z0-9_]*)\}\}$")
_PARAMETER = re.compile(r"\{\{([A-Za-z_][A-Za-z0-9_]*)\}\}")


class SpecValidationError(ValueError):
    """Raised when a run spec cannot be safely executed."""

    def __init__(self, errors: list[str]):
        super().__init__("Invalid harness spec:\n- " + "\n- ".join(errors))
        self.errors = errors


def _read_json_object(path: Path, label: str) -> dict[str, Any]:
    try:
        with path.open(encoding="utf-8") as file_handle:
            value = json.load(file_handle)
    except FileNotFoundError as exc:
        raise SpecValidationError([f"{label} not found: {path}"]) from exc
    except json.JSONDecodeError as exc:
        raise SpecValidationError(
            [f"{label} is not valid JSON at line {exc.lineno}, column {exc.colno}: {path}"]
        ) from exc
    except OSError as exc:
        raise SpecValidationError([f"Could not read {label}: {path}: {exc}"]) from exc
    if not isinstance(value, dict):
        raise SpecValidationError([f"{label} must contain a JSON object: {path}"])
    return value


def _sequence_map(document: dict[str, Any], label: str) -> dict[str, Any]:
    raw_sequences = document.get("action_sequences", document.get("sequences", {}))
    if not isinstance(raw_sequences, dict):
        raise SpecValidationError([f"{label}.action_sequences must be an object"])
    return raw_sequences


def _substitute(value: Any, parameters: dict[str, Any], context: str) -> Any:
    if isinstance(value, str):
        exact_match = _EXACT_PARAMETER.match(value)
        if exact_match:
            key = exact_match.group(1)
            if key not in parameters:
                raise SpecValidationError([f"{context} requires parameter '{key}'"])
            return copy.deepcopy(parameters[key])

        def replace(match: re.Match[str]) -> str:
            key = match.group(1)
            if key not in parameters:
                raise SpecValidationError([f"{context} requires parameter '{key}'"])
            return str(parameters[key])

        return _PARAMETER.sub(replace, value)
    if isinstance(value, list):
        return [_substitute(item, parameters, context) for item in value]
    if isinstance(value, dict):
        return {key: _substitute(item, parameters, context) for key, item in value.items()}
    return copy.deepcopy(value)


def _normalize_sequence(sequence: Any, sequence_name: str) -> tuple[list[str], list[Any]]:
    if isinstance(sequence, list):
        return [], sequence
    if not isinstance(sequence, dict):
        raise SpecValidationError(
            [f"Action sequence '{sequence_name}' must be an array or object"]
        )
    parameters = sequence.get("parameters", [])
    actions = sequence.get("actions", [])
    if not isinstance(parameters, list) or not all(isinstance(item, str) for item in parameters):
        raise SpecValidationError(
            [f"Action sequence '{sequence_name}'.parameters must be an array of strings"]
        )
    if not isinstance(actions, list):
        raise SpecValidationError([f"Action sequence '{sequence_name}'.actions must be an array"])
    return parameters, actions


def _expand_action_list(
    actions: Any,
    sequences: dict[str, Any],
    field_name: str,
    stack: tuple[str, ...] = (),
) -> list[dict[str, Any]]:
    if actions is None:
        return []
    if not isinstance(actions, list):
        raise SpecValidationError([f"{field_name} must be an array"])

    expanded: list[dict[str, Any]] = []
    for index, action in enumerate(actions):
        location = f"{field_name}[{index}]"
        if not isinstance(action, dict):
            raise SpecValidationError([f"{location} must be an object"])
        if "use" not in action:
            expanded.append(copy.deepcopy(action))
            continue

        sequence_name = str(action.get("use", "")).strip()
        if not sequence_name:
            raise SpecValidationError([f"{location}.use must name an action sequence"])
        if sequence_name not in sequences:
            raise SpecValidationError([f"{location} references unknown sequence '{sequence_name}'"])
        if sequence_name in stack:
            cycle = " -> ".join((*stack, sequence_name))
            raise SpecValidationError([f"Action sequence cycle detected: {cycle}"])

        parameters = action.get("with", {})
        if not isinstance(parameters, dict):
            raise SpecValidationError([f"{location}.with must be an object"])
        required_parameters, sequence_actions = _normalize_sequence(
            sequences[sequence_name], sequence_name
        )
        missing = [key for key in required_parameters if key not in parameters]
        if missing:
            raise SpecValidationError(
                [f"{location} sequence '{sequence_name}' is missing parameters: {', '.join(missing)}"]
            )
        substituted = _substitute(
            sequence_actions, parameters, f"{location} sequence '{sequence_name}'"
        )
        expanded.extend(
            _expand_action_list(
                substituted,
                sequences,
                f"{location}<{sequence_name}>",
                (*stack, sequence_name),
            )
        )
    return expanded


def validate_spec(spec: dict[str, Any]) -> None:
    """Validate an expanded run spec and raise SpecValidationError on failure."""
    errors: list[str] = []
    scene_path = spec.get("scene_path")
    if not isinstance(scene_path, str) or not scene_path.strip():
        errors.append("scene_path is required and must be a non-empty string")

    for field_name, allowed_types in (
        ("actions", PRE_ACTION_TYPES),
        ("post_actions", POST_ACTION_TYPES),
    ):
        actions = spec.get(field_name, [])
        if not isinstance(actions, list):
            errors.append(f"{field_name} must be an array")
            continue
        for index, action in enumerate(actions):
            if not isinstance(action, dict):
                errors.append(f"{field_name}[{index}] must be an object")
                continue
            action_type = action.get("type")
            if action_type not in allowed_types:
                errors.append(
                    f"{field_name}[{index}].type '{action_type}' is unsupported; "
                    f"expected one of {sorted(allowed_types)}"
                )
                continue
            if action_type == "capture_screenshot" and not str(
                action.get("name", "")
            ).strip():
                # The name becomes the PNG filename, so an unnamed capture would be
                # skipped in the middle of a run that may have cost real model calls.
                errors.append(f"{field_name}[{index}] (capture_screenshot) requires name")
            if action_type == "mount_scene" and not str(
                action.get("scene_path", "")
            ).strip():
                errors.append(f"{field_name}[{index}] (mount_scene) requires scene_path")

    assertions = spec.get("assertions", [])
    if not isinstance(assertions, list):
        errors.append("assertions must be an array")
    else:
        for index, assertion in enumerate(assertions):
            if not isinstance(assertion, dict):
                errors.append(f"assertions[{index}] must be an object")
                continue
            assertion_type = assertion.get("type")
            if assertion_type not in ASSERTION_TYPES:
                errors.append(
                    f"assertions[{index}].type '{assertion_type}' is unsupported; "
                    f"expected one of {sorted(ASSERTION_TYPES)}"
                )
                continue
            if (
                assertion_type not in _ASSERTION_TYPES_WITHOUT_VALUE
                and "value" not in assertion
            ):
                errors.append(f"assertions[{index}] ({assertion_type}) requires value")
            if (
                assertion_type == "exact_sender_occurrences"
                and not str(assertion.get("sender", "")).strip()
            ):
                errors.append(
                    f"assertions[{index}] (exact_sender_occurrences) requires sender"
                )
            if assertion_type == "snapshot_field" and not str(
                assertion.get("path", "")
            ).strip():
                errors.append(f"assertions[{index}] (snapshot_field) requires path")

    if errors:
        raise SpecValidationError(errors)


def prepare_spec(spec: dict[str, Any], spec_dir: Path) -> dict[str, Any]:
    """Resolve libraries and named actions, then validate a copy of the spec."""
    if not isinstance(spec, dict):
        raise SpecValidationError(["Spec must be a JSON object"])

    sequences: dict[str, Any] = {}
    libraries = spec.get("action_libraries", [])
    if not isinstance(libraries, list) or not all(isinstance(item, str) for item in libraries):
        raise SpecValidationError(["action_libraries must be an array of path strings"])
    for library_ref in libraries:
        library_path = Path(library_ref)
        if not library_path.is_absolute():
            library_path = spec_dir / library_path
        library = _read_json_object(library_path.resolve(), "Action library")
        for sequence_name, sequence in _sequence_map(library, str(library_path)).items():
            if sequence_name in sequences:
                raise SpecValidationError(
                    [f"Duplicate action sequence '{sequence_name}' from {library_path}"]
                )
            sequences[sequence_name] = sequence

    for sequence_name, sequence in _sequence_map(spec, "spec").items():
        if sequence_name in sequences:
            raise SpecValidationError(
                [f"Local action sequence '{sequence_name}' duplicates a library sequence"]
            )
        sequences[sequence_name] = sequence

    prepared = copy.deepcopy(spec)
    prepared["actions"] = _expand_action_list(spec.get("actions", []), sequences, "actions")
    prepared["post_actions"] = _expand_action_list(
        spec.get("post_actions", []), sequences, "post_actions"
    )
    prepared.pop("action_libraries", None)
    prepared.pop("action_sequences", None)
    prepared.pop("sequences", None)
    validate_spec(prepared)
    return prepared


def load_and_prepare_spec(spec_path: Path) -> dict[str, Any]:
    """Load a run spec from disk, expand reusable actions, and validate it."""
    resolved_path = spec_path.resolve()
    spec = _read_json_object(resolved_path, "Run spec")
    return prepare_spec(spec, resolved_path.parent)
