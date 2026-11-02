extends BaseMetapromptManager
class_name OpenPlayMetapromptManager

## Open Play: immersion-first Story Catalyst prompts for narrative fun and
## roleplay. No didactic meters, civic agendas, or cultural-matrix obligations.
## Genre tags from the scenario seed tone only.

const StoryScenarioContractScript = preload(
	"res://ScenSyn/session_types/story_catalyst/open_play/story_scenario_contract.gd"
)


func _ready() -> void:
	super._ready()
	game_theme = "Open Play"


func generate_game_session_metaprompt(
	scenario: Dictionary, characters: Array, player_character: Dictionary
) -> String:
	var player_name: String = String(player_character.get("name", "Player"))
	var prompt: String = get_core_narrative_rules(player_name)
	prompt += """

### Open Play responsibilities
- Prioritize immersion, character voice, dramatic tension, and player agency.
- Treat the scenario objective as a dramatic goal, not a lesson or policy outcome.
- Stay in character; do not narrate or decide actions for player-controlled characters.
- Do not inject sustainability metrics, civic curricula, or cultural-matrix obligations.
- Use genre tags only as tone and trope guidance.

"""
	var tags_any: Variant = scenario.get("tags", [])
	var tags: Array[String] = []
	if typeof(tags_any) == TYPE_ARRAY:
		for tag_any: Variant in tags_any:
			var tag_text: String = String(tag_any).strip_edges()
			if not tag_text.is_empty():
				tags.append(tag_text)
	var tags_fragment: String = StoryScenarioContractScript.tags_prompt_fragment(tags)
	if not tags_fragment.is_empty():
		prompt += tags_fragment + "\n\n"
	prompt += get_scenario_context(scenario, characters, player_character)
	var twists_any: Variant = scenario.get("plot_twists", [])
	if typeof(twists_any) == TYPE_ARRAY and not (twists_any as Array).is_empty():
		prompt += "\nOptional plot-twist fuel (use sparingly if the scene calls for it):\n"
		for twist_any: Variant in twists_any:
			var twist_text: String = String(twist_any).strip_edges()
			if not twist_text.is_empty():
				prompt += "- " + twist_text + "\n"
	return prompt


func generate_ai_character_metaprompt(_scenario: Dictionary, _ai_characters: Array) -> String:
	return (
		"Respond in vivid character voice. Protect player agency. "
		+ "Advance drama through dialogue and choice, without didactic agendas."
	)


func get_metaprompt(category: String, index: int) -> String:
	if category == "scenario_creation" and index == 0:
		var additional_customization: String = get_additional_customization()
		var theme_text: String = game_theme if not game_theme.is_empty() else "Open Play"
		return """
		Create a new scenario for Open Play — narrative fun and roleplay with no teaching agenda.
		Tone/register: {game_theme}. {additional_customization}
		Begin your response with a unique and engaging scenario name on its own line, prefixed with 'Scenario Name:'.
		Then provide a brief description of the setting and premise.
		Do not start with filler words.

		Scenario Name: The Crystal Caverns of Zor
		In the depths of an alien world, explorers discover a vast network of crystal caves hiding an ancient civilization's secrets...

		Now create a new and original scenario following this format.
		""".format({
			"game_theme": theme_text,
			"additional_customization": additional_customization,
		})
	if category == "scenario_creation" and index == scenario_steps.find("characters"):
		return """
		Generate 4 unique characters for this Open Play story. For each character, provide:
		Name: [Character Name]
		Role: [Short dramatic role]
		Description: [Brief character description]

		Please ensure each character is separated by a blank line.
		"""
	if category == "scenario_creation" and index == scenario_steps.find("plot_twists"):
		return """
		Based on the scenario you've created, provide 3-5 potential plot twists.
		Each should be unexpected and impactful. Present them as a numbered list:

		1. [First plot twist]
		2. [Second plot twist]
		3. [Third plot twist]
		"""
	return super.get_metaprompt(category, index)


func should_include_voice_guidance() -> bool:
	return true


func should_include_backgrounds() -> bool:
	return true
