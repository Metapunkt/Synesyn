extends RefCounted
class_name WorkshopSessionRecordPulse

## Builds the short, one-line ambient status-bar summary of what the hidden
## specialist pass found on a given turn. Kept as a pure static helper (no
## Node/autoload dependencies) so it stays independently testable and so
## ai_character_agent.gd does not need to grow more inline formatting logic.
##
## The full 2-5 paragraph Session Record narrative is cached separately
## (see ai_character_agent.gd::_cache_session_record_synthesis) and is only
## surfaced in the visible log on demand, via the /synthesis facilitator
## command. This pulse is what tells the facilitator analysis happened
## without a wall of text appearing every turn.

const CATEGORY_ORDER: Array[String] = ["cause", "effect", "opportunity"]
const NO_CLAIMS_TEXT := "Session Record: no new claims this turn — type /synthesis for the full recap."


static func build_pulse(batch_result: Dictionary) -> String:
	var candidates_any: Variant = batch_result.get("map_candidates", [])
	var candidates: Array = candidates_any if typeof(candidates_any) == TYPE_ARRAY else []
	var counts_by_category: Dictionary = {}
	for candidate_any: Variant in candidates:
		if typeof(candidate_any) != TYPE_DICTIONARY:
			continue
		var category_id: String = String(candidate_any.get("category", "")).strip_edges()
		if category_id.is_empty():
			continue
		var current_count: int = int(counts_by_category.get(category_id, 0))
		counts_by_category[category_id] = current_count + 1
	if counts_by_category.is_empty():
		return NO_CLAIMS_TEXT
	var parts: Array[String] = []
	for category_id in CATEGORY_ORDER:
		var count: int = int(counts_by_category.get(category_id, 0))
		if count > 0:
			parts.append("%d %s" % [count, _pluralize_category(category_id, count)])
	for category_id: String in counts_by_category.keys():
		if category_id not in CATEGORY_ORDER:
			var extra_count: int = int(counts_by_category.get(category_id, 0))
			parts.append("%d %s" % [extra_count, _pluralize_category(category_id, extra_count)])
	return "Session Record: %s noted — type /synthesis for the full recap." % ", ".join(parts)


static func _pluralize_category(category_id: String, count: int) -> String:
	if count == 1:
		return category_id
	if category_id == "opportunity":
		return "opportunities"
	return category_id + "s"
