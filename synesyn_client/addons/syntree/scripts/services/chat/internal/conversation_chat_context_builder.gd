## Purpose: Internal chat context builder for ConversationManager.chat().
extends RefCounted

const SynTreeAutoloads = preload("res://addons/syntree/scripts/autoload/syntree_autoloads.gd")
const PromptChainStore = preload("res://addons/syntree/scripts/services/prompting/prompt_chain_store.gd")
const ContextCompilerBridgeScript = preload(
	"res://addons/syntree/scripts/services/chat/internal/conversation_context_compiler_bridge.gd"
)
const BoundPromptChainContextBuilderScript = preload(
	"res://addons/syntree/scripts/services/chat/internal/bound_prompt_chain_context_builder.gd"
)
const ModelContextPolicyScript = preload(
	"res://addons/syntree/scripts/services/chat/internal/conversation_model_context_policy.gd"
)

var _compiler_bridge: RefCounted = ContextCompilerBridgeScript.new()
var _bound_prompt_context_builder: RefCounted = (
	BoundPromptChainContextBuilderScript.new()
)
var _model_context_policy: RefCounted = ModelContextPolicyScript.new()

func build_context(manager: Object, user_prompt: String, thread_id: String, ai_model_manager) -> String:
	var chain_package: Dictionary = _get_applied_prompt_chain(
		manager,
		thread_id
	)
	var context_string: String = str(chain_package.get("prefix", ""))
	var chain: Dictionary = chain_package.get("chain", {})
	var bound_context: Dictionary = await _bound_prompt_context_builder.call(
		"resolve",
		manager,
		chain,
		chain_package.get("slot_values", {}),
		context_string
	)
	if bool(bound_context.get("handled", false)):
		return str(bound_context.get("text", context_string))
	if not bool(manager.get("include_content_bus_context")):
		return context_string

	var bus := SynTreeAutoloads.content_bus()
	var content_state = bus.get_content_state_resource() if is_instance_valid(bus) else null
	print("[DEBUG_STATE] ConversationManager using ContentStateResource instance: %s" % str(content_state.get_instance_id() if is_instance_valid(content_state) else "INVALID"))
	if not is_instance_valid(content_state):
		push_warning("ConversationManager: ContentStateResource not available via ContentBus to fetch active sources.")
		return context_string

	var context_utils: Object = manager.get("_context_utils")
	var active_sources: Array = content_state.get_active_sources()
	if bool(manager.get("DEBUG_VERBOSE")):
		print("ConversationManager: Found active sources for context: ", active_sources)

	var matchable_sources: Array[String] = active_sources
	if is_instance_valid(context_utils) and context_utils.has_method("expand_active_sources_for_reference_matching"):
		matchable_sources = context_utils.call("expand_active_sources_for_reference_matching", content_state, active_sources)

	var referenced_sources: Array[String] = []
	if is_instance_valid(context_utils) and context_utils.has_method("find_referenced_active_sources"):
		referenced_sources = context_utils.call("find_referenced_active_sources", user_prompt, content_state, matchable_sources)

	var sources_for_context: Array = active_sources
	if not referenced_sources.is_empty():
		sources_for_context = referenced_sources
		if bool(manager.get("DEBUG_VERBOSE")):
			print("ConversationManager: User prompt references specific sources. Limiting context to: ", sources_for_context)

	# Expand stacks into ordered members (wiring semantics) and dedupe.
	if is_instance_valid(context_utils) and context_utils.has_method("expand_sources_for_context"):
		sources_for_context = context_utils.call("expand_sources_for_context", content_state, sources_for_context)

	if bool(manager.get("use_stfx_store_context")):
		var store_context_string: String = await manager.call("_try_build_stfx_store_context", user_prompt, content_state, sources_for_context)
		if not store_context_string.is_empty():
			if context_string.is_empty():
				context_string = store_context_string
			else:
				context_string = context_string + "\n\n" + store_context_string

	if bool(manager.get_meta("use_context_compiler", false)):
		var compiler_source_ids: Array[String] = []
		for source_id_any in sources_for_context:
			compiler_source_ids.append(str(source_id_any))
		var current_model_id: String = ""
		if ai_model_manager and ai_model_manager.has_method("get_current_model"):
			current_model_id = str(ai_model_manager.get_current_model())
		var compile_options: Dictionary = {
			"preset": str(manager.get_meta("context_compiler_preset", "balanced")),
			"max_tokens": int(manager.get_meta("context_compiler_max_tokens", 8000)),
			"model_id": current_model_id,
		}
		var compile_result: Dictionary = {}
		var frozen_result_any: Variant = manager.get_meta(
			"frozen_context_compile_result",
			{}
		)
		if (
			typeof(frozen_result_any) == TYPE_DICTIONARY
			and bool((frozen_result_any as Dictionary).get("ok", false))
		):
			compile_result = (frozen_result_any as Dictionary).duplicate(true)
		else:
			compile_result = _compiler_bridge.call(
				"compile_sources",
				content_state,
				compiler_source_ids,
				compile_options
			)
		manager.set_meta("last_context_compile_result", compile_result)
		var compiled_context: String = _compiler_bridge.call(
			"wrap_for_chat",
			compile_result
		)
		if not compiled_context.is_empty():
			if context_string.is_empty():
				return compiled_context
			return context_string + "\n\n" + compiled_context

	var model_policy: Dictionary = _resolve_model_policy(ai_model_manager, not referenced_sources.is_empty())
	var context_parts: Array = []
	var poisoned_sources: Dictionary = {} # source_id -> true when we detected HTML wrapper and scheduled refresh
	var remote_refresh_attempted: Dictionary = manager.get("_remote_refresh_attempted")

	for source_id_any in sources_for_context:
		var source_id: String = str(source_id_any)
		var source_data: Dictionary = content_state.get_source_data(source_id)
		if source_data.is_empty():
			push_warning("ConversationManager: Could not get data for active source ID: " + source_id)
			continue

		if not source_data.has("meta"):
			push_warning("ConversationManager: Missing metadata for active source ID: " + source_id)
			continue

		var source_meta: Dictionary = source_data.get("meta", {})
		var source_name: String = str(source_meta.get("name", source_id))
		var ai_context: Dictionary = source_meta.get("ai_context", {})
		var is_stack: bool = bool(ai_context.get("is_stack", false))

		_maybe_trigger_remote_refresh(
			context_utils,
			source_id,
			source_name,
			source_data,
			source_meta,
			poisoned_sources,
			remote_refresh_attempted
		)

		if is_stack:
			# Stacks should have been expanded before this loop. Skip here.
			continue

		_append_regular_source_context(
			context_utils,
			source_id,
			source_data,
			source_meta,
			source_name,
			model_policy,
			poisoned_sources,
			context_parts
		)

	if context_parts.is_empty():
		return context_string

	var joined: String = "\n\n".join(context_parts)
	joined = _build_context_header(
		context_utils,
		content_state,
		sources_for_context,
		poisoned_sources,
		int(model_policy.get("preview_chars", 220))
	) + joined + "\n[/SYNESYN_CONTEXT]\n"

	if context_string.is_empty():
		context_string = joined
	else:
		context_string = context_string + "\n\n" + joined
	if bool(manager.get("DEBUG_VERBOSE")):
		print("ConversationManager: Generated context string from memory (length: %d)" % context_string.length())
	return context_string


func _build_prompt_chain_prefix(manager: Object, thread_id: String) -> String:
	return str(_get_applied_prompt_chain(manager, thread_id).get("prefix", ""))


func _get_applied_prompt_chain(
	manager: Object,
	thread_id: String
) -> Dictionary:
	var manager_thread_scope: String = str(manager.get("thread_scope"))
	var thread_settings: Dictionary = PromptChainStore.get_thread_settings(manager_thread_scope, thread_id)
	if thread_settings.is_empty():
		return {}
	if not bool(thread_settings.get("apply_to_chat", false)):
		return {}

	var mode_id: String = str(thread_settings.get("mode", "asset")).to_lower()
	var chain: Dictionary = {}
	if mode_id == "draft":
		var draft_any: Variant = thread_settings.get("draft", {})
		if typeof(draft_any) == TYPE_DICTIONARY:
			chain = draft_any
	else:
		var asset_id: String = str(thread_settings.get("asset_id", ""))
		if not asset_id.is_empty():
			chain = PromptChainStore.get_chain(manager_thread_scope, asset_id)

	var sv_any: Variant = thread_settings.get("slot_values", {})
	var sv: Dictionary = sv_any if typeof(sv_any) == TYPE_DICTIONARY else {}
	var prefix_text: String = PromptChainStore.render_chain_text(chain, sv).strip_edges()
	return {
		"chain": chain,
		"slot_values": sv,
		"prefix": prefix_text + "\n\n" if not prefix_text.is_empty() else "",
	}

func _resolve_model_policy(ai_model_manager, has_referenced_sources: bool) -> Dictionary:
	return _model_context_policy.call(
		"resolve",
		ai_model_manager,
		has_referenced_sources
	)

func _maybe_trigger_remote_refresh(
	context_utils: Object,
	source_id: String,
	source_name: String,
	source_data: Dictionary,
	source_meta: Dictionary,
	poisoned_sources: Dictionary,
	remote_refresh_attempted: Dictionary
) -> void:
	var origin: String = str(source_meta.get("source_origin", "file"))
	if origin != "remote":
		return

	var extracted_now: String = ""
	if is_instance_valid(context_utils) and context_utils.has_method("extract_text_from_source_data"):
		extracted_now = str(context_utils.call("extract_text_from_source_data", source_data))
	var is_html: bool = false
	if is_instance_valid(context_utils) and context_utils.has_method("looks_like_html"):
		is_html = bool(context_utils.call("looks_like_html", extracted_now))
	if not is_html:
		return

	poisoned_sources[source_id] = true
	if bool(remote_refresh_attempted.get(source_id, false)):
		return

	remote_refresh_attempted[source_id] = true
	var url: String = str(source_meta.get("path", "")).strip_edges()
	var refresh_bus := SynTreeAutoloads.content_bus()
	if not url.is_empty() and is_instance_valid(refresh_bus) and refresh_bus.has_method("trigger_remote_source_refresh"):
		print("ConversationManager: Remote source '%s' looks like HTML. Triggering background refresh: %s" % [source_name, url])
		refresh_bus.call_deferred("trigger_remote_source_refresh", source_id, url)
	else:
		print("ConversationManager: Remote source '%s' looks like HTML but cannot refresh (missing URL or trigger method)." % source_name)

func _append_regular_source_context(
	context_utils: Object,
	source_id: String,
	source_data: Dictionary,
	source_meta: Dictionary,
	source_name: String,
	model_policy: Dictionary,
	poisoned_sources: Dictionary,
	context_parts: Array
) -> void:
	var direct_path: String = str(source_meta.get("path", ""))
	var direct_content: String = ""
	if is_instance_valid(context_utils) and context_utils.has_method("extract_text_from_source_data"):
		direct_content = str(context_utils.call("extract_text_from_source_data", source_data))

	var per_source_char_limit: int = int(model_policy.get("per_source_char_limit", 20000))
	if direct_content.length() > per_source_char_limit:
		direct_content = direct_content.substr(0, per_source_char_limit) + "\n\n[...truncated...]"

	if direct_content.is_empty():
		print("ConversationManager: Content for active source '%s' (ID: %s) is empty." % [source_name, source_id])
		return

	var body_text: String = direct_content
	# If this remote source is HTML-wrapped, don't feed the HTML to the model.
	if bool(poisoned_sources.get(source_id, false)):
		body_text = "[Remote source returned an HTML wrapper (e.g., GitHub page chrome). A background refresh was triggered to fetch the raw text. Ask again in a moment to use the refreshed content.]"

	if not bool(model_policy.get("include_full_text", false)):
		var digest_text: String = ""
		if is_instance_valid(context_utils) and context_utils.has_method("make_source_digest"):
			digest_text = str(context_utils.call("make_source_digest", body_text, int(model_policy.get("digest_chars", 1200))))
		if not digest_text.is_empty():
			body_text = digest_text

	context_parts.append("--- Context from %s (%s) ---\n%s\n--- End Context ---" % [source_name, direct_path, body_text])

func _build_context_header(
	context_utils: Object,
	content_state,
	sources_for_context: Array,
	poisoned_sources: Dictionary,
	preview_chars: int
) -> String:
	var index_sources: Array = []
	for source_id_any in sources_for_context:
		var source_id: String = str(source_id_any)
		var source_data: Dictionary = content_state.get_source_data(source_id)
		var source_meta: Dictionary = source_data.get("meta", {})
		var idx_item := {
			"id": source_id,
			"name": str(source_meta.get("name", source_id)),
			"path": str(source_meta.get("path", "")),
			"origin": str(source_meta.get("source_origin", "")),
			"type": str(source_meta.get("source_type", "")),
		}
		index_sources.append(idx_item)

	var sources_index_json: String = JSON.stringify({"schema": "syntree.sources_index.v1", "sources": index_sources}, "  ")
	var active_lines: Array[String] = []
	for source_id_any in sources_for_context:
		var source_id: String = str(source_id_any)
		var source_data: Dictionary = content_state.get_source_data(source_id)
		var source_meta: Dictionary = source_data.get("meta", {})
		var source_title: String = str(source_meta.get("name", source_id))
		var source_path: String = str(source_meta.get("path", ""))
		var preview_text: String = ""
		if is_instance_valid(context_utils) and context_utils.has_method("extract_text_from_source_data"):
			preview_text = str(context_utils.call("extract_text_from_source_data", source_data)).strip_edges()
		if bool(poisoned_sources.get(source_id, false)):
			preview_text = "<remote source returned HTML wrapper; refresh triggered>"
		if preview_text.length() > preview_chars:
			preview_text = preview_text.substr(0, preview_chars) + "..."
		if preview_text.is_empty():
			preview_text = "<no text extracted>"
		if source_path.is_empty():
			active_lines.append("- %s - preview: %s" % [source_title, preview_text])
		else:
			active_lines.append("- %s (%s) - preview: %s" % [source_title, source_path, preview_text])

	var header: String = "[SYNESYN_CONTEXT v1]\n"
	header += "You have access to CONTENT SOURCES below. Their FULL CONTENT is included here.\n"
	header += "When asked what is available in content sources, list each source and summarize what it contains.\n"
	header += "IMPORTANT: Do NOT say \"visit the URL\" or claim you cannot read a URL source. If a source path is an http(s) URL, the fetched text is already included below.\n"
	header += "If the user references a specific source (by name/id/path), focus on that source first.\n"
	header += "Where helpful, quote a short excerpt from the source text to prove you used it.\n"
	header += "\nSOURCES_INDEX_JSON:\n" + sources_index_json + "\n\n"
	header += "SOURCES_PREVIEW:\n" + "\n".join(active_lines) + "\n\n"
	header += "SOURCES_CONTENT:\n"
	return header
