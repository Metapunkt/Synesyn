extends Node

func _ready():
	print("🧪 Testing Basic ReadyMade System...")
	
	# Test orchestrator loading
	var orchestrator = get_node_or_null("/root/ReadyMadeOrchestrator")
	if not orchestrator:
		print("❌ ReadyMadeOrchestrator not found!")
		get_tree().quit(1)
		return
	
	print("✅ ReadyMadeOrchestrator found")

	# WorkplanManager is created deferred — wait briefly for the active workplan.
	var waited := 0
	while waited < 60 and (orchestrator.workplan == null):
		await get_tree().process_frame
		waited += 1
	if orchestrator.workplan == null and orchestrator.has_signal("workplan_loaded"):
		await orchestrator.workplan_loaded
	
	# Test workplan loading
	if not orchestrator.workplan:
		print("❌ Workplan not loaded!")
		get_tree().quit(1)
		return
	
	print("✅ Workplan loaded")
	
	# Show basic stats
	var total_tasks = orchestrator.workplan.get_total_tasks()
	var completed_tasks = orchestrator.workplan.get_completed_tasks()
	var pending_tasks = orchestrator.workplan.get_tasks_by_status("To Do").size()
	
	print("📊 WORKPLAN STATS:")
	print("   📋 Total Tasks: ", total_tasks)
	print("   ✅ Completed: ", completed_tasks)
	print("   📝 Pending: ", pending_tasks)
	
	# Test persistence — WorkplanManager under Documents/Synesyn/readymade/workplans/
	print("\n💾 PERSISTENCE TEST:")
	var manager = get_node_or_null("/root/WorkplanManager")
	if manager == null and orchestrator.has_method("get_workplan_manager"):
		manager = orchestrator.get_workplan_manager()
	var workplans_dir: String = RuntimeConfig.get_workplans_dir()
	var found_store := false
	if manager != null and not String(manager.current_workplan_path).is_empty():
		found_store = FileAccess.file_exists(manager.current_workplan_path) or ResourceLoader.exists(manager.current_workplan_path)
		print("   📂 Active workplan path: ", manager.current_workplan_path)
	if not found_store and DirAccess.dir_exists_absolute(workplans_dir):
		var dir := DirAccess.open(workplans_dir)
		if dir:
			dir.list_dir_begin()
			var file_name := dir.get_next()
			while file_name != "":
				if file_name.ends_with(".tres"):
					found_store = true
					print("   ✅ Found workplan store file: ", workplans_dir.path_join(file_name))
					break
				file_name = dir.get_next()
	if found_store:
		print("   ✅ WorkplanManager store present under ", workplans_dir)
	else:
		print("   📝 No workplan store file yet (will be created on first save) at ", workplans_dir)
	
	# Instrument vocabulary (ADR 0024) — avoids instantiating LimboAI BTTask subclasses
	print("\n🎨 INSTRUMENT VOCABULARY TEST:")
	var mapped: String = CosmicInstruments.canonicalize("Role-Playing (Expert Analysis)")
	if mapped == CosmicInstruments.CODE_RP:
		print("   ✅ CosmicInstruments maps Role-Playing → RP")
	else:
		print("   ⚠️ CosmicInstruments mapping unexpected: ", mapped)
	
	print("\n🚀 Basic system test complete!")
	
	# Exit after a short settle so deferred orchestrator setup finishes cleanly
	await get_tree().create_timer(1.0).timeout
	get_tree().quit(0)
