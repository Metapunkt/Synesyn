extends Node # Needs to be a Node if using process loop or timers, or just Object?
# class_name BehaviorTreeRunner # Renamed!
class_name BehaviorTreeRunner_Template

# --- TEMPLATE WARNING --- #
# This script serves as a TEMPLATE for implementing a specific Behavior Tree (BT) library runner.
# It makes HYPOTHETICAL assumptions about how a BT resource is structured and executed 
# (e.g., a Resource with a tick(context) method).
# 
# TO USE A REAL BT LIBRARY:
# 1. Create a NEW script (e.g., PineBTRunner.gd, GDXProtoBTRunner.gd).
# 2. This new script should ideally inherit from a common BaseLogicRunner class (not yet defined)
#    OR implement a standard interface defined by Metapunkt (e.g., setup, load, tick, stop methods).
# 3. Adapt the methods below (especially load_tree and tick) to match the specific API 
#    of your chosen BT library.
# 4. Update DecisionLogicManager to map the library's name (e.g., "pinebt") to your new runner script.
# --- END TEMPLATE WARNING --- #

enum Status { RUNNING, SUCCESS, FAILURE }

# Integrates Godot-native or addon BTs (TEMPLATE - Requires Adaptation).

# --- Dependencies (Set via setup method) ---
var agent_instance # : AgentInstance
var action_dispatcher # : ActionDispatcher
var sensor_interface # : SensorInterface
# var short_term_memory # : ShortTermMemory - Or access via agent_instance.blackboard?
var audit_logger # : AuditLogger

# --- Configuration ---
var behavior_tree_resource: Resource # The loaded .tres BT resource

# --- State ---
var current_status: Status = Status.FAILURE # Default status if no tree loaded
var is_active: bool = false

# --- Initialization --- 
# Using setup instead of init to allow for deferred dependency injection
func setup(p_agent_instance, p_action_dispatcher, p_sensor_interface, p_audit_logger):
	agent_instance = p_agent_instance
	action_dispatcher = p_action_dispatcher
	sensor_interface = p_sensor_interface
	audit_logger = p_audit_logger
	# Validate crucial dependencies
	if not agent_instance:
		push_error("BehaviorTreeRunner setup without AgentInstance!")
		return false
	if not action_dispatcher:
		push_error("BehaviorTreeRunner setup without ActionDispatcher!")
		return false
	if not sensor_interface:
		push_error("BehaviorTreeRunner setup without SensorInterface!")
		return false
	return true

# --- Public API --- 

# Loads the Behavior Tree resource (ADAPT FOR SPECIFIC LIBRARY)
func load_tree(bt_resource_path: String) -> bool:
	if not agent_instance:
		push_error("Cannot load tree: Runner not setup correctly (missing agent instance).")
		return false
		
	behavior_tree_resource = load(bt_resource_path)
	# --- ADAPTATION POINT: Resource Loading & Validation --- #
	if not behavior_tree_resource:
		_log_audit("bt_load_error", {"agent_id": agent_instance.agent_id, "path": bt_resource_path, "error": "Resource not found or failed to load"}, agent_instance.agent_id if agent_instance else "unknown_agent")
		push_error("Failed to load Behavior Tree resource: %s" % bt_resource_path)
		behavior_tree_resource = null # Ensure it's null if loading failed
		current_status = Status.FAILURE
		return false
	
	# *** REPLACE THIS CHECK with validation specific to your BT library ***
	# Example: Check class name, required properties, etc.
	if not behavior_tree_resource.has_method("tick"): # Hypothetical check
		_log_audit("bt_load_error", {"agent_id": agent_instance.agent_id, "path": bt_resource_path, "error": "Invalid BT resource format (missing tick method?)"}, agent_instance.agent_id if agent_instance else "unknown_agent")
		push_error("Invalid Behavior Tree resource format: %s (does it have a 'tick' method?)" % bt_resource_path)
		behavior_tree_resource = null
		current_status = Status.FAILURE
		return false
	# --- END ADAPTATION POINT --- #

	_log_audit("bt_loaded", {"agent_id": agent_instance.agent_id, "path": bt_resource_path}, agent_instance.agent_id if agent_instance else "system")
	print("Behavior Tree loaded for agent %s: %s" % [agent_instance.agent_id, bt_resource_path])
	current_status = Status.SUCCESS # Ready to run, indicate initial success/idle state
	is_active = false # Start inactive
	return true

# Starts or resumes the execution of the tree
func start():
	if not behavior_tree_resource:
		push_warning("Cannot start BT Runner for agent %s: No behavior tree loaded." % agent_instance.agent_id)
		return
	is_active = true
	print("Behavior Tree Runner started for agent %s" % agent_instance.agent_id)

# Stops the execution of the tree
func stop():
	is_active = false
	print("Behavior Tree Runner stopped for agent %s" % agent_instance.agent_id)
	# TODO: Reset BT state if necessary?

# Executes one tick of the behavior tree (ADAPT FOR SPECIFIC LIBRARY)
func tick(delta: float) -> Status:
	if not is_active or not behavior_tree_resource or not agent_instance:
		return current_status # Return last known status if not active or ready
	
	# --- Prepare Context for BT Nodes --- #
	# This context dictionary might need to be adapted based on how the BT library 
	# makes information available to its nodes.
	var context = {
		"agent": agent_instance,
		"blackboard": agent_instance.blackboard,
		"action_dispatcher": action_dispatcher,
		"sensor_interface": sensor_interface,
		"delta": delta,
		"audit_logger": audit_logger,
	}

	# --- Execute the Tree (ADAPTATION POINT) --- #
	# Removed invalid try/except block
	# *** REPLACE THIS CALL with the actual tick/run method of your BT library ***
	# Pass the context dictionary or individual dependencies as required by the library.
	var result_status = behavior_tree_resource.tick(context) # Hypothetical call
		
	# *** REPLACE THIS MATCH with conversion from library status to internal Status enum ***
	match result_status: 
		# Example: Assuming BT library uses 0=RUNNING, 1=SUCCESS, 2=FAILURE
		# and that tick() returns one of these or a specific error indicator.
		0: current_status = Status.RUNNING 
		1: current_status = Status.SUCCESS 
		2: current_status = Status.FAILURE
		# Add checks here for specific error values your BT library might return
		# For example, if it returns -1 on an internal error:
		# -1: 
		# 	 var err_msg = "Error during BT execution for agent %s (BT returned error code)." % agent_instance.agent_id
		# 	 _log_audit("bt_execution_error", {"agent_id": agent_instance.agent_id, "error": err_msg}, "system")
		# 	 printerr(err_msg)
		# 	 current_status = Status.FAILURE
		# 	 stop() # Stop execution on error
		_: 
			push_warning("Agent %s BT returned unknown status: %s. Assuming FAILURE." % [agent_instance.agent_id, result_status])
			current_status = Status.FAILURE
	
	# --- END ADAPTATION POINT --- #
	
	# If the tree finished (Success or Failure), potentially stop the runner
	if current_status == Status.SUCCESS or current_status == Status.FAILURE:
		# Decide if it should automatically stop or wait to be started again
		# stop()
		pass 

	return current_status


# --- Utility Methods ---
func _log_audit(event_type: String, data: Dictionary, user_id: String):
	if audit_logger:
		audit_logger.log_event(event_type, data, user_id)
	else:
		print("[Audit Stub - %s]: %s (User: %s)" % [event_type, data, user_id if user_id else "N/A"]) 