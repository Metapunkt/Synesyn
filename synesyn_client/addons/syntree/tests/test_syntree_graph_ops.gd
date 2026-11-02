extends SceneTree

const ContentEdgeOpsScript = preload(
	"res://addons/syntree/scripts/resources/internal/content_edge_ops.gd"
)
const ContentStackOpsScript = preload(
	"res://addons/syntree/scripts/resources/internal/content_stack_ops.gd"
)
const ContentNodePersistenceOpsScript = preload(
	"res://addons/syntree/scripts/resources/internal/content_node_persistence_ops.gd"
)

const REL_PARENTS: String = "parents"
const REL_CHILDREN: String = "children"
const REL_DEPENDENCIES: String = "dependencies"
const REL_ASSOCIATIONS: String = "associations"
const STACK_EDGES_KEY: String = "stack_edges"
const STACK_LAYOUT_KEY: String = "stack_layout"
const STACK_LAYOUT_POSITIONS_KEY: String = "node_positions"


func _init() -> void:
	var failures: int = 0
	failures += _test_child_edge_add_remove()
	failures += _test_typed_legacy_edge_sets()
	failures += _test_stack_edges_and_layout()
	failures += _test_node_position()
	if failures == 0:
		print("SynTree graph ops tests: PASS")
		quit(0)
		return
	push_error("SynTree graph ops tests: %d failure(s)" % failures)
	quit(1)


func _test_child_edge_add_remove() -> int:
	var edge_ops: RefCounted = ContentEdgeOpsScript.new()
	var nodes: Array = _make_nodes()
	var add_result: Dictionary = edge_ops.mutate_edge(
		nodes,
		"child",
		"node_a",
		"node_b",
		true,
		REL_PARENTS,
		REL_CHILDREN,
		REL_DEPENDENCIES,
		REL_ASSOCIATIONS
	)
	var added_nodes: Array = add_result.get("nodes", [])
	var node_a: Dictionary = added_nodes[0]
	var node_b: Dictionary = added_nodes[1]
	var failures: int = 0
	failures += _expect(
		bool(add_result.get("success", false))
		and (node_a.get("relationships", {}) as Dictionary)
			.get(REL_CHILDREN, []).has("node_b"),
		"child edge was not added"
	)
	failures += _expect(
		(node_b.get("relationships", {}) as Dictionary)
			.get(REL_PARENTS, []).has("node_a"),
		"inverse parent relationship was not added"
	)

	var remove_result: Dictionary = edge_ops.mutate_edge(
		added_nodes,
		"child",
		"node_a",
		"node_b",
		false,
		REL_PARENTS,
		REL_CHILDREN,
		REL_DEPENDENCIES,
		REL_ASSOCIATIONS
	)
	var removed_nodes: Array = remove_result.get("nodes", [])
	node_a = removed_nodes[0]
	node_b = removed_nodes[1]
	failures += _expect(
		not (node_a.get("relationships", {}) as Dictionary)
			.get(REL_CHILDREN, []).has("node_b")
		and not (node_b.get("relationships", {}) as Dictionary)
			.get(REL_PARENTS, []).has("node_a"),
		"child edge was not removed symmetrically"
	)
	return failures


func _test_typed_legacy_edge_sets() -> int:
	var edge_ops: RefCounted = ContentEdgeOpsScript.new()
	var failures: int = 0
	for edge_kind in ["depends", "assoc"]:
		var nodes: Array = _make_nodes()
		var result: Dictionary = edge_ops.mutate_edge(
			nodes,
			edge_kind,
			"node_a",
			"node_b",
			true,
			REL_PARENTS,
			REL_CHILDREN,
			REL_DEPENDENCIES,
			REL_ASSOCIATIONS
		)
		var changed_nodes: Array = result.get("nodes", [])
		var changed_node: Dictionary = changed_nodes[0]
		var relationship_key: String = (
			REL_DEPENDENCIES if edge_kind == "depends" else REL_ASSOCIATIONS
		)
		failures += _expect(
			bool(result.get("success", false))
			and (changed_node.get("relationships", {}) as Dictionary)
				.get(relationship_key, []).has("node_b"),
			"%s edge was not stored in %s" % [edge_kind, relationship_key]
		)
	return failures


func _test_stack_edges_and_layout() -> int:
	var stack_ops: RefCounted = ContentStackOpsScript.new()
	var stack_data: Dictionary = {"meta": {"ai_context": {}}}
	var edges: Array = [{"from": "source_a::node_a", "to": "source_b::node_b"}]
	var initial_edges: Array = edges.duplicate(true)
	var edge_result: Dictionary = stack_ops.set_stack_edges_data(
		stack_data,
		STACK_EDGES_KEY,
		edges
	)
	var edge_data: Dictionary = edge_result.get("data", {})
	var ai_context: Dictionary = edge_data.get("meta", {}).get("ai_context", {})
	var failures: int = 0
	failures += _expect(
		bool(edge_result.get("success", false))
		and ai_context.get(STACK_EDGES_KEY, []) == edges,
		"stack edges were not stored"
	)
	var add_result: Dictionary = stack_ops.add_stack_edge_data(
		edge_data,
		STACK_EDGES_KEY,
		"source_b::node_b",
		"source_c::node_c"
	)
	var add_data: Dictionary = add_result.get("data", {})
	ai_context = add_data.get("meta", {}).get("ai_context", {})
	failures += _expect(
		bool(add_result.get("success", false))
		and bool(add_result.get("changed", false))
		and (ai_context.get(STACK_EDGES_KEY, []) as Array).size() == 2,
		"incremental stack edge was not added"
	)
	var duplicate_result: Dictionary = stack_ops.add_stack_edge_data(
		add_data,
		STACK_EDGES_KEY,
		"source_b::node_b",
		"source_c::node_c"
	)
	failures += _expect(
		bool(duplicate_result.get("success", false))
		and not bool(duplicate_result.get("changed", true)),
		"duplicate stack edge was not ignored"
	)
	var remove_result: Dictionary = stack_ops.remove_stack_edge_data(
		add_data,
		STACK_EDGES_KEY,
		"source_b::node_b",
		"source_c::node_c"
	)
	var remove_data: Dictionary = remove_result.get("data", {})
	ai_context = remove_data.get("meta", {}).get("ai_context", {})
	failures += _expect(
		bool(remove_result.get("success", false))
		and bool(remove_result.get("changed", false))
		and ai_context.get(STACK_EDGES_KEY, []) == initial_edges,
		"incremental stack edge was not removed"
	)

	var layout_result: Dictionary = stack_ops.set_stack_layout_position_data(
		remove_data,
		STACK_LAYOUT_KEY,
		STACK_LAYOUT_POSITIONS_KEY,
		"source_a::node_a",
		Vector2(42.0, 84.0)
	)
	var layout_data: Dictionary = layout_result.get("data", {})
	ai_context = layout_data.get("meta", {}).get("ai_context", {})
	var graph_layout: Dictionary = ai_context.get(STACK_LAYOUT_KEY, {})
	var positions: Dictionary = graph_layout.get(
		STACK_LAYOUT_POSITIONS_KEY,
		{}
	)
	failures += _expect(
		positions.get("source_a::node_a", {}) == {"x": 42.0, "y": 84.0},
		"stack layout position was not stored"
	)
	return failures


func _test_node_position() -> int:
	var position_ops: RefCounted = ContentNodePersistenceOpsScript.new()
	var result: Dictionary = position_ops.set_node_position(
		_make_nodes(),
		"node_b",
		Vector2(12.0, 34.0)
	)
	var nodes: Array = result.get("nodes", [])
	var node_b: Dictionary = nodes[1]
	return _expect(
		bool(result.get("success", false))
		and node_b.get("position", {}) == {"x": 12.0, "y": 34.0},
		"node position was not stored"
	)


func _make_nodes() -> Array:
	return [
		{
			"node_id": "node_a",
			"relationships": {
				REL_PARENTS: [],
				REL_CHILDREN: [],
				REL_DEPENDENCIES: [],
				REL_ASSOCIATIONS: [],
			},
		},
		{
			"node_id": "node_b",
			"relationships": {
				REL_PARENTS: [],
				REL_CHILDREN: [],
				REL_DEPENDENCIES: [],
				REL_ASSOCIATIONS: [],
			},
		},
	]


func _expect(condition: bool, failure_message: String) -> int:
	if condition:
		return 0
	push_error(failure_message)
	return 1
