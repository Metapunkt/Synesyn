extends RefCounted
class_name WorkshopWorkspacePresetModel

## Pure Workshop Catalyst dashboard state. Groups map to named regions/content,
## never interchangeable cards. Safety controls are absent so presets cannot hide them.

const PRESET_TALK := "talk"
const PRESET_MAP := "map"
const PRESET_REVIEW := "review"
const PRESET_HOW_TO := "how_to"
const PRESET_FULL_DASHBOARD := "full_dashboard"
const PRESET_CUSTOM := "custom"

const GROUP_CONVERSATION := "conversation"
const GROUP_THINKING_MAP := "thinking_map"
const GROUP_AI_ASSISTANT := "ai_assistant"
const GROUP_SESSION_RECORD := "session_record"
const GROUP_PARTICIPANTS := "participants"
const GROUP_SESSION_MENU := "session_menu"

const GROUP_IDS: Array[String] = [
	GROUP_CONVERSATION,
	GROUP_THINKING_MAP,
	GROUP_AI_ASSISTANT,
	GROUP_SESSION_RECORD,
	GROUP_PARTICIPANTS,
	GROUP_SESSION_MENU,
]

const PRESET_IDS: Array[String] = [
	PRESET_TALK,
	PRESET_MAP,
	PRESET_REVIEW,
	PRESET_HOW_TO,
	PRESET_FULL_DASHBOARD,
	PRESET_CUSTOM,
]


static func default_custom_visibility() -> Dictionary:
	return visibility_for_preset(PRESET_FULL_DASHBOARD, {})


static func visibility_for_preset(preset_id: String, custom_visibility: Dictionary) -> Dictionary:
	match sanitize_preset_id(preset_id):
		PRESET_TALK:
			return _visibility([
				"conversation", "ai_assistant", "session_record",
				"participants", "session_menu",
			])
		PRESET_MAP:
			return _visibility([
				"thinking_map", "ai_assistant", "session_record",
				"participants", "session_menu"
			])
		PRESET_REVIEW:
			return _visibility(["session_record", "participants", "session_menu"])
		PRESET_HOW_TO:
			return _visibility([
				"ai_assistant", "session_record", "participants", "session_menu"
			])
		PRESET_CUSTOM:
			return sanitize_visibility(custom_visibility)
		_:
			return _visibility(GROUP_IDS)


static func sanitize_preset_id(preset_id: String) -> String:
	var normalized_id: String = preset_id.strip_edges().to_lower()
	return normalized_id if normalized_id in PRESET_IDS else PRESET_FULL_DASHBOARD


static func sanitize_visibility(candidate_visibility: Dictionary) -> Dictionary:
	var sanitized: Dictionary = {}
	var defaults: Dictionary = _visibility(GROUP_IDS)
	for group_id: String in GROUP_IDS:
		sanitized[group_id] = candidate_visibility.get(group_id, defaults[group_id]) == true
	return sanitized


static func with_manual_toggle(
	custom_visibility: Dictionary,
	group_id: String,
	is_group_visible: bool
) -> Dictionary:
	var updated: Dictionary = sanitize_visibility(custom_visibility)
	if group_id in GROUP_IDS:
		updated[group_id] = is_group_visible
	return updated


static func _visibility(visible_group_ids: Array[String]) -> Dictionary:
	var result: Dictionary = {}
	for group_id: String in GROUP_IDS:
		result[group_id] = group_id in visible_group_ids
	return result
