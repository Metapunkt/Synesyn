## Purpose: Resolve, normalize, mutate, and persist legacy source edge arrays.
extends RefCounted

const ContentEdgeOpsScript = preload(
	"res://addons/syntree/scripts/resources/internal/content_edge_ops.gd"
)

var _edge_ops: RefCounted = ContentEdgeOpsScript.new()


func mutate(
	content_state: Object,
	kind: String,
	from_id: String,
	to_id: String,
	is_adding: bool,
	default_kind: String,
	relationship_keys: Array
) -> bool:
	if from_id.is_empty() or to_id.is_empty():
		return false
	var normalized_kind: String = kind.strip_edges()
	if normalized_kind.is_empty():
		normalized_kind = default_kind
	var parsed_from: Dictionary = content_state.call("parse_composed_node_id", from_id)
	var parsed_to: Dictionary = content_state.call("parse_composed_node_id", to_id)
	var source_from: String = (
		str(parsed_from.get("source_id", ""))
		if bool(parsed_from.get("is_composed", false))
		else str(content_state.call("get_source_for_node", from_id))
	)
	var source_to: String = (
		str(parsed_to.get("source_id", ""))
		if bool(parsed_to.get("is_composed", false))
		else str(content_state.call("get_source_for_node", to_id))
	)
	if source_from.is_empty() or source_to.is_empty() or source_from != source_to:
		return false
	var source_data: Dictionary = content_state.call("get_source_data", source_from)
	var content_data: Dictionary = source_data.get("content", {})
	var nodes_any: Variant = content_data.get("nodes", null)
	if typeof(nodes_any) != TYPE_ARRAY:
		return false
	var changed: bool = false
	source_data = content_state.call("_normalize_graph_in_data", source_data, changed)
	var nodes: Array = source_data.get("content", {}).get("nodes", [])
	var result: Dictionary = _edge_ops.call(
		"mutate_edge",
		nodes,
		normalized_kind,
		str(parsed_from.get("node_id", "")),
		str(parsed_to.get("node_id", "")),
		is_adding,
		relationship_keys[0],
		relationship_keys[1],
		relationship_keys[2],
		relationship_keys[3]
	)
	if not bool(result.get("success", false)):
		return false
	if bool(result.get("changed", false)):
		var normalized_content: Dictionary = source_data.get("content", {})
		normalized_content["nodes"] = result.get("nodes", nodes)
		source_data["content"] = normalized_content
	source_data = content_state.call(
		"_normalize_graph_in_data",
		source_data,
		changed
	)
	var is_updated: bool = bool(
		content_state.call("update_source", source_from, source_data)
	)
	if is_updated:
		content_state.call("save_source", source_from)
	return is_updated
