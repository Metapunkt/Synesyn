## Purpose: Dev Agent and run-spec helpers for SyntreePanel.
@tool
extends RefCounted
class_name SyntreePanelDevAgentUtils

const SynTreeAutoloads = preload("res://addons/syntree/scripts/autoload/syntree_autoloads.gd")
const ContentBusScript = preload("res://addons/syntree/scripts/autoload/content_bus.gd")

static func _bus() -> ContentBusScript:
	return SynTreeAutoloads.content_bus()

static func _on_dev_agent_button_pressed(panel: Object) -> void:
	if not is_instance_valid(panel.dev_agent_popup):
		panel._show_warning_dialog("Dev Agent", "DevAgentPopup not found in scene.")
		return
	# Re-load schema on open (supports per-project changes without restart).
	panel._run_spec_ui_schema = {}
	panel._run_spec_ui_schema_fields.clear()
	_ensure_run_spec_ui_schema_loaded(panel)
	_refresh_dev_agent_last_run_ui(panel)
	# If the panel was instanced before the Loop tab was added, the nodes won't exist.
	# Provide a clear hint so users know they need to reload the plugin/panel.
	if not is_instance_valid(panel.dev_agent_loop_goal_input):
		panel._show_warning_dialog(
			"SynTree UI needs reload",
			"This SynTree panel instance was created before the Dev Agent Loop tab existed.\n\nReload the SynTree plugin UI to see the new tab:\n- Project → Project Settings → Plugins: disable SynTree, then enable it again, OR\n- Restart the Godot editor."
		)
	# Keep the popup reasonably sized; content scrolls inside.
	panel.dev_agent_popup.popup_centered(Vector2i(860, 520))

# Public helpers (best-effort) for integrations (e.g. Metapunkt Pack panels)
static func open_dev_agent_popup(panel: Object) -> void:
	_on_dev_agent_button_pressed(panel)

static func open_dev_agent_artifacts_folder(panel: Object) -> void:
	_on_open_artifacts_folder_pressed(panel)

static func open_dev_agent_backups_folder(panel: Object) -> void:
	_on_open_backups_folder_pressed(panel)

static func _wire_dev_agent_patch_ui(panel: Object) -> void:
	if not is_instance_valid(panel.dev_agent_patch_input):
		return
	if is_instance_valid(panel.dev_agent_patch_result):
		panel.dev_agent_patch_result.editable = false
	if is_instance_valid(panel.dev_agent_patch_dry_run_button) and not panel.dev_agent_patch_dry_run_button.pressed.is_connected(Callable(panel, "_on_dev_agent_patch_dry_run_pressed")):
		panel.dev_agent_patch_dry_run_button.pressed.connect(Callable(panel, "_on_dev_agent_patch_dry_run_pressed"))
	if is_instance_valid(panel.dev_agent_patch_apply_button) and not panel.dev_agent_patch_apply_button.pressed.is_connected(Callable(panel, "_on_dev_agent_patch_apply_pressed")):
		panel.dev_agent_patch_apply_button.pressed.connect(Callable(panel, "_on_dev_agent_patch_apply_pressed"))
	if is_instance_valid(panel.dev_agent_patch_revert_button) and not panel.dev_agent_patch_revert_button.pressed.is_connected(Callable(panel, "_on_dev_agent_patch_revert_pressed")):
		panel.dev_agent_patch_revert_button.pressed.connect(Callable(panel, "_on_dev_agent_patch_revert_pressed"))
	if is_instance_valid(panel.dev_agent_patch_close_button) and not panel.dev_agent_patch_close_button.pressed.is_connected(Callable(panel, "_on_dev_agent_patch_close_pressed")):
		panel.dev_agent_patch_close_button.pressed.connect(Callable(panel, "_on_dev_agent_patch_close_pressed"))

static func _wire_dev_agent_artifacts_ui(panel: Object) -> void:
	if is_instance_valid(panel.dev_agent_open_backups_folder_button) and not panel.dev_agent_open_backups_folder_button.pressed.is_connected(Callable(panel, "_on_open_backups_folder_pressed")):
		panel.dev_agent_open_backups_folder_button.pressed.connect(Callable(panel, "_on_open_backups_folder_pressed"))
	if is_instance_valid(panel.dev_agent_open_artifacts_folder_button) and not panel.dev_agent_open_artifacts_folder_button.pressed.is_connected(Callable(panel, "_on_open_artifacts_folder_pressed")):
		panel.dev_agent_open_artifacts_folder_button.pressed.connect(Callable(panel, "_on_open_artifacts_folder_pressed"))

static func _wire_dev_agent_run_spec_ui(panel: Object) -> void:
	if is_instance_valid(panel.dev_agent_run_spec_result):
		panel.dev_agent_run_spec_result.editable = false
	if is_instance_valid(panel.dev_agent_run_spec_load_button) and not panel.dev_agent_run_spec_load_button.pressed.is_connected(Callable(panel, "_on_run_spec_load_pressed")):
		panel.dev_agent_run_spec_load_button.pressed.connect(Callable(panel, "_on_run_spec_load_pressed"))
	if is_instance_valid(panel.dev_agent_run_spec_save_button) and not panel.dev_agent_run_spec_save_button.pressed.is_connected(Callable(panel, "_on_run_spec_save_pressed")):
		panel.dev_agent_run_spec_save_button.pressed.connect(Callable(panel, "_on_run_spec_save_pressed"))
	if is_instance_valid(panel.dev_agent_run_spec_run_button) and not panel.dev_agent_run_spec_run_button.pressed.is_connected(Callable(panel, "_on_run_spec_run_pressed")):
		panel.dev_agent_run_spec_run_button.pressed.connect(Callable(panel, "_on_run_spec_run_pressed"))
	if is_instance_valid(panel.dev_agent_run_spec_scene_picker_dialog):
		# Editor-only; avoid hooking multiple times.
		if not panel.dev_agent_run_spec_scene_picker_dialog.file_selected.is_connected(Callable(panel, "_on_run_spec_scene_selected")):
			panel.dev_agent_run_spec_scene_picker_dialog.file_selected.connect(Callable(panel, "_on_run_spec_scene_selected"))
	if is_instance_valid(panel.dev_agent_run_spec_browse_scene_button) and not panel.dev_agent_run_spec_browse_scene_button.pressed.is_connected(Callable(panel, "_on_run_spec_browse_scene_pressed")):
		panel.dev_agent_run_spec_browse_scene_button.pressed.connect(Callable(panel, "_on_run_spec_browse_scene_pressed"))
	if is_instance_valid(panel.dev_agent_run_spec_sync_to_json_button) and not panel.dev_agent_run_spec_sync_to_json_button.pressed.is_connected(Callable(panel, "_on_run_spec_sync_to_json_pressed")):
		panel.dev_agent_run_spec_sync_to_json_button.pressed.connect(Callable(panel, "_on_run_spec_sync_to_json_pressed"))
	if is_instance_valid(panel.dev_agent_run_spec_fill_from_json_button) and not panel.dev_agent_run_spec_fill_from_json_button.pressed.is_connected(Callable(panel, "_on_run_spec_fill_from_json_pressed")):
		panel.dev_agent_run_spec_fill_from_json_button.pressed.connect(Callable(panel, "_on_run_spec_fill_from_json_pressed"))
	if is_instance_valid(panel.dev_agent_run_spec_refresh_last_run_button) and not panel.dev_agent_run_spec_refresh_last_run_button.pressed.is_connected(Callable(panel, "_on_run_spec_refresh_last_run_pressed")):
		panel.dev_agent_run_spec_refresh_last_run_button.pressed.connect(Callable(panel, "_on_run_spec_refresh_last_run_pressed"))
	if is_instance_valid(panel.dev_agent_run_spec_open_last_run_dir_button) and not panel.dev_agent_run_spec_open_last_run_dir_button.pressed.is_connected(Callable(panel, "_on_run_spec_open_last_run_dir_pressed")):
		panel.dev_agent_run_spec_open_last_run_dir_button.pressed.connect(Callable(panel, "_on_run_spec_open_last_run_dir_pressed"))
	if is_instance_valid(panel.dev_agent_run_spec_open_last_run_manifest_button) and not panel.dev_agent_run_spec_open_last_run_manifest_button.pressed.is_connected(Callable(panel, "_on_run_spec_open_last_run_manifest_pressed")):
		panel.dev_agent_run_spec_open_last_run_manifest_button.pressed.connect(Callable(panel, "_on_run_spec_open_last_run_manifest_pressed"))

	# Initial UI state
	if is_instance_valid(panel.dev_agent_run_spec_last_run_text):
		panel.dev_agent_run_spec_last_run_text.editable = false
	_ensure_run_spec_ui_schema_loaded(panel)
	_refresh_dev_agent_last_run_ui(panel)

static func _wire_dev_agent_loop_ui(panel: Object) -> void:
	if is_instance_valid(panel.dev_agent_loop_log):
		panel.dev_agent_loop_log.editable = false
	if is_instance_valid(panel.dev_agent_loop_stop_button):
		panel.dev_agent_loop_stop_button.disabled = true
	if is_instance_valid(panel.dev_agent_loop_start_button) and not panel.dev_agent_loop_start_button.pressed.is_connected(Callable(panel, "_on_dev_agent_loop_start_pressed")):
		panel.dev_agent_loop_start_button.pressed.connect(Callable(panel, "_on_dev_agent_loop_start_pressed"))
	if is_instance_valid(panel.dev_agent_loop_stop_button) and not panel.dev_agent_loop_stop_button.pressed.is_connected(Callable(panel, "_on_dev_agent_loop_stop_pressed")):
		panel.dev_agent_loop_stop_button.pressed.connect(Callable(panel, "_on_dev_agent_loop_stop_pressed"))

	# Instantiate orchestrator once.
	if panel._dev_agent_orchestrator == null:
		panel._dev_agent_orchestrator = panel.DevAgentOrchestratorScript.new()
		panel.add_child(panel._dev_agent_orchestrator)
		if panel._dev_agent_orchestrator.has_signal("log_line"):
			panel._dev_agent_orchestrator.log_line.connect(Callable(panel, "_on_dev_agent_loop_log_line"))
		if panel._dev_agent_orchestrator.has_signal("loop_finished"):
			panel._dev_agent_orchestrator.loop_finished.connect(Callable(panel, "_on_dev_agent_loop_finished"))
		# Conversation manager is created during setup.
		panel._dev_agent_orchestrator.setup(panel, panel._conversation_manager)

static func _append_loop_log(panel: Object, line: String) -> void:
	if not is_instance_valid(panel.dev_agent_loop_log):
		return
	var prev := String(panel.dev_agent_loop_log.text)
	panel.dev_agent_loop_log.text = (prev + "\n" if not prev.is_empty() else "") + String(line)
	panel.dev_agent_loop_log.scroll_vertical = 999999

static func _on_dev_agent_loop_log_line(panel: Object, line: String) -> void:
	_append_loop_log(panel, line)

static func _on_dev_agent_loop_finished(panel: Object, ok: bool, summary: String) -> void:
	_append_loop_log(panel, "Finished: ok=%s summary=%s" % [str(ok), String(summary)])
	if is_instance_valid(panel.dev_agent_loop_start_button):
		panel.dev_agent_loop_start_button.disabled = false
	if is_instance_valid(panel.dev_agent_loop_stop_button):
		panel.dev_agent_loop_stop_button.disabled = true

static func _on_dev_agent_loop_start_pressed(panel: Object) -> void:
	# Side-effect loop: requires Dev Agent toggle.
	if not _dev_agent_guard_or_warn(panel):
		return
	if panel._dev_agent_orchestrator == null:
		_wire_dev_agent_loop_ui(panel)
	if panel._dev_agent_orchestrator == null:
		panel._show_warning_dialog("Dev Agent Loop", "Orchestrator not available.")
		return
	var goal := String(panel.dev_agent_loop_goal_input.text if is_instance_valid(panel.dev_agent_loop_goal_input) else "").strip_edges()
	var where := String(panel.dev_agent_loop_where_input.text if is_instance_valid(panel.dev_agent_loop_where_input) else "").strip_edges()
	var verify := String(panel.dev_agent_loop_verify_input.text if is_instance_valid(panel.dev_agent_loop_verify_input) else "").strip_edges()
	var constraints := String(panel.dev_agent_loop_constraints_input.text if is_instance_valid(panel.dev_agent_loop_constraints_input) else "").strip_edges()
	if goal.is_empty():
		panel._show_warning_dialog("Dev Agent Loop", "Fill in the Goal field first.")
		return
	var task_parts: Array[String] = []
	task_parts.append("Goal:\n%s" % goal)
	if not where.is_empty():
		task_parts.append("Where:\n%s" % where)
	if not verify.is_empty():
		task_parts.append("Verify:\n%s" % verify)
	if not constraints.is_empty():
		task_parts.append("Constraints:\n%s" % constraints)
	var task := "\n\n".join(task_parts)
	var iters := int(panel.dev_agent_loop_max_iters.value) if is_instance_valid(panel.dev_agent_loop_max_iters) else 2
	_append_loop_log(panel, "Starting loop…")
	if is_instance_valid(panel.dev_agent_loop_start_button):
		panel.dev_agent_loop_start_button.disabled = true
	if is_instance_valid(panel.dev_agent_loop_stop_button):
		panel.dev_agent_loop_stop_button.disabled = false
	panel._dev_agent_orchestrator.setup(panel, panel._conversation_manager)
	panel._dev_agent_orchestrator.start(task, iters)

static func _on_dev_agent_loop_stop_pressed(panel: Object) -> void:
	if panel._dev_agent_orchestrator != null:
		panel._dev_agent_orchestrator.stop()
	if is_instance_valid(panel.dev_agent_loop_stop_button):
		panel.dev_agent_loop_stop_button.disabled = true

static func _dev_agent_apply_patch_text(panel: Object, patch_text: String) -> Dictionary:
	# Internal API for orchestrator: apply a unified diff with backups + refresh.
	if not _dev_agent_guard_or_warn(panel):
		return {"ok": false, "error": "Dev Agent is OFF or not in editor"}
	var patch := String(patch_text)
	if patch.strip_edges().is_empty():
		return {"ok": false, "error": "empty patch"}
	if is_instance_valid(panel.dev_agent_patch_input):
		panel.dev_agent_patch_input.text = patch
	var backup_root := _get_dev_agent_backup_root_dir(panel)
	var res: Dictionary = panel.UnifiedDiffApplier.apply_with_backups(patch, backup_root)
	if bool(res.get("ok", false)):
		# Persist manifest for revert + refresh sources.
		var manifest := {
			"applied_at": Time.get_datetime_string_from_system(false, true),
			"backup_root": backup_root,
			"results": res.get("results", []),
		}
		_write_last_apply_manifest(panel, manifest)
		if _bus() and _bus().has_method("refresh_active_sources"):
			_bus().refresh_active_sources()
	return res

static func _dev_agent_launch_harness_from_spec(panel: Object, spec: Dictionary) -> void:
	# Internal API for orchestrator: set run spec and launch harness.
	if not _dev_agent_guard_or_warn(panel):
		return
	if not Engine.is_editor_hint():
		return
	if not is_instance_valid(panel.dev_agent_run_spec_input):
		return
	panel.dev_agent_run_spec_input.text = JSON.stringify(spec if spec != null else {}, "  ")
	_on_run_spec_run_pressed(panel)

static func _set_dev_agent_patch_result(panel: Object, text: String) -> void:
	if is_instance_valid(panel.dev_agent_patch_result):
		panel.dev_agent_patch_result.text = String(text)

static func _set_run_spec_result(panel: Object, text: String) -> void:
	if is_instance_valid(panel.dev_agent_run_spec_result):
		panel.dev_agent_run_spec_result.text = String(text)

static func _ensure_run_spec_ui_schema_loaded(panel: Object) -> void:
	# Load once per panel lifetime unless the user changes ProjectSettings.
	if not panel._run_spec_ui_schema.is_empty() and panel._run_spec_ui_schema_fields.size() > 0:
		return
	panel._run_spec_ui_schema = _load_run_spec_ui_schema(panel)
	_apply_run_spec_ui_schema(panel, panel._run_spec_ui_schema)

static func _load_run_spec_ui_schema(panel: Object) -> Dictionary:
	# Order:
	# 1) ProjectSetting `syntree/dev_agent/run_spec_ui_schema_path` if set.
	# 2) `res://syntree_run_spec_ui_schema.json` (project-local convention).
	# 3) `res://run_spec_ui_schema.json` (alternate convention).
	# 4) fallback: empty schema.
	var p := ""
	if ProjectSettings.has_setting("syntree/dev_agent/run_spec_ui_schema_path"):
		p = String(ProjectSettings.get_setting("syntree/dev_agent/run_spec_ui_schema_path", "")).strip_edges()
	if p.is_empty():
		if FileAccess.file_exists("res://syntree_run_spec_ui_schema.json"):
			p = "res://syntree_run_spec_ui_schema.json"
		elif FileAccess.file_exists("res://run_spec_ui_schema.json"):
			p = "res://run_spec_ui_schema.json"

	var schema: Dictionary = {"schema_version": 1, "name": "Run Spec UI (default)", "fields": [], "source_path": p}
	if p.is_empty():
		return schema

	var raw := FileAccess.get_file_as_string(p)
	if raw.strip_edges().is_empty():
		schema["name"] = "Run Spec UI (empty schema file)"
		return schema
	var any: Variant = JSON.parse_string(raw)
	if typeof(any) != TYPE_DICTIONARY:
		schema["name"] = "Run Spec UI (invalid schema JSON)"
		return schema
	schema = any
	schema["source_path"] = p
	return schema

static func _apply_run_spec_ui_schema(panel: Object, schema: Dictionary) -> void:
	panel._run_spec_ui_schema_fields.clear()
	if is_instance_valid(panel.dev_agent_run_spec_schema_fields_container):
		for c in panel.dev_agent_run_spec_schema_fields_container.get_children():
			c.queue_free()

	var src := String(schema.get("source_path", "")).strip_edges()
	var name := String(schema.get("name", "Run Spec UI")).strip_edges()
	if is_instance_valid(panel.dev_agent_run_spec_schema_status_label):
		panel.dev_agent_run_spec_schema_status_label.text = "Schema: %s%s" % [name if not name.is_empty() else "(unnamed)", (" — " + src) if not src.is_empty() else ""]

	var fields_any: Variant = schema.get("fields", [])
	if typeof(fields_any) != TYPE_ARRAY or not is_instance_valid(panel.dev_agent_run_spec_schema_fields_container):
		return

	for f_any in (fields_any as Array):
		if typeof(f_any) != TYPE_DICTIONARY:
			continue
		var f: Dictionary = f_any
		var fid := String(f.get("id", "")).strip_edges()
		var label := String(f.get("label", fid)).strip_edges()
		var ftype := String(f.get("type", "string")).strip_edges().to_lower()
		var json_path := String(f.get("json_path", "")).strip_edges()
		var help := String(f.get("help", f.get("tooltip", f.get("description", "")))).strip_edges()
		if fid.is_empty() or json_path.is_empty():
			continue

		var clear_on_empty := bool(f.get("clear_on_empty", true))
		var default_val: Variant = f.get("default", null)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		panel.dev_agent_run_spec_schema_fields_container.add_child(row)

		var lbl := Label.new()
		lbl.text = (label + ":") if not label.ends_with(":") else label
		if not help.is_empty():
			lbl.tooltip_text = help
		row.add_child(lbl)

		var ctrl: Control = null
		match ftype:
			"bool":
				var cb := CheckButton.new()
				cb.text = ""  # keep label in the left column
				if not help.is_empty():
					cb.tooltip_text = help
				ctrl = cb
			"enum":
				var ob := OptionButton.new()
				if not help.is_empty():
					ob.tooltip_text = help
				var opts_any: Variant = f.get("options", [])
				if typeof(opts_any) == TYPE_ARRAY:
					for opt_any in (opts_any as Array):
						if typeof(opt_any) != TYPE_DICTIONARY:
							continue
						var opt: Dictionary = opt_any
						var olabel := String(opt.get("label", "")).strip_edges()
						var oval: String = String(opt.get("value", ""))
						var idx := ob.item_count
						ob.add_item(olabel if not olabel.is_empty() else oval)
						ob.set_item_metadata(idx, oval)
				ctrl = ob
			_:
				var le := LineEdit.new()
				le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				le.placeholder_text = String(f.get("placeholder", "")).strip_edges()
				if not help.is_empty():
					le.tooltip_text = help
				ctrl = le

		if ctrl:
			ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(ctrl)

		panel._run_spec_ui_schema_fields.append({
			"id": fid,
			"json_path": json_path,
			"type": ftype,
			"control": ctrl,
			"clear_on_empty": clear_on_empty,
			"default": default_val,
		})

static func _dict_get_path(panel: Object, d: Dictionary, path: String, default_val: Variant = null) -> Variant:
	var cur: Variant = d
	for seg_any in String(path).split("."):
		var seg := String(seg_any).strip_edges()
		if seg.is_empty():
			continue
		if typeof(cur) != TYPE_DICTIONARY:
			return default_val
		var cd: Dictionary = cur
		if not cd.has(seg):
			return default_val
		cur = cd.get(seg)
	return cur

static func _dict_set_path(panel: Object, d: Dictionary, path: String, value: Variant) -> void:
	var parts := String(path).split(".")
	if parts.is_empty():
		return
	var cur: Dictionary = d
	for i in range(parts.size() - 1):
		var seg := String(parts[i]).strip_edges()
		if seg.is_empty():
			continue
		var next_any: Variant = cur.get(seg, {})
		if typeof(next_any) != TYPE_DICTIONARY:
			next_any = {}
		cur[seg] = next_any
		cur = cur[seg]
	var last := String(parts[parts.size() - 1]).strip_edges()
	if last.is_empty():
		return
	cur[last] = value

static func _dict_erase_path(panel: Object, d: Dictionary, path: String) -> void:
	var parts := String(path).split(".")
	if parts.is_empty():
		return
	var cur: Variant = d
	for i in range(parts.size() - 1):
		var seg := String(parts[i]).strip_edges()
		if seg.is_empty():
			continue
		if typeof(cur) != TYPE_DICTIONARY:
			return
		var cd: Dictionary = cur
		if not cd.has(seg):
			return
		cur = cd.get(seg)
	if typeof(cur) != TYPE_DICTIONARY:
		return
	var parent: Dictionary = cur
	var last := String(parts[parts.size() - 1]).strip_edges()
	if parent.has(last):
		parent.erase(last)

static func _read_json_file_best_effort(panel: Object, path: String) -> Dictionary:
	var p := String(path).strip_edges()
	if p.is_empty() or not FileAccess.file_exists(p):
		return {}
	var raw := FileAccess.get_file_as_string(p)
	if raw.strip_edges().is_empty():
		return {}
	var any: Variant = JSON.parse_string(raw)
	return any if typeof(any) == TYPE_DICTIONARY else {}

static func _get_harness_last_run_pointer_path(panel: Object) -> String:
	return _get_session_data_root_dir(panel).path_join("syntree_artifacts").path_join("harness_last_run.json")

static func _refresh_dev_agent_last_run_ui(panel: Object) -> void:
	panel._dev_agent_last_run_pointer = _read_json_file_best_effort(panel, _get_harness_last_run_pointer_path(panel))
	var txt := ""
	if panel._dev_agent_last_run_pointer.is_empty():
		txt = "(No harness run recorded yet.)"
	else:
		var ok := bool(panel._dev_agent_last_run_pointer.get("ok", false))
		var run_dir := String(panel._dev_agent_last_run_pointer.get("run_dir", "")).strip_edges()
		var run_manifest := String(panel._dev_agent_last_run_pointer.get("run_manifest_path", "")).strip_edges()
		var err := String(panel._dev_agent_last_run_pointer.get("error", "")).strip_edges()
		txt = "ok=%s\nrun_dir=%s\nrun_manifest=%s" % [str(ok), run_dir, run_manifest]
		if not err.is_empty():
			txt += "\nerror=%s" % err
	if is_instance_valid(panel.dev_agent_run_spec_last_run_text):
		panel.dev_agent_run_spec_last_run_text.text = txt

static func _open_file_in_os(panel: Object, path_abs: String) -> void:
	var p := String(path_abs).strip_edges()
	if p.is_empty():
		return
	p = p.replace("\\", "/")
	if OS.get_name() == "Windows":
		var win := p.replace("/", "\\")
		var err := OS.create_process("explorer.exe", PackedStringArray(["/select,", win]), false)
		if err != OK:
			OS.create_process("explorer.exe", PackedStringArray([win]), false)
		return
	OS.shell_open("file://" + p)

static func _on_run_spec_refresh_last_run_pressed(panel: Object) -> void:
	_refresh_dev_agent_last_run_ui(panel)

static func _on_run_spec_open_last_run_dir_pressed(panel: Object) -> void:
	# Always refresh so we open the latest run.
	_refresh_dev_agent_last_run_ui(panel)
	if panel._dev_agent_last_run_pointer.is_empty():
		# No run yet: open the runs root so the button still does something useful.
		var runs_root := _get_session_data_root_dir(panel).path_join("syntree_artifacts").path_join("runs")
		DirAccess.make_dir_recursive_absolute(runs_root)
		_set_run_spec_result(panel, "No last run available yet.\nOpening runs folder:\n%s" % runs_root)
		_open_folder_in_os(panel, runs_root)
		return

	var run_dir := String(panel._dev_agent_last_run_pointer.get("run_dir", "")).strip_edges()
	if run_dir.is_empty():
		# Back-compat: derive from run_manifest_path if present.
		var run_manifest := String(panel._dev_agent_last_run_pointer.get("run_manifest_path", "")).strip_edges()
		if not run_manifest.is_empty():
			run_dir = run_manifest.get_base_dir()

	if run_dir.is_empty():
		# Fallback: open runs root.
		var runs_root2 := _get_session_data_root_dir(panel).path_join("syntree_artifacts").path_join("runs")
		DirAccess.make_dir_recursive_absolute(runs_root2)
		_set_run_spec_result(panel, "Last run has no run_dir/run_manifest_path.\nOpening runs folder:\n%s" % runs_root2)
		_open_folder_in_os(panel, runs_root2)
		return

	# Best-effort: ensure directory exists before opening.
	run_dir = run_dir.replace("\\", "/")
	DirAccess.make_dir_recursive_absolute(run_dir)
	_set_run_spec_result(panel, "Opening run folder:\n%s" % run_dir)
	_open_folder_in_os(panel, run_dir)

static func _on_run_spec_open_last_run_manifest_pressed(panel: Object) -> void:
	# Always refresh so we open the latest run.
	_refresh_dev_agent_last_run_ui(panel)
	if panel._dev_agent_last_run_pointer.is_empty():
		_set_run_spec_result(panel, "No last run available.")
		return
	var run_manifest := String(panel._dev_agent_last_run_pointer.get("run_manifest_path", "")).strip_edges()
	if run_manifest.is_empty():
		_set_run_spec_result(panel, "Last run has no run_manifest_path.\nTry 'Refresh' or run the harness once.")
		return
	_open_file_in_os(panel, run_manifest)

static func _on_run_spec_browse_scene_pressed(panel: Object) -> void:
	if not Engine.is_editor_hint():
		panel._show_warning_dialog("Scene Picker", "Scene picker is editor-only.")
		return
	if not is_instance_valid(panel.dev_agent_run_spec_scene_picker_dialog):
		panel._show_warning_dialog("Scene Picker", "RunSpecScenePickerDialog not found.")
		return
	panel.dev_agent_run_spec_scene_picker_dialog.popup_centered_ratio(0.75)

static func _on_run_spec_scene_selected(panel: Object, res_path: String) -> void:
	if is_instance_valid(panel.dev_agent_run_spec_scene_path):
		panel.dev_agent_run_spec_scene_path.text = String(res_path).strip_edges()
	_on_run_spec_sync_to_json_pressed(panel)

static func _parse_run_spec_json_best_effort(panel: Object) -> Dictionary:
	if not is_instance_valid(panel.dev_agent_run_spec_input):
		return {}
	var raw := String(panel.dev_agent_run_spec_input.text)
	if raw.strip_edges().is_empty():
		return {}
	var any: Variant = JSON.parse_string(raw)
	return any if typeof(any) == TYPE_DICTIONARY else {}

static func _write_run_spec_json(panel: Object, d: Dictionary) -> void:
	if not is_instance_valid(panel.dev_agent_run_spec_input):
		return
	panel.dev_agent_run_spec_input.text = JSON.stringify(d if d != null else {}, "  ")

static func _on_run_spec_sync_to_json_pressed(panel: Object) -> void:
	# Merge structured fields into the JSON, preserving any advanced keys.
	var d := _parse_run_spec_json_best_effort(panel)
	if d.is_empty():
		d = {}

	var scene_path := String(panel.dev_agent_run_spec_scene_path.text if is_instance_valid(panel.dev_agent_run_spec_scene_path) else "").strip_edges()
	if not scene_path.is_empty():
		d["scene_path"] = scene_path

	_ensure_run_spec_ui_schema_loaded(panel)
	for f in panel._run_spec_ui_schema_fields:
		var ctrl: Control = f.get("control")
		if not is_instance_valid(ctrl):
			continue
		var ftype := String(f.get("type", "string"))
		var json_path := String(f.get("json_path", "")).strip_edges()
		if json_path.is_empty():
			continue
		var clear_on_empty := bool(f.get("clear_on_empty", true))
		var v: Variant = null
		if ftype == "bool" and ctrl is CheckButton:
			v = bool((ctrl as CheckButton).button_pressed)
			_dict_set_path(panel, d, json_path, v)
		elif ftype == "enum" and ctrl is OptionButton:
			var ob := ctrl as OptionButton
			var selected_val := String(ob.get_item_metadata(ob.selected)).strip_edges() if ob.item_count > 0 else ""
			if clear_on_empty and selected_val.is_empty():
				_dict_erase_path(panel, d, json_path)
			else:
				_dict_set_path(panel, d, json_path, selected_val)
		elif ctrl is LineEdit:
			v = String((ctrl as LineEdit).text).strip_edges()
			if clear_on_empty and String(v).is_empty():
				_dict_erase_path(panel, d, json_path)
			else:
				_dict_set_path(panel, d, json_path, v)

	_write_run_spec_json(panel, d)
	_set_run_spec_result(panel, "Updated Run Spec JSON from fields.")

static func _on_run_spec_fill_from_json_pressed(panel: Object) -> void:
	var d := _parse_run_spec_json_best_effort(panel)
	if d.is_empty():
		_set_run_spec_result(panel, "JSON is empty or invalid.")
		return

	if is_instance_valid(panel.dev_agent_run_spec_scene_path):
		panel.dev_agent_run_spec_scene_path.text = String(d.get("scene_path", "")).strip_edges()

	_ensure_run_spec_ui_schema_loaded(panel)
	for f in panel._run_spec_ui_schema_fields:
		var ctrl: Control = f.get("control")
		if not is_instance_valid(ctrl):
			continue
		var ftype := String(f.get("type", "string"))
		var json_path := String(f.get("json_path", "")).strip_edges()
		var defv: Variant = f.get("default", null)
		var v := _dict_get_path(panel, d, json_path, defv)
		if ftype == "bool" and ctrl is CheckButton:
			(ctrl as CheckButton).button_pressed = bool(v)
		elif ftype == "enum" and ctrl is OptionButton:
			var ob := ctrl as OptionButton
			var sv := String(v).strip_edges()
			var idx := 0
			for i in range(ob.item_count):
				if String(ob.get_item_metadata(i)).strip_edges() == sv:
					idx = i
					break
			ob.select(idx)
		elif ctrl is LineEdit:
			(ctrl as LineEdit).text = String(v) if v != null else ""

	_set_run_spec_result(panel, "Filled fields from Run Spec JSON.")

static func _dev_agent_guard_or_warn(panel: Object) -> bool:
	if not Engine.is_editor_hint():
		panel._show_warning_dialog("Dev Agent", "Dev Agent writeback is editor-only (res:// is not writable in exported builds).")
		return false
	if _bus() and _bus().has_method("is_dev_agent_enabled") and not bool(_bus().is_dev_agent_enabled()):
		panel._show_warning_dialog("Dev Agent is OFF", "Enable Dev Agent (toggle in toolbar) to apply/revert patches.")
		return false
	return true

static func _get_current_thread_id_for_run_spec(panel: Object) -> String:
	# Thread ID is owned by ViewStateResource; use safe getter already on panel.
	return panel._get_current_thread_id_safe()

static func _get_run_spec_dir(panel: Object) -> String:
	return _get_session_data_root_dir(panel).path_join("syntree_run_specs")

static func _get_run_spec_path_for_thread(panel: Object, thread_id: String) -> String:
	var tid := String(thread_id).strip_edges()
	if tid.is_empty():
		tid = "default"
	# Keep filename safe.
	tid = tid.replace("/", "_").replace("\\", "_").replace(":", "_")
	return _get_run_spec_dir(panel).path_join(tid + ".json")

static func _on_run_spec_load_pressed(panel: Object) -> void:
	if not Engine.is_editor_hint():
		panel._show_warning_dialog("Run Spec", "Run Spec persistence is editor-oriented (user://).")
		return
	var tid := _get_current_thread_id_for_run_spec(panel)
	var p := _get_run_spec_path_for_thread(panel, tid)
	if not FileAccess.file_exists(p):
		_set_run_spec_result(panel, "No run spec saved for thread: %s" % tid)
		return
	var f := FileAccess.open(p, FileAccess.READ)
	if not f:
		_set_run_spec_result(panel, "Failed to read: %s" % p)
		return
	var txt := f.get_as_text()
	f.close()
	if is_instance_valid(panel.dev_agent_run_spec_input):
		panel.dev_agent_run_spec_input.text = txt
	_set_run_spec_result(panel, "Loaded run spec for thread: %s" % tid)

static func _on_run_spec_save_pressed(panel: Object) -> void:
	if not Engine.is_editor_hint():
		panel._show_warning_dialog("Run Spec", "Run Spec persistence is editor-oriented (user://).")
		return
	var tid := _get_current_thread_id_for_run_spec(panel)
	var p := _get_run_spec_path_for_thread(panel, tid)
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	var txt := ""
	if is_instance_valid(panel.dev_agent_run_spec_input):
		txt = String(panel.dev_agent_run_spec_input.text)
	if txt.strip_edges().is_empty():
		_set_run_spec_result(panel, "Nothing to save.")
		return
	# Validate JSON (optional but safer).
	var j := JSON.new()
	if j.parse(txt) != OK:
		_set_run_spec_result(panel, "Invalid JSON. Fix it before saving.")
		return
	var f := FileAccess.open(p, FileAccess.WRITE)
	if not f:
		_set_run_spec_result(panel, "Failed to write: %s" % p)
		return
	f.store_string(txt)
	f.close()
	_set_run_spec_result(panel, "Saved run spec for thread: %s" % tid)

static func _get_pending_run_spec_path(panel: Object) -> String:
	return _get_session_data_root_dir(panel).path_join("syntree_run_specs").path_join("_pending_run.json")

static func _on_run_spec_run_pressed(panel: Object) -> void:
	# Side-effect action: launches a harness run (play custom scene).
	if not _dev_agent_guard_or_warn(panel):
		return
	if not Engine.is_editor_hint():
		return
	if not is_instance_valid(panel._plugin_ref) or not panel._plugin_ref.has_method("get_editor_interface"):
		panel._show_warning_dialog("Run Harness", "EditorPlugin reference not available; cannot start harness run.")
		return
	if not is_instance_valid(panel.dev_agent_run_spec_input):
		panel._show_warning_dialog("Run Harness", "RunSpecInput not available.")
		return

	var txt := String(panel.dev_agent_run_spec_input.text)
	if txt.strip_edges().is_empty():
		_set_run_spec_result(panel, "No run spec provided.")
		return

	# Validate JSON.
	var j := JSON.new()
	if j.parse(txt) != OK:
		_set_run_spec_result(panel, "Invalid JSON. Fix it before running.")
		return
	var spec_any: Variant = j.data
	if typeof(spec_any) != TYPE_DICTIONARY:
		_set_run_spec_result(panel, "Run spec must be a JSON object.")
		return

	var tid := _get_current_thread_id_for_run_spec(panel)
	var pending := {
		"thread_id": tid,
		"created_at": Time.get_datetime_string_from_system(false, true),
		"spec": spec_any,
	}
	var pending_path := _get_pending_run_spec_path(panel)
	DirAccess.make_dir_recursive_absolute(pending_path.get_base_dir())
	var f := FileAccess.open(pending_path, FileAccess.WRITE)
	if not f:
		_set_run_spec_result(panel, "Failed to write pending run spec:\n%s" % pending_path)
		return
	f.store_string(JSON.stringify(pending, "  "))
	f.close()

	_set_run_spec_result(panel, "Launching harness run…\nPending spec:\n%s" % pending_path)

	# Launch the harness runner scene.
	var harness_scene := "res://addons/syntree/harness/harness_runner.tscn"
	var editor_interface: Variant = panel._plugin_ref.call("get_editor_interface")
	if not is_instance_valid(editor_interface) or not editor_interface.has_method("play_custom_scene"):
		_set_run_spec_result(panel, "EditorInterface not available.")
		return
	editor_interface.call("play_custom_scene", harness_scene)

static func _on_open_backups_folder_pressed(panel: Object) -> void:
	var p := _get_session_data_root_dir(panel).path_join("syntree_dev_agent_backups")
	DirAccess.make_dir_recursive_absolute(p)
	_open_folder_in_os(panel, p)

static func _on_open_artifacts_folder_pressed(panel: Object) -> void:
	# Reserve a stable location for harness/artifacts.
	var p := _get_session_data_root_dir(panel).path_join("syntree_artifacts")
	DirAccess.make_dir_recursive_absolute(p)
	_open_folder_in_os(panel, p)

static func _get_session_data_root_dir(panel: Object) -> String:
	# Agreed local disk location (default set by SynTree EditorPlugin).
	var configured := ""
	if ProjectSettings.has_setting("synesyn/session_data_dir"):
		configured = String(ProjectSettings.get_setting("synesyn/session_data_dir", "")).strip_edges()
	if not configured.is_empty():
		DirAccess.make_dir_recursive_absolute(configured)
		return configured

	# Fallback to Documents/Synesyn (per-user).
	var docs := String(OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)).strip_edges()
	if not docs.is_empty():
		var d := docs.path_join("Synesyn")
		DirAccess.make_dir_recursive_absolute(d)
		return d

	# Final fallback: Godot user:// (app_userdata)
	var u := ProjectSettings.globalize_path("user://Synesyn")
	DirAccess.make_dir_recursive_absolute(u)
	return u

static func _open_folder_in_os(panel: Object, abs_dir: String) -> void:
	var d := String(abs_dir).strip_edges()
	if d.is_empty():
		return
	d = d.replace("\\", "/")
	if OS.get_name() == "Windows":
		var pwin := d.replace("/", "\\")
		var pid := OS.create_process("explorer.exe", PackedStringArray([pwin]), false)
		if pid > 0:
			return
		# Fallback 1: cmd start
		var pid2 := OS.create_process("cmd.exe", PackedStringArray(["/c", "start", "", pwin]), false)
		if pid2 > 0:
			return
		# Fallback 2: shell_open file URL
		var url := "file:///" + d
		OS.shell_open(url)
		return
	OS.shell_open("file://" + d)

static func _get_dev_agent_backup_root_dir(panel: Object) -> String:
	var base := _get_session_data_root_dir(panel).path_join("syntree_dev_agent_backups")
	var ts := Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")
	return base.path_join(ts)

static func _get_last_apply_manifest_path(panel: Object) -> String:
	return _get_session_data_root_dir(panel).path_join("syntree_dev_agent_backups").path_join("last_apply_manifest.json")

static func _write_last_apply_manifest(panel: Object, manifest: Dictionary) -> void:
	var p := _get_last_apply_manifest_path(panel)
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	var f := FileAccess.open(p, FileAccess.WRITE)
	if not f:
		return
	f.store_string(JSON.stringify(manifest, "  "))
	f.close()

static func _read_last_apply_manifest(panel: Object) -> Dictionary:
	var p := _get_last_apply_manifest_path(panel)
	if not FileAccess.file_exists(p):
		return {}
	var f := FileAccess.open(p, FileAccess.READ)
	if not f:
		return {}
	var txt := f.get_as_text()
	f.close()
	var j := JSON.new()
	var err := j.parse(txt)
	if err != OK:
		return {}
	var data: Variant = j.data
	return data if typeof(data) == TYPE_DICTIONARY else {}

static func _on_dev_agent_patch_dry_run_pressed(panel: Object) -> void:
	if not _dev_agent_guard_or_warn(panel):
		return
	var patch := String(panel.dev_agent_patch_input.text)
	if patch.strip_edges().is_empty():
		_set_dev_agent_patch_result(panel, "No patch provided.")
		return
	var res: Dictionary = panel.UnifiedDiffApplier.dry_run_apply(patch)
	if bool(res.get("ok", false)):
		var files: Array = []
		for r_any in res.get("results", []):
			if typeof(r_any) == TYPE_DICTIONARY:
				files.append(str((r_any as Dictionary).get("path", "")))
		_set_dev_agent_patch_result(panel, "Dry run OK.\nFiles:\n- " + "\n- ".join(files))
	else:
		_set_dev_agent_patch_result(panel, "Dry run FAILED:\n" + str(res.get("error", res)))

static func _on_dev_agent_patch_apply_pressed(panel: Object) -> void:
	if not _dev_agent_guard_or_warn(panel):
		return
	var patch := String(panel.dev_agent_patch_input.text)
	if patch.strip_edges().is_empty():
		_set_dev_agent_patch_result(panel, "No patch provided.")
		return
	var backup_root := _get_dev_agent_backup_root_dir(panel)
	var res: Dictionary = panel.UnifiedDiffApplier.apply_with_backups(patch, backup_root)
	if not bool(res.get("ok", false)):
		_set_dev_agent_patch_result(panel, "APPLY FAILED:\n" + str(res.get("error", res)))
		return
	var manifest := {
		"applied_at": Time.get_datetime_string_from_system(false, true),
		"backup_root": backup_root,
		"backups": res.get("backups", []),
	}
	_write_last_apply_manifest(panel, manifest)
	# Refresh active sources so context compilation sees updated content.
	if _bus() and _bus().has_method("refresh_active_sources"):
		_bus().refresh_active_sources()
	_set_dev_agent_patch_result(panel, "APPLY OK.\nBackups in:\n" + backup_root)

static func _on_dev_agent_patch_revert_pressed(panel: Object) -> void:
	if not _dev_agent_guard_or_warn(panel):
		return
	var manifest := _read_last_apply_manifest(panel)
	if manifest.is_empty():
		_set_dev_agent_patch_result(panel, "No last-apply manifest found.\nNothing to revert.")
		return
	var backups_any: Variant = manifest.get("backups", [])
	if typeof(backups_any) != TYPE_ARRAY:
		_set_dev_agent_patch_result(panel, "Invalid manifest format.")
		return
	var backups: Array = backups_any
	var restored := 0
	var failures: Array[String] = []
	for b_any in backups:
		if typeof(b_any) != TYPE_DICTIONARY:
			continue
		var b: Dictionary = b_any
		var target_os := str(b.get("target_os", "")).strip_edges()
		var backup_os := str(b.get("backup_os", "")).strip_edges()
		if target_os.is_empty() or backup_os.is_empty():
			continue
		if not FileAccess.file_exists(backup_os):
			failures.append("Missing backup: %s" % backup_os)
			continue
		var fin := FileAccess.open(backup_os, FileAccess.READ)
		if not fin:
			failures.append("Failed read: %s" % backup_os)
			continue
		var txt := fin.get_as_text()
		fin.close()
		var fout := FileAccess.open(target_os, FileAccess.WRITE)
		if not fout:
			failures.append("Failed write: %s" % target_os)
			continue
		fout.store_string(txt)
		fout.close()
		restored += 1
	if _bus() and _bus().has_method("refresh_active_sources"):
		_bus().refresh_active_sources()
	var msg := "Revert complete.\nRestored: %d" % restored
	if not failures.is_empty():
		msg += "\n\nFailures:\n- " + "\n- ".join(failures)
	_set_dev_agent_patch_result(panel, msg)

static func _on_dev_agent_patch_close_pressed(panel: Object) -> void:
	if is_instance_valid(panel.dev_agent_popup):
		panel.dev_agent_popup.hide()

static func _ensure_ensembles_popup(panel: Object) -> void:
	if is_instance_valid(panel._ensembles_popup):
		return
	if not panel.EnsemblesPopupScene:
		return
	var inst: Node = panel.EnsemblesPopupScene.instantiate()
	if inst is PopupPanel:
		panel._ensembles_popup = inst
		panel.add_child(panel._ensembles_popup)
	else:
		push_warning("SyntreePanel: ensembles_popup.tscn did not instance a PopupPanel.")

static func _reload_current_thread(panel: Object) -> void:
	panel._setup_chat_panel_controller()
	if not is_instance_valid(panel._chat_panel_controller) or not is_instance_valid(panel._view_state_resource):
		return
	panel._chat_panel_controller.load_thread(panel._view_state_resource.get_current_thread_id())

static func _on_thread_dropdown_item_selected(panel: Object, index: int) -> void:
	if is_instance_valid(panel._chat_panel_controller):
		panel._chat_panel_controller.on_thread_selected(index)

static func _on_new_thread_button_pressed(panel: Object) -> void:
	if is_instance_valid(panel._chat_panel_controller):
		panel._chat_panel_controller.on_new_thread()

static func _on_thread_hub_versions_button_pressed(panel: Object) -> void:
	# Ensure the controller exists and is set up, then open the versions popup.
	panel._setup_status_hub_controller()
	if is_instance_valid(panel._status_hub_controller):
		panel._status_hub_controller.on_open_thread_hub_versions_pressed()

static func _on_chat_menu_toggled(panel: Object, button_pressed: bool) -> void:
	if panel.chat_menu_container:
		panel.chat_menu_container.visible = button_pressed
		panel._update_layout_visibility()
		# Sync both toolbars
		if is_instance_valid(panel.top_toolbar_controls):
			panel.top_toolbar_controls.set_chat_menu_state(button_pressed)
		if is_instance_valid(panel.bottom_toolbar_controls):
			panel.bottom_toolbar_controls.set_chat_menu_state(button_pressed)

static func _on_main_menu_toggled(panel: Object, button_pressed: bool) -> void:
	if panel.main_menu_container:
		panel.main_menu_container.visible = button_pressed
		panel._update_layout_visibility()
		# Sync both toolbars
		if is_instance_valid(panel.top_toolbar_controls):
			panel.top_toolbar_controls.set_main_menu_state(button_pressed)
		if is_instance_valid(panel.bottom_toolbar_controls):
			panel.bottom_toolbar_controls.set_main_menu_state(button_pressed)

static func _on_dev_agent_toggled(panel: Object, button_pressed: bool) -> void:
	# Single source of truth: ContentBus -> ViewStateResource (persisted).
	if _bus() and _bus().has_method("set_dev_agent_enabled"):
		_bus().set_dev_agent_enabled(bool(button_pressed))
	# Sync both toolbars (avoid drift when the user clicks top vs bottom).
	var enabled := bool(button_pressed)
	if is_instance_valid(panel.top_toolbar_controls) and panel.top_toolbar_controls.has_method("set_dev_agent_state"):
		panel.top_toolbar_controls.set_dev_agent_state(enabled)
	if is_instance_valid(panel.bottom_toolbar_controls) and panel.bottom_toolbar_controls.has_method("set_dev_agent_state"):
		panel.bottom_toolbar_controls.set_dev_agent_state(enabled)

static func _sync_dev_agent_toggle_from_bus(panel: Object) -> void:
	if not (_bus() and _bus().has_method("is_dev_agent_enabled")):
		return
	var enabled := bool(_bus().is_dev_agent_enabled())
	if is_instance_valid(panel.top_toolbar_controls) and panel.top_toolbar_controls.has_method("set_dev_agent_state"):
		panel.top_toolbar_controls.set_dev_agent_state(enabled)
	if is_instance_valid(panel.bottom_toolbar_controls) and panel.bottom_toolbar_controls.has_method("set_dev_agent_state"):
		panel.bottom_toolbar_controls.set_dev_agent_state(enabled)

static func _wire_dev_agent_bus_signal(panel: Object) -> void:
	# If dev-agent enabled state changes elsewhere, keep UI in sync.
	if not _bus():
		return
	if not _bus().has_signal("dev_agent_enabled_changed"):
		return
	if not _bus().dev_agent_enabled_changed.is_connected(Callable(panel, "_on_dev_agent_bus_changed")):
		_bus().dev_agent_enabled_changed.connect(Callable(panel, "_on_dev_agent_bus_changed"))

static func _on_dev_agent_bus_changed(panel: Object, enabled: bool) -> void:
	# Update UI without re-emitting (ToolbarControls handles internal guard).
	var en := bool(enabled)
	if is_instance_valid(panel.top_toolbar_controls) and panel.top_toolbar_controls.has_method("set_dev_agent_state"):
		panel.top_toolbar_controls.set_dev_agent_state(en)
	if is_instance_valid(panel.bottom_toolbar_controls) and panel.bottom_toolbar_controls.has_method("set_dev_agent_state"):
		panel.bottom_toolbar_controls.set_dev_agent_state(en)

