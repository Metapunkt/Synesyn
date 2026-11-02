## Purpose: Conversation thread folder and STFX Store actions for SyntreePanel.
@tool
extends RefCounted
class_name SyntreePanelStoreActions

static func _on_open_threads_folder_pressed(panel: Object) -> void:
	# Open the conversation threads directory on disk.
	# This is intentionally panel-owned (simple UX action; should not depend on status controller).
	var cm: Object = panel._conversation_manager
	if not is_instance_valid(cm) and is_instance_valid(panel._plugin_manager) and panel._plugin_manager.has_method("get_conversation_manager"):
		cm = panel._plugin_manager.get_conversation_manager()
		panel._conversation_manager = cm

	if not is_instance_valid(cm) or not cm.has_method("get_threads_dir_info"):
		panel._show_warning_dialog("Open Threads Folder", "ConversationManager not available.")
		return

	var info: Dictionary = cm.get_threads_dir_info()
	var abs_dir := str(info.get("threads_dir_abs", "")).strip_edges()
	if abs_dir.is_empty():
		panel._show_warning_dialog("Open Threads Folder", "Threads folder path not available.")
		return

	abs_dir = abs_dir.replace("\\", "/")
	var mkerr := DirAccess.make_dir_recursive_absolute(abs_dir)
	if mkerr != OK:
		panel._show_error_dialog("Open Threads Folder", "Could not create/open threads directory:\n%s" % abs_dir)
		return

	# Windows: open via Explorer (most reliable).
	if OS.get_name() == "Windows":
		var pwin := abs_dir.replace("/", "\\")
		var pid := OS.create_process("explorer.exe", PackedStringArray([pwin]), false)
		if pid > 0:
			return
		# Final fallback: cmd start
		var pid2 := OS.create_process("cmd.exe", PackedStringArray(["/c", "start", "", pwin]), false)
		if pid2 > 0:
			return

	# Other OS / fallback
	var err := OS.shell_open(abs_dir)
	if err == OK:
		return

	# URI fallback
	var uri := abs_dir
	if not uri.begins_with("file://"):
		if uri.length() >= 2 and uri[1] == ":":
			uri = "file:///" + uri
		else:
			uri = "file://" + uri
	if uri.find(" ") != -1:
		uri = uri.uri_encode()
	var err2 := OS.shell_open(uri)
	if err2 != OK:
		panel._show_warning_dialog("Open Threads Folder", "Failed to open:\n%s" % abs_dir)

static func _on_open_store_trace_button_pressed(panel: Object) -> void:
	var info: Dictionary = await _latest_store_context_paths_or_warn(panel, "Open Store Trace")
	if info.is_empty():
		return
	var trace_dir: String = str(info.get("trace_dir", "")).strip_edges()
	if trace_dir.is_empty():
		panel._show_warning_dialog("Open Store Trace", "Trace directory path is empty.")
		return
	panel._open_folder_in_os(trace_dir)
	var trace_id: String = str(info.get("trace_id", "")).strip_edges()
	var context_pack_id: String = str(info.get("context_pack_id", "")).strip_edges()
	panel._set_status_strip_text("Store trace: %s | context pack: %s" % [trace_id, context_pack_id])

static func _latest_store_context_paths_or_warn(panel: Object, action_title: String) -> Dictionary:
	var cm: Object = panel._conversation_manager
	if not is_instance_valid(cm) and is_instance_valid(panel._plugin_manager) and panel._plugin_manager.has_method("get_conversation_manager"):
		cm = panel._plugin_manager.get_conversation_manager()
		panel._conversation_manager = cm
	if not is_instance_valid(cm) or not cm.has_method("get_latest_stfx_store_context_paths"):
		panel._show_warning_dialog(action_title, "ConversationManager does not expose STFX Store trace paths.")
		return {}
	var info: Dictionary = await cm.get_latest_stfx_store_context_paths()
	if not bool(info.get("ok", false)):
		panel._show_warning_dialog(action_title, str(info.get("error", "No STFX Store trace is available yet.")))
		return {}
	return info

static func _on_view_store_trace_button_pressed(panel: Object) -> void:
	var info: Dictionary = await _latest_store_context_paths_or_warn(panel, "View Store Trace")
	if info.is_empty():
		return
	var trace_id: String = str(info.get("trace_id", "")).strip_edges()
	var context_pack_id: String = str(info.get("context_pack_id", "")).strip_edges()
	var client: Node = panel.HubSubstrateClientScript.new()
	panel.add_child(client)
	client.configure_from_runtime_config()
	var trace_res: Dictionary = await client.stfx_store_get_trace(trace_id)
	var pack_res: Dictionary = await client.stfx_store_get_context_pack(context_pack_id)
	client.queue_free()
	if not bool(trace_res.get("ok", false)):
		panel._show_warning_dialog("View Store Trace", _store_result_error(panel, trace_res))
		return
	var trace_any: Variant = trace_res.get("trace", {})
	var pack_any: Variant = pack_res.get("context_pack", {})
	var summary := "Trace %s\nContext pack %s\n\n%s" % [
		trace_id,
		context_pack_id,
		JSON.stringify({"trace": trace_any, "context_pack": pack_any}, "\t").left(5000),
	]
	panel._show_warning_dialog("STFX Store Trace", summary)

static func _on_open_store_chunk_button_pressed(panel: Object) -> void:
	var chunk: Dictionary = await _latest_store_chunk_or_warn(panel, "Open Canonical Chunk")
	if chunk.is_empty():
		return
	var folder_path: String = str(chunk.get("folder", "")).strip_edges()
	if folder_path.is_empty():
		panel._show_warning_dialog("Open Canonical Chunk", "Chunk folder path is empty.")
		return
	panel._open_folder_in_os(folder_path)
	panel._set_status_strip_text("Opened canonical chunk folder: %s" % str(chunk.get("chunk_id", "")).left(12))

static func _on_repair_store_symbolic_button_pressed(panel: Object) -> void:
	var chunk: Dictionary = await _latest_store_chunk_or_warn(panel, "Repair Symbolic Metadata")
	if chunk.is_empty():
		return
	var chunk_id: String = str(chunk.get("chunk_id", "")).strip_edges()
	var symbolic_any: Variant = chunk.get("symbolic", {})
	var symbolic: Dictionary = symbolic_any if typeof(symbolic_any) == TYPE_DICTIONARY else {}
	var primary_seed: String = str(symbolic.get("primary_seed", "primary")).strip_edges()
	if primary_seed.is_empty():
		primary_seed = "primary"
	var repair_note := "SynTree reviewed symbolic metadata from inline repair affordance."
	var client: Node = panel.HubSubstrateClientScript.new()
	panel.add_child(client)
	client.configure_from_runtime_config()
	var res: Dictionary = await client.stfx_store_update_chunk_symbolic(chunk_id, {
		"primary_seed": primary_seed,
		"rationale": str(symbolic.get("rationale", repair_note)).strip_edges(),
	}, repair_note)
	client.queue_free()
	if not bool(res.get("ok", false)):
		panel._show_warning_dialog("Repair Symbolic Metadata", _store_result_error(panel, res))
		return
	panel._set_status_strip_text("Repaired symbolic metadata for chunk: %s" % chunk_id.left(12))

static func _latest_store_chunk_or_warn(panel: Object, action_title: String) -> Dictionary:
	var info: Dictionary = await _latest_store_context_paths_or_warn(panel, action_title)
	if info.is_empty():
		return {}
	var context_pack_id: String = str(info.get("context_pack_id", "")).strip_edges()
	var client: Node = panel.HubSubstrateClientScript.new()
	panel.add_child(client)
	client.configure_from_runtime_config()
	var pack_res: Dictionary = await client.stfx_store_get_context_pack(context_pack_id)
	if not bool(pack_res.get("ok", false)):
		client.queue_free()
		panel._show_warning_dialog(action_title, _store_result_error(panel, pack_res))
		return {}
	var pack_any: Variant = pack_res.get("context_pack", {})
	var pack: Dictionary = pack_any if typeof(pack_any) == TYPE_DICTIONARY else {}
	var chunks_any: Variant = pack.get("chunks", [])
	var chunks: Array = chunks_any if typeof(chunks_any) == TYPE_ARRAY else []
	if chunks.is_empty() or typeof(chunks[0]) != TYPE_DICTIONARY:
		client.queue_free()
		panel._show_warning_dialog(action_title, "Latest context pack has no chunks.")
		return {}
	var first_chunk: Dictionary = chunks[0]
	var chunk_id: String = str(first_chunk.get("chunk_id", "")).strip_edges()
	var chunk_res: Dictionary = await client.stfx_store_get_chunk(chunk_id)
	client.queue_free()
	if not bool(chunk_res.get("ok", false)):
		panel._show_warning_dialog(action_title, _store_result_error(panel, chunk_res))
		return {}
	var chunk_record_any: Variant = chunk_res.get("chunk", {})
	var chunk_record: Dictionary = chunk_record_any if typeof(chunk_record_any) == TYPE_DICTIONARY else {}
	chunk_record["folder"] = str(chunk_res.get("folder", "")).strip_edges()
	return chunk_record

static func _on_store_repair_button_pressed(panel: Object) -> void:
	if panel._is_store_repair_running:
		return
	panel._is_store_repair_running = true
	if is_instance_valid(panel.store_repair_button):
		panel.store_repair_button.disabled = true
	panel._set_status_strip_text("STFX Store: running validate, repair report, rebuild...")

	var client: Node = panel.HubSubstrateClientScript.new()
	panel.add_child(client)
	if client.has_method("configure_from_runtime_config"):
		client.configure_from_runtime_config()

	var validate_res: Dictionary = await client.stfx_store_validate()
	if not bool(validate_res.get("ok", false)):
		_finish_store_repair_action(panel, client, false, "Store validate failed: %s" % _store_result_error(panel, validate_res))
		return

	var repair_res: Dictionary = await client.stfx_store_repair_report()
	var rebuild_res: Dictionary = await client.stfx_store_rebuild_indexes()
	var has_failure := not bool(repair_res.get("ok", false)) or not bool(rebuild_res.get("ok", false))
	var summary: String = _format_store_repair_summary(panel, validate_res, repair_res, rebuild_res)
	_finish_store_repair_action(panel, client, not has_failure, summary)

static func _finish_store_repair_action(panel: Object, client: Node, is_success: bool, message: String) -> void:
	if is_instance_valid(client):
		client.queue_free()
	panel._is_store_repair_running = false
	if is_instance_valid(panel.store_repair_button):
		panel.store_repair_button.disabled = false
	panel._set_status_strip_text(message)
	if not is_success:
		panel._show_warning_dialog("STFX Store Repair", message)

static func _format_store_repair_summary(panel: Object, validate_res: Dictionary, repair_res: Dictionary, rebuild_res: Dictionary) -> String:
	var errors_any: Variant = validate_res.get("errors", [])
	var error_count := 0
	if typeof(errors_any) == TYPE_ARRAY:
		error_count = (errors_any as Array).size()

	var report_any: Variant = repair_res.get("report", {})
	var report: Dictionary = report_any if typeof(report_any) == TYPE_DICTIONARY else {}
	var report_id: String = str(report.get("report_id", "")).strip_edges()
	var checks_any: Variant = report.get("checks", [])
	var failed_checks: Array[String] = []
	if typeof(checks_any) == TYPE_ARRAY:
		for check_any in checks_any:
			if typeof(check_any) != TYPE_DICTIONARY:
				continue
			var check: Dictionary = check_any
			if not bool(check.get("ok", false)):
				failed_checks.append(str(check.get("name", "check")).strip_edges())

	var rebuild_report_any: Variant = rebuild_res.get("report", {})
	var rebuild_report: Dictionary = rebuild_report_any if typeof(rebuild_report_any) == TYPE_DICTIONARY else {}
	var source_count := int(rebuild_report.get("source_count", 0))
	var chunk_count := int(rebuild_report.get("chunk_count", 0))
	var status_label := "ok" if failed_checks.is_empty() and bool(repair_res.get("ok", false)) and bool(rebuild_res.get("ok", false)) else "needs attention"
	var msg := "Store repair %s: validate_errors=%d, sources=%d, chunks=%d" % [status_label, error_count, source_count, chunk_count]
	if not report_id.is_empty():
		msg += ", report=%s" % report_id
	if not failed_checks.is_empty():
		msg += ", failed_checks=%s" % ", ".join(failed_checks)
	if not bool(repair_res.get("ok", false)) and failed_checks.is_empty():
		msg += ", repair_error=%s" % _store_result_error(panel, repair_res)
	if not bool(rebuild_res.get("ok", false)):
		msg += ", rebuild_error=%s" % _store_result_error(panel, rebuild_res)
	return msg

static func _store_result_error(panel: Object, result: Dictionary) -> String:
	var err_any: Variant = result.get("error", result.get("detail", "unknown error"))
	if typeof(err_any) == TYPE_DICTIONARY:
		return JSON.stringify(err_any)
	if typeof(err_any) == TYPE_ARRAY:
		return JSON.stringify(err_any)
	return str(err_any)

