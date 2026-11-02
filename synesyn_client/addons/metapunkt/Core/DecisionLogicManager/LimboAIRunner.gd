# ------------------------------------------------------------------------------
# DEVELOPER NOTES: LimboAI BTPlayer Integration Architecture
# ------------------------------------------------------------------------------
# This script represents the culmination of a significant debugging effort, and
# its current structure is critical for stability. Please read these notes
# before making significant changes.
#
# 1. INHERITANCE IS KEY: This script `extends BTPlayer` directly, rather than
#    `extends Node` and holding a BTPlayer as a child.
#    - WHY: Early attempts to manage a child BTPlayer node led to persistent
#      and difficult-to-diagnose Godot lifecycle issues. The child node's
#      `_ready()` function would execute at the wrong time, it couldn't find
#      its owner ("agent"), and its internal BehaviorTree instance would fail
#      to initialize. By making this runner *BE* the BTPlayer, we let Godot
#      manage its lifecycle correctly, which solves these problems entirely.
#
# 2. THE `set_scene_root_hint()` IS NOT OPTIONAL: For any BTPlayer that is
#    instantiated dynamically (as this one is by the DecisionLogicManager),
#    LimboAI's C++ backend often cannot determine the scene root automatically.
#    - THE FIX: We MUST manually provide this hint. Critically, this must be
#      done *BEFORE* the `.behavior_tree` property is assigned. Assigning the
#      resource is the trigger for the internal BTInstance to be created, and
#      it needs the hint *before* that happens.
#    - SYMPTOM OF FAILURE: If the hint is missing or called too late, you will
#      get the error: "BTPlayer doesn't have a behavior tree with a valid root
#      task to execute", even if you've loaded the resource correctly. This is
#      because the internal `bt_instance` remains null.
#
# 3. DEPENDENCY INJECTION PATTERN: The managers (AgentManager,
#    DecisionLogicManager) use a two-phase initialization (`.new()` then
#    `setup(...)`).
#    - WHY: This was implemented to solve a circular dependency issue that
#      arose during testing, where Manager A needed Manager B at the same time
#      Manager B needed Manager A. Instantiating all objects first and then
#      calling `setup()` to wire them together breaks this cycle.
# ------------------------------------------------------------------------------

extends BTPlayer
class_name LimboAIRunner

# --- Utility Methods ---
# Moved to top to potentially resolve parsing issues
func _log_audit(event_type: String, data: Dictionary, user_id: String = "system"):
	if audit_logger:
		audit_logger.log_event(event_type, data, user_id)
	else:
		print("[Audit Stub - %s]: %s (User: %s)" % [event_type, data, user_id if user_id else "N/A"])

# This script now IS A BTPlayer, adapted to the Metapunkt runner interface.

# Internal status matching the template runners
enum Status { RUNNING, SUCCESS, FAILURE }

# --- Dependencies (Injected via setup) ---
var agent_instance # : AgentInstance
var action_dispatcher # : ActionDispatcher
var sensor_interface # : SensorInterface
var audit_logger # : AuditLogger

# --- State ---
var current_status: Status = Status.FAILURE # Default status if not loaded/running
var is_active: bool = false
var last_bt_status: int = -1

# --- Initialization --- 
func setup(p_agent_instance, p_action_dispatcher, p_sensor_interface, p_audit_logger):
	agent_instance = p_agent_instance
	action_dispatcher = p_action_dispatcher
	sensor_interface = p_sensor_interface
	audit_logger = p_audit_logger
	if not agent_instance or not action_dispatcher or not sensor_interface:
		push_error("LimboAIRunner setup failed due to missing dependencies.")
		return false
	return true

# Called by the engine when the BTPlayer's status is updated.
func _on_bt_player_updated(status: int):
	last_bt_status = status
	match status:
		BT.Status.FRESH: current_status = Status.FAILURE  # Initial state, not yet started
		BT.Status.RUNNING: current_status = Status.RUNNING
		BT.Status.SUCCESS: current_status = Status.SUCCESS
		BT.Status.FAILURE: current_status = Status.FAILURE
		_:
			push_warning("LimboAIRunner received unexpected status from BTPlayer: %s" % status)
			current_status = Status.FAILURE

# --- Public API (Runner Interface) ---

func load_behavior_tree(config: Dictionary) -> bool:
	if not agent_instance:
		push_error("Cannot load tree: Runner not setup correctly.")
		return false
	
	var bt_resource_path = config.get("path", "")
	if bt_resource_path.is_empty():
		push_error("LimboAI BT load failed for %s: Missing 'path' in config" % agent_instance.agent_id)
		return false
		
	# Check if the file exists first
	if not FileAccess.file_exists(bt_resource_path):
		push_error("LimboAI BehaviorTree file does not exist: %s" % bt_resource_path)
		return false
	
	var new_behavior_tree = load(bt_resource_path)
	
	if not new_behavior_tree:
		push_error("Failed to load resource from path: %s (returned null)" % bt_resource_path)
		return false
	
	if not new_behavior_tree is BehaviorTree:
		push_error("Failed to load LimboAI BehaviorTree resource: %s (wrong type: %s)" % [bt_resource_path, new_behavior_tree.get_class()])
		return false
	
	if not new_behavior_tree.root_task:
		push_error("LimboAI BehaviorTree has no root task: %s" % bt_resource_path)
		return false
	
	# --- Configure self (as BTPlayer) ---

	# CRITICAL FIX: Ensure proper scene tree context BEFORE assigning the behavior_tree.
	# Set the owner to help LimboAI understand the scene context
	if get_parent():
		owner = get_parent()
	
	# Alternative scene root hint - try multiple approaches
	var scene_tree: SceneTree = Engine.get_main_loop()
	if scene_tree and scene_tree.current_scene:
		var root_hint: Node = scene_tree.current_scene
		
		# Try the newer method first
		if self.has_method("set_scene_root_hint"):
			self.set_scene_root_hint(root_hint)
		else:
			# Fallback - ensure we're properly connected to scene tree
			if not owner and get_parent():
				owner = get_parent()
	
	self.behavior_tree = new_behavior_tree
	
	# Ensure blackboard is created AFTER behavior tree assignment
	if not self.blackboard:
		self.blackboard = Blackboard.new()
		
	self.update_mode = BTPlayer.UpdateMode.MANUAL
	
	# Inject dependencies for custom tasks
	self.blackboard.set_var("agent_instance", agent_instance)
	self.blackboard.set_var("action_dispatcher", action_dispatcher)
	self.blackboard.set_var("sensor_interface", sensor_interface)
	self.blackboard.set_var("audit_logger", audit_logger)
	self.blackboard.set_var("short_term_memory", agent_instance.short_term_memory)
	
	# Connect the updated signal to our handler
	if not self.updated.is_connected(_on_bt_player_updated):
		self.updated.connect(_on_bt_player_updated)

	print("LimboAIRunner: Successfully loaded behavior tree for agent %s" % agent_instance.agent_id)
	_log_audit("limbo_loaded", {"agent_id": agent_instance.agent_id, "path": bt_resource_path}, "system")
	is_active = false
	return true

func start():
	if not self.behavior_tree:
		push_warning("Cannot start LimboAIRunner: No behavior tree loaded.")
		return
	
	# Now that this node is in the tree, restarting is safe and will create the BT instance.
	self.restart()
	
	if get_bt_instance() == null:
		push_error("LimboAIRunner.start(): BTPlayer restart failed - no valid BT instance created.")
		return

	is_active = true
	_log_audit("limbo_started", {"agent_id": agent_instance.agent_id}, "system")

func stop():
	is_active = false
	_log_audit("limbo_stopped", {"agent_id": agent_instance.agent_id}, "system")

func tick(delta: float) -> Status:
	if not is_active:
		return current_status
	
	if not get_bt_instance():
		push_warning("LimboAIRunner tick(): No valid BT instance to tick.")
		return Status.FAILURE

	# This will execute the behavior tree and emit the 'updated' signal.
	self.update(delta)
	
	return current_status
