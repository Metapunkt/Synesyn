extends Node

"""
Simple Agent Creation Test

Tests just the agent creation and LimboAI runner assignment without the full conversation system.
"""

# --- Component References ---
var agent_registry
var agent_manager
var short_term_memory
var audit_logger

# --- Preloads ---
const AgentDefinition = preload("res://addons/metapunkt/Core/AgentRegistry/AgentDefinition.gd")
const AgentInstance = preload("res://addons/metapunkt/Core/AgentRegistry/AgentInstance.gd")
const AgentManager = preload("res://addons/metapunkt/Core/AgentManager.gd")

func _ready():
	print("=== Simple Agent Creation Test ===")
	await _initialize_metapunkt()
	await _test_single_agent_creation()

func _initialize_metapunkt() -> bool:
	"""Initialize minimal Metapunkt components needed for agent creation"""
	print("Initializing Metapunkt components...")
	
	# --- Module Instantiation (Minimal Set) ---
	var modules = {}
	
	# Level 0: Independent Services
	modules["audit_logger"] = preload("res://addons/metapunkt/Audit/AuditLogger.gd").new()
	modules["tool_registry"] = preload("res://addons/metapunkt/Tools/ToolRegistry.gd").new(modules["audit_logger"])
	modules["task_queue"] = preload("res://addons/metapunkt/TaskManager/TaskQueue.gd").new(modules["audit_logger"])
	modules["short_term_memory"] = preload("res://addons/metapunkt/Memory/ShortTermMemory.gd").new(modules["audit_logger"])
	modules["sensor_interface"] = preload("res://addons/metapunkt/Core/SensorInterface/SensorInterface.gd").new(modules["audit_logger"])
	modules["action_dispatcher"] = preload("res://addons/metapunkt/Core/ActionDispatcher/ActionDispatcher.gd").new(modules["tool_registry"], modules["audit_logger"], modules["task_queue"])

	# Level 2: Manager Node for runners
	modules["agent_manager"] = preload("res://addons/metapunkt/Core/AgentManager.gd").new()
	add_child(modules["agent_manager"]) # Add to scene so it's a valid parent

	# Level 3: Decision Logic Manager
	modules["decision_logic_manager"] = preload("res://addons/metapunkt/Core/DecisionLogicManager/DecisionLogicManager.gd").new(
		modules["action_dispatcher"],
		modules["audit_logger"],
		modules["sensor_interface"],
		modules["agent_manager"] # Provide the parent for runners
	)
	
	modules["agent_registry"] = preload("res://addons/metapunkt/Core/AgentRegistry/AgentRegistry.gd").new(
		modules["audit_logger"],
		modules["action_dispatcher"],
		modules["sensor_interface"],
		modules["short_term_memory"],
		modules["decision_logic_manager"]
	)
	
	# Setup the AgentManager
	modules["agent_manager"].setup(modules["agent_registry"], modules["audit_logger"])

	# Assign created modules to local variables for convenience
	agent_registry = modules["agent_registry"]
	short_term_memory = modules["short_term_memory"]
	audit_logger = modules["audit_logger"]
	agent_manager = modules["agent_manager"]

	print("✅ Metapunkt components initialized")
	return true

func _test_single_agent_creation():
	"""Test creating a single agent with LimboAI behavior tree"""
	print("\n=== Testing Single Agent Creation ===")
	
	# Create agent definition
	var test_agent_def = AgentDefinition.new()
	test_agent_def.agent_id = "test_agent"
	test_agent_def.agent_name = "Test Agent"
	test_agent_def.persona = "A simple test agent"
	test_agent_def.logic_type = "limboai"
	test_agent_def.logic_config = {"path": "res://addons/metapunkt/behavior_trees/debug_simple.tres"}

	print("Agent definition created:")
	print("  - ID: ", test_agent_def.agent_id)
	print("  - Name: ", test_agent_def.agent_name)
	print("  - Logic type: ", test_agent_def.logic_type)
	print("  - Logic config: ", test_agent_def.logic_config)

	# Create agent instance
	print("\nCreating agent instance...")
	var test_agent = await agent_registry.create_agent_from_definition(test_agent_def, "test_user")
	
	if test_agent:
		print("✅ Agent created successfully!")
		print("  - Agent ID: ", test_agent.agent_id)
		print("  - Status: ", AgentInstance.Status.keys()[test_agent.current_status])
		print("  - Status message: ", test_agent.status_message)
		
		# Check if logic runner was assigned
		if test_agent.logic_runner:
			print("  - Logic runner: ", test_agent.logic_runner.get_class())
			print("  - Logic runner is in scene tree: ", test_agent.logic_runner.get_parent() != null)
			if test_agent.logic_runner.get_parent():
				print("  - Logic runner parent: ", test_agent.logic_runner.get_parent().get_path())
		else:
			print("  - ❌ No logic runner assigned")
			
		# Test starting the agent
		print("\nTesting agent logic runner start...")
		if test_agent.logic_runner and test_agent.logic_runner.has_method("start"):
			test_agent.logic_runner.start()
			print("✅ Logic runner started")
		else:
			print("❌ Cannot start logic runner")
			
	else:
		print("❌ Agent creation failed!")
	
	print("\n=== Test Complete ===") 
