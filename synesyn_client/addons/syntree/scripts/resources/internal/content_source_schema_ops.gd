## Purpose: Schema + validation helpers for ContentSourceResource (no IO, no signals)
extends RefCounted

const SOURCE_SCHEMA := {
	"required_fields": ["meta", "content"],
	"meta_required_fields": ["source_id", "name", "path"]
}

const STACK_SCHEMA := {
	"required_fields": ["ai_context"],
	"ai_context_fields": ["is_stack", "stack_sources"]
}

func validate_and_normalize_source_data(data: Dictionary) -> Dictionary:
	# Returns: { success: bool, error: String, data: Dictionary }
	# NOTE: This function mutates the provided dictionaries (meta/ai_context) in-place.
	if data.is_empty():
		return {"success": false, "error": "Empty source data", "data": data}

	# Check required fields
	for field in SOURCE_SCHEMA.required_fields:
		if not data.has(field):
			return {"success": false, "error": "Missing required field: %s" % field, "data": data}

	# Check meta required fields
	var meta_any: Variant = data.get("meta", {})
	if not (meta_any is Dictionary):
		return {"success": false, "error": "meta must be a Dictionary", "data": data}
	var meta: Dictionary = meta_any
	for field in SOURCE_SCHEMA.meta_required_fields:
		if not meta.has(field):
			return {"success": false, "error": "Missing required meta field: %s" % field, "data": data}

	# Ensure ai_context exists with default values
	if not meta.has("ai_context") or not (meta.get("ai_context") is Dictionary):
		meta["ai_context"] = {}
	var ai_context: Dictionary = meta.get("ai_context") as Dictionary

	if not ai_context.has("is_active"):
		ai_context["is_active"] = false
	if not ai_context.has("metaprompt"):
		ai_context["metaprompt"] = false
	if not ai_context.has("is_stack"):
		ai_context["is_stack"] = false

	# Check stack-specific fields if this is a stack
	if bool(ai_context.get("is_stack", false)):
		# Ensure required sub-fields
		for sub_field in STACK_SCHEMA.ai_context_fields:
			if not ai_context.has(sub_field):
				return {"success": false, "error": "Stack validation failed - Missing sub-field '%s' in meta.ai_context" % sub_field, "data": data}

		# Validate stack sources array exists and is not empty
		var stack_sources: Variant = ai_context.get("stack_sources", [])
		if not (stack_sources is Array) or (stack_sources as Array).is_empty():
			return {"success": false, "error": "Stack must have at least one source", "data": data}

	meta["ai_context"] = ai_context
	data["meta"] = meta
	return {"success": true, "error": "", "data": data}


