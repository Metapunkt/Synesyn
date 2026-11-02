extends SceneTree

## Stage 11b: Thinking Map half of the "My Sessions" resume-live reload path
## (see test_workshop_catalyst_stage11.gd for the Session Record half, and
## why this is a separate file). Mirrors
## ControllerUtilsScript.reload_workshop_panels_from_state(): adapter.initialize()
## + refresh(), never mount() again (that would double-wire the panel's
## buttons).

const ThinkingMapControllerScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_thinking_map_controller.gd"
)
const MapScene = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_thinking_map.tscn"
)
const RecordStoreScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_session_record_store.gd"
)

var _failures: Array[String] = []


class FakeHub:
	extends Node

	func create_artifact_inline_json(
		_artifact_type: String, _payload: Dictionary, _metadata: Dictionary = {}
	) -> Dictionary:
		return {"ok": true, "id": "art_stub"}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_reload_rehydrates_thinking_map()
	_finish()


func _test_reload_rehydrates_thinking_map() -> void:
	var hub_node := FakeHub.new()
	root.add_child(hub_node)
	var map_panel_node: Control = MapScene.instantiate() as Control
	root.add_child(map_panel_node)
	var record_store: RefCounted = RecordStoreScript.new()
	record_store.initialize("sess_stage11b")
	var map_controller: RefCounted = ThinkingMapControllerScript.new()
	_expect(
		map_controller.mount(
			map_panel_node, hub_node, record_store, "sess_stage11b", "scenario", {}
		),
		"Thinking Map controller did not mount for reload test"
	)
	map_controller.ingest_specialist_candidate_batch({
		"status": "complete",
		"turn_id": "turn_1",
		"trace_ref": "specialist-trace:turn_1",
		"created_at": "2026-08-01T10:00:00Z",
		# `category` and `proposition`, matching what
		# WorkshopSpecialistCoordinator._normalize_map_candidate emits and what
		# ThinkingMapAdapter.specialist_candidate_command reads. An earlier fixture here used
		# `kind`/`text`, which the ingest path rejects as invalid_map_category — harmless
		# while this file could not compile under `--headless --script`, and wrong the moment
		# it could.
		"map_candidates": [{
			"id": "cause-before",
			"category": "cause",
			"proposition": "Initial cause before resume",
			"source_class": "participant_said",
			"source_refs": ["trace-1"],
			"evidence_status": "unsupported",
		}],
	})
	var preview_button_node: Button = map_panel_node.get_node_or_null(
		"%PreviewMapButton"
	) as Button
	_expect(
		preview_button_node != null and preview_button_node.pressed.get_connections().size() == 1,
		"Thinking Map preview button should have exactly one connection after mount"
	)
	var causes_items_before: VBoxContainer = map_panel_node.get_node_or_null(
		"%CausesItems"
	) as VBoxContainer
	_expect(
		causes_items_before.get_child_count() == 1,
		"Thinking Map did not render the pre-resume cause card"
	)

	var adapter: RefCounted = map_controller.get_adapter()
	var resumed_map_state: Dictionary = adapter.get_state()
	var resumed_document: Dictionary = resumed_map_state.get("document", {})
	# Overwrite with a distinct "resumed" node so we can tell reload actually
	# replaced the document rather than appending to it.
	# A stored node, not a candidate: the document keeps `kind` and `label`.
	resumed_document["nodes"] = [{
		"id": "cause-after",
		"kind": "cause",
		"label": "Resumed cause after reload",
		"source_class": "participant_said",
		"status": "accepted",
		"provenance_refs": [],
	}]
	resumed_map_state["document"] = resumed_document
	adapter.initialize("sess_stage11b", "scenario", "decision_triage", resumed_map_state)
	map_controller.refresh()

	var causes_items_after: VBoxContainer = map_panel_node.get_node_or_null(
		"%CausesItems"
	) as VBoxContainer
	_expect(
		causes_items_after.get_child_count() == 1,
		"Thinking Map reload did not re-render exactly one card"
	)
	_expect(
		preview_button_node.pressed.get_connections().size() == 1,
		"Thinking Map reload duplicated a button signal connection"
	)

	map_panel_node.queue_free()
	hub_node.queue_free()
	await process_frame


func _expect(condition: bool, failure_message: String) -> void:
	if condition:
		return
	_failures.append(failure_message)
	push_error(failure_message)


func _finish() -> void:
	if _failures.is_empty():
		print("Workshop Catalyst Stage 11b tests: all passed")
		quit(0)
	else:
		push_error("Workshop Catalyst Stage 11b: %d failure(s)" % _failures.size())
		quit(1)
