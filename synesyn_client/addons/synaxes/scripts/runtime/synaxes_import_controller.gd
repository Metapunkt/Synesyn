extends RefCounted
## Handles data import from all sources (demo, Hub context graphs, saved embeddings,
## ScenSyn sessions) and the source-picker popup for multi-item sources.

const HubSubstrateClient = preload("res://addons/synesyn_core/scripts/hub_substrate_client.gd")
const TestDataGeneratorScript = preload("res://addons/synaxes/scripts/integration/test_data_generator.gd")

signal import_completed(data: Array)
signal status_changed(msg: String)
## Emitted when Hub reports ui.context_graph availability (for Import Latest CTA).
signal context_graphs_availability(count: int)

# Dependencies — set by the runtime controller after construction.
var hub: HubSubstrateClient
var load_json_fn: Callable  # async (uri: String) -> Variant

# Picker UI (bound once by the runtime controller).
var picker_popup: Window
var picker_list: ItemList
var picker_hint: Label

# Internal picker state.
var _picker_rows: Array = []
var _picker_cols: Array = []
var _picker_mode: String = ""  # "sessions" | "context_graphs" | "saved_embeddings"

## Last context-graph artifact id successfully imported (for provenance).
var last_context_graph_artifact_id: String = ""
var last_context_graph_count: int = 0

const SOURCE_LABEL_HUB_CONTEXT := "Hub: Context Graphs"
const SOURCE_LABEL_HUB_EMBEDDINGS := "Hub: Saved Embeddings"
const SOURCE_LABEL_SCENSYN_SESSIONS := "ScenSyn: Session Data"

# ── Public API ────────────────────────────────────────────────────────────

func import_source(label: String) -> void:
	var type_map := {
		"Demo: Text Samples": "text",
		"Demo: Semantic Samples": "semantic",
		"Demo: Image Samples": "image",
	}
	if label in type_map:
		_import_demo(type_map[label])
	elif label == SOURCE_LABEL_HUB_CONTEXT:
		await _import_from_hub_context_graph()
	elif label == SOURCE_LABEL_HUB_EMBEDDINGS:
		await _import_from_hub_saved_embeddings()
	elif label == SOURCE_LABEL_SCENSYN_SESSIONS:
		await _import_from_scensyn_sessions()
	else:
		_status("Import source '%s' not recognized." % label)


func import_latest_context_graph() -> void:
	## Prominent CTA path (REQ-NDP-007): skip picker when exactly one graph exists.
	await _import_from_hub_context_graph()


func import_scensyn_session(session_id: String = "") -> void:
	## Application-layer import: load one session (or the only/latest available).
	## Empty session_id → prefer single session if only one exists; else latest by row order.
	_status("Querying hub for ScenSyn sessions…")
	if hub == null:
		_status("Hub unavailable — cannot import ScenSyn session.")
		return
	var res: Dictionary = await hub.query_events_by_type("session.turn", "scensyn", 500)
	if not bool(res.get("ok", false)):
		_status("Hub query failed: %s" % str(res.get("error", res)))
		return
	var result: Dictionary = res.get("result", {})
	var cols: Array = result.get("columns", [])
	var rows: Array = result.get("rows", [])
	if rows.is_empty():
		_status("No ScenSyn session events found. Run a ScenSyn session first.")
		return

	var wanted: String = session_id.strip_edges()
	var session_counts: Dictionary = {}
	var last_seen_order: Array[String] = []
	for row_any in rows:
		if typeof(row_any) != TYPE_ARRAY:
			continue
		var row: Array = row_any
		var sid: String = _row_get(cols, row, "session_id")
		if sid.is_empty():
			sid = "(no session)"
		if not session_counts.has(sid):
			session_counts[sid] = 0
			last_seen_order.append(sid)
		session_counts[sid] = int(session_counts[sid]) + 1

	var selected: Array = []
	if not wanted.is_empty():
		if not session_counts.has(wanted):
			_status("Session '%s' not found in Hub session.turn events." % wanted.left(24))
			return
		selected = [wanted]
	elif session_counts.size() == 1:
		selected = session_counts.keys()
	elif not last_seen_order.is_empty():
		# Rows are typically chronological; take the last distinct session id seen.
		selected = [last_seen_order[last_seen_order.size() - 1]]
	else:
		_status("No ScenSyn sessions available to import.")
		return

	await _scensyn_import_rows(cols, rows, selected)


func refresh_context_graph_availability() -> int:
	## Query Hub for ui.context_graph count; emit availability for CTA visibility.
	last_context_graph_count = 0
	if hub == null:
		context_graphs_availability.emit(0)
		return 0
	var res: Dictionary = await hub.query_artifacts_by_type("ui.context_graph", 25)
	if not bool(res.get("ok", false)):
		context_graphs_availability.emit(0)
		return 0
	var result: Dictionary = res.get("result", {})
	var rows: Array = result.get("rows", [])
	last_context_graph_count = rows.size()
	context_graphs_availability.emit(last_context_graph_count)
	return last_context_graph_count

func bind_picker_buttons(confirm_btn: Button, cancel_btn: Button, sel_all_btn: Button) -> void:
	if confirm_btn:
		confirm_btn.pressed.connect(_on_picker_confirm)
	if cancel_btn:
		cancel_btn.pressed.connect(_on_picker_cancel)
	if sel_all_btn:
		sel_all_btn.pressed.connect(_on_picker_select_all)
	if picker_popup:
		picker_popup.close_requested.connect(_on_picker_cancel)

# ── Demo sources ──────────────────────────────────────────────────────────

func _import_demo(data_type: String) -> void:
	var gen := TestDataGeneratorScript.new()
	gen.set_data_type(data_type)
	gen.set_item_count(20)
	var data: Array = gen.generate_test_data()
	last_context_graph_artifact_id = ""
	_status("Loaded %d demo %s items." % [data.size(), data_type])
	import_completed.emit(data)

# ── Hub context graphs ────────────────────────────────────────────────────

func _import_from_hub_context_graph() -> void:
	_status("Querying hub for ui.context_graph artifacts…")
	var res: Dictionary = await hub.query_artifacts_by_type("ui.context_graph", 25)
	if not bool(res.get("ok", false)):
		_status("Hub query failed: %s" % str(res.get("error", res)))
		return
	var result: Dictionary = res.get("result", {})
	var cols: Array = result.get("columns", [])
	var rows: Array = result.get("rows", [])
	if rows.is_empty():
		_status("No published context graphs found. In SynTree, use Manage Sources → Publish Context Graph.")
		return
	if rows.size() == 1:
		await _load_context_graph_row(cols, rows[0])
		return
	# Multiple — show picker
	_picker_mode = "context_graphs"
	_picker_cols = cols
	_picker_rows = rows
	_show_picker("Select a context graph to import",
		"Found %d published context graphs. Select one:" % rows.size())
	for row_any in rows:
		if typeof(row_any) != TYPE_ARRAY:
			continue
		var row: Array = row_any
		var art_id := _row_get(cols, row, "id")
		var created := _row_get(cols, row, "created_at")
		var meta_str := _row_get(cols, row, "metadata_json")
		var item_label: String = "Graph %s" % art_id.left(16)
		if not created.is_empty():
			item_label += " (created %s)" % created.left(10)
		if not meta_str.is_empty():
			var m: Variant = JSON.parse_string(meta_str)
			if typeof(m) == TYPE_DICTIONARY:
				var prov: Dictionary = (m as Dictionary).get("provenance", {})
				if prov.has("source_count"):
					item_label += " — %s sources" % str(prov.get("source_count", "?"))
		picker_list.add_item(item_label)
		picker_list.set_item_metadata(picker_list.item_count - 1, art_id)

func _load_context_graph_row(cols: Array, row: Array) -> void:
	var uri := _row_get(cols, row, "uri")
	var art_id := _row_get(cols, row, "id")
	if uri.is_empty():
		_status("Context graph missing uri (artifact %s)" % art_id)
		return
	var graph_any: Variant = null
	var hub_json_res: Dictionary = await hub.get_artifact_json(art_id)
	if bool(hub_json_res.get("ok", false)):
		graph_any = hub_json_res.get("json", null)
	if typeof(graph_any) != TYPE_DICTIONARY and load_json_fn.is_valid():
		graph_any = await load_json_fn.call(uri)
	if typeof(graph_any) != TYPE_DICTIONARY:
		_status("Failed to load context graph JSON (artifact %s, uri %s)" % [art_id, uri])
		return
	var graph: Dictionary = graph_any
	var data: Array = _context_graph_to_items(graph)
	data = await _apply_store_admissibility_filter(data)
	last_context_graph_artifact_id = art_id
	import_completed.emit(data)
	_status("Loaded context graph %s (%d nodes). Review in Imported Data tab." % [art_id.left(16), data.size()])

func _context_graph_to_items(graph: Dictionary) -> Array:
	var items: Array = []
	var nodes: Array = graph.get("nodes", [])
	for n_any in nodes:
		if typeof(n_any) != TYPE_DICTIONARY:
			continue
		var n: Dictionary = n_any
		var meta: Dictionary = n.get("meta", {})
		var node_name := str(meta.get("name", n.get("id", "")))
		var node_path := str(meta.get("path", ""))
		var node_type := str(meta.get("type", n.get("type", "")))
		var content_parts: Array = []
		if not node_name.is_empty():
			content_parts.append(node_name)
		if not node_type.is_empty():
			content_parts.append("[%s]" % node_type)
		if not node_path.is_empty():
			content_parts.append(node_path)
		var node_desc := str(meta.get("description", meta.get("text", meta.get("content", ""))))
		if not node_desc.is_empty():
			if node_desc.length() > 100:
				node_desc = node_desc.left(97) + "..."
			content_parts.append("— %s" % node_desc)
		var content_label: String = " ".join(content_parts) if not content_parts.is_empty() else str(n.get("id", "unnamed"))
		items.append({
			"id": str(n.get("id", "")),
			"content": content_label.strip_edges(),
			"vector": [],
			"metadata": {"context_graph_node": n},
		})
	return items

# ── Hub saved embeddings ──────────────────────────────────────────────────

func _import_from_hub_saved_embeddings() -> void:
	_status("Querying hub for synaxes.embeddings artifacts…")
	var res: Dictionary = await hub.query_artifacts_by_type("synaxes.embeddings", 25)
	if not bool(res.get("ok", false)):
		_status("Hub query failed: %s" % str(res.get("error", res)))
		return
	var result: Dictionary = res.get("result", {})
	var cols: Array = result.get("columns", [])
	var rows: Array = result.get("rows", [])
	if rows.is_empty():
		_status("No saved embeddings found. Run an analysis with Model Embeddings first.")
		return
	if rows.size() > 1:
		_picker_mode = "saved_embeddings"
		_picker_cols = cols
		_picker_rows = rows
		_show_picker("Select saved embeddings to import",
			"Found %d saved embedding sets. Select one:" % rows.size())
		for row_any in rows:
			if typeof(row_any) != TYPE_ARRAY:
				continue
			var row: Array = row_any
			var r_id := _row_get(cols, row, "id")
			var created := _row_get(cols, row, "created_at")
			var meta_str := _row_get(cols, row, "metadata_json")
			var item_label: String = "Embeddings %s" % r_id.left(16)
			if not created.is_empty():
				item_label += " (created %s)" % created.left(10)
			if not meta_str.is_empty():
				var m: Variant = JSON.parse_string(meta_str)
				if typeof(m) == TYPE_DICTIONARY:
					var prov: Dictionary = (m as Dictionary).get("provenance", {})
					var tier := str(prov.get("embedding_tier", ""))
					var count := str(prov.get("item_count", "?"))
					if not tier.is_empty():
						item_label += " — %s, %s items" % [tier, count]
			picker_list.add_item(item_label)
			picker_list.set_item_metadata(picker_list.item_count - 1, r_id)
		return
	var first_row: Array = rows[0]
	var art_id := _row_get(cols, first_row, "id")
	await _load_saved_embeddings_by_id(art_id)

func _load_saved_embeddings_by_id(art_id: String) -> void:
	var json_res: Dictionary = await hub.get_artifact_json(art_id)
	if not bool(json_res.get("ok", false)):
		_status("Failed to load embeddings artifact: %s" % art_id)
		return
	var json: Dictionary = json_res.get("json", {})
	var item_ids_any: Variant = json.get("item_ids", [])
	var vectors_map_any: Variant = json.get("vectors", {})
	var contents_map_any: Variant = json.get("contents", {})
	if typeof(item_ids_any) != TYPE_ARRAY or typeof(vectors_map_any) != TYPE_DICTIONARY:
		_status("Embeddings artifact has unexpected structure.")
		return
	var item_ids: Array = item_ids_any
	var vectors_map: Dictionary = vectors_map_any
	var contents_map: Dictionary = contents_map_any if typeof(contents_map_any) == TYPE_DICTIONARY else {}
	var data: Array = []
	for iid in item_ids:
		var id_str := str(iid)
		var vec: Variant = vectors_map.get(id_str, [])
		var content := str(contents_map.get(id_str, id_str))
		data.append({
			"id": id_str,
			"content": content,
			"vector": vec if typeof(vec) == TYPE_ARRAY else [],
			"metadata": {"source_artifact": art_id},
		})
	data = await _apply_store_admissibility_filter(data)
	last_context_graph_artifact_id = ""
	import_completed.emit(data)
	_status("Loaded %d items from saved embeddings (%s). Review in Imported Data tab." % [data.size(), art_id.left(12)])

# ── ScenSyn sessions ─────────────────────────────────────────────────────

func _import_from_scensyn_sessions() -> void:
	_status("Querying hub for ScenSyn sessions…")
	var res: Dictionary = await hub.query_events_by_type("session.turn", "scensyn", 500)
	if not bool(res.get("ok", false)):
		_status("Hub query failed: %s" % str(res.get("error", res)))
		return
	var result: Dictionary = res.get("result", {})
	var cols: Array = result.get("columns", [])
	var rows: Array = result.get("rows", [])
	if rows.is_empty():
		_status("No ScenSyn session events found. Run a ScenSyn session first.")
		return

	var session_counts: Dictionary = {}
	var session_preview: Dictionary = {}
	for row_any in rows:
		if typeof(row_any) != TYPE_ARRAY:
			continue
		var row: Array = row_any
		var sid := _row_get(cols, row, "session_id")
		if sid.is_empty():
			sid = "(no session)"
		session_counts[sid] = int(session_counts.get(sid, 0)) + 1
		if not session_preview.has(sid):
			var pstr := _row_get(cols, row, "payload_json")
			if pstr.is_empty():
				pstr = _row_get(cols, row, "payload")
			if not pstr.is_empty():
				var pj: Variant = JSON.parse_string(pstr)
				if typeof(pj) == TYPE_DICTIONARY:
					var preview := str((pj as Dictionary).get("text", ""))
					if preview.length() > 60:
						preview = preview.left(57) + "..."
					if not preview.is_empty():
						session_preview[sid] = preview

	if session_counts.size() <= 1:
		_scensyn_import_rows(cols, rows, session_counts.keys())
		return

	_picker_mode = "sessions"
	_picker_cols = cols
	_picker_rows = rows
	_show_picker("Select ScenSyn session(s) to import",
		"Found %d sessions. Select which story logs to analyse:" % session_counts.size())
	for sid_key in session_counts:
		var count: int = session_counts[sid_key]
		var preview: String = session_preview.get(sid_key, "")
		var item_label: String = "%s (%d turns)" % [sid_key.left(20), count]
		if not preview.is_empty():
			item_label += " — %s" % preview
		picker_list.add_item(item_label)
		picker_list.set_item_metadata(picker_list.item_count - 1, sid_key)
	for i in range(picker_list.item_count):
		picker_list.select(i, false)

func _scensyn_import_rows(cols: Array, rows: Array, selected_sessions: Array) -> void:
	var data: Array = []
	for row_any in rows:
		if typeof(row_any) != TYPE_ARRAY:
			continue
		var row: Array = row_any
		var session_id := _row_get(cols, row, "session_id")
		if not selected_sessions.is_empty() and session_id not in selected_sessions:
			continue
		var evt_id := _row_get(cols, row, "id")
		var payload_str := _row_get(cols, row, "payload_json")
		if payload_str.is_empty():
			payload_str = _row_get(cols, row, "payload")
		var payload: Dictionary = {}
		if not payload_str.is_empty():
			var p: Variant = JSON.parse_string(payload_str)
			if typeof(p) == TYPE_DICTIONARY:
				payload = p
		var character := str(payload.get("character_name", payload.get("character", "")))
		if character.is_empty():
			character = str(payload.get("role", ""))
		var text := str(payload.get("text", ""))
		if text.is_empty() and character.is_empty():
			continue
		var content: String = ""
		if not text.is_empty():
			content = "%s: %s" % [character, text] if not character.is_empty() else text
		elif not character.is_empty():
			content = character
		else:
			continue
		data.append({
			"id": evt_id,
			"content": content,
			"vector": [],
			"metadata": {"source": "scensyn", "session_id": session_id, "character": character},
		})
	data = await _apply_store_admissibility_filter(data)
	last_context_graph_artifact_id = ""
	import_completed.emit(data)
	_status("Loaded %d ScenSyn session turns. Review in Imported Data tab." % data.size())

# ── Store admissibility filter (Open Closure–aligned, opt-in via Store config) ─

func _apply_store_admissibility_filter(data: Array) -> Array:
	## When STFX Store admissibility is enabled, drop items whose
	## provenance matches the forbidden policy (or Store closure forbidden ids).
	## Demo imports are not filtered here.
	if data.is_empty() or hub == null:
		return data
	if not hub.has_method("stfx_store_status"):
		return data
	var status_res: Dictionary = await hub.stfx_store_status()
	if not bool(status_res.get("ok", false)):
		return data
	var manifest_any: Variant = status_res.get("manifest", {})
	if typeof(manifest_any) != TYPE_DICTIONARY:
		return data
	var adm_any: Variant = (manifest_any as Dictionary).get("admissibility", {})
	if typeof(adm_any) != TYPE_DICTIONARY:
		return data
	var adm: Dictionary = adm_any
	if not bool(adm.get("enabled", false)):
		return data

	var forbidden_prefixes: Array = adm.get("forbidden_produced_by_prefixes", []) if typeof(adm.get("forbidden_produced_by_prefixes", [])) == TYPE_ARRAY else []
	var forbidden_types: Array = adm.get("forbidden_source_types", []) if typeof(adm.get("forbidden_source_types", [])) == TYPE_ARRAY else []
	var forbidden_kinds: Array = adm.get("forbidden_authorship_kinds", []) if typeof(adm.get("forbidden_authorship_kinds", [])) == TYPE_ARRAY else []
	# Client filter applies explicit policy matches only. Store retrieve owns uncertain→exclude.
	var forbidden_source_ids: Dictionary = {}
	if hub.has_method("stfx_store_list_closures"):
		var clo_res: Dictionary = await hub.stfx_store_list_closures()
		if bool(clo_res.get("ok", false)):
			var closures_any: Variant = clo_res.get("closures", [])
			if typeof(closures_any) == TYPE_ARRAY:
				for clo_any in closures_any:
					if typeof(clo_any) != TYPE_DICTIONARY:
						continue
					var sc_any: Variant = (clo_any as Dictionary).get("symbolic_constraints", {})
					if typeof(sc_any) != TYPE_DICTIONARY:
						continue
					var ids_any: Variant = (sc_any as Dictionary).get("forbidden_source_ids", [])
					if typeof(ids_any) != TYPE_ARRAY:
						continue
					for sid_any in ids_any:
						var sid := str(sid_any).strip_edges()
						if not sid.is_empty():
							forbidden_source_ids[sid] = true

	var kept: Array = []
	var dropped: int = 0
	for it_any in data:
		if typeof(it_any) != TYPE_DICTIONARY:
			continue
		var it: Dictionary = it_any
		if _item_forbidden_by_admissibility(it, forbidden_prefixes, forbidden_types, forbidden_kinds, forbidden_source_ids):
			dropped += 1
			continue
		kept.append(it)
	if dropped > 0:
		_status("Store admissibility excluded %d of %d imported items (Open Closure–aligned policy)." % [dropped, data.size()])
	return kept

func _item_forbidden_by_admissibility(
	it: Dictionary,
	forbidden_prefixes: Array,
	forbidden_types: Array,
	forbidden_kinds: Array,
	forbidden_source_ids: Dictionary
) -> bool:
	var meta_any: Variant = it.get("metadata", {})
	var meta: Dictionary = meta_any if typeof(meta_any) == TYPE_DICTIONARY else {}
	var produced_by := ""
	var authorship_kind := ""
	var source_type := ""
	var source_id := ""

	var node_any: Variant = meta.get("context_graph_node", {})
	if typeof(node_any) == TYPE_DICTIONARY:
		var node: Dictionary = node_any
		var nmeta_any: Variant = node.get("meta", {})
		var nmeta: Dictionary = nmeta_any if typeof(nmeta_any) == TYPE_DICTIONARY else {}
		var nprov_any: Variant = nmeta.get("provenance", node.get("provenance", {}))
		var nprov: Dictionary = nprov_any if typeof(nprov_any) == TYPE_DICTIONARY else {}
		produced_by = str(nprov.get("produced_by", "")).strip_edges()
		authorship_kind = str(nprov.get("authorship_kind", "")).strip_edges().to_lower()
		source_type = str(nmeta.get("type", nmeta.get("source_type", node.get("type", "")))).strip_edges().to_lower()
		source_id = str(nmeta.get("source_id", nprov.get("origin_ref", ""))).strip_edges()

	if source_id.is_empty():
		source_id = str(meta.get("source_id", "")).strip_edges()
	if produced_by.is_empty():
		produced_by = str(meta.get("produced_by", "")).strip_edges()
	if authorship_kind.is_empty():
		authorship_kind = str(meta.get("authorship_kind", "")).strip_edges().to_lower()
	if source_type.is_empty():
		source_type = str(meta.get("source_type", meta.get("source", ""))).strip_edges().to_lower()

	if not source_id.is_empty() and forbidden_source_ids.has(source_id):
		return true
	for prefix_any in forbidden_prefixes:
		var prefix := str(prefix_any).strip_edges()
		if not prefix.is_empty() and produced_by.begins_with(prefix):
			return true
	for st_any in forbidden_types:
		var st := str(st_any).strip_edges().to_lower()
		if not st.is_empty() and source_type == st:
			return true
	for kind_any in forbidden_kinds:
		var kind := str(kind_any).strip_edges().to_lower()
		if not kind.is_empty() and authorship_kind == kind:
			return true
	return false

# ── Picker popup helpers ─────────────────────────────────────────────────

func _show_picker(title: String, hint: String) -> void:
	if not picker_popup or not picker_list:
		return
	picker_popup.title = title
	if picker_hint:
		picker_hint.text = hint
	picker_list.clear()
	picker_popup.popup_centered()

func _on_picker_confirm() -> void:
	if not picker_list:
		return
	var selected := picker_list.get_selected_items()
	if selected.is_empty():
		_status("No items selected in picker.")
		return
	picker_popup.hide()
	match _picker_mode:
		"sessions":
			var sel_sessions: Array = []
			for idx in selected:
				sel_sessions.append(picker_list.get_item_metadata(idx))
			_scensyn_import_rows(_picker_cols, _picker_rows, sel_sessions)
		"context_graphs":
			var art_id: String = picker_list.get_item_metadata(selected[0])
			for row_any in _picker_rows:
				if typeof(row_any) != TYPE_ARRAY:
					continue
				var row: Array = row_any
				if _row_get(_picker_cols, row, "id") == art_id:
					_load_context_graph_row(_picker_cols, row)
					break
		"saved_embeddings":
			var art_id: String = picker_list.get_item_metadata(selected[0])
			_load_saved_embeddings_by_id(art_id)
	_picker_rows = []
	_picker_cols = []

func _on_picker_cancel() -> void:
	if picker_popup:
		picker_popup.hide()
	_picker_rows = []
	_picker_cols = []
	_status("Import cancelled.")

func _on_picker_select_all() -> void:
	if not picker_list:
		return
	for i in range(picker_list.item_count):
		picker_list.select(i, false)

# ── Utility ──────────────────────────────────────────────────────────────

func _row_get(cols: Array, row: Array, col_name: String) -> String:
	var idx := cols.find(col_name)
	if idx == -1 or idx >= row.size():
		return ""
	return str(row[idx])

func _status(msg: String) -> void:
	status_changed.emit(msg)
