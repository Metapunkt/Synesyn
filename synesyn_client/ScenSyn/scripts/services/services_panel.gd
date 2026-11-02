extends Control

signal panel_opened
signal panel_closed

const WorkspaceUtilsScript = preload("res://ScenSyn/scripts/services/internal/services_panel_workspace_utils.gd")

@onready var hub_path_edit: LineEdit = %HubPathEdit
@onready var start_button: Button = %StartHubButton
@onready var stop_button: Button = %StopHubButton
@onready var health_label: Label = %HealthLabel
@onready var status_text: TextEdit = %StatusText
@onready var error_label: Label = %ErrorLabel
@onready var current_ws_details_label: Label = %CurrentWorkspaceDetailsLabel

@onready var ws_name_edit: LineEdit = %WorkspaceNameEdit
@onready var ws_slug_edit: LineEdit = %WorkspaceSlugEdit
@onready var ws_root_edit: LineEdit = %WorkspaceRootEdit
@onready var ws_name_pick: OptionButton = %WorkspaceNamePick
@onready var ws_slug_pick: OptionButton = %WorkspaceSlugPick
@onready var ws_root_pick: OptionButton = %WorkspaceRootPick

@onready var export_button: Button = %ExportButton
@onready var voice_test_button: Button = %VoiceTestButton
@onready var voice_mode_option: OptionButton = %VoiceModeOption
@onready var hub_tts_provider_option: OptionButton = get_node_or_null("%HubTtsProviderOption")
@onready var hub_tts_provider_status_label: Label = get_node_or_null("%HubTtsProviderStatusLabel")
@onready var hub_url_edit: LineEdit = %HubUrlEdit
@onready var voice_service_url_edit: LineEdit = %VoiceServiceUrlEdit
@onready var save_providers_button: Button = %SaveProvidersButton
@onready var save_recordings_toggle: CheckButton = get_node_or_null("%SaveRecordingsToggle")
@onready var publish_character_voices_button: Button = get_node_or_null("%PublishCharacterVoicesButton")

@onready var metapunkt_auth_mode_option: OptionButton = get_node_or_null("%MetapunktAuthModeOption") as OptionButton
@onready var metapunkt_auth_token_edit: LineEdit = get_node_or_null("%MetapunktAuthTokenEdit") as LineEdit
@onready var metapunkt_verify_via_hub_toggle: CheckButton = get_node_or_null("%MetapunktVerifyViaHubToggle") as CheckButton
@onready var ui_scale_option: OptionButton = get_node_or_null("%UIScaleOption") as OptionButton

@onready var file_dialog: FileDialog = %HubExeDialog
@onready var workspace_root_dialog: FileDialog = %WorkspaceRootDialog
@onready var backdrop_rect: ColorRect = $Backdrop
@onready var panel_container: PanelContainer = $Panel

var hub: HubProcessManager
var _last_workspace_base_root: String = ""
var _current_ws_name: String = ""
var _current_ws_slug: String = ""
var _current_ws_base_root: String = ""
var _current_ws_root: String = ""
var _workspace_user_dirty: bool = false
var _workspace_synced_once: bool = false
var _last_health_ok: bool = false
var _workspace_programmatic_update: bool = false
var _workspace_sync_inflight: bool = false
var _desired_ws_loaded: bool = false
var _desired_ws_applied_once: bool = false
var _desired_ws_name: String = ""
var _desired_ws_slug: String = ""
var _desired_ws_root_base: String = ""
var _desired_ws_pending_hub_apply: bool = false
var _ws_label_refresh_inflight: bool = false
var _ws_label_refresh_last_ms: int = 0
## True while the slug field contains an auto-generated value derived from the name.
## Set to false as soon as the user edits the slug field manually or hub data is applied.
var _slug_is_auto: bool = true

const _OVERLAY_MARGIN_X := 72.0
const _OVERLAY_MARGIN_Y := 52.0

func _ready() -> void:
	hub = HubProcessManager.new()
	add_child(hub)
	_configure_panel_presentation()

	# Only prefill when the hub is actually present; otherwise leave the field
	# empty and rely on Browse rather than showing a path that does not exist.
	var default_exe := HubLocator.find_hub_exe(RuntimeConfig.load_config())
	if hub_path_edit.text.is_empty() and not default_exe.is_empty():
		hub_path_edit.text = default_exe

	start_button.pressed.connect(_on_start_pressed)
	stop_button.pressed.connect(_on_stop_pressed)
	export_button.pressed.connect(_on_export_pressed)
	voice_test_button.pressed.connect(_on_voice_test_pressed)
	if save_providers_button:
		save_providers_button.pressed.connect(_on_save_providers_pressed)
	if ui_scale_option:
		ui_scale_option.item_selected.connect(_on_ui_scale_option_selected)
	if save_recordings_toggle:
		save_recordings_toggle.toggled.connect(_on_save_recordings_toggled)
	if publish_character_voices_button:
		publish_character_voices_button.pressed.connect(_on_publish_character_voices_pressed)

	%BrowseHubButton.pressed.connect(func():
		file_dialog.popup_centered_ratio(0.7)
	)
	file_dialog.file_selected.connect(func(path: String):
		hub_path_edit.text = path
	)
	file_dialog.files_selected.connect(func(paths: PackedStringArray):
		if paths.size() > 0:
			hub_path_edit.text = String(paths[0])
	)

	if ws_name_pick:
		ws_name_pick.item_selected.connect(_on_ws_name_pick_selected)
	if ws_slug_pick:
		ws_slug_pick.item_selected.connect(_on_ws_slug_pick_selected)
	if ws_root_pick:
		ws_root_pick.item_selected.connect(_on_ws_root_pick_selected)
	if workspace_root_dialog:
		workspace_root_dialog.dir_selected.connect(_on_ws_root_dir_selected)

	# If the user starts editing workspace fields, don't keep overwriting them
	# from the hub's current workspace during polling.
	if ws_name_edit:
		ws_name_edit.text_changed.connect(func(t: String) -> void:
			if _workspace_programmatic_update:
				return
			_workspace_user_dirty = true
			# Auto-fill slug from name while the user hasn't set a custom slug.
			if _slug_is_auto and ws_slug_edit:
				_workspace_programmatic_update = true
				ws_slug_edit.text = WorkspaceUtilsScript.slugify(t)
				_workspace_programmatic_update = false
		)
	if ws_slug_edit:
		ws_slug_edit.text_changed.connect(func(_t: String) -> void:
			if _workspace_programmatic_update:
				return
			_workspace_user_dirty = true
			_slug_is_auto = false  # User typed their own slug; stop auto-generating.
		)
	if ws_root_edit:
		ws_root_edit.text_changed.connect(func(_t: String) -> void:
			if _workspace_programmatic_update:
				return
			_workspace_user_dirty = true
		)

	%CloseButton.pressed.connect(func():
		close_panel()
	)
	if backdrop_rect:
		backdrop_rect.gui_input.connect(_on_backdrop_gui_input)

	hub.hub_started.connect(func(pid: int):
		error_label.text = ""
	)
	hub.hub_stopped.connect(func():
		health_label.text = "Hub stopped"
	)
	hub.hub_health_updated.connect(_on_health_updated)
	hub.hub_status_updated.connect(_on_status_updated)
	hub.hub_error.connect(func(msg: String):
		error_label.text = msg
	)

	_load_provider_config_into_ui()
	# Re-apply stored UI scale each time Services opens (covers the first scene load).
	var _cfg_for_scale: Dictionary = RuntimeConfig.load_config()
	var _disp_cfg: Dictionary = _cfg_for_scale.get("display", {})
	_apply_ui_scale(float(_disp_cfg.get("ui_scale", 1.0)))
	_load_workspace_config_into_ui()
	# Populate pickers immediately with best-effort defaults (even if hub is down).
	_refresh_workspace_dropdowns()
	call_deferred("_ensure_workspace_synced")
	_update_buttons()
	if _is_overlay_mode():
		_set_open_state(visible)
	else:
		if backdrop_rect:
			backdrop_rect.visible = false

func _is_overlay_mode() -> bool:
	var parent_node: Node = get_parent()
	if not is_instance_valid(parent_node):
		return false
	if parent_node is TabContainer:
		return false
	var ancestor: Node = parent_node
	while is_instance_valid(ancestor):
		if ancestor is TabContainer:
			return false
		ancestor = ancestor.get_parent()
	return true

func _configure_panel_presentation() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	if backdrop_rect:
		backdrop_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	if panel_container:
		panel_container.mouse_filter = Control.MOUSE_FILTER_STOP
	if _is_overlay_mode() and panel_container:
		panel_container.anchor_left = 0.0
		panel_container.anchor_top = 0.0
		panel_container.anchor_right = 1.0
		panel_container.anchor_bottom = 1.0
		panel_container.offset_left = _OVERLAY_MARGIN_X
		panel_container.offset_top = _OVERLAY_MARGIN_Y
		panel_container.offset_right = -_OVERLAY_MARGIN_X
		panel_container.offset_bottom = -_OVERLAY_MARGIN_Y

func _set_open_state(is_open: bool) -> void:
	visible = is_open
	if backdrop_rect:
		backdrop_rect.visible = is_open and _is_overlay_mode()
	if is_open:
		panel_opened.emit()
	else:
		panel_closed.emit()

func open_panel() -> void:
	if _is_overlay_mode():
		_set_open_state(true)
	else:
		visible = true

func close_panel() -> void:
	if _is_overlay_mode():
		_set_open_state(false)
	else:
		visible = false

func toggle_panel() -> void:
	if is_panel_open():
		close_panel()
	else:
		open_panel()

func is_panel_open() -> bool:
	return visible

func _on_backdrop_gui_input(event: InputEvent) -> void:
	if not _is_overlay_mode():
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close_panel()
		get_viewport().set_input_as_handled()

func _load_workspace_config_into_ui() -> void:
	# Persisted "last applied workspace" (client-side) stored in a dedicated state file.
	# This avoids churn/overwrites from other systems that also write synesyn_client.json.
	var ws_cfg: Dictionary = WorkspaceUtilsScript.load_workspace_state()
	if ws_cfg.is_empty():
		return
	_desired_ws_name = str(ws_cfg.get("name", "")).strip_edges()
	_desired_ws_slug = str(ws_cfg.get("slug", "")).strip_edges()
	_desired_ws_root_base = str(ws_cfg.get("root_base", "")).strip_edges()
	_desired_ws_loaded = (not _desired_ws_name.is_empty()) and (not _desired_ws_slug.is_empty())
	if not _desired_ws_loaded:
		return

	# Migration / sanity:
	# Historically, Synesyn used Documents/Synesyn as the base root. That mixes workspaces
	# with config/logs/substrate folders and is confusing. Prefer:
	#   Documents/Synesyn/Workspaces
	# Unless the user explicitly chose a different root, migrate legacy roots.
	var legacy_root := WorkspaceUtilsScript.to_native_path(str(OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)).path_join("Synesyn")).strip_edges()
	var workspaces_root := WorkspaceUtilsScript.to_native_path(str(OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)).path_join("Synesyn").path_join(WorkspaceUtilsScript.DEFAULT_WORKSPACES_DIRNAME)).strip_edges()
	if _desired_ws_root_base.is_empty() or WorkspaceUtilsScript.norm_picker_value(_desired_ws_root_base) == WorkspaceUtilsScript.norm_picker_value(legacy_root):
		_desired_ws_root_base = workspaces_root
		# Persist migrated base root so restarts are stable.
		_save_workspace_state(_desired_ws_name, _desired_ws_slug, _desired_ws_root_base)

	# Always (re)apply desired workspace to hub on startup once reachable.
	# This makes persistence deterministic even if the hub boots with a stale selection.
	_desired_ws_applied_once = false
	_desired_ws_pending_hub_apply = true

	# Pre-fill the "Set Workspace ..." fields from the last applied selection
	# so restarts feel stable even before the hub finishes starting.
	if not _workspace_user_dirty:
		_workspace_programmatic_update = true
		ws_name_edit.text = _desired_ws_name
		ws_slug_edit.text = _desired_ws_slug
		if not _desired_ws_root_base.is_empty():
			ws_root_edit.text = _desired_ws_root_base
			_last_workspace_base_root = _desired_ws_root_base
		_workspace_programmatic_update = false
		_slug_is_auto = false  # Slug comes from persisted desired-state, not auto-gen.
		_refresh_workspace_dropdowns()
		_autoselect_workspace_pickers()

		# Pre-fill the "Current workspace" label optimistically from desired values.
		# Hub sync will reconcile later (and should converge to the same values).
		var base_root: String = _desired_ws_root_base
		if base_root.is_empty():
			base_root = str(OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)).path_join("Synesyn").path_join(WorkspaceUtilsScript.DEFAULT_WORKSPACES_DIRNAME)
		var workspace_root: String = base_root.path_join(_desired_ws_slug)
		_apply_current_workspace_from_dict({"name": _desired_ws_name, "slug": _desired_ws_slug, "root": workspace_root})

func _save_workspace_state(ws_name: String, slug: String, root_base: String) -> void:
	var boot_write := WorkspaceUtilsScript.save_workspace_state(ws_name, slug, root_base)
	if not (boot_write.get("ok", false) == true):
		# Make failures visible; otherwise it looks like "persistence doesn't work".
		error_label.text = "Workspace saved, but couldn't write the Hub boot file — the Hub may not remember this workspace after a restart. Details: %s (%s)" % [str(boot_write.get("error", "unknown error")), str(boot_write.get("path", ""))]

func _ensure_workspace_synced() -> void:
	# Deterministic fix: retry GET /workspace until we get a real workspace,
	# then select the corresponding dropdown entries.
	if _workspace_sync_inflight:
		return
	_workspace_sync_inflight = true

	# Wait for hub node to be ready.
	for _i in range(30):
		if hub != null and hub.is_node_ready():
			break
		await get_tree().process_frame

	# Retry a few seconds; hub may still be starting.
	# IMPORTANT: when we have a persisted desired workspace, we do NOT trust the hub's
	# boot-time selection. We force-apply the desired workspace first, then verify via GET.
	for _attempt in range(60):
		var res_ws: Dictionary = await hub.get_workspace()
		var hub_reachable: bool = (res_ws.get("ok", false) == true)
		if not hub_reachable:
			await get_tree().create_timer(0.2).timeout
			continue

		# Step 1: if we have a desired workspace, force-apply it once.
		if _desired_ws_loaded and _desired_ws_pending_hub_apply and (not _desired_ws_applied_once):
			var root_base := _desired_ws_root_base
			if root_base.strip_edges().is_empty():
				root_base = str(OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)).path_join("Synesyn").path_join(WorkspaceUtilsScript.DEFAULT_WORKSPACES_DIRNAME)
			var res_sel: Dictionary = await hub.select_workspace(_desired_ws_name, _desired_ws_slug, root_base)
			if res_sel.get("ok", false) == true:
				_desired_ws_applied_once = true
				_desired_ws_pending_hub_apply = false
			else:
				error_label.text = "Couldn't apply saved workspace on startup — Hub may not have been ready yet. Try clicking Apply Workspace manually. Details: %s" % str(res_sel.get("error", res_sel))

			# Always re-read after attempting to apply; do not reuse stale pre-apply GET data.
			res_ws = await hub.get_workspace()
			if not (res_ws.get("ok", false) == true):
				await get_tree().create_timer(0.2).timeout
				continue

		# Step 2: show the hub's current workspace (authoritative).
		var ws_dict: Dictionary = WorkspaceUtilsScript.extract_workspace_dict(res_ws.get("data", null))
		if not ws_dict.is_empty():
			var n := str(ws_dict.get("name", "") if ws_dict.get("name") != null else "").strip_edges()
			var s := str(ws_dict.get("slug", "") if ws_dict.get("slug") != null else "").strip_edges()
			if not n.is_empty() and not s.is_empty():
				_apply_current_workspace_from_dict(ws_dict)

		# Exit when hub reflects desired (or we have no desired).
		if not _desired_ws_loaded:
			_workspace_sync_inflight = false
			return
		if (not _current_ws_name.is_empty()) and (not _current_ws_slug.is_empty()) and _current_ws_name == _desired_ws_name and _current_ws_slug == _desired_ws_slug:
			_workspace_sync_inflight = false
			return

		await get_tree().create_timer(0.2).timeout
	_workspace_sync_inflight = false

func _refresh_workspace_ui_from_hub(force: bool = false) -> bool:
	# Populate Name/Slug/Root from the currently active workspace in the Hub,
	# and build dropdowns based on the last-used base root folder.
	if hub == null:
		return false
	var res: Dictionary = await hub.get_workspace()
	if not (res.get("ok", false) == true):
		return false
	var data_any: Variant = res.get("data", null)
	var ws: Dictionary = WorkspaceUtilsScript.extract_workspace_dict(data_any)
	if ws.is_empty():
		return false

	var ws_name := str(ws.get("name", "")).strip_edges()
	var slug := str(ws.get("slug", "")).strip_edges()
	var hub_root := str(ws.get("root", "")).strip_edges()
	if ws_name.is_empty() or slug.is_empty():
		# Hub is reachable but workspace not configured yet.
		return false

	var base_root := WorkspaceUtilsScript.base_root_from_hub_workspace_root(hub_root, slug)

	# Persist the hub-reported "current workspace" values for deterministic selection.
	_current_ws_name = ws_name
	_current_ws_slug = slug
	_current_ws_base_root = base_root
	_last_workspace_base_root = base_root
	_current_ws_root = hub_root
	_workspace_synced_once = true

	_refresh_current_workspace_details_label()

	# Only overwrite UI fields if we're not actively editing (or if forced).
	if force or not _workspace_user_dirty:
		_workspace_programmatic_update = true
		if not ws_name.is_empty():
			ws_name_edit.text = ws_name
		if not slug.is_empty():
			ws_slug_edit.text = slug
		if not base_root.is_empty():
			ws_root_edit.text = base_root
		_workspace_programmatic_update = false
		_slug_is_auto = false  # Slug comes from hub, not auto-gen.

	_refresh_workspace_dropdowns()
	_autoselect_workspace_pickers()
	return true

func _refresh_current_workspace_details_label() -> void:
	if current_ws_details_label == null:
		return
	var n := _current_ws_name if not _current_ws_name.is_empty() else "(unknown)"
	var s := _current_ws_slug if not _current_ws_slug.is_empty() else "(unknown)"
	var r := WorkspaceUtilsScript.to_native_path(_current_ws_root) if (not _current_ws_root.is_empty()) else "(unknown)"

	var dn := _desired_ws_name if not _desired_ws_name.is_empty() else "(unknown)"
	var ds := _desired_ws_slug if not _desired_ws_slug.is_empty() else "(unknown)"
	var dr := WorkspaceUtilsScript.to_native_path(_desired_ws_root_base) if (not _desired_ws_root_base.is_empty()) else "(unknown)"

	current_ws_details_label.text = (
		"Hub Current Workspace Name: %s\nHub Current Workspace Slug: %s\nHub Current Workspace Root: %s\n"
		+ "Last Applied Workspace Name: %s\nLast Applied Workspace Slug: %s\nLast Applied Workspace Root (base): %s"
	) % [n, s, r, dn, ds, dr]

func _apply_current_workspace_from_dict(ws: Dictionary) -> void:
	# Update "current workspace" (hub-truth) fields from a hub workspace dict:
	# {"name": str|None, "slug": str|None, "root": str|None}
	var ws_name := str(ws.get("name", "") if ws.get("name") != null else "").strip_edges()
	var slug := str(ws.get("slug", "") if ws.get("slug") != null else "").strip_edges()
	var root := str(ws.get("root", "") if ws.get("root") != null else "").strip_edges()

	_current_ws_name = ws_name
	_current_ws_slug = slug
	_current_ws_root = root
	_current_ws_base_root = WorkspaceUtilsScript.base_root_from_hub_workspace_root(root, slug)
	if not _current_ws_base_root.is_empty():
		_last_workspace_base_root = _current_ws_base_root
	_workspace_synced_once = true
	_refresh_current_workspace_details_label()
	# IMPORTANT:
	# Do NOT auto-select the "Set Workspace ..." pickers from hub state.
	# The pickers/edits represent the desired workspace to apply, while this function
	# only updates the hub's current workspace label. Keeping these separate prevents
	# the mismatch you observed (inputs show Workspace_4 but pickers snap to Workspace_1).

func _refresh_workspace_dropdowns() -> void:
	_refresh_root_pick()
	_refresh_slug_pick()
	_refresh_name_pick()
	# Keep selections aligned with the current text fields.
	_autoselect_workspace_pickers()

func _autoselect_workspace_pickers() -> void:
	# Ensure pickers reflect the "current workspace" fields so the UI is intuitive.
	# (This is important on startup: LineEdits may populate, but OptionButtons otherwise stay on item 0.)
	if ws_root_pick:
		var want_root := _current_ws_base_root if not _current_ws_base_root.is_empty() else ws_root_edit.text.strip_edges()
		_select_or_add_option_by_text(ws_root_pick, want_root)
	if ws_slug_pick:
		var want_slug := _current_ws_slug if not _current_ws_slug.is_empty() else ws_slug_edit.text.strip_edges()
		_select_or_add_option_by_text(ws_slug_pick, want_slug)
	if ws_name_pick:
		var want_name := _current_ws_name if not _current_ws_name.is_empty() else ws_name_edit.text.strip_edges()
		_select_or_add_option_by_text(ws_name_pick, want_name)

func _select_or_add_option_by_text(ob: OptionButton, text: String) -> void:
	var t := text.strip_edges()
	if t.is_empty() or ob == null:
		return
	var target := WorkspaceUtilsScript.norm_picker_value(t)
	for i in range(ob.item_count):
		# Skip sentinel items like "Browse…" or the "choose existing" placeholder.
		var md: Variant = ob.get_item_metadata(i)
		if typeof(md) == TYPE_STRING and (str(md) == WorkspaceUtilsScript.META_BROWSE_ROOT or str(md) == WorkspaceUtilsScript.META_PLACEHOLDER):
			continue
		var item_text := ob.get_item_text(i)
		if WorkspaceUtilsScript.norm_picker_value(item_text) == target:
			ob.select(i)
			return
	# If the current workspace value isn't in the scanned list (or differs by formatting),
	# add it so the picker always reflects the hub's active workspace.
	ob.add_item(t)
	ob.select(ob.item_count - 1)

func _refresh_root_pick() -> void:
	if ws_root_pick == null:
		return
	ws_root_pick.clear()

	var roots: Array[String] = []
	var from_edit := ws_root_edit.text.strip_edges()
	if not from_edit.is_empty():
		roots.append(from_edit)
	if not _last_workspace_base_root.is_empty() and _last_workspace_base_root != from_edit:
		roots.append(_last_workspace_base_root)

	# Common default: Documents/Synesyn/Workspaces
	var docs_root := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS).path_join("Synesyn").path_join(WorkspaceUtilsScript.DEFAULT_WORKSPACES_DIRNAME)
	docs_root = WorkspaceUtilsScript.to_native_path(docs_root)
	if docs_root != from_edit and docs_root != _last_workspace_base_root:
		roots.append(docs_root)
	# Legacy base root: Documents/Synesyn
	var legacy_root := WorkspaceUtilsScript.to_native_path(OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS).path_join("Synesyn"))
	if legacy_root != from_edit and legacy_root != _last_workspace_base_root and legacy_root != docs_root:
		roots.append(legacy_root)
	# If we have no remembered root yet, prefer the common default so scans work.
	if _last_workspace_base_root.is_empty():
		_last_workspace_base_root = docs_root

	for r in roots:
		if r.is_empty():
			continue
		ws_root_pick.add_item(r)

	ws_root_pick.add_separator()
	ws_root_pick.add_item("Browse…")
	ws_root_pick.set_item_metadata(ws_root_pick.item_count - 1, WorkspaceUtilsScript.META_BROWSE_ROOT)

func _refresh_slug_pick() -> void:
	if ws_slug_pick == null:
		return
	ws_slug_pick.clear()
	ws_slug_pick.add_item("— choose existing —")
	ws_slug_pick.set_item_disabled(0, true)
	ws_slug_pick.set_item_metadata(0, WorkspaceUtilsScript.META_PLACEHOLDER)

	var base_root := ws_root_edit.text.strip_edges()
	if base_root.is_empty():
		base_root = _last_workspace_base_root

	var slugs: Array[String] = []
	if not base_root.is_empty():
		slugs = WorkspaceUtilsScript.scan_workspace_slugs(base_root)

	# Ensure current value is present.
	var cur := ws_slug_edit.text.strip_edges()
	if not cur.is_empty() and not slugs.has(cur):
		slugs.push_front(cur)

	for s in slugs:
		ws_slug_pick.add_item(s)

func _refresh_name_pick() -> void:
	if ws_name_pick == null:
		return
	ws_name_pick.clear()
	ws_name_pick.add_item("— choose existing —")
	ws_name_pick.set_item_disabled(0, true)
	ws_name_pick.set_item_metadata(0, WorkspaceUtilsScript.META_PLACEHOLDER)

	# Populate from per-workspace metadata when available (workspace.json),
	# otherwise fall back to slug.
	var base_root := ws_root_edit.text.strip_edges()
	if base_root.is_empty():
		base_root = _last_workspace_base_root
	var records: Array[Dictionary] = WorkspaceUtilsScript.scan_workspace_records(base_root)

	# Ensure current typed value is present.
	var cur_name := ws_name_edit.text.strip_edges()
	var cur_slug := ws_slug_edit.text.strip_edges()
	if not cur_slug.is_empty():
		var found := false
		for r in records:
			if str(r.get("slug", "")) == cur_slug:
				found = true
				break
		if not found:
			records.push_front({"slug": cur_slug, "name": (cur_name if not cur_name.is_empty() else cur_slug)})

	for r in records:
		var s := str(r.get("slug", "")).strip_edges()
		if s.is_empty():
			continue
		var n := str(r.get("name", "")).strip_edges()
		if n.is_empty():
			n = s
		ws_name_pick.add_item(n)
		ws_name_pick.set_item_metadata(ws_name_pick.item_count - 1, {"slug": s})

func _on_ws_name_pick_selected(idx: int) -> void:
	if ws_name_pick == null:
		return
	var check_meta: Variant = ws_name_pick.get_item_metadata(idx)
	if typeof(check_meta) == TYPE_STRING and str(check_meta) == WorkspaceUtilsScript.META_PLACEHOLDER:
		return
	ws_name_edit.text = ws_name_pick.get_item_text(idx)
	var meta: Variant = ws_name_pick.get_item_metadata(idx)
	if typeof(meta) == TYPE_DICTIONARY:
		var m: Dictionary = meta
		var s := str(m.get("slug", "")).strip_edges()
		if not s.is_empty():
			ws_slug_edit.text = s
	_workspace_user_dirty = true

func _on_ws_slug_pick_selected(idx: int) -> void:
	if ws_slug_pick == null:
		return
	var check_meta: Variant = ws_slug_pick.get_item_metadata(idx)
	if typeof(check_meta) == TYPE_STRING and str(check_meta) == WorkspaceUtilsScript.META_PLACEHOLDER:
		return
	var picked := ws_slug_pick.get_item_text(idx)
	var prev_slug := ws_slug_edit.text.strip_edges()
	ws_slug_edit.text = picked
	# If name is empty or was mirroring the slug, keep it in sync for convenience.
	var prev_name := ws_name_edit.text.strip_edges()
	if prev_name.is_empty() or prev_name == prev_slug:
		ws_name_edit.text = picked
	_workspace_user_dirty = true

func _on_ws_root_pick_selected(idx: int) -> void:
	if ws_root_pick == null:
		return
	var meta = ws_root_pick.get_item_metadata(idx)
	if meta == WorkspaceUtilsScript.META_BROWSE_ROOT:
		if workspace_root_dialog:
			var base_root := ws_root_edit.text.strip_edges()
			if base_root.is_empty():
				base_root = _last_workspace_base_root
			if not base_root.is_empty():
				workspace_root_dialog.current_dir = base_root
			workspace_root_dialog.popup_centered_ratio(0.75)
		return

	var picked := ws_root_pick.get_item_text(idx)
	if picked.is_empty():
		return
	ws_root_edit.text = picked
	_last_workspace_base_root = picked
	_refresh_workspace_dropdowns()
	_workspace_user_dirty = true

func _on_ws_root_dir_selected(dir_path: String) -> void:
	var picked := dir_path.strip_edges()
	if picked.is_empty():
		return
	ws_root_edit.text = picked
	_last_workspace_base_root = picked
	_refresh_workspace_dropdowns()
	_workspace_user_dirty = true

func _load_provider_config_into_ui() -> void:
	var cfg: Dictionary = RuntimeConfig.load_config()
	var voice_cfg: Dictionary = cfg.get("voice", {})
	var hub_cfg: Dictionary = cfg.get("hub", {})

	var mode := str(voice_cfg.get("provider_mode", "direct")).strip_edges().to_lower()
	if voice_mode_option:
		# id 0 = hub, id 1 = direct (see scene)
		voice_mode_option.select(0 if mode == "hub" else 1)
	if hub_tts_provider_option:
		var tts_pref := str(voice_cfg.get("hub_tts_provider_preference", "auto")).strip_edges().to_lower()
		match tts_pref:
			"edge", "edge_tts", "edgetts":
				hub_tts_provider_option.select(1)
			"sapi", "pyttsx3":
				hub_tts_provider_option.select(2)
			"sidecar", "voice_sidecar":
				hub_tts_provider_option.select(3)
			_:
				hub_tts_provider_option.select(0)

	if hub_url_edit:
		hub_url_edit.text = str(voice_cfg.get("hub_url", "http://127.0.0.1:17777"))
	if hub_path_edit:
		var saved_exec := str(hub_cfg.get("exec_path", "")).strip_edges()
		if not saved_exec.is_empty():
			hub_path_edit.text = saved_exec
	if voice_service_url_edit:
		voice_service_url_edit.text = str(voice_cfg.get("service_url", "http://127.0.0.1:8000"))
	if save_recordings_toggle:
		save_recordings_toggle.button_pressed = (voice_cfg.get("save_recordings", false) == true)
	_refresh_hub_tts_provider_status(voice_cfg)

	# Metapunkt auth config
	var apps_cfg: Dictionary = cfg.get("apps", {})
	var mp_cfg: Dictionary = apps_cfg.get("metapunkt", {})
	var auth_mode := str(mp_cfg.get("auth_mode", "no-auth")).strip_edges().to_lower()
	if metapunkt_auth_mode_option:
		# id 0 = no-auth, id 1 = auth-required (see scene)
		# Back-compat: accept "open"/"required"
		metapunkt_auth_mode_option.select(1 if (auth_mode == "auth-required" or auth_mode == "required") else 0)
	if metapunkt_auth_token_edit:
		metapunkt_auth_token_edit.text = str(mp_cfg.get("auth_token", ""))
	if metapunkt_verify_via_hub_toggle:
		metapunkt_verify_via_hub_toggle.button_pressed = (mp_cfg.get("auth_verify_via_hub", false) == true)

	# Display: UI scale
	var display_cfg: Dictionary = cfg.get("display", {})
	var stored_scale: float = float(display_cfg.get("ui_scale", 1.0))
	if ui_scale_option:
		ui_scale_option.select(_ui_scale_to_option_idx(stored_scale))

func _ui_scale_to_option_idx(scale: float) -> int:
	# Map stored float to OptionButton index (75%, 100%, 125%, 150%, 200%).
	if scale <= 0.80:
		return 0  # 75 %
	elif scale <= 1.12:
		return 1  # 100 %
	elif scale <= 1.37:
		return 2  # 125 %
	elif scale <= 1.75:
		return 3  # 150 %
	return 4  # 200 %

func _option_idx_to_ui_scale(idx: int) -> float:
	match idx:
		0: return 0.75
		1: return 1.0
		2: return 1.25
		3: return 1.5
		4: return 2.0
		_: return 1.0

func _apply_ui_scale(scale: float) -> void:
	RuntimeConfig.apply_ui_scale(get_tree().root, scale)
	# Portrait header banner is size-fitted in local coords; re-fit after scale.
	var session_host: Node = get_tree().current_scene
	if session_host != null and session_host.has_method("_fit_header_banner"):
		session_host.call_deferred("_fit_header_banner")

func _unhandled_input(event: InputEvent) -> void:
	if is_panel_open() and _is_overlay_mode():
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
			close_panel()
			get_viewport().set_input_as_handled()
			return
	# Quick toggle (useful in kiosk): F12
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F12:
		toggle_panel()

func _update_buttons() -> void:
	# A hub this client did not spawn still occupies the port, so drive the
	# buttons from reachability as well as from our own PID. Otherwise Stop sits
	# disabled against an orphan and Start invites a spawn that cannot bind.
	var present: bool = hub.is_running() or hub.is_reachable()
	start_button.disabled = present
	stop_button.disabled = not present

func _on_start_pressed() -> void:
	error_label.text = ""
	var args_list: Array[String] = []
	var exec_path := hub_path_edit.text.strip_edges()
	var ok = hub.start_hub(exec_path, args_list)
	_update_buttons()
	if not ok:
		return
	# Register the PID with WorkspaceBootstrapper so it is killed on app exit.
	# An adopted hub reports -1 and is deliberately left unregistered: this
	# client did not start it and must not kill it on the way out.
	var pid := hub.get_pid()
	if pid > 0 and WorkspaceBootstrapper and WorkspaceBootstrapper.has_method("register_hub_process"):
		WorkspaceBootstrapper.register_hub_process(pid, exec_path)

func _on_stop_pressed() -> void:
	var stopped: bool = await hub.stop_hub_async()
	if not stopped:
		error_label.text = "Could not stop the hub. It may already be down, or unresponsive."
	_update_buttons()
	# Clear registration so WorkspaceBootstrapper doesn't try to re-kill a dead process.
	if WorkspaceBootstrapper and WorkspaceBootstrapper.has_method("clear_hub_process_registration"):
		WorkspaceBootstrapper.clear_hub_process_registration()

func _on_health_updated(ok: bool, payload: Dictionary) -> void:
	health_label.text = "Hub: %s" % ("OK" if ok else "NOT OK")
	if payload.has("reason") and payload["reason"] != null:
		health_label.text += " (%s)" % str(payload["reason"])
	# Do NOT refresh workspace fields on every poll tick; it will overwrite edits.
	# But do a one-shot sync when the hub becomes reachable (common on startup).
	if ok and (not _last_health_ok):
		if (not _workspace_user_dirty) and (not _workspace_synced_once):
			call_deferred("_ensure_workspace_synced")
	_last_health_ok = ok
	# Always keep the "Current Workspace ..." label up to date (does not modify input fields).
	if ok:
		_kick_refresh_current_workspace_label()

func _on_status_updated(payload: Dictionary) -> void:
	status_text.text = JSON.stringify(payload, "\t")

func _kick_refresh_current_workspace_label() -> void:
	# Throttle to avoid spamming /workspace calls.
	if _ws_label_refresh_inflight:
		return
	var now_ms := int(Time.get_ticks_msec())
	if _ws_label_refresh_last_ms > 0 and (now_ms - _ws_label_refresh_last_ms) < 900:
		return
	_ws_label_refresh_last_ms = now_ms
	call_deferred("_refresh_current_workspace_label_async")

func _refresh_current_workspace_label_async() -> void:
	if _ws_label_refresh_inflight:
		return
	_ws_label_refresh_inflight = true
	if hub != null:
		var res: Dictionary = await hub.get_workspace()
		if res.get("ok", false) == true:
			var ws: Dictionary = WorkspaceUtilsScript.extract_workspace_dict(res.get("data", null))
			if not ws.is_empty():
				# Update current-workspace fields and label ONLY (do not touch input fields).
				var ws_name := str(ws.get("name", "") if ws.get("name") != null else "").strip_edges()
				var slug := str(ws.get("slug", "") if ws.get("slug") != null else "").strip_edges()
				var root := str(ws.get("root", "") if ws.get("root") != null else "").strip_edges()
				if not ws_name.is_empty() and not slug.is_empty():
					_current_ws_name = ws_name
					_current_ws_slug = slug
					_current_ws_root = root
					_current_ws_base_root = WorkspaceUtilsScript.base_root_from_hub_workspace_root(root, slug)
					_workspace_synced_once = true
					_refresh_current_workspace_details_label()
	_ws_label_refresh_inflight = false

func _set_feedback(message: String) -> void:
	if error_label:
		error_label.text = message

func _format_hub_action_error(action_name: String, err_any: Variant) -> String:
	if typeof(err_any) == TYPE_DICTIONARY:
		var err_dict: Dictionary = err_any
		var status_code: int = int(err_dict.get("status", 0))
		if status_code == 0:
			return "%s failed: Hub is unavailable. Start the Hub first or verify the Hub URL." % action_name
		return "%s failed: Hub returned HTTP %d." % [action_name, status_code]
	var err_text: String = str(err_any).strip_edges()
	if err_text == "busy":
		return "%s is already in progress. Wait a moment and try again." % action_name
	if err_text.is_empty():
		return "%s failed: unknown error." % action_name
	return "%s failed: %s" % [action_name, err_text]

func _on_ui_scale_option_selected(idx: int) -> void:
	var chosen_scale: float = _option_idx_to_ui_scale(idx)
	_apply_ui_scale(chosen_scale)
	var cfg: Dictionary = RuntimeConfig.load_config()
	var display_any: Variant = cfg.get("display", {})
	var display_cfg: Dictionary = display_any if typeof(display_any) == TYPE_DICTIONARY else {}
	display_cfg["ui_scale"] = chosen_scale
	cfg["display"] = display_cfg
	if RuntimeConfig.save_config(cfg):
		_set_feedback("UI scale set to %d %%." % int(round(chosen_scale * 100.0)))
	else:
		_set_feedback("UI scale applied for this session, but could not be saved.")

func _on_export_pressed() -> void:
	_set_feedback("Requesting workspace export from the Hub...")
	if export_button:
		export_button.disabled = true
	var res = await hub.export_workspace_zip()
	if export_button:
		export_button.disabled = false
	if res.ok:
		var zip_url: String = str(res.data.get("zip_url", "")).strip_edges()
		if zip_url.is_empty():
			_set_feedback("Workspace export completed.")
		else:
			_set_feedback("Workspace export created: %s" % zip_url)
	else:
		_set_feedback(_format_hub_action_error("Workspace export", res.error))

func _on_voice_test_pressed() -> void:
	_set_feedback("Testing voice via the Hub. This can take a few seconds.")
	voice_test_button.disabled = true
	var hub_tts_pref := "auto"
	if hub_tts_provider_option:
		match int(hub_tts_provider_option.selected):
			1: hub_tts_pref = "edge_tts"
			2: hub_tts_pref = "sapi"
			3: hub_tts_pref = "sidecar"
			_: hub_tts_pref = "auto"
	var res = await hub.test_voice("Hello from Synesyn.", hub_tts_pref)
	voice_test_button.disabled = false
	if not res.ok:
		_set_feedback(_format_hub_action_error("Voice test", res.error))
		return
	var provider: String = str(res.data.get("provider_used", "?"))
	var audio_url: String = str(res.data.get("audio_url", ""))
	_set_feedback("Voice test succeeded (%s). Attempting playback..." % provider)
	var played := await _try_play_audio_url(audio_url)
	if played:
		_set_feedback("Voice test succeeded (%s)." % provider)
	else:
		_set_feedback("Voice test succeeded (%s), but in-app playback could not start. Check your audio output and Hub artifacts." % provider)

func _try_play_audio_url(audio_url: String) -> bool:
	if audio_url.is_empty():
		return false
	var path := _audio_uri_to_path(audio_url)
	if path.is_empty() or not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if not f:
		return false
	var audio_data := f.get_buffer(f.get_length())
	f.close()
	if audio_data.is_empty():
		return false

	# Detect MP3 by magic bytes (sync word 0xFF 0xEx or ID3 header).
	var is_mp3 := false
	var is_wav := false
	var ext := path.get_extension().to_lower()
	if ext == "mp3":
		is_mp3 = true
	elif ext == "wav":
		is_wav = true
	elif audio_data.size() > 3:
		var b0: int = audio_data[0]; var b1: int = audio_data[1]; var b2: int = audio_data[2]
		is_mp3 = (b0 == 0xFF and (b1 & 0xE0) == 0xE0) or (b0 == 0x49 and b1 == 0x44 and b2 == 0x33)
		is_wav = (b0 == 0x52 and b1 == 0x49 and b2 == 0x46)  # "RIF"

	var stream: AudioStream
	if is_mp3:
		var mp3 := AudioStreamMP3.new()
		mp3.data = audio_data
		stream = mp3
	else:
		# WAV: extract PCM from RIFF container, configure AudioStreamWAV.
		var pcm_data := audio_data
		var sample_rate := 24000
		var bits_per_sample := 16
		var num_channels := 1
		if is_wav and audio_data.size() > 44:
			num_channels = int(audio_data.decode_u16(22))
			sample_rate = int(audio_data.decode_u32(24))
			bits_per_sample = int(audio_data.decode_u16(34))
			var offset := 12
			while offset + 8 < audio_data.size():
				var is_data := audio_data[offset] == 0x64 and audio_data[offset + 1] == 0x61 \
						and audio_data[offset + 2] == 0x74 and audio_data[offset + 3] == 0x61
				var chunk_size: int = audio_data.decode_u32(offset + 4)
				if is_data:
					pcm_data = audio_data.slice(offset + 8, offset + 8 + chunk_size)
					break
				offset += 8 + chunk_size
				if chunk_size % 2 != 0:
					offset += 1
		var wav := AudioStreamWAV.new()
		wav.data = pcm_data
		wav.format = AudioStreamWAV.FORMAT_16_BITS if bits_per_sample == 16 else AudioStreamWAV.FORMAT_8_BITS
		wav.mix_rate = sample_rate
		wav.stereo = (num_channels >= 2)
		stream = wav

	var player: AudioStreamPlayer
	if VoiceService and VoiceService.has_method("get_or_create_audio_player"):
		player = VoiceService.get_or_create_audio_player("Narrator") as AudioStreamPlayer
	if not is_instance_valid(player):
		player = AudioStreamPlayer.new()
		add_child(player)
	player.stream = stream
	player.play()
	await player.finished
	return true

func _audio_uri_to_path(uri: String) -> String:
	var s := uri.strip_edges()
	if s.begins_with("file:///"):
		s = s.substr(8)
	elif s.begins_with("file://"):
		s = s.substr(7)
	# Strip leading "/" from Windows paths like /C:/...
	if s.length() > 2 and s[0] == "/" and s[2] == ":":
		s = s.substr(1)
	return s

func _on_save_providers_pressed() -> void:
	error_label.text = ""

	var mode := "direct"
	if voice_mode_option:
		mode = "hub" if voice_mode_option.selected == 0 else "direct"

	var hub_url := hub_url_edit.text.strip_edges() if hub_url_edit else ""
	var service_url := voice_service_url_edit.text.strip_edges() if voice_service_url_edit else ""
	var hub_tts_pref := "auto"
	if hub_tts_provider_option:
		match int(hub_tts_provider_option.selected):
			1:
				hub_tts_pref = "edge_tts"
			2:
				hub_tts_pref = "sapi"
			3:
				hub_tts_pref = "sidecar"
			_:
				hub_tts_pref = "auto"

	var cfg: Dictionary = RuntimeConfig.load_config()
	cfg["voice"] = {
		"provider_mode": mode,
		"hub_url": hub_url,
		"service_url": service_url,
		"hub_tts_provider_preference": hub_tts_pref,
		"save_recordings": (save_recordings_toggle.button_pressed if save_recordings_toggle else ((cfg.get("voice", {}) as Dictionary).get("save_recordings", false) == true)),
	}
	# Keep hub config aligned while preserving existing hub settings.
	var hub_cfg: Dictionary = cfg.get("hub", {})
	hub_cfg["base_url"] = hub_url
	if hub_path_edit:
		hub_cfg["exec_path"] = hub_path_edit.text.strip_edges()
	cfg["hub"] = hub_cfg

	# Save Metapunkt auth settings (optional)
	var apps_cfg: Dictionary = cfg.get("apps", {})
	var mp_cfg: Dictionary = apps_cfg.get("metapunkt", {})
	var auth_mode := "no-auth"
	if metapunkt_auth_mode_option:
		auth_mode = "auth-required" if metapunkt_auth_mode_option.selected == 1 else "no-auth"
	mp_cfg["auth_mode"] = auth_mode
	if metapunkt_auth_token_edit:
		mp_cfg["auth_token"] = metapunkt_auth_token_edit.text.strip_edges()
	if metapunkt_verify_via_hub_toggle:
		mp_cfg["auth_verify_via_hub"] = (metapunkt_verify_via_hub_toggle.button_pressed == true)
	apps_cfg["metapunkt"] = mp_cfg
	cfg["apps"] = apps_cfg

	# UX hint: avoid surprising "required" mode with no verifier configured.
	if auth_mode == "auth-required":
		var token_empty := (metapunkt_auth_token_edit == null or metapunkt_auth_token_edit.text.strip_edges().is_empty())
		var via_hub := (metapunkt_verify_via_hub_toggle != null and metapunkt_verify_via_hub_toggle.button_pressed)
		if token_empty and not via_hub:
			error_label.text = "Saved, but auth mode is required with no token and verify-via-hub is off. Metapunkt SLOP will reject requests until configured."

	# Display settings
	var chosen_scale := _option_idx_to_ui_scale(ui_scale_option.selected if ui_scale_option else 1)
	var display_cfg: Dictionary = cfg.get("display", {})
	display_cfg["ui_scale"] = chosen_scale
	cfg["display"] = display_cfg

	if not RuntimeConfig.save_config(cfg):
		error_label.text = "Couldn't save settings — check file permissions in %s." % RuntimeConfig.get_config_path_abs()
		return

	# Apply UI scale immediately after saving.
	_apply_ui_scale(chosen_scale)

	# Apply immediately if voice autoload exists.
	if typeof(VoiceService) != TYPE_NIL and VoiceService and VoiceService.has_method("apply_runtime_config"):
		VoiceService.apply_runtime_config(mode, hub_url, service_url, hub_tts_pref)

	# Align HubProcessManager base URL too (used by /status polling and voice test through hub).
	hub.hub_base_url = hub_url

	var saved_exec_path := ""
	if hub_path_edit:
		saved_exec_path = hub_path_edit.text.strip_edges()
	if saved_exec_path.is_empty():
		_set_feedback("Providers saved and applied. UI scale changes take effect now. Hub path will use auto-detect.")
	else:
		_set_feedback("Providers saved and applied. UI scale changes take effect now. Hub path saved: %s" % saved_exec_path)
	_refresh_hub_tts_provider_status(cfg.get("voice", {}))

func _refresh_hub_tts_provider_status(voice_cfg_any: Variant) -> void:
	if not hub_tts_provider_status_label:
		return
	var voice_cfg: Dictionary = voice_cfg_any as Dictionary if typeof(voice_cfg_any) == TYPE_DICTIONARY else {}
	var mode := str(voice_cfg.get("provider_mode", "direct")).strip_edges().to_lower()
	var pref := str(voice_cfg.get("hub_tts_provider_preference", "auto")).strip_edges().to_lower()
	var label_pref := "auto (edge_tts then sapi)"
	if pref in ["edge", "edge_tts", "edgetts"]:
		label_pref = "edge_tts (forced)"
	elif pref in ["sapi", "pyttsx3"]:
		label_pref = "sapi / pyttsx3 (forced)"
	elif pref in ["sidecar", "voice_sidecar"]:
		label_pref = "sidecar (forced)"

	if mode == "hub":
		hub_tts_provider_status_label.text = "Hub TTS provider: " + label_pref
	else:
		hub_tts_provider_status_label.text = "Hub TTS provider: " + label_pref + " (inactive while Voice mode = direct)"

func _on_save_recordings_toggled(enabled: bool) -> void:
	error_label.text = ""

	# Persist to runtime config (Documents/Synesyn/.../synesyn_client.json)
	var cfg: Dictionary = RuntimeConfig.load_config()
	var voice_cfg: Dictionary = cfg.get("voice", {})
	voice_cfg["save_recordings"] = (enabled == true)
	cfg["voice"] = voice_cfg
	if not RuntimeConfig.save_config(cfg):
		error_label.text = "Failed to save consent setting"
		return

	# Apply immediately if voice autoload exists.
	if typeof(VoiceService) != TYPE_NIL and VoiceService and VoiceService.has_method("set_save_recordings_enabled"):
		VoiceService.set_save_recordings_enabled(enabled == true)

	# Consent is only meaningful for hub transcription.
	var mode_is_hub := (voice_mode_option and voice_mode_option.selected == 0)
	if not mode_is_hub:
		error_label.text = "Saved. Consent applies when Voice mode = hub."
		return

	# Ensure HubProcessManager base URL is aligned with the UI.
	var hub_url := hub_url_edit.text.strip_edges() if hub_url_edit else hub.hub_base_url
	if not hub_url.is_empty():
		hub.hub_base_url = hub_url

	var session_id := SynesynSession.get_or_create_session_id("scensyn")
	var res = await hub.set_session_consent_save_recordings(session_id, enabled == true)
	if res.ok:
		error_label.text = "Consent updated for session: %s" % session_id
	else:
		error_label.text = "Consent update failed: %s" % str(res.error)

func _on_publish_character_voices_pressed() -> void:
	error_label.text = ""
	var mode_is_hub := (voice_mode_option and voice_mode_option.selected == 0)
	if not mode_is_hub:
		error_label.text = "Publish requires Voice mode = hub"
		return
	if typeof(VoiceService) == TYPE_NIL or not VoiceService:
		error_label.text = "VoiceService not available"
		return
	if not VoiceService.has_method("save_character_voices_to_file"):
		error_label.text = "VoiceService missing save_character_voices_to_file"
		return
	if not VoiceService.has_method("publish_character_voices_to_substrate"):
		error_label.text = "VoiceService missing publish_character_voices_to_substrate"
		return

	# Ensure file exists and is up to date with current mapping.
	VoiceService.save_character_voices_to_file()
	var res: Dictionary = await VoiceService.publish_character_voices_to_substrate("scensyn")
	if res.get("ok", false) == true:
		error_label.text = "Published: %s" % str(res.get("id", "ok"))
	else:
		error_label.text = "Publish failed: %s" % str(res.get("error", "unknown error"))

func apply_workspace_selection() -> void:
	error_label.text = ""
	var ws_name = ws_name_edit.text.strip_edges()
	var slug = ws_slug_edit.text.strip_edges()
	var root = ws_root_edit.text.strip_edges()
	if ws_name.is_empty():
		error_label.text = "Workspace name is required"
		return
	if slug.is_empty():
		error_label.text = "Workspace slug is required"
		return

	# Optimistically update the "Current workspace" label immediately so UI feedback is instant.
	# We'll reconcile with the hub's select response (and a follow-up GET) afterwards.
	var base_root: String = root
	if base_root.is_empty():
		base_root = str(OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)).path_join("Synesyn").path_join(WorkspaceUtilsScript.DEFAULT_WORKSPACES_DIRNAME)
	var workspace_root: String = base_root.path_join(slug)
	_apply_current_workspace_from_dict({"name": ws_name, "slug": slug, "root": workspace_root})

	# Persist immediately so restart retains the values even if hub sync is slow/flaky.
	var root_to_save: String = root if not root.is_empty() else base_root
	_save_workspace_state(ws_name, slug, root_to_save)

	# Always send a base root to the hub so workspaces don't pollute Documents/Synesyn directly.
	var root_for_hub: String = root if not root.is_empty() else base_root
	var res = await hub.select_workspace(name, slug, root_for_hub)
	if res.ok:
		var ws: Dictionary = WorkspaceUtilsScript.extract_workspace_dict(res.get("data", null))
		error_label.text = "Workspace applied: \"%s\" (slug: %s)" % [name, slug]
		_workspace_user_dirty = false
		# Persist again (idempotent).
		_save_workspace_state(name, slug, root_to_save)
		_desired_ws_loaded = true
		_desired_ws_applied_once = true
		_desired_ws_name = name
		_desired_ws_slug = slug
		_desired_ws_root_base = root_to_save
		# Update UI immediately from the select response (authoritative for what hub applied).
		if not ws.is_empty():
			_apply_current_workspace_from_dict(ws)
		# Kick a short delayed dropdown refresh to catch freshly created folders.
		_refresh_workspace_dropdowns()
		call_deferred("_refresh_workspace_dropdowns")
		# Now that the hub has accepted the change, reload authoritative values and select pickers.
		call_deferred("_ensure_workspace_synced")
	else:
		error_label.text = "Couldn't apply workspace — Hub may be offline. Settings were saved locally and will apply on next Hub start. Details: %s" % str(res.error)
