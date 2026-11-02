extends RefCounted
class_name WorkshopParticipantMapExtractor

const MIN_PROPOSITION_CHARS: int = 24
const MAX_CANDIDATES: int = 3

const OPPORTUNITY_MARKERS: Array[String] = [
	" should ",
	" can ",
	" could ",
	" invest",
	" redirect",
	" adopt",
	" improve",
	" develop",
	" establish",
	" expand",
	" leverage",
	" take advantage",
	" mitigate",
]
const CAUSE_MARKERS: Array[String] = [
	" because ",
	" due to ",
	" drives ",
	" driven by ",
	" caused by ",
	" contributes to ",
	" lack of ",
]
const EFFECT_MARKERS: Array[String] = [
	" leads to ",
	" results in ",
	" increases ",
	" reduces ",
	" affects ",
	" impact ",
	" consequence",
	" outcome",
	" risk of ",
]
const META_MARKERS: Array[String] = [
	"what should we",
	"can we discuss",
	"please explain",
	"continue the discussion",
	"preview",
	"commit",
	"facilitator",
]


func extract(message_text: String) -> Array[Dictionary]:
	var cleaned: String = message_text.strip_edges()
	if cleaned.length() < MIN_PROPOSITION_CHARS or _contains_any(
		" " + cleaned.to_lower() + " ",
		META_MARKERS
	):
		return []
	var fragments: PackedStringArray = cleaned.replace(";", ".").split(
		".",
		false
	)
	var candidates: Array[Dictionary] = []
	for fragment_text: String in fragments:
		if candidates.size() >= MAX_CANDIDATES:
			break
		var proposition: String = fragment_text.strip_edges()
		if proposition.length() < MIN_PROPOSITION_CHARS:
			continue
		var category_id: String = _category_for(proposition)
		if category_id.is_empty():
			continue
		var source_ref: String = (
			"facilitator-input:" + proposition.sha256_text().left(16)
		)
		candidates.append({
			"id": "participant_" + proposition.sha256_text().left(16),
			"category": category_id,
			"proposition": proposition.left(500),
			"source_class": "participant_said",
			"source_refs": [source_ref],
			"rationale": (
				"Structured deterministically from the facilitator's submitted "
				+ "statement; facilitator review is required."
			),
			"confidence": 1.0,
			"evidence_status": "unsupported",
		})
	return candidates


func _category_for(proposition: String) -> String:
	var lowered: String = " " + proposition.to_lower() + " "
	if _contains_any(lowered, OPPORTUNITY_MARKERS):
		return "opportunity"
	if _contains_any(lowered, CAUSE_MARKERS):
		return "cause"
	if _contains_any(lowered, EFFECT_MARKERS):
		return "effect"
	return ""


func _contains_any(text_value: String, markers: Array[String]) -> bool:
	for marker_text: String in markers:
		if text_value.contains(marker_text):
			return true
	return false
