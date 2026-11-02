extends SceneTree

const ContextGraphAdapterScript = preload(
	"res://addons/syntree/scripts/core/context_graph_adapter.gd"
)
const RelationshipRegistryScript = preload(
	"res://addons/syntree/scripts/core/context_graph_relationship_registry.gd"
)

var _failures: int = 0


class FakeContentState:
	extends RefCounted
	var sources: Dictionary = {}

	func get_source_data(source_id: String) -> Dictionary:
		return sources.get(source_id, {})


func _init() -> void:
	_test_v1_migration()
	_test_source_mapping()
	if _failures == 0:
		print("Context graph adapter tests: all passed")
		quit(0)
		return
	push_error("Context graph adapter tests: %d failure(s)" % _failures)
	quit(1)


func _test_v1_migration() -> void:
	var adapter: RefCounted = ContextGraphAdapterScript.new()
	var payload := {
		"schema_version": 1,
		"name": "Legacy context",
		"nodes": [
			{"id": "stack-a", "kind": "stack", "meta": {"name": "Stack A"}},
			{"id": "source-a", "kind": "content_source", "meta": {"name": "Source A"}},
		],
		"edges": [{"from": "stack-a", "to": "source-a", "kind": "stack_member"}],
		"selection": {"active_source_ids": ["stack-a"]},
	}
	var result: Dictionary = adapter.call("migrate_artifact", payload)
	var document: Dictionary = result.get("document", {})
	_expect(bool(result.get("ok", false)), "schema-v1 migration produced an invalid graph")
	_expect(bool(result.get("requires_commit", false)), "migration did not require an explicit commit")
	_expect(int(document.get("schema_version", 0)) == 2, "migration did not produce schema v2")
	_expect(
		document.get("edges", [])[0].get("relation", "") == "contains",
		"stack membership did not migrate to contains"
	)


func _test_source_mapping() -> void:
	var content_state := FakeContentState.new()
	content_state.sources = {
		"stack-a": _source("Stack A", true, ["source-a"], []),
		"source-a": _source("Source A", false, [], [
			_node("node-a", "Node A", ["node-b"]),
			_node("node-b", "Node B", []),
		]),
	}
	var source_a: Dictionary = content_state.sources["source-a"]
	var source_meta: Dictionary = source_a.get("meta", {})
	var ai_context: Dictionary = source_meta.get("ai_context", {})
	ai_context["context_sets"] = [{
		"id": "evidence",
		"label": "Evidence",
		"entry_node_ids": ["node-b"],
		"allowed_relationship_types": ["supports"],
		"traversal_depth": 1,
		"activation_rules": {"mode": "manual_only"},
		"budget_policy": {},
	}]
	source_meta["ai_context"] = ai_context
	source_a["meta"] = source_meta
	var source_content: Dictionary = source_a.get("content", {})
	var source_nodes: Array = source_content.get("nodes", [])
	var activated_node: Dictionary = source_nodes[0]
	activated_node["activation"] = {"mode": "always"}
	source_nodes[0] = activated_node
	source_content["nodes"] = source_nodes
	source_content["context_graph_edges"] = [
		RelationshipRegistryScript.make_edge(
			"supports",
			"node-b",
			"node-a",
			"Evidence",
			0.8
		)
	]
	source_a["content"] = source_content
	content_state.sources["source-a"] = source_a
	var adapter: RefCounted = ContextGraphAdapterScript.new()
	var source_ids: Array[String] = ["stack-a"]
	var result: Dictionary = adapter.call(
		"build_from_sources",
		content_state,
		source_ids,
		"Mapped context"
	)
	var document: Dictionary = result.get("document", {})
	_expect(bool(result.get("ok", false)), "source mapping produced an invalid graph")
	_expect(document.get("nodes", []).size() == 4, "source mapping omitted stack members or chunks")
	_expect(
		_has_edge(document.get("edges", []), "stack-a", "source-a", "contains"),
		"stack membership edge was not mapped"
	)
	_expect(
		_has_edge(document.get("edges", []), "source-a::node-a", "source-a::node-b", "contains"),
		"legacy child edge was not mapped"
	)
	_expect(
		_has_edge(document.get("edges", []), "source-a::node-b", "source-a::node-a", "supports"),
		"rich edge was not mapped into the artifact"
	)
	_expect(
		_has_context_set(
			document.get("context_sets", []),
			"source-a::evidence",
			"source-a::node-b"
		),
		"named context set was not mapped with stable artifact ids"
	)
	var mapped_node: Dictionary = _find_node(
		document.get("nodes", []),
		"source-a::node-a"
	)
	_expect(
		(mapped_node.get("activation", {}) as Dictionary).get("mode", "")
		== "always",
		"node activation was not mapped into the compiler document"
	)


func _source(
	source_label: String,
	is_stack: bool,
	stack_sources: Array,
	content_nodes: Array
) -> Dictionary:
	return {
		"meta": {
			"name": source_label,
			"source_type": "test",
			"ai_context": {
				"is_stack": is_stack,
				"stack_sources": stack_sources,
				"is_active": true,
				"metaprompt": false,
			},
		},
		"content": {"nodes": content_nodes},
	}


func _node(node_id: String, node_content: String, children: Array) -> Dictionary:
	return {
		"node_id": node_id,
		"content": node_content,
		"relationships": {
			"parents": [],
			"children": children,
			"dependencies": [],
			"associations": [],
		},
	}


func _has_edge(edges: Array, from_id: String, to_id: String, relation_id: String) -> bool:
	for edge_any in edges:
		var edge_data: Dictionary = edge_any
		if (
			str(edge_data.get("from", "")) == from_id
			and str(edge_data.get("to", "")) == to_id
			and str(edge_data.get("relation", "")) == relation_id
		):
			return true
	return false


func _has_context_set(
	context_sets: Array,
	context_set_id: String,
	entry_node_id: String
) -> bool:
	for context_set_any in context_sets:
		var context_set: Dictionary = context_set_any
		if (
			str(context_set.get("id", "")) == context_set_id
			and (context_set.get("entry_node_ids", []) as Array).has(
				entry_node_id
			)
		):
			return true
	return false


func _find_node(nodes: Array, node_id: String) -> Dictionary:
	for node_any in nodes:
		var node_data: Dictionary = node_any
		if str(node_data.get("id", "")) == node_id:
			return node_data
	return {}


func _expect(condition: bool, failure_message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(failure_message)
