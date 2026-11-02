extends RefCounted
class_name SynpunktRenderWorkflowSelectorUtils

const WorkflowUtilsScript = preload("res://addons/synpunkt/scripts/internal/render_workflow_utils.gd")

static func _metadata_dict_from_text(txt: String) -> Dictionary:
	var raw := String(txt).strip_edges()
	if raw.is_empty():
		return {}
	var any: Variant = JSON.parse_string(raw)
	return any if typeof(any) == TYPE_DICTIONARY else {}


static func _split_tags(raw: String) -> Array[String]:
	var out: Array[String] = []
	for part_any in String(raw).split(",", false):
		var t := str(part_any).strip_edges().to_lower()
		if t.is_empty():
			continue
		if not out.has(t):
			out.append(t)
	return out


static func _selected_workflow_artifact_id(owner: Control) -> String:
	var last_meta_any: Variant = owner.get("_last_workflow_select_meta")
	var last_meta: Dictionary = last_meta_any if typeof(last_meta_any) == TYPE_DICTIONARY else {}
	if str(last_meta.get("kind", "")).strip_edges() == "workflow":
		return str(last_meta.get("artifact_id", "")).strip_edges()
	return ""


static func _load_preset_lineage_and_version(owner: Control, selected_workflow_id: String) -> Dictionary:
	var lineage_id := String(selected_workflow_id).strip_edges()
	var base_version := 0
	var hub: Object = owner.get("_hub")
	if lineage_id.is_empty() or not hub:
		return {"lineage_id": lineage_id, "base_version": base_version}
	var rec_res: Dictionary = await hub.get_artifact_record_by_id(lineage_id)
	if bool(rec_res.get("ok", false)):
		var result: Dictionary = rec_res.get("result", {})
		var cols: Array = result.get("columns", [])
		var rows_any: Variant = result.get("rows", [])
		var rows: Array = rows_any if typeof(rows_any) == TYPE_ARRAY else []
		if rows.size() > 0 and typeof(rows[0]) == TYPE_ARRAY:
			var row: Array = rows[0]
			var meta_txt := str(owner.call("_row_get", cols, row, "metadata_json")).strip_edges()
			var md := _metadata_dict_from_text(meta_txt)
			var preset_any: Variant = md.get("preset", {})
			var preset: Dictionary = preset_any if typeof(preset_any) == TYPE_DICTIONARY else {}
			var existing_lineage := str(preset.get("lineage_id", "")).strip_edges()
			if not existing_lineage.is_empty():
				lineage_id = existing_lineage
			base_version = maxi(base_version, int(preset.get("version", 0)))
	return {"lineage_id": lineage_id, "base_version": base_version}


static func _max_preset_version_for_lineage(owner: Control, lineage_id: String) -> int:
	var lid := String(lineage_id).strip_edges()
	if lid.is_empty():
		return 0
	var hub: Object = owner.get("_hub")
	if not hub:
		return 0
	var res: Dictionary = await hub.query_artifacts_by_type("json.workflow", 200)
	if not bool(res.get("ok", false)):
		return 0
	var result: Dictionary = res.get("result", {})
	var cols: Array = result.get("columns", [])
	var rows_any: Variant = result.get("rows", [])
	var rows: Array = rows_any if typeof(rows_any) == TYPE_ARRAY else []
	var vmax := 0
	for r_any in rows:
		if typeof(r_any) != TYPE_ARRAY:
			continue
		var row: Array = r_any
		var meta_txt := str(owner.call("_row_get", cols, row, "metadata_json")).strip_edges()
		var md := _metadata_dict_from_text(meta_txt)
		var preset_any: Variant = md.get("preset", {})
		var preset: Dictionary = preset_any if typeof(preset_any) == TYPE_DICTIONARY else {}
		if str(preset.get("lineage_id", "")).strip_edges() != lid:
			continue
		vmax = maxi(vmax, int(preset.get("version", 0)))
	return vmax

static func select_workflow_in_selector(owner: Control, artifact_id: String) -> void:
	var workflow_select: OptionButton = owner.get("_workflow_select")
	if not workflow_select:
		return
	var target := String(artifact_id).strip_edges()
	if target.is_empty():
		return
	for i in range(workflow_select.item_count):
		var md: Variant = workflow_select.get_item_metadata(i)
		if typeof(md) != TYPE_DICTIONARY:
			continue
		var meta: Dictionary = md
		if str(meta.get("kind", "")) == "workflow" and str(meta.get("artifact_id", "")).strip_edges() == target:
			workflow_select.select(i)
			return


static func on_save_workflow_preset(owner: Control) -> void:
	var hub: Node = owner.get("_hub")
	if not hub:
		owner.call("_set_status", "Render: hub client not initialized")
		return
	var workflow_json: TextEdit = owner.get("_workflow_json")
	if not workflow_json:
		owner.call("_set_status", "Render: no workflow JSON field")
		return
	var raw := workflow_json.text
	var wf_any: Variant = JSON.parse_string(raw)
	if typeof(wf_any) != TYPE_DICTIONARY:
		owner.call("_set_status", "Render: invalid workflow JSON")
		return
	var wf_wrapped: Dictionary = wf_any
	var wf_norm: Dictionary = WorkflowUtilsScript.extract_comfy_prompt_graph(wf_wrapped)
	if not bool(wf_norm.get("ok", false)):
		owner.call("_set_status", "Render: %s" % str(wf_norm.get("error", "workflow_invalid")))
		return
	var workflow: Dictionary = wf_norm.get("prompt", {})
	var workflow_hash := WorkflowUtilsScript.hash_sha256_hex(WorkflowUtilsScript.canonical_json_bytes(workflow))
	var selected_workflow_id := _selected_workflow_artifact_id(owner)
	var lineage_meta := await _load_preset_lineage_and_version(owner, selected_workflow_id)
	var lineage_id := str(lineage_meta.get("lineage_id", selected_workflow_id)).strip_edges()
	if lineage_id.is_empty():
		lineage_id = selected_workflow_id
	var max_ver := await _max_preset_version_for_lineage(owner, lineage_id)
	var next_ver := max(1, max_ver + 1)
	var preset_name := str(owner.get("_render_recipe_name").text if owner.get("_render_recipe_name") else "").strip_edges()
	if preset_name.is_empty():
		preset_name = "Workflow preset"
	var preset_tags := _split_tags(str(owner.get("_preset_tags").text if owner.get("_preset_tags") else ""))
	var model_family := str(owner.get("_preset_model_family").text if owner.get("_preset_model_family") else "").strip_edges()
	var model_ids := WorkflowUtilsScript.extract_model_identifiers_from_workflow(workflow)
	if model_family.is_empty() and model_ids.size() > 0:
		model_family = str(model_ids[0]).strip_edges()
	var preset_meta := {
		"name": preset_name,
		"tags": preset_tags,
		"model_family": model_family,
		"lineage_id": lineage_id,
		"version": next_ver,
		"last_used_at": int(Time.get_unix_time_from_system()),
		"archived": false,
	}
	var workflow_artifact_id := await owner.call("_find_existing_workflow_artifact_id_by_hash", workflow_hash)
	var seen_any: Variant = owner.get("_render_seen_workflow_hash_to_workflow_id")
	var seen: Dictionary = seen_any if typeof(seen_any) == TYPE_DICTIONARY else {}
	if not workflow_artifact_id.is_empty():
		var hub_reuse: Object = owner.get("_hub")
		if hub_reuse:
			await hub_reuse.update_artifact_metadata(workflow_artifact_id, {"preset": preset_meta}, true)
		seen[workflow_hash] = workflow_artifact_id
		owner.set("_render_seen_workflow_hash_to_workflow_id", seen)
		owner.set("_last_saved_workflow_artifact_id", workflow_artifact_id)
		if owner.get("_workflow_select"):
			await refresh_render_workflow_selector(owner)
			select_workflow_in_selector(owner, workflow_artifact_id)
		owner.call("_set_status", "Render: reused existing workflow preset: %s (v%d)." % [workflow_artifact_id.left(12), int(preset_meta.get("version", 1))])
		return
	var meta := {
		"provenance": {"generated_by": "synpunkt.workflow.preset", "session_id": owner.get("_session_id"), "workflow_hash_sha256": workflow_hash},
		"preset": preset_meta,
	}
	var wf_res: Dictionary = await hub.create_artifact_inline_json("json.workflow", workflow, meta)
	workflow_artifact_id = str(wf_res.get("id", wf_res.get("artifact_id", ""))).strip_edges()
	if workflow_artifact_id.is_empty():
		owner.call("_set_status", "Render: failed to save workflow preset: %s" % str(wf_res.get("error", wf_res)))
		return
	seen[workflow_hash] = workflow_artifact_id
	owner.set("_render_seen_workflow_hash_to_workflow_id", seen)
	owner.set("_last_saved_workflow_artifact_id", workflow_artifact_id)
	if owner.get("_workflow_select"):
		await refresh_render_workflow_selector(owner)
		select_workflow_in_selector(owner, workflow_artifact_id)
	owner.call("_set_status", "Render: saved workflow preset: %s (v%d)." % [workflow_artifact_id.left(12), int(preset_meta.get("version", 1))])


static func init_workflow_selector(owner: Control) -> void:
	var workflow_select: OptionButton = owner.get("_workflow_select")
	if not workflow_select:
		return
	workflow_select.clear()
	workflow_select.add_item("(select an action…)", 0)
	workflow_select.set_item_metadata(0, {"kind": "placeholder"})
	workflow_select.add_item("Refresh saved presets (json.workflow)", 1)
	workflow_select.set_item_metadata(1, {"kind": "refresh_workflows"})
	workflow_select.add_item("Refresh render history (json.render_request)", 2)
	workflow_select.set_item_metadata(2, {"kind": "refresh_render_requests"})
	workflow_select.select(0)


static func kick_refresh_render_workflow_selector(owner: Control) -> void:
	await refresh_render_workflow_selector(owner)
	var render_workflow_options_any: Variant = owner.get("_render_workflow_options")
	var render_workflow_options: Array = render_workflow_options_any if typeof(render_workflow_options_any) == TYPE_ARRAY else []
	if render_workflow_options.is_empty():
		await refresh_render_request_selector(owner)


static func refresh_render_workflow_selector(owner: Control) -> void:
	var workflow_select: OptionButton = owner.get("_workflow_select")
	var hub: Node = owner.get("_hub")
	if not workflow_select or not hub:
		return
	owner.call("_set_status", "Render [hub/substrate]: querying json.workflow…")
	var res: Dictionary = await hub.query_artifacts_by_type("json.workflow", 50)
	if not bool(res.get("ok", false)):
		owner.call("_set_status", owner.call("_render_error_status", "workflow_query", {"routing": {"mode": "hub", "provider": "substrate"}, "error": res.get("error", res)}))
		return
	var result: Dictionary = res.get("result", {})
	var cols: Array = result.get("columns", [])
	var rows: Array = result.get("rows", [])
	var render_workflow_options: Array = []
	for r_any in rows:
		if typeof(r_any) != TYPE_ARRAY:
			continue
		var row: Array = r_any
		var aid := str(owner.call("_row_get", cols, row, "id"))
		if aid.is_empty():
			continue
		var created := str(owner.call("_row_get", cols, row, "created_at"))
		var meta_txt := str(owner.call("_row_get", cols, row, "metadata_json")).strip_edges()
		var md := _metadata_dict_from_text(meta_txt)
		var preset_any: Variant = md.get("preset", {})
		var preset: Dictionary = preset_any if typeof(preset_any) == TYPE_DICTIONARY else {}
		var archived := bool(preset.get("archived", false))
		render_workflow_options.append({"artifact_id": aid, "created_at": created, "preset": preset, "archived": archived})
	owner.set("_render_workflow_options", render_workflow_options)
	init_workflow_selector(owner)
	if render_workflow_options.is_empty():
		var last_saved_workflow_artifact_id := str(owner.get("_last_saved_workflow_artifact_id")).strip_edges()
		if not last_saved_workflow_artifact_id.is_empty():
			workflow_select.add_item("— This session —", workflow_select.item_count)
			workflow_select.set_item_disabled(workflow_select.item_count - 1, true)
			workflow_select.set_item_metadata(workflow_select.item_count - 1, {"kind": "header"})
			workflow_select.add_item(last_saved_workflow_artifact_id.left(12) + "  (just saved)", workflow_select.item_count)
			workflow_select.set_item_metadata(workflow_select.item_count - 1, {"kind": "workflow", "artifact_id": last_saved_workflow_artifact_id})
		workflow_select.add_item("(no json.workflow artifacts found)", workflow_select.item_count)
		workflow_select.set_item_metadata(workflow_select.item_count - 1, {"kind": "info"})
	else:
		workflow_select.add_item("— Saved presets —", workflow_select.item_count)
		workflow_select.set_item_disabled(workflow_select.item_count - 1, true)
		workflow_select.set_item_metadata(workflow_select.item_count - 1, {"kind": "header"})
		for opt_any in render_workflow_options:
			var opt: Dictionary = opt_any if typeof(opt_any) == TYPE_DICTIONARY else {}
			var aid2 := str(opt.get("artifact_id", "")).strip_edges()
			var created2 := str(opt.get("created_at", "")).strip_edges()
			var preset_any: Variant = opt.get("preset", {})
			var preset: Dictionary = preset_any if typeof(preset_any) == TYPE_DICTIONARY else {}
			var name := str(preset.get("name", "")).strip_edges()
			var version := int(preset.get("version", 0))
			var archived := bool(opt.get("archived", false))
			var label := "%s%s%s  (%s)" % [
				("%s " % name) if not name.is_empty() else "",
				("v%d " % version) if version > 0 else "",
				aid2.left(12),
				created2
			]
			if archived:
				label = "[archived] " + label
			workflow_select.add_item(label, workflow_select.item_count)
			workflow_select.set_item_metadata(workflow_select.item_count - 1, {"kind": "workflow", "artifact_id": aid2, "preset": preset, "archived": archived})
	workflow_select.select(0)
	owner.call("_set_status", "Render [hub/substrate]: found %d saved workflows." % render_workflow_options.size())


static func refresh_render_request_selector(owner: Control) -> void:
	var workflow_select: OptionButton = owner.get("_workflow_select")
	var hub: Node = owner.get("_hub")
	if not workflow_select or not hub:
		return
	owner.call("_set_status", "Render [hub/substrate]: querying json.render_request…")
	var res: Dictionary = await hub.query_artifacts_by_type("json.render_request", 50)
	if not bool(res.get("ok", false)):
		owner.call("_set_status", owner.call("_render_error_status", "render_request_query", {"routing": {"mode": "hub", "provider": "substrate"}, "error": res.get("error", res)}))
		return
	var result: Dictionary = res.get("result", {})
	var cols: Array = result.get("columns", [])
	var rows: Array = result.get("rows", [])
	var render_request_options: Array = []
	for r_any in rows:
		if typeof(r_any) != TYPE_ARRAY:
			continue
		var row: Array = r_any
		var aid := str(owner.call("_row_get", cols, row, "id"))
		if aid.is_empty():
			continue
		var created := str(owner.call("_row_get", cols, row, "created_at"))
		render_request_options.append({"artifact_id": aid, "created_at": created})
	owner.set("_render_request_options", render_request_options)
	var workflows_copy_any: Variant = owner.get("_render_workflow_options")
	var workflows_copy: Array = (workflows_copy_any if typeof(workflows_copy_any) == TYPE_ARRAY else []).duplicate(true)
	init_workflow_selector(owner)
	owner.set("_render_workflow_options", workflows_copy)
	if workflows_copy.size() > 0:
		workflow_select.add_item("— Saved presets —", workflow_select.item_count)
		workflow_select.set_item_disabled(workflow_select.item_count - 1, true)
		workflow_select.set_item_metadata(workflow_select.item_count - 1, {"kind": "header"})
		for opt_any in workflows_copy:
			var opt: Dictionary = opt_any if typeof(opt_any) == TYPE_DICTIONARY else {}
			var aidw := str(opt.get("artifact_id", "")).strip_edges()
			var createdw := str(opt.get("created_at", "")).strip_edges()
			var preset_any: Variant = opt.get("preset", {})
			var preset: Dictionary = preset_any if typeof(preset_any) == TYPE_DICTIONARY else {}
			var name := str(preset.get("name", "")).strip_edges()
			var version := int(preset.get("version", 0))
			var archived := bool(opt.get("archived", false))
			var labelw := "%s%s%s  (%s)" % [
				("%s " % name) if not name.is_empty() else "",
				("v%d " % version) if version > 0 else "",
				aidw.left(12),
				createdw
			]
			if archived:
				labelw = "[archived] " + labelw
			workflow_select.add_item(labelw, workflow_select.item_count)
			workflow_select.set_item_metadata(workflow_select.item_count - 1, {"kind": "workflow", "artifact_id": aidw, "preset": preset, "archived": archived})
	else:
		workflow_select.add_item("(no json.workflow artifacts found)", workflow_select.item_count)
		workflow_select.set_item_metadata(workflow_select.item_count - 1, {"kind": "info"})
	if render_request_options.is_empty():
		workflow_select.add_item("(no json.render_request artifacts found)", workflow_select.item_count)
		workflow_select.set_item_metadata(workflow_select.item_count - 1, {"kind": "info"})
	else:
		workflow_select.add_item("— Render history —", workflow_select.item_count)
		workflow_select.set_item_disabled(workflow_select.item_count - 1, true)
		workflow_select.set_item_metadata(workflow_select.item_count - 1, {"kind": "header"})
		for opt_any2 in render_request_options:
			var opt2: Dictionary = opt_any2 if typeof(opt_any2) == TYPE_DICTIONARY else {}
			var aid2 := str(opt2.get("artifact_id", "")).strip_edges()
			var created2 := str(opt2.get("created_at", "")).strip_edges()
			var label2 := "%s  (%s)" % [aid2.left(12), created2]
			workflow_select.add_item(label2, workflow_select.item_count)
			workflow_select.set_item_metadata(workflow_select.item_count - 1, {"kind": "render_request", "artifact_id": aid2})
	workflow_select.select(0)
	owner.call("_set_status", "Render [hub/substrate]: found %d render requests." % render_request_options.size())


static func on_render_workflow_selected(owner: Control, idx: int) -> void:
	var workflow_select: OptionButton = owner.get("_workflow_select")
	if not workflow_select:
		return
	var meta := workflow_select.get_item_metadata(idx)
	if meta == null or typeof(meta) != TYPE_DICTIONARY:
		owner.set("_last_workflow_select_meta", {})
		return
	var m: Dictionary = meta
	owner.set("_last_workflow_select_meta", m.duplicate(true))
	var kind := str(m.get("kind", "")).strip_edges()
	if kind == "refresh_workflows":
		await refresh_render_workflow_selector(owner)
		return
	if kind == "refresh_render_requests":
		await refresh_render_request_selector(owner)
		return
	if kind != "workflow":
		if kind != "render_request":
			return
		var rr_id := str(m.get("artifact_id", "")).strip_edges()
		if rr_id.is_empty() or not owner.get("_hub"):
			return
		await owner.call("_load_workflow_from_render_request_artifact", rr_id)
		return
	var aid := str(m.get("artifact_id", "")).strip_edges()
	if aid.is_empty():
		return
	var hub: Node = owner.get("_hub")
	if not hub:
		return
	var touched: Dictionary = await hub.update_artifact_metadata(aid, {"preset": {"last_used_at": int(Time.get_unix_time_from_system())}}, true)
	if not bool(touched.get("ok", false)):
		push_warning("SynPunkt preset usage touch failed: %s" % str(touched.get("error", touched)))
	owner.call("_set_status", "Render playback [hub/substrate]: loading workflow %s…" % aid.left(12))
	var fetched: Dictionary = await hub.get_artifact_json(aid)
	if not bool(fetched.get("ok", false)):
		owner.call("_set_status", owner.call("_render_error_status", "playback_workflow", {"routing": {"mode": "hub", "provider": "substrate"}, "error": fetched.get("error", fetched)}))
		return
	var wf_any: Variant = fetched.get("json", {})
	if typeof(wf_any) != TYPE_DICTIONARY:
		owner.call("_set_status", owner.call("_render_error_status", "playback_workflow", {"routing": {"mode": "hub", "provider": "substrate"}, "error": "workflow artifact JSON invalid"}))
		return
	var workflow_json: TextEdit = owner.get("_workflow_json")
	if workflow_json:
		workflow_json.text = JSON.stringify(wf_any, "\t")
		owner.call("_sync_common_params_from_workflow_json", false)
	owner.call("_set_status", "Render playback [hub/substrate]: loaded workflow %s into Workflow JSON." % aid.left(12))


static func delete_selected_render_request_artifact(owner: Control) -> void:
	var hub: Node = owner.get("_hub")
	if not hub:
		owner.call("_set_status", "Render: hub client not initialized.")
		return
	var last_meta_any: Variant = owner.get("_last_workflow_select_meta")
	var last_meta: Dictionary = last_meta_any if typeof(last_meta_any) == TYPE_DICTIONARY else {}
	var kind := str(last_meta.get("kind", "")).strip_edges()
	if kind != "render_request":
		owner.call("_set_status", "Render: select an item under Render history first.")
		return
	var rr_id := str(last_meta.get("artifact_id", "")).strip_edges()
	if rr_id.is_empty():
		owner.call("_set_status", "Render: selected history item has no artifact id.")
		return
	var del_res: Dictionary = await hub.delete_artifact(rr_id, true)
	if not bool(del_res.get("ok", false)):
		owner.call("_set_status", "Render: failed deleting render_request %s: %s" % [rr_id.left(12), owner.call("_error_details_text", del_res)])
		return
	await refresh_render_request_selector(owner)
	owner.set("_last_workflow_select_meta", {})
	owner.call("_set_status", "Render: deleted render_request %s." % rr_id.left(12))


static func on_save_preset_version(owner: Control) -> void:
	# Uses the same save pipeline but guarantees lineage/version progression.
	await on_save_workflow_preset(owner)


static func on_diff_selected_preset(owner: Control) -> void:
	var selected_id := _selected_workflow_artifact_id(owner)
	if selected_id.is_empty():
		owner.call("_set_status", "Preset diff: select a workflow preset first.")
		return
	var hub: Object = owner.get("_hub")
	if not hub:
		owner.call("_set_status", "Preset diff: hub client not initialized.")
		return
	var fetched: Dictionary = await hub.get_artifact_json(selected_id)
	if not bool(fetched.get("ok", false)):
		owner.call("_set_status", owner.call("_render_error_status", "preset_diff_load", fetched))
		return
	var selected_wf_any: Variant = fetched.get("json", {})
	if typeof(selected_wf_any) != TYPE_DICTIONARY:
		owner.call("_set_status", "Preset diff: selected preset workflow JSON invalid.")
		return
	var workflow_json: TextEdit = owner.get("_workflow_json")
	if not workflow_json:
		owner.call("_set_status", "Preset diff: Workflow JSON field not found.")
		return
	var current_any: Variant = JSON.parse_string(workflow_json.text.strip_edges())
	if typeof(current_any) != TYPE_DICTIONARY:
		owner.call("_set_status", "Preset diff: current Workflow JSON is invalid.")
		return
	var selected_wf: Dictionary = selected_wf_any
	var current_wf: Dictionary = current_any
	var selected_keys := selected_wf.keys()
	var current_keys := current_wf.keys()
	var added := 0
	var removed := 0
	var changed := 0
	for k in current_keys:
		if not selected_wf.has(k):
			added += 1
		else:
			if JSON.stringify(current_wf.get(k, {}), "", true) != JSON.stringify(selected_wf.get(k, {}), "", true):
				changed += 1
	for k2 in selected_keys:
		if not current_wf.has(k2):
			removed += 1
	var summary := "Preset diff vs %s: +%d nodes, -%d nodes, ~%d changed (selected=%d, current=%d)." % [
		selected_id.left(12),
		added,
		removed,
		changed,
		selected_keys.size(),
		current_keys.size(),
	]
	DisplayServer.clipboard_set(summary)
	owner.call("_set_status", summary + " Copied summary to clipboard.")


static func on_archive_selected_preset(owner: Control) -> void:
	var selected_id := _selected_workflow_artifact_id(owner)
	if selected_id.is_empty():
		owner.call("_set_status", "Archive preset: select a workflow preset first.")
		return
	var hub: Object = owner.get("_hub")
	if not hub:
		owner.call("_set_status", "Archive preset: hub client not initialized.")
		return
	var patch := {"preset": {"archived": true, "archived_at": int(Time.get_unix_time_from_system())}}
	var res: Dictionary = await hub.update_artifact_metadata(selected_id, patch, true)
	if not bool(res.get("ok", false)):
		owner.call("_set_status", owner.call("_render_error_status", "preset_archive", res))
		return
	await refresh_render_workflow_selector(owner)
	owner.call("_set_status", "Archived workflow preset %s." % selected_id.left(12))


static func on_prune_archived_preset(owner: Control) -> void:
	var selected_id := _selected_workflow_artifact_id(owner)
	if selected_id.is_empty():
		owner.call("_set_status", "Prune preset: select a workflow preset first.")
		return
	var hub: Object = owner.get("_hub")
	if not hub:
		owner.call("_set_status", "Prune preset: hub client not initialized.")
		return
	var rec: Dictionary = await hub.get_artifact_record_by_id(selected_id)
	if not bool(rec.get("ok", false)):
		owner.call("_set_status", owner.call("_render_error_status", "preset_prune_record", rec))
		return
	var result: Dictionary = rec.get("result", {})
	var cols: Array = result.get("columns", [])
	var rows_any: Variant = result.get("rows", [])
	var rows: Array = rows_any if typeof(rows_any) == TYPE_ARRAY else []
	if rows.is_empty() or typeof(rows[0]) != TYPE_ARRAY:
		owner.call("_set_status", "Prune preset: selected record not found.")
		return
	var row: Array = rows[0]
	var meta_txt := str(owner.call("_row_get", cols, row, "metadata_json")).strip_edges()
	var md := _metadata_dict_from_text(meta_txt)
	var preset_any: Variant = md.get("preset", {})
	var preset: Dictionary = preset_any if typeof(preset_any) == TYPE_DICTIONARY else {}
	var archived := bool(preset.get("archived", false))
	if not archived:
		owner.call("_set_status", "Prune preset blocked: archive it first (safety check).")
		return
	var del_res: Dictionary = await hub.delete_artifact(selected_id, true)
	if not bool(del_res.get("ok", false)):
		owner.call("_set_status", owner.call("_render_error_status", "preset_prune_delete", del_res))
		return
	await refresh_render_workflow_selector(owner)
	owner.call("_set_status", "Pruned archived preset %s." % selected_id.left(12))
