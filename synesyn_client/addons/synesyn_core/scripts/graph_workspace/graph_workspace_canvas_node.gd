## Purpose: Domain-neutral GraphEdit node for Graph Workspace documents.
extends GraphNode

var workspace_node_id: String = ""
var workspace_kind: String = ""


func configure(node_data: Dictionary) -> void:
	workspace_node_id = String(node_data.get("id", "")).strip_edges()
	workspace_kind = String(node_data.get("kind", "")).strip_edges()
	title = _title_for(node_data)
	var body_label_node: Label = get_node_or_null("BodyLabel") as Label
	if body_label_node:
		body_label_node.text = String(node_data.get("label", "")).strip_edges()
	var status_label_node: Label = get_node_or_null("StatusLabel") as Label
	if status_label_node:
		var status_text: String = String(node_data.get("status", "suggested")).strip_edges()
		status_label_node.text = status_text.capitalize()
	custom_minimum_size = Vector2(220, 96)
	clear_all_slots()
	set_slot_enabled_left(0, true)
	set_slot_enabled_right(0, true)
	set_slot_type_left(0, 0)
	set_slot_type_right(0, 0)
	var accent: Color = _accent_for_kind(workspace_kind)
	set_slot_color_left(0, accent)
	set_slot_color_right(0, accent)


func _title_for(node_data: Dictionary) -> String:
	var kind_text: String = String(node_data.get("kind", "node")).strip_edges()
	if kind_text.is_empty():
		kind_text = "node"
	return kind_text.capitalize()


func _accent_for_kind(kind_text: String) -> Color:
	match kind_text:
		"cause":
			return Color("#6f8fb3")
		"effect":
			return Color("#b58b4b")
		"opportunity":
			return Color("#4f9b72")
		_:
			return Color("#8a72b5")
