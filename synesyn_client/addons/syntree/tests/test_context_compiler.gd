extends SceneTree

const ContextCompilerScript = preload(
	"res://addons/syntree/scripts/core/context_compiler.gd"
)

var _failures: int = 0


func _init() -> void:
	_test_deterministic_traversal()
	_test_budget_and_pinned_content()
	_test_rejected_content()
	if _failures == 0:
		print("Context compiler tests: all passed")
		quit(0)
		return
	push_error("Context compiler tests: %d failure(s)" % _failures)
	quit(1)


func _test_deterministic_traversal() -> void:
	var compiler: RefCounted = ContextCompilerScript.new()
	var document: Dictionary = _document()
	var context_set: Dictionary = {
		"id": "test-set",
		"entry_node_ids": ["a"],
		"traversal_depth": 2,
		"allowed_relationship_types": ["contains", "supports"],
		"budget_policy": {"max_tokens": 100},
	}
	var first: Dictionary = compiler.call("compile", document, context_set, {})
	var second: Dictionary = compiler.call("compile", document, context_set, {})
	_expect(first == second, "same compiler inputs produced different outputs")
	_expect(
		first.get("compiled_text", "") == "Alpha\n\nBeta\n\nGamma",
		"compiler traversal or ordering changed"
	)
	var included: Array = first.get("included_nodes", [])
	_expect(
		included[1].get("reason", "") == "via:contains"
		and included[2].get("traversal_path", []) == ["a", "b", "c"],
		"compiler omitted inclusion reasons or traversal paths"
	)


func _test_budget_and_pinned_content() -> void:
	var compiler: RefCounted = ContextCompilerScript.new()
	var context_set: Dictionary = {
		"id": "budget-set",
		"entry_node_ids": ["a"],
		"traversal_depth": 2,
		"allowed_relationship_types": [],
	}
	var options: Dictionary = {
		"max_tokens": 1,
		"pinned_node_ids": ["c"],
		"model_id": "test-model",
	}
	var result: Dictionary = compiler.call(
		"compile",
		_document(),
		context_set,
		options
	)
	var included: Array = result.get("included_nodes", [])
	var omitted: Array = result.get("omitted_nodes", [])
	_expect(
		included.size() == 1
		and included[0].get("node_id", "") == "c"
		and included[0].get("reason", "") == "pinned",
		"pinned content was silently dropped by the budget"
	)
	_expect(
		omitted.size() == 2
		and omitted[0].get("reason", "") == "token_budget",
		"budget omissions were not explained"
	)


func _test_rejected_content() -> void:
	var compiler: RefCounted = ContextCompilerScript.new()
	var document: Dictionary = _document()
	document["nodes"][1]["status"] = "rejected"
	var context_set: Dictionary = {
		"id": "review-set",
		"entry_node_ids": ["a"],
		"traversal_depth": 1,
		"allowed_relationship_types": ["contains"],
	}
	var result: Dictionary = compiler.call("compile", document, context_set, {})
	var omitted: Array = result.get("omitted_nodes", [])
	_expect(
		omitted.size() == 1
		and omitted[0].get("node_id", "") == "b"
		and omitted[0].get("reason", "") == "rejected",
		"rejected content entered compiled context"
	)


func _document() -> Dictionary:
	return {
		"graph_schema_version": 1,
		"graph_kind": "context_graph",
		"nodes": [
			_node("a", "Alpha"),
			_node("b", "Beta"),
			_node("c", "Gamma"),
		],
		"edges": [
			_edge("edge-a-b", "a", "b", "contains"),
			_edge("edge-b-c", "b", "c", "supports"),
		],
	}


func _node(node_id: String, node_label: String) -> Dictionary:
	return {
		"id": node_id,
		"kind": "chunk",
		"label": node_label,
		"status": "committed",
		"provenance_refs": [],
	}


func _edge(
	edge_id: String,
	from_id: String,
	to_id: String,
	relation_id: String
) -> Dictionary:
	return {
		"id": edge_id,
		"from": from_id,
		"to": to_id,
		"relation": relation_id,
		"status": "committed",
		"provenance_refs": [],
	}


func _expect(condition: bool, failure_message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(failure_message)
