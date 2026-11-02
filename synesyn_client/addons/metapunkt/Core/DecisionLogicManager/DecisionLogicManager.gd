extends Object # Or Node if it needs to run ticks
class_name DecisionLogicManager

# Configures & manages agent decision logic (BTs, FSMs, Policies).
# Implements SLOP /models endpoint logic.

# --- Runner Script Paths (Used for dynamic loading) ---
# This dictionary maps logic_type strings to the script paths of their runners.
# Add entries here when creating new runner adapters.
const RUNNER_SCRIPTS = {
	"behaviortree": "res://addons/metapunkt/Core/DecisionLogicManager/BehaviorTreeRunner_Template.gd",
	"bt": "res://addons/metapunkt/Core/DecisionLogicManager/BehaviorTreeRunner_Template.gd", # Alias
	"statemachine": "res://addons/metapunkt/Core/DecisionLogicManager/StateMachineRunner_Template.gd", # Use Template
	"fsm": "res://addons/metapunkt/Core/DecisionLogicManager/StateMachineRunner_Template.gd", # Alias
	"policy": "res://addons/metapunkt/Core/DecisionLogicManager/PolicyLoader_Template.gd", # Use Template
	# Add the mapping for LimboAI:
	"limboai": "res://addons/metapunkt/Core/DecisionLogicManager/LimboAIRunner.gd",
	# Example for a specific library:
	# "pinebt": "res://addons/metapunkt/Integrations/PineBTRunner.gd", 
}

# --- Dependencies ---
var action_dispatcher # : ActionDispatcher
var sensor_interface # : SensorInterface
var audit_logger # : AuditLogger
var runner_parent_node: Node # NEW: Parent for runner nodes

# --- Internal State ---
var _agent_runners: Dictionary = {} # agent_id -> RunnerInstance

# --- Initialization ---
func _init(p_action_dispatcher = null, p_audit_logger = null, p_sensor_interface = null, p_runner_parent: Node = null):
	# Removed agent_registry from constructor parameters
	action_dispatcher = p_action_dispatcher
	audit_logger = p_audit_logger
	sensor_interface = p_sensor_interface
	runner_parent_node = p_runner_parent
	# if not agent_registry: # Removed check
	# 	push_error("DecisionLogicManager initialized without AgentRegistry!")
	if not action_dispatcher:
		push_error("DecisionLogicManager initialized without ActionDispatcher!")
	if not sensor_interface:
		push_error("DecisionLogicManager initialized without SensorInterface!")
	if not runner_parent_node:
		push_error("DecisionLogicManager initialized without a runner_parent_node! Runners will not be added to the scene.")
	if not audit_logger:
		push_warning("DecisionLogicManager initialized without AuditLogger.")


# --- Public API (called by AgentInstance or a main loop) ---

# Assigns and initializes the appropriate logic runner for an agent
func assign_logic_to_agent(agent_instance: AgentInstance, logic_type: String, config: Dictionary) -> bool:
	if not agent_instance:
		_log_audit("logic_assignment_error", {"agent_id": "Unknown", "error": "Agent instance not provided"}, "system")
		push_error("Cannot assign logic: Agent instance not provided.")
		return false
	
	var agent_id = agent_instance.agent_id
	var type_lower = logic_type.to_lower()
	print("DecisionLogicManager: Assigning logic type '%s' to agent '%s'" % [logic_type, agent_id])

	# --- Dynamic Runner Loading --- 
	if not RUNNER_SCRIPTS.has(type_lower):
		_log_audit("logic_assignment_error", {"agent_id": agent_id, "error": "Unknown logic type: %s" % logic_type}, "system")
		push_error("Cannot assign logic for agent %s: Unknown logic type '%s'" % [agent_id, logic_type])
		return false
	
	var runner_script_path = RUNNER_SCRIPTS[type_lower]
	print("DecisionLogicManager: Loading runner script: ", runner_script_path)
	var runner_script = load(runner_script_path)
	if not runner_script:
		_log_audit("logic_assignment_error", {"agent_id": agent_id, "type": logic_type, "error": "Failed to load runner script: %s" % runner_script_path}, "system")
		push_error("Failed to load runner script for %s: %s" % [logic_type, runner_script_path])
		return false
	
	# --- Instantiate and Setup Runner --- 
	print("DecisionLogicManager: Instantiating runner...")
	var runner = runner_script.new()
	if not runner:
		_log_audit("logic_assignment_error", {"agent_id": agent_id, "type": logic_type, "error": "Failed to instantiate runner script"}, "system")
		push_error("Failed to instantiate runner script: %s" % runner_script_path)
		return false

	# Remove existing runner if present
	if _agent_runners.has(agent_id):
		var old_runner = _agent_runners[agent_id]
		_cleanup_runner(old_runner)
		_agent_runners.erase(agent_id)

	# CRITICAL FIX: Add LimboAI runners to scene tree BEFORE setup/loading
	# LimboAI BTPlayer needs to be in the scene tree before configuration
	if runner_parent_node and runner is Node and type_lower == "limboai":
		print("DecisionLogicManager: Adding LimboAI runner to scene tree...")
		runner_parent_node.add_child(runner)

	var success = false
	# Check if the runner needs setup (assuming a standard 'setup' method)
	if runner.has_method("setup"):
		print("DecisionLogicManager: Setting up runner dependencies...")
		if not runner.setup(agent_instance, action_dispatcher, sensor_interface, audit_logger):
			push_error("Failed to setup %s for agent %s" % [runner.get_class(), agent_id])
			_log_audit("logic_assignment_error", {"agent_id": agent_id, "type": logic_type, "error": "Runner setup failed"}, "system")
			# Cleanup partially setup runner if needed
			# if runner is Node: runner.queue_free()
			return false
	# else: Runner might not need setup or uses a different method - adapt as needed.

	# --- Load Logic Resource / Configure Runner --- 
	# Use different methods based on assumed runner type/interface
	# TODO: Define a BaseLogicRunner interface/class to standardize methods like load()
	var logic_path = config.get("path", "") # Common config parameter?
	var logic_config = config.get("config", config) # Pass full config if no path

	if runner.has_method("load_tree") and (type_lower == "behaviortree" or type_lower == "bt"):
		if logic_path.is_empty(): # BTs typically need a path
			_log_audit("logic_assignment_error", {"agent_id": agent_id, "type": logic_type, "error": "Missing logic path in config"}, "system")
			push_error("Logic assignment failed for %s: Missing 'path' in config" % agent_id)
			return false
		success = runner.load_tree(logic_path)
		if not success: push_error("Runner failed to load BT resource: %s" % logic_path)
		
	elif runner.has_method("load_behavior_tree") and type_lower == "limboai":
		# LimboAI specific method
		print("DecisionLogicManager: Loading behavior tree with config: ", config)
		success = runner.load_behavior_tree(config)
		if not success: 
			push_error("LimboAI Runner failed to load behavior tree from config: %s" % config)
		else:
			print("DecisionLogicManager: Behavior tree loaded successfully!")
		
	elif runner.has_method("load_fsm") and (type_lower == "statemachine" or type_lower == "fsm"):
		# FSM might use path or just config dictionary
		success = runner.load_fsm(logic_config)
		if not success: push_error("Runner failed to load/configure FSM.")
		
	elif runner.has_method("load_policy") and type_lower == "policy":
		# Policy likely uses config dictionary (API keys, model paths, etc.)
		success = runner.load_policy(logic_config)
		if not success: push_error("Runner failed to load/configure Policy.")
		
	else:
		# Fallback / Unknown runner type or load method
		push_warning("Runner %s for agent %s does not have a recognized load method (e.g., load_tree, load_behavior_tree, load_fsm, load_policy). Assuming setup was sufficient." % [runner.get_class(), agent_id])
		success = true # Assume setup is enough if no specific load method

	# --- Store Runner --- 
	if runner and success:
		_agent_runners[agent_id] = runner
		# Add non-LimboAI runners to the scene tree (LimboAI already added above)
		if runner_parent_node and runner is Node and type_lower != "limboai":
			runner_parent_node.add_child(runner)
		print("DecisionLogicManager: Successfully assigned logic for agent '%s'" % agent_id)
		_log_audit("logic_assigned", {"agent_id": agent_id, "type": logic_type, "runner_class": runner.get_class(), "config": config}, "system")
		# runner.start() # Optionally start automatically
		return true
	else:
		# Cleanup runner if creation/loading failed
		print("DecisionLogicManager: Failed to assign logic for agent '%s' - success: %s, runner: %s" % [agent_id, success, runner != null])
		if runner is Node and runner.get_parent():
			runner.queue_free()
		return false

func release_agent(agent_id: String) -> void:
	"""
	Release any runner state for an agent (used on agent deletion/cleanup).
	"""
	if not _agent_runners.has(agent_id):
		return
	var r = _agent_runners.get(agent_id)
	_cleanup_runner(r)
	_agent_runners.erase(agent_id)

func _cleanup_runner(runner: Variant) -> void:
	if runner == null:
		return
	if runner is Node:
		var n: Node = runner
		if n.has_method("stop"):
			n.stop()
		if is_instance_valid(n):
			n.queue_free()
	else:
		if runner is Object and runner.has_method("stop"):
			runner.stop()

# Gets the runner instance for a specific agent
func get_agent_runner(agent_id: String):
	return _agent_runners.get(agent_id)

# Executes a logic tick for a specific agent
# Now requires agent_instance for context if runner needs it (BT runner does)
func tick_agent_logic(agent_id: String, delta: float):
	var runner = _agent_runners.get(agent_id)
	if runner and runner.has_method("tick"):
		# No need to get agent_instance here if tick() is called from AgentInstance itself
		# var agent_instance = agent_registry.get_agent_instance(agent_id)
		var status = runner.tick(delta)
		# Optionally update agent status based on runner status?
		# match status:
		#     BehaviorTreeRunner.Status.RUNNING:
		#         agent_instance.set_status(AgentInstance.Status.RUNNING)
		#     BehaviorTreeRunner.Status.SUCCESS:
		#         agent_instance.set_status(AgentInstance.Status.IDLE, "BT Success") # Or COMPLETED?
		#     BehaviorTreeRunner.Status.FAILURE:
		#         agent_instance.set_status(AgentInstance.Status.IDLE, "BT Failure") # Or ERROR?
	# else: No logic assigned or runner has no tick method

# ... (SLOP Handlers: handle_request, _handle_get_model_types, _handle_assign_logic_request) ...

# --- Utility Methods ---
# Added missing utility method
func _log_audit(event_type: String, data: Dictionary, user_id: String):
	if audit_logger:
		audit_logger.log_event(event_type, data, user_id)
	else:
		print("[Audit Stub - %s]: %s (User: %s)" % [event_type, data, user_id if user_id else "N/A"])
 
