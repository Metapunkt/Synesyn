extends SceneTree

const ContentStateResourceScript = preload(
	"res://addons/syntree/scripts/resources/content_state_resource.gd"
)
const RelationshipRegistryScript = preload(
	"res://addons/syntree/scripts/core/context_graph_relationship_registry.gd"
)

var _failures: int = 0


class NoSaveContentSource:
	extends ContentSourceResource

	func save_source(_source_id: String) -> bool:
		return true


func _init() -> void:
	var state: ContentStateResource = _make_state()
	var contains_edge: Dictionary = RelationshipRegistryScript.make_edge(
		"contains",
		"node-a",
		"node-b"
	)
	var insert_result: Dictionary = state.upsert_context_graph_edge(
		"source-a",
		contains_edge
	)
	_expect(bool(insert_result.get("success", false)), "rich containment edge was not persisted")
	var source_data: Dictionary = state.get_source_data("source-a")
	var nodes: Array = source_data.get("content", {}).get("nodes", [])
	var first_relationships: Dictionary = nodes[0].get("relationships", {})
	_expect(
		first_relationships.get("children", []).has("node-b"),
		"rich containment edge was not mirrored for Hierarchy"
	)
	var supports_edge: Dictionary = RelationshipRegistryScript.make_edge(
		"supports",
		"node-b",
		"node-a",
		"Corroborating passage",
		0.9,
		["source:source-a"]
	)
	var supports_result: Dictionary = state.upsert_context_graph_edge(
		"source-a",
		supports_edge
	)
	_expect(bool(supports_result.get("success", false)), "evidential edge was not persisted")
	var projected_edges: Array = state.get_context_graph_edges("source-a", true)
	_expect(projected_edges.size() == 2, "rich and legacy projection produced duplicates")
	var remove_result: Dictionary = state.remove_context_graph_edge(
		"source-a",
		str(contains_edge.get("id", ""))
	)
	_expect(bool(remove_result.get("success", false)), "rich edge removal failed")
	source_data = state.get_source_data("source-a")
	nodes = source_data.get("content", {}).get("nodes", [])
	first_relationships = nodes[0].get("relationships", {})
	_expect(
		not first_relationships.get("children", []).has("node-b"),
		"rich containment removal was not mirrored for Hierarchy"
	)
	_expect(
		state.add_edge("child", "node-a", "node-b"),
		"legacy containment fixture could not be added"
	)
	var projected_legacy: Array = state.get_context_graph_edges("source-a", true)
	var legacy_edge_id: String = ""
	for projected_any in projected_legacy:
		var projected_edge: Dictionary = projected_any
		if str(projected_edge.get("relation", "")) == "contains":
			legacy_edge_id = str(projected_edge.get("id", ""))
			break
	var legacy_remove: Dictionary = state.remove_context_graph_edge(
		"source-a",
		legacy_edge_id
	)
	_expect(
		bool(legacy_remove.get("success", false)),
		"projected legacy relationship could not be removed"
	)
	var stack_node_ids: Array[String] = [
		"source-a__node-a",
		"source-a__node-b",
	]
	var stack_edge: Dictionary = RelationshipRegistryScript.make_edge(
		"supports",
		stack_node_ids[0],
		stack_node_ids[1]
	)
	var stack_insert: Dictionary = state.upsert_stack_context_graph_edge(
		"stack-a",
		stack_edge,
		stack_node_ids
	)
	_expect(bool(stack_insert.get("success", false)), "typed stack edge was not persisted")
	_expect(
		state.get_stack_context_graph_edges("stack-a").size() == 1,
		"typed stack edge did not round trip"
	)
	_expect(
		state.get_stack_edges("stack-a").size() == 1,
		"typed stack edge was not mirrored for legacy rendering"
	)
	_expect(
		state.get_stack_structural_edges("stack-a").is_empty(),
		"semantic stack edge leaked into structural ordering"
	)
	var stack_remove: Dictionary = state.remove_stack_context_graph_edge(
		"stack-a",
		str(stack_edge.get("id", ""))
	)
	_expect(bool(stack_remove.get("success", false)), "typed stack edge removal failed")
	_expect(state.get_stack_edges("stack-a").is_empty(), "typed stack mirror was not removed")
	if _failures == 0:
		print("Context graph edge persistence tests: all passed")
		quit(0)
		return
	push_error("Context graph edge persistence tests: %d failure(s)" % _failures)
	quit(1)


func _make_state() -> ContentStateResource:
	var state: ContentStateResource = ContentStateResourceScript.new()
	var source := NoSaveContentSource.new()
	source.sources_directory = "user://syntree_context_graph_edge_tests"
	state.content_source = source
	source.add_or_update_source_data({
		"format_version": "1.0.0",
		"meta": {
			"source_id": "source-a",
			"name": "Source A",
			"path": "user://syntree_context_graph_edge_tests/source-a.json",
			"ai_context": {"is_active": true, "metaprompt": false, "is_stack": false},
		},
		"content": {
			"nodes": [
				_node("node-a"),
				_node("node-b"),
			],
		},
	})
	source.add_or_update_source_data({
		"format_version": "1.0.0",
		"meta": {
			"source_id": "stack-a",
			"name": "Stack A",
			"path": "user://syntree_context_graph_edge_tests/stack-a.json",
			"ai_context": {
				"is_active": true,
				"metaprompt": false,
				"is_stack": true,
				"stack_sources": ["source-a"],
				"stack_edges": [],
			},
		},
		"content": {"nodes": []},
	})
	return state


func _node(node_id: String) -> Dictionary:
	return {
		"node_id": node_id,
		"content": node_id,
		"relationships": {
			"parents": [],
			"children": [],
			"dependencies": [],
			"associations": [],
		},
	}


func _expect(condition: bool, failure_message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(failure_message)
