extends RefCounted
class_name WorkshopPromptContextBuilder

const RECENT_EXCHANGE_LIMIT: int = 8
const RESUME_EXCHANGE_LIMIT: int = 32
const ENTRY_CHAR_LIMIT: int = 500
const SCENARIO_CHAR_LIMIT: int = 1600
const RECORD_CHAR_LIMIT: int = 4000

const ResumeHydrateScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_resume_hydrate.gd"
)

const EXCLUDED_CONTEXT_PHRASES: Array[String] = [
	"the ai couldn't generate a response",
	"timed out waiting for an ai response",
	"could not retain a reliable specialist analysis",
	"batch response could not be structured reliably",
	"specialist output was unavailable",
]


func build(
	story_log: Array,
	human_input: Dictionary,
	scenario: Dictionary,
	workshop_state: Dictionary
) -> Dictionary:
	return {
		"scenario": _scenario_context(scenario),
		"recent_transcript": _recent_transcript(story_log, human_input, workshop_state),
		"session_record": _session_record_context(workshop_state),
	}


func _scenario_context(scenario: Dictionary) -> String:
	var name_text: String = String(scenario.get("name", "")).strip_edges()
	var objective_text: String = String(
		scenario.get("objective", "")
	).strip_edges()
	var packet_text: String = String(
		scenario.get(
			"workshop_packet_text",
			scenario.get("description", "")
		)
	).strip_edges()
	var sections: Array[String] = []
	if not name_text.is_empty():
		sections.append("Scenario: " + name_text)
	if not objective_text.is_empty():
		sections.append("Objective: " + objective_text.left(600))
	if not packet_text.is_empty() and packet_text != objective_text:
		sections.append(packet_text.left(SCENARIO_CHAR_LIMIT))
	return "\n".join(sections)


func _recent_transcript(
	story_log: Array,
	human_input: Dictionary,
	workshop_state: Dictionary = {}
) -> String:
	var exchange_limit: int = RECENT_EXCHANGE_LIMIT
	if String(workshop_state.get("resume_mode", "")) == "continue_prior_session":
		exchange_limit = RESUME_EXCHANGE_LIMIT
	var latest_message: String = String(
		human_input.get("message", "")
	).strip_edges()
	var reverse_lines: Array[String] = []
	for entry_index: int in range(story_log.size() - 1, -1, -1):
		if reverse_lines.size() >= exchange_limit:
			break
		var entry_any: Variant = story_log[entry_index]
		if typeof(entry_any) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_any
		var sender_text: String = String(entry.get("sender", "")).strip_edges()
		var message_text: String = String(entry.get("message", "")).strip_edges()
		if (
			sender_text.is_empty()
			or message_text.is_empty()
			or _is_excluded(message_text)
			or (
				message_text == latest_message
				and sender_text == String(
					human_input.get("sender", "")
				).strip_edges()
			)
		):
			continue
		reverse_lines.append(
			"- %s: %s" % [sender_text, message_text.left(ENTRY_CHAR_LIMIT)]
		)
	reverse_lines.reverse()
	return "\n".join(reverse_lines)


func _session_record_context(workshop_state: Dictionary) -> String:
	return ResumeHydrateScript.session_record_prompt_text(
		workshop_state,
		RECORD_CHAR_LIMIT
	)


func _is_excluded(message_text: String) -> bool:
	var lowered: String = message_text.to_lower()
	for phrase_text: String in EXCLUDED_CONTEXT_PHRASES:
		if lowered.contains(phrase_text):
			return true
	return false
