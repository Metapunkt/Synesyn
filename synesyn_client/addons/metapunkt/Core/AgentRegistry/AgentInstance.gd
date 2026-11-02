extends Object # Or Node? Needs careful consideration if it needs SceneTree access or signals
class_name AgentInstance

# Preloads
const AgentDefinition = preload("res://addons/metapunkt/Core/AgentRegistry/AgentDefinition.gd")
# Removed preload for LimboTask - Assuming it's a global class from GDExtension
# const LimboTask = preload("res://addons/limboai/tasks/limbo_task.gd")

enum Status { CREATED, INITIALIZING, IDLE, RUNNING, WAITING_FOR_ACTION, COMPLETED, ERROR }

# Runtime representation of an active agent.
# Includes optional owner_user_id.

# --- Configuration ---
var definition: AgentDefinition
var agent_id: String = ""
var owner_user_id: String = ""

# --- State ---
var current_status: Status = Status.CREATED
var status_message: String = "Agent created but not initialized."
var current_action_id: String = "" # ID of the action currently being executed (if async)
var blackboard: Dictionary = {} # Agent-specific memory/state

# Synterfaces/Bindings (v1): populated during spawn if AgentDefinition.required_synterfaces is non-empty.
var bound_ports: Dictionary = {}

# --- Dependencies (Set via setup or DI) ---
var action_dispatcher # : ActionDispatcher
var sensor_interface # : SensorInterface
var short_term_memory # : ShortTermMemory
var logic_runner # Instance of BehaviorTreeRunner, StateMachineRunner, etc.
var decision_logic_manager # : DecisionLogicManager (needed to assign logic?)


func _init(p_agent_id: String = "", p_owner_id: String = "", p_definition: AgentDefinition = null):
	agent_id = p_agent_id
	owner_user_id = p_owner_id
	if p_definition:
		set_definition(p_definition)
	else:
		set_status(Status.ERROR, "Agent created without a definition.")

# Setup dependencies (alternative to passing everything in init)
func setup_dependencies(p_action_dispatcher, p_sensor_interface, p_stm, p_dlm):
	action_dispatcher = p_action_dispatcher
	sensor_interface = p_sensor_interface
	short_term_memory = p_stm
	decision_logic_manager = p_dlm
	# Basic validation
	if not action_dispatcher or not sensor_interface or not short_term_memory or not decision_logic_manager:
		push_error("Agent %s failed dependency setup!" % agent_id)
		set_status(Status.ERROR, "Missing core dependencies during setup.")
		return false
	return true

# --- Public Methods ---

func set_definition(p_definition: AgentDefinition):
	if not p_definition is AgentDefinition:
		set_status(Status.ERROR, "Invalid definition provided.")
		push_error("Agent %s: Invalid definition provided." % agent_id)
		return
	
	definition = p_definition
	set_status(Status.INITIALIZING, "Definition set, ready for initialization.")
	# TODO: Load BT/FSM/Policy specified in definition
	# TODO: Identify required tools from definition
	print("Agent %s: Set definition '%s'" % [agent_id, definition.resource_path if definition else "None"])

func initialize_state():
	if current_status != Status.INITIALIZING:
		push_warning("Agent %s: Cannot initialize state, current status is %s" % [agent_id, Status.keys()[current_status]])
		return
	if not definition:
		set_status(Status.ERROR, "Cannot initialize: Definition not set.")
		return
	if not decision_logic_manager:
		set_status(Status.ERROR, "Cannot initialize: DecisionLogicManager not set.")
		return

	print("Agent %s: Initializing state based on definition: %s" % [agent_id, definition.resource_path])
	
	# --- Assign Decision Logic --- 
	# Get logic type and config FROM the definition resource
	var logic_type: String = definition.logic_type
	var logic_config: Dictionary = definition.logic_config
	
	if logic_type.is_empty():
		set_status(Status.ERROR, "Cannot initialize: Agent definition is missing 'logic_type'.")
		_log_audit("agent_init_error", {"agent_id": agent_id, "error": "Missing logic_type in definition"}, owner_user_id)
		return

	# Pass self (the AgentInstance) to assign_logic_to_agent
	var assigned = decision_logic_manager.assign_logic_to_agent(self, logic_type, logic_config)
	if assigned:
		logic_runner = decision_logic_manager.get_agent_runner(agent_id)
		if logic_runner:
			print("Agent %s: Logic runner (%s) assigned." % [agent_id, logic_runner.get_class()])
			
			# If the runner is a Node, it needs to be ready before we start it.
			if logic_runner is Node:
				if not logic_runner.is_node_ready():
					await logic_runner.ready
			
			# Start the runner?
			if logic_runner.has_method("start"): 
				logic_runner.start()
				set_status(Status.IDLE, "Initialization complete, logic started.")
			else:
				set_status(Status.IDLE, "Initialization complete, runner has no start method.")
		else:
			set_status(Status.ERROR, "Failed to retrieve assigned logic runner after assignment.")
			_log_audit("agent_init_error", {"agent_id": agent_id, "error": "Failed to get assigned runner"}, owner_user_id)
			return
	else:
		set_status(Status.ERROR, "Failed to assign decision logic based on definition.")
		_log_audit("agent_init_error", {"agent_id": agent_id, "error": "assign_logic_to_agent failed"}, owner_user_id)
		return
	
	# TODO: Set up blackboard based on definition.capabilities or other fields?
	# TODO: Connect to sensors based on definition.required_sensors (add field?)
	
	print("Agent %s: State initialized." % agent_id)

func set_status(new_status: Status, message: String = ""):
	if new_status == current_status and message == status_message:
		return # No change
	
	var old_status = Status.keys()[current_status]
	current_status = new_status
	status_message = message if message else "Status changed to %s" % Status.keys()[current_status]
	print("Agent %s: Status changed from %s to %s (%s)" % [agent_id, old_status, Status.keys()[current_status], status_message])
	# TODO: Emit a signal? ("status_changed")

func get_status_info() -> Dictionary:
	return {
		"status_code": current_status,
		"status_name": Status.keys()[current_status],
		"message": status_message,
		"current_action_id": current_action_id
	}

# Agent's main loop - called externally (e.g., by a central AgentManager node)
func tick(delta):
	# Only tick if in a runnable state and logic is assigned
	if (current_status == Status.RUNNING or current_status == Status.IDLE) and logic_runner:
		if logic_runner.has_method("tick"):
			# The runner's tick should return its internal Status enum (RUNNING, SUCCESS, FAILURE)
			# Keep this robust: avoid parse-time dependencies on LimboAI classes.
			var runner_internal_status = logic_runner.tick(delta)
			
			# Update agent status based on runner status
			match _normalize_runner_status(runner_internal_status):
				"running":
					set_status(Status.RUNNING)
				"success":
					set_status(Status.IDLE, "Logic execution successful.")
				"failure":
					set_status(Status.IDLE, "Logic execution failed.") # Or ERROR?
				_:
					# Unknown runner status: keep agent stable, but report.
					set_status(Status.IDLE, "Logic returned unknown status: %s" % str(runner_internal_status))
			# No need to reference BehaviorTreeRunner here anymore
			
		else:
			push_warning("Agent %s: Logic runner has no tick method." % agent_id)
			set_status(Status.ERROR, "Logic runner is invalid.")
	# else: Agent is not in a state to be ticked (e.g., INITIALIZING, ERROR, COMPLETED)

func _normalize_runner_status(v) -> String:
	# Normalize runner status into: "running" | "success" | "failure"
	# Common cases:
	# - LimboAIRunner.Status enum: 0/1/2
	# - Strings: "RUNNING"/"SUCCESS"/"FAILURE"
	if typeof(v) == TYPE_INT:
		match int(v):
			0:
				return "running"
			1:
				return "success"
			2:
				return "failure"
			_:
				return "unknown"
	if typeof(v) == TYPE_STRING:
		var s := str(v).strip_edges().to_lower()
		if s == "running":
			return "running"
		if s == "success":
			return "success"
		if s == "failure" or s == "failed":
			return "failure"
		return "unknown"
	return "unknown"

# Called when an action needs to be performed (e.g., by a BT action node via context)
func request_action(tool_name: String, args: Dictionary) -> Dictionary:
	if not action_dispatcher:
		push_error("Agent %s: ActionDispatcher not set." % agent_id)
		return {"error": "ActionDispatcher not available", "status_code": 500}

	set_status(Status.WAITING_FOR_ACTION, "Requesting action: %s" % tool_name)
	var dispatch_result = await action_dispatcher.dispatch_action(agent_id, tool_name, args, owner_user_id, []) # TODO: Pass actual scopes
	
	# If action was async, store task ID and stay WAITING?
	if dispatch_result.has("task_id"):
		current_action_id = dispatch_result["task_id"]
		# Status remains WAITING_FOR_ACTION until task completes
	else:
		# Action was sync, return to IDLE (or RUNNING?)
		current_action_id = ""
		set_status(Status.IDLE, "Synchronous action complete.") 
		
	return dispatch_result

func shutdown():
	set_status(Status.COMPLETED, "Shutdown requested.")
	# TODO: Clean up resources, stop runners, etc.
	print("Agent %s: Shutdown complete." % agent_id)
	# Stop logic runner if it exists
	if logic_runner and logic_runner.has_method("stop"):
		logic_runner.stop()
	logic_runner = null # Release reference 

# --- Utility Methods ---
func _log_audit(event_type: String, data: Dictionary, user_id: String):
	# Forward to a potential audit_logger dependency if needed, 
	# or rely on DLM/ActionDispatcher logging for now.
	# if audit_logger: audit_logger.log_event(event_type, data, user_id)
	print("[Agent Audit Stub - %s]: %s (User: %s)" % [event_type, data, user_id if user_id else "N/A"]) 