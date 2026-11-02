extends SceneTree

const GraphDocumentScript = preload(
	"res://addons/synesyn_core/scripts/graph_workspace/graph_workspace_document.gd"
)
const CONTEXT_ADAPTER_PATH := "res://addons/syntree/scripts/core/context_graph_adapter.gd"
const THINKING_ADAPTER_PATH := (
	"res://ScenSyn/session_types/workshop_catalyst/thinking_map_adapter.gd"
)

var _failures: Array[String] = []


func _init() -> void:
	var fixture_text: String = FileAccess.get_file_as_string(
		"res://addons/synesyn_core/scripts/graph_workspace/tests/fixtures/adapter_conformance_v1.json"
	)
	var fixture_any: Variant = JSON.parse_string(fixture_text)
	if typeof(fixture_any) != TYPE_DICTIONARY:
		_fail("Conformance fixture could not be read")
		_finish()
		return
	var fixture: Dictionary = fixture_any
	_test_both_adapters(fixture)
	_finish()


func _test_both_adapters(fixture: Dictionary) -> void:
	## Product adapters live outside synesyn_core; skip when absent (drop-in core).
	if not ResourceLoader.exists(CONTEXT_ADAPTER_PATH):
		print("SKIP ContextGraphAdapter — SynTree not present")
		return
	if not ResourceLoader.exists(THINKING_ADAPTER_PATH):
		print("SKIP ThinkingMapAdapter — ScenSyn host not present")
		return
	var ContextAdapterScript: Script = load(CONTEXT_ADAPTER_PATH) as Script
	var ThinkingAdapterScript: Script = load(THINKING_ADAPTER_PATH) as Script
	if ContextAdapterScript == null or ThinkingAdapterScript == null:
		_fail("Adapter scripts failed to load")
		return
	var records: Array = fixture.get("records", [])
	var edge_fixture: Dictionary = fixture.get("edge", {})
	var context_document: Dictionary = {
		"schema_version": 2,
		"graph_schema_version": 1,
		"graph_kind": "context_graph",
		"name": "Conformance context",
		"nodes": [
			_record_node(records[0], "chunk"),
			_record_node(records[1], "chunk"),
		],
		"edges": [_record_edge(edge_fixture, "supports")],
	}
	var context_adapter: RefCounted = ContextAdapterScript.new() as RefCounted
	var context_result: Dictionary = context_adapter.call("migrate_artifact", context_document)
	_expect(bool(context_result.get("ok", false)), "ContextGraphAdapter rejected shared envelope")

	var thinking_adapter: RefCounted = ThinkingAdapterScript.new() as RefCounted
	thinking_adapter.call("initialize", "sess_conformance")
	var commands: Array = [
		{
			"operation": "propose_node",
			"id": String(records[0]["id"]),
			"category": "cause",
			"label": String(records[0]["label"]),
			"source_class": "participant_said",
			"provenance_refs": records[0]["provenance_refs"],
			"provenance": {"review_status": "unreviewed"},
		},
		{
			"operation": "propose_node",
			"id": String(records[1]["id"]),
			"category": "effect",
			"label": String(records[1]["label"]),
			"source_class": "ai_inferred",
			"provenance_refs": records[1]["provenance_refs"],
			"provenance": {"review_status": "unreviewed", "evidence_status": "unsupported"},
		},
		{
			"operation": "propose_edge",
			"id": String(edge_fixture["id"]),
			"from": String(edge_fixture["from"]),
			"to": String(edge_fixture["to"]),
			"relation": "causes",
			"confidence": 0.7,
			"provenance_refs": ["trace:fixture-edge"],
		},
	]
	var map_result: Dictionary = thinking_adapter.call("apply_command_batch", "fixture", commands)
	_expect(bool(map_result.get("ok", false)), "ThinkingMapAdapter rejected shared envelope")
	var map_document: Dictionary = thinking_adapter.call("get_document")
	_expect(
		bool(GraphDocumentScript.validate(map_document, "workshop_thinking_map").get("ok", false)),
		"Thinking Map did not conform to Graph Workspace validation"
	)
	_expect(
		context_result["document"]["graph_kind"] == "context_graph"
		and map_document["graph_kind"] == "workshop_thinking_map",
		"Product graph kinds were not kept distinct"
	)
	var with_layout: Dictionary = map_document.duplicate(true)
	with_layout["viewport"] = {"zoom": 2.0}
	var diff: Dictionary = GraphDocumentScript.semantic_diff(map_document, with_layout)
	_expect(
		(diff["nodes"]["changed"] as Array).is_empty()
		and (diff["edges"]["changed"] as Array).is_empty(),
		"Shared semantic diff included transient layout"
	)


func _record_node(fixture_record: Dictionary, kind_id: String) -> Dictionary:
	return {
		"id": String(fixture_record["id"]),
		"kind": kind_id,
		"label": String(fixture_record["label"]),
		"status": "suggested",
		"provenance_refs": fixture_record["provenance_refs"],
	}


func _record_edge(fixture_edge: Dictionary, relation_id: String) -> Dictionary:
	return {
		"id": String(fixture_edge["id"]),
		"from": String(fixture_edge["from"]),
		"to": String(fixture_edge["to"]),
		"relation": relation_id,
		"status": "suggested",
		"provenance_refs": ["trace:fixture-edge"],
	}


func _expect(condition: bool, failure_message: String) -> void:
	if not condition:
		_fail(failure_message)


func _fail(failure_message: String) -> void:
	_failures.append(failure_message)
	push_error(failure_message)


func _finish() -> void:
	if _failures.is_empty():
		print("Graph Workspace adapter conformance tests: all passed")
		quit(0)
	else:
		push_error("Graph Workspace adapter conformance: %d failure(s)" % _failures.size())
		quit(1)
