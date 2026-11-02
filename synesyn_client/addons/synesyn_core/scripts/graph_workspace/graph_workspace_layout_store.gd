## Purpose: Persist user-owned named canvas layouts outside semantic artifacts.
extends RefCounted

const SCHEMA_ID: String = "graph_workspace_layouts.v1"
const RuntimeConfigScript = preload("res://addons/synesyn_core/scripts/runtime_config.gd")


func _store_path() -> String:
	var dest: String = RuntimeConfigScript.get_graph_layouts_path()
	RuntimeConfigScript.migrate_file_if_needed(
		dest,
		[
			"user://syntree/context_graph_layouts.json",
			"user://synesyn/context_graph_layouts.json",
		]
	)
	return dest


func list_layouts(owner_id: String) -> Array[Dictionary]:
	var store: Dictionary = _read_store()
	var result: Array[Dictionary] = []
	var owner_layouts: Dictionary = store.get("owners", {}).get(owner_id, {})
	for layout_id_any in owner_layouts:
		var layout_data: Dictionary = owner_layouts[layout_id_any]
		result.append(layout_data.duplicate(true))
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return str(left.get("label", "")) < str(right.get("label", ""))
	)
	return result


func save_layout(
	owner_id: String,
	label_text: String,
	canvas_state: Dictionary,
	layout_id: String = ""
) -> Dictionary:
	var normalized_owner: String = owner_id.strip_edges()
	var normalized_label: String = label_text.strip_edges()
	if normalized_owner.is_empty() or normalized_label.is_empty():
		return {"ok": false, "error": "owner_and_label_required"}
	var stable_id: String = layout_id.strip_edges()
	if stable_id.is_empty():
		stable_id = "layout_%s" % (
			"%s|%s" % [normalized_owner, normalized_label]
		).sha256_text().substr(0, 16)
	var store: Dictionary = _read_store()
	var owners: Dictionary = store.get("owners", {})
	var owner_layouts: Dictionary = owners.get(normalized_owner, {})
	var record: Dictionary = {
		"id": stable_id,
		"owner_id": normalized_owner,
		"label": normalized_label,
		"node_positions": _normalized_positions(
			canvas_state.get("node_positions", {})
		),
		"viewport": _normalized_viewport(canvas_state.get("viewport", {})),
	}
	owner_layouts[stable_id] = record
	owners[normalized_owner] = owner_layouts
	store["owners"] = owners
	var write_result: Dictionary = _write_store(store)
	if not bool(write_result.get("ok", false)):
		return write_result
	return {"ok": true, "layout": record.duplicate(true)}


func delete_layout(owner_id: String, layout_id: String) -> Dictionary:
	var store: Dictionary = _read_store()
	var owners: Dictionary = store.get("owners", {})
	var owner_layouts: Dictionary = owners.get(owner_id, {})
	if not owner_layouts.erase(layout_id):
		return {"ok": false, "error": "layout_not_found"}
	owners[owner_id] = owner_layouts
	store["owners"] = owners
	return _write_store(store)


func _read_store() -> Dictionary:
	var store_path: String = _store_path()
	if not FileAccess.file_exists(store_path):
		return {"schema": SCHEMA_ID, "owners": {}}
	var file: FileAccess = FileAccess.open(store_path, FileAccess.READ)
	if file == null:
		return {"schema": SCHEMA_ID, "owners": {}}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"schema": SCHEMA_ID, "owners": {}}
	var store: Dictionary = parsed
	if str(store.get("schema", "")) != SCHEMA_ID:
		return {"schema": SCHEMA_ID, "owners": {}}
	return store


func _write_store(store: Dictionary) -> Dictionary:
	var store_path: String = _store_path()
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(
		store_path.get_base_dir()
	)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return {"ok": false, "error": "layout_directory_unavailable"}
	var file: FileAccess = FileAccess.open(store_path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "layout_store_unavailable"}
	file.store_string(JSON.stringify(store, "\t", false))
	return {"ok": true}


func _normalized_positions(value: Variant) -> Dictionary:
	var result: Dictionary = {}
	if typeof(value) != TYPE_DICTIONARY:
		return result
	for node_id_any in value:
		var point_any: Variant = (value as Dictionary).get(node_id_any, {})
		if typeof(point_any) != TYPE_DICTIONARY:
			continue
		var point: Dictionary = point_any
		result[str(node_id_any)] = {
			"x": float(point.get("x", 0.0)),
			"y": float(point.get("y", 0.0)),
		}
	return result


func _normalized_viewport(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {"scroll_x": 0.0, "scroll_y": 0.0, "zoom": 1.0}
	var viewport_data: Dictionary = value
	return {
		"scroll_x": float(viewport_data.get("scroll_x", 0.0)),
		"scroll_y": float(viewport_data.get("scroll_y", 0.0)),
		"zoom": clampf(float(viewport_data.get("zoom", 1.0)), 0.1, 4.0),
	}
