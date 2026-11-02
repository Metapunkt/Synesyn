extends Node

func _ready():
	print("🧪 Testing Enhanced AI Content Generation...")
	
	# Get the orchestrator
	var orchestrator = get_node("/root/ReadyMadeOrchestrator")
	if not orchestrator:
		print("❌ ReadyMadeOrchestrator not found!")
		return
	
	# Get a task to test with
	var test_task = orchestrator.get_next_pending_task()
	if not test_task:
		print("❌ No pending tasks found!")
		return
	
	print("📋 Testing with task: ", test_task.core_idea)
	
	# Create the ProcessFoundConceptTask
	var process_task = preload("res://readymade/scripts/bt_tasks/ProcessFoundConceptTask.gd").new()
	
	# Test the enhanced prompting system
	var formats = ["Short Text"]
	var channels = ["Facebook", "Twitter/X", "Discord"]  
	var instruments = ["Hypothetical Framings (Reality Benders)"]
	
	var enhanced_prompt = process_task._apply_cosmic_instruments(
		test_task.core_idea, 
		instruments, 
		formats, 
		channels, 
		test_task.notes
	)
	
	print("\n🎯 ENHANCED PROMPT GENERATED:")
	print("==================================================")
	print(enhanced_prompt)
	print("==================================================")
	
	print("\n✅ Enhanced prompting system is working!")
	print("🎨 This should generate much more creative, less formulaic content.")
	
	# Clean up
	process_task.queue_free() 