## Purpose: GraphRenderer (script)
@tool
class_name GraphRenderer
extends RefCounted

const RelationshipRegistryScript = preload(
	"res://addons/syntree/scripts/core/context_graph_relationship_registry.gd"
)

# GraphEdit mutation helper for ContentGraphController.
# IMPORTANT:
# - No signals.
# - No ContentState reads.
# - Controller remains the only signal owner / orchestrator.

func add_node_to_graph(graph_view: GraphEdit, node: Node, pos: Vector2, is_active: bool, is_metaprompt: bool) -> void:
	if not is_instance_valid(graph_view) or not is_instance_valid(node):
		return
	if node.get_parent() != graph_view:
		graph_view.add_child(node)
	if node is GraphNode:
		(node as GraphNode).position_offset = pos
	if node is ContentSourceGraphNode:
		(node as ContentSourceGraphNode).set_active_state(is_active)
		(node as ContentSourceGraphNode).set_metaprompt_state(is_metaprompt)

func connect_children_edges(graph_view: GraphEdit, created_nodes: Dictionary, nodes: Array) -> void:
	if not is_instance_valid(graph_view):
		return
	for node_data in nodes:
		if not (node_data is Dictionary):
			continue
		var node_id := str((node_data as Dictionary).get("node_id", "")).strip_edges()
		if node_id.is_empty() or not created_nodes.has(node_id):
			continue
		var relationships: Dictionary = (node_data as Dictionary).get("relationships", {})
		var children: Array = relationships.get("children", [])
		for child_id_any in children:
			var child_id := str(child_id_any).strip_edges()
			if child_id.is_empty() or not created_nodes.has(child_id):
				continue
			graph_view.connect_node(created_nodes[node_id].name, 1, created_nodes[child_id].name, 1)

func connect_stack_edges(graph_view: GraphEdit, created_nodes: Dictionary, edges: Array) -> void:
	if not is_instance_valid(graph_view):
		return
	for e in edges:
		var from_id := ""
		var to_id := ""
		if e is Dictionary:
			from_id = str((e as Dictionary).get("from", "")).strip_edges()
			to_id = str((e as Dictionary).get("to", "")).strip_edges()
		if from_id.is_empty() or to_id.is_empty():
			continue
		if created_nodes.has(from_id) and created_nodes.has(to_id):
			graph_view.connect_node(created_nodes[from_id].name, 1, created_nodes[to_id].name, 1)


func connect_typed_edges(
	graph_view: GraphEdit,
	created_nodes: Dictionary,
	edges: Array
) -> void:
	if not is_instance_valid(graph_view):
		return
	for edge_any in edges:
		if typeof(edge_any) != TYPE_DICTIONARY:
			continue
		var edge_data: Dictionary = edge_any
		var from_id: String = str(edge_data.get("from", "")).strip_edges()
		var to_id: String = str(edge_data.get("to", "")).strip_edges()
		if not created_nodes.has(from_id) or not created_nodes.has(to_id):
			continue
		var from_node_id: StringName = created_nodes[from_id].name
		var to_node_id: StringName = created_nodes[to_id].name
		var relation_port: int = _port_for_relation(
			str(edge_data.get("relation", ""))
		)
		if not graph_view.is_node_connected(
			from_node_id,
			relation_port,
			to_node_id,
			relation_port
		):
			graph_view.connect_node(
				from_node_id,
				relation_port,
				to_node_id,
				relation_port
			)


func _port_for_relation(relation_id: String) -> int:
	var relation_definition: Dictionary = RelationshipRegistryScript.definition(
		relation_id
	)
	match str(relation_definition.get("category", "semantic")):
		"structural":
			return 1
		"dependency":
			return 2
		"evidential":
			return 3
	return 4
