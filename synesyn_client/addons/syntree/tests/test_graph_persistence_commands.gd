extends SceneTree

const GraphPersistenceCommandsScript = preload(
	"res://addons/syntree/scripts/ui/content_graph/internal/graph_persistence_commands.gd"
)


class FakeContentState:
	extends RefCounted

	var last_method: String = ""
	var last_args: Array = []
	var stack_edges: Array = []

	func set_stack_layout_position(
		stack_id: String,
		node_id: String,
		node_position: Vector2
	) -> bool:
		last_method = "set_stack_layout_position"
		last_args = [stack_id, node_id, node_position]
		return true

	func update_node_position(node_id: String, node_position: Vector2) -> bool:
		last_method = "update_node_position"
		last_args = [node_id, node_position]
		return true

	func add_edge(
		edge_kind: String,
		from_id: String,
		to_id: String
	) -> bool:
		last_method = "add_edge"
		last_args = [edge_kind, from_id, to_id]
		return true

	func remove_edge(
		edge_kind: String,
		from_id: String,
		to_id: String
	) -> bool:
		last_method = "remove_edge"
		last_args = [edge_kind, from_id, to_id]
		return true

	func add_stack_edge(
		stack_id: String,
		from_id: String,
		to_id: String
	) -> bool:
		last_method = "add_stack_edge"
		last_args = [stack_id, from_id, to_id]
		var new_edge: Dictionary = {"from": from_id, "to": to_id}
		if not stack_edges.has(new_edge):
			stack_edges.append(new_edge)
		return true

	func remove_stack_edge(
		stack_id: String,
		from_id: String,
		to_id: String
	) -> bool:
		last_method = "remove_stack_edge"
		last_args = [stack_id, from_id, to_id]
		stack_edges = stack_edges.filter(
			func(edge_any: Variant) -> bool:
				if not edge_any is Dictionary:
					return true
				var edge_data: Dictionary = edge_any
				return (
					str(edge_data.get("from", "")) != from_id
					or str(edge_data.get("to", "")) != to_id
				)
		)
		return true

	func get_stack_edges(_stack_id: String) -> Array:
		return stack_edges.duplicate(true)

	func set_stack_edges(stack_id: String, new_edges: Array) -> bool:
		last_method = "set_stack_edges"
		last_args = [stack_id, new_edges.duplicate(true)]
		stack_edges = new_edges.duplicate(true)
		return true


func _init() -> void:
	var failures: int = 0
	failures += _test_member_position_routing()
	failures += _test_stack_position_routing()
	failures += _test_legacy_child_edge_routing()
	failures += _test_stack_edge_deduplication_and_removal()
	if failures == 0:
		print("Graph persistence command tests: PASS")
		quit(0)
		return
	push_error("Graph persistence command tests: %d failure(s)" % failures)
	quit(1)


func _test_member_position_routing() -> int:
	var commands: RefCounted = GraphPersistenceCommandsScript.new()
	var state := FakeContentState.new()
	var succeeded: bool = commands.persist_node_position(
		state,
		false,
		"",
		"node_a",
		Vector2(10.0, 20.0)
	)
	return _expect(
		succeeded
		and state.last_method == "update_node_position"
		and state.last_args == ["node_a", Vector2(10.0, 20.0)],
		"member node position did not route to update_node_position"
	)


func _test_stack_position_routing() -> int:
	var commands: RefCounted = GraphPersistenceCommandsScript.new()
	var state := FakeContentState.new()
	var succeeded: bool = commands.persist_node_position(
		state,
		true,
		"stack_a",
		"source_a::node_a",
		Vector2(30.0, 40.0)
	)
	return _expect(
		succeeded
		and state.last_method == "set_stack_layout_position"
		and state.last_args == [
			"stack_a",
			"source_a::node_a",
			Vector2(30.0, 40.0),
		],
		"stack node position did not route to stack layout persistence"
	)


func _test_legacy_child_edge_routing() -> int:
	var commands: RefCounted = GraphPersistenceCommandsScript.new()
	var state := FakeContentState.new()
	var add_succeeded: bool = commands.connect_nodes(
		state,
		false,
		"",
		"node_a",
		"node_b"
	)
	var failures: int = _expect(
		add_succeeded
		and state.last_method == "add_edge"
		and state.last_args == ["child", "node_a", "node_b"],
		"ordinary connection no longer routes to legacy child edge"
	)
	var remove_succeeded: bool = commands.disconnect_nodes(
		state,
		false,
		"",
		"node_a",
		"node_b"
	)
	failures += _expect(
		remove_succeeded
		and state.last_method == "remove_edge"
		and state.last_args == ["child", "node_a", "node_b"],
		"ordinary disconnection no longer removes legacy child edge"
	)
	return failures


func _test_stack_edge_deduplication_and_removal() -> int:
	var commands: RefCounted = GraphPersistenceCommandsScript.new()
	var state := FakeContentState.new()
	var first_add: bool = commands.connect_nodes(
		state,
		true,
		"stack_a",
		"source_a::node_a",
		"source_b::node_b"
	)
	var second_add: bool = commands.connect_nodes(
		state,
		true,
		"stack_a",
		"source_a::node_a",
		"source_b::node_b"
	)
	var failures: int = _expect(
		first_add and second_add and state.stack_edges.size() == 1,
		"stack connection was not deduplicated"
	)
	var removed: bool = commands.disconnect_nodes(
		state,
		true,
		"stack_a",
		"source_a::node_a",
		"source_b::node_b"
	)
	failures += _expect(
		removed and state.stack_edges.is_empty(),
		"stack connection was not removed"
	)
	return failures


func _expect(condition: bool, failure_message: String) -> int:
	if condition:
		return 0
	push_error(failure_message)
	return 1
