## Purpose: Internal helper for ConversationManager Hub thread index/versioning/sync (v1 substrate mapping).
extends RefCounted

const HUB_INDEX_SCHEMA_VERSION := 1

func _to_abs_path(p: String) -> String:
	var s := String(p).strip_edges().replace("\\", "/")
	if s.is_empty():
		return ""
	if s.begins_with("res://") or s.begins_with("user://"):
		return ProjectSettings.globalize_path(s)
	return s

func _ensure_dir(path: String) -> bool:
	var p := String(path).strip_edges().replace("\\", "/")
	if p.is_empty():
		return false
	var abs := _to_abs_path(p)
	if abs.is_empty():
		return false
	var err := DirAccess.make_dir_recursive_absolute(abs)
	return err == OK

func hub_index_path(threads_dir: String) -> String:
	return String(threads_dir).strip_edges().path_join("_hub_index.json")

func load_hub_index(threads_dir: String) -> Dictionary:
	var p := hub_index_path(threads_dir)
	if not FileAccess.file_exists(p):
		return {"schema_version": HUB_INDEX_SCHEMA_VERSION, "threads": {}}
	var raw := FileAccess.get_file_as_string(p)
	if raw.strip_edges().is_empty():
		return {"schema_version": HUB_INDEX_SCHEMA_VERSION, "threads": {}}
	var any: Variant = JSON.parse_string(raw)
	if typeof(any) != TYPE_DICTIONARY:
		return {"schema_version": HUB_INDEX_SCHEMA_VERSION, "threads": {}}
	var d: Dictionary = any
	if not d.has("threads") or typeof(d.get("threads")) != TYPE_DICTIONARY:
		d["threads"] = {}
	if not d.has("schema_version"):
		d["schema_version"] = HUB_INDEX_SCHEMA_VERSION
	return d

func save_hub_index(threads_dir: String, idx: Dictionary) -> bool:
	var td := String(threads_dir).strip_edges()
	if td.is_empty():
		return false
	# Ensure directory exists (supports user:// and absolute override roots).
	if not _ensure_dir(td):
		return false
	var f := FileAccess.open(hub_index_path(td), FileAccess.WRITE)
	if not f:
		return false
	f.store_string(JSON.stringify(idx, "\t"))
	f.close()
	return true

func record_thread_hub_version(threads_dir: String, thread_id: String, artifact_id: String) -> void:
	var aid := String(artifact_id).strip_edges()
	if aid.is_empty():
		return
	var tid := String(thread_id).strip_edges()
	if tid.is_empty():
		return

	var idx := load_hub_index(threads_dir)
	var threads: Dictionary = idx.get("threads", {})
	var info_any: Variant = threads.get(tid, {})
	var info: Dictionary = info_any if typeof(info_any) == TYPE_DICTIONARY else {}
	var versions_any: Variant = info.get("versions", [])
	var versions: Array = versions_any if typeof(versions_any) == TYPE_ARRAY else []
	if not versions.has(aid):
		versions.append(aid)
	info["versions"] = versions
	info["latest_artifact_id"] = aid
	threads[tid] = info
	idx["threads"] = threads
	save_hub_index(threads_dir, idx)

func persist_thread_version_to_hub(hub: Object, thread_scope: String, hub_session_id: String, threads_dir: String, threads: Dictionary, thread_id: String) -> Dictionary:
	if not is_instance_valid(hub):
		return {"ok": false, "error": "Hub client not available"}
	var tid := String(thread_id).strip_edges()
	if tid.is_empty():
		return {"ok": false, "error": "thread_id is required"}

	# Reachability probe
	if hub.has_method("check_health"):
		var health: Dictionary = await hub.check_health()
		if not bool(health.get("ok", false)):
			return {"ok": false, "error": "Hub not reachable"}

	var thread: Dictionary = threads.get(tid, {})
	var messages_any: Variant = thread.get("messages", [])
	var messages: Array = messages_any if typeof(messages_any) == TYPE_ARRAY else []

	var idx := load_hub_index(threads_dir)
	var idx_threads: Dictionary = idx.get("threads", {})
	var info_any: Variant = idx_threads.get(tid, {})
	var info: Dictionary = info_any if typeof(info_any) == TYPE_DICTIONARY else {}
	var prev_id := str(info.get("latest_artifact_id", "")).strip_edges()

	var now := float(Time.get_unix_time_from_system())
	var hub_session_id_val: Variant = null
	if not String(hub_session_id).strip_edges().is_empty():
		hub_session_id_val = String(hub_session_id).strip_edges()
	var prev_artifact_id_val: Variant = null
	if not prev_id.is_empty():
		prev_artifact_id_val = prev_id
	var inline_json := {
		"schema_version": 1,
		"scope": String(thread_scope).strip_edges(),
		"thread_id": tid,
		"session_id": hub_session_id_val,
		"messages": messages,
		"updated_at": now,
		"prev_artifact_id": prev_artifact_id_val,
	}
	var metadata := {
		"provenance": {"generated_by": "syntree.conversation_manager"},
		"refs": {"thread_id": tid, "scope": String(thread_scope).strip_edges(), "session_id": String(hub_session_id).strip_edges()},
	}

	if not hub.has_method("create_artifact_inline_json"):
		return {"ok": false, "error": "Hub client missing create_artifact_inline_json"}
	var res: Dictionary = await hub.create_artifact_inline_json("chat.thread", inline_json, metadata)
	var aid := ""
	if bool(res.get("ok", false)):
		aid = str(res.get("id", ""))
	elif res.has("id"):
		aid = str(res.get("id", ""))
	elif res.has("artifact_id"):
		aid = str(res.get("artifact_id", ""))
	if aid.strip_edges().is_empty():
		return {"ok": false, "error": "Failed to create artifact", "details": str(res.get("error", ""))}

	record_thread_hub_version(threads_dir, tid, aid)
	return {"ok": true, "artifact_id": aid}

func sync_threads_from_hub(hub: Object, thread_scope: String, hub_session_id: String, threads_dir: String, threads: Dictionary, thread_loaded_cb: Callable, conversation_updated_cb: Callable) -> void:
	if not is_instance_valid(hub):
		return
	# Reachability probe
	if hub.has_method("check_health"):
		var health: Dictionary = await hub.check_health()
		if not bool(health.get("ok", false)):
			return

	var idx := load_hub_index(threads_dir)
	var threads_any: Variant = idx.get("threads", {})
	if typeof(threads_any) != TYPE_DICTIONARY:
		return
	var idx_threads: Dictionary = threads_any
	for tid_any in idx_threads.keys():
		var tid := str(tid_any).strip_edges()
		if tid.is_empty():
			continue
		var info_any: Variant = idx_threads.get(tid, {})
		if typeof(info_any) != TYPE_DICTIONARY:
			continue
		var info: Dictionary = info_any
		var latest := str(info.get("latest_artifact_id", "")).strip_edges()
		if latest.is_empty():
			continue
		if not hub.has_method("get_artifact_json"):
			continue
		var res: Dictionary = await hub.get_artifact_json(latest)
		if not bool(res.get("ok", false)):
			continue
		var any: Variant = res.get("json", {})
		if typeof(any) != TYPE_DICTIONARY:
			continue
		var j: Dictionary = any
		var msgs_any: Variant = j.get("messages", [])
		if typeof(msgs_any) != TYPE_ARRAY:
			continue
		threads[tid] = {
			"name": tid,
			"_thread_id": tid,
			"messages": msgs_any,
			"last_updated": Time.get_unix_time_from_system(),
		}
		if thread_loaded_cb.is_valid():
			thread_loaded_cb.call(tid)
		if conversation_updated_cb.is_valid():
			conversation_updated_cb.call(tid)

func get_thread_hub_info(threads_dir: String, thread_id: String) -> Dictionary:
	var tid := String(thread_id).strip_edges()
	if tid.is_empty():
		return {}
	var idx := load_hub_index(threads_dir)
	var threads_any: Variant = idx.get("threads", {})
	if typeof(threads_any) != TYPE_DICTIONARY:
		return {}
	var threads: Dictionary = threads_any
	var info_any: Variant = threads.get(tid, {})
	return info_any if typeof(info_any) == TYPE_DICTIONARY else {}

func load_thread_from_hub_version(
		hub: Object,
		thread_scope: String,
		hub_session_id: String,
		threads_dir: String,
		threads: Dictionary,
		thread_id: String,
		artifact_id: String,
		get_or_create_thread_cb: Callable,
		save_thread_cb: Callable,
		thread_loaded_cb: Callable,
		conversation_updated_cb: Callable
	) -> Dictionary:
	if not is_instance_valid(hub):
		return {"success": false, "error": "Hub client not available"}
	var tid := String(thread_id).strip_edges()
	if tid.is_empty():
		return {"success": false, "error": "thread_id is required"}
	var aid := String(artifact_id).strip_edges()
	if aid.is_empty():
		return {"success": false, "error": "artifact_id is required"}

	# Reachability probe
	if hub.has_method("check_health"):
		var health: Dictionary = await hub.check_health()
		if not bool(health.get("ok", false)):
			return {"success": false, "error": "Hub not reachable"}
	if not hub.has_method("get_artifact_json"):
		return {"success": false, "error": "Hub client missing get_artifact_json"}
	var res: Dictionary = await hub.get_artifact_json(aid)
	if not bool(res.get("ok", false)):
		return {"success": false, "error": "Failed to load artifact", "details": str(res.get("error", ""))}
	var any: Variant = res.get("json", {})
	if typeof(any) != TYPE_DICTIONARY:
		return {"success": false, "error": "Artifact JSON is not a dictionary"}
	var j: Dictionary = any
	var msgs_any: Variant = j.get("messages", [])
	if typeof(msgs_any) != TYPE_ARRAY:
		return {"success": false, "error": "Artifact JSON has no messages[]"}
	var msgs: Array = msgs_any

	# Apply to local in-memory thread and persist locally
	var thread: Dictionary = {}
	if get_or_create_thread_cb.is_valid():
		thread = get_or_create_thread_cb.call(tid)
	if thread.is_empty():
		thread = threads.get(tid, {})
	if thread.is_empty():
		thread = {"name": tid, "_thread_id": tid, "messages": [], "last_updated": Time.get_unix_time_from_system()}
		threads[tid] = thread
	thread["messages"] = msgs
	thread["last_updated"] = Time.get_unix_time_from_system()

	if save_thread_cb.is_valid():
		var save_res: Dictionary = save_thread_cb.call(tid)
		if not bool(save_res.get("success", false)):
			return {"success": false, "error": "Failed to save thread locally after import"}

	# Record this version in hub index (so it appears in the versions list)
	record_thread_hub_version(threads_dir, tid, aid)

	if thread_loaded_cb.is_valid():
		thread_loaded_cb.call(tid)
	if conversation_updated_cb.is_valid():
		conversation_updated_cb.call(tid)
	return {"success": true}


