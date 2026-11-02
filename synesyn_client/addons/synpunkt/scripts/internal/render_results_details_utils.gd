extends RefCounted
class_name SynpunktRenderResultsDetailsUtils

static func refresh_render_results_from_hub(owner: Control, limit: int = 200, source: String = "auto") -> void:
	owner.call("_ensure_render_results_bound")
	var rr: ItemList = owner.get("_render_results")
	if not rr:
		return
	var hub: Object = owner.get("_hub")
	if not hub:
		owner.call("_set_render_results_refresh_meta", source, 0, false, "hub_client_not_initialized")
		owner.call("_set_status", "Render: hub client not initialized.")
		return
	var q: Dictionary = await hub.call("query_artifacts_by_type", "image.generated", limit)
	if not bool(q.get("ok", false)):
		var q_err: Variant = q.get("error", q)
		owner.call("_set_render_results_refresh_meta", source, 0, false, str(q_err))
		owner.call("_set_status", owner.call("_render_error_status", "results_query", q_err))
		return
	var result: Dictionary = q.get("result", {})
	var cols: Array = result.get("columns", [])
	var rows: Array = result.get("rows", [])
	var cache: Array = []
	for r_any in rows:
		if typeof(r_any) != TYPE_ARRAY:
			continue
		var row: Array = r_any
		var aid := str(owner.call("_row_get", cols, row, "id")).strip_edges()
		if aid.is_empty():
			continue
		var created := str(owner.call("_row_get", cols, row, "created_at")).strip_edges()
		var meta_txt := str(owner.call("_row_get", cols, row, "metadata_json")).strip_edges()
		if meta_txt.is_empty():
			meta_txt = str(owner.call("_row_get", cols, row, "metadata")).strip_edges()
		if meta_txt.is_empty():
			meta_txt = str(owner.call("_row_get", cols, row, "meta_json")).strip_edges()
		var uri := str(owner.call("_row_get", cols, row, "uri")).strip_edges()
		var h := str(owner.call("_row_get", cols, row, "hash")).strip_edges()
		var at := str(owner.call("_row_get", cols, row, "artifact_type")).strip_edges()
		cache.append(
			{
				"artifact_id": aid,
				"created_at": created,
				"metadata_json": meta_txt,
				"uri": uri,
				"hash": h,
				"artifact_type": at,
			}
		)
	owner.set("_render_results_cache", cache)
	apply_render_results_view(owner)
	owner.call("_set_render_results_refresh_meta", source, cache.size(), true, "")
	owner.call("_set_status", "Render: loaded %d image artifacts from workspace." % cache.size())


static func parse_created_at_float(created_at: String) -> float:
	var s := String(created_at).strip_edges()
	if s.is_empty():
		return 0.0
	return float(s)


static func parse_render_filter_query(q_raw: String) -> Dictionary:
	var out := {
		"text_terms": [],
		"require_workflow": false,
		"require_request": false,
		"require_prompt": false,
		"require_any_link": false,
		"require_missing_workflow": false,
		"require_missing_request": false,
		"require_missing_prompt": false,
		"last_window_sec": 0.0,
		"view_mode": "default", # default | compact | expanded
	}
	var text_terms: Array[String] = []
	for tok_any in String(q_raw).split(" ", false):
		var tok := String(tok_any).strip_edges()
		if tok.is_empty():
			continue
		match tok:
			"has:workflow", "has:wf":
				out["require_workflow"] = true
			"has:request", "has:rr":
				out["require_request"] = true
			"has:prompt", "has:pr":
				out["require_prompt"] = true
			"has:link", "has:links":
				out["require_any_link"] = true
			"missing:workflow", "missing:wf":
				out["require_missing_workflow"] = true
			"missing:request", "missing:rr":
				out["require_missing_request"] = true
			"missing:prompt", "missing:pr":
				out["require_missing_prompt"] = true
			"last:24h":
				out["last_window_sec"] = 24.0 * 3600.0
			"last:7d":
				out["last_window_sec"] = 7.0 * 24.0 * 3600.0
			"last:30d":
				out["last_window_sec"] = 30.0 * 24.0 * 3600.0
			"view:compact":
				out["view_mode"] = "compact"
			"view:expanded":
				out["view_mode"] = "expanded"
			_:
				text_terms.append(tok)
	out["text_terms"] = text_terms
	return out


static func render_results_item_label(owner: Control, row: Dictionary, view_mode: String) -> String:
	var aid := str(row.get("artifact_id", "")).strip_edges()
	var created := str(row.get("created_at", "")).strip_edges()
	var meta_txt := str(row.get("metadata_json", "")).strip_edges()
	var name := str(owner.call("_artifact_display_name_for_id", aid, meta_txt)).strip_edges()
	if name.is_empty():
		name = aid.left(12)
	if view_mode == "compact":
		return "%s  (%s)" % [name, aid.left(12)]
	if view_mode == "expanded":
		var uri := str(row.get("uri", "")).strip_edges()
		var ext := str(owner.call("_artifact_ext_from_uri", uri)).strip_edges()
		var when := created if not created.is_empty() else "?"
		return "%s  |  %s  |  %s  |  %s" % [name, aid.left(12), when, ext if not ext.is_empty() else "?"]
	return str(owner.call("_artifact_item_label", aid, created, meta_txt))


static func sort_render_results_rows(owner: Control, rows: Array) -> Array:
	var sorted: Array = rows.duplicate(true)
	var mode := 0
	var sort_ob: OptionButton = owner.get("_render_results_sort")
	if sort_ob:
		mode = int(sort_ob.get_selected_id())
	if mode == 1:
		sorted.sort_custom(func(a_any: Variant, b_any: Variant) -> bool:
			var a: Dictionary = a_any if typeof(a_any) == TYPE_DICTIONARY else {}
			var b: Dictionary = b_any if typeof(b_any) == TYPE_DICTIONARY else {}
			return parse_created_at_float(str(a.get("created_at", ""))) < parse_created_at_float(str(b.get("created_at", "")))
		)
	elif mode == 2:
		sorted.sort_custom(func(a_any: Variant, b_any: Variant) -> bool:
			var a: Dictionary = a_any if typeof(a_any) == TYPE_DICTIONARY else {}
			var b: Dictionary = b_any if typeof(b_any) == TYPE_DICTIONARY else {}
			var an := str(owner.call("_artifact_display_name_for_id", str(a.get("artifact_id", "")), str(a.get("metadata_json", "")))).to_lower()
			var bn := str(owner.call("_artifact_display_name_for_id", str(b.get("artifact_id", "")), str(b.get("metadata_json", "")))).to_lower()
			return an < bn
		)
	else:
		sorted.sort_custom(func(a_any: Variant, b_any: Variant) -> bool:
			var a: Dictionary = a_any if typeof(a_any) == TYPE_DICTIONARY else {}
			var b: Dictionary = b_any if typeof(b_any) == TYPE_DICTIONARY else {}
			return parse_created_at_float(str(a.get("created_at", ""))) > parse_created_at_float(str(b.get("created_at", "")))
		)
	return sorted


static func row_matches_render_filter(owner: Control, row: Dictionary) -> bool:
	var filter_le: LineEdit = owner.get("_render_results_filter")
	var q_raw := filter_le.text.strip_edges().to_lower() if filter_le else ""
	if q_raw.is_empty():
		return true
	var meta_txt := str(row.get("metadata_json", "")).strip_edges()
	var md := owner.call("_metadata_dict_from_text", meta_txt)
	var refs_any: Variant = md.get("refs", {})
	var refs: Dictionary = refs_any if typeof(refs_any) == TYPE_DICTIONARY else {}
	var parsed := parse_render_filter_query(q_raw)
	var text_terms: Array[String] = parsed.get("text_terms", [])
	var require_workflow := bool(parsed.get("require_workflow", false))
	var require_request := bool(parsed.get("require_request", false))
	var require_prompt := bool(parsed.get("require_prompt", false))
	var require_any_link := bool(parsed.get("require_any_link", false))
	var require_missing_workflow := bool(parsed.get("require_missing_workflow", false))
	var require_missing_request := bool(parsed.get("require_missing_request", false))
	var require_missing_prompt := bool(parsed.get("require_missing_prompt", false))
	var last_window_sec := float(parsed.get("last_window_sec", 0.0))
	var wf_id := str(refs.get("workflow_artifact_id", "")).strip_edges()
	var rr_id := str(refs.get("render_request_artifact_id", "")).strip_edges()
	var pr_id := str(refs.get("prompt_artifact_id", "")).strip_edges()
	if require_workflow and wf_id.is_empty():
		return false
	if require_request and rr_id.is_empty():
		return false
	if require_prompt and pr_id.is_empty():
		return false
	if require_any_link and wf_id.is_empty() and rr_id.is_empty() and pr_id.is_empty():
		return false
	if require_missing_workflow and not wf_id.is_empty():
		return false
	if require_missing_request and not rr_id.is_empty():
		return false
	if require_missing_prompt and not pr_id.is_empty():
		return false
	if last_window_sec > 0.0:
		var created_sec := parse_created_at_float(str(row.get("created_at", "")))
		if created_sec <= 0.0:
			return false
		var now_sec := float(Time.get_unix_time_from_system())
		if (now_sec - created_sec) > last_window_sec:
			return false
	if text_terms.is_empty():
		return true
	var needle_parts := [
		str(row.get("artifact_id", "")),
		str(row.get("created_at", "")),
		str(row.get("artifact_type", "")),
		str(row.get("uri", "")),
		str(owner.call("_artifact_display_name_for_id", str(row.get("artifact_id", "")), meta_txt)),
		rr_id,
		wf_id,
		pr_id,
	]
	var haystack := " ".join(needle_parts).to_lower()
	for term in text_terms:
		if haystack.find(term) == -1:
			return false
	return true


static func apply_render_results_view(owner: Control) -> void:
	var rr: ItemList = owner.get("_render_results")
	if not rr:
		return
	var selected_before: Array = owner.call("_get_selected_render_artifact_ids")
	rr.clear()
	rr.add_item("Workspace image artifacts (image.generated)")
	rr.set_item_disabled(0, true)
	rr.set_item_metadata(0, {"kind": "header"})
	var cache_any: Variant = owner.get("_render_results_cache")
	var cache: Array = cache_any if typeof(cache_any) == TYPE_ARRAY else []
	var sorted := sort_render_results_rows(owner, cache)
	var filter_le: LineEdit = owner.get("_render_results_filter")
	var q_raw := filter_le.text.strip_edges().to_lower() if filter_le else ""
	var parsed := parse_render_filter_query(q_raw)
	var view_mode := str(parsed.get("view_mode", "default")).strip_edges()
	for row_any in sorted:
		if typeof(row_any) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_any
		if not row_matches_render_filter(owner, row):
			continue
		var aid := str(row.get("artifact_id", "")).strip_edges()
		if aid.is_empty():
			continue
		var created := str(row.get("created_at", "")).strip_edges()
		var meta_txt := str(row.get("metadata_json", "")).strip_edges()
		var idx := rr.item_count
		rr.add_item(render_results_item_label(owner, row, view_mode))
		rr.set_item_metadata(idx, {"kind": "artifact", "artifact_id": aid, "created_at": created, "metadata_json": meta_txt, "uri": str(row.get("uri", "")), "hash": str(row.get("hash", "")), "artifact_type": str(row.get("artifact_type", ""))})
	if not selected_before.is_empty():
		for i in range(rr.item_count):
			var md: Variant = rr.get_item_metadata(i)
			if md == null or typeof(md) != TYPE_DICTIONARY:
				continue
			var m: Dictionary = md
			var aid2 := str(m.get("artifact_id", "")).strip_edges()
			if selected_before.has(aid2):
				rr.select(i)
	owner.call("_update_render_artifact_details")

