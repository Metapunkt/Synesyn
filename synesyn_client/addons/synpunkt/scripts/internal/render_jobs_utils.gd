extends RefCounted
class_name SynpunktRenderJobsUtils

static func init_render_jobs_ui(owner: Control) -> void:
	var jobs: ItemList = owner.get("_render_jobs_list")
	if not jobs:
		return
	jobs.clear()
	jobs.add_item("Hub render jobs")
	jobs.set_item_disabled(0, true)
	jobs.set_item_metadata(0, {"kind": "header"})


static func _json_dict_from_cell(cell: Variant) -> Dictionary:
	if typeof(cell) == TYPE_DICTIONARY:
		return cell
	var txt := str(cell).strip_edges()
	if txt.is_empty():
		return {}
	# Avoid noisy parser errors for plain text/non-JSON values returned by some backends.
	if not (txt.begins_with("{") and txt.ends_with("}")):
		return {}
	var any: Variant = JSON.parse_string(txt)
	return any if typeof(any) == TYPE_DICTIONARY else {}


static func _job_row_label(owner: Control, row: Dictionary) -> String:
	var job_id := str(row.get("id", "")).strip_edges()
	var status := str(row.get("status", "")).strip_edges()
	var created := str(row.get("created_at", "")).strip_edges()
	var output := _json_dict_from_cell(row.get("output_json", {}))
	var prompt_id := str(output.get("prompt_id", "")).strip_edges()
	var rr_id := str(output.get("render_request_artifact_id", "")).strip_edges()
	var s_prompt := prompt_id.left(12) if not prompt_id.is_empty() else "-"
	var s_rr := rr_id.left(12) if not rr_id.is_empty() else "-"
	var when := created if not created.is_empty() else "?"
	return "%s  %s  | prompt=%s | rr=%s | %s" % [job_id.left(12), status, s_prompt, s_rr, when]


static func refresh_render_jobs(owner: Control, limit: int = 100, source: String = "manual") -> void:
	var jobs: ItemList = owner.get("_render_jobs_list")
	var hub: Object = owner.get("_hub")
	if not jobs:
		return
	if not hub:
		owner.call("_set_status", "Render jobs: hub client not initialized.")
		return
	var res: Dictionary = await hub.call("render_list_jobs", limit)
	if not bool(res.get("ok", false)):
		owner.call("_set_status", owner.call("_render_error_status", "jobs_query", {"routing": {"mode": "hub", "provider": "jobs"}, "error": res.get("error", res)}))
		return
	var result: Dictionary = res.get("result", {})
	var cols: Array = result.get("columns", [])
	var rows_any: Variant = result.get("rows", [])
	var rows: Array = rows_any if typeof(rows_any) == TYPE_ARRAY else []
	var cache: Array = []
	for r_any in rows:
		if typeof(r_any) != TYPE_ARRAY:
			continue
		var r: Array = r_any
		cache.append(
			{
				"id": owner.call("_row_get", cols, r, "id"),
				"job_type": owner.call("_row_get", cols, r, "job_type"),
				"status": owner.call("_row_get", cols, r, "status"),
				"created_at": owner.call("_row_get", cols, r, "created_at"),
				"started_at": owner.call("_row_get", cols, r, "started_at"),
				"completed_at": owner.call("_row_get", cols, r, "completed_at"),
				"input_json": owner.call("_row_get", cols, r, "input_json"),
				"output_json": owner.call("_row_get", cols, r, "output_json"),
				"error": owner.call("_row_get", cols, r, "error"),
				"metadata_json": owner.call("_row_get", cols, r, "metadata_json"),
			}
		)
	owner.set("_render_jobs_cache", cache)
	var selected_job_id := str(owner.get("_last_selected_render_job_id")).strip_edges()
	jobs.clear()
	jobs.add_item("Hub render jobs")
	jobs.set_item_disabled(0, true)
	jobs.set_item_metadata(0, {"kind": "header"})
	for row_any in cache:
		if typeof(row_any) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_any
		var job_id := str(row.get("id", "")).strip_edges()
		if job_id.is_empty():
			continue
		var idx := jobs.item_count
		jobs.add_item(_job_row_label(owner, row))
		jobs.set_item_metadata(idx, {"kind": "job", "job_id": job_id, "status": str(row.get("status", "")).strip_edges(), "row": row})
		if not selected_job_id.is_empty() and selected_job_id == job_id:
			jobs.select(idx)
	owner.call("_set_status", "Render jobs [%s]: loaded %d jobs." % [source, cache.size()])


static func _selected_render_job_meta(owner: Control) -> Dictionary:
	var jobs: ItemList = owner.get("_render_jobs_list")
	if not jobs:
		return {}
	var selected := jobs.get_selected_items()
	if selected.is_empty():
		return {}
	var idx := int(selected[0])
	var md: Variant = jobs.get_item_metadata(idx)
	if md == null or typeof(md) != TYPE_DICTIONARY:
		return {}
	var meta: Dictionary = md
	if str(meta.get("kind", "")) != "job":
		return {}
	return meta


static func on_render_jobs_item_selected(owner: Control, _idx: int) -> void:
	var meta := _selected_render_job_meta(owner)
	if meta.is_empty():
		return
	var job_id := str(meta.get("job_id", "")).strip_edges()
	var status := str(meta.get("status", "")).strip_edges()
	owner.set("_last_selected_render_job_id", job_id)
	owner.call("_set_status", "Render jobs: selected %s (%s)." % [job_id.left(12), status])


static func cancel_selected_render_job(owner: Control) -> void:
	var meta := _selected_render_job_meta(owner)
	if meta.is_empty():
		owner.call("_set_status", "Render jobs: select a job first.")
		return
	var job_id := str(meta.get("job_id", "")).strip_edges()
	var hub: Object = owner.get("_hub")
	if job_id.is_empty() or not hub:
		owner.call("_set_status", "Render jobs: hub client unavailable.")
		return
	var res: Dictionary = await hub.call("render_cancel_job", job_id)
	if not bool(res.get("ok", false)):
		owner.call("_set_status", owner.call("_render_error_status", "jobs_cancel", {"routing": {"mode": "hub", "provider": "jobs"}, "error": res.get("error", res)}))
		return
	await refresh_render_jobs(owner, 100, "cancel")
	owner.call("_set_status", "Render jobs: canceled %s." % job_id.left(12))


static func retry_selected_render_job(owner: Control, source_label: String = "retry") -> void:
	var meta := _selected_render_job_meta(owner)
	if meta.is_empty():
		owner.call("_set_status", "Render jobs: select a job first.")
		return
	var job_id := str(meta.get("job_id", "")).strip_edges()
	var hub: Object = owner.get("_hub")
	if job_id.is_empty() or not hub:
		owner.call("_set_status", "Render jobs: hub client unavailable.")
		return
	var res: Dictionary = await hub.call("render_retry_job", job_id)
	if not bool(res.get("ok", false)):
		owner.call("_set_status", owner.call("_render_error_status", "jobs_retry", {"routing": {"mode": "hub", "provider": "jobs"}, "error": res.get("error", res)}))
		return
	var new_job_id := str(res.get("job_id", "")).strip_edges()
	if not new_job_id.is_empty():
		owner.set("_last_selected_render_job_id", new_job_id)
	await refresh_render_jobs(owner, 100, source_label)
	owner.call("_set_status", "Render jobs: %s -> queued %s." % [job_id.left(12), new_job_id.left(12)])


static func maybe_refresh_jobs_from_event(owner: Control, evt: Dictionary) -> void:
	var et := str(evt.get("event_type", "")).strip_edges()
	if et.begins_with("render.") or et.begins_with("job."):
		owner.call_deferred("_refresh_render_jobs", 100, "event")
