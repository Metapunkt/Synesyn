extends RefCounted
class_name WorkshopSessionRecordProposalEngine

const EXTRACTED_CATEGORIES: Array[String] = [
	"decisions",
	"risks",
	"open_questions",
	"owners",
	"next_steps",
]


func request_proposals(
	conversation: Variant,
	scenario: Dictionary,
	stage_title: String,
	recent_log: Array,
	store: RefCounted
) -> Dictionary:
	if not conversation:
		return {"ok": false, "error": "conversation_unavailable", "proposals": []}
	var prompt: String = _build_prompt(scenario, stage_title, recent_log, store.get_reviewed())
	var response: Variant = await conversation.chat(prompt, "workshop_catalyst_bucket_synth")
	if not response or not response.success:
		response = await conversation.chat(prompt)
	if not response or not response.success:
		return {"ok": false, "error": "proposal_request_failed", "proposals": []}
	var raw_json: String = _strip_fences(String(response.response))
	var parsed: Variant = JSON.parse_string(raw_json)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "error": "proposal_response_invalid", "proposals": []}
	var buckets_any: Variant = parsed.get("buckets", {})
	if typeof(buckets_any) != TYPE_DICTIONARY:
		return {"ok": false, "error": "proposal_buckets_missing", "proposals": []}
	var provenance: Dictionary = {
		"authorship_kind": "ai_inference",
		"origin_ref": "workshop_bucket_extraction",
		"model_id": String(response.get("model", "")) if typeof(response) == TYPE_DICTIONARY else "",
		"created_at": Time.get_datetime_string_from_system(true),
	}
	var created: Array[Dictionary] = propose_bucket_diff(store, buckets_any, provenance)
	return {"ok": true, "proposals": created}


func propose_bucket_diff(
	store: RefCounted,
	candidate_buckets: Dictionary,
	provenance: Dictionary = {}
) -> Array[Dictionary]:
	var created: Array[Dictionary] = []
	for category_id: String in EXTRACTED_CATEGORIES:
		var candidates_any: Variant = candidate_buckets.get(category_id, [])
		if typeof(candidates_any) != TYPE_ARRAY:
			continue
		for candidate_any: Variant in candidates_any:
			var candidate_text: String = ""
			if typeof(candidate_any) == TYPE_DICTIONARY:
				candidate_text = String(candidate_any.get("text", "")).strip_edges()
			else:
				candidate_text = String(candidate_any).strip_edges()
			var proposal: Dictionary = store.propose(category_id, candidate_text, provenance)
			if not proposal.is_empty():
				created.append(proposal)
	return created


func _build_prompt(
	scenario: Dictionary,
	stage_title: String,
	recent_log: Array,
	reviewed: Dictionary
) -> String:
	var prompt: String = "You maintain proposal-only structured workshop notes.\n"
	prompt += "Extract NEW candidate items from the transcript as a semantic diff against the reviewed state.\n"
	prompt += "Never treat your output as accepted, reviewed, committed, or canonical.\n\n"
	var packet_text: String = String(scenario.get("workshop_packet_text", "")).strip_edges()
	if not packet_text.is_empty():
		prompt += "WORKSHOP PACKET:\n%s\n\n" % packet_text.left(5000)
	if not stage_title.is_empty():
		prompt += "CURRENT STAGE: %s\n\n" % stage_title
	prompt += "LAST FACILITATOR-REVIEWED STATE:\n%s\n\n" % JSON.stringify(reviewed)
	prompt += "RECENT TRANSCRIPT:\n"
	for entry_any: Variant in recent_log:
		if typeof(entry_any) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_any
		var sender_id: String = String(entry.get("sender", "")).strip_edges()
		var message_text: String = String(entry.get("message", "")).strip_edges()
		if not sender_id.is_empty() and not message_text.is_empty():
			prompt += "- %s: %s\n" % [sender_id, message_text]
	prompt += "\nRULES:\n"
	prompt += "- Return only genuinely new suggestions. Do not repeat or rewrite reviewed items.\n"
	prompt += "- Facilitator-authored wording is authoritative; do not propose replacing it.\n"
	prompt += "- Decisions need a clear statement. Risks name a harm. Open questions are unresolved.\n"
	prompt += "- Owners identify accountable roles. Next steps are concrete actions.\n"
	prompt += "- Exclude Session Record progress narration, targets, timing, and process instructions.\n"
	prompt += "- Every array item must be a plain string.\n\n"
	prompt += "OUTPUT JSON ONLY:\n"
	prompt += (
		"{\"buckets\":{\"decisions\":[],\"risks\":[],\"open_questions\":[]," +
		"\"owners\":[],\"next_steps\":[]}}"
	)
	return prompt


func _strip_fences(raw_text: String) -> String:
	var clean_text: String = raw_text.strip_edges()
	if not clean_text.begins_with("```"):
		return clean_text
	var first_newline: int = clean_text.find("\n")
	if first_newline >= 0:
		clean_text = clean_text.substr(first_newline + 1)
	var last_fence: int = clean_text.rfind("```")
	if last_fence >= 0:
		clean_text = clean_text.substr(0, last_fence)
	return clean_text.strip_edges()
