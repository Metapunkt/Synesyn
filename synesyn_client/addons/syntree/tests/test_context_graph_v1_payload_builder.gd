extends SceneTree

const ContextGraphV1PayloadBuilderScript = preload(
	"res://addons/syntree/scripts/ui/panel/internal/context_graph_v1_payload_builder.gd"
)


class FakeContentState:
	extends RefCounted

	var sources: Dictionary = {
		"source_a": {
			"meta": {
				"name": "Source A",
				"source_type": "txt",
				"ai_context": {
					"is_active": false,
					"metaprompt": true,
					"is_stack": false,
				},
			},
			"content": {"nodes": []},
		},
		"source_b": {
			"meta": {
				"name": "Source B",
				"source_type": "md",
				"ai_context": {
					"is_active": false,
					"metaprompt": false,
					"is_stack": false,
				},
			},
			"content": {"nodes": []},
		},
		"stack_a": {
			"meta": {
				"name": "Stack A",
				"source_type": "stack",
				"ai_context": {
					"is_active": true,
					"metaprompt": false,
					"is_stack": true,
					"stack_sources": [
						{"id": "source_a"},
						"source_b",
					],
				},
			},
			"content": {"nodes": []},
		},
	}

	func get_source_data(source_id: String) -> Dictionary:
		return sources.get(source_id, {})


func _init() -> void:
	var failures: int = _test_existing_v1_shape()
	if failures == 0:
		print("Context graph v1 payload builder tests: PASS")
		quit(0)
		return
	push_error("Context graph v1 payload builder tests: %d failure(s)" % failures)
	quit(1)


func _test_existing_v1_shape() -> int:
	var builder: RefCounted = ContextGraphV1PayloadBuilderScript.new()
	var state := FakeContentState.new()
	var active_source_ids: Array[String] = ["stack_a"]
	var source_ids: Array = builder.collect_source_ids(
		state,
		active_source_ids
	)
	var failures: int = _expect(
		source_ids == ["source_a", "source_b", "stack_a"],
		"active stack members were not collected and sorted"
	)

	var nodes: Array = []
	var edges: Array = []
	for source_id_any in source_ids:
		builder.append_source(state, str(source_id_any), nodes, edges)
	var payload: Dictionary = builder.make_payload(
		active_source_ids,
		nodes,
		edges,
		"2026-07-10T19:00:00"
	)
	failures += _expect(
		int(payload.get("schema_version", 0)) == 1
		and not payload.has("graph_schema_version"),
		"existing context graph schema version changed"
	)
	failures += _expect(
		(payload.get("selection", {}) as Dictionary)
			.get("active_source_ids", []) == ["stack_a"],
		"active source selection changed"
	)
	failures += _expect(nodes.size() == 3, "payload node count changed")
	failures += _expect(
		edges == [
			{
				"from": "stack_a",
				"to": "source_a",
				"kind": "stack_member",
			},
			{
				"from": "stack_a",
				"to": "source_b",
				"kind": "stack_member",
			},
		],
		"existing stack-member edge shape changed"
	)
	var serialized: String = JSON.stringify(payload)
	var parsed_any: Variant = JSON.parse_string(serialized)
	var parsed: Dictionary = (
		parsed_any as Dictionary
		if typeof(parsed_any) == TYPE_DICTIONARY
		else {}
	)
	failures += _expect(
		not parsed.is_empty()
		and int(parsed.get("schema_version", 0)) == 1
		and (parsed.get("nodes", []) as Array).size() == nodes.size()
		and parsed.get("edges", []) == edges
		and (parsed.get("selection", {}) as Dictionary)
			.get("active_source_ids", []) == ["stack_a"],
		"existing context graph payload failed JSON round trip"
	)
	return failures


func _expect(condition: bool, failure_message: String) -> int:
	if condition:
		return 0
	push_error(failure_message)
	return 1
