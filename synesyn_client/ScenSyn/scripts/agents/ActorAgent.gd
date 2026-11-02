# ActorAgent.gd
extends Node
class_name ActorAgent

const DirectorAgentScript = preload("res://ScenSyn/scripts/agents/DirectorAgent.gd")

# Dependencies
var conversation_manager

## How far over its word ceiling a line may run before it is worth another model call.
## A reprompt doubles the wait for that line, so a line only a few words long is cut at a
## sentence boundary instead; one that runs well over has an unfinished thought in it that
## cutting would lose, so that one goes back for a shorter take.
const REPROMPT_TOLERANCE: float = 0.25

## Reasoning budget for the repair call, on providers that accept one (currently xAI).
## Repair is mechanical — say the line already written, shorter — but Grok's default
## budget treated it as a fresh creative problem and spent longer on it than on the line
## it was fixing (10.3s against 3.0s in measurement, for an equally clean result). The
## first take is left on the provider's default, since that one is the writing.
## Set to "" to hand the repair back to the provider's default too. See ADR 0028.
const REPAIR_REASONING_EFFORT: String = "low"

## Senders and repair-prompt headings that are not in any cast but can still turn up as a
## "Name:" prefix on a line. Stripping them keeps a repair call that echoed its own heading
## ("**Corrected Line:** ...") from being rejected as meta-commentary after `**` is removed.
const SYSTEM_PREFIX_NAMES: Array[String] = [
	"Narrator",
	"Facilitator",
	"Session Record",
	"Corrected Line",
	"Rewritten Line",
	"Final Line",
]

# --- Public API ---

func initialize(p_conversation_manager, _p_metaprompt_manager):
	conversation_manager = p_conversation_manager
	print("[ActorAgent] Initialized.")

func generate_dialogue_line(cue_card: Dictionary):
	var character_name = cue_card.get("character_name", "Character")
	var prompt = _build_cue_card_prompt(cue_card)

	# Per-scenario actor model override. Set by DirectorAgent from the scenario's
	# system_config["actor_model"] and stamped onto every cue card. Empty string
	# means "use the global current model" (default, legacy behaviour).
	# To route Actor calls for a scenario, add to its [SYSTEM_CONFIG]:
	#   actor_model: <model-id>
	var actor_model_override: String = String(cue_card.get("actor_model_override", "")).strip_edges()
	var thread_name = _scoped_thread_name("actor_" + character_name.to_lower())
	# Scenario-set reasoning budget for the spoken line, stamped onto the cue card by the
	# Director. Empty (the default) leaves the budget to the provider.
	var line_effort: String = DirectorAgentScript.normalized_reasoning_effort(
		String(cue_card.get("actor_reasoning_effort", ""))
	)
	var line_settings: Dictionary = {}
	if not line_effort.is_empty():
		line_settings["reasoning_effort"] = line_effort
	var response = await conversation_manager.chat(prompt, thread_name, actor_model_override, line_settings)

	var line = "..."
	if response and response.success:
		line = _clean_actor_line(String(response.response), cue_card)

	# Soft-fix: truncate to word limit at a sentence boundary (no LLM call needed)
	line = _soft_truncate(line, cue_card)

	# Hard validation: only reject for structural issues that can't be fixed locally
	if _violates_hard_rules(line, cue_card):
		print("[ActorAgent] Hard validator FAILED for %s. Reprompting for fix." % character_name)
		var fix_prompt = _build_fix_prompt(line, cue_card)
		var fix_thread = _scoped_thread_name("actor_fix_" + character_name.to_lower())
		# Fix reprompt uses the same model override so corrections stay on-budget.
		var fix_settings: Dictionary = {}
		if not REPAIR_REASONING_EFFORT.is_empty():
			fix_settings["reasoning_effort"] = REPAIR_REASONING_EFFORT
		var fix_response = await conversation_manager.chat(fix_prompt, fix_thread, actor_model_override, fix_settings)
		if fix_response and fix_response.success:
			line = _clean_actor_line(String(fix_response.response), cue_card)
			line = _soft_truncate(line, cue_card)
			if _violates_hard_rules(line, cue_card):
				line = _salvage_or_drop(line, cue_card, character_name)
	
	return line


# --- Private Methods ---

func _build_cue_card_prompt(cue_card: Dictionary) -> String:
	var character_name = cue_card.get("character_name", "Character")
	var scene_aim = cue_card.get("scene_aim", "continue the conversation.")
	var persona = cue_card.get("persona", "A character in a scene.")
	var cue = cue_card.get("cue", {}).get("text", "Say something relevant.")
	var full_log = cue_card.get("full_log_for_context", [])
	var recent_dialogue = _build_recent_context(full_log, 4)
	var addressee = cue_card.get("addressee", "")
	var delivery_rules = cue_card.get("delivery_rules", {})
	var delivery_note = delivery_rules.get("delivery_note", "")
	var external_turn_context: String = str(cue_card.get("external_turn_context", "")).strip_edges()
	var turn_obligation: String = str(cue_card.get("turn_obligation", "")).strip_edges()
	var scenario_guardrails: Dictionary = cue_card.get("scenario_guardrails", {})
	
	var scene_partners_text = ""
	var scene_partners = cue_card.get("scene_partners", [])
	if not scene_partners.is_empty():
		scene_partners_text += "\n**YOUR SCENE PARTNERS:**\n"
		for partner in scene_partners:
			scene_partners_text += "- **%s:** %s\n" % [partner.name, partner.persona]

	var addressing_instruction = ""
	if not addressee.is_empty():
		var aliases_any: Variant = delivery_rules.get("address_aliases", [])
		if typeof(aliases_any) == TYPE_ARRAY and (aliases_any as Array).size() > 1:
			addressing_instruction = "\n**ADDRESS YOUR LINE TO:** %s (may be addressed as %s)\n" % [addressee, " or ".join(aliases_any as Array)]
		else:
			addressing_instruction = "\n**ADDRESS YOUR LINE TO:** %s\n" % addressee
	var limits: Dictionary = _get_word_limits(cue_card)
	var word_limit: int = int(limits.get("limit", 120))
	if word_limit > 0:
		addressing_instruction += "**WORD LIMIT:** Keep your line to at most %d words.\n" % word_limit

	var prime_objective_instruction = "\n**PRIME OBJECTIVE:** Your response MUST serve this scene's core narrative goal: '%s'. This is your most important goal.\n" % scene_aim
	var external_context_block := ""
	if external_turn_context != "":
		external_context_block = "\n**FRESH SCENARIO TURN CONTEXT:**\n%s\n" % external_turn_context
	var weaver_context: String = str(cue_card.get("weaver_context", "")).strip_edges()
	var weaver_context_block := ""
	if weaver_context != "":
		weaver_context_block = (
			"\n**WORDS JUST SPOKEN IN THIS CLUSTER — your scene-partners have already responded "
			+ "to this divination event. Weave from what they said; do not re-introduce it as new:\n"
			+ weaver_context + "\n"
		)
	var obligation_block := ""
	if turn_obligation != "":
		obligation_block = "\n**YOUR CURRENT TURN OBLIGATION:** %s\n" % turn_obligation
	var guardrails_block := _build_guardrails_block(scenario_guardrails)

	var thought_process_instruction = ""
	if not delivery_note.is_empty():
		thought_process_instruction = """
**INTERNAL THOUGHT PROCESS (Follow these steps, but only output the final line):**
1.  **Draft:** First, write a fluent, natural line that follows the director's instruction and the PRIME OBJECTIVE.
2.  **Ground:** If fresh scenario turn context is present, anchor the line in it concretely.
3.  **Stylize:** Now, take your draft and strictly apply this stylistic rule: '%s'.
4.  **Final Line:** The result of step 3 is your final answer.
""" % delivery_note
	else:
		thought_process_instruction = """
**INTERNAL THOUGHT PROCESS (Follow this step, but only output the final line):**
1.  **Formulate:** Consider the PRIME OBJECTIVE, your persona, the director's instruction, and any fresh scenario turn context to formulate your line.
"""

	var prompt = """
You are an actor performing in a serious, thought-provoking role play scenario. Your performance must be subtle, grounded, and entirely in character. Do not use stage directions, quotation marks, or character name prefixes.
%s
**THE SCENE:**
You are **%s**. Your core persona is:
%s
%s
%s
%s
%s
%s
**RECENT DIALOGUE:**
%s
%s
**YOUR INSTRUCTION:**
Your director has given you this instruction for your next line:
**"%s"**
%s
Now, deliver your final line as **%s**.
""" % [prime_objective_instruction, character_name, persona, scene_partners_text, external_context_block, obligation_block, weaver_context_block, guardrails_block, recent_dialogue, addressing_instruction, cue, thought_process_instruction, character_name]
	
	return prompt

func _build_fix_prompt(bad_line: String, cue_card: Dictionary) -> String:
	var character_name = cue_card.get("character_name", "Character")
	var cue = cue_card.get("cue", {}).get("text", "Say something relevant.")
	var delivery_rules = cue_card.get("delivery_rules", {})
	var delivery_note = delivery_rules.get("delivery_note", "")
	var external_turn_context: String = str(cue_card.get("external_turn_context", "")).strip_edges()
	var turn_obligation: String = str(cue_card.get("turn_obligation", "")).strip_edges()
	var scenario_guardrails: Dictionary = cue_card.get("scenario_guardrails", {})

	var limits: Dictionary = _get_word_limits(cue_card)
	var word_limit: int = int(limits.get("limit", 120))
	var address_rule_line := ""
	var required_addressee: String = str(delivery_rules.get("address_to", "")).strip_edges()
	if not required_addressee.is_empty():
		var aliases_any: Variant = delivery_rules.get("address_aliases", [])
		if typeof(aliases_any) == TYPE_ARRAY and (aliases_any as Array).size() > 1:
			address_rule_line = "\n- Directly address %s (using %s)." % [required_addressee, " or ".join(aliases_any as Array)]
		else:
			address_rule_line = "\n- Directly address %s by name." % required_addressee

	# Aggressive correction for characters with a specific delivery note
	if not delivery_note.is_empty():
		var guardrails_addendum := ""
		var anchor_terms: Array = scenario_guardrails.get("required_anchor_terms", [])
		if bool(scenario_guardrails.get("require_anchor_term", false)) and not anchor_terms.is_empty():
			guardrails_addendum = "\n**Additional constraint:** The line must also reference at least one of these terms: %s" % ", ".join(anchor_terms)
		return ("An actor failed to follow a specific performance note. Rewrite their line to strictly follow the rule (at most %d words).%s%s\n\n**Rule:** '%s'\n**Actor's Bad Line:** \"%s\"\n\nOutput only the corrected in-character dialogue line, with no prefix, label, or quotation marks." % [word_limit, guardrails_addendum, address_rule_line, delivery_note, bad_line])


	# Specific fix for the "Before we..." banned opener
	var txt_lower_fix := bad_line.strip_edges().to_lower()
	var fix_sentence_end: int = txt_lower_fix.find(".")
	var fix_before_we_idx: int = txt_lower_fix.find("before we ")
	var fix_before_i_idx: int = txt_lower_fix.find("before i ")
	var fix_has_before_we_stall: bool = fix_before_we_idx >= 0 and (fix_sentence_end == -1 or fix_before_we_idx <= fix_sentence_end + 2)
	var fix_has_before_i_stall: bool = fix_before_i_idx >= 0 and (fix_sentence_end == -1 or fix_before_i_idx <= fix_sentence_end + 2)
	if fix_has_before_we_stall or fix_has_before_i_stall:
		return (
			"An actor opened their line with a banned stalling preamble (\"Before we...\").\n\n"
			+ "**Character:** %s\n" % character_name
			+ "**Director's Instruction:** \"%s\"\n" % cue
			+ "**Actor's Bad Line:** \"%s\"\n\n" % bad_line
			+ "Rewrite this line so it opens with the character's SUBSTANTIVE POINT directly — "
			+ "the concern, position, or observation they want to make — without framing it as "
			+ "a prerequisite that must be resolved before the group can proceed.\n"
			+ "Do not begin with \"Before we\", \"Before I\", or any similar construction.\n"
			+ "Keep the line to at most %d words.%s\n" % [word_limit, address_rule_line]
			+ "Output only the corrected in-character line, with no prefix, label, or formatting."
		)

	var prompt = """
An actor delivered a line that violated the rules.

**Character:** %s
**Director's Instruction:** "%s"
**Actor's Bad Line:** "%s"
**Fresh Scenario Turn Context:** %s
**Current Turn Obligation:** %s
**Scenario Guardrails:** %s

The line was bad because it likely violated one or more of these rules:
- Keep the line to at most %d words.%s
- No quotation marks, character-name prefixes, or stage directions.
- No meta commentary about editing, rewriting, formatting, or what was removed.
- If the character is not technical, do not invent gauges, scores, percentages, coordinates, or numerical readings.
- Do not invent symbolic vocabulary that is not supported by the current scenario turn context.
- Stay grounded in the current scenario turn context and obey the current turn obligation.

Rewrite the line to be a clean, direct piece of dialogue that strictly follows the director's instruction, with no extra formatting.
If there are invented numbers or invented symbolic terms, remove them rather than replacing them with new ones.
Output only the corrected in-character dialogue line, with no label, prefix, or quotation marks.
""" % [character_name, cue, bad_line, external_turn_context if external_turn_context != "" else "None provided.", turn_obligation if turn_obligation != "" else "None provided.", _guardrails_summary(scenario_guardrails), word_limit, address_rule_line]
	return prompt

func _get_word_limits(cue_card: Dictionary) -> Dictionary:
	var guardrails: Dictionary = cue_card.get("scenario_guardrails", {})
	var word_count_hint: String = cue_card.get("cue", {}).get("word_count_hint", "brief")
	var default_brief: int = 120
	var default_full: int = 150
	var brief_limit: int = int(guardrails.get("max_words_brief", default_brief))
	var full_limit: int = int(guardrails.get("max_words_default", default_full))
	var limit: int = brief_limit if word_count_hint == "brief" else full_limit
	var should_reprompt: bool = bool(guardrails.get("reprompt_on_excess", false))
	var threshold: int = int(ceil(float(limit) * (1.0 + REPROMPT_TOLERANCE)))
	return {
		"limit": limit,
		"reprompt_on_excess": should_reprompt,
		"reprompt_threshold": threshold,
	}

## Last resort after a fix reprompt still fails. Dropping the line costs the scene its
## turn, and a silent character reads as a broken session rather than a rejected line —
## for a scenario with a tight word ceiling and `reprompt_on_excess: true`, a verbose
## model can silence every actor. Length is the one violation repairable without
## another call, so a still-too-long line is cut to the ceiling and kept. Anything else
## (stage directions, meta-commentary, a missing anchor) is not locally repairable and
## still yields "...", which the caller reports as a failed line.
func _salvage_or_drop(line: String, cue_card: Dictionary, character_name: String) -> String:
	var salvaged: String = _truncate_to_limit(line, cue_card)
	if not salvaged.is_empty() and not _violates_hard_rules(salvaged, cue_card):
		print(
			"[ActorAgent] Fix still over the word ceiling for %s — truncated and kept."
			% character_name
		)
		return salvaged
	print("[ActorAgent] Hard validator FAILED again for %s after fix." % character_name)
	return "..."

func _soft_truncate(line: String, cue_card: Dictionary) -> String:
	var limits: Dictionary = _get_word_limits(cue_card)
	if not bool(limits["reprompt_on_excess"]):
		return _truncate_to_limit(line, cue_card)
	if line.strip_edges().split(" ", false).size() > int(limits["reprompt_threshold"]):
		# Far enough over that the scenario would rather pay for a shorter take.
		return line.strip_edges()
	return _truncate_to_limit(line, cue_card)

func _truncate_to_limit(line: String, cue_card: Dictionary) -> String:
	var txt := line.strip_edges()
	if txt.is_empty():
		return txt
	var limits: Dictionary = _get_word_limits(cue_card)
	var max_words: int = limits["limit"]
	var words: PackedStringArray = txt.split(" ", false)
	if words.size() <= max_words:
		return txt
	var truncated: String = " ".join(words.slice(0, max_words))
	var last_period: int = truncated.rfind(".")
	var last_question: int = truncated.rfind("?")
	var last_exclaim: int = truncated.rfind("!")
	var best_cut: int = maxi(last_period, maxi(last_question, last_exclaim))
	if best_cut > int(truncated.length() * 0.4):
		truncated = truncated.substr(0, best_cut + 1)
	else:
		truncated = truncated + "."
	print("[ActorAgent] Soft-truncated from %d to ~%d words." % [words.size(), truncated.split(" ", false).size()])
	return truncated

## Names that can legitimately appear as a "Name:" prefix on a generated line: the speaker's
## own, whoever they address, their scene partners', and the system voices. All of them read
## as attribution rather than dialogue, and all are removable without a model call.
func _known_prefix_names(cue_card: Dictionary) -> Array[String]:
	var names: Array[String] = []
	for key: String in ["character_name", "addressee"]:
		var value: String = String(cue_card.get(key, "")).strip_edges()
		if not value.is_empty():
			names.append(value)
	var partners_any: Variant = cue_card.get("scene_partners", [])
	if typeof(partners_any) == TYPE_ARRAY:
		for partner_any: Variant in (partners_any as Array):
			if typeof(partner_any) != TYPE_DICTIONARY:
				continue
			var partner: String = String((partner_any as Dictionary).get("name", "")).strip_edges()
			if not partner.is_empty():
				names.append(partner)
	names.append_array(SYSTEM_PREFIX_NAMES)
	return names

func _clean_actor_line(raw_line: String, cue_card: Dictionary) -> String:
	var line := raw_line.strip_edges()
	if line.begins_with("\"") and line.ends_with("\"") and line.length() >= 2:
		line = line.substr(1, line.length() - 2).strip_edges()
	line = _strip_name_prefix(line, cue_card)
	line = _strip_stage_directions(line)
	# Run prefix + quote stripping again after stage-direction removal so bolded
	# prefixes like "**Pozzo:** ..." or "**Corrected Line:** \"...\"" are cleaned.
	line = _strip_name_prefix(line, cue_card)
	if line.begins_with("\"") and line.ends_with("\"") and line.length() >= 2:
		line = line.substr(1, line.length() - 2).strip_edges()
	return line

## Removes a leading attribution. A partner's name in front of the line means the model wrote
## the line under the wrong heading rather than in the wrong voice, so the line is kept and
## the strip is logged: an odd attribution is easier to read in the log than a missing speaker.
func _strip_name_prefix(line: String, cue_card: Dictionary) -> String:
	var txt: String = line.strip_edges()
	var colon_pos: int = txt.find(":")
	if colon_pos <= 0:
		return txt
	var before_colon: String = txt.substr(0, colon_pos).replace("*", "").replace("\"", "").strip_edges().to_lower()
	for name: String in _known_prefix_names(cue_card):
		if before_colon != name.to_lower():
			continue
		if before_colon != String(cue_card.get("character_name", "")).strip_edges().to_lower():
			print("[ActorAgent] Stripped a '%s:' attribution from %s's line." % [
				name, String(cue_card.get("character_name", ""))
			])
		return txt.substr(colon_pos + 1).lstrip("*\" ").strip_edges()
	return txt

## Removes a bracketed or asterisked aside — "(leans in)", "*a pause*" — which is an actor
## describing themselves rather than speaking. Like a word ceiling, it is repairable without a
## model call: the words of the line are already there. Returns the line untouched if nothing
## would be left, so the validator can still reject a line that is only a stage direction.
func _strip_stage_directions(line: String) -> String:
	var txt: String = line.strip_edges()
	if not (txt.contains("*") or txt.contains("(") or txt.contains("[")):
		return txt
	var stripped: String = txt
	for pattern: String in ["\\*[^*]*\\*", "\\([^)]*\\)", "\\[[^\\]]*\\]"]:
		var expression := RegEx.new()
		if expression.compile(pattern) != OK:
			continue
		stripped = expression.sub(stripped, "", true)
	var whitespace := RegEx.new()
	if whitespace.compile("\\s{2,}") == OK:
		stripped = whitespace.sub(stripped, " ", true)
	var orphan_space := RegEx.new()
	if orphan_space.compile("\\s+([,.?!;:])") == OK:
		stripped = orphan_space.sub(stripped, "$1", true)
	stripped = stripped.strip_edges()
	if stripped.is_empty():
		return txt
	if stripped != txt:
		print("[ActorAgent] Stripped a stage direction from the line.")
	return stripped

func _violates_hard_rules(line: String, cue_card: Dictionary) -> bool:
	var txt := line.strip_edges()
	if txt.is_empty():
		return true

	if txt.begins_with("\"") or txt.ends_with("\""):
		print("[Validator] FAILED: Wrapped in quotes.")
		return true

	# Reject "Before we/I..." stalling gambits in the opening sentence, even if
	# preceded by a greeting ("Good morning... Before we...").
	var txt_opener := txt.to_lower()
	var first_sentence_end: int = txt_opener.find(".")
	var before_we_idx: int = txt_opener.find("before we ")
	var before_i_idx: int = txt_opener.find("before i ")
	var has_before_we_stall: bool = before_we_idx >= 0 and (first_sentence_end == -1 or before_we_idx <= first_sentence_end + 2)
	var has_before_i_stall: bool = before_i_idx >= 0 and (first_sentence_end == -1 or before_i_idx <= first_sentence_end + 2)
	if has_before_we_stall or has_before_i_stall:
		print("[Validator] FAILED: Banned 'Before we...' opening gambit.")
		return true
	# Only a name in front of the colon is an attribution. This used to reject any colon in
	# the first forty characters, which is a shape spoken dialogue takes constantly — "Listen:
	# the river does not argue" — and the repair call could not fix a line that was not broken,
	# so every speaker of a turn could be rejected in turn and the scene fell back to one line.
	if _strip_name_prefix(txt, cue_card) != txt:
		print("[Validator] FAILED: Speaker attribution left in front of the line.")
		return true

	if txt.contains("*") or txt.contains("(") or txt.contains("["):
		print("[Validator] FAILED: Contained stage directions.")
		return true

	var txt_lower := txt.to_lower()
	if txt_lower.find("i removed") != -1 or txt_lower.find("quotation marks") != -1 or txt_lower.find("character name prefix") != -1 or txt_lower.find("rephrased the sentence") != -1 or txt_lower.find("corrected line") != -1:
		print("[Validator] FAILED: Contained meta-editing commentary.")
		return true

	var limits: Dictionary = _get_word_limits(cue_card)
	if bool(limits["reprompt_on_excess"]):
		var word_count: int = txt.split(" ", false).size()
		if word_count > int(limits["reprompt_threshold"]):
			print("[Validator] FAILED: Exceeded scenario word limit. Limit: %d (reprompt over %d), Actual: %d" % [limits["limit"], limits["reprompt_threshold"], word_count])
			return true

	var delivery_rules: Dictionary = cue_card.get("delivery_rules", {})
	var require_full_sentence: bool = delivery_rules.get("require_full_sentence", false)
	var addressee: String = delivery_rules.get("address_to", "")
	var scenario_guardrails: Dictionary = cue_card.get("scenario_guardrails", {})

	if require_full_sentence:
		if not txt.ends_with(".") and not txt.ends_with("?") and not txt.ends_with("!"):
			print("[Validator] FAILED: Delivery rule requires a full sentence.")
			return true

	if not addressee.is_empty():
		var addressed := txt.to_lower().contains(addressee.to_lower())
		var aliases_any: Variant = delivery_rules.get("address_aliases", [])
		if not addressed and typeof(aliases_any) == TYPE_ARRAY:
			for alias_any in (aliases_any as Array):
				var alias_str := String(alias_any).strip_edges().to_lower()
				if not alias_str.is_empty() and txt.to_lower().contains(alias_str):
					addressed = true
					break
		if not addressed:
			print("[Validator] FAILED: Line must address '%s'." % addressee)
			return true

	if _violates_scenario_guardrails(txt, scenario_guardrails):
		return true

	return false

func _build_guardrails_block(scenario_guardrails: Dictionary) -> String:
	if scenario_guardrails.is_empty():
		return ""
	var lines: Array[String] = []
	var required_anchor_terms: Array = scenario_guardrails.get("required_anchor_terms", [])
	var allowed_bead_names: Array = scenario_guardrails.get("allowed_bead_names", [])
	if bool(scenario_guardrails.get("require_anchor_term", false)) and not required_anchor_terms.is_empty():
		lines.append("- Your line must anchor itself in at least one of these current-turn terms: %s" % ", ".join(required_anchor_terms))
	if bool(scenario_guardrails.get("enforce_known_bead_names", false)) and not allowed_bead_names.is_empty():
		lines.append("- If you mention beads, only use these bead names: %s" % ", ".join(allowed_bead_names))
	if lines.is_empty():
		return ""
	return "\n**SCENARIO GUARDRAILS:**\n%s\n" % "\n".join(lines)

func _guardrails_summary(scenario_guardrails: Dictionary) -> String:
	if scenario_guardrails.is_empty():
		return "None."
	var parts: Array[String] = []
	var anchors: Array = scenario_guardrails.get("required_anchor_terms", [])
	if bool(scenario_guardrails.get("require_anchor_term", false)) and not anchors.is_empty():
		parts.append("must mention at least one anchor: %s" % ", ".join(anchors))
	var allowed_beads: Array = scenario_guardrails.get("allowed_bead_names", [])
	if bool(scenario_guardrails.get("enforce_known_bead_names", false)) and not allowed_beads.is_empty():
		parts.append("only valid bead names: %s" % ", ".join(allowed_beads))
	return "; ".join(parts) if not parts.is_empty() else "None."

func _violates_scenario_guardrails(txt: String, scenario_guardrails: Dictionary) -> bool:
	if scenario_guardrails.is_empty():
		return false
	var txt_lower := txt.to_lower()
	var required_anchor_terms: Array = scenario_guardrails.get("required_anchor_terms", [])
	if bool(scenario_guardrails.get("require_anchor_term", false)) and not required_anchor_terms.is_empty():
		var has_anchor := false
		for term_any in required_anchor_terms:
			var term: String = str(term_any).strip_edges()
			if term != "" and txt_lower.find(term.to_lower()) != -1:
				has_anchor = true
				break
		if not has_anchor:
			print("[Validator] FAILED: Missing required current-turn anchor.")
			return true
	if bool(scenario_guardrails.get("enforce_known_bead_names", false)):
		var allowed_beads: Array = scenario_guardrails.get("allowed_bead_names", [])
		if _contains_unknown_bead_reference(txt, allowed_beads):
			print("[Validator] FAILED: Contained unknown bead reference.")
			return true
	return false

func _contains_unknown_bead_reference(txt: String, allowed_beads: Array) -> bool:
	if allowed_beads.is_empty():
		return false
	var allowed_lower: Array[String] = []
	for bead_any in allowed_beads:
		allowed_lower.append(str(bead_any).to_lower())
	var regex := RegEx.new()
	regex.compile("\\b([A-Za-z]+)\\s+beads?\\b")
	var matches: Array = regex.search_all(txt)
	for match_any in matches:
		var match: RegExMatch = match_any
		if match.get_group_count() >= 2:
			var bead_name := str(match.get_string(1)).to_lower()
			if not allowed_lower.has(bead_name):
				return true
	return false

func _build_recent_context(story_log: Array, line_count: int) -> String:
	var lines = []
	var start_index = max(0, story_log.size() - line_count)
	for i in range(start_index, story_log.size()):
		var entry = story_log[i]
		var sender = entry.get("sender", "Unknown")
		if sender == "Narrator": continue
		lines.append("%s: %s" % [sender, entry.get("message", "")])
	
	if lines.is_empty():
		return "The scene has just begun."
		
	return "\n".join(lines)

func _scoped_thread_name(suffix: String) -> String:
	var cleaned_suffix := suffix.replace(" ", "_")
	var ts := str(Time.get_ticks_msec())
	if conversation_manager and conversation_manager.has_method("get_current_thread"):
		var base_thread := str(conversation_manager.get_current_thread()).strip_edges()
		if base_thread != "":
			return base_thread + "__" + cleaned_suffix + "_" + ts
	return cleaned_suffix + "_" + ts
