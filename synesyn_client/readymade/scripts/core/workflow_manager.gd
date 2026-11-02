extends Node

## ReadyMade Workflow Manager - Handles switching between different workflow modes
## This singleton manages workflow configurations and notifies UI components of workflow changes

signal workflow_changed(new_workflow: String)

# Available workflows
enum Workflow {
	TASK_MANAGEMENT,
	EDIT_SESSION,
	BRAINSTORM
}

# Workflow configuration mappings
var workflow_names: Dictionary = {
	Workflow.TASK_MANAGEMENT: "task_management",
	Workflow.EDIT_SESSION: "edit_session",
	Workflow.BRAINSTORM: "brainstorm"
}

var workflow_display_names: Dictionary = {
	Workflow.TASK_MANAGEMENT: "Task Management",
	Workflow.EDIT_SESSION: "Edit Session",
	Workflow.BRAINSTORM: "Brainstorm"
}

var current_workflow: int = Workflow.TASK_MANAGEMENT

func _ready():
	print("WorkflowManager: Initializing...")
	_load_user_preference()
	print("WorkflowManager: Ready with workflow: %s" % get_current_workflow_name())

func get_available_workflows() -> Array[String]:
	"""Get list of available workflow names"""
	var workflows: Array[String] = []
	for workflow_enum in workflow_names.keys():
		workflows.append(workflow_names[workflow_enum])
	return workflows

func get_workflow_display_names() -> Array[String]:
	"""Get list of workflow display names for UI"""
	var display_names: Array[String] = []
	for workflow_enum in workflow_display_names.keys():
		display_names.append(workflow_display_names[workflow_enum])
	return display_names

func set_workflow(workflow_name: String):
	"""Change the current workflow by name"""
	var target_workflow = _get_workflow_enum_by_name(workflow_name)
	
	if target_workflow == -1:
		push_error("WorkflowManager: Cannot set unknown workflow '%s'" % workflow_name)
		return
	
	if target_workflow == current_workflow:
		return # No change needed
	
	var old_workflow = current_workflow
	current_workflow = target_workflow
	
	print("WorkflowManager: Workflow changed from '%s' to '%s'" % [
		workflow_names[old_workflow], 
		workflow_names[current_workflow]
	])
	
	# Save preference and emit signal
	_save_user_preference()
	workflow_changed.emit(workflow_names[current_workflow])

func set_workflow_by_enum(workflow_enum):
	"""Change the current workflow by enum value"""
	set_workflow(workflow_names[workflow_enum])

func get_current_workflow() -> int:
	"""Get current workflow enum"""
	return current_workflow

func get_current_workflow_name() -> String:
	"""Get current workflow name"""
	return workflow_names[current_workflow]

func get_current_workflow_display_name() -> String:
	"""Get current workflow display name"""
	return workflow_display_names[current_workflow]

func _get_workflow_enum_by_name(workflow_name: String) -> int:
	"""Get workflow enum by name string"""
	for workflow_enum in workflow_names.keys():
		if workflow_names[workflow_enum] == workflow_name:
			return workflow_enum
	return -1  # Not found

func _get_workflow_enum_by_display_name(display_name: String) -> int:
	"""Get workflow enum by display name string"""
	for workflow_enum in workflow_display_names.keys():
		if workflow_display_names[workflow_enum] == display_name:
			return workflow_enum
	return -1  # Not found

func _load_user_preference():
	"""Load user's preferred workflow from project settings"""
	if ProjectSettings.has_setting("readymade/default_workflow"):
		var saved_workflow = ProjectSettings.get_setting("readymade/default_workflow", "task_management")
		var workflow_enum = _get_workflow_enum_by_name(saved_workflow)
		if workflow_enum != -1:
			current_workflow = workflow_enum
			print("WorkflowManager: Loaded user preference: %s" % saved_workflow)
		else:
			print("WorkflowManager: Invalid saved workflow '%s', using default" % saved_workflow)

func _save_user_preference():
	"""Save current workflow as user preference"""
	var workflow_name = workflow_names[current_workflow]
	ProjectSettings.set_setting("readymade/default_workflow", workflow_name)
	var err = ProjectSettings.save()
	if err != OK:
		push_error("WorkflowManager: Failed to save user preference: %s" % err)
	else:
		print("WorkflowManager: Saved user preference: %s" % workflow_name) 