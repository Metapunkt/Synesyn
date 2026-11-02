extends Node
class_name BaseMetapromptManager

## BaseMetapromptManager - Core metaprompt functionality shared across all themes
##
## This base class provides theme-agnostic metaprompt generation and management.
## Theme-specific managers should extend this class and implement theme-specific
## methods for keywords, concepts, and domain-specific prompting logic.

# Required imports for dynamic background system (use alias to avoid class name clash)
const BackgroundManagerScript = preload("res://addons/story_stage/scripts/story_stage_background_controller.gd")

# Core configuration
var scenario_steps = ["setting", "objective", "characters", "plot_twists"]
var game_theme: String = "Interactive Narrative"  # Default theme
var feedback_manager: FeedbackManager 
var feedback_adjustments: String = ""

# Generic metaprompt library (theme-agnostic)
var metaprompt_library = {
	"scenario_creation": [
		"Let's create a new scenario. What's the basic premise you have in mind?",
		"Can you describe the setting in more detail?",
		"Who are the main characters in this scenario?",
		"What's the main objective or quest for the player?",
		"What potential challenges or plot twists might the player face?",
		"Is there any additional element you'd like to add to make the scenario more interesting?"
	],
	"character_interaction": [
		"Describe your character's background and personality.",
		"What motivates your character?",
		"How does your character interact with others in the scenario?",
		"What are your character's strengths and weaknesses?"
	],
	"plot_twists": [
		"Introduce an unexpected event that changes the course of the story.",
		"Reveal a hidden secret about one of the characters.",
		"Create a moral dilemma for the player to navigate."
	]
}

# Narrative phase instructions (universal across themes)
var _narrative_phase_instructions = {
	"setup": "NARRATIVE PHASE: SETUP - Introduce setting, establish roles and stakes. Foreshadow the central conflict but do NOT resolve anything yet. Focus on character positioning and world-building.",
	"incident": "NARRATIVE PHASE: INCIDENT - Present the central crisis that forces characters to act. This is the inciting incident that disrupts the status quo and creates urgency.",
	"rising": "NARRATIVE PHASE: RISING ACTION - Escalate complications, highlight trade-offs, and showcase opposing viewpoints. Build tension through difficult choices and competing interests.",
	"climax": "NARRATIVE PHASE: CLIMAX - Drive toward a decisive choice or turning point. Tension should be at its highest. Force characters to make the critical decision that will determine the outcome.",
	"resolution": "NARRATIVE PHASE: RESOLUTION - Describe consequences of the climax decision. Reflect on whether goals were achieved and provide closure to the narrative arc.",
	"ended": "NARRATIVE PHASE: ENDED - The story has concluded. Provide final reflections, summarize outcomes, and offer closure to the experience."
}

# NEW: Absolute laws for AI behavior that override all other instructions.
const ABSOLUTE_LAWS = """
1.  **ABSOLUTE LAW: NEVER BREAK CHARACTER OR FOURTH WALL.** You are the characters. Do not talk about the characters in the third person. Do not give meta-commentary on the conversation. Do not say things like "As the antagonist, I will..." or "The analyst's eyes narrowed." You must ONLY generate first-person dialogue in the format "Character Name: Dialogue."
2.  **ABSOLUTE LAW: ONLY GENERATE DIALOGUE.** Do not generate narrator descriptions, scene settings, or instructions like "Please respond accordingly." Your entire output must be usable as direct character speech.
"""

func _ready():
	pass

## Theme hook: character-specific delivery rules for ActorAgent validation/styling.
## Default: no special constraints.
func get_character_delivery_rules(_character_name: String, _phase: String, _scenario: Dictionary) -> Dictionary:
	return {}

## Theme hook: optional extra director-side instructions per character.
## Default: none.
func get_director_instructions(_character_name: String, _phase: String, _scenario: Dictionary) -> String:
	return ""

## Set the game theme for scenario generation
func set_game_theme(theme: String):
	game_theme = theme
	
## Set additional customization for scenario generation
func set_additional_customization(customization: String):
	set_meta("additional_customization", customization)
	
## Get additional customization settings
func get_additional_customization() -> String:
	return get_meta("additional_customization", "")

## Get metaprompt from the library
## Virtual method - can be overridden by theme-specific managers
func get_metaprompt(category: String, index: int) -> String:
	if category == "scenario_creation" and index == 0:
		var additional_customization = get_additional_customization()
		return """
		Create a new scenario for a {game_theme} game. {additional_customization}
		Begin your response with a unique and engaging scenario name on its own line, prefixed with 'Scenario Name:'. 
		Then, provide a brief description of the setting and premise. 
		Do not start with 'Hmm' or any other filler words. For example:

		Scenario Name: The Crystal Caverns of Zor
		In the depths of an alien world, explorers discover a vast network of crystal caves hiding an ancient civilization's secrets...

		Now, create a new and original scenario following this format.
		 """.format({"game_theme": game_theme, "additional_customization": additional_customization})
			
	if category == "scenario_creation" and index == scenario_steps.find("characters"):
		return """
		Generate 4 unique characters for this game scenario. For each character, provide:
		Name: [Character Name]
		Description: [Brief character description]

		Please ensure each character is separated by a blank line.
		"""
	if category == "scenario_creation" and index == scenario_steps.find("plot_twists"):
		return """
		Based on the scenario you've created, please provide 3-5 potential plot twists. 
		Each plot twist should be unexpected and impactful to the story. 
		Present them in a numbered list format, like this:

		1. [First plot twist]
		2. [Second plot twist]
		3. [Third plot twist]

		Ensure each twist is concise but descriptive.
		"""
	if metaprompt_library.has(category) and index < metaprompt_library[category].size():
		return metaprompt_library[category][index]
	return ""

## Combine multiple metaprompts
func combine_metaprompts(categories: Array) -> String:
	var combined = ""
	for category in categories:
		if metaprompt_library.has(category):
			for prompt in metaprompt_library[category]:
				combined += prompt + "\n\n"
	return combined

## Get narrative phase instruction for current phase
func get_phase_instruction(phase: String) -> String:
	return _narrative_phase_instructions.get(phase, "")

## Fetch base metaprompt with character information
func fetch_base_metaprompt(scenario: Dictionary, characters: Array, player_character: Dictionary) -> String:
	var base_metaprompt = scenario.get("metaprompt", "")
	var prompt = base_metaprompt + "\n\n"

	# Append character information
	for character in characters:
		prompt += character.get("name", "") + ": " + character.get("description", "") + "\n"
	prompt += "Player Character: " + player_character.get("name", "") + " - " + player_character.get("description", "") + "\n"

	return prompt

## Generate core game session metaprompt (theme-agnostic parts)
## Virtual method - should be extended by theme-specific managers
func generate_game_session_metaprompt(scenario: Dictionary, characters: Array, player_character: Dictionary) -> String:
	var prompt = ""
	var phase = StoryState.get_current_narrative_phase() if StoryState else "setup"
	
	# LAYER 1: Core narrative rules (enhanced in Phase 1)
	prompt += get_core_narrative_rules(player_character.get("name", "Player"))
	prompt += "\n\n---\n\n"
	
	# LAYER 2: Theme creative mission (Phase 2)
	var theme_mission = get_theme_creative_mission(phase, scenario)
	if theme_mission != "":
		prompt += "## CURRENT CREATIVE MISSION\n"
		prompt += theme_mission
		prompt += "\n\n---\n\n"
	
	# LAYER 3: Scenario context (existing)
	prompt += get_scenario_context(scenario, characters, player_character)
	
	# LAYER 4: Location context for visual presentation (existing)
	var location_context = _get_location_context_for_ai()
	if location_context != "":
		prompt += "\n\n" + location_context
	
	# LAYER 5: Narrative phase instruction (existing)
	if StoryState and StoryState.has_method("get_current_narrative_phase"):
		var current_phase = StoryState.get_current_narrative_phase()
		var phase_instruction = get_phase_instruction(current_phase)
		if phase_instruction != "":
			prompt = phase_instruction + "\n\n" + prompt
	
	# LAYER 6: Real-time Chaos Injection (Umeno Engine)
	# This ensures the LLM sees the *actual* math, not hallucinated numbers.
	var chaos_engine = get_tree().get_first_node_in_group("chaos_engine")
	if chaos_engine:
		var params = chaos_engine.get_comfy_parameters()
		var chaos_context = """
## LIVE SYSTEM METRICS (DO NOT HALLUCINATE THESE NUMBERS)
The "Chaos Engine" is active. You must reference these EXACT values in your dialogue if you speak as The Diviner or The Chaos Engine.
- Umeno Alpha (Bias): %0.2f
- Umeno Beta (Stability): %0.2f
- Current Chaos Value: %0.4f
""" % [params.alpha, params.beta, params.chaos_value]
		prompt += "\n" + chaos_context + "\n"

	return prompt

## Generate metaprompt specifically for AI character responses
func generate_ai_character_metaprompt(scenario: Dictionary, ai_characters: Array) -> String:
	"""Generate a metaprompt specifically for AI character responses"""
	var prompt = ""
	
	# Add scenario context
	if scenario.has("name"):
		prompt += "SCENARIO: " + scenario.name + "\n"
	if scenario.has("objective"):
		prompt += "OBJECTIVE: " + scenario.objective + "\n\n"
	
	# Add AI character information
	if not ai_characters.is_empty():
		prompt += "YOU ARE CONTROLLING THESE AI CHARACTERS:\n"
		for character in ai_characters:
			prompt += "- " + character.get("name", "Unknown") + " (" + character.get("role", "Unknown Role") + "): "
			prompt += character.get("description", "No description available") + "\n"
		prompt += "\n"
	
	# Add core instructions
	prompt += """INSTRUCTIONS FOR AI CHARACTER RESPONSES:
1. Respond as the AI characters listed above
2. Stay true to each character's personality, role, and motivations
3. Format responses as "Character Name: [their dialogue/action]"
4. Keep responses natural and conversational
5. React appropriately to the current situation and other characters
6. Advance the narrative while staying in character

"""
	
	# Add theme-specific guidance
	var theme_keywords = get_theme_keywords(scenario)
	var theme_concepts = get_theme_concepts(scenario)
	
	if not theme_keywords.is_empty() or not theme_concepts.is_empty():
		prompt += "THEME GUIDANCE:\n"
		if not theme_keywords.is_empty():
			prompt += "Key themes to consider: " + ", ".join(theme_keywords.keys()) + "\n"
		if not theme_concepts.is_empty():
			prompt += "Important concepts: " + ", ".join(theme_concepts.keys()) + "\n"
		prompt += "\n"
	
	return prompt

## Get core narrative rules (theme-agnostic) - ENHANCED VERSION (Phase 1)
func get_core_narrative_rules(player_character_name: String) -> String:
	return """
## YOUR CREATIVE MISSION
You are a collaborative storytelling engine. Your player partner controls {player_name} absolutely.
Your canvas: AI characters, environment, and narrative momentum.
Make every exchange memorable.

## CORE PRINCIPLE: PLAYER AUTONOMY IS SACRED

What this means in practice:
- Your player partner controls {player_name}'s actions, speech, thoughts, and presence
- You can describe how AI characters PERCEIVE {player_name} (e.g., "The antagonist tenses when {player_name} speaks")
- You can describe how the ENVIRONMENT CHANGES around {player_name} (e.g., "The lights flicker")
- You CANNOT describe what {player_name} DOES, SAYS, THINKS, or FEELS

Think of it like improv theater:
- Your scene partner offers something → you build on it naturally
- You don't puppet your scene partner → you react authentically with YOUR character
- You don't narrate their inner state → you show YOUR character's response to them

Decision Test (Use this when uncertain):
- If {player_name} is the SUBJECT doing an action → Cut it (you're puppeting)
- If {player_name} is the OBJECT others perceive → Keep it (you're reacting)

Examples:
❌ "{player_name} nods and suggests a compromise" [Puppeting player]
✅ "The antagonist watches {player_name} closely, waiting for their response" [Reacting to player]

❌ "{player_name} seems convinced by the argument" [Reading player's mind]
✅ "The antagonist leans forward, hopeful. 'Are we on the same page here?'" [Showing uncertainty, asking]

## NARRATOR AS ATMOSPHERE, NOT ACTOR

The Narrator is your toolkit for creating immersion:
- Lighting designer: "The fluorescent bulbs flicker and hold their sickly yellow glow"
- Sound engineer: "Outside, a siren doppler-fades into silence"
- Time keeper: "Three hours into the discussion, coffee cups litter the table"
- Tension amplifier: "The silence stretches. No one blinks first."

The Narrator should NOT:
- Resolve conflicts between characters (that's for characters to do)
- Explain motivations (show through dialogue and action instead)
- Describe player character actions (that's player territory)

Usage Guidelines:
- Use narrator SPARINGLY: 2-3 atmospheric lines per response, maximum
- Use narrator when silence needs texture, time passes, or mood shifts
- Focus narrator on environment and shared space, not character internals

Examples:
✅ "The overhead lights hum at a frequency that makes teeth ache"
✅ "Someone's phone buzzes. Everyone ignores it. Everyone hears it."
❌ "The narrator describes how everyone feels tense about the decision"

## PRIMARY ROLE: DIALOGUE-DRIVEN COLLABORATIVE STORYTELLING
- Generate reactive, grounded dialogue for AI-controlled characters only
- Describe observable environmental events through narrator voice
- Advance story through meaningful interactions that invite player response
- Maintain thematic consistency with the chosen narrative setting
- Show character traits through dialogue and actions, never through exposition

### Additional Guidance:
- EMBODY, DON'T EXPLAIN: Reveal traits through actions/dialogue, not exposition
- DEEPEN ENGAGEMENT: Solicit player's unique perspective, ask direct questions
- MAINTAIN CONTEXT: Address specific points from immediately preceding turn
- ENSURE SELF-CONTAINED DIALOGUE: Each character's line should be complete thought
- When narrative stalls, introduce external events or have AI characters propose specific plans
- Never remove player characters from scenes without explicit player statement

Violation of player autonomy is a critical failure.
""".format({"player_name": player_character_name})

## LEGACY VERSION - Preserved for rollback (original implementation)
func get_core_narrative_rules_legacy(player_character_name: String) -> String:
	return """
**ABSOLUTE LAWS OF NARRATION - NON-NEGOTIABLE**
1.  **NEVER BREAK CHARACTER OR FOURTH WALL.** You are the characters. Never refer to yourself as an AI, a language model, or the character you are playing. For example, do not say "As the antagonist, I will say..." or "I'll respond as the analyst." All dialogue must be from the character's direct perspective.
2.  **NEVER** describe, dictate, or imply the actions, speech, or internal thoughts of any character controlled by a human player. You only describe the environment and the actions of AI characters.
3.  Human player characters are **SOVEREIGN**. Their actions are only determined by player input.
4.  **FORBIDDEN NARRATOR ACTIONS**: NEVER have the narrator describe the player character "{player_character_name}" as suggesting, mentioning, proposing, explaining, continuing, adding, responding, or taking any action whatsoever.
5.  **FORBIDDEN DESCRIPTIONS**: NEVER describe "{player_character_name}"'s eyes, face, expression, voice, thoughts, mind, or attention.
6.  **FORBIDDEN PHYSICAL DESCRIPTIONS**: NEVER describe "{player_character_name}" smiling, frowning, nodding, shaking their head, pulling out items, standing, sitting, or any physical actions.
7.  **FORBIDDEN POSSESSIVE DESCRIPTIONS**: NEVER describe "{player_character_name}'s tablet", "{player_character_name}'s device", or any possessions.
8.  **FORBIDDEN DESCRIPTIVE PHRASES**: NEVER use phrases like "{player_character_name}, a [description]" or "{player_character_name}, who [action]".
9.  **NARRATOR CONTENT RESTRICTION**: The narrator should ONLY describe environmental changes, weather, system alerts, or actions of NPCs/AI characters. Do NOT generate excessive narrator content.
10.  **NARRATOR FREQUENCY LIMIT**: Use narrator sparingly - only for scene transitions or important environmental events. Prioritize AI character dialogue over narrator descriptions.
11. If the narrative stalls, introduce **external environmental events** or have an **AI character** propose a specific plan. Do not resolve stalls by forcing a player character to act.
12. **NEVER** remove player characters from scenes. Do not describe them as leaving, departing, exiting, or being absent unless explicitly stated by the player.
13. **ALWAYS** keep player characters present and engaged in the collaborative environment.
14. **MAINTAIN CONVERSATIONAL CONTEXT**: When responding, ensure your dialogue directly addresses the character you name and the specific points made in the *immediately preceding* turn. Do not misattribute statements or address one character while responding to another. When referencing a prior message, you must accurately paraphrase its core meaning; **do not invent or misquote notifications or dialogue.**
15. **EMBODY, DON'T EXPLAIN**: Reveal character traits through actions and dialogue. **NEVER** have a character state their own backstory, profession, or motivation explicitly (e.g., instead of "As a Marxist scientist, I believe...", say "Who profits from this? That's the question we must ask.").
16. **DEEPEN PLAYER ENGAGEMENT**: Don't just address the player by name. Actively solicit their unique perspective, especially when the conversation touches on their domain of expertise. Ask them direct questions to involve them in decisions.
17. **ENSURE SELF-CONTAINED DIALOGUE**: Each character's dialogue block in a single turn must be a complete, understandable thought. Do not write dialogue that directly quotes or depends on another AI character's line from the same turn, as that line may be filtered out. Respond only to the human player or the previous state of the conversation.
Violation of these laws is a critical failure.

## PRIMARY ROLE DEFINITION
You are the narrative engine of an immersive, dialogue driven interactive story. You coordinate multiple narrative elements while maintaining strict technical and creative constraints. You will begin each session by setting the stage in **two brief sentences** which MUST describe: **THE SETTING**, **WHO IS PRESENT**, **WHY THEY ARE THERE**, **IF THEY REPRESENT A SPECIFIC GROUP**, and **WHAT IS ABOUT TO HAPPEN**.

### Core Responsibilities:
- Generate reactive, grounded dialogue for AI-controlled characters only
- Describe observable environmental events through narrator voice
- Advance story through meaningful interactions that invite player response
- Maintain thematic consistency with the chosen narrative setting
""".format({"player_character_name": player_character_name})

## Get scenario context section
func get_scenario_context(scenario: Dictionary, characters: Array, player_character: Dictionary) -> String:
	var ai_character_names = []
	var ai_character_descriptions = ""
	
	for character in characters:
		if character.get("is_ai", false):
			ai_character_names.append(character.get("name", "Unnamed"))
			ai_character_descriptions += character.get("name", "Unnamed") + ": " + character.get("description", "No description") + "\n"
	
	var plot_twists_text = ""
	var plot_twists = scenario.get("plot_twists", [])
	if not plot_twists.is_empty():
		plot_twists_text = "Potential narrative developments: " + "\n".join(plot_twists)
	
	var prompt := """

## SCENARIO CONTEXT
**Scenario**: {scenario_name}
**Objective**: {scenario_objective}
**Setting**: {scenario_description}

## CHARACTER ROSTER
**AI Characters**: {ai_character_names}
**Player Character**: {player_character_name}

## CHARACTER DETAILS
{ai_character_descriptions}
{player_character_description}

## NARRATIVE ELEMENTS
{plot_twists}

""".format({
		"scenario_name": scenario.get("name", "Unnamed Scenario"),
		"scenario_objective": scenario.get("objective", "No objective set"),
		"scenario_description": scenario.get("description", "No scenario description available"),
		"ai_character_names": ", ".join(ai_character_names),
		"player_character_name": player_character.get("name", "Player"),
		"player_character_description": player_character.get("name", "Player") + ": " + player_character.get("description", "No description available"),
		"ai_character_descriptions": ai_character_descriptions.strip_edges(),
		"plot_twists": plot_twists_text.strip_edges()
	})
	var continuity_block := _get_story_continuity_prompt_block()
	if continuity_block != "":
		prompt += "\n## SCENARIO CONTINUITY HINTS\n" + continuity_block + "\n"
	return prompt

func _get_story_continuity_prompt_block() -> String:
	if typeof(StoryState) == TYPE_NIL or not StoryState or not StoryState.has_method("get_state"):
		return ""
	var state: Dictionary = StoryState.get_state()
	var memory_any: Variant = state.get("memory_context", {})
	var memory_context: Dictionary = memory_any if typeof(memory_any) == TYPE_DICTIONARY else {}
	var cues_any: Variant = state.get("continuity_prompt_cues", {})
	var prompt_cues: Dictionary = cues_any if typeof(cues_any) == TYPE_DICTIONARY else {}
	if memory_context.is_empty() and prompt_cues.is_empty():
		return ""
	var lines: Array[String] = []

	var session_history := str(memory_context.get("session_history", "")).strip_edges()
	if not session_history.is_empty():
		lines.append("- CROSS-SESSION CONTINUITY: This is not the first session. Previous sessions established context, decisions, and unresolved matters. Acknowledge accumulated experience without repeating old material. Build on what came before.")
		lines.append("- Prior session record: " + session_history)

	var anchors_any: Variant = prompt_cues.get("continuity_anchors", [])
	var anchors: Array = anchors_any if typeof(anchors_any) == TYPE_ARRAY else []
	if not anchors.is_empty():
		lines.append("- Continuity anchors: " + ", ".join(anchors))
	var tensions_any: Variant = prompt_cues.get("latent_tensions", [])
	var tensions: Array = tensions_any if typeof(tensions_any) == TYPE_ARRAY else []
	if not tensions.is_empty():
		lines.append("- Latent tensions still in play between sessions: " + "; ".join(tensions))
	var focus_terms_any: Variant = prompt_cues.get("focus_terms", [])
	var focus_terms: Array = focus_terms_any if typeof(focus_terms_any) == TYPE_ARRAY else []
	if not focus_terms.is_empty():
		lines.append("- Focus terms: " + ", ".join(focus_terms))
	var continuity_prompt := str(prompt_cues.get("continuity_prompt", "")).strip_edges()
	if continuity_prompt != "":
		lines.append("- Continuity instruction: " + continuity_prompt)
	var phase_hint := str(state.get("suggested_narrative_phase", "")).strip_edges()
	if phase_hint != "":
		lines.append("- Narrative phase hint: %s (advisory only; do not force it if the live scene contradicts it)." % phase_hint)
	var memory_summary := str(memory_context.get("summary", "")).strip_edges()
	if memory_summary != "":
		lines.append("- Memory summary: " + memory_summary)
	var unresolved_any: Variant = state.get("unresolved_challenges", [])
	var unresolved: Array = unresolved_any if typeof(unresolved_any) == TYPE_ARRAY else []
	if not unresolved.is_empty():
		lines.append("- Unresolved challenges still in play: " + "; ".join(unresolved))
	return "\n".join(lines)

## Virtual methods to be implemented by theme-specific managers

## Get theme-specific keywords (virtual method)
func get_theme_keywords(scenario: Dictionary) -> Dictionary:
	var _scenario = scenario
	return {}

## Get theme-specific concepts (virtual method)  
func get_theme_concepts(scenario: Dictionary) -> Dictionary:
	var _scenario = scenario
	return {}

## Inject theme-specific focus into prompt (virtual method)
func inject_theme_focus(prompt: String, _intensity: String, _feedback: Dictionary) -> String:
	return prompt

## Analyze theme-specific content in message (virtual method)
func analyze_theme_content(_message: String) -> Dictionary:
	return {}

## Generate theme-specific challenge (virtual method)
func generate_theme_challenge(_metrics: Dictionary) -> String:
	return ""

## Virtual: Get theme-specific creative mission for current narrative phase (PHASE 2)
## Override this in theme managers to provide phase-specific creative direction
## that prevents narrative loops and guides dramatic arc progression
func get_theme_creative_mission(phase: String, scenario: Dictionary) -> String:
	var _phase = phase
	var _scenario = scenario
	# Base implementation: no theme-specific mission
	# Theme managers override to provide focused creative goals per phase
	print("[BaseMetapromptManager] WARNING: Base class get_theme_creative_mission called (should be overridden)")
	return ""

## Virtual: Handle external input (e.g., from sensors or other apps)
func handle_external_input(data: Dictionary) -> void:
	print("[BaseMetapromptManager] Received external input: ", data)
	# Override in theme managers to do something useful with this data

## Virtual: Generate theme-specific narrator metaprompt
func generate_narrator_metaprompt(_ai_characters: Array) -> void:
	# Base implementation does nothing
	pass

## Virtual: Get theme-specific narrator metaprompt
func get_narrator_metaprompt() -> String:
	# Base implementation returns empty string
	return ""

## NEW (Multi-Agent): Get theme-specific behavioral guidance for a character
## Override this in theme managers to provide detailed, contextual instructions
func get_character_behavioral_guidance(character_name: String, scenario: Dictionary) -> String:
	var _char_name = character_name
	var _scenario = scenario
	return ""

## Optional: Provide fresh external-turn context for prompt builders.
## Theme/scenario managers may override this when they ingest live external input.
func get_latest_turn_context_for_prompt(_character_name: String = "") -> String:
	return ""

## Optional: Provide a role-specific obligation for the current turn.
## Theme/scenario managers may override this to guide Director/Actor prompts.
func get_character_turn_obligation(_character_name: String) -> String:
	return ""

## Optional: Provide a scenario-authored system cue derived from the latest turn.
func get_latest_turn_system_cue(_phase: String = "") -> String:
	return ""

## Optional: Provide scenario-specific guardrails for the current turn.
## Example uses: required anchor terms, allowed symbolic vocabulary, bead-name constraints.
func get_current_turn_guardrails(_character_name: String = "") -> Dictionary:
	return {}

## Returns sender names that must never trigger AI character responses.
## Covers system voices (Narrator, facilitator inputs) that are not AI-character turns.
## Themes should override this and call super() to extend the list.
func get_system_senders() -> Array[String]:
	return ["Narrator", "Facilitator", "Facilitator Note"]

## Optional theme-specific rules injected into the Director's cue-generation prompt.
## Returns an empty string by default (no additional rules).
## Themes should override this to add cue discipline, move types, or register guidance
## relevant to their specific mode of play — without touching DirectorAgent.gd.
func get_director_rules() -> String:
	return ""

## --- Generic Director affordances (any theme can configure) ---
## These are first-class Director capabilities. Default returns leave the Director's
## behavior unchanged. Themes populate them to drive the Director toward their goals
## (closure for workshops, escalation for narratives, mastery checks for tutoring, etc.).

## Returns a free-form context block describing the current "directive state" of the
## scenario (e.g. closure progress, narrative tension level, mastery checkpoints).
## When non-empty, it is injected into the Director's prompt as a state-aware section
## the Director must consider when picking cues. Default: empty (no state surfaced).
func get_director_directive_state() -> String:
	return ""

## Returns optional cue-verb constraints for the Director. Recognized keys:
##   "preferred_verbs": Array[String] — verbs the Director should favor for this turn
##   "banned_verbs":    Array[String] — verbs the Director must not use this turn
##   "rationale":       String        — short explanation surfaced to the LLM
## Any subset of keys may appear. An empty Dictionary means no constraint and the
## Director uses its default verb palette.
func get_director_cue_verb_constraints() -> Dictionary:
	return {}

## Returns the maximum number of speakers allowed in the next AI batch.
## -1 means no constraint (the planner uses its normal weighted distribution).
## A theme returns 1 (for example) when convergence is detected and a single
## focused contribution is preferable to a multi-character batch.
func get_max_speakers_this_turn() -> int:
	return -1

## Notifies the metaprompt manager of the current AI-controlled character list.
## Called by ai_character_agent after refreshing ai_controlled_names.
## Themes can override this to track the cast for voting thresholds, turn planning, etc.
func set_cast(_names: Array) -> void:
	pass

## Post-generation dialogue hook called for each actor line before it enters the story log.
## Themes can scan for structured tokens (e.g. vote signals, proposal markers), strip them,
## and trigger side-effects (e.g. recording votes, registering proposals).
## Returns the cleaned dialogue string to display. Default: return unchanged.
func process_actor_dialogue(_character_name: String, dialogue: String) -> String:
	return dialogue

## Optional hook allowing a theme to trigger an AI response from a system entry.
## Default is false so shared orchestration remains conservative; themes can opt in
## for explicit control messages that are meant to cause an immediate actor turn.
func should_trigger_ai_from_system_entry(_sender: String, _message: String) -> bool:
	return false

## NEW: Generic function to get the text content of any [SECTION] from the scenario.
func get_narrative_section(section_name: String, scenario: Dictionary) -> String:
	# The parser stores these sections with lowercase keys and "_text" suffix.
	var key = section_name.to_lower() + "_text"
	return scenario.get(key, "ERROR: Section '%s' not found in scenario." % section_name)

## Get location context for AI prompts (visual presentation integration)
func _get_location_context_for_ai() -> String:
	# Try to get location context from visual integration system
	var visual_integration = get_tree().get_first_node_in_group("visual_integration")
	if visual_integration and visual_integration.has_method("get_location_context_for_ai"):
		return visual_integration.get_location_context_for_ai()
	
	# Fallback: Get directly from background manager script
	return BackgroundManagerScript.get_location_context_for_ai()

func generate_actor_cue(params: Dictionary) -> Dictionary:
	"""
	Virtual function to generate a cue card for an actor.
	Base implementation provides a generic, non-theatrical cue.
	Theme-specific managers should override this for intelligent, scenario-aware cues.
	"""
	var last_speaker = params.get("last_speaker", "the previous speaker")
	var addressee = params.get("addressee", "the group")
	
	var cue_text = "Make a new claim that builds on the last line from %s, addressing %s." % [last_speaker, addressee]
	
	return {
		"text": cue_text,
		"word_count_hint": "brief"
	}

func allows_technical_speech(character_role: String) -> bool:
	"""
	Virtual function to determine if a character's role permits technical speech (e.g., metrics, tokens).
	Base implementation is restrictive.
	"""
	var _role = character_role
	return false

# The following functions are not currently used by the Director/Actor model,
# but are kept as stubs for potential future use.
