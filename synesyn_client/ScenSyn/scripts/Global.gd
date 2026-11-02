## Synesyn — A Latent Reality Framework.
## Copyright © 2026 Ayodele Arigbabu | metapunkt.org | NTNU. All rights reserved.
## Licensed under [licence pending].
## Version: 0.0.3
## Enquiries: metapunkt@metapunkt.org

# global.gd
extends Node

const APP_NAME := "Synesyn"
const APP_VERSION := "0.0.3"
const APP_COPYRIGHT := "© 2026 Ayodele Arigbabu | metapunkt.org | NTNU"
const APP_ENQUIRIES := "metapunkt@metapunkt.org"

signal scenario_changed(scenario_name)
signal tts_emitter_changed(new_emitter)

# Updated references to use current SynTree architecture
# var godot_syntree: GodotSynTree  # REMOVED - doesn't exist in current version
var conversation_manager: ConversationManager
var game_conversation_manager: GameConversationManager
var syntree_conversation_manager: ConversationManager
var scenario_loader = preload("res://ScenSyn/scripts/core/scenario_loader.gd").new()

#var scenario_builder: ScenarioBuilder

var metaprompt_manager  # BaseMetapromptManager - untyped to allow dynamic dispatch to overridden methods
var game_flow_manager: GameFlowManager
var current_character: Dictionary = {}
## Scenario the current character was chosen for; see get_current_character().
var current_character_scenario: String = ""
var current_character_session_type: String = ""
var selected_characters = []
var current_scenario = {}
var character_templates = []

var character_pool = []
#var current_scenario_metaprompt: String = "trondheim_future_scenarios"
var current_scenario_metaprompt: String = ""
var is_scenario_selected: bool = false
## Set by GameModePopup's "Resume a previous session" flow. game_session.gd
## consumes this once, on _ready(), to load a prior .json story log live
## instead of starting fresh (same mechanism as the in-session "My Sessions" /
## "Load Story Log…" pickers).
var _pending_workshop_resume_path: String = ""
var current_session_type: String = "workshop_catalyst"
var current_collection_id: String = "decision_triage"
const SESSION_TYPE_ORDER: Array[String] = ["workshop_catalyst", "story_catalyst"]
const SESSION_TYPE_COLLECTIONS: Dictionary = {
	"workshop_catalyst": {
		"decision_triage": [
			"karlsruhe_library_future_design",
			"workshop_catalyst_demo",
		],
	},
	"story_catalyst": {
		"sustainability": [
			"hello_trondheim",
			"the_crisis_goodnight_trondheim",
			"the_revolt_of_the_salmon",
			"energy_futures",
			"the_windmill_syndrome",
		],
		"cultural_narratives": [
			"stochastic_dreams",
			"ireti_okan_awaiting_an_awakening",
		],
		## Open Play: player-authored fun roleplay (no didactic overlays).
		## Authored template list stays empty; selectable scenarios come from
		## StoryScenarioContract's finished library under Documents/Synesyn/scensyn/.
		"open_play": [],
	},
}
const SESSION_TYPE_MANAGER_PATHS: Dictionary = {
	"workshop_catalyst": {
		"decision_triage": "res://ScenSyn/session_types/workshop_catalyst/metaprompt_manager_workshop_catalyst.gd",
	},
	"story_catalyst": {
		"sustainability": "res://ScenSyn/session_types/story_catalyst/sustainability/metaprompt_manager_sustainability.gd",
		"cultural_narratives": "res://ScenSyn/session_types/story_catalyst/cultural_narratives/metaprompt_manager_cultural_narrative.gd",
		"open_play": "res://ScenSyn/session_types/story_catalyst/open_play/metaprompt_manager_open_play.gd",
	},
}
## Which scenario a collection opens on. A collection without an entry opens on the first
## name in its list above. Keep a work-in-progress scenario out of here: the default is the
## one a newcomer meets first.
const COLLECTION_DEFAULT_SCENARIOS: Dictionary = {
	"cultural_narratives": "ireti_okan_awaiting_an_awakening",
}
## Friendly collection labels for dropdowns (fallback: id with underscores → spaces).
const COLLECTION_DISPLAY_NAMES: Dictionary = {
	"decision_triage": "Decision Triage",
	"sustainability": "Sustainability",
	"cultural_narratives": "Cultural Narratives",
	"open_play": "Open Play",
}
var default_scenario_name = "karlsruhe_library_future_design"
## Scenarios that are still in development. Shown with a "⚠ WIP" prefix in the selector so
## facilitators know they may be incomplete. Remove a name here when it reaches pilot-ready state.
var wip_scenarios: Array[String] = ["workshop_catalyst_demo", "hello_trondheim", "stochastic_dreams"]

# Global TTS selection: 'story_log' or 'story_stage'
# Default to story_stage so visuals speak by default
var tts_emitter: String = "story_stage"

signal character_pool_updated

# Opening narrator voice support
var opening_welcome_text: String = ""
var opening_spoken_log: bool = false
var opening_spoken_stage: bool = false
var is_loading_story_log: bool = false

# NEW: External Input Listener Autoload Reference
var external_input_listener: ExternalInputListener
# NEW: Player Auto Input helper
var player_auto_input: PlayerAutoInput
# Cross-cutting closure-formation event bus (theme-agnostic). Themes that
# adopt vote-based or other explicit-closure mechanisms emit to this bus
# whenever a closure is captured or discarded; the bus owns the substrate
# emitter that persists captures as ui.workshop_closure artifacts to the Hub
# when available. See scripts/closure/closure_bus.gd.
var closure_bus: ClosureBus

func _ready():	
	# UPDATED: Wait for PluginManager initialization before getting ConversationManager
	await _wait_for_plugin_manager_ready()
	
	# Initialize External Input Listener
	external_input_listener = preload("res://ScenSyn/scripts/hardware_integration/external_input_listener.gd").new()
	add_child(external_input_listener)

	# Initialize Umeno Chaos Engine
	var umeno_engine = preload("res://ScenSyn/scripts/hardware_integration/umeno_engine.gd").new()
	add_child(umeno_engine)

	# Initialize Player Auto Input helper
	player_auto_input = preload("res://ScenSyn/scripts/core/player_auto_input.gd").new()
	add_child(player_auto_input)

	# Initialize Closure Bus (theme-agnostic closure-formation event bus).
	# Created early so theme controllers (e.g. Workshop Catalyst) can subscribe
	# / emit to it during their own initialization.
	closure_bus = preload("res://ScenSyn/scripts/closure/closure_bus.gd").new()
	closure_bus.name = "ClosureBus"
	add_child(closure_bus)
	
	syntree_conversation_manager = _get_syntree_conversation_manager()
	if syntree_conversation_manager and syntree_conversation_manager.has_method("set_include_content_bus_context"):
		syntree_conversation_manager.set_include_content_bus_context(true)

	# Subscribe to SynTree AI model changes so ScenSyn stays in sync with the UI
	_subscribe_ai_model_change()

	game_conversation_manager = GameConversationManager.new()
	# ScenSyn should be isolated by default; scope must be set BEFORE setup() so disk/session bindings are correct.
	if game_conversation_manager and game_conversation_manager.has_method("set_thread_scope"):
		game_conversation_manager.set_thread_scope("scensyn_session")
	if game_conversation_manager and game_conversation_manager.has_method("set_include_content_bus_context"):
		game_conversation_manager.set_include_content_bus_context(false)
	if PluginManager and PluginManager.is_ready():
		var api_service = PluginManager.get_api_service()
		var ai_manager = PluginManager.get_ai_model_manager()
		if api_service and ai_manager:
			game_conversation_manager.setup(api_service, ai_manager)
	game_flow_manager = GameFlowManager.new()
	# Start with a neutral manager to avoid early theme bleed
	metaprompt_manager = preload("res://ScenSyn/scripts/core/neutral_metaprompt_manager.gd").new()
#	scenario_builder = ScenarioBuilder.new()
	
	# Add the instances as children of this node (except conversation_manager - it's managed by SynTree)
	# REMOVED: add_child(conversation_manager)  # SynTree manages this
	add_child(game_conversation_manager)
	add_child(game_flow_manager)
	add_child(metaprompt_manager)
#	add_child(scenario_builder)

# NEW: Helper to get external input listener
func get_external_input_listener() -> ExternalInputListener:
	return external_input_listener

# NEW: Helper to get auto input helper
func get_player_auto_input() -> PlayerAutoInput:
	return player_auto_input

## Returns the cross-cutting closure-formation event bus.
## Theme records emit to this bus when a closure is captured or discarded;
## listeners include the substrate emitter and any future analytics consumers.
func get_closure_bus() -> ClosureBus:
	return closure_bus

# ADDED: Wait for PluginManager to complete initialization
func _wait_for_plugin_manager_ready():
	if not PluginManager:
		push_error("Global: PluginManager autoload not available")
		return
		
	# If PluginManager is already ready, return immediately
	if PluginManager.is_ready():
		print("Global: PluginManager already ready")
		return
		
	print("Global: Waiting for PluginManager initialization...")
	# Wait for the initialization_completed signal
	await PluginManager.initialization_completed
	print("Global: PluginManager initialization complete")

# ADDED: Helper to get properly configured ConversationManager from SynTree
func _get_syntree_conversation_manager() -> ConversationManager:
	# Wait for PluginManager to be ready
	if not PluginManager:
		push_error("Global: PluginManager not available")
		return null
		
	# Get the conversation manager from PluginManager
	var conv_manager = PluginManager.get_conversation_manager()
	if not conv_manager:
		push_error("Global: Could not get ConversationManager from PluginManager")
		return null
		
	print("Global: Successfully retrieved ConversationManager from SynTree")
	
	# Verify that the ConversationManager is properly configured
	if not conv_manager.ai_model_manager:
		push_error("Global: CRITICAL - Retrieved ConversationManager has null ai_model_manager!")
	if not conv_manager.api_service:
		push_error("Global: CRITICAL - Retrieved ConversationManager has null api_service!")
	else:
		print("Global: ConversationManager properly configured")
		
	return conv_manager

# Listen to SynTree AIModelManager model changes and reattach to ConversationManager
func _subscribe_ai_model_change() -> void:
	if not PluginManager:
		return
	if not PluginManager.is_ready():
		return
	var ai_manager = PluginManager.get_ai_model_manager()
	if ai_manager and ai_manager.has_signal("model_changed"):
		# Avoid duplicate connections
		if not ai_manager.is_connected("model_changed", Callable(self, "_on_ai_model_changed")):
			ai_manager.model_changed.connect(_on_ai_model_changed)
			print("Global: Subscribed to AIModelManager.model_changed")

func _on_ai_model_changed(model_name: String) -> void:
	# Reattach the current SynTree AIModelManager to the active ConversationManager
	if not PluginManager or not PluginManager.is_ready():
		return
	var conv_manager = PluginManager.get_conversation_manager()
	var ai_manager = PluginManager.get_ai_model_manager()
	if conv_manager and ai_manager and conv_manager.has_method("set_ai_model_manager"):
		conv_manager.set_ai_model_manager(ai_manager)
		conversation_manager = conv_manager
		print("Global: Reattached ai_model_manager after model change -> ", model_name)

# UPDATED: Access SynTree functionality through autoloaded services
func get_content_bus():
	# Access ContentBus autoload directly
	return ContentBus if ContentBus else null

func get_plugin_manager():
	# Access PluginManager autoload directly  
	return PluginManager if PluginManager else null

func get_conversation_manager() -> ConversationManager:
	print("Global: get_conversation_manager() called")
	# ScenSyn uses its own scoped conversation manager by default to prevent context bleed.
	if game_conversation_manager:
		return game_conversation_manager
	return conversation_manager

func get_syntree_conversation_manager() -> ConversationManager:
	return syntree_conversation_manager

func get_game_conversation_manager() -> GameConversationManager:
	return game_conversation_manager

#func get_scenario_builder() -> ScenarioBuilder:
	#return scenario_builder

func get_scenario_loader():
	return scenario_loader

func get_collection_ids(session_type_id: String) -> Array[String]:
	var collection_ids: Array[String] = []
	var collections: Dictionary = SESSION_TYPE_COLLECTIONS.get(session_type_id, {})
	for collection_key in collections.keys():
		collection_ids.append(String(collection_key))
	return collection_ids

## The scenario a collection opens on before anyone has chosen one. Empty means "the first
## in the list", which is how every collection behaved: an ordering decision standing in for
## an editorial one, and in Cultural Narratives it opened on a work-in-progress installation
## piece rather than the scenario that demonstrates the collection.
func get_collection_default_scenario(collection_id: String) -> String:
	return String(COLLECTION_DEFAULT_SCENARIOS.get(collection_id, ""))

func get_scenario_names(session_type_id: String, collection_id: String) -> Array[String]:
	var scenario_names: Array[String] = []
	var collections: Dictionary = SESSION_TYPE_COLLECTIONS.get(session_type_id, {})
	var registered_names: Array = collections.get(collection_id, [])
	for scenario_id in registered_names:
		scenario_names.append(String(scenario_id))
	return scenario_names

func resolve_scenario(
	scenario_name: String,
	session_type_hint: String = "",
	collection_hint: String = ""
) -> Dictionary:
	if not session_type_hint.is_empty() and not collection_hint.is_empty():
		if scenario_name in get_scenario_names(session_type_hint, collection_hint):
			return {
				"session_type_id": session_type_hint,
				"collection_id": collection_hint,
				"scenario_name": scenario_name,
			}
	for session_type_id in SESSION_TYPE_ORDER:
		for collection_id in get_collection_ids(session_type_id):
			if scenario_name in get_scenario_names(session_type_id, collection_id):
				return {
					"session_type_id": session_type_id,
					"collection_id": collection_id,
					"scenario_name": scenario_name,
				}
	return {}

func get_metaprompt_manager_for_collection(
	session_type_id: String,
	collection_id: String
) -> BaseMetapromptManager:
	var manager_paths: Dictionary = SESSION_TYPE_MANAGER_PATHS.get(session_type_id, {})
	var manager_path: String = String(manager_paths.get(collection_id, ""))
	if manager_path.is_empty():
		push_error(
			"Global: No metaprompt manager for %s/%s"
			% [session_type_id, collection_id]
		)
		return preload("res://ScenSyn/scripts/core/neutral_metaprompt_manager.gd").new()
	var manager_script: GDScript = load(manager_path)
	return manager_script.new()
	
func get_game_flow_manager() -> GameFlowManager:
	return game_flow_manager
	
func get_metaprompt_manager() -> BaseMetapromptManager:
	return metaprompt_manager

func set_tts_emitter(emitter: String) -> void:
	if emitter != "story_log" and emitter != "story_stage":
		push_warning("Global: Ignoring invalid tts_emitter: " + str(emitter))
		return
	if tts_emitter == emitter:
		return
	tts_emitter = emitter
	emit_signal("tts_emitter_changed", tts_emitter)

func get_tts_emitter() -> String:
	return tts_emitter

func set_current_character(character: Dictionary):
	current_character = character
	current_character_scenario = current_scenario_metaprompt
	current_character_session_type = current_session_type

## The human's character for the scenario now running, or {} when there is none.
##
## A selection belongs to the scenario it was made in. Nothing cleared it on a scenario
## switch, so a character chosen in one scenario was carried into the next, where it was
## announced as "You are playing as …" and — worse — used to attribute typed input in
## the story log, crediting a line to a character from a different scenario. Scenarios
## that have no human player at all, entered through an auto-input skip, inherited
## whichever character had last been picked.
func get_current_character() -> Dictionary:
	if current_character.is_empty():
		return {}
	if current_character_scenario == current_scenario_metaprompt:
		return current_character
	# A session role is not a member of any scenario's cast, so it outlives a scenario
	# change — a facilitator stays the facilitator. A cast member does not. It does not
	# outlive a change of session type, though: "Facilitator" is a workshop role and a
	# system voice in a story, so carrying it into Story Catalyst attributed the human's
	# own typed lines to a system sender, and the AI cast never answered them.
	if current_character_session_type != current_session_type:
		return {}
	if String(current_character.get("role", "")).strip_edges() in ["Facilitator", "Participant"]:
		return current_character
	return {}
	
func set_selected_characters(characters):
	selected_characters = characters

func get_selected_characters():
	return selected_characters

func set_character_templates(templates):
	character_templates = templates
	#for character in character_templates:
		#character.is_player = false
		
#func set_current_scenario(scenario):
	#current_scenario = scenario
#
func get_current_scenario() -> Dictionary:
	# Return cached scenario to avoid recursion/stack overflow when other systems
	# (e.g. StoryStage sprite resolution) query scenario frequently.
	if typeof(current_scenario) == TYPE_DICTIONARY and not (current_scenario as Dictionary).is_empty():
		var scen_cached: Dictionary = current_scenario as Dictionary
		print("Global: Getting current scenario (cached, name only): ", scen_cached.get("name", "No name"))
		return scen_cached.duplicate(false)

	# If cache is empty, fall back to game_flow_manager once (shallow copy),
	# then cache it for subsequent calls.
	var gfm: GameFlowManager = game_flow_manager
	if gfm and is_instance_valid(gfm) and gfm.has_method("get_current_scenario"):
		var scen_from_gfm: Dictionary = gfm.get_current_scenario()
		if typeof(scen_from_gfm) == TYPE_DICTIONARY and not scen_from_gfm.is_empty():
			current_scenario = scen_from_gfm.duplicate(false)
			print("Global: Getting current scenario (from gfm, name only): ", scen_from_gfm.get("name", "No name"))
			return scen_from_gfm.duplicate(false)

	print("Global: Getting current scenario: (none)")
	return {}
	
func set_character_pool(new_pool):
	# Deep copy to prevent unwanted references
	character_pool = []
	for character in new_pool:
		character_pool.append(character.duplicate(true))
	emit_signal("character_pool_updated")  # Notify listeners

func get_character_pool():
	return character_pool
	
func get_current_scenario_metaprompt() -> String:
	return current_scenario_metaprompt

func set_current_scenario_metaprompt(scenario_name: String) -> void:
	print("Global: Setting scenario metaprompt: ", scenario_name)
	var resolution: Dictionary = resolve_scenario(
		scenario_name,
		current_session_type,
		current_collection_id
	)
	if not resolution.is_empty():
		current_session_type = String(resolution.get("session_type_id", ""))
		current_collection_id = String(resolution.get("collection_id", ""))
		if metaprompt_manager and is_instance_valid(metaprompt_manager):
			remove_child(metaprompt_manager)
		metaprompt_manager = get_metaprompt_manager_for_collection(
			current_session_type,
			current_collection_id
		)
		add_child(metaprompt_manager)
		
		current_scenario_metaprompt = scenario_name
		scenario_loader.load_scenario(
			scenario_name,
			current_session_type,
			current_collection_id
		)
		var full_scenario = scenario_loader.get_current_scenario()
		if current_session_type == "workshop_catalyst":
			set_character_templates([])
			set_character_pool([])
			set_selected_characters([])
		else:
			set_character_templates(full_scenario.get("characters", []))
		print("Global: Scenario from scenario_loader (name only): ", full_scenario.get("name", "No name"))
		is_scenario_selected = true
		
		# Ensure the scenario name is properly formatted
		full_scenario["name"] = format_scenario_name(scenario_name)
		
		# Cache for fast, recursion-safe access (e.g. StoryStage sprite lookup).
		current_scenario = full_scenario.duplicate(false)

		get_game_flow_manager().set_current_scenario(full_scenario)
		emit_signal("scenario_changed", scenario_name)  # Emit original name, not formatted
		if Network.is_multiplayer():
			Network.rpc("sync_selected_scenario", scenario_name)
	else:
		print("Error: Invalid scenario name")


func set_pending_workshop_resume_path(json_path: String) -> void:
	_pending_workshop_resume_path = json_path.strip_edges()


func peek_pending_workshop_resume_path() -> String:
	return _pending_workshop_resume_path


## Returns and clears the pending resume path. Call at most once per session
## start so a later "New Story Log" doesn't unexpectedly reload it.
func take_pending_workshop_resume_path() -> String:
	var path: String = _pending_workshop_resume_path
	_pending_workshop_resume_path = ""
	return path


func get_collection_display_name(collection_id: String) -> String:
	var display_name: String = String(COLLECTION_DISPLAY_NAMES.get(collection_id, ""))
	if not display_name.is_empty():
		return display_name
	return collection_id.replace("_", " ").capitalize()


func set_custom_workshop_scenario(source: Dictionary) -> bool:
	current_session_type = "workshop_catalyst"
	current_collection_id = "decision_triage"
	if not scenario_loader.load_workshop_dictionary(source):
		return false
	if metaprompt_manager and is_instance_valid(metaprompt_manager):
		remove_child(metaprompt_manager)
	metaprompt_manager = get_metaprompt_manager_for_collection(
		current_session_type,
		current_collection_id
	)
	add_child(metaprompt_manager)
	var full_scenario: Dictionary = scenario_loader.get_current_scenario()
	current_scenario_metaprompt = String(
		full_scenario.get("id", "custom_workshop_scenario")
	)
	current_scenario = full_scenario.duplicate(true)
	set_character_templates([])
	set_character_pool([])
	set_selected_characters([])
	get_game_flow_manager().set_current_scenario(full_scenario)
	is_scenario_selected = true
	scenario_changed.emit(current_scenario_metaprompt)
	return true


## Apply a Workshop scenario dict received from the ENet host (custom draft or
## authored template already expanded). Prefer this over name-only sync so
## joining clients do not need a local copy of the host's Scenario.
func apply_synced_workshop_scenario(scenario: Dictionary) -> bool:
	if scenario.is_empty():
		return false
	current_session_type = "workshop_catalyst"
	current_collection_id = String(
		scenario.get("collection_id", "decision_triage")
	).strip_edges()
	if current_collection_id.is_empty():
		current_collection_id = "decision_triage"
	# Try the draft/normalizer path first (works for create_custom payloads).
	if scenario_loader and scenario_loader.has_method("load_workshop_dictionary"):
		if scenario_loader.load_workshop_dictionary(scenario):
			var loaded: Dictionary = scenario_loader.get_current_scenario()
			if not loaded.is_empty():
				scenario = loaded
	if metaprompt_manager and is_instance_valid(metaprompt_manager):
		remove_child(metaprompt_manager)
	metaprompt_manager = get_metaprompt_manager_for_collection(
		current_session_type,
		current_collection_id
	)
	add_child(metaprompt_manager)
	current_scenario_metaprompt = String(
		scenario.get("id", scenario.get("name", "custom_workshop_scenario"))
	)
	current_scenario = scenario.duplicate(true)
	set_character_templates([])
	set_character_pool([])
	set_selected_characters([])
	get_game_flow_manager().set_current_scenario(current_scenario)
	is_scenario_selected = true
	scenario_changed.emit(current_scenario_metaprompt)
	return true

func set_custom_story_scenario(source: Dictionary) -> bool:
	current_session_type = "story_catalyst"
	current_collection_id = "open_play"
	if not scenario_loader or not scenario_loader.has_method("load_story_dictionary"):
		return false
	if not scenario_loader.load_story_dictionary(source):
		return false
	if metaprompt_manager and is_instance_valid(metaprompt_manager):
		remove_child(metaprompt_manager)
	metaprompt_manager = get_metaprompt_manager_for_collection(
		current_session_type,
		current_collection_id
	)
	add_child(metaprompt_manager)
	var full_scenario: Dictionary = scenario_loader.get_current_scenario()
	current_scenario_metaprompt = String(
		full_scenario.get("id", "custom_open_play_scenario")
	)
	current_scenario = full_scenario.duplicate(true)
	var characters_any: Variant = full_scenario.get("characters", [])
	var characters: Array = characters_any if typeof(characters_any) == TYPE_ARRAY else []
	set_character_templates(characters)
	set_character_pool([])
	set_selected_characters([])
	get_game_flow_manager().set_current_scenario(full_scenario)
	is_scenario_selected = true
	scenario_changed.emit(current_scenario_metaprompt)
	return true


## Apply an Open Play / custom Story scenario received from the ENet host.
func apply_synced_story_scenario(scenario: Dictionary) -> bool:
	if scenario.is_empty():
		return false
	current_session_type = "story_catalyst"
	current_collection_id = String(scenario.get("_collection_id", "open_play")).strip_edges()
	if current_collection_id.is_empty():
		current_collection_id = "open_play"
	if scenario_loader and scenario_loader.has_method("load_story_dictionary"):
		if scenario_loader.load_story_dictionary(scenario):
			var loaded: Dictionary = scenario_loader.get_current_scenario()
			if not loaded.is_empty():
				scenario = loaded
	if metaprompt_manager and is_instance_valid(metaprompt_manager):
		remove_child(metaprompt_manager)
	metaprompt_manager = get_metaprompt_manager_for_collection(
		current_session_type,
		current_collection_id
	)
	add_child(metaprompt_manager)
	current_scenario_metaprompt = String(
		scenario.get("id", scenario.get("name", "custom_open_play_scenario"))
	)
	current_scenario = scenario.duplicate(true)
	var characters_any: Variant = current_scenario.get("characters", [])
	var characters: Array = characters_any if typeof(characters_any) == TYPE_ARRAY else []
	set_character_templates(characters)
	set_character_pool([])
	set_selected_characters([])
	get_game_flow_manager().set_current_scenario(current_scenario)
	is_scenario_selected = true
	scenario_changed.emit(current_scenario_metaprompt)
	return true


func has_scenario_been_selected() -> bool:
	return is_scenario_selected
	
func switch_scenario(new_scenario_name: String) -> void:
	set_current_scenario_metaprompt(new_scenario_name)
	# Signal already emitted by set_current_scenario_metaprompt, no need to emit again

func format_scenario_name(scenario_name: String) -> String:
	# Convert underscore to spaces and capitalize each word
	var words = scenario_name.split("_")
	for i in range(words.size()):
		words[i] = words[i].capitalize()
	return " ".join(words)
