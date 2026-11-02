extends Control

# Test script for Agent-Alexander integration with SynTree
# Demonstrates proper async/await pattern for agent chat interactions
# 
# ARCHITECTURE NOTES:
# - AgentInstance.request_action() now properly awaits the full execution chain
# - SynTree executes synchronously through ActionDispatcher→ToolRegistry→SynTreeInterface
# - AI responses appear directly in chat UI without polling or task queues
# 
# Attach this script to a Control node with:
# - RichTextLabel (unique name: %RichTextLabel) for chat output
# - LineEdit (unique name: %LineEdit) for message input  
# - Button (unique name: %SendButton) for send action

# Preload required classes
const AgentDefinition = preload("res://addons/metapunkt/Core/AgentRegistry/AgentDefinition.gd")

@onready var output_label: RichTextLabel = %RichTextLabel
@onready var message_input: LineEdit = %LineEdit
var send_button: Button

# Core components - populated during initialization
var agent_alexander = null        # AgentInstance for chat interactions
var endpoint_handler: Node = null # Metapunkt's main entry point
var agent_registry = null         # For agent management
var agent_manager = null          # For agent lifecycle
var task_queue = null             # For task monitoring (used for logging only)

func _ready():
	setup_ui()
	await test_agent_alexander()

func setup_ui():
	"""Configure the chat interface UI components"""
	if not output_label:
		push_error("RichTextLabel not found! Make sure you have a RichTextLabel with unique name %RichTextLabel in the scene")
		return
		
	if not message_input:
		push_error("LineEdit not found! Make sure you have a LineEdit with unique name %LineEdit in the scene")
		return
	
	# Configure chat output display
	output_label.bbcode_enabled = true
	output_label.scroll_following = true
	output_label.text = "[b]Agent-Alexander Chat Interface[/b]\n[i]Real-time AI conversation through SynTree integration[/i]\n\n"
	
	# Configure message input
	message_input.placeholder_text = "Type a message for Agent-Alexander..."
	message_input.text_submitted.connect(_on_send_pressed)
	
	# Setup send button
	send_button = get_node_or_null("%SendButton")
	if send_button:
		send_button.pressed.connect(func(): _on_send_pressed(""))
		log_output("✅ Chat UI configured successfully")
	else:
		log_output("⚠️ SendButton not found - creating fallback button")
		send_button = Button.new()
		send_button.text = "Send"
		send_button.pressed.connect(func(): _on_send_pressed(""))
		message_input.get_parent().add_child(send_button)

func test_agent_alexander():
	"""Initialize and test Agent-Alexander integration"""
	log_output("=== Initializing Agent-Alexander ===\n")
	
	# Wait for plugins to initialize
	await get_tree().process_frame
	await get_tree().process_frame
	
	# Step 1: Find or create Metapunkt components
	log_output("Step 1: Locating Metapunkt system...")
	if not await _initialize_metapunkt_components():
		log_output("❌ Failed to initialize Metapunkt components")
		return
	
	# Step 2: Create Agent-Alexander
	log_output("Step 2: Creating Agent-Alexander...")
	if not await _create_agent_alexander():
		log_output("❌ Failed to create Agent-Alexander")
		return
	
	# Step 3: Test the integration
	log_output("Step 3: Testing SynTree integration...")
	await _test_initial_interaction()
	
	log_output("\n=== 🎉 Agent-Alexander Ready! ===")
	log_output("Use the input field below to chat with Agent-Alexander.")
	log_output("Responses now appear directly in this chat interface.\n")

func _initialize_metapunkt_components() -> bool:
	"""Find existing Metapunkt components or create them for testing"""
	# Try to find existing components first
	var endpoint_handlers = get_tree().get_nodes_in_group("endpoint_handler")
	
	if endpoint_handlers.size() > 0:
		endpoint_handler = endpoint_handlers[0]
		log_output("✅ Found existing EndpointHandler")
	else:
		log_output("Creating EndpointHandler for testing...")
		if not await _create_endpoint_handler():
			return false
	
	# Get required components
	agent_registry = endpoint_handler.get("agent_registry")
	agent_manager = endpoint_handler.get("agent_manager")
	task_queue = endpoint_handler.get("task_queue")
	
	if agent_registry and agent_manager and task_queue:
		log_output("✅ All Metapunkt components available")
		return true
	else:
		log_output("❌ Missing required components:")
		log_output("   Registry: " + str(agent_registry))
		log_output("   Manager: " + str(agent_manager))
		log_output("   TaskQueue: " + str(task_queue))
		return false

func _create_endpoint_handler() -> bool:
	"""Create EndpointHandler directly for testing"""
	var EndpointHandler = preload("res://addons/metapunkt/Networking/SLOPServer/EndpointHandler.gd")
	if not EndpointHandler:
		log_output("❌ Could not load EndpointHandler script")
		return false
	
	endpoint_handler = EndpointHandler.new()
	if not endpoint_handler:
		log_output("❌ Could not instantiate EndpointHandler")
		return false
	
	add_child(endpoint_handler)
	endpoint_handler.add_to_group("endpoint_handler")
	
	# Wait for initialization
	await get_tree().process_frame
	await get_tree().process_frame
	
	log_output("✅ EndpointHandler created successfully")
	return true

func _create_agent_alexander() -> bool:
	"""Create and initialize Agent-Alexander with proper definition"""
	# Load or create agent definition
	var agent_def_path = "res://addons/metapunkt/resources/agent_alexander.tres"
	var agent_def: AgentDefinition
	
	if FileAccess.file_exists(agent_def_path):
		var loaded_def = load(agent_def_path) as AgentDefinition
		if loaded_def:
			agent_def = loaded_def
			log_output("✅ Loaded Agent-Alexander definition from file")
		else:
			agent_def = _create_fallback_definition()
			log_output("⚠️ File exists but invalid, using fallback definition")
	else:
		agent_def = _create_fallback_definition()
		log_output("⚠️ Definition file not found, using fallback definition")
	
	# Create agent instance
	var AgentInstance = preload("res://addons/metapunkt/Core/AgentRegistry/AgentInstance.gd")
	var agent_id = "agent_alexander_test"
	var user_id = "test_user"
	
	var new_agent = AgentInstance.new(agent_id, user_id, agent_def)
	agent_registry._agents[agent_id] = new_agent
	
	# Setup dependencies
	var action_dispatcher = endpoint_handler.get("action_dispatcher")
	var sensor_interface = endpoint_handler.get("sensor_interface") 
	var short_term_memory = endpoint_handler.get("short_term_memory")
	var decision_logic_manager = endpoint_handler.get("decision_logic_manager")
	
	if not new_agent.setup_dependencies(action_dispatcher, sensor_interface, short_term_memory, decision_logic_manager):
		log_output("❌ Failed to setup agent dependencies")
		return false
	
	# Initialize the agent
	new_agent.initialize_state()
	
	if new_agent.current_status == new_agent.Status.ERROR:
		log_output("❌ Agent initialization failed: " + new_agent.status_message)
		return false
	
	agent_alexander = new_agent
	log_output("✅ Agent-Alexander created and initialized")
	return true

func _create_fallback_definition() -> AgentDefinition:
	"""Create a programmatic agent definition as fallback"""
	var agent_def = AgentDefinition.new()
	agent_def.agent_id = "agent_alexander"
	agent_def.agent_name = "Agent-Alexander"
	agent_def.persona = "Master architect of digital spaces. I approach development with systematic thinking, identifying patterns that create coherent, maintainable systems. Every code structure should have that quality without a name - elegant, functional, alive. I work iteratively, building thoughtfully toward emergent complexity."
	agent_def.role = "developer"
	agent_def.logic_type = "limboai"
	agent_def.logic_config = {"path": "res://addons/metapunkt/behavior_trees/alexander_developer.tres"}
	agent_def.required_tools = ["SynTree", "GodotUtils"]
	agent_def.capabilities = {}
	return agent_def

func _test_initial_interaction():
	"""Test the agent with an initial message to verify everything works"""
	if not agent_alexander:
		log_output("❌ No agent available for testing")
		return
	
	# Send initial test message using the working async pattern
	var result = await agent_alexander.request_action("SynTree", {
		"operation": "chat",
		"message": "Hello Agent-Alexander! Please introduce yourself briefly."
	})
	
	# Display result using the same pattern as user chat
	_handle_agent_response(result)

func _on_send_pressed(text: String = ""):
	"""Handle user message submission - the core chat interaction"""
	var message = text if not text.is_empty() else message_input.text
	
	if message.is_empty():
		return
	
	# Clear input and display user message
	message_input.text = ""
	log_output_sync("\n👤 You: " + message)
	
	if agent_alexander:
		# CRITICAL: This await pattern is what makes the direct response work
		# The agent.request_action() now properly awaits the full execution chain:
		# AgentInstance → ActionDispatcher → ToolRegistry → SynTreeInterface → ConversationManager
		var result = await agent_alexander.request_action("SynTree", {
			"operation": "chat", 
			"message": message
		})
		_handle_agent_response(result)
	else:
		log_output_sync("❌ Agent not available")

func _handle_agent_response(result: Dictionary):
	"""Process and display agent response with proper error handling"""
	if result and result.has("result") and result.result.has("response"):
		# Success case - display the AI response
		log_output_sync("🤖 Agent-Alexander: " + result.result.response)
	elif result and result.has("error"):
		# Error case - display error message
		log_output_sync("❌ Agent error: " + str(result.error))
	else:
		# Unexpected format - display for debugging
		log_output_sync("❌ Unexpected result format: " + str(result))

# Logging functions for output formatting
func log_output(text: String):
	"""Log text to both console and UI (async-safe)"""
	print(text)  # Also print to console 
	if output_label:
		call_deferred("_append_to_output", text)

func log_output_sync(text: String):
	"""Log text to both console and UI (immediate)"""
	print(text)  # Also print to console
	if output_label:
		_append_to_output(text)

func _append_to_output(text: String):
	"""Helper function to append text to the RichTextLabel"""
	if output_label:
		output_label.text += text + "\n" 
