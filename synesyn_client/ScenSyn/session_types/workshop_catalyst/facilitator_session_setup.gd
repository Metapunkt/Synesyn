extends RefCounted
class_name FacilitatorSessionSetup

const WORKSHOP_SESSION_TYPE_ID := "workshop_catalyst"
const FACILITATOR_DISPLAY_IDENTITY := "Facilitator"
const GAME_SESSION_SCENE_PATH := "res://ScenSyn/scenes/game_session.tscn"
const CHARACTER_OPTIONS_SCENE_PATH := "res://ScenSyn/scenes/character_options.tscn"

const PresenceStoreScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_presence_store.gd"
)


static func should_bypass_character_selection(session_type_id: String) -> bool:
	return session_type_id == WORKSHOP_SESSION_TYPE_ID


static func entry_scene_path(session_type_id: String) -> String:
	if should_bypass_character_selection(session_type_id):
		return GAME_SESSION_SCENE_PATH
	return CHARACTER_OPTIONS_SCENE_PATH


static func is_facilitator_sender(sender_id: String) -> bool:
	return (
		sender_id == FACILITATOR_DISPLAY_IDENTITY
		or sender_id.ends_with(" (Facilitator)")
	)


static func build_facilitator_identity(display_name: String = FACILITATOR_DISPLAY_IDENTITY) -> Dictionary:
	var clean_name: String = PresenceStoreScript.format_facilitator_display_name(display_name)
	return {
		"name": clean_name,
		"role": FACILITATOR_DISPLAY_IDENTITY,
		"description": "Human workshop facilitator",
		"is_ai": false,
		"is_player": true,
	}


static func build_participant_identity(display_name: String) -> Dictionary:
	var clean_name: String = display_name.strip_edges()
	if clean_name.is_empty():
		clean_name = "Participant"
	return {
		"name": clean_name,
		"role": "Participant",
		"description": "Workshop participant",
		"is_ai": false,
		"is_player": true,
	}


## Text for the session header's character label.
##
## `no_player_display` is what to show when there is no human character to announce
## because the scenario does not have one — a scenario driven by external input rather
## than by a person choosing a role. Without it such a session either advertised
## whichever character was last selected elsewhere, or reported an error for a state
## that is not an error.
static func character_label_text(
	session_type_id: String,
	human_identity: Dictionary,
	no_player_display: String = ""
) -> String:
	if should_bypass_character_selection(session_type_id):
		# Only trust WC-owned identities (role Facilitator/Participant). Legacy
		# callers may still pass a stale stakeholder dict — ignore those.
		var role_text: String = String(human_identity.get("role", "")).strip_edges()
		var named: String = String(human_identity.get("name", "")).strip_edges()
		if (
			not named.is_empty()
			and role_text in [FACILITATOR_DISPLAY_IDENTITY, "Participant"]
		):
			return named
		return FACILITATOR_DISPLAY_IDENTITY
	if not human_identity.is_empty():
		return "You are playing as: " + String(
			human_identity.get("name", "Unnamed Character")
		)
	if not no_player_display.strip_edges().is_empty():
		return no_player_display.strip_edges()
	return "Error: Character information not available"


## Single-player Workshop entry: this device is Facilitator by default.
static func apply(global_node: Node, story_state_node: Node) -> Dictionary:
	return apply_facilitator(global_node, story_state_node, FACILITATOR_DISPLAY_IDENTITY)


static func apply_facilitator(
	global_node: Node,
	story_state_node: Node,
	display_name: String = FACILITATOR_DISPLAY_IDENTITY
) -> Dictionary:
	var facilitator_identity: Dictionary = build_facilitator_identity(display_name)
	_apply_identity(global_node, story_state_node, facilitator_identity, true)
	return facilitator_identity


static func apply_participant(
	global_node: Node,
	story_state_node: Node,
	display_name: String
) -> Dictionary:
	var participant_identity: Dictionary = build_participant_identity(display_name)
	_apply_identity(global_node, story_state_node, participant_identity, false)
	return participant_identity


static func _apply_identity(
	global_node: Node,
	story_state_node: Node,
	identity: Dictionary,
	send_as_facilitator: bool
) -> void:
	if global_node != null:
		global_node.call("set_selected_characters", [])
		global_node.call("set_current_character", identity)
	if story_state_node != null:
		var state_any: Variant = story_state_node.call("get_state")
		var next_state: Dictionary = {}
		if typeof(state_any) == TYPE_DICTIONARY:
			next_state = (state_any as Dictionary).duplicate(true)
		var workshop_any: Variant = next_state.get(WORKSHOP_SESSION_TYPE_ID, {})
		var workshop_state: Dictionary = {}
		if typeof(workshop_any) == TYPE_DICTIONARY:
			workshop_state = (workshop_any as Dictionary).duplicate(true)
		workshop_state["send_as_facilitator"] = send_as_facilitator
		workshop_state["local_display_name"] = String(identity.get("name", ""))
		next_state[WORKSHOP_SESSION_TYPE_ID] = workshop_state
		story_state_node.call("set_state", next_state)
