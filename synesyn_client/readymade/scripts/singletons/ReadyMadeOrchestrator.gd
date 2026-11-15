# ReadyMadeOrchestrator.gd
extends Node

const WorkplanTaskScript = preload("res://readymade/data/workplan_task.gd")

signal workplan_loaded
signal workplan_manager_ready
signal backend_unavailable(message: String)

# Use WorkplanManager instead of direct workplan management
var workplan_manager: Node
var workplan: Workplan  # Current active workplan (for compatibility)
var a1_agent: Node
var _last_backend_notice: String = ""
var _workplan_manager_ready: bool = false

func _ready():
	print("🚀 ReadyMadeOrchestrator is ready")
	
	# Ensure the core SynTree PluginManager exists at runtime.
	_ensure_plugin_manager()
	
	# WorkplanManager is an autoload declared before this node, so it is already
	# initialized. Bind immediately — no call_deferred race for first UI paint.
	_setup_workplan_manager()
	call_deferred("_setup_a1_agent")

func is_workplan_manager_ready() -> bool:
	return _workplan_manager_ready and workplan_manager != null and workplan != null


func await_workplan_manager_ready() -> void:
	"""UI consumers can await this before reading workplan state."""
	if is_workplan_manager_ready():
		return
	await workplan_manager_ready


func _setup_workplan_manager():
	"""Bind the WorkplanManager autoload (create only if missing in odd test setups)."""
	workplan_manager = get_node_or_null("/root/WorkplanManager")
	if not workplan_manager:
		print("⚠️ WorkplanManager autoload missing - creating fallback instance...")
		call_deferred("_create_workplan_manager_instance_and_bind")
		return
	_bind_workplan_manager()


func _bind_workplan_manager() -> void:
	if workplan_manager == null:
		return
	if not workplan_manager.workplan_changed.is_connected(_on_workplan_changed):
		workplan_manager.workplan_changed.connect(_on_workplan_changed)
	workplan = workplan_manager.get_current_workplan()
	print("🗂️ Connected to WorkplanManager, current workplan: ", workplan_manager.get_current_workplan_name())
	_maybe_offer_first_launch_workplan_choice()
	_workplan_manager_ready = true
	workplan_manager_ready.emit()
	workplan_loaded.emit()


func _create_workplan_manager_instance_and_bind() -> void:
	"""Fallback for environments that did not register the WorkplanManager autoload."""
	var manager_script = load("res://readymade/scripts/singletons/WorkplanManager.gd")
	if manager_script == null:
		push_error("ReadyMadeOrchestrator: Failed to load WorkplanManager script!")
		return
	workplan_manager = manager_script.new()
	workplan_manager.name = "WorkplanManager"
	get_tree().get_root().add_child(workplan_manager)
	print("ReadyMadeOrchestrator: ✅ WorkplanManager fallback created")
	await get_tree().process_frame
	_bind_workplan_manager()

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

func _date_offset_string(days_from_today: int) -> String:
	"""Format YYYY-MM-DD relative to today so demo tasks land on the current calendar."""
	var unix: int = int(Time.get_unix_time_from_system()) + (days_from_today * 86400)
	var date_dict: Dictionary = Time.get_datetime_dict_from_unix_time(unix)
	return "%04d-%02d-%02d" % [int(date_dict.year), int(date_dict.month), int(date_dict.day)]


func _is_headless_runtime() -> bool:
	return DisplayServer.get_name() == "headless" or OS.has_feature("headless")


func _get_readymade_app_config() -> Dictionary:
	var cfg: Dictionary = RuntimeConfig.load_config()
	if not cfg.has("apps") or typeof(cfg["apps"]) != TYPE_DICTIONARY:
		cfg["apps"] = {}
	var apps: Dictionary = cfg["apps"]
	if not apps.has("readymade") or typeof(apps["readymade"]) != TYPE_DICTIONARY:
		apps["readymade"] = {}
	return apps["readymade"]


func _save_readymade_app_config(readymade_cfg: Dictionary) -> void:
	var cfg: Dictionary = RuntimeConfig.load_config()
	if not cfg.has("apps") or typeof(cfg["apps"]) != TYPE_DICTIONARY:
		cfg["apps"] = {}
	(cfg["apps"] as Dictionary)["readymade"] = readymade_cfg
	RuntimeConfig.save_config(cfg)


func get_first_launch_workplan_choice() -> String:
	"""Return remembered first-launch choice: sample | empty | '' if unset."""
	var readymade_cfg: Dictionary = _get_readymade_app_config()
	return String(readymade_cfg.get("first_launch_workplan", "")).strip_edges()


func set_first_launch_workplan_choice(choice: String) -> void:
	"""Persist first-launch sample/empty choice so later launches do not re-seed."""
	var normalized: String = choice.strip_edges().to_lower()
	if normalized != "sample" and normalized != "empty":
		return
	var readymade_cfg: Dictionary = _get_readymade_app_config()
	readymade_cfg["first_launch_workplan"] = normalized
	_save_readymade_app_config(readymade_cfg)


func _maybe_offer_first_launch_workplan_choice() -> void:
	"""On first launch with an empty workplan, offer sample vs blank slate once."""
	if workplan == null:
		return
	var choice: String = get_first_launch_workplan_choice()
	if choice == "empty":
		print("ReadyMade Orchestrator: first-launch choice is empty — not seeding demo tasks.")
		return
	if choice == "sample":
		# Remembered sample: only seed when the workplan is still empty AND we have
		# never completed the initial seed (handled by seeding only from the chooser).
		print("ReadyMade Orchestrator: first-launch choice is sample — leaving current tasks as-is.")
		return
	# Unset: if the workplan already has tasks (legacy installs), remember sample and stop.
	if workplan.get_total_tasks() > 0:
		set_first_launch_workplan_choice("sample")
		return
	if _is_headless_runtime():
		# Non-interactive CI / acceptance: blank slate, never re-prompt.
		set_first_launch_workplan_choice("empty")
		print("ReadyMade Orchestrator: headless first launch → empty workplan (no demo seed).")
		return
	call_deferred("_prompt_first_launch_workplan_choice")


func _prompt_first_launch_workplan_choice() -> void:
	"""Modal chooser: Start with sample workplan vs Start empty."""
	if get_first_launch_workplan_choice() != "":
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = "Welcome to ReadyMade"
	dialog.dialog_text = "How would you like to start?\n\nYou can explore a sample workplan, or begin with a blank slate."
	dialog.ok_button_text = "Start with sample workplan"
	dialog.cancel_button_text = "Start empty"
	dialog.confirmed.connect(func() -> void:
		_apply_first_launch_workplan_choice("sample")
		dialog.queue_free()
	)
	dialog.canceled.connect(func() -> void:
		_apply_first_launch_workplan_choice("empty")
		dialog.queue_free()
	)
	get_tree().root.add_child(dialog)
	dialog.popup_centered()


func _apply_first_launch_workplan_choice(choice: String) -> void:
	set_first_launch_workplan_choice(choice)
	if choice == "sample" and workplan and workplan.get_total_tasks() == 0:
		print("ReadyMade Orchestrator: Creating sample workplan tasks.")
		_create_default_tasks()
		if workplan_manager:
			workplan_manager.save_current_workplan()
		workplan_loaded.emit()
	else:
		print("ReadyMade Orchestrator: Starting with an empty workplan.")


func _create_default_tasks():
	"""Create default/sample tasks for a new workplan"""
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
	task1.deadline = _date_offset_string(5)
	task1.scheduled_date = _date_offset_string(2)
	month1_tasks.append(task1)

	var task2 = WorkplanTask.new()
	task2.title = "Dimensions & Mind Video"
	task2.core_idea = "Video: \"Why 3+1 Dims = 4-Item Mind?\""
	task2.cosmic_instrument = "Abductive Hypothesis Generation (Quantum Reasoning)"
	task2.format = "Video"
	task2.channel = "YouTube"
	task2.notes = "Main deliverable for the week. Drive to Discord #start-here."
	task2.status = "In Progress"
	task2.deadline = _date_offset_string(3)
	task2.start_date = _date_offset_string(0)
	task2.scheduled_date = _date_offset_string(0)
	month1_tasks.append(task2)

	var task3 = WorkplanTask.new()
	task3.title = "Magic Number 4 Carousel"
	task3.core_idea = "Carousel: \"Magic Number 4\" explainer"
	task3.cosmic_instrument = "Iterative Refinement (Gravitational Drift)"
	task3.format = "Carousel"
	task3.channel = "Instagram, Facebook"
	task3.notes = "Link back to the main YouTube video."
	task3.status = "Review"
	task3.deadline = _date_offset_string(7)
	task3.scheduled_date = _date_offset_string(4)
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
	task4.completion_date = _date_offset_string(-2)
	task4.deadline = _date_offset_string(-2)
	task4.scheduled_date = _date_offset_string(-2)
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


func build_backend_unavailable_message(reason: String = "") -> String:
	"""User-facing guidance when hub / LLM backend is missing."""
	var config_path: String = RuntimeConfig.get_config_path_abs()
	var detail: String = reason.strip_edges()
	if detail.is_empty():
		detail = "The AI backend (Synesyn hub / LLM) is not available."
	return (
		"%s\n\n"
		+ "What to do:\n"
		+ "1. Start the Synesyn hub (services/synesyn_hub), usually at http://127.0.0.1:17777.\n"
		+ "2. Configure hub.base_url and model credentials in:\n   %s\n"
		+ "3. Restart ReadyMade, then use Draft To Do tasks again.\n\n"
		+ "Failed generation leaves the task not Done so you can retry."
	) % [detail, config_path]


func get_hub_base_url() -> String:
	"""Resolve the configured Synesyn hub base URL."""
	var cfg: Dictionary = RuntimeConfig.load_config()
	return str(ProviderModePolicy.get_hub_base_url(cfg)).strip_edges()


func probe_hub_available(timeout_sec: float = 0.75) -> bool:
	"""Best-effort TCP reachability check against hub.base_url (host:port)."""
	var base_url: String = get_hub_base_url()
	if base_url.is_empty():
		return false
	var host: String = "127.0.0.1"
	var port: int = 17777
	var cleaned: String = base_url
	if cleaned.begins_with("http://"):
		cleaned = cleaned.substr(7)
	elif cleaned.begins_with("https://"):
		cleaned = cleaned.substr(8)
	cleaned = cleaned.split("/")[0]
	if ":" in cleaned:
		var parts: PackedStringArray = cleaned.split(":")
		host = String(parts[0]).strip_edges()
		port = int(parts[1])
	else:
		host = cleaned.strip_edges()
	if host.is_empty():
		host = "127.0.0.1"
	if port <= 0:
		port = 17777

	var http := HTTPClient.new()
	var connect_err: Error = http.connect_to_host(host, port)
	if connect_err != OK:
		return false
	var started_ms: int = Time.get_ticks_msec()
	var timeout_ms: int = int(timeout_sec * 1000.0)
	while http.get_status() == HTTPClient.STATUS_CONNECTING or http.get_status() == HTTPClient.STATUS_RESOLVING:
		http.poll()
		if Time.get_ticks_msec() - started_ms > timeout_ms:
			http.close()
			return false
		OS.delay_msec(10)
	var status: int = http.get_status()
	http.close()
	return (
		status == HTTPClient.STATUS_CONNECTED
		or status == HTTPClient.STATUS_REQUESTING
		or status == HTTPClient.STATUS_BODY
	)


func request_start_agent_batch() -> bool:
	"""
	Single entry for Draft To Do tasks: require A1 + reachable hub, else emit the
	same AcceptDialog-backed backend_unavailable guidance used by drafting.
	Returns true when batch processing was started.
	"""
	if a1_agent == null:
		a1_agent = get_node_or_null("/root/A1SynthesisEngine")
	if a1_agent == null:
		notify_backend_unavailable("A1 Synthesis Agent is not loaded, so drafting cannot start.")
		return false
	if not probe_hub_available():
		var hub_url: String = get_hub_base_url()
		if hub_url.is_empty():
			hub_url = "http://127.0.0.1:17777"
		notify_backend_unavailable(
			"Synesyn hub is not reachable at %s. Start the hub before running Draft To Do tasks." % hub_url
		)
		return false
	if a1_agent.has_method("start_batch_processing"):
		a1_agent.start_batch_processing()
		print("ReadyMadeOrchestrator: 🚀 Agent batch processing started")
		return true
	if a1_agent.has_method("execute_all_tasks"):
		a1_agent.execute_all_tasks()
		print("ReadyMadeOrchestrator: 🚀 Agent processing all tasks")
		return true
	if a1_agent.has_method("execute_next_task"):
		a1_agent.execute_next_task()
		print("ReadyMadeOrchestrator: 🚀 Agent started (single task mode)")
		return true
	notify_backend_unavailable("A1 Synthesis Agent has no batch entry point.")
	return false


func notify_backend_unavailable(reason: String = "") -> void:
	"""Surface a visible no-hub / no-AI empty state (UI listens on backend_unavailable)."""
	var message: String = build_backend_unavailable_message(reason)
	# Collapse retries that only differ by timestamp / task detail.
	var dedupe_key: String = message
	var reason_l: String = reason.to_lower()
	var message_l: String = message.to_lower()
	if "ai generation failed" in reason_l or "ai generation failed" in message_l:
		dedupe_key = "ai_generation_failed"
	elif "not available" in message_l and "hub" in message_l:
		dedupe_key = "hub_unavailable"
	if dedupe_key == _last_backend_notice:
		return
	_last_backend_notice = dedupe_key
	backend_unavailable.emit(message)

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
