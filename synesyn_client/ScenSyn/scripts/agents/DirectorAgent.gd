extends Node

## Reasoning budget for the cue batch, on providers that accept one (currently xAI).
## A cue is one sentence of direction that no participant ever reads, and on Grok the
## default budget spent about four times as many hidden reasoning tokens on it as the
## cue itself was long — several seconds of every turn's wait. Measured across repeated
## runs, a low budget returns the same speaker choices and a well-formed batch, roughly
## a third faster. Set to "" to hand the call back to the provider's default. See ADR 0028.
const CUE_REASONING_EFFORT: String = "low"

var conversation_manager
var metaprompt_manager
var _last_cues: Dictionary = {} # NEW: Memory for the last cue generated per character

func initialize(p_conv_manager, p_metaprompt_manager):
	conversation_manager = p_conv_manager
	metaprompt_manager = p_metaprompt_manager

func generate_scene_plan(story_log: Array, human_input: Dictionary, ai_characters: Array, planned_speakers: Array, current_phase: String, narrative_mandate: String, scenario: Dictionary) -> Dictionary:
	var plan_result := {
		"turn_outcome": "Tactical", # This is now a fixed identifier
		"scene_aim": narrative_mandate,
		"plan": []
	}
	var external_turn_context: String = ""
	if metaprompt_manager and metaprompt_manager.has_method("get_latest_turn_context_for_prompt"):
		external_turn_context = String(metaprompt_manager.get_latest_turn_context_for_prompt("")).strip_edges()

	var last_line_entry = story_log.back() if not story_log.is_empty() else {"sender": "Narrator", "message": "The scene begins."}
	var last_speaker = last_line_entry.get("sender", "Narrator")
	var last_line = last_line_entry.get("message", "")

	# PERFORMANCE FIX:
	# Previously we generated one tactical cue per planned speaker (N sequential model calls),
	# then invoked the actors (N more calls). That made Story Stage feel "stuck".
	# We now generate all cues in ONE director call, then build cue cards locally.

	var per_speaker: Array = []
	for speaker_name in planned_speakers:
		var delivery_rules = metaprompt_manager.get_character_delivery_rules(speaker_name, current_phase, scenario)
		var addressee = str(delivery_rules.get("address_to", "")).strip_edges()
		if addressee.is_empty():
			addressee = _determine_addressee(speaker_name, last_speaker, str(human_input.get("sender", "")).strip_edges(), ai_characters)
		var turn_obligation := ""
		if metaprompt_manager and metaprompt_manager.has_method("get_character_turn_obligation"):
			turn_obligation = String(metaprompt_manager.get_character_turn_obligation(speaker_name)).strip_edges()
		per_speaker.append({
			"character_name": speaker_name,
			"persona": _get_persona_summary(scenario, speaker_name),
			"addressee": addressee,
			"delivery_note": str(delivery_rules.get("delivery_note", "")).strip_edges(),
			"turn_obligation": turn_obligation,
		})

	# Resolve a per-scenario model override for the Director batch call. This is a
	# Tier-1 cost lever: scenarios can route the Director (a structurally simple
	# task — write one sentence per speaker) to a smaller/cheaper model than the
	# Actor without changing the global current model. Unset => current model.
	var director_model_override: String = _resolve_agent_model_override(scenario, "director_model")
	var cues_by_name: Dictionary = await _generate_tactical_cues_batch(story_log, per_speaker, current_phase, scenario, narrative_mandate, external_turn_context, director_model_override)

	for speaker_name in planned_speakers:
		var delivery_rules2 = metaprompt_manager.get_character_delivery_rules(speaker_name, current_phase, scenario)
		var addressee2 = str(delivery_rules2.get("address_to", "")).strip_edges()
		if addressee2.is_empty():
			addressee2 = _determine_addressee(speaker_name, last_speaker, str(human_input.get("sender", "")).strip_edges(), ai_characters)

		var tactical_cue: String = str(cues_by_name.get(speaker_name, "")).strip_edges()
		if tactical_cue.is_empty():
			tactical_cue = "Answer or react directly to %s, addressing %s." % [last_speaker, addressee2]

		var persona_summary2 = _get_persona_summary(scenario, speaker_name)
		var scene_partners = []
		for character in ai_characters:
			var partner_name: String = String(character.get("name", ""))
			if partner_name != speaker_name:
				scene_partners.append({
					"name": partner_name,
					"persona": _get_persona_brief(scenario, partner_name)
				})

		# Per-scenario actor model override (Tier-1 cost lever). Empty string =>
		# use the global current model. Resolved once per scene plan, stamped into
		# each cue card so the Actor's chat() call can pass it through unchanged.
		var actor_model_override: String = _resolve_agent_model_override(scenario, "actor_model")
		# A line an actor speaks is the writing, so its reasoning budget is left to the
		# provider unless a scenario asks otherwise. A scenario whose cast speaks in short
		# plain turns can spend less on thinking and wait less for each line.
		var actor_effort: String = _resolve_agent_model_override(scenario, "actor_reasoning_effort")
		var cue_card = {
			"character_name": speaker_name,
			"scene_aim": narrative_mandate,
			"persona": persona_summary2,
			"cue": {
				"text": tactical_cue,
				"word_count_hint": "brief"
			},
			"addressee": addressee2,
			"delivery_rules": delivery_rules2,
			"scene_partners": scene_partners,
			"full_log_for_context": story_log,
			"external_turn_context": external_turn_context,
			"turn_obligation": String(_get_per_speaker_value(per_speaker, speaker_name, "turn_obligation")).strip_edges(),
			"allow_technical_speech": _character_allows_technical_speech(scenario, speaker_name),
			"scenario_guardrails": _get_scenario_guardrails(speaker_name),
			"actor_model_override": actor_model_override,
			"actor_reasoning_effort": actor_effort,
		}
		plan_result.plan.append(cue_card)

	var prompt_log = "--- DIRECTOR PROMPT LOG (Tactical Director) ---\n"
	prompt_log += "SCENE AIM: %s\n" % narrative_mandate
	prompt_log += "LAST LINE: %s: %s\n" % [last_speaker, last_line]
	prompt_log += "PLANNED SPEAKERS: %s\n" % str(planned_speakers)
	prompt_log += "\n--- GENERATED PLAN ---\n"
	for card in plan_result.plan:
		prompt_log += "  - CUE FOR %s: %s\n" % [card.character_name, card.cue.text]

	# Avoid writing debug logs to res:// (can be slow or read-only in exports).
	# If needed, diagnostics should go to user:// or the workspace logs directory.

	return plan_result


func _generate_tactical_cues_batch(story_log: Array, per_speaker: Array, current_phase: String, scenario: Dictionary, narrative_mandate: String, external_turn_context: String = "", model_override: String = "") -> Dictionary:
	if conversation_manager == null:
		return {}
	if per_speaker.is_empty():
		return {}

	var last_turn_dialogue = _get_recent_dialogue_as_text(story_log, 6)
	var speaker_lines: Array[String] = []
	for item_any in per_speaker:
		if typeof(item_any) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = item_any
		var speaker_name: String = str(item.get("character_name", "")).strip_edges()
		if speaker_name.is_empty():
			continue
		var persona: String = str(item.get("persona", "")).strip_edges()
		var addressee: String = str(item.get("addressee", "")).strip_edges()
		var note: String = str(item.get("delivery_note", "")).strip_edges()
		var turn_obligation: String = str(item.get("turn_obligation", "")).strip_edges()
		var ln := "- %s | address: %s | persona: %s" % [speaker_name, addressee, persona]
		if not note.is_empty():
			ln += " | delivery_note: %s" % note
		if not turn_obligation.is_empty():
			ln += " | turn_obligation: %s" % turn_obligation
		speaker_lines.append(ln)

	var theme_director_rules := ""
	if metaprompt_manager and metaprompt_manager.has_method("get_director_rules"):
		theme_director_rules = String(metaprompt_manager.get_director_rules()).strip_edges()

	# --- Generic theme-configurable Director affordances ---
	# Themes can populate these to drive the Director toward specific intents
	# (closure for workshops, escalation for narratives, mastery for tutoring, etc.).
	var directive_state := ""
	if metaprompt_manager and metaprompt_manager.has_method("get_director_directive_state"):
		directive_state = String(metaprompt_manager.get_director_directive_state()).strip_edges()
	var cue_verb_constraints: Dictionary = {}
	if metaprompt_manager and metaprompt_manager.has_method("get_director_cue_verb_constraints"):
		var raw_constraints: Variant = metaprompt_manager.get_director_cue_verb_constraints()
		if typeof(raw_constraints) == TYPE_DICTIONARY:
			cue_verb_constraints = raw_constraints

	var directive_state_block := ""
	if not directive_state.is_empty():
		directive_state_block = "\nDIRECTIVE STATE (you MUST act on this when picking cues):\n%s\n" % directive_state

	var verb_constraint_block := ""
	if not cue_verb_constraints.is_empty():
		var lines: Array[String] = []
		var preferred_any: Variant = cue_verb_constraints.get("preferred_verbs", [])
		if typeof(preferred_any) == TYPE_ARRAY and not (preferred_any as Array).is_empty():
			lines.append("- For this turn, your cue verbs SHOULD come from: %s." % ", ".join(preferred_any))
		var banned_any: Variant = cue_verb_constraints.get("banned_verbs", [])
		if typeof(banned_any) == TYPE_ARRAY and not (banned_any as Array).is_empty():
			lines.append("- For this turn, you MUST NOT use these cue verbs: %s." % ", ".join(banned_any))
		var rationale_text: String = String(cue_verb_constraints.get("rationale", "")).strip_edges()
		if not rationale_text.is_empty():
			lines.append("- Reason: %s" % rationale_text)
		if not lines.is_empty():
			verb_constraint_block = "\nCUE VERB CONSTRAINTS (apply on top of the default verb palette):\n%s\n" % "\n".join(lines)

	var prompt := """
You are a performance and dialogue director for a performative role play experience.
Write ONE tactical instruction (one sentence) for EACH planned speaker below.

PRIME DIRECTIVE: Each cue must be a direct, logically coherent reaction to the most recent conversational action.
If the last action was a direct question, the cue must ensure it gets answered.
If fresh scenario context is provided, each cue must use it concretely instead of drifting into generic commentary.

SCENE AIM: %s
%s%s
RECENT DIALOGUE (most recent last):
%s

OPTIONAL FRESH TURN CONTEXT:
%s

PLANNED SPEAKERS (one per line):
%s

RULES:
- Ground each cue in the concrete content of the recent dialogue — specific claims, proposals, or tensions already on the table.
- Keep each speaker true to their character and perspective. Do not force artificial contrast purely for variety.
- "Accept or reject something proposed in the last turn only if it is reasonable and logically aligned with the character's persona and goals."
- Avoid vague cues like "respond thoughtfully" or "reflect on the situation."
- Use active verbs that point at a specific action: Challenge, Build on, Push back on, Correct, Question, Endorse, Concede, Clarify, Reframe, Propose, Name, Offer.
- Never use prerequisite-framing constructions ("raise X before the group proceeds", "flag X before moving on", "ensure X is addressed first"). These produce stalling dialogue. State the action directly.
%s
OUTPUT FORMAT (STRICT):
Return exactly one line per speaker, like:
SpeakerName: cue sentence

Do not add numbering, quotes, markdown, or extra commentary.
""" % [narrative_mandate, directive_state_block, verb_constraint_block, last_turn_dialogue, external_turn_context if external_turn_context != "" else "- No fresh scenario turn context provided.", "\n".join(speaker_lines), ("- " + theme_director_rules + "\n") if not theme_director_rules.is_empty() else ""]

	var cue_effort: String = _resolve_agent_model_override(scenario, "director_reasoning_effort")
	if cue_effort.is_empty():
		cue_effort = CUE_REASONING_EFFORT
	var call_settings: Dictionary = {}
	if not normalized_reasoning_effort(cue_effort).is_empty():
		call_settings["reasoning_effort"] = normalized_reasoning_effort(cue_effort)
	var response = await conversation_manager.chat(prompt, _scoped_thread_name("director_tactical_batch"), model_override, call_settings)
	if not (response and response.success):
		return {}
	var raw: String = String(response.response).strip_edges()
	if raw.is_empty():
		return {}

	var out: Dictionary = {}
	for line_any in raw.split("\n"):
		var ln: String = String(line_any).strip_edges()
		if ln.is_empty():
			continue
		var parts: PackedStringArray = ln.split(":", true, 1)
		if parts.size() != 2:
			continue
		var who: String = String(parts[0]).strip_edges()
		var cue: String = String(parts[1]).strip_edges()
		if who.is_empty() or cue.is_empty():
			continue
		out[who] = cue
		_last_cues[who] = cue
	return out

func _generate_tactical_cue(story_log: Array, speaker_name: String, addressee: String, current_phase: String, scenario: Dictionary) -> String:
	var last_turn_dialogue = _get_recent_dialogue_as_text(story_log, 4)
	var speaker_persona = _get_persona_summary(scenario, speaker_name)

	var special_instructions = ""
	# Rule for Openings: Generic Greeting Acknowledgment
	if story_log.size() <= 2: # First or second entry (Narrator, then Player)
		var last_entry = story_log.back()
		var last_message = String(last_entry.get("message", "")).to_lower()
		if last_message == "hello" or last_message == "hi" or last_message == "hello." or last_message == "hi.":
			special_instructions += "\n**SPECIAL INSTRUCTION FOR THIS TURN:** This is the first exchange. If the player offered a greeting, your instruction MUST ensure the actor acknowledges, responds to, reacts to or dismisses the greeting in a natural or convincing manner before pivoting to their character's core concerns by creating a realistic and intuitive entry point from which the narrative can proceed."

	# Get character-specific instructions from the metaprompt manager
	if metaprompt_manager and metaprompt_manager.has_method("get_director_instructions"):
		var char_specific_instructions = metaprompt_manager.get_director_instructions(speaker_name, current_phase, scenario)
		if not char_specific_instructions.is_empty():
			special_instructions += char_specific_instructions

		# NEW: Add instruction to encourage variety for characters with creative briefs
		if not char_specific_instructions.is_empty() and _last_cues.has(speaker_name):
			var last_cue = _last_cues[speaker_name]
			special_instructions += "\n**NOTE FOR VARIETY:** In the last turn, the cue was: '%s'. Consider choosing a different option from the creative brief for this turn unless you have a strong and logical reason to repeat a similar approach." % last_cue


	var prompt = """
You are a performance and dialogue director for a performative role play experience. Your task is to write a single, sharp, tactical instruction for an actor or character playing a role in a scenario. This instruction should prompt a line of dialogue that is a direct and compelling **reaction** to the previous **conversational action**, while staying true to the actor's character.

**PRIME DIRECTIVE:** Your absolute priority is to generate a cue that is a **logically coherent and direct reaction** to the last conversational action. This is more important than expressing the character's general personality. The persona should only **flavor** the logical reaction.

**CONTEXT:**
Here is the most recent dialogue:
%s

**YOUR TASK:**
The next character to speak is **%s**.
Their core persona is: **%s**.
They should address **%s**.
%s

**THOUGHT PROCESS (Follow these steps internally before writing the instruction):**
1.  **Analyze the Last Conversational Action:** First, determine if the last speaker was asking a direct question that requires an answer, agreement, disagreement,or making a statement. Then, identify the core intent (e.g., "The analyst was asking for counsel," "The authority figure was asserting control").
2.  **Determine Priority & Reaction:** If the last action was a direct question, your absolute priority is to generate a cue that answers it. Otherwise, your priority is a logical reaction based on the character's persona and tactical goal and that does not stall the converation with cyclic discussion.
3.  **Formulate the Cue:** Now, combine the priority and reaction to formulate the final, one-sentence creative instruction.

Write a one-sentence creative instruction for the actor playing **%s**.
The instruction must be a direct, tactical and logical reaction to the last conversational action.
**IMPORTANT:** If your instruction requires the actor to refer to something a specific character said, you MUST name that character explicitly. For example, use "Challenge the strategist's claim about..." instead of the ambiguous "Challenge their claim...". This will prevent misattribution.

Example instructions:
- "Propose a concrete formulation that resolves the tension between the two positions just stated."
- "Push back on the last speaker's framing by naming the specific case it fails to account for."
- "Accept or reject something proposed in the last turn only if it is reasonable and logically aligned with the character's persona and goals."
- "Concede the previous point but add the one condition that makes it workable in practice if it is reasonable and logically aligned with the character's persona and goals."
- "Compress the last several contributions into a single direct question the group must answer."

**INSTRUCTION FOR %s:**
""" % [last_turn_dialogue, speaker_name, speaker_persona, addressee, special_instructions, speaker_name, speaker_name]

	var thread = _scoped_thread_name("director_tactical_cue")
	var response = await conversation_manager.chat(prompt, thread)

	if response and response.success:
		var cue = String(response.response).strip_edges()
		# Clean up potential LLM artifacts like quotes or prefixes
		if cue.begins_with("\"") and cue.ends_with("\""):
			cue = cue.substr(1, cue.length() - 2)
		if cue.to_lower().begins_with("instruction for %s:" % speaker_name.to_lower()):
			cue = cue.substr(cue.find(":") + 1).strip_edges()
		print("[DirectorAgent] Generated Tactical Cue for %s: %s" % [speaker_name, cue])
		_last_cues[speaker_name] = cue # NEW: Remember the generated cue
		return cue

	print("[DirectorAgent] ERROR: Tactical Cue generation failed for %s." % speaker_name)
	return ""

# Resolve the per-call model id for an agent from the scenario's system_config.
#
# Returns "" when no override is configured, which tells ConversationManager to
# use the global current model (legacy behaviour, unchanged).
#
# To activate model routing for a scenario, add to its [SYSTEM_CONFIG] section:
#   director_model: gpt-4o-mini     <- Director batch call uses this model
#   actor_model: claude-sonnet-4-6  <- every Actor call uses this model
#
# The same reader serves the reasoning-budget keys, which are the other lever on what
# a turn costs in seconds on a provider that thinks before it answers:
#   director_reasoning_effort: default  <- undo the low budget cues are written on
#   actor_reasoning_effort: low         <- spend less thinking on each spoken line
#
# Keys are lowercased by ScenarioLoader before storage, so the lookup is exact.
# The override is per-call only: the manager's global current-model state is
# never mutated.
## Reading of a reasoning-budget setting, wherever one is configured.
## "default" (or an unset value) means send nothing and let the provider decide, which is
## also what every provider but xAI does with the setting today.
static func normalized_reasoning_effort(value: String) -> String:
	var effort: String = value.strip_edges().to_lower()
	return "" if effort in ["", "default", "none"] else effort

func _resolve_agent_model_override(scenario: Dictionary, key: String) -> String:
	if scenario == null or scenario.is_empty():
		return ""
	var sys_any: Variant = scenario.get("system_config", {})
	if typeof(sys_any) != TYPE_DICTIONARY:
		return ""
	var sys: Dictionary = sys_any
	return String(sys.get(key, "")).strip_edges()

func _get_per_speaker_value(per_speaker: Array, speaker_name: String, field_name: String) -> Variant:
	for item_any in per_speaker:
		if typeof(item_any) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = item_any
		if String(item.get("character_name", "")).strip_edges() == speaker_name:
			return item.get(field_name)
	return null

func _character_allows_technical_speech(scenario: Dictionary, character_name: String) -> bool:
	if metaprompt_manager == null or not metaprompt_manager.has_method("allows_technical_speech"):
		return false
	if not scenario or not scenario.has("characters"):
		return false
	for c in scenario.characters:
		if String(c.get("name", "")).strip_edges() == character_name:
			return bool(metaprompt_manager.allows_technical_speech(String(c.get("role", ""))))
	return false

func _get_scenario_guardrails(character_name: String) -> Dictionary:
	if metaprompt_manager == null or not metaprompt_manager.has_method("get_current_turn_guardrails"):
		return {}
	var guardrails_any: Variant = metaprompt_manager.get_current_turn_guardrails(character_name)
	if typeof(guardrails_any) == TYPE_DICTIONARY:
		return guardrails_any
	return {}

func _scoped_thread_name(suffix: String) -> String:
	var cleaned_suffix := suffix.replace(" ", "_")
	var ts := str(Time.get_ticks_msec())
	if conversation_manager and conversation_manager.has_method("get_current_thread"):
		var base_thread := str(conversation_manager.get_current_thread()).strip_edges()
		if base_thread != "":
			return base_thread + "__" + cleaned_suffix + "_" + ts
	return cleaned_suffix + "_" + ts

func _determine_addressee(speaker: String, last_speaker: String, human_name: String, all_characters: Array) -> String:
	if last_speaker != speaker and last_speaker != "Narrator":
		return last_speaker # Default to addressing the person who just spoke.

	if human_name != "" and human_name != speaker:
		return human_name # If the last speaker was self or narrator, address the human.

	# Fallback: address anyone but self
	for character in all_characters:
		var candidate_name: String = String(character.get("name", ""))
		if candidate_name != speaker:
			return candidate_name

	return "the group" # Final fallback

func _get_persona_summary(scenario: Dictionary, character_name: String) -> String:
	if not scenario or not scenario.has("characters"):
		return "A character in a scene."

	for character in scenario.characters:
		if character.get("name") == character_name:
			var role_str: String = String(character.get("role", "")).strip_edges()
			var instructions: String = String(character.get("behavioral_instructions", "")).strip_edges()
			if instructions.is_empty():
				return role_str if not role_str.is_empty() else "A character with unknown motives."
			var parts: Array[String] = []
			if not role_str.is_empty():
				parts.append("Role: " + role_str)
			parts.append(instructions)
			return "\n".join(parts)

	return "A character with unknown motives."

func _get_persona_brief(scenario: Dictionary, character_name: String) -> String:
	if not scenario or not scenario.has("characters"):
		return "A character in a scene."
	for character in scenario.characters:
		if character.get("name") == character_name:
			var role_str: String = String(character.get("role", "")).strip_edges()
			var instructions: String = String(character.get("behavioral_instructions", "")).strip_edges()
			if instructions.is_empty():
				return role_str if not role_str.is_empty() else "A character with unknown motives."
			var first_line := ""
			for line_str in instructions.split("\n"):
				var cleaned: String = line_str.strip_edges().trim_prefix("-").strip_edges()
				if not cleaned.is_empty():
					first_line = cleaned
					break
			if role_str.is_empty():
				return first_line if not first_line.is_empty() else "A character with unknown motives."
			return role_str + " — " + first_line
	return "A character with unknown motives."

func _get_character_role(scenario: Dictionary, character_name: String) -> String:
	if not scenario or not scenario.has("characters"):
		return ""

	for character in scenario.characters:
		if character.get("name") == character_name:
			return String(character.get("role", "")).strip_edges()

	return ""

func _get_recent_dialogue_as_text(story_log: Array, line_count: int) -> String:
	var lines := []
	var start_index = max(0, story_log.size() - line_count)
	for i in range(start_index, story_log.size()):
		var entry = story_log[i]
		var sender = entry.get("sender", "Unknown")
		if sender == "Narrator": continue # Skip narrator lines for this context
		lines.append("%s: %s" % [sender, entry.get("message", "")])
	return "\n".join(lines)
