extends RefCounted
class_name SynpunktArtifactBrowserUtils

static func refresh_closures(owner: Control, artifact_closure: String) -> void:
	owner.call("_set_status", "Querying hub for %s…" % artifact_closure)
	var hub: Object = owner.get("_hub")
	if not hub:
		owner.call("_set_status", "Hub unavailable.")
		return
	var res: Dictionary = await hub.call("query_artifacts_by_type", artifact_closure, 50)
	if not bool(res.get("ok", false)):
		var url_hint := ""
		var req_url := str(res.get("url", "")).strip_edges()
		if not req_url.is_empty():
			url_hint = " (%s)" % req_url
		owner.call("_set_status", "Hub query failed%s: %s" % [url_hint, str(res.get("error", res))])
		return
	var result: Dictionary = res.get("result", {})
	owner.set("_closure_cols", result.get("columns", []))
	owner.set("_closure_rows", result.get("rows", []))
	var closures_list: Tree = owner.get("_closures_list")
	if not closures_list:
		return
	closures_list.clear()
	closures_list.hide_root = true
	closures_list.columns = 2
	var root_item := closures_list.create_item()
	var present_ids: Dictionary = {}
	var closure_rows_any: Variant = owner.get("_closure_rows")
	var closure_rows: Array = closure_rows_any if typeof(closure_rows_any) == TYPE_ARRAY else []
	var closure_cols_any: Variant = owner.get("_closure_cols")
	var closure_cols: Array = closure_cols_any if typeof(closure_cols_any) == TYPE_ARRAY else []
	var checked_ids_any: Variant = owner.get("_checked_closure_ids")
	var checked_ids: Dictionary = checked_ids_any if typeof(checked_ids_any) == TYPE_DICTIONARY else {}
	for r in closure_rows:
		if typeof(r) != TYPE_ARRAY:
			continue
		var row: Array = r
		var art_id := str(owner.call("_row_get", closure_cols, row, "id"))
		var created := owner.call("_row_get", closure_cols, row, "created_at")
		var uri := str(owner.call("_row_get", closure_cols, row, "uri"))
		var label := "%s  (%s)" % [art_id.left(12), str(created)]
		if uri.is_empty():
			label = "[NO URI] " + label
		var checked := checked_ids.has(art_id)
		var it := closures_list.create_item(root_item)
		it.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
		it.set_editable(0, true)
		it.set_checked(0, checked)
		it.set_text(0, "")
		it.set_text(1, label)
		it.set_metadata(1, art_id)
		present_ids[art_id] = true
	for aid in checked_ids.keys():
		if not present_ids.has(str(aid)):
			checked_ids.erase(aid)
	owner.set("_checked_closure_ids", checked_ids)
	owner.call("_set_status", "Found %d closures." % closure_rows.size())


static func refresh_store_closures(owner: Control) -> void:
	owner.call("_set_status", "Querying STFX Store closures…")
	var hub: Object = owner.get("_hub")
	if not hub or not hub.has_method("stfx_store_list_closures"):
		owner.call("_set_status", "Hub Store closure API unavailable.")
		return
	var res: Dictionary = await hub.call("stfx_store_list_closures")
	if not bool(res.get("ok", false)):
		owner.call("_set_status", "Store closure query failed: %s" % str(res.get("error", res)))
		return
	var records_any: Variant = res.get("closures", [])
	var records: Array = records_any if typeof(records_any) == TYPE_ARRAY else []
	owner.set("_closure_browser_mode", "store_closure")
	owner.set("_store_closure_records", records)
	_populate_store_records_tree(owner, records, "closure_id", "title", "Store closure")


static func refresh_store_context_packs(owner: Control) -> void:
	owner.call("_set_status", "Querying STFX Store context packs…")
	var hub: Object = owner.get("_hub")
	if not hub or not hub.has_method("stfx_store_list_context_packs"):
		owner.call("_set_status", "Hub Store context-pack API unavailable.")
		return
	var res: Dictionary = await hub.call("stfx_store_list_context_packs")
	if not bool(res.get("ok", false)):
		owner.call("_set_status", "Store context-pack query failed: %s" % str(res.get("error", res)))
		return
	var records_any: Variant = res.get("context_packs", [])
	var records: Array = records_any if typeof(records_any) == TYPE_ARRAY else []
	owner.set("_closure_browser_mode", "store_context_pack")
	owner.set("_store_context_pack_records", records)
	_populate_store_records_tree(owner, records, "context_pack_id", "query", "Context pack")


static func _populate_store_records_tree(owner: Control, records: Array, id_key: String, label_key: String, label_prefix: String) -> void:
	var closures_list: Tree = owner.get("_closures_list")
	if not closures_list:
		return
	closures_list.clear()
	closures_list.hide_root = true
	closures_list.columns = 2
	var root_item := closures_list.create_item()
	var checked_ids_any: Variant = owner.get("_checked_closure_ids")
	var checked_ids: Dictionary = checked_ids_any if typeof(checked_ids_any) == TYPE_DICTIONARY else {}
	var present_ids: Dictionary = {}
	for record_any in records:
		if typeof(record_any) != TYPE_DICTIONARY:
			continue
		var record: Dictionary = record_any
		var record_id := str(record.get(id_key, "")).strip_edges()
		if record_id.is_empty():
			continue
		var title := str(record.get(label_key, "")).strip_edges()
		if title.is_empty():
			title = label_prefix
		var created := str(record.get("created_at", "")).strip_edges()
		var label := "%s: %s" % [record_id.left(12), title]
		if not created.is_empty():
			label += "  (%s)" % created
		var item_node := closures_list.create_item(root_item)
		item_node.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
		item_node.set_editable(0, true)
		item_node.set_checked(0, checked_ids.has(record_id))
		item_node.set_text(0, "")
		item_node.set_text(1, label)
		item_node.set_metadata(1, record_id)
		present_ids[record_id] = true
	for checked_id in checked_ids.keys():
		if not present_ids.has(str(checked_id)):
			checked_ids.erase(checked_id)
	owner.set("_checked_closure_ids", checked_ids)
	owner.call("_set_status", "Found %d %s records." % [records.size(), label_prefix.to_lower()])


static func refresh_flowdocs(owner: Control, artifact_syndoc: String) -> void:
	owner.call("_set_status", "Querying hub for %s…" % artifact_syndoc)
	var hub: Object = owner.get("_hub")
	if not hub:
		owner.call("_set_status", "Hub unavailable.")
		return
	var res: Dictionary = await hub.call("query_artifacts_by_type", artifact_syndoc, 50)
	if not bool(res.get("ok", false)):
		var url_hint := ""
		var req_url := str(res.get("url", "")).strip_edges()
		if not req_url.is_empty():
			url_hint = " (%s)" % req_url
		owner.call("_set_status", "Hub query failed%s: %s" % [url_hint, str(res.get("error", res))])
		return
	var result: Dictionary = res.get("result", {})
	owner.set("_flowdoc_cols", result.get("columns", []))
	owner.set("_flowdoc_rows", result.get("rows", []))
	var flowdocs_list: Tree = owner.get("_flowdocs_list")
	if not flowdocs_list:
		return
	flowdocs_list.clear()
	flowdocs_list.hide_root = true
	flowdocs_list.columns = 2
	var root_item := flowdocs_list.create_item()
	var present_ids: Dictionary = {}
	var flowdoc_rows_any: Variant = owner.get("_flowdoc_rows")
	var flowdoc_rows: Array = flowdoc_rows_any if typeof(flowdoc_rows_any) == TYPE_ARRAY else []
	var flowdoc_cols_any: Variant = owner.get("_flowdoc_cols")
	var flowdoc_cols: Array = flowdoc_cols_any if typeof(flowdoc_cols_any) == TYPE_ARRAY else []
	var checked_ids_any: Variant = owner.get("_checked_syndoc_ids")
	var checked_ids: Dictionary = checked_ids_any if typeof(checked_ids_any) == TYPE_DICTIONARY else {}
	for r in flowdoc_rows:
		if typeof(r) != TYPE_ARRAY:
			continue
		var row: Array = r
		var art_id := str(owner.call("_row_get", flowdoc_cols, row, "id"))
		var created := owner.call("_row_get", flowdoc_cols, row, "created_at")
		var label := "%s  (%s)" % [art_id.left(12), str(created)]
		var checked := checked_ids.has(art_id)
		var it := flowdocs_list.create_item(root_item)
		it.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
		it.set_editable(0, true)
		it.set_checked(0, checked)
		it.set_text(0, "")
		it.set_text(1, label)
		it.set_metadata(1, art_id)
		present_ids[art_id] = true
	for aid in checked_ids.keys():
		if not present_ids.has(str(aid)):
			checked_ids.erase(aid)
	owner.set("_checked_syndoc_ids", checked_ids)
	owner.call("_set_status", "Found %d syndocs." % flowdoc_rows.size())


static func load_selected_closure(owner: Control) -> void:
	var closures_list: Tree = owner.get("_closures_list")
	var sel_item: TreeItem = closures_list.get_selected() if closures_list else null
	if sel_item == null:
		owner.call("_set_status", "Select a closure first.")
		return
	var selected_id := str(sel_item.get_metadata(1)).strip_edges()
	if selected_id.is_empty():
		owner.call("_set_status", "Invalid selection.")
		return
	var browser_mode := str(owner.get("_closure_browser_mode")).strip_edges()
	if browser_mode == "store_closure":
		await _load_store_record(owner, selected_id, "closure_id", owner.get("_store_closure_records"), "Store closure")
		return
	if browser_mode == "store_context_pack":
		await _load_store_record(owner, selected_id, "context_pack_id", owner.get("_store_context_pack_records"), "Store context pack")
		return
	var closure_cols_any: Variant = owner.get("_closure_cols")
	var closure_cols: Array = closure_cols_any if typeof(closure_cols_any) == TYPE_ARRAY else []
	var closure_rows_any: Variant = owner.get("_closure_rows")
	var closure_rows: Array = closure_rows_any if typeof(closure_rows_any) == TYPE_ARRAY else []
	var row: Array = owner.call("_find_row_by_id", closure_cols, closure_rows, selected_id)
	if row.is_empty():
		owner.call("_set_status", "Invalid selection.")
		return
	var active_closure_id := str(owner.call("_row_get", closure_cols, row, "id"))
	var active_closure_uri := str(owner.call("_row_get", closure_cols, row, "uri"))
	owner.set("_active_closure_id", active_closure_id)
	owner.set("_active_closure_uri", active_closure_uri)
	if active_closure_uri.is_empty():
		owner.call("_set_status", "Selected closure has no uri (can't load JSON): %s" % active_closure_id)
		return
	var any := owner.call("_load_json_from_uri", active_closure_uri)
	if typeof(any) != TYPE_DICTIONARY:
		owner.call("_set_status", "Failed to load closure JSON from: %s" % active_closure_uri)
		return
	owner.set("_active_closure_json", any)
	var closure_json: TextEdit = owner.get("_closure_json")
	if closure_json:
		closure_json.text = JSON.stringify(any, "\t")
	var ref_closure: LineEdit = owner.get("_ref_closure")
	if ref_closure:
		ref_closure.text = active_closure_id
	var ref_context_graph: LineEdit = owner.get("_ref_context_graph")
	if ref_context_graph:
		ref_context_graph.text = str(owner.call("_get_closure_context_graph_artifact_id", any))
	var ref_prompt_chain: LineEdit = owner.get("_ref_prompt_chain")
	if ref_prompt_chain and ref_prompt_chain.text.strip_edges().is_empty():
		ref_prompt_chain.text = str(owner.call("_get_closure_prompt_chain_asset_id", any))
	var ref_projection: LineEdit = owner.get("_ref_projection")
	if ref_projection:
		ref_projection.text = str(owner.call("_get_closure_projection_artifact_id", any))
	var ref_cluster: LineEdit = owner.get("_ref_cluster")
	if ref_cluster:
		ref_cluster.text = str(owner.call("_get_closure_cluster_artifact_id", any))
	owner.call("_set_status", "Loaded closure %s" % active_closure_id.left(12))


static func _load_store_record(owner: Control, selected_id: String, id_key: String, records_any: Variant, label: String) -> void:
	var records: Array = records_any if typeof(records_any) == TYPE_ARRAY else []
	for record_any in records:
		if typeof(record_any) != TYPE_DICTIONARY:
			continue
		var record: Dictionary = record_any
		if str(record.get(id_key, "")).strip_edges() != selected_id:
			continue
		owner.set("_active_closure_id", selected_id)
		owner.set("_active_closure_uri", "")
		owner.set("_active_closure_json", record)
		var closure_json: TextEdit = owner.get("_closure_json")
		if closure_json:
			closure_json.text = JSON.stringify(record, "\t")
		var ref_closure: LineEdit = owner.get("_ref_closure")
		if ref_closure:
			ref_closure.text = selected_id
		var ref_context_graph: LineEdit = owner.get("_ref_context_graph")
		if ref_context_graph:
			ref_context_graph.text = ""
		var ref_projection: LineEdit = owner.get("_ref_projection")
		if ref_projection:
			ref_projection.text = ""
		var ref_cluster: LineEdit = owner.get("_ref_cluster")
		if ref_cluster:
			ref_cluster.text = ""
		owner.call("_set_status", "Loaded %s %s" % [label.to_lower(), selected_id.left(12)])
		if owner.has_method("_perform_store_record_on_atlas"):
			await owner.call("_perform_store_record_on_atlas", record, label)
		return
	owner.call("_set_status", "%s not found: %s" % [label, selected_id])


static func focus_design_syndoc_tab(owner: Control) -> void:
	var root: Node = owner.get("_root")
	if not root:
		return
	var mode_tabs := root.get_node_or_null("Body/Right/ModeTabs") as TabContainer
	if mode_tabs:
		var design := mode_tabs.get_node_or_null("Design") as Control
		if design:
			mode_tabs.current_tab = mode_tabs.get_tab_idx_from_control(design)
	var design_tabs := root.get_node_or_null("Body/Right/ModeTabs/Design") as TabContainer
	if design_tabs:
		var syndoc := design_tabs.get_node_or_null("SynDoc") as Control
		if syndoc:
			design_tabs.current_tab = design_tabs.get_tab_idx_from_control(syndoc)


static func load_selected_flowdoc(owner: Control) -> void:
	var flowdocs_list: Tree = owner.get("_flowdocs_list")
	var sel_item: TreeItem = flowdocs_list.get_selected() if flowdocs_list else null
	if sel_item == null:
		owner.call("_set_status", "Select a SynDoc first.")
		return
	var selected_id := str(sel_item.get_metadata(1)).strip_edges()
	if selected_id.is_empty():
		owner.call("_set_status", "Invalid selection.")
		return
	var flowdoc_cols_any: Variant = owner.get("_flowdoc_cols")
	var flowdoc_cols: Array = flowdoc_cols_any if typeof(flowdoc_cols_any) == TYPE_ARRAY else []
	var flowdoc_rows_any: Variant = owner.get("_flowdoc_rows")
	var flowdoc_rows: Array = flowdoc_rows_any if typeof(flowdoc_rows_any) == TYPE_ARRAY else []
	var row: Array = owner.call("_find_row_by_id", flowdoc_cols, flowdoc_rows, selected_id)
	if row.is_empty():
		owner.call("_set_status", "Invalid selection.")
		return
	var active_flowdoc_id := str(owner.call("_row_get", flowdoc_cols, row, "id"))
	var active_flowdoc_uri := str(owner.call("_row_get", flowdoc_cols, row, "uri"))
	owner.set("_active_flowdoc_id", active_flowdoc_id)
	owner.set("_active_flowdoc_uri", active_flowdoc_uri)
	if active_flowdoc_uri.is_empty():
		owner.call("_set_status", "Selected SynDoc has no uri (can't load JSON): %s" % active_flowdoc_id)
		return
	var any := owner.call("_load_json_from_uri", active_flowdoc_uri)
	if typeof(any) != TYPE_DICTIONARY:
		owner.call("_set_status", "Failed to load SynDoc JSON from: %s" % active_flowdoc_uri)
		return
	var flowdoc: Dictionary = any
	owner.set("_flowdoc_model", flowdoc)
	var flowdoc_title: LineEdit = owner.get("_flowdoc_title")
	if flowdoc_title:
		flowdoc_title.text = str(flowdoc.get("title", "")).strip_edges()
	var flowdoc_json: TextEdit = owner.get("_flowdoc_json")
	if flowdoc_json:
		flowdoc_json.text = JSON.stringify(flowdoc, "\t")
	owner.call("_sync_from_raw_json")
	focus_design_syndoc_tab(owner)
	owner.call("_set_status", "Loaded SynDoc %s" % active_flowdoc_id.left(12))
