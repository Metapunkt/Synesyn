extends RefCounted
class_name ConversationModelContextPolicy


func resolve(
	ai_model_manager: Variant,
	has_referenced_sources: bool
) -> Dictionary:
	var policy: Dictionary = {
		"per_source_char_limit": 20000,
		"include_full_text": has_referenced_sources,
		"digest_chars": 1200,
		"preview_chars": 220,
	}
	if (
		not ai_model_manager
		or not ai_model_manager.has_method("get_current_model")
	):
		return policy
	var current_model_id: String = String(
		ai_model_manager.get_current_model()
	)
	var lowered_model_id: String = current_model_id.to_lower()
	if ai_model_manager.has_method("get_model_metadata"):
		var metadata: Dictionary = ai_model_manager.get_model_metadata(
			current_model_id
		)
		var context_length: int = int(
			metadata.get("context_length", 0)
		)
		if context_length > 0:
			# Reserve most of the model window for instructions, history,
			# source count variation, and output. Never exceed the existing
			# 20k/source ceiling merely because a model advertises more.
			var adaptive_char_limit: int = clampi(
				int(float(context_length) * 1.5),
				4000,
				20000
			)
			policy["per_source_char_limit"] = adaptive_char_limit
			policy["digest_chars"] = clampi(
				int(float(adaptive_char_limit) / 6.0),
				800,
				1600
			)
			policy["preview_chars"] = clampi(
				int(float(adaptive_char_limit) / 30.0),
				160,
				260
			)
	if lowered_model_id.contains("llama2"):
		policy["per_source_char_limit"] = mini(
			int(policy.get("per_source_char_limit", 5000)),
			5000
		)
		policy["digest_chars"] = 900
		policy["preview_chars"] = 180
	elif lowered_model_id.contains("phi3"):
		policy["per_source_char_limit"] = mini(
			int(policy.get("per_source_char_limit", 8000)),
			8000
		)
		policy["digest_chars"] = 1000
		policy["preview_chars"] = 200
	return policy
