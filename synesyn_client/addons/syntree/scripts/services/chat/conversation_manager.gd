## Purpose: ConversationManager (script)
@tool
extends Node
class_name ConversationManager

const DEBUG_VERBOSE: bool = false

const DEFAULT_THREADS_ROOT_DIR := "" # Resolved via RuntimeConfig / disk store (Documents/Synesyn).
const HubSubstrateClientScript = preload("res://addons/synesyn_core/scripts/hub_substrate_client.gd")
const SynesynSessionScript = preload("res://addons/synesyn_core/scripts/synesyn_session.gd")
const RuntimeConfigScript = preload("res://addons/synesyn_core/scripts/runtime_config.gd")
const ThreadScopeUtils = preload("res://addons/synesyn_core/scripts/thread_scope_utils.gd")
const _ThreadDiskStoreScript = preload("res://addons/syntree/scripts/services/chat/internal/conversation_thread_disk_store.gd")
const _ContextUtilsScript = preload("res://addons/syntree/scripts/services/chat/internal/conversation_context_utils.gd")
const _ChatContextBuilderScript = preload("res://addons/syntree/scripts/services/chat/internal/conversation_chat_context_builder.gd")
const _HubThreadStoreScript = preload("res://addons/syntree/scripts/services/chat/internal/conversation_hub_thread_store.gd")
const _ContextTraceCoordinatorScript = preload("res://addons/syntree/scripts/services/chat/internal/context_execution_trace_coordinator.gd")

const HUB_INDEX_SCHEMA_VERSION := 1

var thread_scope: String = "shared"
var _requested_thread_scope: String = "shared"

var include_content_bus_context: bool = true

signal conversation_updated(thread_name: String)
signal thread_loaded(thread_name: String)
signal thread_saved(thread_name: String)
signal operation_failed(operation: String, error: String, details: String)

var api_service = null
var ai_model_manager = null

var _hub = null
var _hub_session_id: String = ""

var persist_important_outputs_to_hub: bool = false

var use_stfx_store_context: bool = false
var stfx_store_top_k: int = 5
var stfx_store_expansion_depth: int = 1
var stfx_store_default_seed: String = "primary"

var _current_thread: String = "default"
var _threads: Dictionary = {}
var _message_counter: int = 0
var _remote_refresh_attempted: Dictionary = {} # source_id -> bool (best-effort, per run)
var _last_stfx_store_context_meta: Dictionary = {}

var _thread_exists_on_disk: Dictionary = {} # thread_id -> true

var _storage_root_override: String = ""
var _disk_store := _ThreadDiskStoreScript.new()
var _context_utils := _ContextUtilsScript.new()
var _chat_context_builder := _ChatContextBuilderScript.new()
var _hub_store := _HubThreadStoreScript.new()
var _context_trace_coordinator := _ContextTraceCoordinatorScript.new()

func set_thread_scope(scope: String) -> void:
	_requested_thread_scope = String(scope).strip_edges()
	thread_scope = ThreadScopeUtils.sanitize_scope(_requested_thread_scope)

func get_thread_scope() -> String:
	return thread_scope

func set_include_content_bus_context(enabled: bool) -> void:
	include_content_bus_context = enabled

func _get_threads_dir() -> String:
	if _disk_store != null and (_disk_store as Object).has_method("compute_threads_dir"):
		return (_disk_store as Object).call("compute_threads_dir", thread_scope, _storage_root_override)
	return RuntimeConfig.get_conversation_threads_dir().path_join(thread_scope)

func _maybe_fallback_to_shared_scope_for_backcompat() -> void:
	# Guardrail: if callers request a non-shared scope but the user only has legacy threads
	# under "shared", don't silently hide their history. We only fall back when:
	# - requested scope != shared
	# - requested scope has no thread files
	# - shared has thread files
	if ThreadScopeUtils.sanitize_scope(_requested_thread_scope) == "shared":
		return
	if thread_scope == "shared":
		return
	if _disk_store == null or not (_disk_store as Object).has_method("has_any_thread_files"):
		return

	var requested_dir := _get_threads_dir()
	var has_requested := bool((_disk_store as Object).call("has_any_thread_files", requested_dir))
	if has_requested:
		return

	var shared_dir: String = ""
	if (_disk_store as Object).has_method("compute_threads_dir"):
		shared_dir = str((_disk_store as Object).call("compute_threads_dir", "shared", _storage_root_override))
	else:
		shared_dir = RuntimeConfig.get_conversation_threads_dir().path_join("shared")
	var has_shared := bool((_disk_store as Object).call("has_any_thread_files", shared_dir))
	if has_shared:
		push_warning("ConversationManager: Falling back to legacy thread scope 'shared' (requested '%s' had no threads)" % thread_scope)
		thread_scope = "shared"

func _apply_runtime_storage_config() -> void:
	_storage_root_override = ""
	if _disk_store != null and (_disk_store as Object).has_method("apply_runtime_storage_root_override"):
		_storage_root_override = str((_disk_store as Object).call("apply_runtime_storage_root_override")).strip_edges()
	if not _storage_root_override.is_empty():
		print("ConversationManager: Using storage.root_dir override: %s" % _storage_root_override)

func setup(api_service_node, ai_model_manager_node = null) -> Dictionary:
	if DEBUG_VERBOSE:
		print("ConversationManager: Starting setup...")
	if not api_service_node:
		push_warning("ConversationManager: API service is required")
		return {"success": false, "error": "API service is required"}
	
	api_service = api_service_node
	if ai_model_manager_node: # Only assign if provided during initial setup
		ai_model_manager = ai_model_manager_node

	# Normalize scope before any other work (callers should set scope before setup()).
	set_thread_scope(thread_scope)

	# Hub client (best-effort)
	_hub = HubSubstrateClientScript.new()
	add_child(_hub)
	if _hub and _hub.has_method("configure_from_runtime_config"):
		_hub.configure_from_runtime_config()

	# Optional feature flags (apps.syntree.*)
	var cfg: Dictionary = RuntimeConfigScript.load_config() if RuntimeConfigScript else {}
	var apps_any: Variant = cfg.get("apps", {})
	if typeof(apps_any) == TYPE_DICTIONARY:
		var apps: Dictionary = apps_any
		var syntree_any: Variant = apps.get("syntree", {})
		if typeof(syntree_any) == TYPE_DICTIONARY:
			persist_important_outputs_to_hub = bool((syntree_any as Dictionary).get("persist_important_outputs", false))
			use_stfx_store_context = bool((syntree_any as Dictionary).get("use_stfx_store_context", false))
			stfx_store_top_k = int((syntree_any as Dictionary).get("stfx_store_top_k", 5))
			stfx_store_expansion_depth = int((syntree_any as Dictionary).get("stfx_store_expansion_depth", 1))
			stfx_store_default_seed = str((syntree_any as Dictionary).get("stfx_store_default_seed", "primary")).strip_edges()
			if stfx_store_default_seed.is_empty():
				stfx_store_default_seed = "primary"

	# Storage root override (threads should be human-findable by default).
	_apply_runtime_storage_config()
	_maybe_fallback_to_shared_scope_for_backcompat()
	_hub_session_id = SynesynSessionScript.get_or_create_session_id(thread_scope)
	
	# Initialize default thread
	_threads[_current_thread] = {
		"name": _current_thread,
		"messages": []
	}
	
	# Initialize with default welcome message
	var welcome_message = {
		"role": "assistant",
		"content": "Hi there! How can I help you today?",
		"timestamp": Time.get_datetime_string_from_system()
	}
	_threads[_current_thread].messages.append(welcome_message)
	
	# Load existing threads
	if DEBUG_VERBOSE:
		print("ConversationManager: Loading existing threads...")
	var load_result = _load_threads()
	if not load_result.success:
		if DEBUG_VERBOSE:
			print("ConversationManager: Failed to load threads - ", load_result.error)
		# Don't return error here, just continue with default thread
	
	if DEBUG_VERBOSE:
		print("ConversationManager: Setup complete. Available threads: ", _threads.keys())
	# Hub is system-of-record when reachable; sync latest versions (best-effort).
	call_deferred("_sync_threads_from_hub")
	return {"success": true, "error": ""}

# Single short diagnostic line printed once per completed chat() call, so prompt size, the
# model that received it and the seconds it took are visible alongside the existing
# `[ActorAgent]` / `[DirectorAgent]` logs. A turn costs several of these calls in sequence,
# and the elapsed figure is the only way to see which of them the wait is in.
static func _print_budget(thread_label: String, model_id: String, total_chars: int, elapsed_ms: int, reasoning_effort: String = "") -> void:
	# Strip the conversation-scope prefix and trailing timestamp suffix so the
	# label reads like the role of the call (e.g. "director_tactical_batch")
	# rather than a wall of ids. Falls back to the raw label if no separator.
	var label: String = thread_label
	var sep_idx: int = label.rfind("__")
	if sep_idx >= 0:
		label = label.substr(sep_idx + 2)
	# Drop a trailing _<ms> timestamp if present (added by agent helpers).
	var trim_idx: int = label.rfind("_")
	if trim_idx > 0 and label.substr(trim_idx + 1).is_valid_int():
		label = label.substr(0, trim_idx)
	# Render character count in K for readability (one decimal under 100K).
	var size_label: String
	if total_chars >= 100000:
		size_label = "%dk" % int(round(total_chars / 1000.0))
	elif total_chars >= 1000:
		size_label = "%.1fk" % (total_chars / 1000.0)
	else:
		size_label = "%d" % total_chars
	var effort_label: String = "" if reasoning_effort.is_empty() else " effort=%s" % reasoning_effort
	print("[budget] %s %s chars (%s) %.1fs%s" % [
		label, size_label, model_id, elapsed_ms / 1000.0, effort_label
	])

# Processes a chat message, adding it to the thread, sending it to the API,
# adding the response, and saving the thread.
# Fetches active source context AND conversation history before calling APIService.
#
# Parameters:
#   user_prompt   — The message to send.
#   thread_name   — Thread id for history isolation. Empty → default thread.
#   model_override — If non-empty, this call uses the named model instead of the
#                    manager's current selection. The global current-model state is
#                    NOT changed. Pass "" (the default) to keep legacy behaviour.
#                    Populated by DirectorAgent and ActorAgent via scenario
#                    system_config keys "director_model" / "actor_model".
#   call_settings — Per-call request settings for callers that know something about
#                    their own call the loader cannot, e.g. {"reasoning_effort": "low"}
#                    for an internal or mechanical call. Providers that do not
#                    understand a given key never receive it.
#
# Emits one line per completed call: [budget] <role-label> <size> (<model>) <seconds>,
# the label being the meaningful part of thread_name.
func chat(user_prompt: String, thread_name: String = "", model_override: String = "", call_settings: Dictionary = {}) -> Dictionary:
	_last_stfx_store_context_meta = {}
	remove_meta("last_context_compile_result")
	if DEBUG_VERBOSE:
		print("ConversationManager (Instance: %s): Processing chat message..." % get_instance_id())
		# Check if the ai_model_manager reference is valid before proceeding.
		print("  - Current ai_model_manager reference: %s" % str(ai_model_manager))
		if ai_model_manager:
			print("  - ai_model_manager Instance ID: %s" % ai_model_manager.get_instance_id())
	
	if not api_service:
		operation_failed.emit("chat", "API service not available", "")
		return {"success": false, "error": "API service not available"}
	
	# This check ensures the manager reference was successfully set before chat is called.
	if not ai_model_manager:
		operation_failed.emit("chat", "AI model manager not available", "")
		return {"success": false, "error": "AI model manager not available"}
	
	# Resolve target thread ID (do NOT rely on Dictionary dot-access for identity).
	var thread_id := String(thread_name).strip_edges()
	if thread_id.is_empty():
		thread_id = _current_thread
	else:
		# Keep manager state consistent if callers pass an explicit thread id.
		_current_thread = thread_id

	# Get current thread
	var thread = _get_or_create_thread(thread_id)
	if not thread:
		operation_failed.emit("chat", "Thread not found: " + thread_name, "")
		return {"success": false, "error": "Thread not found"}
		
	# Ensure messages key exists and is an array
	if not thread.has("messages") or not thread.messages is Array:
		thread["messages"] = []
	
	# --- Get HISTORY ---
	var history_messages = thread.messages.duplicate() # Get a copy of existing messages
	if DEBUG_VERBOSE:
		print("ConversationManager DEBUG: Thread '%s' has %d messages in history" % [thread.name, history_messages.size()])

	# --- Add NEW user message to LOCAL history (for saving) ---
	var user_message: Dictionary = _context_trace_coordinator.make_message(
		thread_scope,
		thread_id,
		thread.messages.size(),
		"user",
		user_prompt
	)
	thread.messages.append(user_message) # Append to the dictionary we'll save

	# Persist immediately so the prompt survives reload/thread switching even if the API call fails
	# or the editor closes mid-request.
	if thread.has("last_updated"):
		thread.last_updated = Time.get_unix_time_from_system()
	else:
		thread["last_updated"] = Time.get_unix_time_from_system()
	var save_prompt_res: Dictionary = _save_thread(thread_id)
	if not bool(save_prompt_res.get("success", false)):
		push_error("ConversationManager: Failed to save thread '%s' after adding user prompt: %s" % [thread_id, str(save_prompt_res.get("error", ""))])
	
	# --- Prepare message list FOR API --- 
	# Start with history, add the new user prompt
	var messages_for_api = history_messages 
	messages_for_api.append({"role": "user", "content": user_prompt}) # Add NEW message for API call
	if DEBUG_VERBOSE:
		print("ConversationManager DEBUG: Sending %d messages to API" % messages_for_api.size())
	
	# --- Prepare Context from Active Sources ---
	var context_string: String = await _chat_context_builder.build_context(self, user_prompt, thread_id, ai_model_manager)
	# --- End Context Preparation ---

	# --- Call API Service --- 
	# Pass the history+new message list, and the context string separately
	# Ensure the target method exists before calling
	if not api_service.has_method("process_message_with_history"):
		operation_failed.emit("chat", "APIService is missing process_message_with_history method.", "")
		return {"success": false, "error": "Internal error: API service method missing."}
	
	# DEBUG: Calculate total size being sent
	var total_chars_sent = 0
	var total_chars_context := context_string.length()
	for msg in messages_for_api:
		if msg.has("content"):
			total_chars_sent += str(msg.content).length()
	total_chars_sent += total_chars_context
	if DEBUG_VERBOSE:
		print("ConversationManager DEBUG: Sending %d total characters to API (%d from messages, %d from context)" % [total_chars_sent, total_chars_sent - total_chars_context, total_chars_context])

	# Per-call prompt-budget visibility (always on, one short line). Resolves the
	# model id from the override (if set) or the manager's current selection so
	# the line reflects what was actually sent.
	var resolved_model_id := String(model_override).strip_edges()
	if resolved_model_id.is_empty() and ai_model_manager and ai_model_manager.has_method("get_current_model"):
		resolved_model_id = String(ai_model_manager.get_current_model())
	var budget_started_ms: int = Time.get_ticks_msec()
	var pending_context_trace: Dictionary = _context_trace_coordinator.begin_for_chat(
		self,
		thread_id,
		user_message,
		thread.messages.size() - 1,
		ai_model_manager,
		model_override
	)

	var api_response = await api_service.process_message_with_history(messages_for_api, context_string, model_override, call_settings)
	# The applied budget when the call reports one, since a model that cannot reason has it
	# dropped; otherwise what was asked for, which is all a failed call can say.
	_print_budget(
		thread_id,
		resolved_model_id,
		total_chars_sent,
		Time.get_ticks_msec() - budget_started_ms,
		String(api_response.get("reasoning_effort", call_settings.get("reasoning_effort", "")))
	)
	if not api_response.success:
		# Ensure the error response structure is consistent
		var error_msg = api_response.get("error", "Unknown API error")
		var error_details = api_response.get("details", "")
		if DEBUG_VERBOSE:
			print("ConversationManager: API Error response - ", error_msg)
			print("ConversationManager: API Error details - ", error_details)
		_context_trace_coordinator.complete(
			self,
			_hub,
			pending_context_trace,
			{"status": "request_failed", "error": error_msg}
		)
		operation_failed.emit("chat", error_msg, error_details)
		# Return a consistent error format
		return {"success": false, "error": error_msg, "details": error_details}
	
	# Add assistant response to LOCAL thread history
	var assistant_message: Dictionary = _context_trace_coordinator.make_message(
		thread_scope,
		thread_id,
		thread.messages.size(),
		"assistant",
		str(api_response.response)
	)
	thread.messages.append(assistant_message) # Append to the dictionary we'll save
	if DEBUG_VERBOSE:
		print("ConversationManager DEBUG: Thread '%s' NOW has %d messages after response" % [thread.name, thread.messages.size()])
	
	# Update last_updated timestamp
	if thread.has("last_updated"): # Check if key exists
		thread.last_updated = Time.get_unix_time_from_system()
	else:
		thread["last_updated"] = Time.get_unix_time_from_system() # Add if missing
	
	# Save the updated LOCAL thread (which now includes user + assistant message)
	var save_result = _save_thread(thread_id)
	if not save_result.success:
		# Log the error but don't necessarily fail the chat operation itself,
		# as the response was already received.
		push_error("ConversationManager: Failed to save thread '%s' after chat: %s" % [thread_id, save_result.error])
		# Optionally emit an operation_failed signal here if desired
		# operation_failed.emit("save_thread", save_result.error, "Failed after chat completion")
	
	# Best-effort: optional substrate persistence for important outputs with provenance stamps.
	if persist_important_outputs_to_hub:
		var model_id := ""
		var provider_id := ""
		if ai_model_manager and ai_model_manager.has_method("get_current_model"):
			model_id = str(ai_model_manager.get_current_model()).strip_edges()
		if ai_model_manager and ai_model_manager.has_method("get_provider_for_model"):
			provider_id = str(ai_model_manager.get_provider_for_model(model_id)).strip_edges()
		var payload := {
			"schema_version": 1,
			"thread_scope": thread_scope,
			"thread_id": thread_id,
			"hub_session_id": _hub_session_id,
			"model_id": model_id,
			"provider_id": provider_id,
			"created_at": Time.get_unix_time_from_system(),
			"context_string": context_string,
			"messages_for_api": messages_for_api,
			"user_prompt": user_prompt,
			"assistant_response": str(api_response.response),
			"metrics": {
				"total_chars_sent": total_chars_sent,
				"messages_chars": total_chars_sent - total_chars_context,
				"context_chars": total_chars_context,
				"response_chars": str(api_response.response).length(),
			},
		}
		call_deferred("_persist_important_outputs_async", payload)

	if use_stfx_store_context and not _last_stfx_store_context_meta.is_empty():
		var store_payload := {
			"schema_version": 1,
			"thread_scope": thread_scope,
			"thread_id": thread_id,
			"hub_session_id": _hub_session_id,
			"created_at": Time.get_unix_time_from_system(),
			"user_prompt": user_prompt,
			"assistant_response": str(api_response.response),
			"context_meta": _last_stfx_store_context_meta.duplicate(true),
			"metrics": {
				"total_chars_sent": total_chars_sent,
				"context_chars": total_chars_context,
				"response_chars": str(api_response.response).length(),
			},
		}
		call_deferred("_persist_stfx_store_chat_async", store_payload)

	_context_trace_coordinator.complete(
		self,
		_hub,
		pending_context_trace,
		{
			"status": "completed",
			"assistant_message_id": str(assistant_message.get("id", "")),
			"assistant_index": thread.messages.size() - 1,
		}
	)

	return {"success": true, "response": api_response.response}

func _try_build_stfx_store_context(user_prompt: String, content_state, sources_for_context: Array) -> String:
	if not use_stfx_store_context:
		return ""
	if not is_instance_valid(_hub):
		return ""
	if not (_hub as Object).has_method("stfx_store_ingest_source"):
		return ""
	if not (_hub as Object).has_method("stfx_store_retrieve"):
		return ""
	if not is_instance_valid(content_state):
		return ""

	var store_source_ids: Array[String] = []
	for source_id_any in sources_for_context:
		var source_id: String = str(source_id_any).strip_edges()
		if source_id.is_empty():
			continue
		var source_data: Dictionary = content_state.get_source_data(source_id)
		if source_data.is_empty():
			continue
		var ingest_path: String = _get_stfx_store_ingest_path(source_data)
		if ingest_path.is_empty():
			continue
		var ingest_res: Dictionary = await (_hub as Object).call(
			"stfx_store_ingest_source",
			ingest_path,
			stfx_store_default_seed
		)
		if not bool(ingest_res.get("ok", false)):
			continue
		var store_source_id: String = str(ingest_res.get("source_id", "")).strip_edges()
		if not store_source_id.is_empty() and not store_source_ids.has(store_source_id):
			store_source_ids.append(store_source_id)

	if store_source_ids.is_empty():
		return ""

	var retrieve_res: Dictionary = await (_hub as Object).call(
		"stfx_store_retrieve",
		user_prompt,
		store_source_ids,
		stfx_store_default_seed,
		stfx_store_top_k,
		stfx_store_expansion_depth
	)
	if not bool(retrieve_res.get("ok", false)):
		return ""
	var pack_any: Variant = retrieve_res.get("context_pack", {})
	if typeof(pack_any) != TYPE_DICTIONARY:
		return ""
	var context_pack: Dictionary = pack_any
	var chunks_any: Variant = context_pack.get("chunks", [])
	if typeof(chunks_any) != TYPE_ARRAY:
		return ""
	var chunks: Array = chunks_any
	if chunks.is_empty():
		return ""

	var trace_any: Variant = retrieve_res.get("trace", {})
	var trace_id: String = str(context_pack.get("trace_id", "")).strip_edges()
	if typeof(trace_any) == TYPE_DICTIONARY:
		var trace: Dictionary = trace_any
		trace_id = str(trace.get("trace_id", trace_id)).strip_edges()
	var trace_created_at := ""
	if typeof(trace_any) == TYPE_DICTIONARY:
		var trace2: Dictionary = trace_any
		trace_created_at = str(trace2.get("created_at", "")).strip_edges()
	_last_stfx_store_context_meta = {
		"trace_id": trace_id,
		"context_pack_id": str(context_pack.get("context_pack_id", "")).strip_edges(),
		"trace_created_at": trace_created_at,
		"store_source_ids": store_source_ids,
		"retrieval_trace": trace_any if typeof(trace_any) == TYPE_DICTIONARY else {},
	}

	var out: String = "[SYNESYN_STFX_STORE_CONTEXT v1]\n"
	out += "Context below was retrieved from the Hub STFX Store. Use citation labels when helpful.\n"
	out += "trace_id=%s\ncontext_pack_id=%s\n\n" % [trace_id, str(context_pack.get("context_pack_id", ""))]
	for chunk_any in chunks:
		if typeof(chunk_any) != TYPE_DICTIONARY:
			continue
		var chunk: Dictionary = chunk_any
		var citation: String = str(chunk.get("citation", chunk.get("chunk_id", ""))).strip_edges()
		var text: String = str(chunk.get("text", "")).strip_edges()
		if text.is_empty():
			continue
		var scores_any: Variant = chunk.get("scores", {})
		var scores_text: String = ""
		if typeof(scores_any) == TYPE_DICTIONARY:
			scores_text = JSON.stringify(scores_any)
		out += "--- Retrieved Chunk: %s ---\n" % citation
		if not scores_text.is_empty():
			out += "scores=%s\n" % scores_text
		out += text + "\n--- End Retrieved Chunk ---\n\n"
	out += "[/SYNESYN_STFX_STORE_CONTEXT]\n"
	return out

func _get_stfx_store_ingest_path(source_data: Dictionary) -> String:
	var meta_any: Variant = source_data.get("meta", {})
	if typeof(meta_any) != TYPE_DICTIONARY:
		return ""
	var meta: Dictionary = meta_any
	var origin: String = str(meta.get("source_origin", "file")).strip_edges().to_lower()
	if origin == "remote":
		return ""
	var raw_path: String = str(meta.get("path", "")).strip_edges()
	if raw_path.is_empty():
		return ""
	if raw_path.begins_with("http://") or raw_path.begins_with("https://"):
		return ""
	raw_path = raw_path.replace("\\", "/")
	var fs_path: String = raw_path
	if raw_path.begins_with("res://") or raw_path.begins_with("user://"):
		fs_path = ProjectSettings.globalize_path(raw_path)
	if fs_path.strip_edges().is_empty():
		return ""
	if not FileAccess.file_exists(fs_path):
		return ""
	return fs_path

func get_latest_stfx_store_context_meta() -> Dictionary:
	return _last_stfx_store_context_meta.duplicate(true)

func get_latest_stfx_store_context_paths() -> Dictionary:
	if _last_stfx_store_context_meta.is_empty():
		return {"ok": false, "error": "No STFX Store context has been used in this chat session yet."}
	if not is_instance_valid(_hub):
		return {"ok": false, "error": "Hub client unavailable"}
	if not (_hub as Object).has_method("get_workspace_root"):
		return {"ok": false, "error": "Hub client cannot resolve workspace root"}
	var root: String = str(await (_hub as Object).call("get_workspace_root"))
	root = root.strip_edges().replace("\\", "/")
	if root.is_empty():
		return {"ok": false, "error": "Hub workspace root unavailable"}
	var trace_id: String = str(_last_stfx_store_context_meta.get("trace_id", "")).strip_edges()
	var context_pack_id: String = str(_last_stfx_store_context_meta.get("context_pack_id", "")).strip_edges()
	var created_at: String = str(_last_stfx_store_context_meta.get("trace_created_at", "")).strip_edges()
	var date_label: String = created_at.substr(0, 10) if created_at.length() >= 10 else Time.get_date_string_from_system(true)
	var store_root: String = root.path_join("stfx_store")
	var trace_path: String = store_root.path_join("traces").path_join(date_label).path_join(trace_id + ".json")
	var context_pack_path: String = store_root.path_join("artifacts").path_join("context_packs").path_join(context_pack_id + ".json")
	return {
		"ok": true,
		"store_root": store_root,
		"trace_id": trace_id,
		"context_pack_id": context_pack_id,
		"trace_path": trace_path,
		"context_pack_path": context_pack_path,
		"trace_dir": trace_path.get_base_dir(),
	}

func _persist_stfx_store_chat_async(payload: Dictionary) -> void:
	if not use_stfx_store_context:
		return
	if not is_instance_valid(_hub):
		return
	if not (_hub as Object).has_method("stfx_store_commit_artifact"):
		return
	var context_meta_any: Variant = payload.get("context_meta", {})
	var context_meta: Dictionary = context_meta_any if typeof(context_meta_any) == TYPE_DICTIONARY else {}
	var trace_id: String = str(context_meta.get("trace_id", "")).strip_edges()
	var context_pack_id: String = str(context_meta.get("context_pack_id", "")).strip_edges()
	if trace_id.is_empty() and context_pack_id.is_empty():
		return
	var artifact_payload := {
		"schema_version": 1,
		"thread_scope": str(payload.get("thread_scope", "")).strip_edges(),
		"thread_id": str(payload.get("thread_id", "")).strip_edges(),
		"hub_session_id": str(payload.get("hub_session_id", "")).strip_edges(),
		"created_at": payload.get("created_at", Time.get_unix_time_from_system()),
		"user_prompt": str(payload.get("user_prompt", "")),
		"assistant_response": str(payload.get("assistant_response", "")),
		"context_meta": context_meta,
		"metrics": payload.get("metrics", {}),
	}
	var provenance := {
		"produced_by": "syntree.chat_with_stfx_store_context",
		"inputs": [
			{"type": "stfx_store.retrieval_trace", "trace_id": trace_id},
			{"type": "stfx_store.context_pack", "context_pack_id": context_pack_id},
		],
		"thread_scope": artifact_payload.get("thread_scope", ""),
		"thread_id": artifact_payload.get("thread_id", ""),
		"hub_session_id": artifact_payload.get("hub_session_id", ""),
	}
	await (_hub as Object).call("stfx_store_commit_artifact", "text.summary", artifact_payload, provenance)

func _persist_important_outputs_async(payload: Dictionary) -> void:
	if not persist_important_outputs_to_hub:
		return
	if not is_instance_valid(_hub):
		return
	if not (_hub as Object).has_method("check_health"):
		return

	# Fast reachability check (do not block the chat UX if hub is down).
	var health: Dictionary = await (_hub as Object).call("check_health")
	if not bool(health.get("ok", false)):
		return

	var thread_id := str(payload.get("thread_id", "")).strip_edges()
	var scope := str(payload.get("thread_scope", "")).strip_edges()
	var model_id := str(payload.get("model_id", "")).strip_edges()
	var provider_id := str(payload.get("provider_id", "")).strip_edges()

	var prov_base := {
		"generated_by": "syntree.important_outputs",
		"tool_version": "syntree@v1",
		"model_id": model_id,
		"provider_id": provider_id,
		"thread_scope": scope,
		"thread_id": thread_id,
		"hub_session_id": str(payload.get("hub_session_id", "")).strip_edges(),
	}

	# 1) text.prompt (metaprompt + envelope)
	var prompt_text := ""
	prompt_text += "[SYNESYN_PROMPT v1]\n"
	prompt_text += "thread_scope=%s\nthread_id=%s\nmodel=%s\nprovider=%s\n\n" % [scope, thread_id, model_id, provider_id]
	prompt_text += "--- CONTEXT_STRING (system/metaprompt) ---\n%s\n\n" % str(payload.get("context_string", ""))
	prompt_text += "--- MESSAGES_FOR_API (json) ---\n%s\n" % JSON.stringify(payload.get("messages_for_api", []), "  ")
	prompt_text += "[/SYNESYN_PROMPT]\n"

	var prompt_meta := {
		"provenance": prov_base.duplicate(true),
		"refs": {"thread_scope": scope, "thread_id": thread_id},
	}
	var prompt_res: Dictionary = await (_hub as Object).call(
		"create_artifact_inline_bytes_base64",
		"text.prompt",
		prompt_text.to_utf8_buffer(),
		"txt",
		prompt_meta
	)
	var prompt_art_id := str(prompt_res.get("id", "")).strip_edges()

	# 2) text.summary (assistant output; can be treated as "analysis" output by downstream apps)
	var summary_text := str(payload.get("assistant_response", ""))
	var summary_meta := {
		"provenance": prov_base.duplicate(true),
		"refs": {"thread_scope": scope, "thread_id": thread_id, "prompt_artifact_id": prompt_art_id},
	}
	await (_hub as Object).call(
		"create_artifact_inline_bytes_base64",
		"text.summary",
		summary_text.to_utf8_buffer(),
		"txt",
		summary_meta
	)

	# 3) json.metrics
	var metrics: Dictionary = payload.get("metrics", {}) if typeof(payload.get("metrics", {})) == TYPE_DICTIONARY else {}
	var metrics_meta := {
		"provenance": prov_base.duplicate(true),
		"refs": {"thread_scope": scope, "thread_id": thread_id, "prompt_artifact_id": prompt_art_id},
	}
	await (_hub as Object).call("create_artifact_inline_json", "json.metrics", metrics, metrics_meta)

func export_context_graph_bridge_artifact(context_graph_artifact_id: String, note: String = "") -> Dictionary:
	# Optional bridge artifact: allows apps to pass around a reference to a ui.context_graph id
	# without direct content injection. This is distinct from thread bridge artifacts (chat.thread).
	if not is_instance_valid(_hub):
		return {"ok": false, "error": "Hub client not available"}
	var cg := String(context_graph_artifact_id).strip_edges()
	if cg.is_empty():
		return {"ok": false, "error": "context_graph_artifact_id is required"}
	var meta := {"provenance": {"generated_by": "syntree.context_graph_bridge", "note": note}}
	if (_hub as Object).has_method("create_context_graph_bridge"):
		return await (_hub as Object).call("create_context_graph_bridge", cg, meta)
	return {"ok": false, "error": "Hub client missing create_context_graph_bridge"}

func resolve_context_graph_bridge_artifact(bridge_artifact_id: String) -> Dictionary:
	if not is_instance_valid(_hub):
		return {"ok": false, "error": "Hub client not available"}
	if (_hub as Object).has_method("resolve_context_graph_bridge"):
		return await (_hub as Object).call("resolve_context_graph_bridge", bridge_artifact_id)
	return {"ok": false, "error": "Hub client missing resolve_context_graph_bridge"}

func _exit_tree() -> void:
	# Disk is the source of truth; do not write thread JSON files on shutdown/reload.
	# Thread files are only written during explicit user actions (create thread / user prompt / AI response / history edit).
	return

func get_current_thread() -> String:
	return _current_thread

func set_current_thread(thread_name: String) -> Dictionary:
	if thread_name.is_empty():
		return {"success": false, "error": "Thread name cannot be empty"}

	var tid := String(thread_name).strip_edges()
	if tid.is_empty():
		return {"success": false, "error": "Thread name cannot be empty"}

	# Disk is the source of truth: reload the thread from JSON each time it becomes current.
	var threads_dir := _get_threads_dir()
	var loaded_thread: Dictionary = {}
	if _disk_store != null and (_disk_store as Object).has_method("load_thread"):
		var load_res: Dictionary = (_disk_store as Object).call("load_thread", threads_dir, tid)
		if bool(load_res.get("success", false)):
			var t_any: Variant = load_res.get("thread", {})
			if typeof(t_any) == TYPE_DICTIONARY:
				loaded_thread = t_any

	if loaded_thread.is_empty():
		# If the JSON doesn't exist, do NOT auto-create on select.
		# Creation should only happen via explicit user action ("Create New Thread") or by chat() when the user sends a message.
		return {"success": false, "error": "Thread JSON not found on disk: %s" % tid}
	else:
		# Overwrite in-memory cache with disk data.
		_threads[tid] = loaded_thread
		_thread_exists_on_disk[tid] = true

	_current_thread = tid
	if DEBUG_VERBOSE:
		print("ConversationManager: Set current thread to '%s' (reloaded from disk)" % tid)
	thread_loaded.emit(tid)
	conversation_updated.emit(tid)
	return {"success": true, "error": ""}

# Ensure a thread exists on disk (so it survives project reload even before first message).
func ensure_thread_saved(thread_id: String) -> Dictionary:
	var tid := String(thread_id).strip_edges()
	if tid.is_empty():
		return {"success": false, "error": "Thread ID cannot be empty"}
	# Ensure in-memory structure exists.
	_get_or_create_thread(tid)
	# Write an empty/initial file if needed.
	var res := _save_thread(tid)
	if bool(res.get("success", false)):
		_thread_exists_on_disk[tid] = true
	# Helpful breadcrumb for users: user:// is outside the project folder.
	if bool(res.get("success", false)):
		var threads_dir := _get_threads_dir()
		var abs_dir := ProjectSettings.globalize_path(threads_dir)
		print("ConversationManager: Thread ensured on disk: %s (dir: %s)" % [tid, abs_dir])
	return res

func get_threads_dir_info() -> Dictionary:
	var threads_dir := _get_threads_dir()
	return {
		"threads_dir": threads_dir,
		"threads_dir_abs": ProjectSettings.globalize_path(threads_dir),
		"scope": thread_scope
	}

func get_thread_list() -> Array:
	# Present only threads that exist on disk (plus default).
	# This avoids confusing "phantom" threads if a JSON file was deleted externally.
	var out: Array[String] = []
	for tid_any in _threads.keys():
		var tid := String(tid_any).strip_edges()
		if tid.is_empty():
			continue
		if tid == "default":
			out.append(tid)
			continue
		if bool(_thread_exists_on_disk.get(tid, false)):
			out.append(tid)
	return out

func reload_threads_from_disk() -> Dictionary:
	# Disk is the source of truth; refresh the in-memory cache from JSON files.
	return _load_threads()

func get_thread_messages(thread_name: String = "") -> Array:
	if thread_name.is_empty():
		thread_name = _current_thread
	var thread = _threads.get(thread_name)
	if thread and thread is Dictionary and thread.has("messages"):
		if thread.messages is Array:
			return thread.messages
		else:
			return []
	return []

func set_thread_messages(thread_name: String, new_messages: Array) -> Dictionary:
	"""Replace the messages in a thread with a new array of messages."""
	if thread_name.is_empty():
		thread_name = _current_thread
	
	if not _threads.has(thread_name):
		return {"success": false, "error": "Thread not found: " + thread_name}
	
	var thread = _threads.get(thread_name)
	if not thread or not thread is Dictionary:
		return {"success": false, "error": "Invalid thread structure"}
	
	# Replace the messages array
	thread["messages"] = new_messages.duplicate()
	if DEBUG_VERBOSE:
		print("ConversationManager: Replaced thread '", thread_name, "' messages. New count: ", new_messages.size())
	
	return {"success": true, "messages_count": new_messages.size()}

func _save_thread(thread_name: String) -> Dictionary:
	if not _threads.has(thread_name):
		return {"success": false, "error": "Thread not found"}
	
	# Get the actual thread dictionary
	var current_thread_data = _threads[thread_name]
	if not current_thread_data is Dictionary:
		push_error("ConversationManager: Invalid thread data structure for '%s'" % thread_name)
		return {"success": false, "error": "Invalid thread data structure"}
	
	var threads_dir := _get_threads_dir()
	if _disk_store == null or not (_disk_store as Object).has_method("save_thread"):
		return {"success": false, "error": "Thread disk store not available"}
	var save_res: Dictionary = (_disk_store as Object).call("save_thread", threads_dir, thread_name, current_thread_data)
	if not bool(save_res.get("success", false)):
		return {"success": false, "error": str(save_res.get("error", "Failed to save thread"))}
	_thread_exists_on_disk[thread_name] = true
	thread_saved.emit(thread_name)
	# Best-effort hub persistence (v1): versioned artifact per save.
	call_deferred("_persist_thread_version_to_hub", thread_name)
	return {"success": true, "error": ""}

func _load_threads() -> Dictionary:
	var threads_dir := _get_threads_dir()
	# Clear existing threads but keep the in-memory default thread (it may be overwritten by disk data).
	var default_thread: Variant = _threads.get(_current_thread)
	_threads.clear()
	_threads[_current_thread] = default_thread

	if _disk_store == null or not (_disk_store as Object).has_method("load_threads"):
		return {"success": false, "error": "Thread disk store not available"}
	var res: Dictionary = (_disk_store as Object).call("load_threads", threads_dir)
	if not bool(res.get("success", false)):
		return {"success": false, "error": str(res.get("error", "Failed to load threads"))}
	var loaded_any: Variant = res.get("threads", {})
	if typeof(loaded_any) == TYPE_DICTIONARY:
		var loaded: Dictionary = loaded_any
		_thread_exists_on_disk.clear()
		for tid in loaded.keys():
			_threads[tid] = loaded[tid]
			_thread_exists_on_disk[str(tid)] = true
	return {"success": true, "error": ""}

func _get_or_create_thread(thread_name: String = "") -> Dictionary:
	# Note: thread_name here corresponds to the filename-based ID now
	if thread_name.is_empty():
		thread_name = _current_thread
	
	if not _threads.has(thread_name):
		if DEBUG_VERBOSE:
			print("ConversationManager: Creating new thread structure for ID: ", thread_name)
		_threads[thread_name] = {
			"name": thread_name, # Use the ID as the initial name
			"messages": [],
			"last_updated": Time.get_unix_time_from_system(),
			"_thread_id": thread_name # Store the ID derived from filename
		}
	
	return _threads[thread_name]

# New function to explicitly set the AI model manager later if needed
# This is typically called by SyntreePanel during its setup phase.
func set_ai_model_manager(manager) -> void:
	if not manager:
		push_warning("ConversationManager: Attempted to set null AI model manager.")
		return
	if DEBUG_VERBOSE:
		print("ConversationManager (Instance: %s): AI Model Manager explicitly set to Instance: %s." % [get_instance_id(), manager.get_instance_id()])
	ai_model_manager = manager

# --- NEW METHOD for handling history edits --- 
# Updates the messages for a specific thread and saves it.
func update_thread_messages(thread_id: String, messages: Array) -> Dictionary:
	if thread_id.is_empty():
		var err_msg = "Thread ID cannot be empty for updating messages."
		operation_failed.emit("update_messages", err_msg)
		return {"success": false, "error": err_msg}
		
	# Get the thread data structure (ensure it exists)
	var thread = _get_or_create_thread(thread_id)
	if not thread:
		var err_msg = "Failed to get or create thread '%s' for message update." % thread_id
		operation_failed.emit("update_messages", err_msg)
		return {"success": false, "error": err_msg}
		
	# Replace the messages array
	thread["messages"] = messages
	# Update timestamp
	thread["last_updated"] = Time.get_unix_time_from_system()
	
	if DEBUG_VERBOSE:
		print("ConversationManager: Updated messages for thread '%s'. New count: %d" % [thread_id, messages.size()])
	
	# Save the updated thread
	var save_result = _save_thread(thread_id)
	if not save_result.success:
		var err_msg = "Failed to save thread '%s' after updating messages: %s" % [thread_id, save_result.error]
		operation_failed.emit("update_messages", err_msg)
		# Return failure even though update happened in memory
		return {"success": false, "error": err_msg}
	
	# Emit signal to notify UI (or rely on Resource signals if threads become Resources)
	conversation_updated.emit(thread_id)

	# Best-effort hub persistence for edited history
	call_deferred("_persist_thread_version_to_hub", thread_id)
	
	return {"success": true}

func _persist_thread_version_to_hub(thread_id: String) -> void:
	if not is_instance_valid(_hub_store) or not _hub_store.has_method("persist_thread_version_to_hub"):
		return
	await _hub_store.persist_thread_version_to_hub(_hub, thread_scope, _hub_session_id, _get_threads_dir(), _threads, thread_id)

# --- Bridge artifacts (v1): explicit export/import for cross-app sharing ---
func export_thread_bridge_artifact(thread_id: String) -> Dictionary:
	# Explicit action: publish a snapshot of the given thread as a hub artifact and return its artifact_id.
	var tid := String(thread_id).strip_edges()
	if tid.is_empty():
		return {"success": false, "error": "thread_id is required"}
	if not is_instance_valid(_hub_store) or not _hub_store.has_method("persist_thread_version_to_hub"):
		return {"success": false, "error": "Hub thread store not available"}
	var res: Dictionary = await _hub_store.persist_thread_version_to_hub(_hub, thread_scope, _hub_session_id, _get_threads_dir(), _threads, tid)
	if not bool(res.get("ok", false)):
		return {"success": false, "error": str(res.get("error", "Failed to export thread to hub"))}
	return {"success": true, "artifact_id": str(res.get("artifact_id", "")).strip_edges()}

func import_thread_bridge_artifact(artifact_id: String, target_thread_id: String = "") -> Dictionary:
	# Explicit action: import a hub thread artifact into local storage under target_thread_id (or the artifact's thread_id).
	var aid := String(artifact_id).strip_edges()
	if aid.is_empty():
		return {"success": false, "error": "artifact_id is required"}
	if not is_instance_valid(_hub) or not _hub.has_method("get_artifact_json"):
		return {"success": false, "error": "Hub client not available"}

	var tid := String(target_thread_id).strip_edges()
	if tid.is_empty():
		var aj: Dictionary = await _hub.get_artifact_json(aid)
		if not bool(aj.get("ok", false)):
			return {"success": false, "error": "Failed to load artifact JSON", "details": str(aj.get("error", ""))}
		var any: Variant = aj.get("json", {})
		if typeof(any) != TYPE_DICTIONARY:
			return {"success": false, "error": "Artifact JSON invalid"}
		var j: Dictionary = any
		tid = String(j.get("thread_id", "")).strip_edges()
		if tid.is_empty():
			return {"success": false, "error": "Artifact JSON missing thread_id"}

	# Reuse existing hub-version importer (it persists locally + updates local hub index).
	return await load_thread_from_hub_version(tid, aid)

func get_latest_thread_bridge_artifact_id(thread_id: String) -> String:
	var tid := String(thread_id).strip_edges()
	if tid.is_empty():
		return ""
	var info: Dictionary = get_thread_hub_info(tid)
	return String(info.get("latest_artifact_id", "")).strip_edges()

func _sync_threads_from_hub() -> void:
	if not is_instance_valid(_hub_store) or not _hub_store.has_method("sync_threads_from_hub"):
		return
	await _hub_store.sync_threads_from_hub(_hub, thread_scope, _hub_session_id, _get_threads_dir(), _threads, Callable(self, "_emit_thread_loaded"), Callable(self, "_emit_conversation_updated"))

func _emit_thread_loaded(thread_id: String) -> void:
	thread_loaded.emit(thread_id)

func _emit_conversation_updated(thread_id: String) -> void:
	conversation_updated.emit(thread_id)

func get_thread_hub_info(thread_id: String) -> Dictionary:
	if not is_instance_valid(_hub_store) or not _hub_store.has_method("get_thread_hub_info"):
		return {}
	return _hub_store.get_thread_hub_info(_get_threads_dir(), thread_id)

func load_thread_from_hub_version(thread_id: String, artifact_id: String) -> Dictionary:
	if not is_instance_valid(_hub_store) or not _hub_store.has_method("load_thread_from_hub_version"):
		return {"success": false, "error": "Hub thread store not available"}
	return await _hub_store.load_thread_from_hub_version(
		_hub,
		thread_scope,
		_hub_session_id,
		_get_threads_dir(),
		_threads,
		thread_id,
		artifact_id,
		Callable(self, "_get_or_create_thread"),
		Callable(self, "_save_thread"),
		Callable(self, "_emit_thread_loaded"),
		Callable(self, "_emit_conversation_updated")
	)

func is_busy() -> bool:
	if api_service and api_service.has_method("is_request_in_progress"):
		return api_service.is_request_in_progress()
	return false

func get_messages_for_thread(thread_name: String) -> Array:
	"""
	Safely retrieves the messages for a given thread.
	If the thread doesn't exist, it will be created.
	"""
	var thread = _get_or_create_thread(thread_name)
	if thread and thread.has("messages"):
		return thread.messages
	return []
