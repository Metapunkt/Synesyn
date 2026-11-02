extends Node

"""
Multi-Agent Conversation Test: Two Agent-Chaplins Discuss UFOs

This test demonstrates Metapunkt's core value proposition:
- Multi-agent orchestration via behavior trees
- Role-based behavior consistency through LimboAI
- Inter-agent communication through shared memory
- Turn-taking logic via behavior tree execution
- Comprehensive audit trails

This showcases the complexity that would be difficult to manage with direct SynTree integration.
"""

# --- Test Configuration ---
const TEST_DURATION = 60.0  # seconds
const MAX_CONVERSATION_TURNS = 10
const TURN_DELAY = 3.0  # seconds between turns

# --- Component References ---
var endpoint_handler
var agent_registry
var agent_manager  # NEW: For proper behavior tree execution
var short_term_memory
var audit_logger

# --- Agent Instances ---
var chaplin_1: AgentInstance
var chaplin_2: AgentInstance

# --- Conversation State ---
var conversation_log: Array = []
var current_turn = 0
var active_speaker = 1  # 1 or 2
var conversation_topic = "UFOs and extraterrestrial visitors"
var conversation_active = false
var conversation_completed = false
var _scroll_log_needed = false
var turn_timer: Timer  # Store timer reference for cleanup

# --- UI References ---
@onready var log_display = %LogDisplay
@onready var start_button = %StartButton
@onready var stop_button = %StopButton
@onready var status_label = %StatusLabel

# --- Preloads ---
const AgentDefinition = preload("res://addons/metapunkt/Core/AgentRegistry/AgentDefinition.gd")
const AgentInstance = preload("res://addons/metapunkt/Core/AgentRegistry/AgentInstance.gd")
const AgentManager = preload("res://addons/metapunkt/Core/AgentManager.gd")

func _ready():
	log_output("🎭 Multi-Agent Chaplin UFO Conversation Test", "title")
	log_output("=".repeat(50), "separator")
	
	# Setup UI
	if start_button:
		start_button.pressed.connect(_on_start_pressed)
	if stop_button:
		stop_button.pressed.connect(_on_stop_pressed)
		stop_button.disabled = true
	
	# Initialize Metapunkt
	await _initialize_metapunkt()

func _initialize_metapunkt() -> bool:
	"""Initialize Metapunkt orchestration system"""
	log_output("🔧 Initializing Metapunkt...", "system")
	
	# --- Module Instantiation (Corrected Order) ---
	var modules = {}
	
	# Level 0: Independent Services
	modules["audit_logger"] = preload("res://addons/metapunkt/Audit/AuditLogger.gd").new()
	modules["tool_registry"] = preload("res://addons/metapunkt/Tools/ToolRegistry.gd").new(modules["audit_logger"])
	modules["task_queue"] = preload("res://addons/metapunkt/TaskManager/TaskQueue.gd").new(modules["audit_logger"])
	modules["short_term_memory"] = preload("res://addons/metapunkt/Memory/ShortTermMemory.gd").new(modules["audit_logger"])
	modules["long_term_memory_client"] = preload("res://addons/metapunkt/Memory/LongTermMemoryClient.gd").new(modules["audit_logger"])
	modules["payments_client"] = preload("res://addons/metapunkt/Payments/PaymentClient.gd").new()
	
	# Level 1: Services depending on Level 0
	modules["sensor_interface"] = preload("res://addons/metapunkt/Core/SensorInterface/SensorInterface.gd").new(modules["audit_logger"])
	modules["action_dispatcher"] = preload("res://addons/metapunkt/Core/ActionDispatcher/ActionDispatcher.gd").new(modules["tool_registry"], modules["audit_logger"], modules["task_queue"])
	
	# Level 2: Manager Nodes
	# The AgentManager will be the parent for logic runners.
	modules["agent_manager"] = preload("res://addons/metapunkt/Core/AgentManager.gd").new()
	add_child(modules["agent_manager"]) # Add to scene so it's a valid parent
	
	modules["task_runner"] = preload("res://addons/metapunkt/TaskManager/TaskRunner.gd").new(modules["task_queue"], modules["audit_logger"])
	add_child(modules["task_runner"])

	# Level 3: Core Logic Managers (depending on previous levels)
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
	
	# Now that all modules are created, setup the AgentManager
	modules["agent_manager"].setup(modules["agent_registry"], modules["audit_logger"])

	# Assign created modules to local variables for convenience
	agent_registry = modules["agent_registry"]
	short_term_memory = modules["short_term_memory"]
	audit_logger = modules["audit_logger"]
	agent_manager = modules["agent_manager"]

	# Level 4: Networking
	endpoint_handler = preload("res://addons/metapunkt/Networking/SLOPServer/EndpointHandler.gd").new()
	endpoint_handler.setup_modules(modules)
	add_child(endpoint_handler)

	log_output("✅ Metapunkt ready", "success")
	return true

func _on_start_pressed():
	"""Start the multi-agent conversation"""
	start_button.disabled = true
	stop_button.disabled = false
	
	await _start_conversation()

func _on_stop_pressed():
	"""Stop the conversation"""
	if conversation_active:
		_stop_conversation()

func _start_conversation():
	"""Initialize and start the UFO conversation between two Chaplin agents"""
	if conversation_active:
		log_output("⚠️ Conversation already in progress!", "warning")
		return
	
	log_output("🚀 Starting UFO Conversation Test...", "title")
	
	# Reset conversation state
	conversation_active = true
	conversation_completed = false  # Reset completion flag
	current_turn = 0
	active_speaker = 1
	conversation_log.clear()
	
	# Update UI
	start_button.disabled = true
	stop_button.disabled = false
	
	# Create both agent instances
	if not await _create_chaplin_agents():
		log_output("❌ Failed to create agent instances", "error")
		return
	
	# Initialize conversation context in shared memory
	_setup_conversation_context()
	
	# Start the agents' behavior trees
	_start_agent_behavior_trees()
	
	# Set conversation trigger for first agent
	await _trigger_conversation_start()
	
	# Begin turn-based conversation monitoring
	_start_conversation_monitoring()

func _create_chaplin_agents() -> bool:
	"""Create two Agent-Chaplin instances with conversation behavior"""
	# log_output("👥 Creating agents...", "system")
	
	# Create agent definitions with unique IDs
	var chaplin_1_def = AgentDefinition.new()
	chaplin_1_def.agent_id = "chaplin_1"
	chaplin_1_def.agent_name = "Agent-Chaplin #1 (The Believer)"
	chaplin_1_def.persona = "A curious and optimistic individual who finds wonder in the possibility of extraterrestrial life. You get excited about UFO sightings and love discussing the mysteries of the universe. You're naturally hopeful and see the magic in unexplained phenomena."
	chaplin_1_def.role = "roleplay"
	chaplin_1_def.logic_type = "limboai"
	chaplin_1_def.logic_config = {"path": "res://addons/metapunkt/behavior_trees/chaplin_conversation.tres"}
	
	var chaplin_2_def = AgentDefinition.new()
	chaplin_2_def.agent_id = "chaplin_2"
	chaplin_2_def.agent_name = "Agent-Chaplin #2 (The Doubter)"
	chaplin_2_def.persona = "A thoughtful skeptic who approaches extraordinary claims with careful reasoning. You enjoy debating UFO phenomena but prefer evidence-based explanations. You're not dismissive - just cautious and analytical by nature."
	chaplin_2_def.role = "roleplay"
	chaplin_2_def.logic_type = "limboai"
	chaplin_2_def.logic_config = {"path": "res://addons/metapunkt/behavior_trees/chaplin_conversation.tres"}
	
	# Create agents with unique definitions
	chaplin_1 = await agent_registry.create_agent_from_definition(chaplin_1_def, "test_user")
	chaplin_2 = await agent_registry.create_agent_from_definition(chaplin_2_def, "test_user")
	
	if not chaplin_1 or not chaplin_2:
		log_output("❌ Failed to create agents", "error")
		return false
	
	log_output("✅ Agents created", "success")
	return true

func _setup_conversation_context():
	"""Setup shared conversation context in memory"""
	# Store conversation metadata
	short_term_memory.set_memory("conversation_topic", conversation_topic, "shared")
	short_term_memory.set_memory("conversation_log", [], "shared")
	short_term_memory.set_memory("current_turn", 0, "shared")
	short_term_memory.set_memory("active_speaker", 1, "shared")
	short_term_memory.set_memory("conversation_active", false, "shared")
	short_term_memory.set_memory("conversation_trigger", "", "shared")
	
	# Set individual agent contexts using their correct agent_id
	short_term_memory.set_memory("my_name", chaplin_1.definition.agent_name, chaplin_1.agent_id)
	short_term_memory.set_memory("other_agent", chaplin_2.definition.agent_name, chaplin_1.agent_id)
	short_term_memory.set_memory("my_role", "believer", chaplin_1.agent_id)
	
	short_term_memory.set_memory("my_name", chaplin_2.definition.agent_name, chaplin_2.agent_id)
	short_term_memory.set_memory("other_agent", chaplin_1.definition.agent_name, chaplin_2.agent_id)
	short_term_memory.set_memory("my_role", "doubter", chaplin_2.agent_id)

func _start_agent_behavior_trees():
	"""Start the behavior trees for both agents"""
	# AgentManager will now tick the agents, which in turn ticks the runners.
	# The logic_runner.start() call is now handled inside AgentInstance.initialize_state
	# which correctly awaits the 'ready' signal. We don't need to do anything here.
	
	conversation_active = true

func _trigger_conversation_start():
	"""Trigger the conversation by setting appropriate memory flags"""
	# log_output("🛸 Starting conversation...", "system")
	
	# Set the conversation as active and trigger the first speaker
	short_term_memory.set_memory("conversation_active", true, "shared")
	short_term_memory.set_memory("conversation_trigger", "start_ufo_discussion", "shared")
	short_term_memory.set_memory("active_speaker", 1, "shared")
	
	# Set specific trigger for Chaplin-1 to start, using its correct agent_id
	short_term_memory.set_memory("should_speak", true, chaplin_1.agent_id)
	short_term_memory.set_memory("should_speak", false, chaplin_2.agent_id)

func _start_conversation_monitoring():
	"""Begin monitoring the conversation for turn management"""
	turn_timer = Timer.new()
	add_child(turn_timer)
	turn_timer.wait_time = TURN_DELAY
	turn_timer.timeout.connect(_monitor_conversation_turn)
	turn_timer.start()

func _monitor_conversation_turn():
	"""Monitor and manage conversation turns"""
	if conversation_completed:
		return  # Already completed, don't repeat
		
	if current_turn >= MAX_CONVERSATION_TURNS:
		conversation_completed = true
		conversation_active = false  # Stop processing
		
		# Stop the timer
		if turn_timer:
			turn_timer.stop()
			turn_timer.queue_free()
			turn_timer = null
		
		log_output("🎬 Conversation completed after %d turns" % MAX_CONVERSATION_TURNS, "success")
		_stop_conversation()
		return
	
	# Check if it's time to switch speakers
	var conversation_log_shared = short_term_memory.get_memory("conversation_log", "shared")
	if conversation_log_shared and conversation_log_shared.size() > current_turn:
		# New message detected, switch speakers
		current_turn = conversation_log_shared.size()
		active_speaker = 2 if active_speaker == 1 else 1
		
		# Update shared memory (remove verbose logging)
		short_term_memory.set_memory("current_turn", current_turn, "shared")
		short_term_memory.set_memory("active_speaker", active_speaker, "shared")
		
		# Set speaking flags
		if active_speaker == 1:
			short_term_memory.set_memory("should_speak", true, chaplin_1.agent_id)
			short_term_memory.set_memory("should_speak", false, chaplin_2.agent_id)
		else:
			short_term_memory.set_memory("should_speak", false, chaplin_1.agent_id)
			short_term_memory.set_memory("should_speak", true, chaplin_2.agent_id)

func _stop_conversation():
	"""Stop the conversation and show results"""
	conversation_active = false
	conversation_completed = true
	
	# Stop the timer if it's still running
	if turn_timer:
		turn_timer.stop()
		turn_timer.queue_free()
		turn_timer = null
	
	start_button.disabled = false
	stop_button.disabled = true
	
	log_output("🎭 Conversation Summary", "title")
	log_output("=".repeat(40), "separator")
	log_output("Total turns: %d" % current_turn, "info")
	log_output("Messages exchanged: %d" % conversation_log.size(), "info")
	
	# We no longer print the full conversation recap to avoid duplicate logs.

func log_output(text: String, type: String = "normal"):
	"""Display formatted output in UI and console"""
	print(text)
	if log_display:
		match type:
			"title":
				log_display.text += "[color=cyan][b]%s[/b][/color]\n" % text
			"subtitle":
				log_display.text += "[color=yellow][b]%s[/b][/color]\n" % text
			"separator":
				log_display.text += "[color=gray]%s[/color]\n" % text
			"system":
				log_display.text += "[color=lightblue]%s[/color]\n" % text
			"success":
				log_display.text += "[color=green]%s[/color]\n" % text
			"error":
				log_display.text += "[color=red]%s[/color]\n" % text
			"warning":
				log_display.text += "[color=orange]%s[/color]\n" % text
			"thinking":
				log_display.text += "[color=magenta]%s[/color]\n" % text
			"advantage":
				log_display.text += "[color=lightgreen]%s[/color]\n" % text
			"info":
				log_display.text += "[color=white]%s[/color]\n" % text
			_:
				log_display.text += "%s\n" % text
		_scroll_log_needed = true

func log_conversation_message(speaker: String, message: String, prefix: String = ""):
	"""Log a conversation message with special formatting"""
	var speaker_color = "aqua" if speaker.contains("1") else "pink"
	var prefix_text = "[color=gray]%s - [/color]" % prefix if not prefix.is_empty() else ""
	if log_display:
		log_display.text += "%s[color=%s][b]%s:[/b][/color] [color=white]%s[/color]\n" % [prefix_text, speaker_color, speaker, message]
		_scroll_log_needed = true

# --- Scene Tree Structure ---
func _create_ui():
	"""Create the test UI if running as main scene"""
	var vbox = VBoxContainer.new()
	add_child(vbox)
	
	# Status label
	var status = Label.new()
	status.name = "StatusLabel"
	status.unique_name_in_owner = true
	status.text = "Multi-Agent Chaplin UFO Conversation Test"
	status.add_theme_color_override("font_color", Color.CYAN)
	vbox.add_child(status)
	
	# Buttons
	var button_container = HBoxContainer.new()
	vbox.add_child(button_container)
	
	var start_btn = Button.new()
	start_btn.name = "StartButton"
	start_btn.unique_name_in_owner = true
	start_btn.text = "Start UFO Conversation"
	start_btn.add_theme_color_override("font_color", Color.GREEN)
	button_container.add_child(start_btn)
	
	var stop_btn = Button.new()
	stop_btn.name = "StopButton"
	stop_btn.unique_name_in_owner = true
	stop_btn.text = "Stop Conversation"
	stop_btn.add_theme_color_override("font_color", Color.RED)
	button_container.add_child(stop_btn)
	
	# Log display
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(900, 700)
	vbox.add_child(scroll)
	
	var log_rich = RichTextLabel.new()
	log_rich.name = "LogDisplay"
	log_rich.unique_name_in_owner = true
	log_rich.fit_content = true
	log_rich.bbcode_enabled = true
	log_rich.add_theme_color_override("default_color", Color.WHITE)
	log_rich.add_theme_color_override("font_color", Color.WHITE)
	scroll.add_child(log_rich)

# Create UI if no existing UI found
func _enter_tree():
	if not has_node("VBoxContainer"):
		_create_ui() 

func _add_to_conversation_log(speaker: String, message: String):
	"""Add message to conversation log and shared memory"""
	var log_entry = {
		"speaker": speaker,
		"message": message,
		"timestamp": Time.get_unix_time_from_system(),
		"turn": current_turn
	}
	
	conversation_log.append(log_entry)
	
	# Update shared memory
	short_term_memory.set_memory("conversation_log", conversation_log, "shared")
	
	# Log audit trail
	if audit_logger:
		audit_logger.log_event("agent_conversation", {
			"speaker": speaker,
			"turn": current_turn,
			"message_length": message.length()
		}, "test_user")

func _process(delta):
	"""Monitor for new conversation messages from agents"""
	# Early exit if conversation is not active
	if not conversation_active or not short_term_memory:
		return
	
	if _scroll_log_needed:
		if log_display and log_display.get_parent() is ScrollContainer:
			var scroll = log_display.get_parent() as ScrollContainer
			scroll.scroll_vertical = scroll.get_v_scroll_bar().max_value
		_scroll_log_needed = false
	
	# Check for new messages in shared memory
	var conversation_log_shared = short_term_memory.get_memory("conversation_log", "shared")
	if conversation_log_shared and conversation_log_shared.size() > conversation_log.size():
		# New message detected
		var new_messages = conversation_log_shared.slice(conversation_log.size())
		for msg in new_messages:
			log_conversation_message(msg.speaker, msg.message)
			conversation_log.append(msg)

func _check_for_agent_responses():
	"""Check for agent responses through behavior tree execution"""
	# This function monitors the agents' behavior tree execution results
	# For now, the conversation monitoring is handled through shared memory
	# Future enhancement: Monitor specific tool execution results
	pass
