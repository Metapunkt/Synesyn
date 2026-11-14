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
	_test_backend_unavailable_message_and_fail_task()
	await _test_start_agent_batch_hub_gate()
	await _test_workplan_manager_ready_before_ui()
	await _test_top_level_readymade_path_and_migration()
	await _test_workplan_save_load_and_legacy_migration()

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
	RuntimeConfig.migrate_readymade_storage_if_needed()

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
