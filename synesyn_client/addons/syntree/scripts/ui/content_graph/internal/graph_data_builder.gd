## Purpose: GraphDataBuilder (script)
@tool
class_name GraphDataBuilder
extends RefCounted

# Pure-ish data preparation helper for ContentGraphController.
# IMPORTANT:
# - No signals.
# - No scene tree / GraphEdit mutation.
# - Only reads ContentStateResource for derived metadata (states, source meta).

var _content_state: ContentStateResource = null

func _init(content_state: ContentStateResource = null) -> void:
	_content_state = content_state

func set_content_state(content_state: ContentStateResource) -> void:
	_content_state = content_state

func build_node_payload(
		display_node_id: String,
		container_source_id: String,
		container_source_data: Dictionary,
		raw_node_data: Dictionary,
		merge_container_source_meta: bool,
		set_container_source_id_meta: bool
	) -> Dictionary:
	# Returns:
	# {
	#   "complete_node_data": Dictionary,
	#   "effective_source_id": String,
	#   "is_active": bool,
	#   "is_metaprompt": bool,
	#   "raw_node_id": String
	# }

	var out: Dictionary = {
		"complete_node_data": {},
		"effective_source_id": "",
		"is_active": false,
		"is_metaprompt": false,
		"raw_node_id": ""
	}

	var disp_id := String(display_node_id).strip_edges()
	if disp_id.is_empty():
		return out

	if not (raw_node_data is Dictionary):
		return out

	var src_id := String(container_source_id).strip_edges()
	if src_id.is_empty():
		return out

	var source_meta: Dictionary = container_source_data.get("meta", {})

	# Snapshot the raw node id before we override it (stack composed ids).
	var raw_node_id := str(raw_node_data.get("node_id", "")).strip_edges()
	out["raw_node_id"] = raw_node_id

	var complete_node_data: Dictionary = raw_node_data.duplicate(true)
	complete_node_data["node_id"] = disp_id

	# Determine effective source for toggles/labels (supports linked child placeholder nodes).
	var effective_source_id := src_id
	var node_meta0: Dictionary = raw_node_data.get("meta", {})
	var linked_sid := str(node_meta0.get("linked_source_id", "")).strip_edges()
	if not linked_sid.is_empty() and is_instance_valid(_content_state) and _content_state.has_method("has_source") and bool(_content_state.has_source(linked_sid)):
		effective_source_id = linked_sid

	complete_node_data["source_id"] = effective_source_id

	if not complete_node_data.has("meta") or not (complete_node_data["meta"] is Dictionary):
		complete_node_data["meta"] = {}
	var meta: Dictionary = complete_node_data["meta"]

	# Optionally merge container source meta keys (non-stack graph does this; stack graph historically did not).
	if merge_container_source_meta and (source_meta is Dictionary):
		for key in source_meta:
			if not meta.has(key):
				meta[key] = source_meta[key]

	# Always set effective source id for rendering/toggles.
	meta["source_id"] = effective_source_id

	# Optionally preserve container identity (stack graphs)
	if set_container_source_id_meta:
		meta["container_source_id"] = src_id
		# Store the original raw node id (pre-composed) to aid debugging/traceability.
		if not raw_node_id.is_empty():
			complete_node_data["orig_node_id"] = raw_node_id

	# Resolve effective meta for display/path.
	var eff_meta: Dictionary = source_meta
	if effective_source_id != src_id and is_instance_valid(_content_state):
		var eff_data: Dictionary = _content_state.get_source_data(effective_source_id)
		eff_meta = eff_data.get("meta", eff_meta)

	# Source name display
	var source_name: String = str(eff_meta.get("name", "")).strip_edges()
	if source_name.is_empty():
		# Fallbacks: use container name for same-source, else effective id.
		if effective_source_id == src_id:
			source_name = str(source_meta.get("name", src_id))
		else:
			source_name = effective_source_id
	meta["source_name"] = source_name

	# Preserve node-level path if provided; otherwise fall back to effective source meta.path.
	var node_path0 := str(complete_node_data.get("path", "")).strip_edges()
	if node_path0.is_empty():
		var eff_path := str(eff_meta.get("path", "")).strip_edges()
		if not eff_path.is_empty():
			complete_node_data["path"] = eff_path
			meta["path"] = eff_path

	# States are per-effective source.
	var is_metaprompt := false
	var is_active := false
	if is_instance_valid(_content_state):
		is_metaprompt = _content_state.get_metaprompt_state(effective_source_id)
		is_active = _content_state.get_source_active_state(effective_source_id)

	complete_node_data["is_active"] = is_active
	complete_node_data["is_metaprompt"] = is_metaprompt
	meta["ai_context"] = {"metaprompt": is_metaprompt, "is_active": is_active}

	out["complete_node_data"] = complete_node_data
	out["effective_source_id"] = effective_source_id
	out["is_active"] = is_active
	out["is_metaprompt"] = is_metaprompt
	return out


