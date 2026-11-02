extends Node

# ReadyMade System Diagnostics
# Run this to check system health before testing

func _ready():
	print("=== ReadyMade System Diagnostics ===")
	run_all_diagnostics()

func run_all_diagnostics():
	check_scene_files()
	check_script_files()
	check_dependencies()
	check_data_persistence()
	check_ai_integration()
	print("=== Diagnostics Complete ===")

func check_scene_files():
	print("\n🎬 Scene Files Check:")
	var scenes_to_check = [
		"res://readymade/ui/mission_control_dashboard.tscn",
		"res://readymade/ui/task_creation_dialog.tscn",
		"res://readymade/agents/a1_synthesis_engine.tscn"
	]
	
	for scene_path in scenes_to_check:
		if ResourceLoader.exists(scene_path):
			print("✅ " + scene_path)
		else:
			print("❌ MISSING: " + scene_path)

func check_script_files():
	print("\n📝 Script Files Check:")
	var scripts_to_check = [
		"res://readymade/ui/mission_control_dashboard.gd",
		"res://readymade/ui/task_creation_dialog.gd",
		"res://readymade/agents/a1_agent.gd",
		"res://readymade/scripts/bt_tasks/ProcessFoundConceptTask.gd",
		"res://readymade/scripts/content_templates/format_templates.gd",
		"res://readymade/scripts/content_templates/channel_optimizer.gd"
	]
	
	for script_path in scripts_to_check:
		if ResourceLoader.exists(script_path):
			print("✅ " + script_path)
		else:
			print("❌ MISSING: " + script_path)

func check_dependencies():
	print("\n🔗 Dependencies Check:")
	
	# Check if SynTree plugin is loaded
	if Engine.has_singleton("SynTreeAPI"):
		print("✅ SynTree API available")
	else:
		print("⚠️  SynTree API not found - AI features may not work")
	
	# Check LimboAI plugin
	if ClassDB.class_exists("BehaviorTree"):
		print("✅ LimboAI (BehaviorTree) available")
	else:
		print("❌ LimboAI plugin not loaded")
	
	# Check file system access
	var test_dir = "readymade/output/"
	var dir_access = DirAccess.open("res://")
	if dir_access and dir_access.dir_exists(test_dir):
		print("✅ Output directory accessible")
	else:
		print("⚠️  Output directory not found: " + test_dir)

func check_data_persistence():
	print("\n💾 Data Persistence Check:")
	
	# Check if workplan data exists
	var workplan_path = "res://readymade/data/workplan.gd"
	if ResourceLoader.exists(workplan_path):
		print("✅ Workplan data structure available")
		
		# Try to create a test workplan
		var workplan_script = load(workplan_path)
		if workplan_script:
			var workplan = workplan_script.new()
			print("✅ Workplan instantiation works")
		else:
			print("❌ Cannot instantiate Workplan")
	else:
		print("❌ MISSING: Workplan data structure")

func check_ai_integration():
	print("\n🤖 AI Integration Check:")
	
	# Check if format templates are loadable
	var format_templates_path = "res://readymade/scripts/content_templates/format_templates.gd"
	if ResourceLoader.exists(format_templates_path):
		var templates_script = load(format_templates_path)
		if templates_script:
			var templates = templates_script.new()
			print("✅ Format templates loadable")
			
			# Test template access
			var video_template = templates.get_template("video")
			if video_template and video_template.has("structure"):
				print("✅ Template data structure valid")
			else:
				print("⚠️  Template data structure issues")
		else:
			print("❌ Cannot load format templates")
	
	# Check channel optimizer
	var optimizer_path = "res://readymade/scripts/content_templates/channel_optimizer.gd"
	if ResourceLoader.exists(optimizer_path):
		var optimizer_script = load(optimizer_path)
		if optimizer_script:
			var optimizer = optimizer_script.new()
			print("✅ Channel optimizer loadable")
		else:
			print("❌ Cannot load channel optimizer")

# Helper function to run diagnostics from console
func run_diagnostics():
	run_all_diagnostics()

# Test specific components
func test_task_creation():
	print("\n🧪 Testing Task Creation:")
	var task_script = load("res://readymade/data/workplan_task.gd")
	if task_script:
		var task = task_script.new()
		task.title = "Test Task"
		task.description = "Testing task creation"
		task.priority = "Medium"
		task.status = "To Do"
		print("✅ Task creation successful")
		print("   Title: " + task.title)
		print("   Status: " + task.status)
		return task
	else:
		print("❌ Cannot create test task")
		return null

func test_agent_instantiation():
	print("\n🤖 Testing Agent Instantiation:")
	var agent_scene_path = "res://readymade/agents/a1_synthesis_engine.tscn"
	if ResourceLoader.exists(agent_scene_path):
		var agent_scene = load(agent_scene_path)
		if agent_scene:
			var agent_instance = agent_scene.instantiate()
			print("✅ Agent instantiation successful")
			print("   Agent type: " + str(agent_instance.get_class()))
			agent_instance.queue_free()
		else:
			print("❌ Cannot instantiate agent")
	else:
		print("❌ Agent scene not found")

# Quick system health check
func quick_health_check():
	print("\n⚡ Quick Health Check:")
	var health_score = 0
	var total_checks = 5
	
	# Check 1: Core scenes exist
	if ResourceLoader.exists("res://readymade/ui/mission_control_dashboard.tscn"):
		health_score += 1
		print("✅ Dashboard scene")
	else:
		print("❌ Dashboard scene missing")
	
	# Check 2: Agent exists
	if ResourceLoader.exists("res://readymade/agents/a1_synthesis_engine.tscn"):
		health_score += 1
		print("✅ Agent scene")
	else:
		print("❌ Agent scene missing")
	
	# Check 3: Data structures
	if ResourceLoader.exists("res://readymade/data/workplan_task.gd"):
		health_score += 1
		print("✅ Data structures")
	else:
		print("❌ Data structures missing")
	
	# Check 4: Content templates
	if ResourceLoader.exists("res://readymade/scripts/content_templates/format_templates.gd"):
		health_score += 1
		print("✅ Content templates")
	else:
		print("❌ Content templates missing")
	
	# Check 5: LimboAI
	if ClassDB.class_exists("BehaviorTree"):
		health_score += 1
		print("✅ LimboAI plugin")
	else:
		print("❌ LimboAI plugin not loaded")
	
	var health_percentage = (health_score * 100) / total_checks
	print("\n🏥 System Health: " + str(health_percentage) + "% (" + str(health_score) + "/" + str(total_checks) + " checks passed)")
	
	if health_percentage >= 80:
		print("🟢 System ready for testing!")
	elif health_percentage >= 60:
		print("🟡 System partially ready - some features may not work")
	else:
		print("🔴 System not ready - major issues detected")
	
	return health_percentage 