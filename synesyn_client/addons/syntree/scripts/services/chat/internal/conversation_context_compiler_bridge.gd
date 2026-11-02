## Purpose: Shared compile path for SynTree chat submission and Context Preview.
extends RefCounted

const ContextGraphAdapterScript = preload(
	"res://addons/syntree/scripts/core/context_graph_adapter.gd"
)
const ContextCompilerScript = preload(
	"res://addons/syntree/scripts/core/context_compiler.gd"
)

var _adapter: RefCounted = ContextGraphAdapterScript.new()
var _compiler: RefCounted = ContextCompilerScript.new()


func compile_sources(
	content_state: Object,
	source_ids: Array[String],
	options: Dictionary = {}
) -> Dictionary:
	var mapped: Dictionary = _adapter.call(
		"build_from_sources",
		content_state,
		source_ids,
		str(options.get("graph_title", "SynTree Chat Context"))
	)
	if not bool(mapped.get("ok", false)):
		return mapped
	var document: Dictionary = mapped.get("document", {})
	var context_sets: Array = document.get("context_sets", [])
	if context_sets.is_empty():
		return {"ok": false, "error": "context_set_missing"}
	var context_set: Dictionary = context_sets[0]
	var context_set_override_any: Variant = options.get(
		"context_set_override",
		null
	)
	if typeof(context_set_override_any) == TYPE_DICTIONARY:
		context_set = (context_set_override_any as Dictionary).duplicate(true)
	else:
		var requested_set_id: String = str(options.get("context_set_id", ""))
		for candidate_any in context_sets:
			var candidate: Dictionary = candidate_any
			if str(candidate.get("id", "")) == requested_set_id:
				context_set = candidate
				break
	var effective_options: Dictionary = _compiler.call(
		"preset",
		str(options.get("preset", "balanced"))
	)
	for option_key in options:
		effective_options[option_key] = options[option_key]
	var compile_result: Dictionary = _compiler.call(
		"compile",
		document,
		context_set,
		effective_options
	)
	compile_result["document"] = document
	return compile_result


func wrap_for_chat(compile_result: Dictionary) -> String:
	var compiled_text: String = str(
		compile_result.get("compiled_text", "")
	).strip_edges()
	if compiled_text.is_empty():
		return ""
	return (
		"[SYNESYN_CONTEXT v2]\n"
		+ compiled_text
		+ "\n[/SYNESYN_CONTEXT]\n"
	)
