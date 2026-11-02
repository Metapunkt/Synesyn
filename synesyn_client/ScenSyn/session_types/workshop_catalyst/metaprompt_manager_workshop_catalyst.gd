extends BaseMetapromptManager
class_name WorkshopCatalystMetapromptManager

## WorkshopCatalystMetapromptManager
## Theme: workshop_catalyst
##
## This theme is facilitation-first (workshops / roleplay sessions), not narrative-first.
## It intentionally supports structured outputs (buckets, decisions, next steps) and
## agenda/timeboxing context provided by WorkshopCatalystController + StoryState.

const FacilitatorSessionSetupScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/facilitator_session_setup.gd"
)

func _ready():
	super._ready()
	game_theme = "Workshop Catalyst (Facilitation)"

func get_system_cue_tag() -> String:
	# In this theme, we use a dedicated speaker label for facilitator notes so the AI agent ignores them.
	return "Facilitator Note"

func get_director_rules() -> String:
	return (
		"THEME CONTEXT: This is a structured facilitation session aimed at producing concrete outputs " +
		"(decisions, named risks, deferred questions with owners). The facilitator remains the only " +
		"human runtime identity; fixed specialist functions are hidden analytical lenses, not personas."
	)

# --- Director closure-awareness configuration ---
# The workshop populates the generic Director affordances with closure state so the
# Director picks convergent cues when the room has converged or the chair has signaled
# assent. This is the root-cause fix for characters skirting closure.

const _CONVERGENT_VERBS: Array[String] = ["Endorse", "Synthesize", "Compress", "Propose", "Bridge", "Amend", "Confirm"]
const _REACTIVE_VERBS: Array[String] = ["Challenge", "Push back on", "Correct", "Question", "Reframe"]

func get_director_directive_state() -> String:
	var ws := _get_workshop_state()
	if ws.is_empty():
		return ""
	var buckets_any: Variant = ws.get("buckets", {})
	var buckets: Dictionary = buckets_any if typeof(buckets_any) == TYPE_DICTIONARY else {}
	var d_count: int = (buckets.get("decisions", []) as Array).size() if typeof(buckets.get("decisions", [])) == TYPE_ARRAY else 0
	var r_count: int = (buckets.get("risks", []) as Array).size() if typeof(buckets.get("risks", [])) == TYPE_ARRAY else 0
	var q_count: int = (buckets.get("open_questions", []) as Array).size() if typeof(buckets.get("open_questions", [])) == TYPE_ARRAY else 0
	var stage_name: String = String(ws.get("current_stage_name", "")).strip_edges()
	var lines: Array[String] = []
	lines.append("- Decision record so far: %d/3 decisions, %d/2 risks, %d/1 deferred question." % [d_count, r_count, q_count])
	if not stage_name.is_empty():
		lines.append("- Current stage: \"%s\". The stage exists to produce concrete outputs against the targets above." % stage_name)
	var mode := _closure_mode()
	match mode:
		"vote_pending":
			var pending_text: String = _pending_vote_text()
			lines.append("- A formal proposal is currently on the table awaiting Yes/No votes: \"%s\"." % pending_text)
			lines.append("- The next response from each speaker MUST be a clear vote (open with Yes or No), optionally followed by a one-sentence rationale.")
		"convergence":
			lines.append("- The room has shown convergence in the most recent turns (the chair has signaled assent or speakers have endorsed without new objections).")
			lines.append("- Closure is the next required move: compress the agreement into a single statement, name an owner, and ask whether to record it.")
		"open":
			lines.append("- Discussion is still open. Reactive moves are appropriate. Convergent moves should appear once the room shows agreement or has been circling.")
	return "\n".join(lines)

func get_director_cue_verb_constraints() -> Dictionary:
	var mode := _closure_mode()
	match mode:
		"vote_pending":
			return {
				"preferred_verbs": ["Vote (Yes)", "Vote (No)"],
				"banned_verbs": _REACTIVE_VERBS,
				"rationale": "A vote is in progress. Cues must direct each speaker to take a clear Yes/No position, not re-open debate."
			}
		"convergence":
			return {
				"preferred_verbs": _CONVERGENT_VERBS,
				"banned_verbs": _REACTIVE_VERBS,
				"rationale": "The room has converged. Cues must drive closure — synthesize, compress, propose, endorse — not introduce new objections or push back."
			}
		_:
			return {}

func get_max_speakers_this_turn() -> int:
	var mode := _closure_mode()
	if mode == "convergence" or mode == "vote_pending":
		return 1
	return -1

# Closure-mode classifier shared by all three director-awareness hooks.
# Returns "vote_pending" | "convergence" | "open".
func _closure_mode() -> String:
	if typeof(StoryState) == TYPE_NIL or not StoryState:
		return "open"
	var state: Dictionary = StoryState.get_state()
	var ws_any: Variant = state.get("workshop_catalyst", {})
	var ws: Dictionary = ws_any if typeof(ws_any) == TYPE_DICTIONARY else {}
	var pending_any: Variant = ws.get("pending_vote", {})
	if typeof(pending_any) == TYPE_DICTIONARY and not String((pending_any as Dictionary).get("text", "")).strip_edges().is_empty():
		return "vote_pending"
	if _detect_recent_convergence(state):
		return "convergence"
	return "open"

func _pending_vote_text() -> String:
	if typeof(StoryState) == TYPE_NIL or not StoryState:
		return ""
	var state: Dictionary = StoryState.get_state()
	var ws_any: Variant = state.get("workshop_catalyst", {})
	if typeof(ws_any) != TYPE_DICTIONARY:
		return ""
	var pending_any: Variant = (ws_any as Dictionary).get("pending_vote", {})
	if typeof(pending_any) != TYPE_DICTIONARY:
		return ""
	return String((pending_any as Dictionary).get("text", "")).strip_edges()

# Convergence detection (heuristic, narrow): if the chair / facilitator role spoke
# in the last 4 entries with assent-shaped language, OR if 3+ AI characters have
# spoken without any negation/objection markers in the same window, consider the
# room converged. This is pre-vote signal — meant to flip the Director toward
# closure cues so the next AI turn naturally drives toward a proposal.
func _detect_recent_convergence(state: Dictionary) -> bool:
	var log_any: Variant = state.get("story_log", [])
	if typeof(log_any) != TYPE_ARRAY:
		return false
	var log: Array = log_any
	if log.size() < 3:
		return false
	var window_size: int = mini(log.size(), 5)
	var window: Array = log.slice(log.size() - window_size, log.size())
	var system_senders: Array = get_system_senders()
	var assent_markers := ["agreed", "let's adopt", "let us adopt", "we adopt", "i adopt",
		"that works", "i'm happy with", "happy with that", "let's go with that",
		"adopt that", "adopt it", "we have decided", "let's accept", "let us accept",
		"we accept", "i accept", "ratify", "of course we will include", "let's add it",
		"yes, let's", "yes let's", "okay, let's", "alright, let's"]
	var negation_markers := ["i disagree", "i object", "i push back", "no,", "but ",
		"however,", "before we", "wait,", "i would not", "i won't"]
	var assent_seen: bool = false
	var negation_seen: bool = false
	for entry_any in window:
		if typeof(entry_any) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_any
		var sender: String = String(entry.get("sender", "")).strip_edges()
		if sender in system_senders:
			continue
		var msg_lower: String = String(entry.get("message", "")).to_lower()
		for marker in assent_markers:
			if msg_lower.find(marker) != -1:
				assent_seen = true
				break
		for marker in negation_markers:
			if msg_lower.find(marker) != -1:
				negation_seen = true
				break
	if negation_seen:
		return false
	if assent_seen:
		return true
	return false

func should_trigger_ai_from_system_entry(sender: String, message: String) -> bool:
	# Workshop participants enter as the human Facilitator. Closure commands and
	# note-only input are intercepted before they reach the story log, so ordinary
	# Facilitator entries should continue through the existing AI response flow.
	if FacilitatorSessionSetupScript.is_facilitator_sender(sender):
		return true
	# Session Record proposals also require an immediate Yes/No response.
	return sender == "Session Record" and message.begins_with("PROPOSAL")

func get_theme_creative_mission(_phase: String, scenario: Dictionary) -> String:
	# Workshop mission is stage-driven (agenda), not narrative-arc-driven.
	var ws := _get_workshop_state()
	var stage_name := String(ws.get("current_stage_name", "")).strip_edges()
	if stage_name.is_empty():
		stage_name = "Workshop"

	var packet_text := String(scenario.get("workshop_packet_text", "")).strip_edges()
	var mission := "WORKSHOP CATALYST MISSION (CURRENT STAGE): %s\n" % stage_name
	mission += "- Drive toward the decision record: 3 decisions (with owners), 2 risks (with cost-bearers), 1 deferred question (with owner)\n"
	mission += "- When the room has explored enough, compress contributions into a decision statement and ask for assent\n"
	mission += "- Keep responses to 3–5 sentences when a decision is within reach\n"
	mission += "- Ask at most one clarifying question per turn (only if needed to unlock a decision)\n"
	var stage_guidance := _get_current_stage_guidance(scenario, stage_name)
	if not stage_guidance.is_empty():
		mission += "- Follow the authored stage guidance, particularly the required output and decision-forcing question\n"
	if not packet_text.is_empty():
		mission += "\n(Workshop packet is available in the scenario for grounding.)\n"
	if not stage_guidance.is_empty():
		mission += "\nSTAGE GUIDANCE:\n" + stage_guidance + "\n"

	mission += "\nUse plain, direct language. Keep outputs concise, name concrete consequences, and do not re-open settled points.\n"
	return mission

func generate_game_session_metaprompt(scenario: Dictionary, _characters: Array, _player_character: Dictionary) -> String:
	var prompt := ""
	prompt += _get_workshop_core_rules()
	prompt += "\n\n---\n\n"
	prompt += _get_workshop_packet_block(scenario)
	var stage_guidance_block := _get_stage_guidance_block(scenario)
	if not stage_guidance_block.is_empty():
		prompt += "\n\n---\n\n"
		prompt += stage_guidance_block
	var continuity_block := _get_workshop_continuity_block()
	if not continuity_block.is_empty():
		prompt += "\n\n---\n\n"
		prompt += continuity_block
	var steering_block := _get_workshop_steering_block(scenario)
	if not steering_block.is_empty():
		prompt += "\n\n---\n\n"
		prompt += steering_block
	prompt += "\n\n---\n\n"
	prompt += _get_workshop_live_state_block()
	return prompt

func _get_workshop_core_rules() -> String:
	return """
YOU ARE: The Workshop Catalyst -- a co-facilitator for an AI-augmented policy stress-test workshop.

YOUR PRIMARY MISSION:
Drive the group toward a decision record by end of session:
- 3 decisions made (each with an owning role and confidence level: High / Medium / Low)
- 2 risks named (each with likelihood and who absorbs the cost)
- 1 open question deferred (with a stated owner and reason for deferral)

PRIMARY RESPONSIBILITIES:
- Push the group toward explicit decisions rather than continued deliberation
- When the room has explored enough, compress contributions into a decision statement and ask: Can we agree on this, or does something need to change?
- Name institutional constraints and second-order effects that prevent agreement -- then ask: Which option can you accept and act on?
- Maintain an up-to-date structured record (decisions, risks, open questions)

RESPONSE DISCIPLINE:
- 3-5 sentences per turn when a decision is within reach (do not write longer in that state)
- Ask at most ONE clarifying question per turn (only if it unlocks a decision)
- When several roles are making the same point, compress to: The positions are X, Y, and Z. What is the decision?
- If a participant gives brief assent (okay, agreed, fair enough, sounds right), treat that as a CLOSURE SIGNAL, not an invitation to probe further. Your immediate response must confirm and read back the decision, not open a new sub-question.

COMMUNICATION REGISTER:
- Write in plain, direct language that a non-specialist participant can follow in real time. Avoid dense policy jargon, long subordinate clauses, and academic hedging.
- Prefer short sentences. State the substance first; qualifications go at the end or in a second sentence.
- When technical terms are necessary (e.g. MHRA, ICB, grey-market), use them — but do not stack multiple technical concepts in the same sentence without a plain-language anchor.
- Read back proposed decisions in one clear sentence. A decision statement should be understandable to anyone who has followed the conversation, not just domain experts.

ASSENT AND CLOSURE CALIBRATION:
- When a proposal is on the table and the group has explored the key tensions, assent should not be unreasonably withheld. The default posture is: if there is sufficient logical reason to agree and act, agree.
- A participant MAY withhold assent only if they have a genuinely new, blocking objection -- one that would make the decision unactionable or harmful as stated. Clarifying concerns, precision preferences, and "I want X named more explicitly" are not blocking objections unless the decision literally cannot be implemented without resolving them.
- If a participant has a concern that is real but not blocking, the right move is: register it as a condition, a risk, or a deferred question -- not hold up the decision.
- When the chair or facilitator signals closure ("let's adopt this", "okay, let's go with that"), remaining speakers should ask themselves: "Does my objection prevent this from being acted on?" If no, note it and assent. If yes, state it clearly and concisely -- one sentence, not a re-opening of the full debate.
- Read back the agreed position as a one-sentence decision statement, name the owner and confidence level, and ask: "Shall we log this and move on?" This is the expected closure sequence.

RESPONSE OPENING DISCIPLINE — STRUCTURAL BAN:
- BANNED STRUCTURE: Do not open any response with a sentence whose function is "the group cannot proceed until my prerequisite is resolved." This covers all variants including: "Before we get moving...", "Before we go any further...", "Before we move on...", "Before we build any framework...", "Before we record...", "Before we land on...", "Before we reach...", and any other construction that positions the speaker's concern as a blocker on the group's next action.
- WHY this is banned: these openers are stalling gambits. They reframe a legitimate concern as a veto over group progress, even when the concern could simply be stated as a position.
- REQUIRED ALTERNATIVE: State your concern or position directly as an ASSERTION or OBSERVATION, not as a prerequisite. The difference:
  BAD: "Before we get moving, I need us to agree on what failure mode we're targeting."
  GOOD: "I see three distinct failure modes here — counterfeit supply, access distortion, and inadequate clinical assessment — and they need different enforcement responses. Which one is this room optimising for?"
  BAD: "Before we go further, I want to know if telehealth is in scope."
  GOOD: "My platform's prescribing flows are live material if telehealth is in scope. Is it?"
- Open with your substantive point. Name what you see, what you support, what you challenge — not what the group must resolve before you will participate.

PROPOSAL ANALYSIS DISCIPLINE:
- When analysing a proposal, weight agreement first. Name what you agree with before naming what you do not.
- If you share a concern already named by another speaker, do not re-state it at length -- say "I share [speaker]'s concern" and add only what is genuinely new.
- Do not add precision requirements to a proposal that has already received assent. If you need more precision, register it as a deferred question with an owner, not a blocking objection.

BEHAVIORAL RULES:
- Do not let the group cycle past 4 turns on one question without naming a decision or explicitly deferring it with an owner
- Do not keep cornering the same participant; after brief resistance or assent, ask for an explicit choice then redirect
- If the group cannot agree, name the two best options, the hidden cost of each, and ask: Which option can you accept and act on?
- If a stage ends with no captured decision, flag it: We have not named a decision here. What is the closest thing we can agree on?
- If the user says note this / do not respond yet, acknowledge briefly and do not elaborate
- Decisions already listed in the DECISION RECORD are closed and final. Do not invite re-debate or re-ratification of anything already captured there. Acknowledge it as done and move to the next needed output.
- When a new stage begins, treat that as a confirmed direction signal: what the previous stage produced (or failed to produce) is on the record; focus entirely on what this stage must deliver before its timer runs out.

CLOSURE PROTOCOL (vote-based decision capture):
- The Session Record is the closure formation controller. When the room has converged on a position (or has been circling one), it will post a message labelled "PROPOSAL — Decision/Risk/Deferred question: ..." and ask each participant to vote Yes or No.
- When you see a "PROPOSAL" message from the Session Record, your very next response MUST open with the single word "Yes" or "No" (followed by punctuation), optionally followed by one short sentence of rationale. Nothing else may precede that word.
  Examples: "Yes — that captures the substance of what we agreed." or "No, the owner role isn't right yet; it should sit with the NHS lead, not the regulator."
- If you would like to use a structured token instead, you may include "<<YES>>" or "<<NO>>" anywhere in your response.
- Vote Yes only for genuine institutional commitment. Vote No if you have a substantive objection that the proposal cannot accommodate as-is.
- Do not vote on a Session Record proposal you have already voted on (your vote is already counted).
- After the vote completes (you will see a "Decision captured" or "Proposal not adopted" message from Session Record), discussion resumes normally.
"""

func _get_workshop_packet_block(scenario: Dictionary) -> String:
	var packet_text := String(scenario.get("workshop_packet_text", "")).strip_edges()
	var agenda_text := String(scenario.get("workshop_agenda_text", "")).strip_edges()
	var out := "## WORKSHOP PACKET\n"
	if packet_text.is_empty():
		out += "(No [WORKSHOP_PACKET] provided in scenario.)\n"
	else:
		out += packet_text + "\n"
	if not agenda_text.is_empty():
		out += "\n## WORKSHOP AGENDA (RAW)\n"
		out += agenda_text + "\n"
	return out

func _get_workshop_live_state_block() -> String:
	var out := "## LIVE WORKSHOP STATE\n"
	var ws := _get_workshop_state()
	if ws.is_empty():
		out += "(Workshop state not initialized yet.)\n"
		return out
	out += "Day: %s\n" % str(ws.get("day", 1))
	out += "Session: %s\n" % str(ws.get("session_label", ""))
	out += "Session Duration (min): %s\n" % str(ws.get("session_duration_minutes", 0))
	out += "Multi-day Session: %s\n" % str(ws.get("is_multi_day", false))
	out += "Resume Mode: %s\n" % str(ws.get("resume_mode", "fresh"))
	out += "Current Stage: %s\n" % str(ws.get("current_stage_name", ""))
	out += "Stage Status: %s\n" % str(ws.get("stage_status", "not_started"))
	out += "Time Remaining (sec): %s\n" % str(ws.get("stage_remaining_sec", 0))
	out += "\nBuckets:\n"
	var buckets_any: Variant = ws.get("buckets", {})
	var buckets: Dictionary = buckets_any if typeof(buckets_any) == TYPE_DICTIONARY else {}
	for key in ["ideas", "constraints", "risks", "decisions", "open_questions", "next_steps"]:
		var v_any: Variant = buckets.get(key, [])
		var v_arr: Array = v_any if typeof(v_any) == TYPE_ARRAY else []
		out += "- %s (%d)\n" % [key, v_arr.size()]
	return out

func _get_workshop_state() -> Dictionary:
	# Prefer the autoload singleton (ScenSyn uses StoryState autoload).
	if typeof(StoryState) != TYPE_NIL and StoryState and StoryState.has_method("get_state"):
		var state_dict: Dictionary = StoryState.get_state()
		var ws_any: Variant = state_dict.get("workshop_catalyst", {})
		return ws_any if typeof(ws_any) == TYPE_DICTIONARY else {}
	return {}

func _get_stage_guidance_block(scenario: Dictionary) -> String:
	var ws := _get_workshop_state()
	var stage_name := String(ws.get("current_stage_name", "")).strip_edges()
	var stage_guidance := _get_current_stage_guidance(scenario, stage_name)
	if stage_guidance.is_empty():
		return ""
	return "## ACTIVE STAGE GUIDANCE\n" + stage_guidance + "\n"

func _get_current_stage_guidance(scenario: Dictionary, stage_name: String) -> String:
	var stage_guidance_any: Variant = scenario.get("stage_guidance", {})
	var stage_guidance: Dictionary = stage_guidance_any if typeof(stage_guidance_any) == TYPE_DICTIONARY else {}
	if stage_name.is_empty() or stage_guidance.is_empty():
		return ""
	return String(stage_guidance.get(stage_name, "")).strip_edges()

func _get_workshop_continuity_block() -> String:
	if typeof(StoryState) == TYPE_NIL or not StoryState or not StoryState.has_method("get_state"):
		return ""
	var state: Dictionary = StoryState.get_state()
	var ws := _get_workshop_state()
	var memory_any: Variant = state.get("memory_context", {})
	var memory_context: Dictionary = memory_any if typeof(memory_any) == TYPE_DICTIONARY else {}
	var cues_any: Variant = state.get("continuity_prompt_cues", {})
	var prompt_cues: Dictionary = cues_any if typeof(cues_any) == TYPE_DICTIONARY else {}
	var lines: Array[String] = []

	var resume_summary: String = str(ws.get("resume_summary", "")).strip_edges()
	if not resume_summary.is_empty():
		lines.append("- Resume summary: " + resume_summary)

	var session_history: String = str(memory_context.get("session_history", "")).strip_edges()
	if not session_history.is_empty():
		lines.append("- Prior workshop record: " + session_history)

	var anchors_any: Variant = prompt_cues.get("continuity_anchors", [])
	var anchors: Array = anchors_any if typeof(anchors_any) == TYPE_ARRAY else []
	if not anchors.is_empty():
		lines.append("- Carry-forward anchors: " + ", ".join(anchors))

	var tensions_any: Variant = prompt_cues.get("latent_tensions", [])
	var tensions: Array = tensions_any if typeof(tensions_any) == TYPE_ARRAY else []
	if not tensions.is_empty():
		lines.append("- Unresolved tensions still in play: " + "; ".join(tensions))

	var focus_terms_any: Variant = prompt_cues.get("focus_terms", [])
	var focus_terms: Array = focus_terms_any if typeof(focus_terms_any) == TYPE_ARRAY else []
	if not focus_terms.is_empty():
		lines.append("- Carry-forward focus terms: " + ", ".join(focus_terms))

	var continuity_prompt: String = str(prompt_cues.get("continuity_prompt", "")).strip_edges()
	if not continuity_prompt.is_empty():
		lines.append("- Suggested facilitation focus: " + continuity_prompt)

	var unresolved_any: Variant = state.get("unresolved_challenges", [])
	var unresolved: Array = unresolved_any if typeof(unresolved_any) == TYPE_ARRAY else []
	if not unresolved.is_empty():
		lines.append("- Unresolved questions or challenges: " + "; ".join(unresolved))

	if lines.is_empty():
		return ""
	return "## WORKSHOP CONTINUITY\n" + "\n".join(lines) + "\n"

func _get_workshop_steering_block(scenario: Dictionary) -> String:
	var ws := _get_workshop_state()
	var lines: Array[String] = []
	var recent_entries: Array = _get_recent_workshop_entries(8)
	if not recent_entries.is_empty():
		lines.append("- Recent turn order: " + _build_recent_turn_order(recent_entries))
	var compressed_speaker: String = _find_compressed_speaker(recent_entries)
	if not compressed_speaker.is_empty():
		lines.append("- Steering signal: %s has been giving relatively short replies while others keep pressing. Stop stacking pressure. Summarize the pressure once, ask for an explicit choice or threshold, then redirect." % compressed_speaker)
	var stage_status: String = String(ws.get("stage_status", "not_started")).strip_edges()
	var time_remaining_sec: int = int(ws.get("stage_remaining_sec", 0))
	if stage_status == "completed":
		lines.append("- Steering signal: the current stage is complete. Stop extending debate. Summarize outputs, record what remains open, and suggest advancing when appropriate.")
	elif time_remaining_sec > 0 and time_remaining_sec <= 120:
		lines.append("- Steering signal: less than two minutes remain in this stage. Shift from exploration into synthesis, decisions, and transition readiness.")
	var buckets_any: Variant = ws.get("buckets", {})
	var buckets: Dictionary = buckets_any if typeof(buckets_any) == TYPE_DICTIONARY else {}
	var decisions_arr_any: Variant = buckets.get("decisions", [])
	var decisions_arr: Array = decisions_arr_any if typeof(decisions_arr_any) == TYPE_ARRAY else []
	var risks_arr_any: Variant = buckets.get("risks", [])
	var risks_arr: Array = risks_arr_any if typeof(risks_arr_any) == TYPE_ARRAY else []
	var oq_arr_any: Variant = buckets.get("open_questions", [])
	var oq_arr: Array = oq_arr_any if typeof(oq_arr_any) == TYPE_ARRAY else []
	var target_decisions := 3
	var target_risks := 2
	if decisions_arr.size() < target_decisions and recent_entries.size() >= 3:
		lines.append("- Decision record: %d of %d decisions captured. Drive toward the next decision before advancing." % [decisions_arr.size(), target_decisions])
	if risks_arr.size() < target_risks and recent_entries.size() >= 3:
		lines.append("- Decision record: %d of %d risks named. Make the next response name a risk with its likelihood and who absorbs the cost." % [risks_arr.size(), target_risks])
	if oq_arr.is_empty() and recent_entries.size() >= 6:
		lines.append("- Decision record: no deferred question captured yet. Watch for an unresolvable question and name its owner before the session ends.")
	if lines.is_empty():
		return ""
	return "## FACILITATION STEERING\n" + "\n".join(lines) + "\n"

func _get_recent_workshop_entries(limit_count: int) -> Array:
	if typeof(StoryState) == TYPE_NIL or not StoryState or not StoryState.has_method("get_state"):
		return []
	var state: Dictionary = StoryState.get_state()
	var story_log_any: Variant = state.get("story_log", [])
	var story_log: Array = story_log_any if typeof(story_log_any) == TYPE_ARRAY else []
	var recent_entries: Array = []
	for entry_index: int in range(story_log.size() - 1, -1, -1):
		var entry_any: Variant = story_log[entry_index]
		if typeof(entry_any) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_any
		var sender_name: String = String(entry.get("sender", "")).strip_edges()
		if sender_name.is_empty() or sender_name == "Narrator" or sender_name == "Facilitator Note" or sender_name == "Session Record":
			continue
		recent_entries.push_front(entry)
		if recent_entries.size() >= limit_count:
			break
	return recent_entries

func _build_recent_turn_order(recent_entries: Array) -> String:
	var senders: Array[String] = []
	for entry_any in recent_entries:
		if typeof(entry_any) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_any
		var sender_name: String = String(entry.get("sender", "")).strip_edges()
		if not sender_name.is_empty():
			senders.append(sender_name)
	return " -> ".join(senders)

func _find_compressed_speaker(recent_entries: Array) -> String:
	if recent_entries.size() < 4:
		return ""
	var counts_by_sender: Dictionary = {}
	var lengths_by_sender: Dictionary = {}
	for entry_any in recent_entries:
		if typeof(entry_any) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_any
		var sender_name: String = String(entry.get("sender", "")).strip_edges()
		var message_text: String = String(entry.get("message", "")).strip_edges()
		if sender_name.is_empty() or message_text.is_empty():
			continue
		counts_by_sender[sender_name] = int(counts_by_sender.get(sender_name, 0)) + 1
		lengths_by_sender[sender_name] = int(lengths_by_sender.get(sender_name, 0)) + message_text.length()
	if counts_by_sender.size() < 3:
		return ""
	for sender_key_any in counts_by_sender.keys():
		var sender_key: String = String(sender_key_any)
		var sender_count: int = int(counts_by_sender.get(sender_key, 0))
		if sender_count <= 0 or sender_count > 2:
			continue
		var sender_average_length: float = float(int(lengths_by_sender.get(sender_key, 0))) / float(sender_count)
		var longer_speaker_count: int = 0
		for other_sender_any in counts_by_sender.keys():
			var other_sender: String = String(other_sender_any)
			if other_sender == sender_key:
				continue
			var other_count: int = int(counts_by_sender.get(other_sender, 0))
			if other_count <= 0:
				continue
			var other_average_length: float = float(int(lengths_by_sender.get(other_sender, 0))) / float(other_count)
			if other_average_length > sender_average_length * 1.8:
				longer_speaker_count += 1
		if longer_speaker_count >= 2:
			return sender_key
	return ""

func _all_buckets_empty(buckets: Dictionary) -> bool:
	for bucket_key: String in ["ideas", "constraints", "risks", "decisions", "open_questions", "next_steps"]:
		var items_any: Variant = buckets.get(bucket_key, [])
		var items: Array = items_any if typeof(items_any) == TYPE_ARRAY else []
		for item_any in items:
			if String(item_any).strip_edges() != "":
				return false
	return true

func get_system_senders() -> Array[String]:
	var senders: Array[String] = super.get_system_senders()
	senders.append("Session Record")
	senders.append("Workshop Catalyst")
	return senders

# --- Closure formation: vote handling ---
# The Session Record is the "closure formation controller". It generates Yes/No
# proposals (call_vote_from_recent_log) and tallies/captures them (record_vote).
# This manager's job for voting is just to detect votes in actor dialogue and
# forward them to the session record. Everything else lives in the session record.

var _session_record: WorkshopCatalystSessionRecord = null

func set_cast(_cast_names: Array) -> void:
	# Compatibility hook: Workshop Catalyst intentionally has no runtime cast.
	pass

# Wired from workshop_catalyst_controller.initialize() so the manager can route
# detected votes back to the session record's tally logic.
func set_session_record(sr: WorkshopCatalystSessionRecord) -> void:
	_session_record = sr

func process_actor_dialogue(character_name: String, dialogue: String) -> String:
	var cleaned: String = dialogue
	if _has_pending_vote():
		# A vote is on the table — only look for vote tokens / Yes-No openers.
		const YES_TOKEN := "<<YES>>"
		const NO_TOKEN := "<<NO>>"
		if YES_TOKEN in cleaned:
			cleaned = cleaned.replace(YES_TOKEN, "").strip_edges()
			_route_vote(character_name, "yes")
			return cleaned
		if NO_TOKEN in cleaned:
			cleaned = cleaned.replace(NO_TOKEN, "").strip_edges()
			_route_vote(character_name, "no")
			return cleaned
		# Strict opener-only natural language.
		var opener_choice: String = _strict_opener_vote(cleaned)
		if not opener_choice.is_empty():
			_route_vote(character_name, opener_choice)
		return cleaned
	# No vote pending — scan for explicit closure-request language. When a character
	# says "can we adopt that as decision N", "ask the room for assent", "let's record
	# this as agreed" etc., they are explicitly asking for closure. This is high-precision
	# (characters don't use this language casually) so we trigger a vote immediately.
	if _looks_like_closure_request(cleaned):
		_request_vote_call("closure_request_from_%s" % character_name)
	return cleaned

# High-precision closure-request detector. Only matches phrasing that is unambiguously
# a request to capture/adopt/ratify a position, not generic agreement.
func _looks_like_closure_request(dialogue: String) -> bool:
	var tl: String = dialogue.to_lower()
	var markers: Array[String] = [
		"can we adopt", "can we accept", "can we agree",
		"can we record", "can we capture", "can we mark",
		"can we ratify", "can we lock", "can we commit",
		"can we take that as decision", "can we take that as a decision",
		"can we take this as decision", "can we take this as a decision",
		"can we read that back", "can we close on", "can we close that",
		"shall we adopt", "shall we accept", "shall we record", "shall we capture",
		"should we adopt", "should we accept", "should we record",
		"should we mark this", "should we mark that",
		"let's adopt that", "let's adopt this", "let us adopt that", "let us adopt this",
		"let's record that", "let's record this", "let us record that", "let us record this",
		"let's lock", "let's commit to that", "let us commit to that",
		"let's mark this", "let's mark that", "let us mark this", "let us mark that",
		"i think we have enough to close",
		"ask the room for assent", "ask the group for assent",
		"get a read from the group", "read from the group",
		"propose we adopt", "propose we accept", "propose we record",
		"propose we capture", "propose we mark", "propose we ratify"
	]
	for marker in markers:
		if tl.find(marker) != -1:
			return true
	return false

# Defer the async vote-call so process_actor_dialogue can stay synchronous.
# The session record itself guards against duplicate concurrent invocations.
func _request_vote_call(trigger: String) -> void:
	if not _session_record or not _session_record.has_method("call_vote_from_recent_log"):
		return
	# Suppress autonomous closure-request triggers during the post-capture riff window.
	# This is critical for breaking the vote-rationale-triggers-new-vote feedback loop.
	# Facilitator /vote (handled directly in game_session_ai_flow_utils) bypasses this.
	if _session_record.has_method("is_in_capture_cooldown") and _session_record.is_in_capture_cooldown():
		return
	_session_record.call_deferred("call_vote_from_recent_log", trigger)

# Returns "yes", "no", or "" depending on whether the dialogue opens with a vote-shaped word.
# Skips a leading speaker-name colon prefix if the orchestrator left one in place.
func _strict_opener_vote(dialogue: String) -> String:
	var s: String = dialogue.strip_edges()
	if s.is_empty():
		return ""
	# Strip leading "<character name>: " (if any actor prefix slipped through)
	var colon_idx: int = s.find(":")
	if colon_idx > 0 and colon_idx < 60 and s.substr(0, colon_idx).find(" ") < 0:
		# Looks like a name prefix — skip it.
		s = s.substr(colon_idx + 1).strip_edges()
	# Strip leading quotation marks / asterisks etc. that LLMs sometimes add.
	while not s.is_empty() and s[0] in ["\"", "'", "*", "_", "(", "["]:
		s = s.substr(1).strip_edges()
	if s.is_empty():
		return ""
	# Pull the first whitespace-/punctuation-separated token.
	var first_token: String = ""
	for i in range(s.length()):
		var ch: String = s[i]
		if ch in [" ", ",", ".", "!", "?", ";", ":", "\n", "\t"]:
			break
		first_token += ch
	var tl: String = first_token.to_lower()
	if tl == "yes" or tl == "yeah" or tl == "yep" or tl == "agreed" or tl == "aye":
		return "yes"
	if tl == "no" or tl == "nope" or tl == "nay":
		return "no"
	return ""

func _route_vote(voter: String, choice: String) -> void:
	if _session_record and _session_record.has_method("record_vote"):
		_session_record.record_vote(voter, choice)

func _has_pending_vote() -> bool:
	if typeof(StoryState) == TYPE_NIL or not StoryState:
		return false
	var state: Dictionary = StoryState.get_state()
	var ws_any: Variant = state.get("workshop_catalyst", {})
	if typeof(ws_any) != TYPE_DICTIONARY:
		return false
	var pv_any: Variant = (ws_any as Dictionary).get("pending_vote", {})
	if typeof(pv_any) != TYPE_DICTIONARY:
		return false
	return not String((pv_any as Dictionary).get("text", "")).strip_edges().is_empty()
