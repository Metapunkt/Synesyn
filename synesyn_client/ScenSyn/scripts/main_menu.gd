# scripts/main_menu.gd
extends Control

const _LOGO_DARK := preload("res://ScenSyn/scene_images/ScenSyn_logo_2.svg")
const _LOGO_WHITE := preload("res://ScenSyn/scene_images/ScenSyn_logo_2_white.svg")
const _BG_DARK := preload("res://Synesyn_icons/synesyn-backgrounds/bg_main_home_dark.png")
const _BG_LIGHT := preload("res://Synesyn_icons/synesyn-backgrounds/bg_main_home_light.png")
const FacilitatorSessionSetupScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/facilitator_session_setup.gd"
)
const SynesynToolsNavScript = preload("res://ScenSyn/scripts/synesyn_tools_nav.gd")
const HomeReadinessScript = preload("res://ScenSyn/scripts/scensyn_home_readiness.gd")

@onready var _main_logo: TextureRect = %ScenSynLogo4
@onready var _bg_image: TextureRect = %BackgroundImage
@onready var _bg_rect: ColorRect = %ColorRect
@onready var new_game_button = %NewGameButton
@onready var build_scenario_button = %BuildScenarioButton
@onready var playable_scenarios_button = %PlayableScenariosButton
@onready var game_mode_popup = %GameModePopup
@onready var finish_button = %FinishButton
@onready var services_panel = %ServicesPanel
@onready var tools_button = %ToolsButton
@onready var services_menu_button = %ServicesMenuButton
@onready var hamburger_menu_btn = %HamburgerMenuBtn
@onready var hamburger_settings_panel = %HamburgerSettingsPanel
@onready var services_button_hamburger = %ServicesButton
@onready var back_button_hamburger = %BackButton
@onready var theme_toggle_button = %ThemeToggleButton
@onready var readiness_banner: Control = get_node_or_null("%ReadinessBanner")
@onready var readiness_label: Label = get_node_or_null("%ReadinessLabel")
@onready var open_settings_button: Button = get_node_or_null("%OpenSettingsButton")
@onready var readiness_spacer: Control = get_node_or_null("%ReadinessSpacer")
var scenario_container: VBoxContainer
var current_scenario
var game_flow_manager
var current_scenario_name
#@onready var Network = %Network

func _ready():
	new_game_button.pressed.connect(func(): _on_game_button_pressed("new_game"))
	build_scenario_button.pressed.connect(func(): _on_game_button_pressed("build_scenario"))
	playable_scenarios_button.pressed.connect(func(): _on_game_button_pressed("playable_scenarios"))
	finish_button.pressed.connect(_on_check_current_scenario_button_pressed)
	if tools_button:
		tools_button.pressed.connect(_open_tools)
	if services_menu_button:
		services_menu_button.visible = false
	if open_settings_button:
		open_settings_button.pressed.connect(_open_settings_from_readiness)
	Network.is_host = false
	
	game_flow_manager = Global.get_game_flow_manager()
	current_scenario = game_flow_manager.get_current_scenario()
	current_scenario_name = Global.current_scenario_metaprompt
	
	game_mode_popup.mode_selected.connect(_on_mode_selected)
	# Connect to the client_start_game_signal
	Network.client_start_game_signal.connect(_on_client_start_game)
	
	# Wire hamburger menu
	if hamburger_menu_btn:
		hamburger_menu_btn.pressed.connect(_on_hamburger_menu_pressed)
	if services_button_hamburger:
		services_button_hamburger.pressed.connect(_toggle_services_panel)
	if back_button_hamburger:
		back_button_hamburger.pressed.connect(_on_back_to_launcher)
	if theme_toggle_button:
		theme_toggle_button.pressed.connect(_on_theme_toggle_pressed)
		_update_theme_toggle_label()
		if ThemeManager:
			ThemeManager.mode_changed.connect(func(_m): _update_theme_toggle_label(); _update_logo(); _update_bg_opacity())
	_update_logo()
	_update_bg_opacity()

	# Settings overlay: hamburger, F12, Tools → Settings, or the home readiness strip.
	if services_panel:
		if services_panel.has_method("close_panel"):
			services_panel.close_panel()
		else:
			services_panel.visible = false
	if hamburger_settings_panel:
		hamburger_settings_panel.visible = false
	_refresh_home_readiness()
	if WorkspaceBootstrapper and WorkspaceBootstrapper.has_signal("hub_connection_changed"):
		if not WorkspaceBootstrapper.hub_connection_changed.is_connected(_on_hub_connection_changed):
			WorkspaceBootstrapper.hub_connection_changed.connect(_on_hub_connection_changed)
	if PluginManager and PluginManager.has_signal("initialization_completed"):
		if not PluginManager.initialization_completed.is_connected(_refresh_home_readiness):
			PluginManager.initialization_completed.connect(_refresh_home_readiness)
	call_deferred("_refresh_home_readiness")
	if services_panel and not services_panel.visibility_changed.is_connected(_refresh_home_readiness):
		services_panel.visibility_changed.connect(_refresh_home_readiness)
	get_tree().create_timer(2.0).timeout.connect(_on_readiness_retry)
	
func _exit_tree():
	Network.client_start_game_signal.disconnect(_on_client_start_game)
	if WorkspaceBootstrapper and WorkspaceBootstrapper.has_signal("hub_connection_changed"):
		if WorkspaceBootstrapper.hub_connection_changed.is_connected(_on_hub_connection_changed):
			WorkspaceBootstrapper.hub_connection_changed.disconnect(_on_hub_connection_changed)
	if PluginManager and PluginManager.has_signal("initialization_completed"):
		if PluginManager.initialization_completed.is_connected(_refresh_home_readiness):
			PluginManager.initialization_completed.disconnect(_refresh_home_readiness)

func _on_theme_toggle_pressed() -> void:
	if ThemeManager:
		ThemeManager.toggle_mode()

func _update_theme_toggle_label() -> void:
	if not theme_toggle_button or not ThemeManager:
		return
	theme_toggle_button.text = "Switch to Light Mode" if ThemeManager.is_dark() else "Switch to Dark Mode"

func _update_logo() -> void:
	if not _main_logo or not ThemeManager:
		return
	_main_logo.texture = _LOGO_WHITE if ThemeManager.is_dark() else _LOGO_DARK

func _update_bg_opacity() -> void:
	if not is_instance_valid(_bg_image) or not ThemeManager:
		return
	var is_dark_mode: bool = ThemeManager.is_dark()
	_bg_image.texture = _BG_DARK if is_dark_mode else _BG_LIGHT
	_bg_image.modulate.a = 1.0
	_bg_image.visible = true
	if is_instance_valid(_bg_rect):
		_bg_rect.color = (
			Color(0.039, 0.055, 0.078, 1.0) if is_dark_mode else Color(0.953, 0.965, 0.984, 1.0)
		)

func _on_hamburger_menu_pressed():
	if services_panel and services_panel.has_method("is_panel_open") and services_panel.is_panel_open():
		services_panel.close_panel()
		if hamburger_settings_panel:
			hamburger_settings_panel.visible = false
		return
	if hamburger_settings_panel:
		hamburger_settings_panel.visible = not hamburger_settings_panel.visible

func _on_hub_connection_changed(_is_connected: bool) -> void:
	_refresh_home_readiness()


func _on_readiness_retry() -> void:
	if not is_inside_tree():
		return
	_refresh_home_readiness()


func _open_settings_from_readiness() -> void:
	_toggle_services_panel()


func _refresh_home_readiness() -> void:
	if not is_instance_valid(readiness_banner) or not is_instance_valid(readiness_label):
		return
	var status: Dictionary = HomeReadinessScript.assess()
	var state_id: String = String(status.get("state", HomeReadinessScript.STATE_CHECKING))
	var is_ready: bool = state_id == HomeReadinessScript.STATE_READY
	readiness_banner.visible = not is_ready
	readiness_label.text = String(status.get("message", ""))
	if open_settings_button:
		open_settings_button.visible = state_id == HomeReadinessScript.STATE_NEEDS_SETUP
		# The button sits at one end of the row, which would leave the message centred in
		# what is left rather than in the banner. A spacer of the button's own width at the
		# other end restores the symmetry, and hides with it.
		if is_instance_valid(readiness_spacer):
			readiness_spacer.custom_minimum_size.x = (
				open_settings_button.get_combined_minimum_size().x
			)
			readiness_spacer.visible = open_settings_button.visible


func _toggle_services_panel():
	if services_panel:
		if services_panel.has_method("is_panel_open") and services_panel.is_panel_open():
			if hamburger_settings_panel:
				hamburger_settings_panel.visible = false
			return
		if services_panel.has_method("open_panel"):
			services_panel.open_panel()
		else:
			services_panel.visible = true
		if hamburger_settings_panel:
			hamburger_settings_panel.visible = false

func _on_back_to_launcher():
	if services_panel and services_panel.has_method("is_panel_open") and services_panel.is_panel_open():
		services_panel.close_panel()
	# Return to Synesyn Launcher
	get_tree().change_scene_to_file("res://scenes/synesyn_launcher.tscn")

func _open_tools() -> void:
	SynesynToolsNavScript.open_from(
		get_tree(),
		SynesynToolsNavScript.RETURN_SCENSYN_MENU_PATH
	)

#func _on_game_button_pressed(mode: String):
##	Network.reset_network_state()  # Reset the network state before showing the popup
	#game_mode_popup.popup_centered()
	## Store the mode for later use
	#game_mode_popup.set_meta("selected_mode", mode)
##	var selected_scenario = Global.get_current_scenario_metaprompt()
	#print("MODE BEING SELECTED")
	#game_mode_popup.setup_scenario_buttons()

func _on_game_button_pressed(mode: String):
#	Network.reset_network_state()  # Reset the network state before showing the popup
	#game_flow_manager = Global.get_game_flow_manager()
	#current_scenario = game_flow_manager.get_current_scenario()
	#current_scenario_name = Global.current_scenario_metaprompt
	#Global.set_current_scenario_metaprompt(current_scenario_name)
	
	#if Network.is_host or Global.game_flow_manager.get_current_scenario().is_empty():
	#if Network.is_host: #or current_scenario.is_empty():
	if mode == "playable_scenarios":
		if game_mode_popup.has_method("open_fitted"):
			game_mode_popup.open_fitted()
		else:
			game_mode_popup.popup_centered()
	elif mode == "build_scenario":
		_start_single_player(mode)
	# Store the mode for later use
	game_mode_popup.set_meta("selected_mode", mode)
	print("MODE BEING SELECTED")
	
	
#func _on_mode_selected(is_multiplayer: bool, players: Array):	
	#var mode = game_mode_popup.get_meta("selected_mode", "new_game")
	#var game_flow_manager = Global.get_game_flow_manager()
	#
	## Set up the scenario
	#var scenario = load_scenario(mode)
	#game_flow_manager.set_current_scenario(scenario)
	#
	#if is_multiplayer:
		#_start_multiplayer(players, mode)
	#else:
		#_start_single_player(mode)

#func _on_mode_selected(is_multiplayer: bool, players: Array):
	#var selected_scenario = game_mode_popup.get_selected_scenario()
	#var mode = game_mode_popup.get_meta("selected_mode", "new_game")
	#var game_flow_manager = Global.get_game_flow_manager()
	#
##	if Network.is_server():
		## Server selects and sets the scenario
	#var scenario = load_scenario(mode)
	#game_flow_manager.set_current_scenario(scenario)
	#
	#if is_multiplayer:
		#if Network.is_server():
			#Network.rpc("sync_full_scenario", scenario)
		#_start_multiplayer(players, mode)
	#else:
		#_start_single_player(mode)

#func _on_mode_selected(is_multiplayer: bool, players: Array):
	#var selected_scenario = game_mode_popup.get_selected_scenario()
	#var mode = game_mode_popup.get_meta("selected_mode", "new_game")
	#var game_flow_manager = Global.get_game_flow_manager()
	#
	## Load scenario based on mode
	#var scenario = load_scenario(mode)
	#
	## If a specific scenario was selected, override the name and objective
	#if selected_scenario != "":
		#scenario["name"] = selected_scenario
		#scenario["objective"] = "Complete the " + selected_scenario + " scenario"
	#
	#game_flow_manager.set_current_scenario(scenario)
	#
	#if is_multiplayer:
		#if Network.is_server():
			#Network.rpc("sync_full_scenario", scenario)
		#_start_multiplayer(players, mode)
	#else:
		#_start_single_player(mode)

#func _on_mode_selected(is_multiplayer: bool, players: Array):
	#var mode = game_mode_popup.get_meta("selected_mode", "new_game")
	#var game_flow_manager = Global.get_game_flow_manager()
	#
	#var scenario = Network.current_scenario
	#if scenario.is_empty():
		#scenario = load_scenario(mode)
		#if Network.is_server():
			#Network.current_scenario = scenario
			#Network.rpc("sync_full_scenario", scenario)
	#
	#game_flow_manager.set_current_scenario(scenario)
	#
	#if is_multiplayer:
		#_start_multiplayer(players, mode)
	#else:
		#_start_single_player(mode)

#func _on_mode_selected(is_multiplayer: bool, players: Array):
	#var mode = game_mode_popup.get_meta("selected_mode", "new_game")
	#var game_flow_manager = Global.get_game_flow_manager()
	#
	#var scenario = load_scenario(mode)
	#if Network.is_server():
		#var selected_scenario = game_mode_popup.get_selected_scenario()
		#if selected_scenario != "":
			#scenario["name"] = selected_scenario
		#Network.current_scenario = scenario
		#Network.rpc("sync_selected_scenario", scenario)
	#
	#game_flow_manager.set_current_scenario(scenario)
	#
	#if is_multiplayer:
		#_start_multiplayer(players, mode)
	#else:
		#_start_single_player(mode)

func _on_mode_selected(is_multiplayer: bool, players: Array):
	var mode = game_mode_popup.get_meta("selected_mode", "new_game")
	var gf_manager = Global.get_game_flow_manager()
	
	if Network.is_server():
		# Use the scenario that was already loaded by the game mode popup
		var scenario = gf_manager.get_current_scenario()
		print("Loaded scenario:", scenario)
		Network.server_selected_scenario = scenario
		Network.rpc("sync_server_scenario", scenario)
		print("Scenario set in _on_mode_selected:", scenario)
	else:
		# Client: Use the server's scenario
		var server_scenario = Network.get_server_scenario()
		gf_manager.set_current_scenario(server_scenario)
	
	if is_multiplayer:
		_start_multiplayer(players, mode)
	else:
		_start_single_player(mode)
			
func _on_client_connected(id: int):
	if Network.is_server() and not Network.current_scenario.is_empty():
		Network.rpc_id(id, "sync_full_scenario", Network.current_scenario)
						
func _start_multiplayer(players: Array, mode: String):
	print("Setting up multiplayer with players:", players)
	# Network initialization code if needed...
	var timeout = 10.0  # 10 seconds timeout
	var time_elapsed = 0.0
	while (multiplayer.multiplayer_peer == null or multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING) and time_elapsed < timeout:
		await get_tree().create_timer(0.1).timeout
		time_elapsed += 0.1
	if time_elapsed >= timeout:
		push_error("Multiplayer setup timed out.")
		return
		
	if multiplayer.multiplayer_peer == null:
		push_error("Multiplayer setup failed.")
		return

	print("Network setup complete. Is host: ", multiplayer.is_server())
	# Initialize player info
	var peer_id = multiplayer.get_unique_id()
	var player_name = "Player_" + str(peer_id)  # Modify as needed
	var peer_info = Network.get_peer_info()
	peer_info[peer_id] = {"name": player_name}
	# Update player info across peers
	Network.rpc("update_peer_info", peer_id, peer_info[peer_id])

	if multiplayer.is_server():
		_start_game(mode)
	else:
		# Clients wait for the host to start the game
		_on_client_start_game(mode)
	#await Network.client_start_game_signal
		#_change_scene(mode)

func _start_single_player(mode: String):
	# Single-player must ignore any stale ENet peer from an earlier multiplayer attempt.
	Network.reset_network_state()
	_start_game(mode)

func _start_game(mode: String):
	if Network.is_multiplayer() and Network.is_server():
		# Host sends RPC to clients to start the game
		Network.rpc("rpc_client_start_game", mode)
	_change_scene(mode)

func _on_client_start_game(mode: String):
	_change_scene(mode)

func _change_scene(mode: String):
	match mode:
		"new_game":
			get_tree().change_scene_to_file("res://ScenSyn/scenes/game_session.tscn")
		"build_scenario":
			get_tree().change_scene_to_file("res://ScenSyn/scenes/scenario_builder.tscn")
		"playable_scenarios":
			var session_type_id: String = String(
				Global.current_session_type
			)
			if FacilitatorSessionSetupScript.should_bypass_character_selection(
				session_type_id
			):
				# Single-player: this device is Facilitator. Multiplayer WC:
				# identity comes from the in-session claim/name dialog (ADR 0013);
				# start as a temporary participant so we do not stamp every peer
				# as Facilitator before a claim exists.
				if Network.is_enet_session():
					FacilitatorSessionSetupScript.apply_participant(
						Global, StoryState, "Participant"
					)
				else:
					FacilitatorSessionSetupScript.apply(Global, StoryState)
			get_tree().change_scene_to_file(
				FacilitatorSessionSetupScript.entry_scene_path(session_type_id)
			)
		_:
			print("Unknown game mode: ", mode)

# REMOVED: Obsolete hardcoded scenario function - now using proper theme-based scenario loading system

func _on_check_current_scenario_button_pressed():
	Global.set_current_scenario_metaprompt(current_scenario_name)
	print("Here is a GAME_MODE_POPUP check FOR CURRENT SCENARIO: ", str(game_flow_manager.get_current_scenario()))
