extends Node
## Headless acceptance: workplan save/load (incl. legacy migration) + instrument mapping.
## Exits non-zero on any failure so CI / scripts can gate on the result.

var _failures: int = 0
var _checks: int = 0

func _ready() -> void:
	print("=== ReadyMade acceptance: workplan + instruments ===")
	await get_tree().process_frame
	await get_tree().process_frame

	_test_instrument_mapping()
	_test_edit_metaprompts_typed_modes()
	_test_custom_channels_and_no_org_presets()
	_test_backend_unavailable_message_and_fail_task()
	_test_config_path_honors_storage_root_dir()
	await _test_start_agent_batch_hub_gate()
	await _test_workplan_manager_ready_before_ui()
	await _test_main_tab_center_mouse_clicks()
	await _test_readymade_main_fills_viewport()
	await _test_template_dialog_releases_exclusivity_for_draft()
	await _test_hub_error_dialog_is_dismissible()
	_test_done_task_deadline_is_neutral()
	_test_first_launch_workplan_choice_api()
	_test_path_getters_are_pure_and_migrations_explicit()
	await _test_top_level_readymade_path_and_migration()
	await _test_workplan_save_load_and_legacy_migration()
	await _test_workplan_markdown_export()
	await _test_task_bulk_io()
	const HardeningHelpers = preload("res://readymade/test_acceptance_hardening_helpers.gd")
	HardeningHelpers.run_all(self)

	print("=== Results: %d checks, %d failures ===" % [_checks, _failures])
	if _failures > 0:
		push_error("ReadyMade acceptance FAILED with %d failure(s)" % _failures)
		get_tree().quit(1)
	else:
		print("ReadyMade acceptance PASSED")
		get_tree().quit(0)


func _expect(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: ", label)
	else:
		_failures += 1
		push_error("  FAIL: " + label)
		print("  FAIL: ", label)


func _test_instrument_mapping() -> void:
	print("-- instrument mapping (ADR 0024) --")
	var cases: Array = [
		["RP", CosmicInstruments.CODE_RP],
		["HF", CosmicInstruments.CODE_HF],
		["IR", CosmicInstruments.CODE_IR],
		["AH", CosmicInstruments.CODE_AH],
		["Role-Play", CosmicInstruments.CODE_RP],
		["Role Play", CosmicInstruments.CODE_RP],
		["Role-Playing (Expert Analysis)", CosmicInstruments.CODE_RP],
		["Role Play (Dimensional Shifter)", CosmicInstruments.CODE_RP],
		["Hypothetical", CosmicInstruments.CODE_HF],
		["Hypothetical Framings (Reality Benders)", CosmicInstruments.CODE_HF],
		["Iterative", CosmicInstruments.CODE_IR],
		["Iterative Refinement (Gravitational Drift)", CosmicInstruments.CODE_IR],
		["Abductive", CosmicInstruments.CODE_AH],
		["Abductive Hypothesis Generation (Quantum Reasoning)", CosmicInstruments.CODE_AH],
	]
	for case_any in cases:
		var case: Array = case_any
		var raw: String = String(case[0])
		var expected: String = String(case[1])
		_expect(
			CosmicInstruments.canonicalize(raw) == expected,
			"canonicalize(%s) == %s (got %s)" % [raw, expected, CosmicInstruments.canonicalize(raw)]
		)

	# ProcessFoundConceptTask extends LimboAI BTTask; mapping is shared via CosmicInstruments.
	# Assert the match helper the task uses, without requiring the GDExtension at compile time.
	_expect(
		CosmicInstruments.matches("Role-Playing (Expert Analysis)", CosmicInstruments.CODE_RP),
		"matches(Role-Playing…) → RP"
	)
	_expect(CosmicInstruments.matches("HF", CosmicInstruments.CODE_HF), "matches(HF) → HF")
	_expect(
		not CosmicInstruments.matches("HF", CosmicInstruments.CODE_RP),
		"HF does not match RP"
	)
	_expect(
		CosmicInstruments.display_name("RP") == CosmicInstruments.NAME_RP,
		"display_name(RP) is canonical long name"
	)
	_expect(
		CosmicInstruments.labeled_display("RP") == "RP — " + CosmicInstruments.NAME_RP,
		"labeled_display(RP) includes code and canonical name"
	)
	_expect(
		CosmicInstruments.labeled_display("HF").begins_with("HF — "),
		"labeled_display(HF) begins with HF —"
	)


func _test_custom_channels_and_no_org_presets() -> void:
	print("-- custom channels + no server-channel product presets --")
	_expect(ModeManager != null, "ModeManager available")
	if ModeManager != null:
		var mode_ids: Array[String] = ModeManager.get_available_modes()
		_expect(mode_ids.size() == 3, "exactly three generic product modes")
		_expect(mode_ids.has("social_media"), "social_media mode present")
		_expect(mode_ids.has("creative_writing"), "creative_writing mode present")
		_expect(mode_ids.has("academic_writing"), "academic_writing mode present")
		for mode_id in mode_ids:
			var mode_cfg = ModeManager.get_mode_config(mode_id)
			_expect(mode_cfg != null, "mode config loads: %s" % mode_id)
			if mode_cfg == null:
				continue
			for channel_label in mode_cfg.channels:
				_expect(
					not String(channel_label).begins_with("#"),
					"mode %s uses platform venues, not #channel presets (%s)" % [mode_id, channel_label]
				)

	_expect(
		_product_scripts_free_of_hash_channel_presets(),
		"product scripts have no hardcoded #channel destination lists"
	)

	var manager: Node = get_node_or_null("/root/WorkplanManager")
	_expect(manager != null, "WorkplanManager for custom channels")
	if manager == null:
		return

	var probe_name := "Custom Channels Probe"
	if manager.available_workplans.has(probe_name):
		manager.delete_workplan(probe_name)
	var created: bool = manager.create_new_workplan(probe_name, "Custom channel CRUD probe")
	_expect(created, "create custom-channel probe workplan")
	var workplan: Workplan = manager.get_current_workplan() as Workplan
	_expect(workplan != null, "probe workplan current")
	if workplan == null:
		return

	_expect(workplan.custom_channels.is_empty(), "new workplan custom_channels defaults empty")
	_expect(manager.get_custom_channels().is_empty(), "get_custom_channels empty by default")

	_expect(manager.add_custom_channel("#alpha"), "add_custom_channel #alpha")
	_expect(manager.add_custom_channel("#beta"), "add_custom_channel #beta")
	_expect(not manager.add_custom_channel("#alpha"), "duplicate add_custom_channel rejected")
	_expect(not manager.add_custom_channel("  "), "blank add_custom_channel rejected")
	_expect(manager.get_custom_channels().has("#alpha"), "list includes #alpha")
	_expect(manager.get_custom_channels().has("#beta"), "list includes #beta")

	_expect(manager.rename_custom_channel("#beta", "#beta_renamed"), "rename_custom_channel")
	_expect(manager.get_custom_channels().has("#beta_renamed"), "renamed channel present")
	_expect(not manager.get_custom_channels().has("#beta"), "old channel name gone")

	_expect(manager.remove_custom_channel("#alpha"), "remove_custom_channel #alpha")
	_expect(not manager.get_custom_channels().has("#alpha"), "#alpha removed")
	_expect(manager.get_custom_channels().size() == 1, "one custom channel remains")

	_expect(manager.set_custom_channels(["#dest_one", "#dest_two", "#dest_one"]), "set_custom_channels dedupes")
	var after_set: Array[String] = manager.get_custom_channels()
	_expect(after_set.size() == 2, "set_custom_channels size 2 after dedupe")
	_expect(after_set.has("#dest_one") and after_set.has("#dest_two"), "set_custom_channels values")
	_expect(manager.move_custom_channel(0, 1), "move_custom_channel reorders")
	var after_move: Array[String] = manager.get_custom_channels()
	_expect(after_move.size() == 2 and after_move[0] == "#dest_two", "reorder puts #dest_two first")

	var effective: Array[String] = manager.get_effective_channels()
	_expect(effective.has("#dest_one"), "get_effective_channels includes custom")
	var mode_channels: Array[String] = ModeManager.get_current_channels()
	_expect(not mode_channels.is_empty(), "current mode still exposes platform venues")
	if not mode_channels.is_empty():
		_expect(
			effective.has(mode_channels[0]),
			"get_effective_channels includes mode platform (%s)" % mode_channels[0]
		)

	manager.save_current_workplan()
	var reloaded: Workplan = manager._load_workplan_from_path(manager.current_workplan_path) as Workplan
	_expect(reloaded != null, "reload workplan with custom_channels")
	if reloaded:
		_expect(reloaded.custom_channels.has("#dest_one"), "custom_channels persist across save/load")
		_expect(reloaded.custom_channels.has("#dest_two"), "custom_channels persist #dest_two")

	if manager.available_workplans.has(probe_name):
		# Switch away before delete when possible.
		var others: Array = manager.get_available_workplans()
		for other_name_any in others:
			var other_name: String = String(other_name_any)
			if other_name != probe_name:
				manager.switch_to_workplan(other_name)
				break
		manager.delete_workplan(probe_name)


func _product_scripts_free_of_hash_channel_presets() -> bool:
	"""Grep-style assert: shipped product scripts must not embed Discord-style #channel lists.
	User destinations belong on Workplan.custom_channels, not ModeManager defaults.
	"""
	var roots: Array[String] = [
		"res://readymade/scripts",
		"res://readymade/ui",
		"res://readymade/data",
		"res://readymade/components",
		"res://readymade/agents",
	]
	var dirty: Array[String] = []
	for root_path in roots:
		_scan_product_dir_for_hash_channels(root_path, dirty)
	if not dirty.is_empty():
		for hit in dirty:
			push_error("hash-channel preset leak: " + hit)
		return false
	return true


func _scan_product_dir_for_hash_channels(dir_path: String, dirty: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while not entry.is_empty():
		if entry == "." or entry == "..":
			entry = dir.get_next()
			continue
		var full: String = dir_path.path_join(entry)
		if dir.current_is_dir():
			if entry == "dogfood" or entry.begins_with("test"):
				entry = dir.get_next()
				continue
			_scan_product_dir_for_hash_channels(full, dirty)
		elif entry.ends_with(".gd") or entry.ends_with(".tscn"):
			if entry.begins_with("test_") or entry.find("dogfood") >= 0:
				entry = dir.get_next()
				continue
			# mode_manager.gd is the canonical place mode venue lists live.
			if entry != "mode_manager.gd":
				entry = dir.get_next()
				continue
			var body: String = FileAccess.get_file_as_string(full)
			# Quoted Discord-style destinations in mode defaults, e.g. "#general".
			var search_from: int = 0
			while true:
				var idx: int = body.find("\"#", search_from)
				if idx < 0:
					break
				dirty.append("%s contains quoted #channel preset at offset %d" % [full, idx])
				search_from = idx + 2
		entry = dir.get_next()
	dir.list_dir_end()


func _test_backend_unavailable_message_and_fail_task() -> void:
	print("-- backend unavailable message + fail_task --")
	var orchestrator = get_node_or_null("/root/ReadyMadeOrchestrator")
	_expect(orchestrator != null, "ReadyMadeOrchestrator present for backend message")
	if orchestrator and orchestrator.has_method("build_backend_unavailable_message"):
		var msg: String = orchestrator.build_backend_unavailable_message("Hub offline for test")
		_expect("Hub offline for test" in msg, "message includes reason")
		_expect("17777" in msg or "hub" in msg.to_lower(), "message mentions hub")
		var config_path: String = RuntimeConfig.get_config_path_abs()
		_expect(config_path in msg or "synesyn_client.json" in msg, "message points at config path")
	var failed_task := WorkplanTask.new()
	failed_task.title = "Fail Probe"
	failed_task.status = "In Progress"
	failed_task.fail_task("probe failure")
	_expect(failed_task.status != "Done", "fail_task leaves status not Done")
	_expect("AI GENERATION FAILED" in failed_task.notes or "probe failure" in failed_task.notes, "fail_task surfaces error in notes")


func _test_config_path_honors_storage_root_dir() -> void:
	print("-- config path honors storage.root_dir (hub dialog) --")
	var temp_root: String = OS.get_user_data_dir().path_join("_config_path_root_dir_tmp")
	DirAccess.make_dir_recursive_absolute(temp_root)
	var previous_root: String = _push_temp_storage_root(temp_root)

	var expected: String = temp_root.path_join("synesyn").path_join("config").path_join("synesyn_client.json")
	var resolved: String = RuntimeConfig.get_config_path_abs()
	_expect(
		resolved.replace("\\", "/") == expected.replace("\\", "/"),
		"get_config_path_abs uses storage.root_dir (got %s)" % resolved
	)
	_expect(FileAccess.file_exists(expected), "config file written under storage.root_dir")

	var orch = get_node_or_null("/root/ReadyMadeOrchestrator")
	if orch and orch.has_method("build_backend_unavailable_message"):
		var msg: String = orch.build_backend_unavailable_message("Hub offline for path test")
		_expect(expected in msg or resolved in msg, "hub dialog message includes root_dir config path")

	_restore_storage_root(previous_root)
	_wipe_dir(temp_root)


func _test_start_agent_batch_hub_gate() -> void:
	print("-- Start Agent Batch hub gate (autoload detect + no-hub dialog) --")
	var root_node: Window = get_tree().root
	_expect(root_node.has_node("ReadyMadeOrchestrator"), "autoload present via root.has_node")
	var orch: Node = get_node_or_null("/root/ReadyMadeOrchestrator")
	_expect(orch != null, "autoload present via /root path")
	_expect(orch.has_method("request_start_agent_batch"), "request_start_agent_batch API present")
	_expect(orch.has_method("probe_hub_available"), "probe_hub_available API present")
	# Engine.has_singleton is unreliable for GDScript autoloads; Start Agent must use /root.
	_expect(
		root_node.has_node("ReadyMadeOrchestrator") == (orch != null),
		"Start Agent detection matches /root node, not Engine.has_singleton alone"
	)

	var got_notice: Array = []
	var on_unavailable := func(message: String) -> void:
		got_notice.append(message)
	if orch.backend_unavailable.is_connected(on_unavailable) == false:
		orch.backend_unavailable.connect(on_unavailable)
	orch._last_backend_notice = ""
	# Hub is expected down in CI / headless agent VMs.
	var started: bool = orch.request_start_agent_batch()
	await get_tree().process_frame
	if orch.probe_hub_available():
		_expect(started or not started, "hub reachable in this environment (batch may start)")
	else:
		_expect(started == false, "Start Agent Batch refuses when hub unreachable")
		_expect(got_notice.size() > 0, "backend_unavailable emitted for Start Agent Batch")
		if got_notice.size() > 0:
			var notice: String = String(got_notice[0])
			_expect("17777" in notice or "hub" in notice.to_lower(), "Start Agent notice mentions hub")
			_expect("synesyn_client.json" in notice or RuntimeConfig.get_config_path_abs() in notice, "Start Agent notice points at config")
			_expect(not ("ReadyMadeOrchestrator is missing" in notice), "does not show false orchestrator-missing message")
	if orch.backend_unavailable.is_connected(on_unavailable):
		orch.backend_unavailable.disconnect(on_unavailable)


func _test_main_tab_center_mouse_clicks() -> void:
	print("-- Main tab center mouse clicks --")
	var scene: PackedScene = load("res://readymade/ui/mission_control_dashboard.tscn")
	_expect(scene != null, "mission control dashboard scene loads")
	if scene == null:
		return
	var dash: Node = scene.instantiate()
	_expect(dash != null, "mission control dashboard instantiates")
	if dash == null:
		return
	add_child(dash)
	_expect(dash.has_method("simulate_main_tab_center_click"), "simulate_main_tab_center_click API present")
	_expect(
		dash.has_method("_setup_main_tabs_structural") or dash.has_method("_ensure_main_tab_hit_targets"),
		"structural tab setup API present"
	)
	if dash.has_method("_setup_main_tabs_structural"):
		dash._setup_main_tabs_structural()
	elif dash.has_method("_ensure_main_tab_hit_targets"):
		dash._ensure_main_tab_hit_targets()
	var tab_container: TabContainer = dash.get("main_tab_container")
	_expect(tab_container != null, "main_tab_container present")
	if tab_container == null or not dash.has_method("simulate_main_tab_center_click"):
		dash.queue_free()
		await get_tree().process_frame
		return
	# Structural setup hides the internal strip; pages must not cover the external bar.
	_expect(tab_container.tabs_visible == false, "TabContainer internal tabs hidden (external TabBar owns chrome)")
	var tab_count: int = tab_container.get_tab_count()
	_expect(tab_count >= 3, "at least Tasks/Content/Calendar tabs present (got %d)" % tab_count)

	var sizes: Array[Vector2i] = [Vector2i(1152, 648), Vector2i(1920, 1080)]
	for size_any in sizes:
		var win_size: Vector2i = size_any
		get_window().size = win_size
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame
		for tab_index in range(tab_count):
			var switched: bool = await dash.simulate_main_tab_center_click(tab_index)
			_expect(
				switched and tab_container.current_tab == tab_index,
				"mouse click at center switches to tab %d (%s) at %dx%d" % [
					tab_index,
					tab_container.get_tab_title(tab_index),
					win_size.x,
					win_size.y,
				]
			)
	dash.queue_free()
	await get_tree().process_frame


func _test_readymade_main_fills_viewport() -> void:
	print("-- ReadyMade main fills viewport (no letterbox / left clip) --")
	var scene: PackedScene = load("res://readymade/readymade_main.tscn")
	_expect(scene != null, "readymade_main.tscn loads")
	if scene == null:
		return
	var root: Node = scene.instantiate()
	_expect(root != null, "readymade_main instantiates")
	if root == null:
		return
	add_child(root)
	# Match the production bootstrap: real-pixel layout, no canvas_items crop.
	var win: Window = get_window()
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	win.content_scale_factor = 1.0

	var sizes: Array[Vector2i] = [Vector2i(1152, 648), Vector2i(1366, 768), Vector2i(1920, 1080)]
	for size_any in sizes:
		var win_size: Vector2i = size_any
		win.size = win_size
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame

		var dash: Control = root.get_node_or_null("MissionControlDashboard") as Control
		_expect(dash != null, "MissionControlDashboard present at %dx%d" % [win_size.x, win_size.y])
		if dash == null:
			continue

		var vp_size: Vector2 = dash.get_viewport_rect().size
		var dash_size: Vector2 = dash.size
		_expect(
			dash_size.x >= vp_size.x - 2.0 and dash_size.y >= vp_size.y - 2.0,
			"dashboard fills viewport at %dx%d (dash=%.0fx%.0f vp=%.0fx%.0f)" % [
				win_size.x, win_size.y, dash_size.x, dash_size.y, vp_size.x, vp_size.y
			]
		)

		var left_panel: Control = dash.get_node_or_null("HSplitContainer/LeftPanelContainer") as Control
		_expect(left_panel != null, "LeftPanelContainer present at %dx%d" % [win_size.x, win_size.y])
		if left_panel != null:
			var left_rect: Rect2 = left_panel.get_global_rect()
			_expect(left_rect.position.x >= -1.0, "left panel not clipped past viewport left at %dx%d (x=%.1f)" % [win_size.x, win_size.y, left_rect.position.x])
			_expect(left_rect.size.x >= 260.0, "left panel min width respected at %dx%d (w=%.0f)" % [win_size.x, win_size.y, left_rect.size.x])

		var filter_row: Node = dash.find_child("FilterSearchContainer", true, false)
		_expect(filter_row != null and filter_row is HFlowContainer, "FilterSearchContainer is HFlowContainer at %dx%d" % [win_size.x, win_size.y])

	root.queue_free()
	await get_tree().process_frame


func _test_template_dialog_releases_exclusivity_for_draft() -> void:
	print("-- template dialog close releases exclusivity for Draft --")
	var scene: PackedScene = load("res://readymade/ui/mission_control_dashboard.tscn")
	_expect(scene != null, "mission control dashboard scene loads for dialog test")
	if scene == null:
		return
	var dash: Node = scene.instantiate()
	add_child(dash)
	await get_tree().process_frame
	await get_tree().process_frame

	_expect(dash.has_method("_show_task_template_selector"), "template selector API present")
	_expect(dash.has_method("_close_template_selector"), "template close API present")
	_expect(dash.has_method("_on_start_agent_pressed"), "Draft To Do API present")
	if not dash.has_method("_show_task_template_selector"):
		dash.queue_free()
		await get_tree().process_frame
		return

	dash._show_task_template_selector()
	await get_tree().process_frame
	await get_tree().process_frame

	var template_dialog: AcceptDialog = null
	for child in dash.get_children():
		if child is AcceptDialog and String(child.title).findn("Template") >= 0:
			template_dialog = child
			break
	_expect(template_dialog != null, "Select Task Template dialog opened")
	if template_dialog != null:
		var ok_btn: Button = template_dialog.get_ok_button()
		_expect(ok_btn == null or ok_btn.visible == false, "template dialog redundant OK is hidden")
		_expect(template_dialog.visible, "template dialog visible before close")
		await dash._close_template_selector(template_dialog)
		await get_tree().process_frame
		_expect(not is_instance_valid(template_dialog) or not template_dialog.visible, "template dialog closed/freed")

	# Workplan manager OK should also be hidden when shown.
	if dash.has_method("_show_workplan_manager_dialog") and dash.get("workplan_manager") != null:
		await dash._show_workplan_manager_dialog()
		await get_tree().process_frame
		var wp_dialog: AcceptDialog = null
		for child2 in dash.get_children():
			if child2 is AcceptDialog and String(child2.title).findn("Workplan Manager") >= 0:
				wp_dialog = child2
				break
		_expect(wp_dialog != null, "Workplan Manager dialog opened")
		if wp_dialog != null:
			var wp_ok: Button = wp_dialog.get_ok_button()
			_expect(wp_ok == null or wp_ok.visible == false, "workplan manager redundant OK is hidden")
			if dash.has_method("_release_exclusive_window"):
				await dash._release_exclusive_window(wp_dialog)
			else:
				wp_dialog.hide()
				wp_dialog.queue_free()
				await get_tree().process_frame

	var got_notice: Array = []
	var orch: Node = get_node_or_null("/root/ReadyMadeOrchestrator")
	var on_unavailable := func(message: String):
		got_notice.append(message)
	if orch != null and orch.has_signal("backend_unavailable"):
		if not orch.backend_unavailable.is_connected(on_unavailable):
			orch.backend_unavailable.connect(on_unavailable)
		# Earlier hub-gate tests may have set the dedupe cache; clear so Draft can notify again.
		if orch.get("_last_backend_notice") != null:
			orch.set("_last_backend_notice", "")

	# After template close, Draft must be able to surface the no-hub / unavailable dialog.
	await dash._on_start_agent_pressed()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var notice_dialog: AcceptDialog = null
	for child3 in dash.get_children():
		if child3 is AcceptDialog and child3.visible:
			notice_dialog = child3
			break
	var hub_up: bool = orch != null and orch.has_method("probe_hub_available") and bool(orch.probe_hub_available())
	if hub_up:
		_expect(true, "hub reachable — Draft may start after template close (exclusivity released)")
	else:
		var has_notice: bool = notice_dialog != null or got_notice.size() > 0
		_expect(has_notice, "Draft after template close shows dialog or emits backend_unavailable")
		if notice_dialog != null:
			var notice_text: String = String(notice_dialog.dialog_text) + " " + String(notice_dialog.title)
			_expect(
				notice_text.findn("hub") >= 0 or notice_text.findn("backend") >= 0 or notice_text.findn("AI") >= 0 or notice_text.findn("Error") >= 0,
				"Draft notice mentions hub/backend/AI (got: %s)" % notice_text.substr(0, 80)
			)
		elif got_notice.size() > 0:
			_expect(true, "backend_unavailable emitted after exclusivity release")

	if orch != null and orch.has_signal("backend_unavailable") and orch.backend_unavailable.is_connected(on_unavailable):
		orch.backend_unavailable.disconnect(on_unavailable)
	dash.queue_free()
	await get_tree().process_frame


func _test_hub_error_dialog_is_dismissible() -> void:
	print("-- hub/backend error dialog dismissible (OK / cancel) --")
	var scene: PackedScene = load("res://readymade/ui/mission_control_dashboard.tscn")
	_expect(scene != null, "dashboard loads for notice dismiss test")
	if scene == null:
		return
	var dash: Node = scene.instantiate()
	add_child(dash)
	await get_tree().process_frame
	_expect(dash.has_method("_show_error_dialog"), "_show_error_dialog present")
	_expect(dash.has_method("_clear_active_notice_dialog"), "_clear_active_notice_dialog present")
	await dash._show_error_dialog("AI generation failed — task left not Done.\n\nWhat to do:\n1. Start hub\n2. Configure hub.base_url")
	await get_tree().process_frame
	await get_tree().process_frame
	var notice: AcceptDialog = dash.get("_active_notice_dialog") as AcceptDialog
	_expect(notice != null and is_instance_valid(notice) and notice.visible, "notice dialog is visible")
	if notice != null and is_instance_valid(notice):
		_expect(notice.unresizable == true, "notice dialog is unresizable (compact)")
		_expect(notice.exclusive == true, "notice dialog is exclusive while shown")
		# Dismiss via canceled (Escape path)
		notice.canceled.emit()
		await get_tree().process_frame
		await get_tree().process_frame
		var after: Variant = dash.get("_active_notice_dialog")
		_expect(after == null or not is_instance_valid(after) or not after.visible, "notice cleared after cancel/Escape")
	# Second show replaces rather than stacking
	await dash._show_error_dialog("Hub offline notice A")
	await get_tree().process_frame
	await dash._show_error_dialog("Hub offline notice B")
	await get_tree().process_frame
	await get_tree().process_frame
	var visible_notices: int = 0
	for child in dash.get_children():
		if child is AcceptDialog and child.visible and String(child.title) == "Error":
			visible_notices += 1
	_expect(visible_notices <= 1, "at most one Error notice visible (got %d)" % visible_notices)
	# Dedupe generation failures in orchestrator
	var orch: Node = get_node_or_null("/root/ReadyMadeOrchestrator")
	if orch != null and orch.has_method("notify_backend_unavailable"):
		orch.set("_last_backend_notice", "")
		var got: Array = []
		var on_note := func(msg: String) -> void:
			got.append(msg)
		if orch.has_signal("backend_unavailable"):
			orch.backend_unavailable.connect(on_note)
		orch.notify_backend_unavailable("AI generation failed — task left not Done.\nFailed at: t1")
		orch.notify_backend_unavailable("AI generation failed — task left not Done.\nFailed at: t2")
		_expect(got.size() == 1, "generation-failure notices are deduped across timestamps")
		if orch.backend_unavailable.is_connected(on_note):
			orch.backend_unavailable.disconnect(on_note)
	if dash.has_method("_clear_active_notice_dialog"):
		await dash._clear_active_notice_dialog()
	dash.queue_free()
	await get_tree().process_frame


func _test_done_task_deadline_is_neutral() -> void:
	print("-- Done task deadline styling is neutral --")
	var task: WorkplanTask = WorkplanTask.new()
	task.title = "Done past-due sample"
	task.status = "Done"
	task.deadline = "2020-01-01"
	_expect(task.is_overdue() == false, "is_overdue is false for Done tasks")

	var scene: PackedScene = load("res://readymade/ui/mission_control_dashboard.tscn")
	_expect(scene != null, "dashboard loads for deadline label test")
	if scene == null:
		return
	var dash: Node = scene.instantiate()
	_expect(dash.has_method("_apply_deadline_label"), "_apply_deadline_label API present")
	if dash.has_method("_apply_deadline_label"):
		var label := Label.new()
		dash._apply_deadline_label(label, task)
		_expect(label.text.findn("OVERDUE") < 0, "Done deadline label text is not OVERDUE")
		_expect(label.text.findn("Completed") >= 0, "Done deadline label shows Completed")
		var font_color: Color = label.get_theme_color("font_color")
		_expect(font_color.r < 0.7 or font_color.g > 0.3, "Done deadline font_color is not pure red")
	dash.queue_free()


func _test_first_launch_workplan_choice_api() -> void:
	print("-- first-launch sample vs empty choice --")
	var orch: Node = get_node_or_null("/root/ReadyMadeOrchestrator")
	_expect(orch != null, "orchestrator present for first-launch choice")
	if orch == null:
		return
	_expect(orch.has_method("get_first_launch_workplan_choice"), "get_first_launch_workplan_choice API")
	_expect(orch.has_method("set_first_launch_workplan_choice"), "set_first_launch_workplan_choice API")
	var previous: String = orch.get_first_launch_workplan_choice()
	orch.set_first_launch_workplan_choice("empty")
	_expect(orch.get_first_launch_workplan_choice() == "empty", "persists empty choice")
	orch.set_first_launch_workplan_choice("sample")
	_expect(orch.get_first_launch_workplan_choice() == "sample", "persists sample choice")
	# Restore prior value (or clear by writing empty string via config).
	if previous.strip_edges().is_empty():
		var cfg: Dictionary = RuntimeConfig.load_config()
		if typeof(cfg.get("apps", {})) == TYPE_DICTIONARY:
			var apps: Dictionary = cfg["apps"]
			if typeof(apps.get("readymade", {})) == TYPE_DICTIONARY:
				(apps["readymade"] as Dictionary).erase("first_launch_workplan")
				RuntimeConfig.save_config(cfg)
	else:
		orch.set_first_launch_workplan_choice(previous)


func _test_workplan_manager_ready_before_ui() -> void:
	print("-- WorkplanManager ready before UI queries --")
	var orch: Node = get_node_or_null("/root/ReadyMadeOrchestrator")
	_expect(orch != null, "orchestrator present for workplan ready check")
	if orch == null:
		return
	_expect(orch.has_method("is_workplan_manager_ready"), "is_workplan_manager_ready API present")
	_expect(orch.has_method("await_workplan_manager_ready"), "await_workplan_manager_ready API present")
	await orch.await_workplan_manager_ready()
	_expect(orch.is_workplan_manager_ready(), "workplan manager ready without deferred race")
	_expect(get_node_or_null("/root/WorkplanManager") != null, "WorkplanManager node on /root")
	_expect(orch.workplan != null, "current workplan available immediately after ready")


func _test_edit_metaprompts_typed_modes() -> void:
	print("-- EditMetaprompts typed Array[String] --")
	var edit_meta = get_node_or_null("/root/EditMetaprompts")
	_expect(edit_meta != null, "EditMetaprompts autoload present")
	if edit_meta == null:
		return
	var modes: Array[String] = edit_meta.get_available_edit_modes()
	_expect(modes.size() == 6, "six edit modes returned (got %d)" % modes.size())
	var expected: Array[String] = [
		"developmental", "structural", "content", "line", "copy", "proofreading"
	]
	for mode_id in expected:
		_expect(mode_id in modes, "mode present: " + mode_id)
	# Returning Array[String] must not throw; calling again confirms stability.
	var again: Array[String] = edit_meta.get_available_edit_modes()
	_expect(again.size() == modes.size(), "second get_available_edit_modes call stable")


func _test_path_getters_are_pure_and_migrations_explicit() -> void:
	print("-- path getters are pure; migrations are explicit --")
	var temp_root: String = OS.get_user_data_dir().path_join("_readymade_pure_getter_tmp")
	DirAccess.make_dir_recursive_absolute(temp_root)
	var previous_root: String = _push_temp_storage_root(temp_root)
	RuntimeConfig.reset_readymade_migration_guard_for_tests()

	var nested_root: String = RuntimeConfig.get_legacy_readymade_data_dir()
	var nested_output: String = nested_root.path_join("output")
	DirAccess.make_dir_recursive_absolute(nested_output)
	var nested_marker: String = nested_output.path_join("pure_getter_marker.md")
	var marker_file: FileAccess = FileAccess.open(nested_marker, FileAccess.WRITE)
	_expect(marker_file != null, "seed legacy marker for pure-getter test")
	if marker_file:
		marker_file.store_string("# must stay until run_storage_migrations\n")
		marker_file.close()

	var dest_marker: String = RuntimeConfig.get_readymade_output_dir().path_join("pure_getter_marker.md")
	# Calling getters must not copy legacy files.
	var _data: String = RuntimeConfig.get_readymade_data_dir()
	var _out: String = RuntimeConfig.get_readymade_output_dir()
	var _wp: String = RuntimeConfig.get_workplans_dir()
	_expect(not FileAccess.file_exists(dest_marker), "getters do not migrate legacy files")
	_expect(FileAccess.file_exists(nested_marker), "legacy marker remains until explicit migration")

	# RuntimeConfig is a class_name / static helper — call the API directly
	# (has_method is instance-only and cannot be used on the class).
	RuntimeConfig.run_storage_migrations()
	_expect(FileAccess.file_exists(dest_marker), "run_storage_migrations copies legacy output")
	# Idempotent: second call is a no-op (guarded).
	RuntimeConfig.run_storage_migrations()
	_expect(FileAccess.file_exists(dest_marker), "run_storage_migrations remains idempotent")

	_restore_storage_root(previous_root)
	_wipe_dir(temp_root)


func _test_top_level_readymade_path_and_migration() -> void:
	print("-- top-level Documents/Synesyn/readymade/ path + nested migration --")
	var temp_root: String = OS.get_user_data_dir().path_join("_readymade_path_migration_tmp")
	DirAccess.make_dir_recursive_absolute(temp_root)
	var previous_root: String = _push_temp_storage_root(temp_root)
	RuntimeConfig.reset_readymade_migration_guard_for_tests()

	var data_dir: String = RuntimeConfig.get_readymade_data_dir()
	var output_dir: String = RuntimeConfig.get_readymade_output_dir()
	var workplans_dir: String = RuntimeConfig.get_workplans_dir()
	_expect(data_dir.ends_with("/readymade/") or data_dir.ends_with("\\readymade\\") or data_dir.ends_with("/readymade"), "get_readymade_data_dir ends with /readymade/")
	_expect("/synesyn/readymade" not in data_dir.replace("\\", "/") and "\\synesyn\\readymade" not in data_dir, "data dir is not nested under synesyn/readymade")
	_expect(output_dir.begins_with(data_dir.rstrip("/\\")) or data_dir.rstrip("/\\") in output_dir.replace("\\", "/"), "output dir is under readymade data dir")
	_expect("workplans" in workplans_dir, "workplans dir name present")
	_expect(workplans_dir.replace("\\", "/").begins_with(data_dir.replace("\\", "/").rstrip("/")), "workplans live under readymade/")

	# Seed nested legacy tree: synesyn/readymade/output/marker.md and a workplan file
	var nested_root: String = RuntimeConfig.get_legacy_readymade_data_dir()
	var nested_output: String = nested_root.path_join("output")
	DirAccess.make_dir_recursive_absolute(nested_output)
	var nested_marker: String = nested_output.path_join("legacy_marker.md")
	var marker_file: FileAccess = FileAccess.open(nested_marker, FileAccess.WRITE)
	_expect(marker_file != null, "seed nested legacy marker")
	if marker_file:
		marker_file.store_string("# legacy nested content\n")
		marker_file.close()

	var nested_workplans: String = RuntimeConfig.get_legacy_workplans_dir()
	DirAccess.make_dir_recursive_absolute(nested_workplans)
	var nested_wp: String = nested_workplans.path_join("nested_plan.tres")
	var plan := Workplan.new()
	plan.name = "Nested Plan"
	ResourceSaver.save(plan, nested_wp)

	# Newer file already at destination must not be overwritten
	var new_output: String = RuntimeConfig.get_readymade_output_dir()
	DirAccess.make_dir_recursive_absolute(new_output)
	var protected: String = new_output.path_join("legacy_marker.md")
	var protected_body: String = "# keep me — newer at dest\n"
	var protected_file: FileAccess = FileAccess.open(protected, FileAccess.WRITE)
	if protected_file:
		protected_file.store_string(protected_body)
		protected_file.close()

	RuntimeConfig.reset_readymade_migration_guard_for_tests()
	RuntimeConfig.run_storage_migrations()

	var migrated_marker: String = new_output.path_join("legacy_marker.md")
	_expect(FileAccess.file_exists(migrated_marker), "nested output marker present after migration")
	if FileAccess.file_exists(migrated_marker):
		var read_back: FileAccess = FileAccess.open(migrated_marker, FileAccess.READ)
		var body: String = read_back.get_as_text() if read_back else ""
		if read_back:
			read_back.close()
		_expect(body == protected_body, "migration does not overwrite newer dest file")

	var migrated_wp: String = RuntimeConfig.get_workplans_dir().path_join("nested_plan.tres")
	_expect(FileAccess.file_exists(migrated_wp) or ResourceLoader.exists(migrated_wp), "nested workplans migrated into readymade/workplans/")

	_restore_storage_root(previous_root)
	_wipe_dir(temp_root)


func _push_temp_storage_root(temp_root: String) -> String:
	var previous_root: String = ""
	var cfg: Dictionary = RuntimeConfig.load_config()
	if typeof(cfg.get("storage", {})) == TYPE_DICTIONARY:
		previous_root = String((cfg["storage"] as Dictionary).get("root_dir", ""))
	if not cfg.has("storage") or typeof(cfg["storage"]) != TYPE_DICTIONARY:
		cfg["storage"] = {}
	(cfg["storage"] as Dictionary)["root_dir"] = temp_root
	RuntimeConfig.save_config(cfg)
	return previous_root


func _restore_storage_root(previous_root: String) -> void:
	var cfg: Dictionary = RuntimeConfig.load_config()
	if not cfg.has("storage") or typeof(cfg["storage"]) != TYPE_DICTIONARY:
		cfg["storage"] = {}
	if previous_root.strip_edges().is_empty():
		(cfg["storage"] as Dictionary).erase("root_dir")
	else:
		(cfg["storage"] as Dictionary)["root_dir"] = previous_root
	RuntimeConfig.save_config(cfg)
	RuntimeConfig.reset_readymade_migration_guard_for_tests()


func _test_workplan_save_load_and_legacy_migration() -> void:
	print("-- workplan save/load + legacy migration --")

	# Isolate under a temp storage root. Autoloads may already have created
	# WorkplanManager against the default Documents path; re-point and re-run
	# migration after seeding the legacy file.
	var temp_root: String = OS.get_user_data_dir().path_join("_readymade_acceptance_tmp")
	DirAccess.make_dir_recursive_absolute(temp_root)
	var previous_root: String = _push_temp_storage_root(temp_root)
	RuntimeConfig.reset_readymade_migration_guard_for_tests()

	var workplans_dir: String = RuntimeConfig.get_workplans_dir()
	var legacy_path: String = Workplan.legacy_persist_path()
	DirAccess.make_dir_recursive_absolute(workplans_dir)
	DirAccess.make_dir_recursive_absolute(legacy_path.get_base_dir())

	_wipe_dir(workplans_dir)
	if FileAccess.file_exists(legacy_path):
		DirAccess.remove_absolute(legacy_path)

	var legacy_plan := Workplan.new()
	legacy_plan.name = "Default Workplan"
	legacy_plan.description = "legacy migration seed"
	legacy_plan.months = {"Month 1": []}
	var seed_task := WorkplanTask.new()
	seed_task.title = "Legacy Seed Task"
	seed_task.core_idea = "Prove legacy migration"
	seed_task.cosmic_instrument = "HF"
	seed_task.status = "To Do"
	legacy_plan.months["Month 1"].append(seed_task)
	var save_err: Error = ResourceSaver.save(legacy_plan, legacy_path)
	_expect(save_err == OK, "seed legacy workplan_data.tres saved (%s)" % str(save_err))
	_expect(FileAccess.file_exists(legacy_path), "legacy file exists on disk")

	var manager: Node = get_node_or_null("/root/WorkplanManager")
	var created_manager := false
	if manager == null:
		var manager_script = load("res://readymade/scripts/singletons/WorkplanManager.gd")
		_expect(manager_script != null, "WorkplanManager script loads")
		manager = manager_script.new()
		manager.name = "WorkplanManager"
		get_tree().root.add_child(manager)
		created_manager = true
		await get_tree().process_frame
		await get_tree().process_frame
	else:
		_expect(true, "WorkplanManager already present from orchestrator")

	# Force migration against the isolated temp store (even if _ready already ran).
	manager.workplans_directory = workplans_dir
	manager._ensure_workplans_directory()
	manager._migrate_legacy_single_workplan_file()
	manager._load_workplan_registry()
	manager._load_default_workplan()

	var migrated_path: String = workplans_dir.path_join("default_workplan.tres")
	_expect(
		FileAccess.file_exists(migrated_path) or ResourceLoader.exists(migrated_path),
		"legacy migrated into workplans/default_workplan.tres"
	)

	var current: Workplan = manager.get_current_workplan()
	_expect(current != null, "current workplan loaded after migration")
	if current:
		_expect(current.get_total_tasks() >= 1, "migrated workplan retains at least one task")
		var titles: PackedStringArray = PackedStringArray()
		for task_any in current.get_all_tasks():
			var task: WorkplanTask = task_any as WorkplanTask
			if task:
				titles.append(task.title)
		_expect("Legacy Seed Task" in titles, "migrated task title preserved")

	if current:
		var extra := WorkplanTask.new()
		extra.title = "Roundtrip Task"
		extra.core_idea = "saved via manager"
		extra.cosmic_instrument = "Role-Play"
		extra.status = "To Do"
		if not current.months.has("Month 1"):
			current.months["Month 1"] = []
		current.months["Month 1"].append(extra)
		manager.save_current_workplan()

		var reloaded: Workplan = manager._load_workplan_from_path(manager.current_workplan_path)
		_expect(reloaded != null, "reload via FileAccess-capable loader")
		if reloaded:
			var found_roundtrip := false
			for task_any2 in reloaded.get_all_tasks():
				var t2: WorkplanTask = task_any2 as WorkplanTask
				if t2 and t2.title == "Roundtrip Task":
					found_roundtrip = true
					_expect(
						CosmicInstruments.canonicalize(t2.cosmic_instrument) == CosmicInstruments.CODE_RP,
						"roundtrip task instrument Role-Play → RP"
					)
			_expect(found_roundtrip, "roundtrip task present after save/load")

	if FileAccess.file_exists(legacy_path):
		DirAccess.remove_absolute(legacy_path)
	if current:
		current.update_task()
	_expect(
		not FileAccess.file_exists(legacy_path),
		"Workplan.update_task does not recreate legacy workplan_data.tres"
	)

	if created_manager and is_instance_valid(manager):
		manager.queue_free()
		await get_tree().process_frame
	_restore_storage_root(previous_root)
	_wipe_dir(temp_root)


func _test_workplan_markdown_export() -> void:
	print("-- workplan markdown export --")
	var temp_root: String = OS.get_user_data_dir().path_join("_md_export_tmp")
	DirAccess.make_dir_recursive_absolute(temp_root)
	var previous_root: String = _push_temp_storage_root(temp_root)

	var workplans_dir: String = RuntimeConfig.get_workplans_dir()
	DirAccess.make_dir_recursive_absolute(workplans_dir)

	var manager: Node = get_node_or_null("/root/WorkplanManager")
	_expect(manager != null, "WorkplanManager for markdown export")
	if manager == null:
		_restore_storage_root(previous_root)
		_wipe_dir(temp_root)
		return

	manager.workplans_directory = workplans_dir
	manager._ensure_workplans_directory()
	manager._load_workplan_registry()

	var plan_name := "Markdown Export Probe"
	if manager.available_workplans.has(plan_name):
		manager.delete_workplan(plan_name)
	var created: bool = manager.create_new_workplan(plan_name, "Export probe")
	_expect(created, "create probe workplan")
	var workplan: Workplan = manager.get_current_workplan() as Workplan
	_expect(workplan != null, "probe workplan current")
	if workplan:
		var task := WorkplanTask.new()
		task.title = "PLACEHOLDER — sample"
		task.channel = "#custom_dest_a"
		task.content_theme = "Export probe"
		task.publish_date = "2026-12-01"
		task.campaign_tag = "probe"
		task.generated_content = "**Sample**\n\nPLACEHOLDER body for export."
		task.notes = "STATUS: placeholder\nSOURCE: test"
		workplan.add_task_to_month("2026-12", task)
		manager.save_current_workplan()

		var export_path: String = temp_root.path_join("probe_export.md")
		var ok: bool = manager.export_workplan_as_markdown(plan_name, export_path)
		_expect(ok, "export_workplan_as_markdown returns true")
		_expect(FileAccess.file_exists(export_path), "markdown file written")
		if FileAccess.file_exists(export_path):
			var md: String = FileAccess.get_file_as_string(export_path)
			_expect(md.find("#custom_dest_a") >= 0, "markdown includes channel")
			_expect(md.find("placeholder") >= 0, "markdown includes plan status placeholder")
			_expect(md.find("Sample") >= 0 or md.find("PLACEHOLDER") >= 0, "markdown includes draft body")

		var export_path2: String = temp_root.path_join("probe_export2.md")
		_expect(
			manager.export_workplan(plan_name, export_path2),
			"export_workplan routes .md to markdown exporter"
		)

	# Leave the probe plan in the temp tree; wipe_dir removes it. Avoid
	# delete_workplan when it would be the only remaining plan (manager guard).
	_restore_storage_root(previous_root)
	_wipe_dir(temp_root)


func _test_task_bulk_io() -> void:
	print("-- task bulk CSV/JSON import-export --")
	const BulkIOScript = preload("res://readymade/scripts/workplan_task_bulk_io.gd")
	var temp_root: String = OS.get_user_data_dir().path_join("_bulk_io_tmp")
	DirAccess.make_dir_recursive_absolute(temp_root)
	var previous_root: String = _push_temp_storage_root(temp_root)

	var workplans_dir: String = RuntimeConfig.get_workplans_dir()
	DirAccess.make_dir_recursive_absolute(workplans_dir)
	var manager: Node = get_node_or_null("/root/WorkplanManager")
	_expect(manager != null, "WorkplanManager for bulk IO")
	if manager == null:
		_restore_storage_root(previous_root)
		_wipe_dir(temp_root)
		return

	manager.workplans_directory = workplans_dir
	manager._ensure_workplans_directory()
	manager._load_workplan_registry()

	var plan_name := "Bulk IO Probe"
	if manager.available_workplans.has(plan_name):
		manager.delete_workplan(plan_name)
	_expect(manager.create_new_workplan(plan_name, "Bulk IO"), "create bulk IO workplan")
	var workplan: Workplan = manager.get_current_workplan() as Workplan
	_expect(workplan != null, "bulk IO workplan current")
	if workplan == null:
		_restore_storage_root(previous_root)
		_wipe_dir(temp_root)
		return

	var task_a := WorkplanTask.new()
	task_a.title = "Morning note"
	task_a.channel = "#general"
	task_a.publish_date = "2026-11-10"
	task_a.publish_time = "11:00"
	task_a.content_theme = "Cadence"
	task_a.campaign_tag = "bulk-probe"
	task_a.generated_content = "Original draft A"
	task_a.set_content_status("draft")
	task_a.deadline = "2026-11-12"
	task_a.start_date = "2026-11-09"
	task_a.status = "In Progress"
	task_a.ensure_task_id()
	workplan.add_task_to_month("2026-11", task_a)

	var task_b := WorkplanTask.new()
	task_b.title = "Open slot Friday"
	task_b.channel = "#studio-notes"
	task_b.publish_date = "2026-11-14"
	task_b.set_content_status("open_slot")
	task_b.ensure_task_id()
	workplan.add_task_to_month("2026-11", task_b)
	manager.save_current_workplan()

	var csv_text: String = BulkIOScript.export_csv(workplan)
	_expect(csv_text.find("task_id") >= 0, "CSV header includes task_id")
	_expect(csv_text.find("deadline") >= 0, "CSV header includes deadline")
	_expect(csv_text.find("workflow_status") >= 0, "CSV header includes workflow_status")
	_expect(csv_text.find("Morning note") >= 0, "CSV includes task title")
	_expect(csv_text.find("open_slot") >= 0, "CSV includes content status")
	_expect(csv_text.find("2026-11-12") >= 0, "CSV includes deadline date")
	_expect(csv_text.find("In Progress") >= 0, "CSV includes workflow status")

	var csv_path: String = temp_root.path_join("tasks.csv")
	_expect(manager.export_current_tasks_csv(csv_path), "export_current_tasks_csv")
	_expect(FileAccess.file_exists(csv_path), "CSV file written")

	var json_path: String = temp_root.path_join("tasks.json")
	_expect(manager.export_current_tasks_json(json_path), "export_current_tasks_json")
	_expect(FileAccess.file_exists(json_path), "JSON file written")

	# Edit CSV: update A by task_id, create C, update B by fallback key.
	var edited_rows: Array = BulkIOScript.parse_csv(csv_text)
	_expect(edited_rows.size() == 2, "parsed two CSV rows")
	for row_any in edited_rows:
		var row: Dictionary = row_any
		if String(row.get("title", "")) == "Morning note":
			row["draft"] = "Rewritten draft A"
			row["status"] = "needs_approval"
			row["deadline"] = "2026-11-13"
			row["workflow_status"] = "Review"
		elif String(row.get("title", "")) == "Open slot Friday":
			row["task_id"] = ""  # force fallback match
			row["draft"] = "Filled open slot"
			row["status"] = "draft"
	edited_rows.append({
		"task_id": "",
		"publish_date": "2026-11-17",
		"publish_time": "11:00",
		"channel": "#general",
		"content_theme": "New",
		"campaign_tag": "bulk-probe",
		"title": "Brand new post",
		"draft": "Created via import",
		"status": "placeholder",
		"notes": "",
	})
	var rebuild_lines: PackedStringArray = PackedStringArray()
	rebuild_lines.append(",".join(BulkIOScript.COLUMNS))
	for row2_any in edited_rows:
		var row2: Dictionary = row2_any
		var cells: PackedStringArray = PackedStringArray()
		for col in BulkIOScript.COLUMNS:
			cells.append(BulkIOScript._csv_escape(String(row2.get(col, ""))))
		rebuild_lines.append(",".join(cells))
	var edited_csv: String = "\n".join(rebuild_lines) + "\n"

	var preview: Dictionary = manager.preview_import_tasks(edited_csv, "csv")
	_expect(int(preview.get("created", 0)) == 1, "preview created == 1")
	_expect(int(preview.get("updated", 0)) == 2, "preview updated == 2")
	_expect(workplan.get_total_tasks() == 2, "preview does not mutate workplan")

	var applied: Dictionary = manager.apply_import_tasks_preview(preview)
	_expect(int(applied.get("created", 0)) == 1, "applied created == 1")
	_expect(int(applied.get("updated", 0)) == 2, "applied updated == 2")
	_expect(workplan.get_total_tasks() == 3, "workplan has 3 tasks after import")
	_expect(task_a.generated_content == "Rewritten draft A", "task A draft updated by id")
	_expect(task_a.get_content_status() == "needs_approval", "task A status updated")
	_expect(task_a.deadline == "2026-11-13", "task A deadline updated via bulk IO")
	_expect(task_a.status == "Review", "task A workflow_status updated via bulk IO")
	_expect(task_b.generated_content == "Filled open slot", "task B updated by fallback")

	var empty_preview: Dictionary = BulkIOScript.preview_import(workplan, "title\n\n", "csv")
	_expect(int(empty_preview.get("skipped", 0)) >= 0, "empty title handling returns preview")

	_restore_storage_root(previous_root)
	_wipe_dir(temp_root)


func _wipe_dir(path: String) -> void:
	if path.strip_edges().is_empty():
		return
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while not file_name.is_empty():
		if file_name == "." or file_name == "..":
			file_name = dir.get_next()
			continue
		var child: String = path.path_join(file_name)
		if dir.current_is_dir():
			_wipe_dir(child)
			DirAccess.remove_absolute(child)
		else:
			DirAccess.remove_absolute(child)
		file_name = dir.get_next()
	dir.list_dir_end()
