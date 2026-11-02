extends RefCounted
class_name SynpunktArtifactDeleteUtils

static func request_delete_selected(owner: Control, kind: String) -> void:
	var delete_confirm_dialog: ConfirmationDialog = owner.get("_delete_confirm_dialog")
	if not delete_confirm_dialog:
		return
	var artifact_ids: Array[String] = []
	if kind == "closure":
		artifact_ids = owner.call("_tree_collect_checked_ids", owner.get("_closures_list"))
		if artifact_ids.is_empty():
			var closures_list: Tree = owner.get("_closures_list")
			var sel_item: TreeItem = closures_list.get_selected() if closures_list else null
			if sel_item == null:
				owner.call("_set_status", "Select a Closure first.")
				return
			var one := str(sel_item.get_metadata(1)).strip_edges()
			if not one.is_empty():
				artifact_ids.append(one)
	else:
		artifact_ids = owner.call("_tree_collect_checked_ids", owner.get("_flowdocs_list"))
		if artifact_ids.is_empty():
			var flowdocs_list: Tree = owner.get("_flowdocs_list")
			var sel_item2: TreeItem = flowdocs_list.get_selected() if flowdocs_list else null
			if sel_item2 == null:
				owner.call("_set_status", "Select a SynDoc first.")
				return
			var one2 := str(sel_item2.get_metadata(1)).strip_edges()
			if not one2.is_empty():
				artifact_ids.append(one2)
	if artifact_ids.is_empty():
		owner.call("_set_status", "Selected item has no artifact id")
		return
	owner.set("_pending_delete_kind", kind)
	owner.set("_pending_delete_artifact_ids", artifact_ids.duplicate())
	var pending_delete_artifact_ids_any: Variant = owner.get("_pending_delete_artifact_ids")
	var pending_delete_artifact_ids: Array = pending_delete_artifact_ids_any if typeof(pending_delete_artifact_ids_any) == TYPE_ARRAY else []
	var count := pending_delete_artifact_ids.size()
	var sample := ""
	var shown := 0
	for aid in pending_delete_artifact_ids:
		if shown >= 6:
			sample += "…\n"
			break
		sample += "%s\n" % String(aid)
		shown += 1
	delete_confirm_dialog.dialog_text = "Delete %d %s(s)?\n\nThis cannot be undone.\n\nArtifact ids:\n%s" % [count, kind, sample]
	delete_confirm_dialog.popup_centered()


static func delete_pending_artifact_async(owner: Control) -> void:
	var kind := str(owner.get("_pending_delete_kind")).strip_edges()
	var ids_any: Variant = owner.get("_pending_delete_artifact_ids")
	var ids: Array = (ids_any if typeof(ids_any) == TYPE_ARRAY else []).duplicate()
	owner.set("_pending_delete_artifact_ids", [])
	owner.set("_pending_delete_kind", "")
	if ids.is_empty() or kind.is_empty():
		return
	var hub: Node = owner.get("_hub")
	if not is_instance_valid(hub):
		owner.call("_set_status", "Hub client not available")
		return
	if not hub.has_method("delete_artifact"):
		owner.call("_set_status", "Hub client missing delete_artifact")
		return
	var deleted_count := 0
	var failed_ids: Array[String] = []
	var first_error: Variant = null
	for aid_any in ids:
		var aid := String(aid_any).strip_edges()
		if aid.is_empty():
			continue
		var res: Dictionary = await hub.delete_artifact(aid, true)
		if not bool(res.get("ok", false)):
			failed_ids.append(aid)
			if first_error == null:
				first_error = res.get("error", res)
			continue
		deleted_count += 1
		if kind == "closure" and str(owner.get("_active_closure_id")) == aid:
			owner.set("_active_closure_id", "")
			owner.set("_active_closure_uri", "")
			owner.set("_active_closure_json", {})
			var closure_json: TextEdit = owner.get("_closure_json")
			if closure_json:
				closure_json.text = ""
		if kind == "syndoc" and str(owner.get("_active_flowdoc_id")) == aid:
			owner.set("_active_flowdoc_id", "")
			owner.set("_active_flowdoc_uri", "")
			owner.set("_flowdoc_model", {})
			var flowdoc_title: LineEdit = owner.get("_flowdoc_title")
			if flowdoc_title:
				flowdoc_title.text = ""
			var flowdoc_json: TextEdit = owner.get("_flowdoc_json")
			if flowdoc_json:
				flowdoc_json.text = ""
		if kind == "closure":
			var checked_closure_ids_any: Variant = owner.get("_checked_closure_ids")
			var checked_closure_ids: Dictionary = checked_closure_ids_any if typeof(checked_closure_ids_any) == TYPE_DICTIONARY else {}
			checked_closure_ids.erase(aid)
			owner.set("_checked_closure_ids", checked_closure_ids)
		else:
			var checked_syndoc_ids_any: Variant = owner.get("_checked_syndoc_ids")
			var checked_syndoc_ids: Dictionary = checked_syndoc_ids_any if typeof(checked_syndoc_ids_any) == TYPE_DICTIONARY else {}
			checked_syndoc_ids.erase(aid)
			owner.set("_checked_syndoc_ids", checked_syndoc_ids)
	if kind == "closure":
		await owner.call("_refresh_closures")
	else:
		await owner.call("_refresh_flowdocs")
	if failed_ids.is_empty():
		owner.call("_set_status", "Deleted %d %s(s)." % [deleted_count, kind])
	else:
		var hint := ""
		if typeof(first_error) == TYPE_DICTIONARY:
			var e: Dictionary = first_error
			if int(e.get("status", 0)) == 404:
				hint = " (hub may not support delete yet; update/rebuild the hub)"
		owner.call("_set_status", "Deleted %d %s(s); failed %d: %s%s" % [deleted_count, kind, failed_ids.size(), str(first_error), hint])


static func post_ready_refresh(owner: Control) -> void:
	if Engine.is_editor_hint():
		return
	var startup_refresh_attempts := int(owner.get("_startup_refresh_attempts"))
	var timeout_sec := 12.0 if startup_refresh_attempts <= 0 else 20.0
	if not await await_hub_ready_for_startup_refresh(owner, timeout_sec):
		startup_refresh_attempts += 1
		owner.set("_startup_refresh_attempts", startup_refresh_attempts)
		if startup_refresh_attempts <= 6:
			owner.call("_set_status", "Hub not ready yet (startup, retry %d/6). Will retry automatically…" % startup_refresh_attempts)
			await owner.get_tree().create_timer(2.0).timeout
			await post_ready_refresh(owner)
		else:
			owner.call("_set_status", "Hub not ready after startup retries. Press Refresh.")
		return
	owner.set("_startup_refresh_attempts", 0)
	await owner.call("_refresh_closures")
	await owner.call("_refresh_flowdocs")
	await owner.call("_refresh_render_results_from_hub")


static func await_hub_ready_for_startup_refresh(owner: Control, timeout_sec: float = 10.0) -> bool:
	var hub: Node = owner.get("_hub")
	if not is_instance_valid(hub):
		return false
	var started_ms := Time.get_ticks_msec()
	var timeout_ms := int(timeout_sec * 1000.0)
	while (Time.get_ticks_msec() - started_ms) < timeout_ms:
		var health: Dictionary = await hub.check_health()
		if bool(health.get("ok", false)):
			return true
		await owner.get_tree().create_timer(0.35).timeout
	return false
