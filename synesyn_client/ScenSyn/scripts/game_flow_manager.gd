# game_flow_manager.gd
extends Node

class_name GameFlowManager

signal game_started(scenario)
signal game_ended(scenario)
signal turn_completed(turn_number)

const MAX_TURNS = 20
const MAX_SESSIONS_PER_SCENARIO = 3

var current_turn = 0
var current_session = 0
var current_scenario: Dictionary = {}

func set_current_scenario(scenario: Dictionary):
	# Avoid deep-duplicating arbitrary scenario payloads; a cyclic Dictionary will
	# recurse until stack overflow. We keep a shallow copy to prevent accidental
	# external mutation of the top-level keys.
	print("Setting current scenario in game_flow_manager (name only): ", scenario.get("name", "Unnamed Scenario"))
	current_scenario = scenario.duplicate(false)
	current_session = 0
	current_turn = 0

func start_new_game():
	if can_start_new_session():
		current_session += 1
		current_turn = 0
		emit_signal("game_started", current_scenario)
	else:
		print("Cannot start new game. Session limit reached.")

func end_game():
	emit_signal("game_ended", current_scenario)
	current_session = 0
	current_turn = 0

func increment_turn():
	current_turn += 1
	emit_signal("turn_completed", current_turn)
	if current_turn >= MAX_TURNS:
		end_game()
	return current_turn <= MAX_TURNS

func get_current_turn():
	return current_turn

func is_game_over():
	return current_turn >= MAX_TURNS

func can_start_new_session() -> bool:
	return current_session < MAX_SESSIONS_PER_SCENARIO

func get_current_scenario() -> Dictionary:
	# Do NOT deep-duplicate: scenario dictionaries can (and sometimes do) contain
	# cyclic references or Objects/Resources. Deep duplication can stack overflow.
	print("Getting current scenario from game_flow_manager (name only): ", current_scenario.get("name", "Unnamed Scenario"))
	return current_scenario.duplicate(false)

func get_current_session() -> int:
	return current_session

@rpc("authority", "call_local")
func sync_turn(turn: int):
	current_turn = turn

func is_multiplayer() -> bool:
	return Network.is_server() or Network.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

@rpc("any_peer", "call_local")
func sync_game_state(scenario: Dictionary, session: int, turn: int):
	set_current_scenario(scenario)
	current_session = session
	current_turn = turn
	print("Game state synced. Scenario: ", scenario, " Session: ", session, " Turn: ", turn)

func get_scenario_name() -> String:
	return current_scenario.get("name", "Unnamed Scenario")
