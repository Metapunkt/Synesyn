# ReadyMadeOrchestrator.gd
extends Node

const WorkplanTaskScript = preload("res://readymade/data/workplan_task.gd")

signal workplan_loaded

# Use WorkplanManager instead of direct workplan management
var workplan_manager: Node
var workplan: Workplan  # Current active workplan (for compatibility)
var a1_agent: Node

func _ready():
	print("🚀 ReadyMadeOrchestrator is ready")
	
	# Ensure the core SynTree PluginManager exists at runtime.
	_ensure_plugin_manager()
	
	# Setup WorkplanManager
	call_deferred("_setup_workplan_manager")

func _setup_workplan_manager():
	"""Setup the WorkplanManager singleton"""
	# Check if WorkplanManager already exists
	workplan_manager = get_node_or_null("/root/WorkplanManager")
	if not workplan_manager:
		print("⚠️ WorkplanManager not found - creating instance...")
		await _create_workplan_manager_instance()
	
	# Connect to WorkplanManager signals
	if workplan_manager:
		workplan_manager.workplan_changed.connect(_on_workplan_changed)
		# Get the current workplan
		workplan = workplan_manager.get_current_workplan()
		print("🗂️ Connected to WorkplanManager, current workplan: ", workplan_manager.get_current_workplan_name())
		
		# If no workplan is active, initialize with default content
		if workplan and workplan.get_total_tasks() == 0:
			print("ReadyMade Orchestrator: Creating default workplan tasks.")
			_create_default_tasks()
			workplan_manager.save_current_workplan()
		
		# Emit the workplan loaded signal for compatibility
		workplan_loaded.emit()
	
	# Find the A1 Synthesis Agent in the scene
	call_deferred("_setup_a1_agent")

func _create_workplan_manager_instance():
	"""Create and instantiate the WorkplanManager if it's not found"""
	var manager_script = load("res://readymade/scripts/singletons/WorkplanManager.gd")
	if manager_script:
		workplan_manager = manager_script.new()
		workplan_manager.name = "WorkplanManager"
		get_tree().get_root().add_child(workplan_manager)
		print("ReadyMadeOrchestrator: ✅ WorkplanManager created and added to scene tree")
		
		# Wait a frame to ensure the node is fully ready
		await get_tree().process_frame
		
		if workplan_manager.is_inside_tree():
			print("ReadyMadeOrchestrator: ✅ WorkplanManager confirmed in scene tree")
		else:
			print("ReadyMadeOrchestrator: ⚠️ WorkplanManager not properly added to scene tree")
	else:
		push_error("ReadyMadeOrchestrator: Failed to load WorkplanManager script!")

func _on_workplan_changed(new_workplan: Workplan):
	"""Handle workplan changes from WorkplanManager"""
	workplan = new_workplan
	print("🔄 Orchestrator received workplan change: ", workplan_manager.get_current_workplan_name())
	workplan_loaded.emit()  # Notify UI components of the change

func get_workplan_manager() -> Node:
	"""Get the WorkplanManager instance"""
	return workplan_manager

func get_current_workplan_name() -> String:
	"""Get the name of the currently active workplan"""
	if workplan_manager:
		return workplan_manager.get_current_workplan_name()
	return ""

func switch_workplan(workplan_name: String) -> bool:
	"""Switch to a different workplan"""
	if workplan_manager:
		return workplan_manager.switch_to_workplan(workplan_name)
	return false

func create_new_workplan(workplan_name: String, description: String = "") -> bool:
	"""Create a new workplan"""
	if workplan_manager:
		return workplan_manager.create_new_workplan(workplan_name, description)
	return false

func _setup_a1_agent():
	"""Setup the A1 agent, creating it if necessary"""
	a1_agent = get_node_or_null("/root/A1SynthesisEngine") # Adjust path if needed
	if not a1_agent:
		print("⚠️ A1 Synthesis Agent not found - creating instance...")
		await _create_a1_agent_instance()

func _create_a1_agent_instance():
	"""
	Creates and instantiates the A1SynthesisEngine if it's not found in the scene tree.
	This ensures the agent is available for task processing.
	"""
	var agent_scene = load("res://readymade/agents/a1_synthesis_engine.tscn")
	if agent_scene:
		a1_agent = agent_scene.instantiate()
		a1_agent.name = "A1SynthesisEngine"
		get_tree().get_root().add_child(a1_agent)
		print("ReadyMadeOrchestrator: ✅ A1SynthesisEngine created and added to scene tree")
		
		# Wait a frame to ensure the node is fully ready
		await get_tree().process_frame
		
		# Verify the agent is properly in the scene tree
		if a1_agent.is_inside_tree():
			print("ReadyMadeOrchestrator: ✅ A1SynthesisEngine confirmed in scene tree")
		else:
			print("ReadyMadeOrchestrator: ⚠️ A1SynthesisEngine not properly added to scene tree")
	else:
		push_error("ReadyMadeOrchestrator: Failed to load A1SynthesisEngine scene!")

func _ensure_plugin_manager():
	"""
	Checks if the PluginManager node exists at the scene root. If not, it
	creates an instance and adds it. This makes the ReadyMade module
	self-contained and runnable without manual scene setup.
	"""
	if get_tree().get_root().has_node("PluginManager"):
		print("ReadyMadeOrchestrator: PluginManager already in scene tree.")
		return

	print("ReadyMadeOrchestrator: PluginManager not found. Creating instance for runtime.")
	var PluginManagerClass = load("res://addons/syntree/scripts/plugin_manager.gd")
	if PluginManagerClass:
		var pm_instance = PluginManagerClass.new()
		pm_instance.name = "PluginManager"
		get_tree().get_root().add_child(pm_instance)
		print("ReadyMadeOrchestrator: PluginManager node added to /root/PluginManager")
	else:
		push_error("ReadyMadeOrchestrator: Failed to load PluginManager script.")

func _create_default_tasks():
	"""Create default tasks if no saved workplan exists"""
	if not workplan.months.has("Month 1"):
		workplan.months["Month 1"] = []
	
	var month1_tasks = workplan.months["Month 1"]
	
	var task1 = WorkplanTask.new()
	task1.title = "Boosted Inference Article"
	task1.core_idea = "Sprint brief: \"Boosted Inference vs. Stochastic Parrots\""
	task1.cosmic_instrument = "Hypothetical Framings (Reality Benders)"
	task1.format = "Article"
	task1.channel = "Discord"
	task1.notes = "Sets the script skeleton for the week's main video."
	task1.status = "To Do"
	task1.deadline = "2025-01-10"
	month1_tasks.append(task1)

	var task2 = WorkplanTask.new()
	task2.title = "Dimensions & Mind Video"
	task2.core_idea = "Video: \"Why 3+1 Dims = 4-Item Mind?\""
	task2.cosmic_instrument = "Abductive Hypothesis Generation (Quantum Reasoning)"
	task2.format = "Video"
	task2.channel = "YouTube"
	task2.notes = "Main deliverable for the week. Drive to Discord #start-here."
	task2.status = "In Progress"
	task2.deadline = "2025-01-08"
	task2.start_date = "2025-01-02"
	month1_tasks.append(task2)

	var task3 = WorkplanTask.new()
	task3.title = "Magic Number 4 Carousel"
	task3.core_idea = "Carousel: \"Magic Number 4\" explainer"
	task3.cosmic_instrument = "Iterative Refinement (Gravitational Drift)"
	task3.format = "Carousel"
	task3.channel = "Instagram, Facebook"
	task3.notes = "Link back to the main YouTube video."
	task3.status = "Review"
	task3.deadline = "2025-01-12"
	task3.generated_content = "# Magic Number 4 Carousel\n\n## Slide 1: Introduction\nThe magic number 4 appears everywhere in cognitive science...\n\n## Slide 2: Working Memory\nHuman working memory can hold approximately 4±1 items...\n\n## Slide 3: Applications\nThis principle applies to UI design, learning, and decision making..."
	month1_tasks.append(task3)
	
	# Add a completed task with content for the content viewer
	var task4 = WorkplanTask.new()
	task4.title = "AI Ethics Brief"
	task4.core_idea = "Brief on AI ethics considerations for content creators"
	task4.cosmic_instrument = "Role-Playing (Expert Analysis)"
	task4.format = "Article"
	task4.channel = "Blog"
	task4.notes = "Background research for upcoming content."
	task4.status = "Done"
	task4.completion_date = "2025-01-01"
	task4.generated_content = "# AI Ethics for Content Creators\n\n## Introduction\nAs AI becomes increasingly integrated into content creation workflows, creators must navigate complex ethical considerations...\n\n## Key Principles\n1. Transparency about AI usage\n2. Respect for human creativity\n3. Avoiding bias amplification\n4. Protecting audience trust\n\n## Best Practices\n- Always disclose AI assistance\n- Review and edit AI-generated content\n- Maintain human oversight\n- Consider societal impact"
	month1_tasks.append(task4)

	workplan.months["Month 1"] = month1_tasks
	print("ReadyMade Orchestrator: Default tasks created successfully with mixed statuses.")
	print("ReadyMade Orchestrator: Created ", month1_tasks.size(), " tasks")

func get_all_tasks() -> Dictionary:
	if workplan:
		return workplan.months
	return {}

func get_next_pending_task() -> WorkplanTask:
	"""Get the next task with 'To Do' status"""
	if not workplan or not workplan.months:
		print("ReadyMadeOrchestrator: ⚠ No workplan available")
		return null
	
	# Search through all months for the first "To Do" task
	for month_name in workplan.months.keys():
		var tasks = workplan.months[month_name]
		for task in tasks:
			if task.status == "To Do":
				print("ReadyMadeOrchestrator: 📋 Next task: ", task.core_idea)
				return task
	
	print("ReadyMadeOrchestrator: ✅ No pending tasks found - all completed!")
	return null

func update_task(_task: WorkplanTask):
	"""Call this whenever a task is modified to trigger persistence"""
	if workplan_manager:
		workplan_manager.save_current_workplan()

func add_task_to_month(month: String, task: WorkplanTask):
	"""Add a new task to a specific month"""
	if workplan:
		workplan.add_task_to_month(month, task)
		if workplan_manager:
			workplan_manager.save_current_workplan()

func remove_task_from_month(month: String, task: WorkplanTask):
	"""Remove a task from a specific month"""
	if workplan:
		workplan.remove_task_from_month(month, task)
		if workplan_manager:
			workplan_manager.save_current_workplan()

func save_workplan():
	"""Manually save the workplan"""
	if workplan_manager:
		workplan_manager.save_current_workplan()

func reset_workplan():
	"""Reset workplan to default tasks (useful for testing)"""
	print("ReadyMade Orchestrator: Resetting current workplan to defaults...")
	if workplan:
		workplan.months.clear()
		workplan.months = {}
		_create_default_tasks()
		if workplan_manager:
			workplan_manager.save_current_workplan()
		workplan_loaded.emit()
		print("ReadyMade Orchestrator: Workplan reset complete") 
