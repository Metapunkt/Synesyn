# a1_agent.gd
extends Node
class_name A1SynthesisEngine
## A1 Synthesis Engine Agent - Processes Found Concepts using LimboAI

@onready var bt_player: BTPlayer = $BTPlayer
var current_task: WorkplanTask = null
var processing_active: bool = false
var completion_timer: Timer = null

# Enhanced robustness features
var task_queue: Array[WorkplanTask] = []
var processing_start_time: float = 0.0
var max_processing_time: float = 300.0  # 5 minutes timeout
var retry_count: int = 0
var max_retries: int = 3
var error_recovery_active: bool = false
var last_error: String = ""
var performance_metrics: Dictionary = {
	"tasks_completed": 0,
	"tasks_failed": 0,
	"average_processing_time": 0.0,
	"total_processing_time": 0.0,
	"success_rate": 0.0
}

# Progress tracking
signal task_started(task: WorkplanTask)
signal task_progress_updated(task: WorkplanTask, progress: float, status: String)
signal task_completed(task: WorkplanTask, success: bool)
signal processing_error(error_message: String)
signal queue_status_changed(queue_size: int)

func _ready():
	print("A1 Synthesis Engine initializing...")
	
	# Wait for node to be properly in the scene tree
	if not is_inside_tree():
		await tree_entered
	
	# Wait for BTPlayer to be fully initialized
	if get_tree():
		await get_tree().process_frame
	
	# Get the orchestrator singleton
	var orchestrator = ReadyMadeOrchestrator
	if not orchestrator:
		printerr("A1Agent: ReadyMadeOrchestrator singleton not found!")
		return
	
	# Set up blackboard with orchestrator
	if bt_player and bt_player.blackboard:
		bt_player.blackboard.set_var("orchestrator", orchestrator)
		print("A1Agent: Blackboard initialized with orchestrator")
	else:
		printerr("A1Agent: BTPlayer or blackboard not found!")
		printerr("  bt_player: ", bt_player)
		if bt_player:
			printerr("  bt_player.blackboard: ", bt_player.blackboard)

func stop_processing():
	"""Stop the behavior tree execution"""
	if bt_player:
		bt_player.set_active(false)
		print("A1Agent: Behavior tree stopped")
	else:
		printerr("A1Agent: BTPlayer not found!")
	
	# Clean up state
	processing_active = false
	current_task = null
	if completion_timer:
		completion_timer.queue_free()
		completion_timer = null

func execute_next_task():
	"""Enhanced task execution with queue management and error recovery"""
	# Don't start new task if already processing and not in error recovery
	if processing_active and not error_recovery_active:
		print("A1Agent: ⚠ Already processing a task, adding to queue...")
		_populate_task_queue()
		return
	
	# Try to get next task from queue first, then from orchestrator
	var next_task: WorkplanTask = null
	if task_queue.size() > 0:
		next_task = task_queue.pop_front()
		queue_status_changed.emit(task_queue.size())
		print("A1Agent: 📋 Processing queued task: ", next_task.core_idea)
	else:
		var orchestrator = ReadyMadeOrchestrator
		next_task = orchestrator.get_next_pending_task()
		if next_task:
			print("A1Agent: 🎯 Starting new task: ", next_task.core_idea)
	
	if next_task:
		_start_task_processing(next_task)
	else:
		print("A1Agent: 🎉 All tasks completed!")
		_finalize_processing_session()

func _start_task_processing(task: WorkplanTask):
	"""Start processing a task with full error handling and monitoring"""
	current_task = task
	processing_active = true
	error_recovery_active = false
	processing_start_time = Time.get_time_dict_from_system().hour * 3600 + Time.get_time_dict_from_system().minute * 60 + Time.get_time_dict_from_system().second
	retry_count = 0
	
	# Emit progress signal
	task_started.emit(task)
	task_progress_updated.emit(task, 0.0, "Initializing...")
	
	if not bt_player:
		_handle_processing_error("BTPlayer not found!", task)
		return
	
	# Ensure behavior tree is active but not running yet
	bt_player.set_active(false)
	
	# Set blackboard variables with validation
	if bt_player.blackboard:
		var orchestrator = ReadyMadeOrchestrator
		bt_player.blackboard.set_var("orchestrator", orchestrator)
		bt_player.blackboard.set_var("current_task", task)
		
		# Add ModeManager for mode-aware prompting
		if ModeManager:
			bt_player.blackboard.set_var("mode_manager", ModeManager)
		
		# Verify the variables were set correctly
		var check_orchestrator = bt_player.blackboard.get_var("orchestrator")
		var check_task = bt_player.blackboard.get_var("current_task")
		var check_mode_manager = bt_player.blackboard.get_var("mode_manager")
		
		if not check_orchestrator or not check_task:
			_handle_processing_error("Failed to set blackboard variables", task)
			return
		
		print("A1Agent: ✓ Blackboard variables verified:")
		print("  - orchestrator: ", check_orchestrator != null)
		print("  - current_task: ", check_task != null, " (", check_task.core_idea if check_task else "null", ")")
		print("  - mode_manager: ", check_mode_manager != null, " (", check_mode_manager.get_current_mode() if check_mode_manager else "null", ")")
		
		# Start execution with timeout monitoring
		bt_player.restart()
		task_progress_updated.emit(task, 10.0, "Processing with AI...")
		print("A1Agent: ✓ Behavior tree started with task: ", task.core_idea)
		
		# Set up comprehensive monitoring
		_setup_enhanced_task_monitoring()
	else:
		_handle_processing_error("Blackboard not available!", task)

func _populate_task_queue():
	"""Populate task queue with pending tasks for batch processing"""
	var orchestrator = ReadyMadeOrchestrator
	if not orchestrator:
		return
	
	var pending_tasks = orchestrator.workplan.get_tasks_by_status("To Do")
	for task in pending_tasks:
		if task not in task_queue and task != current_task:
			task_queue.append(task)
	
	queue_status_changed.emit(task_queue.size())
	print("A1Agent: 📋 Task queue populated with ", task_queue.size(), " tasks")

func _handle_processing_error(error_message: String, task: WorkplanTask):
	"""Handle processing errors with retry logic and recovery"""
	last_error = error_message
	processing_error.emit(error_message)
	print("A1Agent: ❌ Processing error: ", error_message)
	
	# Update performance metrics
	performance_metrics.tasks_failed += 1
	_update_success_rate()
	
	if retry_count < max_retries:
		retry_count += 1
		error_recovery_active = true
		print("A1Agent: 🔄 Attempting retry ", retry_count, "/", max_retries)
		
		# Wait before retry with exponential backoff
		var retry_delay = pow(2, retry_count - 1) * 2.0  # 2, 4, 8 seconds
		await _safe_wait(retry_delay)
		
		task_progress_updated.emit(task, 0.0, "Retrying... (attempt %d/%d)" % [retry_count, max_retries])
		_start_task_processing(task)
	else:
		print("A1Agent: 💥 Max retries exceeded, marking task as failed")
		task.status = "Review"  # Send to review instead of leaving in limbo
		task.notes += "\n\n[PROCESSING FAILED]: " + error_message
		
		var orchestrator = ReadyMadeOrchestrator
		if orchestrator:
			orchestrator.update_task(task)
		
		task_completed.emit(task, false)
		_finish_current_task()

func _finalize_processing_session():
	"""Clean up after processing session ends"""
	processing_active = false
	current_task = null
	error_recovery_active = false
	
	print("A1Agent: 📊 Session complete - Success rate: %.1f%%" % performance_metrics.success_rate)
	print("A1Agent: 📈 Tasks completed: %d, Failed: %d" % [performance_metrics.tasks_completed, performance_metrics.tasks_failed])

func _setup_enhanced_task_monitoring():
	"""Enhanced monitoring with timeout, progress tracking, and performance metrics"""
	# Clean up existing timer
	if completion_timer:
		completion_timer.queue_free()
	
	completion_timer = Timer.new()
	add_child(completion_timer)
	completion_timer.wait_time = 2.0  # Check every 2 seconds for more responsive monitoring
	completion_timer.timeout.connect(_enhanced_task_check)
	completion_timer.start()

func _enhanced_task_check():
	"""Enhanced task monitoring with timeout detection and progress tracking"""
	if not processing_active or not current_task:
		return
	
	# Calculate elapsed time and progress
	var current_time = Time.get_time_dict_from_system().hour * 3600 + Time.get_time_dict_from_system().minute * 60 + Time.get_time_dict_from_system().second
	var elapsed_time = current_time - processing_start_time
	
	# Check for timeout
	if elapsed_time > max_processing_time:
		print("A1Agent: ⏰ Task timeout after ", elapsed_time, " seconds")
		_handle_processing_error("Task processing timeout", current_task)
		return
	
	# Update progress based on elapsed time and status
	var progress_percent = min(90.0, (elapsed_time / max_processing_time) * 100.0)
	var status_message = "Processing... (%.0fs elapsed)" % elapsed_time
	
	# Check if task is completed
	if current_task.status == "Done":
		print("A1Agent: ✅ Task completed: ", current_task.core_idea)
		_record_successful_completion(elapsed_time)
		task_progress_updated.emit(current_task, 100.0, "Completed successfully!")
		task_completed.emit(current_task, true)
		_finish_current_task()
	elif current_task.status == "Review":
		# Task moved to review - might be an error state
		if "[PROCESSING FAILED]" in current_task.notes:
			print("A1Agent: ❌ Task failed and moved to review: ", current_task.core_idea)
			task_completed.emit(current_task, false)
			_finish_current_task()
		else:
			# Normal review state
			task_progress_updated.emit(current_task, 95.0, "Moved to review")
	else:
		# Task still in progress - emit progress update
		match current_task.status:
			"In Progress":
				task_progress_updated.emit(current_task, progress_percent, status_message)
			"To Do":
				# Task might be stuck - check if it's been too long
				if elapsed_time > 30.0:  # 30 seconds without starting
					_handle_processing_error("Task failed to start processing", current_task)

func _record_successful_completion(processing_time: float):
	"""Record successful task completion for performance metrics"""
	performance_metrics.tasks_completed += 1
	performance_metrics.total_processing_time += processing_time
	performance_metrics.average_processing_time = performance_metrics.total_processing_time / performance_metrics.tasks_completed
	_update_success_rate()
	
	print("A1Agent: 📊 Task completed in %.1fs (avg: %.1fs)" % [processing_time, performance_metrics.average_processing_time])

func _update_success_rate():
	"""Update success rate calculation"""
	var total_attempts = performance_metrics.tasks_completed + performance_metrics.tasks_failed
	if total_attempts > 0:
		performance_metrics.success_rate = (float(performance_metrics.tasks_completed) / float(total_attempts)) * 100.0

func _finish_current_task():
	"""Clean up after current task and start next one"""
	# Clean up current processing
	processing_active = false
	current_task = null
	error_recovery_active = false
	retry_count = 0
	
	# Stop current behavior tree
	if bt_player:
		bt_player.set_active(false)
	
	# Clean up timer
	if completion_timer:
		completion_timer.queue_free()
		completion_timer = null
	
	# Wait a moment then start next task
	await _safe_wait(1.0)
	execute_next_task()

# Performance and status methods
func get_performance_metrics() -> Dictionary:
	"""Get current performance metrics"""
	return performance_metrics.duplicate()

func get_queue_status() -> Dictionary:
	"""Get current queue status"""
	return {
		"queue_size": task_queue.size(),
		"current_task": current_task.core_idea if current_task else "",
		"is_processing": processing_active,
		"retry_count": retry_count,
		"last_error": last_error
	}

func get_detailed_status() -> Dictionary:
	"""Get comprehensive agent status"""
	var status = {
		"is_processing": processing_active,
		"current_task": current_task.core_idea if current_task else "",
		"queue_size": task_queue.size(),
		"retry_count": retry_count,
		"max_retries": max_retries,
		"last_error": last_error,
		"error_recovery_active": error_recovery_active,
		"performance": performance_metrics.duplicate()
	}
	
	if current_task and processing_active:
		var current_time = Time.get_time_dict_from_system().hour * 3600 + Time.get_time_dict_from_system().minute * 60 + Time.get_time_dict_from_system().second
		var elapsed_time = current_time - processing_start_time
		status["processing_time"] = elapsed_time
		status["timeout_in"] = max_processing_time - elapsed_time
	
	return status

func process_specific_task(task: WorkplanTask):
	"""Process a specific task immediately, bypassing the queue"""
	print("A1Agent: 🎯 Processing specific task: ", task.title)
	
	# If currently processing, stop and queue the current task
	if processing_active and current_task and current_task != task:
		print("A1Agent: ⏸️ Interrupting current task to process priority task")
		# Add current task back to front of queue
		task_queue.push_front(current_task)
		queue_status_changed.emit(task_queue.size())
		
		# Stop current processing
		if bt_player:
			bt_player.set_active(false)
		if completion_timer:
			completion_timer.queue_free()
			completion_timer = null
	
	# Start processing the specific task immediately
	_start_task_processing(task)

func prioritize_task(task: WorkplanTask):
	"""Add a task to the front of the processing queue"""
	if task in task_queue:
		# Remove from current position
		task_queue.erase(task)
	
	# Add to front of queue
	task_queue.push_front(task)
	queue_status_changed.emit(task_queue.size())
	print("A1Agent: ⬆️ Task prioritized: ", task.title, " (queue size: ", task_queue.size(), ")")

func add_task_to_queue(task: WorkplanTask):
	"""Add a task to the end of the processing queue"""
	if task not in task_queue:
		task_queue.append(task)
		queue_status_changed.emit(task_queue.size())
		print("A1Agent: ➕ Task added to queue: ", task.title, " (queue size: ", task_queue.size(), ")")

func clear_queue():
	"""Clear the task queue"""
	var queue_size = task_queue.size()
	task_queue.clear()
	queue_status_changed.emit(0)
	print("A1Agent: 🗑️ Cleared ", queue_size, " tasks from queue")

func get_queue_tasks() -> Array[WorkplanTask]:
	"""Get copy of current task queue"""
	return task_queue.duplicate()

func start_batch_processing():
	"""Start batch processing of all available tasks"""
	print("A1Agent: 🚀 Starting batch processing...")
	
	# Populate the queue with all pending tasks
	_populate_task_queue()
	
	# Start processing if not already running
	if not processing_active:
		execute_next_task()
	else:
		print("A1Agent: Already processing - batch queue populated with ", task_queue.size(), " tasks")

func execute_all_tasks():
	"""Execute all pending tasks in sequence (alias for start_batch_processing)"""
	start_batch_processing()

# Helper methods
func _safe_wait(delay: float):
	"""Safely wait for a specified delay, handling cases where node might not be in scene tree"""
	if not is_inside_tree():
		print("A1Agent: ⚠️ Node not in scene tree, using fallback timer")
		# Use a manual timer as fallback
		var start_time = Time.get_time_dict_from_system()
		var target_time = start_time.hour * 3600 + start_time.minute * 60 + start_time.second + delay
		
		while true:
			var current_time = Time.get_time_dict_from_system()
			var elapsed = current_time.hour * 3600 + current_time.minute * 60 + current_time.second
			if elapsed >= target_time:
				break
			if get_tree():
				await get_tree().process_frame
			else:
				await Engine.get_main_loop().process_frame
		return
	
	# Normal case - node is in scene tree
	var tree = get_tree()
	if tree:
		await tree.create_timer(delay).timeout
	else:
		print("A1Agent: ⚠️ No scene tree available, skipping wait")
		return
