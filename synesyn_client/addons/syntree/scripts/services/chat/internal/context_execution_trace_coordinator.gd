## Purpose: Build and persist privacy-safe Context Compiler execution traces.
extends RefCounted

var _run_counter: int = 0


func make_message(
	thread_scope: String,
	thread_id: String,
	message_index: int,
	role_id: String,
	content: String
) -> Dictionary:
	var timestamp: String = Time.get_datetime_string_from_system()
	return {
		"id": make_message_id(
			thread_scope,
			thread_id,
			message_index,
			role_id,
			timestamp
		),
		"role": role_id,
		"content": content,
		"timestamp": timestamp,
	}


func make_message_id(
	thread_scope: String,
	thread_id: String,
	message_index: int,
	role_id: String,
	timestamp: String
) -> String:
	var identity_text: String = "%s|%s|%d|%s|%s" % [
		thread_scope,
		thread_id,
		message_index,
		role_id,
		timestamp,
	]
	return "msg_%s" % identity_text.sha256_text().substr(0, 20)


func begin_run(
	compile_result: Dictionary,
	context_meta: Dictionary
) -> Dictionary:
	if not bool(compile_result.get("ok", false)):
		return {}
	_run_counter += 1
	var created_at: float = Time.get_unix_time_from_system()
	var run_seed: String = "%s|%s|%f|%d" % [
		str(context_meta.get("thread_scope", "")),
		str(context_meta.get("thread_id", "")),
		created_at,
		_run_counter,
	]
	var compiled_text: String = str(
		compile_result.get("compiled_text", "")
	)
	var prompt_chain_id: String = str(
		compile_result.get("prompt_chain_id", "")
	)
	return {
		"schema_version": 1,
		"run_id": "ctxrun_%s" % run_seed.sha256_text().substr(0, 24),
		"created_at": created_at,
		"thread_scope": str(context_meta.get("thread_scope", "")),
		"thread_id": str(context_meta.get("thread_id", "")),
		"context_path": (
			"prompt_chain_binding"
			if not prompt_chain_id.is_empty()
			else "context_compiler"
		),
		"graph_artifact_id": str(
			compile_result.get("graph_artifact_id", "")
		),
		"graph_version_id": str(
			compile_result.get("graph_version_id", "")
		),
		"context_set_id": str(
			compile_result.get("context_set_id", "")
		),
		"prompt_chain_id": prompt_chain_id,
		"prompt_chain_block_id": str(
			compile_result.get("prompt_chain_block_id", "")
		),
		"model_id": str(context_meta.get(
			"model_id",
			compile_result.get("model_id", "")
		)),
		"provider_id": str(context_meta.get("provider_id", "")),
		"estimator_id": str(compile_result.get("estimator_id", "")),
		"policy": (
			compile_result.get("policy", {}) as Dictionary
		).duplicate(true),
		"included_nodes": (
			compile_result.get("included_nodes", []) as Array
		).duplicate(true),
		"omitted_nodes": (
			compile_result.get("omitted_nodes", []) as Array
		).duplicate(true),
		"estimated_tokens": int(
			compile_result.get("estimated_tokens", 0)
		),
		"token_budget": int(compile_result.get("token_budget", 0)),
		"compiled_text_hash": compiled_text.sha256_text(),
		"message_refs": {
			"user_message_id": str(
				context_meta.get("user_message_id", "")
			),
			"user_index": int(context_meta.get("user_index", -1)),
			"assistant_message_id": "",
			"assistant_index": -1,
		},
		"store_trace_id": str(context_meta.get("store_trace_id", "")),
		"store_context_pack_id": str(
			context_meta.get("store_context_pack_id", "")
		),
		"status": "pending_response",
	}


func begin_for_chat(
	manager: Object,
	thread_id: String,
	user_message: Dictionary,
	user_index: int,
	model_manager: Object,
	model_override: String
) -> Dictionary:
	var model_id: String = model_override.strip_edges()
	if (
		model_id.is_empty()
		and is_instance_valid(model_manager)
		and model_manager.has_method("get_current_model")
	):
		model_id = str(model_manager.call("get_current_model"))
	var provider_id: String = ""
	if (
		is_instance_valid(model_manager)
		and model_manager.has_method("get_provider_for_model")
	):
		provider_id = str(model_manager.call(
			"get_provider_for_model",
			model_id
		))
	var store_meta: Dictionary = {}
	if manager.has_method("get_latest_stfx_store_context_meta"):
		store_meta = manager.call(
			"get_latest_stfx_store_context_meta"
		)
	return begin_run(manager.get_meta(
		"last_context_compile_result",
		{}
	), {
		"thread_scope": str(manager.get("thread_scope")),
		"thread_id": thread_id,
		"user_message_id": str(user_message.get("id", "")),
		"user_index": user_index,
		"model_id": model_id,
		"provider_id": provider_id,
		"store_trace_id": str(store_meta.get("trace_id", "")),
		"store_context_pack_id": str(
			store_meta.get("context_pack_id", "")
		),
	})


func finalize_run(
	trace: Dictionary,
	response_meta: Dictionary
) -> Dictionary:
	if trace.is_empty():
		return {}
	var finalized: Dictionary = trace.duplicate(true)
	var message_refs: Dictionary = finalized.get("message_refs", {})
	message_refs["assistant_message_id"] = str(
		response_meta.get("assistant_message_id", "")
	)
	message_refs["assistant_index"] = int(
		response_meta.get("assistant_index", -1)
	)
	finalized["message_refs"] = message_refs
	finalized["status"] = str(response_meta.get("status", "completed"))
	if response_meta.has("error"):
		finalized["error"] = str(response_meta.get("error", ""))
	finalized["hub_artifact_ids"] = (
		response_meta.get("hub_artifact_ids", {}) as Dictionary
	).duplicate(true)
	return finalized


func complete(
	manager: Object,
	hub_client: Object,
	trace: Dictionary,
	response_meta: Dictionary
) -> void:
	var finalized: Dictionary = finalize_run(trace, response_meta)
	if finalized.is_empty():
		return
	var runtime_trace: Dictionary = finalized.duplicate(true)
	var compile_result: Dictionary = manager.get_meta(
		"last_context_compile_result",
		{}
	)
	runtime_trace["runtime_compiled_text"] = str(
		compile_result.get("compiled_text", "")
	)
	manager.set_meta("latest_context_execution_trace", runtime_trace)
	Callable(self, "_persist_and_update").call_deferred(
		manager,
		hub_client,
		finalized
	)


func _persist_and_update(
	manager: Object,
	hub_client: Object,
	trace: Dictionary
) -> void:
	var result: Dictionary = await persist(hub_client, trace)
	if (
		bool(result.get("ok", false))
		or not str(result.get("id", "")).is_empty()
	):
		manager.remove_meta("last_context_trace_persistence_warning")
		manager.set_meta(
			"latest_context_execution_trace_artifact_id",
			str(result.get("id", result.get("artifact_id", "")))
		)
		return
	manager.set_meta(
		"last_context_trace_persistence_warning",
		str(result.get("error", "trace_persistence_failed"))
	)


func persist(hub_client: Object, trace: Dictionary) -> Dictionary:
	if (
		not is_instance_valid(hub_client)
		or not hub_client.has_method("create_artifact_inline_json")
	):
		return {"ok": false, "error": "hub_client_unavailable"}
	var metadata: Dictionary = {
		"provenance": {
			"generated_by": "syntree.context_execution_trace",
			"source_artifacts": [{
				"artifact_type": "ui.context_graph",
				"artifact_id": str(trace.get("graph_artifact_id", "")),
				"version_id": str(trace.get("graph_version_id", "")),
			}],
		},
		"refs": {
			"thread_scope": str(trace.get("thread_scope", "")),
			"thread_id": str(trace.get("thread_id", "")),
			"run_id": str(trace.get("run_id", "")),
		},
	}
	return await hub_client.call(
		"create_artifact_inline_json",
		"json.context_execution_trace",
		trace,
		metadata
	)
