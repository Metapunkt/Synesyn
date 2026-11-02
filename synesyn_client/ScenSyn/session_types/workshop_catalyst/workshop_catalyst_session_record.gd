extends RefCounted
class_name WorkshopCatalystSessionRecord

## WorkshopCatalystSessionRecord
## Posts "Session Record" entries into the story log at key workshop events.
## Structural events (session open, stage start/advance, time warnings, bucket updates)
## are wired from the controller. Proactive observations are fired by on_character_turn()
## after every character turn — templated for simple gap-flags, LLM for analytical reads.

const SENDER := "Session Record"
const ResumeHydrateScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_resume_hydrate.gd"
)

# Proactive observation state (resets on stage advance)
var _stage_turn_count: int = 0
var _proactive_turn_count: int = 0
var _last_observation_turn: int = -999
var _last_lm_observation_time: float = 0.0   # real-time guard: min 3 min between LLM observations
var _gap_flag_count: int = 0                 # how many gap flags have fired this stage
var _last_gap_flag_turn: int = -999          # _stage_turn_count when last gap flag fired
var _presynthesis_warned: bool = false
var _session_end_dq_warned: bool = false

const _PROACTIVE_MIN_TURN_GAP: int = 12        # min character turns between any proactive post
const _PROACTIVE_LM_MIN_REAL_SEC: float = 180.0 # min real seconds between LLM analytical posts
const _PROACTIVE_LM_EVERY_N_TURNS: int = 25    # LLM analytical every N stage turns
const _GAP_FLAG_FIRST_TURN: int = 6            # turns before first gap-flag fires
const _GAP_FLAG_REPEAT_INTERVAL: int = 8       # turns between repeated gap-flags (if still no decision)
const _CONVERGENCE_CHECK_FIRST_TURN: int = 4   # turns before first LLM convergence check
const _CONVERGENCE_CHECK_INTERVAL: int = 3     # turns between repeated LLM convergence checks
const _CONVERGENCE_CHECK_INTERVAL_AFTER_CAPTURE: int = 2  # tighter interval right after a decision was just captured

var _last_convergence_check_turn: int = -999
var _last_decisions_count_seen: int = 0  # used to detect "decision was just captured"
var _vote_call_in_flight: bool = false  # guard against concurrent vote-call triggers

# Cross-theme primitive: a tiny stateful object that tracks the post-capture
# "riff window" during which autonomous closure detectors are suppressed so
# vote-rationale and pivot turns don't immediately trigger another vote.
# Default duration (4 turns) lives in CaptureCooldown.DEFAULT_DURATION_TURNS.
var _cooldown: CaptureCooldown = CaptureCooldown.new()

# ── Core post ────────────────────────────────────────────────────────────────

func post(message: String) -> void:
	if typeof(StoryState) == TYPE_NIL or not StoryState:
		return
	if not StoryState.has_method("add_log_entry"):
		return
	StoryState.add_log_entry(SENDER, message)

# ── Status helper ─────────────────────────────────────────────────────────────

func build_decision_record_status(ws: Dictionary) -> String:
	var buckets_any: Variant = ws.get("buckets", {})
	var buckets: Dictionary = buckets_any if typeof(buckets_any) == TYPE_DICTIONARY else {}
	var d_any: Variant = buckets.get("decisions", [])
	var d_arr: Array = d_any if typeof(d_any) == TYPE_ARRAY else []
	var r_any: Variant = buckets.get("risks", [])
	var r_arr: Array = r_any if typeof(r_any) == TYPE_ARRAY else []
	var q_any: Variant = buckets.get("open_questions", [])
	var q_arr: Array = q_any if typeof(q_any) == TYPE_ARRAY else []
	return "Decision record: %d/3 decisions | %d/2 risks | %d/1 deferred question" % [
		d_arr.size(), r_arr.size(), q_arr.size()
	]

# ── Structural LLM entries (called from controller at fixed events) ────────────

func generate_lm_entry(conv: Variant, ws: Dictionary, scenario: Dictionary, trigger: String, recent_log: Array = []) -> void:
	if not conv:
		return
	var prompt: String = _build_lm_prompt(ws, scenario, trigger, recent_log)
	var res: Variant = await conv.chat(prompt, "session_record_synth")
	if not res or not res.success:
		return
	var message: String = String(res.response).strip_edges()
	if not message.is_empty():
		post(message)


# Mandatory per-turn synthesis is deliberately separate from proactive observer
# throttles. It runs once when the hidden-synthesis finalization seam invokes it;
# periodic observations retain their existing cadence and safeguards.
func synthesize_turn(
	conv: Variant,
	specialist_contributions: Array,
	ws: Dictionary,
	scenario: Dictionary,
	human_input: Dictionary
) -> Dictionary:
	var message_text: String = ""
	var status_id: String = "complete"
	var failure_reason: String = ""
	var model_id: String = _resolve_synthesizer_model(scenario)
	if conv:
		var prompt: String = _build_turn_synthesis_prompt(
			specialist_contributions,
			ws,
			scenario,
			human_input
		)
		var response: Variant = await conv.chat(
			prompt,
			"workshop_session_record_synth",
			model_id
		)
		if response and response.success:
			message_text = String(response.response).strip_edges()
		else:
			status_id = "degraded"
			failure_reason = "synthesis_request_failed"
	else:
		status_id = "degraded"
		failure_reason = "conversation_unavailable"
	if message_text.is_empty():
		status_id = "degraded"
		if failure_reason.is_empty():
			failure_reason = "empty_synthesis"
		message_text = _build_deterministic_turn_fallback(specialist_contributions)
	post(message_text)
	return {
		"message": message_text,
		"status": status_id,
		"failure_reason": failure_reason,
		"model_id": model_id if not model_id.is_empty() else "default",
		"created_at": Time.get_datetime_string_from_system(true),
	}


func _build_turn_synthesis_prompt(
	specialist_contributions: Array,
	ws: Dictionary,
	scenario: Dictionary,
	human_input: Dictionary
) -> String:
	var contribution_lines: Array[String] = []
	for contribution_any: Variant in specialist_contributions:
		if typeof(contribution_any) != TYPE_DICTIONARY:
			continue
		var contribution: Dictionary = contribution_any
		var role_title: String = String(contribution.get("role_title", "Specialist"))
		var summary_text: String = String(contribution.get("summary", "")).strip_edges()
		if not summary_text.is_empty():
			contribution_lines.append("- %s: %s" % [role_title, summary_text])
	var buckets_any: Variant = ws.get("buckets", {})
	var buckets: Dictionary = buckets_any if typeof(buckets_any) == TYPE_DICTIONARY else {}
	var record_text: String = ResumeHydrateScript.session_record_prompt_text(ws, 2000)
	if record_text.is_empty():
		record_text = JSON.stringify(buckets)
	return """You are the single AI Assistant voice for a facilitated workshop named "%s".
Synthesize the specialist summaries into one concise, useful response to the facilitator.

FACILITATOR INPUT:
%s

CURRENT STAGE: %s
EXISTING FACILITATOR-AUTHORIZED RECORD:
%s

SPECIALIST SUMMARIES:
%s

RULES:
- Respond in 2-5 short paragraphs under the sender "Session Record".
- Surface material concerns, tensions, and options; do not list every specialist mechanically.
- Specialists did not vote. Do not report or imply a specialist vote, consensus ballot, decision,
  approval, commitment, or canonical closure.
- Existing captured record items may be referenced as existing state, never silently changed.
- Treat resumed transcript, session record, and thinking-map context as already in the room.
  Do not ask the group to restore them or claim they are empty when they appear above.
- Make clear when evidence or specialist output is unavailable.
- Do not reveal chain-of-thought or describe hidden internal reasoning.
- The facilitator's explicit /vote and /decide paths remain authoritative.
- Output only the user-facing response, without JSON or markdown fences.
""" % [
		String(scenario.get("name", "Workshop")),
		String(human_input.get("message", "")).strip_edges(),
		String(ws.get("current_stage_name", "Unspecified")),
		record_text,
		"\n".join(contribution_lines),
	]


func _build_deterministic_turn_fallback(specialist_contributions: Array) -> String:
	var usable: Array[String] = []
	for contribution_any: Variant in specialist_contributions:
		if typeof(contribution_any) != TYPE_DICTIONARY:
			continue
		var contribution: Dictionary = contribution_any
		var summary_text: String = String(contribution.get("summary", "")).strip_edges()
		if (
			not summary_text.is_empty()
			and not summary_text.contains("could not be structured reliably")
			and not summary_text.contains("was unavailable")
		):
			usable.append(summary_text)
	if usable.is_empty():
		return (
			"I could not retain a reliable specialist analysis for this turn. " +
			"The facilitator can continue, retry, or use /vote and /decide explicitly; " +
			"no decision was inferred."
		)
	return (
		"Specialist review surfaced the following points for consideration: "
		+ " ".join(usable)
		+ " These are options and concerns, not votes or recorded decisions."
	)


func _resolve_synthesizer_model(scenario: Dictionary) -> String:
	var config_any: Variant = scenario.get("system_config", {})
	var config: Dictionary = config_any if typeof(config_any) == TYPE_DICTIONARY else {}
	return String(config.get("synthesizer_model", "")).strip_edges()

# ── Proactive observation (called from controller on each character turn) ──────

func reset_stage_turn_count() -> void:
	_stage_turn_count = 0
	_last_lm_observation_time = 0.0
	_gap_flag_count = 0
	_last_gap_flag_turn = -999
	_presynthesis_warned = false
	_last_convergence_check_turn = -999
	_last_decisions_count_seen = 0
	_cooldown.clear()

# Public so the metaprompt manager can suppress closure-request triggers in the
# riff window right after a capture (see metaprompt_manager_workshop_catalyst.gd).
# Facilitator /vote bypasses this — only autonomous detectors check it.
func is_in_capture_cooldown() -> bool:
	return _cooldown.is_active(_stage_turn_count)

func on_character_turn(ws: Dictionary, scenario: Dictionary, conv: Variant, recent_log: Array) -> void:
	_stage_turn_count += 1
	_proactive_turn_count += 1
	# Convergence detection runs independently of the proactive-post gap. It does not
	# itself produce a Session Record entry — it just calls a vote when the LLM judges
	# the room has agreed but is failing to close. The vote is what surfaces in the log.
	_maybe_run_convergence_check(ws, scenario, conv, recent_log)
	# Minimum turn gap between any proactive observations
	if _proactive_turn_count - _last_observation_turn < _PROACTIVE_MIN_TURN_GAP:
		return
	# Templated checks — priority order, fire at most one per call
	var next_gap_at: int = _GAP_FLAG_FIRST_TURN if _gap_flag_count == 0 else _last_gap_flag_turn + _GAP_FLAG_REPEAT_INTERVAL
	if _stage_turn_count >= next_gap_at and _try_post_gap_flag(ws):
		return
	if _try_post_presynthesis_warning(ws):
		return
	if _try_post_session_end_dq_warning(ws):
		return
	# LLM analytical: fires every N stage turns AND only if enough real time has passed.
	# The real-time guard prevents cascade when the AI generates multiple characters per batch.
	if _stage_turn_count >= _PROACTIVE_LM_EVERY_N_TURNS and _stage_turn_count % _PROACTIVE_LM_EVERY_N_TURNS == 0:
		var now: float = Time.get_unix_time_from_system()
		if now - _last_lm_observation_time < _PROACTIVE_LM_MIN_REAL_SEC:
			return
		var trigger_text := "proactive_observation at turn %d of stage \"%s\"" % [
			_stage_turn_count, String(ws.get("current_stage_name", "")).strip_edges()
		]
		_last_lm_observation_time = now
		_last_observation_turn = _proactive_turn_count
		generate_lm_entry(conv, ws, scenario, trigger_text, recent_log)

# ── Templated condition checks ────────────────────────────────────────────────

func _try_post_gap_flag(ws: Dictionary) -> bool:
	var buckets_any: Variant = ws.get("buckets", {})
	var buckets: Dictionary = buckets_any if typeof(buckets_any) == TYPE_DICTIONARY else {}
	var d_any: Variant = buckets.get("decisions", [])
	var d_arr: Array = d_any if typeof(d_any) == TYPE_ARRAY else []
	# Stop firing once the group has at least one decision captured
	if not d_arr.is_empty():
		return false

	# Session Record public post
	post("[%d turns] No decisions captured yet. %s. The facilitator can type /vote to call a vote, or /decide [text] to record one directly." % [
		_stage_turn_count, build_decision_record_status(ws)
	])

	# Closure formation: call a vote based on the recent conversation. Suppressed
	# during the capture cooldown so vote-rationale/pivot turns don't re-trigger.
	if not is_in_capture_cooldown():
		call_vote_from_recent_log("turn_gap_%d" % _stage_turn_count)

	_gap_flag_count += 1
	_last_gap_flag_turn = _stage_turn_count
	_last_observation_turn = _proactive_turn_count
	return true

# ── Closure Formation Controller (vote-based) ──────────────────────────────────
# Three triggers can call a vote:
#   1. Turn-gap (deterministic, fired by _try_post_gap_flag above)
#   2. LLM convergence detection (run periodically; flags "skirting closure")
#   3. Facilitator on-demand (/vote command or button — wired in controller)

# Public entry point: called by the controller (or internally) to start a vote.
# Builds a proposal via a focused system LLM call, then registers it as pending_vote.
func call_vote_from_recent_log(trigger: String) -> void:
	# Concurrency guard: when several closure-request lines arrive in the same
	# AI batch, multiple vote-calls can be queued before any of them sets the
	# pending_vote flag (LLM round-trip happens between the check and the set).
	if _vote_call_in_flight:
		return
	var conv: Variant = Global.get_conversation_manager() if Global else null
	if not conv:
		post("Vote requested (%s) but the LLM service is unavailable." % trigger)
		return
	var state: Dictionary = StoryState.get_state()
	var ws_any: Variant = state.get("workshop_catalyst", {})
	var ws: Dictionary = ws_any if typeof(ws_any) == TYPE_DICTIONARY else {}
	# If a vote is already pending, do not stack a new one.
	var existing_pending_any: Variant = ws.get("pending_vote", {})
	if typeof(existing_pending_any) == TYPE_DICTIONARY and not String((existing_pending_any as Dictionary).get("text", "")).strip_edges().is_empty():
		# Stay quiet here — closure-request triggers can fire repeatedly while a vote
		# is already on the table; surfacing a "vote already on table" line every time
		# would clutter the log. Facilitator-driven /vote keeps its surface message
		# (handled by call site).
		if trigger == "facilitator_vote_command":
			post("A vote is already on the table — waiting for participants to respond before calling another.")
		return
	_vote_call_in_flight = true
	var scenario: Dictionary = Global.get_current_scenario() if Global else {}
	var log_any: Variant = state.get("story_log", [])
	var log: Array = log_any if typeof(log_any) == TYPE_ARRAY else []
	var window_size: int = mini(log.size(), 12)
	var window: Array = log.slice(log.size() - window_size, log.size()) if log.size() > 0 else []
	var prompt := _build_vote_proposal_prompt(ws, scenario, window, trigger)
	# Use the default thread (named threads have caused intermittent failures).
	var res: Variant = await conv.chat(prompt)
	if not res or not res.success:
		post("Vote requested (%s), but proposal synthesis failed. The facilitator can type /decide [text] to record one directly." % trigger)
		_vote_call_in_flight = false
		return
	var raw: String = String(res.response).strip_edges()
	# Strip markdown code fences if the LLM wrapped the response.
	if raw.begins_with("```"):
		var first_nl: int = raw.find("\n")
		if first_nl >= 0:
			raw = raw.substr(first_nl + 1)
		var last_fence: int = raw.rfind("```")
		if last_fence >= 0:
			raw = raw.substr(0, last_fence)
		raw = raw.strip_edges()
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		post("Vote requested (%s), but proposal synthesis returned an unparseable response. The facilitator can type /decide [text] to record one directly." % trigger)
		_vote_call_in_flight = false
		return
	var proposal_dict: Dictionary = parsed
	if String(proposal_dict.get("status", "")).strip_edges().to_lower() == "no_proposal":
		post("Vote requested (%s), but no clear convergence point was found in the recent discussion. Continue, then try again." % trigger)
		_vote_call_in_flight = false
		return
	var proposal_text: String = String(proposal_dict.get("statement", "")).strip_edges()
	var proposal_kind: String = String(proposal_dict.get("kind", "decision")).strip_edges().to_lower()
	if proposal_text.is_empty():
		post("Vote requested (%s) — proposal synthesis returned no statement." % trigger)
		_vote_call_in_flight = false
		return
	if proposal_kind != "decision" and proposal_kind != "risk" and proposal_kind != "open_question":
		proposal_kind = "decision"
	var owner_text: String = String(proposal_dict.get("owner", "")).strip_edges()
	var confidence_text: String = String(proposal_dict.get("confidence", "Medium")).strip_edges()
	# Register pending vote. trigger is stored so that when the proposal is
	# captured/discarded later, the closure event payload can carry the trigger
	# all the way through to substrate consumers (useful for analyzing which
	# trigger paths produce captures vs discards).
	var pending: Dictionary = {
		"text": proposal_text,
		"kind": proposal_kind,
		"owner": owner_text,
		"confidence": confidence_text,
		"votes_yes": [],
		"votes_no": [],
		"opened_at_log_index": log.size(),
		"trigger": trigger
	}
	ws["pending_vote"] = pending
	var new_state: Dictionary = state.duplicate(true)
	new_state["workshop_catalyst"] = ws
	StoryState.set_state(new_state)
	# Surface the proposal as a Session Record entry.
	var kind_label: String = "Decision" if proposal_kind == "decision" else ("Risk" if proposal_kind == "risk" else "Deferred question")
	var details: String = ""
	if not owner_text.is_empty():
		details += " Owner: %s." % owner_text
	if not confidence_text.is_empty() and proposal_kind == "decision":
		details += " Confidence: %s." % confidence_text
	post("PROPOSAL — %s: \"%s\".%s\nVote Yes or No (open your next turn with that word). Tally completes when participants have spoken." % [
		kind_label, proposal_text, details
	])
	_vote_call_in_flight = false

func _build_vote_proposal_prompt(ws: Dictionary, scenario: Dictionary, recent_log: Array, trigger: String) -> String:
	var scenario_name: String = String(scenario.get("name", "Workshop")).strip_edges()
	var stage_name: String = String(ws.get("current_stage_name", "")).strip_edges()
	var packet_text: String = String(scenario.get("workshop_packet_text", "")).strip_edges()
	var prompt := "You are the Session Record (meeting secretary) for a workshop titled \"%s\".\n" % scenario_name
	prompt += "TRIGGER: %s\n\n" % trigger
	prompt += "Your job: synthesize the most salient point of agreement (or risk, or unresolved question) "
	prompt += "from the recent transcript into ONE structured proposal that can be voted on with a simple Yes/No.\n\n"
	if not stage_name.is_empty():
		prompt += "CURRENT STAGE: %s\n" % stage_name
	if not packet_text.is_empty():
		prompt += "WORKSHOP PACKET (for grounding):\n%s\n\n" % packet_text.left(1500)
	prompt += "RECENT TRANSCRIPT (most recent last):\n"
	for entry_any in recent_log:
		if typeof(entry_any) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_any
		var sender: String = String(entry.get("sender", "")).strip_edges()
		var msg: String = String(entry.get("message", "")).strip_edges()
		if not sender.is_empty() and not msg.is_empty():
			prompt += "- %s: %s\n" % [sender, msg.left(300)]
	prompt += "\nDECIDE which proposal kind fits best:\n"
	prompt += "- \"decision\": a substantive conclusion the group has reached or is on the brink of reaching.\n"
	prompt += "- \"risk\":     a named harm or failure mode the group has flagged with a clear cost-bearer.\n"
	prompt += "- \"open_question\": a question the group has explicitly chosen to defer with an owner.\n\n"
	prompt += "OUTPUT a single JSON object (no markdown, no commentary), matching this schema EXACTLY:\n"
	prompt += "{\n"
	prompt += "  \"status\": \"propose\" | \"no_proposal\",\n"
	prompt += "  \"kind\":   \"decision\" | \"risk\" | \"open_question\",\n"
	prompt += "  \"statement\": \"the proposal in one clear sentence (max ~40 words). Do NOT include a trailing period.\",\n"
	prompt += "  \"owner\":     \"the institution or delivery function most responsible. For DECISIONS this is REQUIRED — if no owner is implied by the transcript, use 'Workshop chair' as the default. For risks and deferred questions an empty string is acceptable when truly unclear.\",\n"
	prompt += "  \"confidence\": \"High\" | \"Medium\" | \"Low\"  (only meaningful for decisions; default Medium)\n"
	prompt += "}\n"
	prompt += "If no clear convergence point exists yet, return: { \"status\": \"no_proposal\" }\n"
	prompt += "Be conservative: only propose what the transcript actually supports. Do not invent.\n"
	return prompt

# ── Vote tally (called by metaprompt manager when a vote is detected) ──────────
# The manager hands us a (voter, "yes"|"no") tuple. We tally and, if a majority is
# reached or all participants have voted, capture (or discard) the proposal.
# The actual tally rules (idempotent recording, threshold, plurality tie-break)
# live in VoteTally so other themes adopting vote-based closure use the same logic.
func record_vote(voter: String, choice: String) -> void:
	if typeof(StoryState) == TYPE_NIL or not StoryState:
		return
	var state: Dictionary = StoryState.get_state()
	var ws_any: Variant = state.get("workshop_catalyst", {})
	var ws: Dictionary = ws_any if typeof(ws_any) == TYPE_DICTIONARY else {}
	var pending_any: Variant = ws.get("pending_vote", {})
	if typeof(pending_any) != TYPE_DICTIONARY:
		return
	var pending: Dictionary = pending_any
	var proposal_text: String = String(pending.get("text", "")).strip_edges()
	if proposal_text.is_empty():
		return
	var votes_yes_any: Variant = pending.get("votes_yes", [])
	var votes_no_any: Variant = pending.get("votes_no", [])
	var votes_yes: Array = votes_yes_any if typeof(votes_yes_any) == TYPE_ARRAY else []
	var votes_no: Array = votes_no_any if typeof(votes_no_any) == TYPE_ARRAY else []
	# Apply the vote (idempotent; supports vote-change). VoteTally returns false
	# if nothing actually changed (stale duplicate); skip the state write in that case.
	if not VoteTally.record(votes_yes, votes_no, voter, choice):
		return
	pending["votes_yes"] = votes_yes
	pending["votes_no"] = votes_no
	ws["pending_vote"] = pending
	# Resolve against the current tally; capture, discard, or leave pending.
	var cast_size: int = _get_cast_size_from_manager()
	var resolution: Dictionary = VoteTally.resolve(votes_yes, votes_no, cast_size)
	var outcome: String = String(resolution.get("outcome", VoteTally.OUTCOME_PENDING))
	var reason: String = String(resolution.get("reason", ""))
	if outcome == VoteTally.OUTCOME_YES:
		_capture_proposal_and_clear(ws, pending, votes_yes, reason)
	elif outcome == VoteTally.OUTCOME_NO:
		_discard_proposal_and_clear(ws, pending, votes_no)
	else:
		ws["pending_vote"] = pending
	var new_state: Dictionary = state.duplicate(true)
	new_state["workshop_catalyst"] = ws
	StoryState.set_state(new_state)

func _get_cast_size_from_manager() -> int:
	var mgr = Global.get_metaprompt_manager() if Global else null
	if mgr and "_cast" in mgr:
		var cast_any: Variant = mgr.get("_cast")
		if typeof(cast_any) == TYPE_ARRAY:
			return (cast_any as Array).size()
	return 0

func _capture_proposal_and_clear(ws: Dictionary, pending: Dictionary, voters_yes: Array, reason: String) -> void:
	var kind: String = String(pending.get("kind", "decision")).strip_edges().to_lower()
	var bucket_key: String = "decisions" if kind == "decision" else ("risks" if kind == "risk" else "open_questions")
	# Strip a trailing period from the LLM-supplied statement so the appended Owner /
	# Confidence segments don't produce ".. Owner: ..." in the captured record.
	var statement: String = String(pending.get("text", "")).strip_edges().rstrip(".").strip_edges()
	var owner_text: String = String(pending.get("owner", "")).strip_edges()
	# Lenient fallback: every captured decision must carry an owner. If the proposal
	# synthesizer returned an empty owner (which can happen for definition-shaped
	# decisions), default to "Workshop chair" so the record never has an ownerless
	# decision. Risks and deferred questions retain their existing optional-owner shape.
	if kind == "decision" and owner_text.is_empty():
		owner_text = "Workshop chair"
	var confidence_text: String = String(pending.get("confidence", "")).strip_edges()
	var formatted: String = statement
	if not owner_text.is_empty():
		formatted += ". Owner: " + owner_text
	if kind == "decision" and not confidence_text.is_empty():
		formatted += ". Confidence: " + confidence_text
	if not formatted.ends_with("."):
		formatted += "."
	var buckets_any: Variant = ws.get("buckets", {})
	var buckets: Dictionary = buckets_any if typeof(buckets_any) == TYPE_DICTIONARY else {}
	var items_any: Variant = buckets.get(bucket_key, [])
	var items: Array = items_any if typeof(items_any) == TYPE_ARRAY else []
	var already_exists := false
	for existing_any in items:
		if String(existing_any).strip_edges().to_lower() == formatted.to_lower():
			already_exists = true
			break
	if not already_exists:
		items.append(formatted)
	buckets[bucket_key] = items
	ws["buckets"] = buckets
	ws.erase("pending_vote")
	# Capture cooldown: gives the room a riff window where vote rationale and pivot
	# commentary can land without triggering another vote on the rationale itself.
	_cooldown.start(_stage_turn_count)
	var label: String = "Decision" if kind == "decision" else ("Risk" if kind == "risk" else "Deferred question")
	# Build a directive next-step summary so the AI characters get an explicit pivot
	# signal, not just an announcement. The remaining-targets line is the most
	# important part — it tells the room what to focus on next.
	var pivot_line: String = _build_pivot_summary(buckets)
	post("%s captured (%s): %s — endorsed by: %s.\n%s" % [label, reason, formatted, ", ".join(voters_yes), pivot_line])
	# Cross-cutting: emit to the closure bus so substrate (and any future
	# analytics) consumers can persist this capture as a ui.workshop_closure artifact.
	# Substrate writes are fire-and-forget and silently no-op when the Hub is down.
	_emit_closure_event(true, kind, statement, owner_text, confidence_text, voters_yes, [], reason, ws, pending)

func _discard_proposal_and_clear(ws: Dictionary, pending: Dictionary, voters_no: Array) -> void:
	var statement: String = String(pending.get("text", "")).strip_edges()
	var kind: String = String(pending.get("kind", "decision")).strip_edges().to_lower()
	var owner_text: String = String(pending.get("owner", "")).strip_edges()
	var confidence_text: String = String(pending.get("confidence", "")).strip_edges()
	ws.erase("pending_vote")
	# Same cooldown for discards: prevents immediate re-attempt on the same material.
	_cooldown.start(_stage_turn_count)
	post("Proposal not adopted: \"%s\" — opposed by: %s. Discussion continues; do not re-propose the same statement without addressing the objection first." % [statement, ", ".join(voters_no)])
	# Mirror of the capture-side bus emit — discards are also signalled so any
	# consumer interested in proposal lifecycle (not just successful captures)
	# sees a complete picture. Substrate emitter ignores discards by default.
	_emit_closure_event(false, kind, statement, owner_text, confidence_text, [], voters_no, "No", ws, pending)

# Cross-cutting closure event. Builds the payload defined by ClosureBus and
# forwards it to either emit_captured (if captured == true) or emit_discarded.
# Failure to reach the bus is silent — closure persistence to the substrate is
# best-effort and must never affect live workshop UX.
func _emit_closure_event(
	captured: bool,
	kind: String,
	statement: String,
	owner_text: String,
	confidence_text: String,
	voters_yes: Array,
	voters_no: Array,
	reason: String,
	ws: Dictionary,
	pending: Dictionary
) -> void:
	if typeof(Global) == TYPE_NIL or not Global:
		return
	if not Global.has_method("get_closure_bus"):
		return
	var bus: Variant = Global.get_closure_bus()
	if bus == null:
		return
	var scenario: Dictionary = Global.get_current_scenario() if Global.has_method("get_current_scenario") else {}
	var state: Dictionary = StoryState.get_state() if (typeof(StoryState) != TYPE_NIL and StoryState) else {}
	var log_any: Variant = state.get("story_log", [])
	var log: Array = log_any if typeof(log_any) == TYPE_ARRAY else []
	var payload: Dictionary = {
		"session_type_id": "workshop_catalyst",
		"scenario_id": String(scenario.get("_scenario_name", "")).strip_edges(),
		"scenario_name": String(scenario.get("name", "")).strip_edges(),
		"kind": kind,
		"statement": statement,
		"owner": owner_text,
		"confidence": confidence_text,
		"voters_yes": voters_yes,
		"voters_no": voters_no,
		"outcome": "yes" if captured else "no",
		"reason": reason,
		"trigger": String(pending.get("trigger", "")),
		"stage_name": String(ws.get("current_stage_name", "")).strip_edges(),
		"stage_turn": _stage_turn_count,
		"session_turn": -1,
		"source_log_index_open": int(pending.get("opened_at_log_index", -1)),
		"source_log_index_close": log.size(),
	}
	if captured and bus.has_method("emit_captured"):
		bus.emit_captured(payload)
	elif not captured and bus.has_method("emit_discarded"):
		bus.emit_discarded(payload)

# Builds a compact "what to do next" line shown after every capture.
# Names the remaining targets to give the AI characters a clear pivot.
func _build_pivot_summary(buckets: Dictionary) -> String:
	var d_arr: Array = (buckets.get("decisions", []) as Array) if typeof(buckets.get("decisions", [])) == TYPE_ARRAY else []
	var r_arr: Array = (buckets.get("risks", []) as Array) if typeof(buckets.get("risks", [])) == TYPE_ARRAY else []
	var q_arr: Array = (buckets.get("open_questions", []) as Array) if typeof(buckets.get("open_questions", [])) == TYPE_ARRAY else []
	var remaining: Array[String] = []
	if d_arr.size() < 3:
		remaining.append("%d more decision(s)" % (3 - d_arr.size()))
	if r_arr.size() < 2:
		remaining.append("%d more risk(s) with cost-bearer" % (2 - r_arr.size()))
	if q_arr.size() < 1:
		remaining.append("the deferred question with owner")
	if remaining.is_empty():
		return "Decision record complete (%d/3 decisions, %d/2 risks, %d/1 deferred question). Brief reflection is fine; otherwise the group can advance to the next stage." % [d_arr.size(), r_arr.size(), q_arr.size()]
	# Directive pivot — speak in the meeting-secretary voice the AI characters will read.
	return ("Next outstanding outputs: %s. Brief follow-up reflection on the just-captured item is fine, " % ", ".join(remaining)) + \
		"but the group should now pivot to one of the remaining outputs rather than continue refining what has just been recorded."

func _try_post_presynthesis_warning(ws: Dictionary) -> bool:
	if _presynthesis_warned:
		return false
	var agenda_any: Variant = ws.get("agenda", [])
	var agenda: Array = agenda_any if typeof(agenda_any) == TYPE_ARRAY else []
	var day_idx: int = int(ws.get("day_index", 0))
	if day_idx < 0 or day_idx >= agenda.size():
		return false
	var day_entry_any: Variant = agenda[day_idx]
	if typeof(day_entry_any) != TYPE_DICTIONARY:
		return false
	var day_entry: Dictionary = day_entry_any
	var stages_any: Variant = day_entry.get("stages", [])
	var stages: Array = stages_any if typeof(stages_any) == TYPE_ARRAY else []
	var next_idx: int = int(ws.get("stage_index", 0)) + 1
	if next_idx >= stages.size():
		return false
	var next_stage_any: Variant = stages[next_idx]
	if typeof(next_stage_any) != TYPE_DICTIONARY:
		return false
	var next_stage_name: String = String(next_stage_any.get("name", "")).strip_edges().to_lower()
	if not next_stage_name.contains("synthesis"):
		return false
	var buckets_any: Variant = ws.get("buckets", {})
	var buckets: Dictionary = buckets_any if typeof(buckets_any) == TYPE_DICTIONARY else {}
	var d_any: Variant = buckets.get("decisions", [])
	var d_arr: Array = d_any if typeof(d_any) == TYPE_ARRAY else []
	if d_arr.size() >= 2:
		return false
	post("Synthesis is next. Only %d of 3 decisions captured so far. At least one more decision is needed in this stage before the final record can be completed." % d_arr.size())
	_presynthesis_warned = true
	_last_observation_turn = _proactive_turn_count
	return true

# ── LLM convergence detector ─────────────────────────────────────────────────
# Periodically asks a small system LLM call: "Has the room converged but failed
# to close?". If yes, immediately calls a vote on the convergence point. This is
# the autonomous closure trigger the user asked for — the LLM can recognize when
# characters are skirting closure and act on it without facilitator intervention.
func _maybe_run_convergence_check(ws: Dictionary, scenario: Dictionary, conv: Variant, recent_log: Array) -> void:
	if not conv:
		return
	# Don't run if a vote is already pending — let it resolve first.
	var pending_any: Variant = ws.get("pending_vote", {})
	if typeof(pending_any) == TYPE_DICTIONARY and not String((pending_any as Dictionary).get("text", "")).strip_edges().is_empty():
		return
	# Don't stack a check while a previous vote-call is still mid-flight.
	if _vote_call_in_flight:
		return
	# Capture cooldown: suppress autonomous re-triggering for a few turns after any
	# capture so vote-rationale and pivot commentary don't get read as new convergence.
	if is_in_capture_cooldown():
		return
	# First check needs the conversation to have warmed up
	if _stage_turn_count < _CONVERGENCE_CHECK_FIRST_TURN:
		return
	# Detect "decision was just captured" — when the decisions count has grown since
	# our last observation, the room is warmed up and a follow-on decision is often
	# very close. Use the tighter interval in that window.
	var buckets_any: Variant = ws.get("buckets", {})
	var buckets: Dictionary = buckets_any if typeof(buckets_any) == TYPE_DICTIONARY else {}
	var d_any: Variant = buckets.get("decisions", [])
	var current_decisions_count: int = (d_any as Array).size() if typeof(d_any) == TYPE_ARRAY else 0
	var just_captured: bool = current_decisions_count > _last_decisions_count_seen
	_last_decisions_count_seen = current_decisions_count
	var interval: int = _CONVERGENCE_CHECK_INTERVAL_AFTER_CAPTURE if (just_captured or current_decisions_count > 0) else _CONVERGENCE_CHECK_INTERVAL
	if _stage_turn_count - _last_convergence_check_turn < interval:
		return
	_last_convergence_check_turn = _stage_turn_count
	# Run the check (fire-and-forget; await chains are fine inside the controller's
	# deferred-call timing).
	var verdict: bool = await _llm_detect_convergence_skirt(conv, scenario, recent_log, ws)
	if verdict:
		await call_vote_from_recent_log("llm_convergence_detected_at_turn_%d" % _stage_turn_count)

func _llm_detect_convergence_skirt(conv: Variant, scenario: Dictionary, recent_log: Array, ws: Dictionary) -> bool:
	if recent_log.size() < 3:
		return false
	var scenario_name: String = String(scenario.get("name", "Workshop")).strip_edges()
	var stage_name: String = String(ws.get("current_stage_name", "")).strip_edges()
	var prompt := "You are a meeting analyst watching a structured workshop in real time. Your only "
	prompt += "job is to decide whether the room has reached a point that can be voted on, even if "
	prompt += "the participants have not formally requested closure.\n\n"
	prompt += "WORKSHOP: \"%s\" (current stage: \"%s\")\n\n" % [scenario_name, stage_name]
	prompt += "RECENT TRANSCRIPT (most recent last):\n"
	for entry_any in recent_log:
		if typeof(entry_any) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_any
		var sender: String = String(entry.get("sender", "")).strip_edges()
		var msg: String = String(entry.get("message", "")).strip_edges()
		if not sender.is_empty() and not msg.is_empty():
			prompt += "- %s: %s\n" % [sender, msg.left(280)]
	prompt += "\nDECISION RULE — answer YES if ANY of the following are true:\n"
	prompt += "1. A participant has explicitly asked the group to close, adopt, ratify, or record a NEW position "
	prompt += "that has not yet been captured (\"can we adopt that\", \"let's record this\", \"ask the room for assent\", "
	prompt += "\"can we take that as decision N\", etc.).\n"
	prompt += "2. Two or more participants have endorsed a single substantive NEW formulation in the last few turns "
	prompt += "without any participant raising a blocking objection.\n"
	prompt += "3. Participants are progressively REFINING a NEW position that has not yet been captured "
	prompt += "(each speaker tightens or extends the previous formulation toward one statement).\n\n"
	prompt += "Answer NO if ANY of the following are true:\n"
	prompt += "- The recent turns consist primarily of vote responses (\"Yes\", \"No\", or \"Yes — and...\") to a proposal "
	prompt += "that has just been captured. Substantive rationale ATTACHED TO A VOTE is not a new convergence point — "
	prompt += "it is post-decision elaboration.\n"
	prompt += "- A decision was captured very recently (you can see it in the transcript as a \"Decision captured\" "
	prompt += "Session Record entry) and the discussion has not yet pivoted to a new substantive question.\n"
	prompt += "- Participants are still surfacing fundamentally different positions or raising blocking objections.\n\n"
	prompt += "Reply with EXACTLY one token: YES or NO. No other text.\n"
	var res: Variant = await conv.chat(prompt)
	if not res or not res.success:
		return false
	var reply: String = String(res.response).strip_edges().to_upper()
	return reply.begins_with("YES")

func _try_post_session_end_dq_warning(ws: Dictionary) -> bool:
	if _session_end_dq_warned:
		return false
	var session_started_unix: float = float(ws.get("session_started_at_unix", 0.0))
	if session_started_unix <= 0.0:
		return false
	var session_duration_sec: float = float(int(ws.get("session_duration_minutes", 120))) * 60.0
	var elapsed_sec: float = Time.get_unix_time_from_system() - session_started_unix
	var remaining_min: int = int((session_duration_sec - elapsed_sec) / 60.0)
	if remaining_min > 15:
		return false
	var buckets_any: Variant = ws.get("buckets", {})
	var buckets: Dictionary = buckets_any if typeof(buckets_any) == TYPE_DICTIONARY else {}
	var q_any: Variant = buckets.get("open_questions", [])
	var q_arr: Array = q_any if typeof(q_any) == TYPE_ARRAY else []
	if not q_arr.is_empty():
		return false
	post("Approximately %d minutes remain. No deferred question has been named yet. Identify an unresolvable question and assign it an owner before the session closes." % remaining_min)
	_session_end_dq_warned = true
	_last_observation_turn = _proactive_turn_count
	return true

# ── LLM prompt builder ────────────────────────────────────────────────────────

func _build_lm_prompt(ws: Dictionary, scenario: Dictionary, trigger: String, recent_log: Array = []) -> String:
	var scenario_name: String = String(scenario.get("name", "Workshop")).strip_edges()
	var buckets_any: Variant = ws.get("buckets", {})
	var buckets: Dictionary = buckets_any if typeof(buckets_any) == TYPE_DICTIONARY else {}
	var d_any: Variant = buckets.get("decisions", [])
	var d_arr: Array = d_any if typeof(d_any) == TYPE_ARRAY else []
	var r_any: Variant = buckets.get("risks", [])
	var r_arr: Array = r_any if typeof(r_any) == TYPE_ARRAY else []
	var q_any: Variant = buckets.get("open_questions", [])
	var q_arr: Array = q_any if typeof(q_any) == TYPE_ARRAY else []
	var session_started_unix: float = float(ws.get("session_started_at_unix", 0.0))
	var session_duration_minutes: int = int(ws.get("session_duration_minutes", 120))
	var session_remaining_min: int = session_duration_minutes
	if session_started_unix > 0.0:
		var elapsed_sec: float = Time.get_unix_time_from_system() - session_started_unix
		session_remaining_min = int((float(session_duration_minutes * 60) - elapsed_sec) / 60.0)
	var current_stage: String = String(ws.get("current_stage_name", "")).strip_edges()
	var prompt := "You are the Session Record for a workshop titled \"%s\".\n\n" % scenario_name
	prompt += "Write a brief (2-4 sentences) session update in a neutral, meeting-minutes voice.\n"
	prompt += "Focus: progress toward the decision record, what is still needed, what the group should do next.\n"
	prompt += "Do not editorialize. Report state and flag gaps. Be concise.\n"
	prompt += "IMPORTANT: If decisions are shown as captured (count > 0), treat them as closed and final. "
	prompt += "Do NOT instruct the group to re-confirm, ratify, or re-debate them in the next stage. "
	prompt += "If the count is 0 but the trigger is a stage advance, note the gap and what the next stage should produce — do not suggest the prior stage's decisions need to be re-opened.\n\n"
	prompt += "TRIGGER: %s\n\n" % trigger
	prompt += "DECISION RECORD STATUS:\n"
	prompt += "- Decisions captured: %d of 3\n" % d_arr.size()
	for item_any: Variant in d_arr:
		prompt += "  * %s\n" % String(item_any).strip_edges()
	prompt += "- Risks named: %d of 2\n" % r_arr.size()
	for item_any: Variant in r_arr:
		prompt += "  * %s\n" % String(item_any).strip_edges()
	prompt += "- Deferred questions: %d of 1\n" % q_arr.size()
	for item_any: Variant in q_arr:
		prompt += "  * %s\n" % String(item_any).strip_edges()
	prompt += "\nCURRENT STAGE: %s\n" % current_stage
	prompt += "SESSION TIME REMAINING: approximately %d minutes\n" % session_remaining_min
	if not recent_log.is_empty():
		prompt += "\nRECENT TURNS (last %d):\n" % recent_log.size()
		for entry_any: Variant in recent_log:
			if typeof(entry_any) != TYPE_DICTIONARY:
				continue
			var entry: Dictionary = entry_any
			var sender: String = String(entry.get("sender", "")).strip_edges()
			var msg: String = String(entry.get("message", "")).strip_edges()
			if not sender.is_empty() and not msg.is_empty():
				prompt += "- %s: %s\n" % [sender, msg.left(200)]
	return prompt
