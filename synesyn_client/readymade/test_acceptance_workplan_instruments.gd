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


func _test_workplan_save_load_and_legacy_migration() -> void:
	print("-- workplan save/load + legacy migration --")

	# Isolate under a temp storage root. Autoloads may already have created
	# WorkplanManager against the default Documents path; re-point and re-run
	# migration after seeding the legacy file.
	var temp_root: String = OS.get_user_data_dir().path_join("_readymade_acceptance_tmp")
	DirAccess.make_dir_recursive_absolute(temp_root)
	var previous_root: String = ""
	var cfg: Dictionary = RuntimeConfig.load_config()
	if typeof(cfg.get("storage", {})) == TYPE_DICTIONARY:
		previous_root = String((cfg["storage"] as Dictionary).get("root_dir", ""))
	if not cfg.has("storage") or typeof(cfg["storage"]) != TYPE_DICTIONARY:
		cfg["storage"] = {}
	(cfg["storage"] as Dictionary)["root_dir"] = temp_root
	RuntimeConfig.save_config(cfg)

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
	if previous_root.strip_edges().is_empty():
		(cfg["storage"] as Dictionary).erase("root_dir")
	else:
		(cfg["storage"] as Dictionary)["root_dir"] = previous_root
	RuntimeConfig.save_config(cfg)
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
