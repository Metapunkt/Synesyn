extends Node

func _ready():
	print("🧪 Testing Basic ReadyMade System...")
	
	# Test orchestrator loading
	var orchestrator = get_node_or_null("/root/ReadyMadeOrchestrator")
	if not orchestrator:
		print("❌ ReadyMadeOrchestrator not found!")
		return
	
	print("✅ ReadyMadeOrchestrator found")
	
	# Test workplan loading
	if not orchestrator.workplan:
		print("❌ Workplan not loaded!")
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
	
	# Test persistence
	print("\n💾 PERSISTENCE TEST:")
	var save_path = "user://workplan_data.tres"
	if ResourceLoader.exists(save_path):
		print("   ✅ Persistent workplan file exists")
	else:
		print("   📝 No persistent workplan file (will be created)")
	
	# Test enhanced AI prompting
	print("\n🎨 AI ENHANCEMENT TEST:")
	var process_task = preload("res://readymade/scripts/bt_tasks/ProcessFoundConceptTask.gd").new()
	
	var test_prompt = process_task._build_inference_architect_metaprompt()
	if "concrete" in test_prompt.to_lower() or "specific" in test_prompt.to_lower():
		print("   ✅ Enhanced anti-slop prompting active")
	else:
		print("   ⚠️ Enhanced prompting may not be working")
	
	process_task.queue_free()
	
	print("\n🚀 Basic system test complete!")
	
	# Exit after 2 seconds
	await get_tree().create_timer(2.0).timeout
	get_tree().quit() 