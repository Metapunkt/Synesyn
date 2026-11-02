# Network.gd
extends Node

signal message_received(message_data)
signal peer_connected(peer_id)
@warning_ignore("unused_signal")
signal peer_disconnected(peer_id) # Used by multiplayer system; kept for future listeners.
signal peer_character_selected(peer_id, character_index)
signal player_input_received(sender_id, user_input)
signal story_state_updated(new_state)
signal character_selection_failed(reason)
signal client_start_game_signal(mode)
#signal scenario_loaded(scenario_name)
@warning_ignore("unused_signal")
signal scenario_updated(scenario_name) # Emitted for UI / flow hooks; kept for external listeners.
signal connection_succeeded
signal connection_failed
signal game_ready
signal server_scenario_updated
signal scenario_synced
#signal sync_server_scenario
@warning_ignore("unused_signal")
signal scenario_changed # Emitted for UI / flow hooks; kept for external listeners.
signal peer_info_updated
signal peer_info_cleared

const DEFAULT_PORT = 28960
const MAX_PEERS = 4
const WorkshopPresenceSyncScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_presence_sync.gd"
)

var peer : ENetMultiplayerPeer = null
var _peer_info = {}
var _connected_peers = []
var character_pool = []
var udp: PacketPeerUDP
var is_host: bool = false
var game_ready_emitted: bool = false
var _processed_inputs = []
var server_created: bool = false
#var is_scenario_loaded = false
var loaded_scenario_name = ""
var is_first_instance: bool = true
var current_scenario: Dictionary = {}
var server_selected_scenario: Dictionary = {}
## WC multi-instance presence (ADR 0013). Child node so RPCs share a stable path.
var workshop_presence: Node = null

# Remove local story_state var definition line 38 maybe; but instead create alias to StoryState.

func _init():
	randomize()
		
func _ready():
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connected_fail)
	workshop_presence = WorkshopPresenceSyncScript.new()
	workshop_presence.name = "WorkshopPresenceSync"
	add_child(workshop_presence)
	
	is_host = is_server()
	if is_host:
		generate_character_pool()

func generate_character_pool():
	print("Server: Generating Characters.....")
	var scenario_loader = Global.get_scenario_loader()
	if not scenario_loader:
		push_error("Network: Could not get a valid scenario_loader from Global.")
		return
	
	# The scenario loader now handles character generation based on the loaded scenario.
	character_pool = await scenario_loader.generate_characters(4)

	print("Server: Generated character pool:")
	for character in character_pool:
		print("Generated Character: ", character)

	# Optionally, you can emit a signal here to notify that the character pool has been updated
	#emit_signal("character_pool_updated", character_pool)
							
func create_server(port := DEFAULT_PORT) -> Error:
	if peer:
		peer.close()
	
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(port, MAX_PEERS)
	if error == OK:
		multiplayer.multiplayer_peer = peer
		server_created = true
		is_host = true
		print("Server created successfully on port ", port)
	else:
		print("Failed to create server. Error code: ", error)
	is_first_instance = false
	return error

func join_server(ip: String, port: int) -> Error:
	if peer:
		peer.close()
	
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(ip, port)
	if error == OK:
		multiplayer.multiplayer_peer = peer
		is_host = false
		print("Attempting to connect to server at ", ip, ":", port)
		# Wait for connection to complete
		await get_tree().create_timer(2.0).timeout
		if peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			print("Successfully connected to server")
			emit_signal("connection_succeeded") # Ensure signal is emitted
		else:
			print("Failed to establish connection with server")
			return ERR_CANT_CONNECT
	else:
		print("Failed to create client peer. Error code: ", error)
	is_first_instance = false
	return error

func can_select_scenario() -> bool:
	return is_first_instance or is_server()
	
func _setup_udp(port: int):
	udp = PacketPeerUDP.new()
	var udp_port = port + 1
	var bind_error = udp.bind(udp_port)
	if bind_error == OK:
		print("UDP socket bound successfully on port ", udp_port)
	else:
		print("Failed to bind UDP socket. Error code: ", bind_error)

func is_server() -> bool:
	return is_host
	
func _on_peer_connected(peer_id):
	print("Peer connected: ", peer_id)
	if peer_id not in _connected_peers:
		_connected_peers.append(peer_id)
	emit_signal("peer_connected", peer_id)
	if is_server():
		# Prefer the full scenario dict (required for custom Workshop drafts).
		# sync_selected_scenario only accepts a name string and cannot reload
		# user:// drafts on the joining client.
		var scenario_to_send: Dictionary = server_selected_scenario.duplicate(true)
		if scenario_to_send.is_empty() and Global and Global.get_game_flow_manager():
			var gf_scenario_any: Variant = Global.get_game_flow_manager().get_current_scenario()
			if typeof(gf_scenario_any) == TYPE_DICTIONARY:
				scenario_to_send = (gf_scenario_any as Dictionary).duplicate(true)
		if not scenario_to_send.is_empty():
			rpc_id(peer_id, "sync_server_scenario", scenario_to_send)
		print("Server: Sending initial state to newly connected peer: ", peer_id)
		send_initial_state(peer_id)
		rpc_id(peer_id, "receive_character_pool", character_pool)
	print("Peer Info: ", _peer_info)

@rpc("any_peer")
func receive_character_pool(server_character_pool):
	character_pool = server_character_pool
	Global.set_character_pool(character_pool)
	print("Client: character_pool updated")

func broadcast_character_pool():
	for peer_id in _connected_peers:
		rpc_id(peer_id, "receive_character_pool", character_pool)
						
#func _on_peer_disconnected(peer_id):
	#print("Peer disconnected: ", peer_id)
	#_peer_info.erase(peer_id)
	#_connected_peers.erase(peer_id)
	#emit_signal("peer_disconnected", peer_id)

@rpc("any_peer")
func request_character_pool():
	if is_server():
		print("Server: Client requested character_pool; sending data")
		var sender_id = multiplayer.get_remote_sender_id()
		rpc_id(sender_id, "receive_character_pool", character_pool)
	else:
		print("Client: Received request_character_pool; but not the server")
			
func get_connected_peers() -> Array:
	return _connected_peers
	
func send_message(message: String):
	if is_server():
		rpc("receive_message", multiplayer.get_unique_id(), message)
	else:
		rpc_id(1, "server_receive_message", message)

func get_story_state() -> Dictionary:
	return StoryState.get_state()

func update_story_state(new_state: Dictionary):
	print("Network: update_story_state called (via StoryState)")
	print("Current story_state: ", StoryState.get_state())
	print("New state: ", new_state)
	StoryState.set_state(new_state)
	if is_server():
		print("Server: Syncing story state with clients")
		rpc("sync_story_state", StoryState.get_state())
	# emit local signal so connected systems update
	emit_signal("story_state_updated", StoryState.get_state())

func send_initial_state(peer_id: int):
	var state := StoryState.get_state()
	print("Server: Sending initial state to peer: ", peer_id, " with state: ", state)
	rpc_id(peer_id, "sync_full_peer_info", _peer_info)
	rpc_id(peer_id, "sync_story_state", state)

@rpc("any_peer", "call_local")
func notify_game_ready():
	print("Client: notify_game_ready called on peer ", multiplayer.get_unique_id())
	game_ready_emitted = true
	emit_signal("game_ready")

func notify_clients_game_ready():
	print("Server: Notifying clients that game is ready")
	var peers = multiplayer.get_peers()
	var server_id = multiplayer.get_unique_id()
	for peer_id in peers:
		if peer_id != server_id:
			print("Notifying client peer ", peer_id)
			rpc_id(peer_id, "notify_game_ready")
			
@rpc("any_peer")
func client_ready(selected_character: Dictionary):
	var peer_id = multiplayer.get_remote_sender_id()
	print("Server: Received client_ready from peer_id:", peer_id)
	print("Server: Received selected_character:", selected_character)
	update_peer_info(peer_id, {"selected_character": selected_character})
	broadcast_peer_info()
	print("Server: Updated _peer_info with client's character data")
	# Proceed with any other initialization necessary
#	check_all_clients_ready()

func broadcast_peer_info():
	for peer_id in _peer_info.keys():
		rpc_id(peer_id, "sync_full_peer_info", _peer_info)
						
@rpc("any_peer", "call_local")
func request_initial_state():
	print("request_initial_state called on peer ", multiplayer.get_unique_id())
	if is_server():
		var sender_id = multiplayer.get_remote_sender_id()
		print("Server: request_initial_state called by peer: ", sender_id)
		send_initial_state(sender_id)
	else:
		print("Error: request_initial_state called on client")
		
@rpc("any_peer")
func server_receive_message(message: String):
	var sender_id = multiplayer.get_remote_sender_id()
	rpc("receive_message", sender_id, message)

@rpc("authority", "call_local")
func receive_message(sender_id: int, message: String):
	emit_signal("message_received", {"sender_id": sender_id, "message": message})

@rpc("any_peer", "call_local")
func update_peer_info(id: int, new_peer_info: Dictionary):
	print("Updating peer info for id:", id, "with data:", new_peer_info)
	if _peer_info.has(id):
		for key in new_peer_info.keys():
			var value = new_peer_info[key]
			if key == "selected_character":
				# Replace entire character data; duplicate only if value is Dictionary
				if typeof(value) == TYPE_DICTIONARY:
					_peer_info[id][key] = value.duplicate(true)
				else:
					_peer_info[id][key] = value  # null or other simple type
			else:
				# For other keys, merge / replace as-is (duplicate collections)
				if typeof(value) in [TYPE_DICTIONARY, TYPE_ARRAY]:
					_peer_info[id][key] = value.duplicate(true)
				else:
					_peer_info[id][key] = value
	else:
		# New entry
		var entry_copy = {}
		for k in new_peer_info.keys():
			var v = new_peer_info[k]
			entry_copy[k] = v.duplicate(true) if typeof(v) in [TYPE_DICTIONARY, TYPE_ARRAY] else v
		_peer_info[id] = entry_copy
	print("Updated _peer_info:", _peer_info)
	
	# Broadcast to all peers
	rpc("sync_full_peer_info", _peer_info)

#@rpc("reliable")
#func notify_scenario_loaded(scenario_name: String):
	#if not is_server():
		#Global.set_current_scenario_metaprompt(scenario_name)
	#print("Scenario loaded: ", scenario_name)
	#is_scenario_loaded = true
	#loaded_scenario_name = scenario_name
	#emit_signal("scenario_loaded", scenario_name)

#func check_scenario_loaded() -> Dictionary:
	#if scenario_loaded:
		#return {"loaded": true, "name": loaded_scenario_name}
	#else:
		#return {"loaded": false}
		
func get_player_controlled_character_ids() -> Array:
	var ids = []
	for peer_id in _peer_info:
		var selected_character = _peer_info[peer_id].get("selected_character")
		if selected_character:
			ids.append(selected_character.id)
	print("Player controlled character IDs: ", ids)
	return ids

func get_ai_controlled_character_names() -> Array:
	var ai_names = []
	
	# Get AI characters from peer_info (assigned AI entities)
	for peer_id in _peer_info:
		var character = _peer_info[peer_id].get("selected_character", null)
		# An empty selection is still a Dictionary, and a missing is_ai flag
		# defaults to true. Treating that as a cast member inserts a blank
		# name that occupies a speaker slot and the turn looks like one reply.
		if typeof(character) != TYPE_DICTIONARY or (character as Dictionary).is_empty():
			continue
		var character_name := String(character.get("name", "")).strip_edges()
		if character_name.is_empty():
			continue
		if bool(character.get("is_ai", true)) and not ai_names.has(character_name):
			ai_names.append(character_name)
	
	# CRITICAL FIX: Also include unselected scenario characters as AI-controlled
	var scenario = Global.get_current_scenario()
	var all_scenario_characters = scenario.get("characters", [])
	var player_controlled_character_names = get_player_controlled_character_names()
	
	for scenario_character in all_scenario_characters:
		var character_name = scenario_character.get("name", "")
		if character_name != "" and not player_controlled_character_names.has(character_name):
			# This scenario character is not controlled by any player, so it's AI-controlled
			if not ai_names.has(character_name):
				ai_names.append(character_name)
	
	print("Network: Final AI-controlled character names: ", ai_names)
	return ai_names

func get_player_controlled_character_names() -> Array:
	var player_names = []
	for peer_id in _peer_info:
		var peer_info = _peer_info[peer_id]
		var selected_character = peer_info.get("selected_character", {})
		if selected_character and not selected_character.get("is_ai", true):
			player_names.append(selected_character.get("name", ""))
	# Single-player character select stores the human on Global and never writes
	# peer_info. Without this, every scenario character, including the one the
	# player is typing as, is treated as AI and no reply is generated.
	if Global and Global.has_method("get_current_character"):
		var local_character: Dictionary = Global.get_current_character()
		var local_name := String(local_character.get("name", "")).strip_edges()
		var local_is_player: bool = (
			not local_character.is_empty()
			and (
				bool(local_character.get("is_player", false))
				or not bool(local_character.get("is_ai", true))
			)
		)
		if local_is_player and not local_name.is_empty() and not player_names.has(local_name):
			player_names.append(local_name)
	print("Network: Player-controlled character names: ", player_names)
	return player_names

func is_character_ai_controlled(character_name: String) -> bool:
	return character_name in get_ai_controlled_character_names()

func _on_peer_disconnected(id):
	print("Peer disconnected: ", id)
	emit_signal("peer_disconnected", id)
	if workshop_presence and workshop_presence.has_method("is_active") and workshop_presence.is_active():
		workshop_presence.notify_peer_disconnected(id)
	if _peer_info.has(id):
		var disconnected_character = _peer_info[id].get("selected_character")
		if disconnected_character:
			disconnected_character.is_ai = true
			_assign_character_to_ai(disconnected_character)
			
			# NEW: Emit signal for character control change due to disconnection
			emit_signal("peer_character_selected", id, {})  # Empty character means deselection
			
		_peer_info.erase(id)
		rpc("sync_full_peer_info", _peer_info)
		rpc("notify_player_disconnection", id)

func _assign_character_to_ai(character):
	var ai_id = get_next_available_ai_id()
	_peer_info[ai_id] = {"selected_character": character, "player_name": "AI (was " + character.name + ")"}

func get_next_available_ai_id():
	var max_id = _peer_info.keys().max()
	return max_id + 1 if max_id != null else Network.MAX_PEERS + 1

@rpc("reliable")
func notify_player_disconnection(disconnected_id):
	print("Player disconnected: ", disconnected_id)
	# Implement any additional logic needed when a player disconnects
			
@rpc("authority", "call_local")
func _sync_peer_info(peer_id: int, info: Dictionary):
	_peer_info[peer_id] = info

@rpc("any_peer", "call_local")
func sync_full_peer_info(new_peer_info: Dictionary):
	_peer_info = new_peer_info.duplicate(true)  # Create a deep copy
	print("Client: _peer_info synchronized: ", _peer_info)
	# Emit signal so UI can update
	emit_signal("peer_info_updated")

@rpc("any_peer", "call_local")
func sync_peer_character_selection(peer_id: int, selected_character: Dictionary):
	print("=== sync_peer_character_selection called ===")
	print("Peer ID: ", peer_id)
	print("Selected character: ", selected_character)
	print("Current _peer_info: ", _peer_info)
	
	if selected_character.is_empty():
		print("Character deselected, clearing selection for peer ", peer_id)
		update_peer_info(peer_id, {"selected_character": null})
	else:
		# Check if the character is already selected by another peer
		for other_peer_id in _peer_info.keys():
			if other_peer_id != peer_id:
				var other_character = _peer_info[other_peer_id].get("selected_character")
				if other_character:
					# Skip entries still flagged as AI – placeholders shouldn't block players
					if other_character.get("is_ai", true):
						continue
					var other_name = other_character.get("name", "")
					var selected_name = selected_character.get("name", "")
					var other_id = other_character.get("id", -1)
					var selected_id = selected_character.get("id", -1)
					
					# Check by ID first, then by name
					var is_same_character = false
					if selected_id != -1 and other_id != -1:
						is_same_character = (other_id == selected_id)
					else:
						is_same_character = (other_name == selected_name)
					
					if is_same_character:
						print("Character '", selected_name, "' already selected by peer ", other_peer_id)
						if peer_id == multiplayer.get_unique_id():
							# If this is the local peer, emit the signal directly
							emit_signal("character_selection_failed", "Character already selected")
						else:
							# If it's a remote peer, send the RPC
							_on_character_selection_failed.rpc_id(peer_id, "Character already selected")
						return
		
		print("Character '", selected_character.get("name", ""), "' selected by peer ", peer_id)
		update_peer_info(peer_id, {"selected_character": selected_character})
	
	# NEW: Emit signal for character control change to update AI awareness
	emit_signal("peer_character_selected", peer_id, selected_character)
	
	print("Broadcasting peer info to all clients")
	broadcast_peer_info()
	# Broadcast the updated character pool to all peers
	broadcast_character_pool()
	
	print("=== sync_peer_character_selection completed ===")
	print("Final _peer_info: ", _peer_info)

@rpc("authority", "call_remote")
func _on_character_selection_failed(reason: String):
	print("Character selection failed: ", reason)
	# Emit a signal that the UI can listen to for displaying the error
	emit_signal("character_selection_failed", reason)

func is_character_taken(character: Dictionary) -> bool:
	var character_name = character.get("name", "")
	var character_id = character.get("id", -1)
	
	if character_name == "":
		print("Warning: Character has no name for comparison")
		return false
	
	for peer_info in _peer_info.values():
		var selected_character = peer_info.get("selected_character")
		if selected_character:
			# Ignore characters still flagged as AI; they are free to be taken by players
			if selected_character.get("is_ai", true):
				continue
			
			var selected_name = selected_character.get("name", "")
			var selected_id = selected_character.get("id", -1)
			
			# Try ID comparison first, fall back to name comparison
			if character_id != -1 and selected_id != -1:
				if selected_id == character_id:
					print("Character taken by ID (player-controlled): ", character_name, " (ID: ", character_id, ")")
					return true
			elif selected_name == character_name:
				print("Character taken by name (player-controlled): ", character_name)
				return true
	
	print("Character available: ", character_name)
	return false
		
@rpc("any_peer")
func process_player_input(sender_id: int, user_input: String):
	if is_input_processed(sender_id, user_input):
		print("Network: Duplicate input detected, ignoring")
		return

	if is_server():
		print("Network: Server processing player input from sender_id:", sender_id)
		add_processed_input(sender_id, user_input)
		emit_signal("player_input_received", sender_id, user_input)
	else:
		print("Network: Client attempting to process_player_input locally")
		# This shouldn't happen, but log it just in case

func is_input_processed(sender_id: int, user_input: String) -> bool:
	return _processed_inputs.has([sender_id, user_input])

func add_processed_input(sender_id: int, user_input: String):
	_processed_inputs.append([sender_id, user_input])
	if _processed_inputs.size() > 10:  # Keep only the last 10 processed inputs
		_processed_inputs.pop_front()

func send_player_input(user_input: String):
	if not is_server():
		print("Network: Client sending process_player_input to server")
		rpc_id(1, "process_player_input", multiplayer.get_unique_id(), user_input)
	else:
		print("Network: Server attempting to send_player_input")
		# This shouldn't happen, but log it just in case

@rpc("authority", "call_local")
func sync_player_input(sender_id: int, user_input: String):
	if not is_server():
		emit_signal("player_input_received", sender_id, user_input)		
	
@rpc("authority", "call_remote")
func sync_story_log(sender: String, message: String):
	emit_signal("message_received", {"sender_id": sender, "message": message})
	
@rpc("any_peer", "call_local")
func sync_story_state(new_state: Dictionary):
	
	print("Peer: Received sync_story_state")
	if not is_server():
		StoryState.set_state(new_state)
		emit_signal("story_state_updated", StoryState.get_state())
#	emit_signal("story_state_updated", story_state)

@rpc("any_peer")
func rpc_client_start_game(mode: String):
	emit_signal("client_start_game_signal", mode)

@rpc("reliable")
func sync_selected_scenario(scenario_name: String):
	var peer_id = multiplayer.get_remote_sender_id()
	if _peer_info.has(peer_id):
		_peer_info[peer_id]["selected_scenario"] = scenario_name
	Global.set_current_scenario_metaprompt(scenario_name)
	if is_server():
		var full_scenario = Global.quick_test_scenario.get_scenario()
		full_scenario["name"] = Global.format_scenario_name(scenario_name)
		Global.get_game_flow_manager().set_current_scenario(full_scenario)	
		emit_signal("scenario_synced", scenario_name)
		Global.emit_signal("scenario_changed", scenario_name)
	rpc("client_sync_scenario", Global.game_flow_manager.get_current_scenario())

@rpc func client_sync_scenario(scenario: Dictionary):
	if not is_server():
		Global.game_flow_manager.set_current_scenario(scenario)
		# Cache scenario in Global for fast, recursion-safe access (e.g. StoryStage sprites).
		if Global:
			Global.current_scenario = scenario.duplicate(false)
		
@rpc("reliable")
func sync_full_scenario(scenario: Dictionary):
	current_scenario = scenario
	if not is_server():
		Global.get_game_flow_manager().set_current_scenario(scenario)
		Global.set_current_scenario_metaprompt(scenario["name"])
		if Global:
			Global.current_scenario = scenario.duplicate(false)
		
	print("Scenario synced: ", scenario.get("name", "Unnamed Scenario"))		
	
func _on_connected_ok():
	print("Connected to server successfully")
	emit_signal("connection_succeeded")

func _on_connected_fail():
	print("Failed to connect to server")
	emit_signal("connection_failed")

func get_peer_name(id: int) -> String:
	return _peer_info.get(id, {}).get("player_name", "Unknown Peer")
	
func get_character_name(peer_id: int) -> String:
	var peer_info = _peer_info.get(peer_id, {})
	var selected_character = peer_info.get("selected_character", {})
	if typeof(selected_character) == TYPE_DICTIONARY and selected_character.has("name"):
		return selected_character["name"]
	return peer_info.get("player_name", "Unknown Character")

func reconnect_peer(peer_id: int):
	if _peer_info.has(peer_id):
		var peer_data = _peer_info[peer_id]
		rpc_id(peer_id, "sync_peer_info", peer_id, peer_data)
		rpc_id(peer_id, "sync_full_peer_info", _peer_info)
	else:
		print("Error: Reconnecting peer not found in peer info")
						
func get_connection_status() -> int:
	if multiplayer.multiplayer_peer:
		return multiplayer.multiplayer_peer.get_connection_status()
	else:
		return MultiplayerPeer.CONNECTION_DISCONNECTED

func is_multiplayer() -> bool:
	return multiplayer.multiplayer_peer != null


## True only when an ENet host/client peer was created for a live session.
## Prefer this over is_multiplayer() for Workshop Catalyst: Godot always installs
## an OfflineMultiplayerPeer, so is_multiplayer() is true even in single-player.
func is_enet_session() -> bool:
	return peer != null and is_instance_valid(peer)

func get_peer_info() -> Dictionary:
	return _peer_info

func get_multiplayer_peer():
	return multiplayer.multiplayer_peer

func reset_network_state():
	if peer:
		peer.close()
	peer = null
	multiplayer.multiplayer_peer = null
	is_host = false
	server_created = false
	game_ready_emitted = false
	is_first_instance = true
	current_scenario.clear()
	server_selected_scenario.clear()
	character_pool.clear()
	_peer_info.clear()
	_connected_peers.clear()
	if workshop_presence and workshop_presence.has_method("deactivate"):
		workshop_presence.deactivate()
	print("Network: reset_network_state completed - cleared multiplayer peer and session state")

func get_workshop_presence() -> Node:
	return workshop_presence
	
func _process(_delta):
#	print("Peer Info: ", _peer_info)
	if is_server() and udp and udp.get_available_packet_count() > 0:
		var sender_ip = udp.get_packet_ip()
		var sender_port = udp.get_packet_port()
		var data = udp.get_packet()
		if data.get_string_from_utf8() == "Are you there?":
			udp.set_dest_address(sender_ip, sender_port)
			udp.put_packet("Yes, I'm here".to_utf8_buffer())
			
func has_scenario_been_assigned() -> bool:
	for peer_info in _peer_info.values():
		if peer_info.has("selected_scenario") and peer_info["selected_scenario"] != null:
			return true
	return false

func get_assigned_scenario() -> Dictionary:
	for peer_info in _peer_info.values():
		if peer_info.has("selected_scenario") and peer_info["selected_scenario"] != null:
			return peer_info["selected_scenario"]
	return {}

#@rpc("reliable")
#func sync_server_scenario(scenario: Dictionary):
	#set_server_scenario(scenario)
	#if not is_server():
		#Global.get_game_flow_manager().set_current_scenario(scenario)

@rpc("any_peer", "call_local") 
func sync_server_scenario(scenario: Dictionary):
	print("sync_server_scenario RPC called with scenario:", scenario)
	server_selected_scenario = scenario.duplicate(true)
	print("server_selected_scenario set to:", server_selected_scenario)
	if Global:
		# Prefer typed apply helpers so session_type, collection, and metaprompt
		# manager match the host (custom Workshop or Open Play drafts).
		var scenario_id: String = String(scenario.get("id", "")).strip_edges()
		var collection_id: String = String(scenario.get("_collection_id", "")).strip_edges()
		var looks_like_open_play: bool = (
			scenario_id == "custom_open_play_scenario"
			or collection_id == "open_play"
			or (
				String(scenario.get("_session_type_id", "")) == "story_catalyst"
				and (scenario.has("plot_twists") or scenario.has("tags"))
			)
		)
		var looks_like_workshop: bool = (
			scenario_id == "custom_workshop_scenario"
			or scenario.has("workshop_packet")
			or scenario.has("agenda")
			or String(Global.current_session_type) == "workshop_catalyst"
		)
		if looks_like_open_play and Global.has_method("apply_synced_story_scenario"):
			Global.apply_synced_story_scenario(scenario)
		elif looks_like_workshop and Global.has_method("apply_synced_workshop_scenario"):
			Global.apply_synced_workshop_scenario(scenario)
		else:
			Global.get_game_flow_manager().set_current_scenario(scenario)
			Global.current_scenario = scenario.duplicate(false)
	print("Scenario set in game_flow_manager from RPC:", Global.get_game_flow_manager().get_current_scenario())
	emit_signal("server_scenario_updated")
	emit_signal("scenario_updated", scenario.get("name", ""))
	emit_signal("scenario_changed")
	
func set_server_scenario(scenario: Dictionary):
	print("Setting server scenario in Network:", scenario)
	server_selected_scenario = scenario.duplicate(true)
	# Signal is declared with 0 args; listeners (e.g. game_mode_popup) read via
	# get_server_scenario(). Passing the Dictionary here crashes the handler.
	emit_signal("server_scenario_updated")
	emit_signal("scenario_updated", scenario.get("name", ""))
	emit_signal("scenario_changed")
	
func get_server_scenario() -> Dictionary:
	print("Getting server scenario from Network:", server_selected_scenario)
	return server_selected_scenario.duplicate(true)
	
@rpc("any_peer")
func request_current_scenario():
	var requester_id = multiplayer.get_remote_sender_id()
	var current_scenario_metaprompt = Global.get_current_scenario_metaprompt()
	if current_scenario_metaprompt:
		rpc_id(requester_id, "receive_current_scenario", current_scenario_metaprompt)

@rpc("reliable")
func receive_current_scenario(scenario_name: String):
	Global.set_current_scenario_metaprompt(scenario_name)
	emit_signal("scenario_synced", scenario_name)
	emit_signal("scenario_updated", scenario_name)
	emit_signal("scenario_changed")
	Global.emit_signal("scenario_changed", scenario_name)

@rpc("reliable") func request_scenario_sync():
	rpc("sync_server_scenario", server_selected_scenario)

# NEW: Function to automatically assign unselected scenario characters as AI-controlled
func assign_unselected_characters_to_ai():
	"""
	Ensure all scenario characters not selected by players are AI-controlled.
	This is called when the game starts.
	"""
	print("Network: Assigning unselected scenario characters to AI")
	
	var scenario = Global.get_current_scenario()
	var all_scenario_characters = scenario.get("characters", [])
	var player_controlled_ids = []
	
	# Get all player-controlled character IDs
	for peer_id in _peer_info:
		var character = _peer_info[peer_id].get("selected_character", {})
		if character and not character.get("is_ai", true):
			player_controlled_ids.append(character.get("id", -1))
	
	print("Network: Player-controlled character IDs: ", player_controlled_ids)
	print("Network: All scenario characters: ", all_scenario_characters.map(func(c): return c.get("name", "Unnamed")))
	
	# Find unselected characters and assign them to AI
	var next_ai_id = get_next_available_ai_id()
	var characters_assigned_to_ai = false
	for scenario_character in all_scenario_characters:
		var character_id = scenario_character.get("id", -1)
		if character_id != -1 and not player_controlled_ids.has(character_id):
			# This character is not selected by any player, assign to AI
			var ai_character = scenario_character.duplicate()
			ai_character["is_ai"] = true
			
			print("Network: Assigning unselected character to AI: ", ai_character.get("name", "Unnamed"))
			_peer_info[next_ai_id] = {
				"selected_character": ai_character, 
				"player_name": "AI (" + ai_character.get("name", "Unnamed") + ")"
			}
			next_ai_id += 1
			characters_assigned_to_ai = true
	
	print("Network: Final _peer_info after AI assignment: ")
	for peer_id in _peer_info:
		var info = _peer_info[peer_id]
		var character = info.get("selected_character", {})
		if character:
			print("  Peer ", peer_id, ": ", character.get("name", "Unknown"), " (is_ai: ", character.get("is_ai", true), ")")
	
	# Sync this with all clients
	rpc("sync_full_peer_info", _peer_info)
	
	# NEW: Emit signal to notify that AI character assignments have changed
	if characters_assigned_to_ai:
		print("Network: Emitting character control change signal for AI assignments")
		emit_signal("peer_character_selected", -1, {})  # Special peer ID -1 indicates AI assignment batch

func reset_character_selection():
	print("Network: Resetting character selection state (clearing _peer_info)")
	_peer_info.clear()
	emit_signal("peer_info_cleared")
	# Broadcast cleared state if server
	if is_server():
		rpc("sync_full_peer_info", _peer_info)
