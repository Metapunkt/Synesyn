extends Node
class_name AgentManager

# Iterates through active agents and calls their tick() method.

# --- Dependencies ---
var agent_registry # : AgentRegistry
var audit_logger # : AuditLogger

# --- Initialization ---
func _init():
	pass # Dependencies are now set via setup()

func setup(p_agent_registry, p_audit_logger):
	agent_registry = p_agent_registry
	audit_logger = p_audit_logger
	if not agent_registry:
		push_error("AgentManager setup without AgentRegistry!")
	if not audit_logger:
		push_warning("AgentManager setup without AuditLogger.")

# --- Godot Lifecycle ---

func _process(delta: float):
	if not agent_registry:
		return # Cannot operate without registry
		
	# Get all current agent instances
	var agent_instances: Array[AgentInstance] = agent_registry.get_all_agent_instances()

	# v1: deterministic scheduling (stable order by agent_id)
	agent_instances.sort_custom(func(a, b):
		if not a or not b:
			return false
		return str(a.agent_id) < str(b.agent_id)
	)
	
	# Tick each agent
	# TODO: Add error handling / try-catch around tick?
	# TODO: Potentially filter which agents to tick based on status?
	for agent_instance in agent_instances:
		if is_instance_valid(agent_instance) and agent_instance.has_method("tick"):
			agent_instance.tick(delta)
		# else: Log warning if instance is invalid or lacks tick method?

# --- Utility Methods ---
func _log_audit(event_type: String, data: Dictionary, user_id: String):
	if audit_logger:
		audit_logger.log_event(event_type, data, user_id)
	else:
		print("[Audit Stub - %s]: %s (User: %s)" % [event_type, data, user_id if user_id else "N/A"]) 
