extends BaseMetapromptManager

# NeutralMetapromptManager: a safe, theme-less manager used before a scenario/theme is selected.
# Provides minimal, non-directive prompts and no optional injections.

func generate_game_session_metaprompt(_scenario: Dictionary, _characters: Array, _player_character: Dictionary) -> String:
	# Minimal neutral framing to avoid biasing any domain
	return "You are coordinating a character-driven exchange. Avoid domain-specific agendas. Keep tone neutral until scenario selection."

func get_game_session_metaprompt() -> String:
	# Compatibility shim (some callers may fetch a cached metaprompt)
	return "You are coordinating a character-driven exchange. Avoid domain-specific agendas. Keep tone neutral until scenario selection."

func generate_ai_character_metaprompt(_scenario: Dictionary, _ai_characters: Array) -> String:
	# Minimal character guidance to keep output generic
	return "Respond in character voice without adding domain agendas. If uncertain, ask a brief clarifying question."

func plan_ai_turn(ai_characters: Array) -> Dictionary:
	# Simple neutral planner: 1 speaker to reduce footprint before selection
	if ai_characters.is_empty():
		return {"speakers": [], "target_total": 1}
	# Extract character names deterministically
	var first_name := String(ai_characters[0].get("name", "")).strip_edges()
	return {"speakers": [first_name], "target_total": 1}

func should_include_voice_guidance() -> bool:
	return false

func should_include_backgrounds() -> bool:
	return false

func get_character_degradation(_character_name: String) -> Dictionary:
	# Neutral: no degradation before scenario rules apply
	return {
		"advance_per_line": 0,
		"max_level": 0,
		"low_tokens": [],
		"p_low": 0.0,
		"soften_p": 0.0,
		"clip_early_ratio": 1.0,
		"anchor_tokens": []
	}
