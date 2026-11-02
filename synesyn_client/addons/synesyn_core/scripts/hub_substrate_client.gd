extends HubSubstrateTransport
class_name HubSubstrateClient

# Typed endpoint facade for the Synesyn hub.
#
# All connection/transport plumbing (HTTP verbs, WebSocket loop, retry policy,
# auth, signals, state) lives in the `HubSubstrateTransport` base class. This
# file only contains the domain endpoint wrappers grouped by hub area
# (substrate artifacts/events/queries, stfx store & memory, ScenSyn
# continuity & verse, closure algebra, render, jobs). Callers instantiate this
# class and get the full API via inheritance.

func configure_from_runtime_config() -> void:
	var cfg: Dictionary = RuntimeConfig.load_config()
	# Centralize base URL interpretation and normalization (e.g. "localhost" -> "127.0.0.1").
	# This avoids IPv6 loopback edge cases on Windows when the hub binds only to 127.0.0.1.
	base_url = str(ProviderModePolicy.get_hub_base_url(cfg)).strip_edges()

	var hub_cfg_any: Variant = cfg.get("hub", {})
	if typeof(hub_cfg_any) == TYPE_DICTIONARY:
		var hub_cfg: Dictionary = hub_cfg_any
		var auth_any: Variant = hub_cfg.get("auth", {})
		if typeof(auth_any) == TYPE_DICTIONARY:
			var a: Dictionary = auth_any
			auth_enabled = bool(a.get("enabled", false))
			auth_token = str(a.get("token", "")).strip_edges()
		else:
			auth_enabled = false
			auth_token = ""
	# If base_url changes, next ws connect will use it.
	_ws_url = ""

func create_artifact_inline_json(artifact_type: String, inline_json: Dictionary, metadata: Dictionary = {}) -> Dictionary:
	# Backward-compatible:
	# - Newer hubs accept inline_json and store it server-side.
	# - Older hubs require uri+hash and reject inline_json with HTTP 422 validation errors.
	var payload := {
		"artifact_type": artifact_type,
		"inline_json": inline_json,
		"metadata": metadata,
	}
	var url := base_url.rstrip("/") + "/substrate/artifacts"
	var res: Dictionary = await _post_json(url, payload)
	if bool(res.get("ok", false)):
		return res

	# Detect old-hub validation shape: {"ok": false, "error": {"status": 422, "body": {...}}}
	var err_any: Variant = res.get("error", null)
	if typeof(err_any) == TYPE_DICTIONARY:
		var err: Dictionary = err_any
		var status := int(err.get("status", 0))
		var body_any: Variant = err.get("body", null)
		var body: Dictionary = body_any if typeof(body_any) == TYPE_DICTIONARY else {}
		if status == 422 and _body_mentions_missing_uri_hash(body):
			# Fall back to file-backed artifact creation in the hub workspace.
			var fb: Dictionary = await _create_artifact_via_workspace_file(artifact_type, inline_json, metadata)
			if bool(fb.get("ok", false)):
				return fb
	return res

func create_artifact_inline_bytes_base64(artifact_type: String, bytes: PackedByteArray, ext: String, metadata: Dictionary = {}) -> Dictionary:
	var payload := {
		"artifact_type": artifact_type,
		"inline_bytes_base64": Marshalls.raw_to_base64(bytes),
		"ext": ext,
		"metadata": metadata,
	}
	return await _post_json(base_url.rstrip("/") + "/substrate/artifacts", payload)

func create_artifact_inline_text(artifact_type: String, text: String, metadata: Dictionary = {}) -> Dictionary:
	# Convenience wrapper for text artifacts (stored as bytes with ext=txt).
	var bytes := text.to_utf8_buffer()
	return await create_artifact_inline_bytes_base64(artifact_type, bytes, "txt", metadata)

func delete_artifact(artifact_id: String, delete_file: bool = true) -> Dictionary:
	var aid := String(artifact_id).strip_edges()
	if aid.is_empty():
		return {"ok": false, "error": "artifact_id is required"}
	var url := base_url.rstrip("/") + "/substrate/artifacts/" + aid
	url += "?delete_file=%s" % ("true" if bool(delete_file) else "false")
	return await _delete_json(url)

func update_artifact_metadata(artifact_id: String, metadata_patch: Dictionary, merge: bool = true) -> Dictionary:
	var aid := String(artifact_id).strip_edges()
	if aid.is_empty():
		return {"ok": false, "error": "artifact_id is required"}
	var url := base_url.rstrip("/") + "/substrate/artifacts/" + aid + "/metadata"
	var payload := {"metadata": metadata_patch, "merge": bool(merge)}
	return await _patch_json(url, payload)

func create_context_graph_bridge(context_graph_artifact_id: String, metadata: Dictionary = {}) -> Dictionary:
	# Bridge artifact for cross-app auditability: store a reference to a ui.context_graph artifact id.
	# This is distinct from thread bridge artifacts (chat.thread).
	var cg := String(context_graph_artifact_id).strip_edges()
	if cg.is_empty():
		return {"ok": false, "error": "context_graph_artifact_id is required"}
	var payload := {
		"schema_version": 1,
		"context_graph_artifact_id": cg,
		"created_at": Time.get_unix_time_from_system(),
	}
	return await create_artifact_inline_json("bridge.ui_context_graph", payload, metadata)

func resolve_context_graph_bridge(bridge_artifact_id: String) -> Dictionary:
	var bid := String(bridge_artifact_id).strip_edges()
	if bid.is_empty():
		return {"ok": false, "error": "bridge_artifact_id is required"}
	var res: Dictionary = await get_artifact_json(bid)
	if not bool(res.get("ok", false)):
		return res
	var js: Dictionary = res.get("json", {})
	var cg := str(js.get("context_graph_artifact_id", "")).strip_edges()
	if cg.is_empty():
		return {"ok": false, "error": "Bridge artifact missing context_graph_artifact_id", "artifact_id": bid}
	return {"ok": true, "context_graph_artifact_id": cg, "bridge_artifact_id": bid, "record": res.get("record", {})}

func create_event(event_type: String, payload: Dictionary, provenance: Dictionary = {}, source_id: String = "synaxes", seq: int = 0, session_id: String = "") -> Dictionary:
	var evt := {
		"event_type": event_type,
		"source_id": source_id,
		"seq": seq,
		"t_received": Time.get_unix_time_from_system(),
		"payload": payload,
		"provenance": provenance,
	}
	var sid := String(session_id).strip_edges()
	if not sid.is_empty():
		evt["session_id"] = sid
	return await _post_json(base_url.rstrip("/") + "/substrate/events", evt)

func create_event_fire_and_forget(event_type: String, payload: Dictionary, provenance: Dictionary = {}, source_id: String = "synaxes", seq: int = 0, session_id: String = "") -> void:
	# Non-awaiting variant for UI code paths where we don't want to block, and
	# where calling the async create_event() would raise:
	# "Trying to call an async function without 'await'."
	var evt := {
		"event_type": event_type,
		"source_id": source_id,
		"seq": seq,
		"t_received": Time.get_unix_time_from_system(),
		"payload": payload,
		"provenance": provenance,
	}
	var sid := String(session_id).strip_edges()
	if not sid.is_empty():
		evt["session_id"] = sid

	var url := base_url.rstrip("/") + "/substrate/events"
	var headers := ["Content-Type: application/json"]
	if auth_enabled and not auth_token.is_empty():
		headers.append("Authorization: Bearer %s" % auth_token)
	var body := JSON.stringify(evt)

	var http := HTTPRequest.new()
	http.timeout = 6.0
	add_child(http)
	_disable_proxy_for_local(http, url)
	http.request_completed.connect(func(_result: int, _code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
		if is_instance_valid(http):
			http.queue_free()
	)
	var err := http.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		http.queue_free()
		request_failed.emit("HTTPRequest.request failed: %s" % error_string(err))

func set_session_consent_save_recordings(session_id: String, enabled: bool) -> Dictionary:
	# v0 consent gate: enables saving `audio.input` when calling /voice/transcribe with save_recordings=true.
	var sid := String(session_id).strip_edges()
	if sid.is_empty():
		return {"ok": false, "error": "session_id is required"}
	var payload := {"save_recordings": bool(enabled)}
	return await _post_json(base_url.rstrip("/") + "/substrate/sessions/%s/consent" % sid, payload)

func get_workspace_root() -> String:
	return await _get_workspace_root()

func stfx_ingest_document(md_path: String, parse_strategy: String = "headings") -> Dictionary:
	var payload := {
		"md_path": str(md_path).strip_edges(),
		"parse_strategy": str(parse_strategy).strip_edges(),
	}
	return await _post_json(base_url.rstrip("/") + "/stfx-memory/documents/ingest", payload)

func stfx_get_document(document_id: String) -> Dictionary:
	var did := String(document_id).strip_edges()
	if did.is_empty():
		return {"ok": false, "error": "document_id is required"}
	return await _get_json(base_url.rstrip("/") + "/stfx-memory/documents/" + did)

func stfx_store_status() -> Dictionary:
	return await _get_json(base_url.rstrip("/") + "/stfx-store/status")

func stfx_store_update_config(
	enabled: Variant = null,
	accelerators: Dictionary = {},
	admissibility: Variant = null
) -> Dictionary:
	var payload := {"accelerators": accelerators}
	if enabled != null:
		payload["enabled"] = bool(enabled)
	if typeof(admissibility) == TYPE_DICTIONARY:
		payload["admissibility"] = admissibility
	return await _post_json(base_url.rstrip("/") + "/stfx-store/config", payload)

func stfx_store_list_memories() -> Dictionary:
	return await _get_json(base_url.rstrip("/") + "/stfx-store/memories")

func stfx_store_list_closures() -> Dictionary:
	return await _get_json(base_url.rstrip("/") + "/stfx-store/closures")

func stfx_store_list_context_packs() -> Dictionary:
	return await _get_json(base_url.rstrip("/") + "/stfx-store/context-packs")

func stfx_store_get_context_pack(context_pack_id: String) -> Dictionary:
	var cpid := String(context_pack_id).strip_edges()
	if cpid.is_empty():
		return {"ok": false, "error": "context_pack_id is required"}
	return await _get_json(base_url.rstrip("/") + "/stfx-store/context-packs/" + cpid)

func stfx_store_get_trace(trace_id: String) -> Dictionary:
	var tid := String(trace_id).strip_edges()
	if tid.is_empty():
		return {"ok": false, "error": "trace_id is required"}
	return await _get_json(base_url.rstrip("/") + "/stfx-store/traces/" + tid)

func stfx_store_get_index(index_name: String) -> Dictionary:
	var idx_name := String(index_name).strip_edges()
	if idx_name.is_empty():
		return {"ok": false, "error": "index_name is required"}
	return await _get_json(base_url.rstrip("/") + "/stfx-store/indexes/" + idx_name)

func stfx_store_get_chunk(chunk_id: String) -> Dictionary:
	var cid := String(chunk_id).strip_edges()
	if cid.is_empty():
		return {"ok": false, "error": "chunk_id is required"}
	return await _get_json(base_url.rstrip("/") + "/stfx-store/chunks/" + cid)

func stfx_store_update_chunk_symbolic(chunk_id: String, symbolic: Dictionary, repair_note: String = "") -> Dictionary:
	var cid := String(chunk_id).strip_edges()
	if cid.is_empty():
		return {"ok": false, "error": "chunk_id is required"}
	var payload := {
		"symbolic": symbolic,
		"repair_note": String(repair_note).strip_edges(),
	}
	return await _post_json(base_url.rstrip("/") + "/stfx-store/chunks/" + cid + "/symbolic", payload)

func stfx_store_validate() -> Dictionary:
	return await _post_json(base_url.rstrip("/") + "/stfx-store/validate", {})

func stfx_store_repair_report() -> Dictionary:
	return await _post_json(base_url.rstrip("/") + "/stfx-store/repair/report", {})

func stfx_store_rebuild_indexes() -> Dictionary:
	return await _post_json(base_url.rstrip("/") + "/stfx-store/indexes/rebuild", {})

func stfx_store_ingest_source(source_path: String, default_seed: String = "primary") -> Dictionary:
	var source_path_clean := String(source_path).strip_edges()
	if source_path_clean.is_empty():
		return {"ok": false, "error": "source_path is required"}
	var payload := {
		"source_path": source_path_clean,
		"default_seed": String(default_seed).strip_edges(),
	}
	return await _post_json(base_url.rstrip("/") + "/stfx-store/sources/ingest", payload)

func stfx_store_retrieve(
	query: String,
	active_source_ids: Array[String] = [],
	seed_family: String = "",
	top_k: int = 5,
	expansion_depth: int = 1
) -> Dictionary:
	var query_text := String(query).strip_edges()
	if query_text.is_empty():
		return {"ok": false, "error": "query is required"}
	var payload := {
		"query": query_text,
		"active_source_ids": active_source_ids,
		"seed_family": String(seed_family).strip_edges(),
		"top_k": int(top_k),
		"expansion_depth": int(expansion_depth),
	}
	return await _post_json(base_url.rstrip("/") + "/stfx-store/retrieve", payload)

func stfx_store_commit_artifact(artifact_type: String, payload: Dictionary, provenance: Dictionary = {}) -> Dictionary:
	var atype := String(artifact_type).strip_edges()
	if atype.is_empty():
		atype = "json.generic"
	var body := {
		"artifact_type": atype,
		"payload": payload,
		"provenance": provenance,
	}
	return await _post_json(base_url.rstrip("/") + "/stfx-store/artifacts/commit", body)

func stfx_store_commit_context_graph(graph: Dictionary, provenance: Dictionary = {}) -> Dictionary:
	var body := {
		"graph": graph,
		"provenance": provenance,
	}
	return await _post_json(base_url.rstrip("/") + "/stfx-store/context-graphs/commit", body)

func stfx_store_commit_memory(payload: Dictionary, provenance: Dictionary = {}) -> Dictionary:
	var body := {
		"payload": payload,
		"provenance": provenance,
	}
	return await _post_json(base_url.rstrip("/") + "/stfx-store/memories/commit", body)

func stfx_store_commit_closure(payload: Dictionary, provenance: Dictionary = {}) -> Dictionary:
	var body := {
		"payload": payload,
		"provenance": provenance,
	}
	return await _post_json(base_url.rstrip("/") + "/stfx-store/closures/commit", body)

func stfx_store_export_legacy_memory() -> Dictionary:
	return await _post_json(base_url.rstrip("/") + "/stfx-store/migrations/stfx-memory/export", {})

func stfx_store_export_syntree_context_graphs() -> Dictionary:
	return await _post_json(base_url.rstrip("/") + "/stfx-store/migrations/syntree-context-graphs/export", {})

func stfx_store_export_substrate_artifacts() -> Dictionary:
	return await _post_json(base_url.rstrip("/") + "/stfx-store/migrations/substrate-artifacts/export", {})

func scensyn_get_continuity_state(document_id: String, chunk_path: String = "", depth: int = 2, sibling_window: int = 2) -> Dictionary:
	var payload := {
		"document_id": str(document_id).strip_edges(),
		"chunk_path": str(chunk_path).strip_edges(),
		"depth": int(depth),
		"sibling_window": int(sibling_window),
	}
	return await _post_json(base_url.rstrip("/") + "/scensyn/continuity-state/from-memory", payload)

func scensyn_get_continuity_state_from_store_context(context_pack_id: String, commit_artifact: bool = true, session_id: String = "") -> Dictionary:
	var cpid := String(context_pack_id).strip_edges()
	if cpid.is_empty():
		return {"ok": false, "error": "context_pack_id is required"}
	var payload := {
		"context_pack_id": cpid,
		"commit_artifact": bool(commit_artifact),
		"session_id": String(session_id).strip_edges(),
	}
	return await _post_json(base_url.rstrip("/") + "/scensyn/continuity-state/from-store-context", payload)

func scensyn_build_vis_story_cycle(continuity_state: Dictionary, cycle_id: int = 1, scenario_context: Dictionary = {}) -> Dictionary:
	var payload := {
		"continuity_state": continuity_state,
		"cycle_id": int(cycle_id),
		"scenario_context": scenario_context,
	}
	return await _post_json(base_url.rstrip("/") + "/scensyn/vis-story-cycle/from-continuity", payload)

func scensyn_build_vis_story_v2_cycle(
	continuity_state: Dictionary,
	cycle_id: int = 1,
	scenario_context: Dictionary = {},
	max_panels_per_turn: int = 12,
	panels_to_render: int = 6,
	selection_mode: String = "spread",
	panel_indices: Array = [],
	max_concurrent_renders: int = 2,
) -> Dictionary:
	var payload := {
		"continuity_state": continuity_state,
		"cycle_id": int(cycle_id),
		"scenario_context": scenario_context,
		"max_panels_per_turn": int(max_panels_per_turn),
		"panels_to_render": int(panels_to_render),
		"selection_mode": String(selection_mode).strip_edges(),
		"panel_indices": panel_indices,
		"max_concurrent_renders": int(max_concurrent_renders),
	}
	return await _post_json(base_url.rstrip("/") + "/scensyn/vis-story-v2-cycle/from-continuity", payload)

func query_artifacts_by_type(artifact_type: String, limit: int = 50) -> Dictionary:
	var payload := {
		"table": "artifacts",
		"where": {"artifact_type": artifact_type},
		"limit": limit,
	}
	return await _post_json(base_url.rstrip("/") + "/substrate/query", payload)

func get_artifact_record_by_id(artifact_id: String) -> Dictionary:
	# Now supported by hub v1 query allowlist (where.id).
	var payload := {"table": "artifacts", "where": {"id": artifact_id}, "limit": 1}
	return await _post_json(base_url.rstrip("/") + "/substrate/query", payload)

func query_events_by_type(event_type: String, source_id: String = "", limit: int = 100) -> Dictionary:
	var where: Dictionary = {"event_type": event_type}
	if not source_id.is_empty():
		where["source_id"] = source_id
	var payload := {"table": "events", "where": where, "limit": limit}
	return await _post_json(base_url.rstrip("/") + "/substrate/query", payload)

func query_entities(entity_type: String = "", entity_name: String = "", limit: int = 50) -> Dictionary:
	var where: Dictionary = {}
	if not entity_type.is_empty():
		where["entity_type"] = entity_type
	if not entity_name.is_empty():
		where["name"] = entity_name
	var payload := {"table": "entities", "where": where, "limit": limit}
	return await _post_json(base_url.rstrip("/") + "/substrate/query", payload)

func query_relations(relation_type: String = "", from_entity_id: String = "", to_entity_id: String = "", limit: int = 50) -> Dictionary:
	var where: Dictionary = {}
	if not relation_type.is_empty():
		where["relation_type"] = relation_type
	if not from_entity_id.is_empty():
		where["from_entity_id"] = from_entity_id
	if not to_entity_id.is_empty():
		where["to_entity_id"] = to_entity_id
	var payload := {"table": "relations", "where": where, "limit": limit}
	return await _post_json(base_url.rstrip("/") + "/substrate/query", payload)

func submit_render(request: Dictionary) -> Dictionary:
	# Hub-submit render request (v1).
	# Endpoint: POST /render/submit
	# Payload: {request: <SynesynRenderRequestV1>}
	var url := base_url.rstrip("/") + "/render/submit"
	return await _post_json(url, {"request": request})

func submit_render_batch(request: Dictionary) -> Dictionary:
	# Hub-submit render batch request (generic multi-image fan-out).
	# Endpoint: POST /render/submit-batch
	# Payload: {request: <render batch payload>}
	var url := base_url.rstrip("/") + "/render/submit-batch"
	return await _post_json(url, {"request": request})

func render_list_jobs(limit: int = 50) -> Dictionary:
	var lim := maxi(1, mini(limit, 200))
	var url := "%s/render/jobs?limit=%d" % [base_url.rstrip("/"), lim]
	return await _get_json(url)

func render_get_job(job_id: String) -> Dictionary:
	var jid := String(job_id).strip_edges()
	if jid.is_empty():
		return {"ok": false, "error": "job_id is required"}
	var url := base_url.rstrip("/") + "/render/jobs/" + jid
	return await _get_json(url)

func render_cancel_job(job_id: String) -> Dictionary:
	var jid := String(job_id).strip_edges()
	if jid.is_empty():
		return {"ok": false, "error": "job_id is required"}
	var url := base_url.rstrip("/") + "/render/jobs/" + jid + "/cancel"
	return await _post_json(url, {})

func render_retry_job(job_id: String) -> Dictionary:
	var jid := String(job_id).strip_edges()
	if jid.is_empty():
		return {"ok": false, "error": "job_id is required"}
	var url := base_url.rstrip("/") + "/render/jobs/" + jid + "/retry"
	return await _post_json(url, {})

func create_entity(entity_type: String, entity_name: String = "", summary: String = "", tags: Array = [], metadata: Dictionary = {}) -> Dictionary:
	# Avoid incompatible ternary warnings by conditionally setting optional fields.
	var payload: Dictionary = {
		"entity_type": entity_type,
		"tags": tags,
		"metadata": metadata,
	}
	if not entity_name.is_empty():
		payload["name"] = entity_name
	if not summary.is_empty():
		payload["summary"] = summary
	return await _post_json(base_url.rstrip("/") + "/substrate/entities", payload)

func create_relation(relation_type: String, from_entity_id: String, to_entity_id: String, weight: float = 0.0, metadata: Dictionary = {}) -> Dictionary:
	# Avoid incompatible ternary warnings by conditionally setting optional fields.
	var payload: Dictionary = {
		"relation_type": relation_type,
		"from_entity_id": from_entity_id,
		"to_entity_id": to_entity_id,
		"metadata": metadata,
	}
	if not is_equal_approx(weight, 0.0):
		payload["weight"] = weight
	return await _post_json(base_url.rstrip("/") + "/substrate/relations", payload)

func check_health() -> Dictionary:
	# Simple reachability probe used by UI status indicators.
	return await _get_json(base_url.rstrip("/") + "/health")

func get_or_create_entity(entity_type: String, entity_name: String, summary: String = "", tags: Array = [], metadata: Dictionary = {}) -> Dictionary:
	# Best-effort id stability: reuse the most recent entity with (entity_type, name).
	var q: Dictionary = await query_entities(entity_type, entity_name, 1)
	if bool(q.get("ok", false)):
		var result: Dictionary = q.get("result", {})
		var cols: Array = result.get("columns", [])
		var rows: Array = result.get("rows", [])
		if rows.size() > 0 and typeof(rows[0]) == TYPE_ARRAY:
			var row: Array = rows[0]
			var ent_id := _row_get(cols, row, "id")
			if not ent_id.is_empty():
				return {"ok": true, "id": ent_id, "existing": true}
	# Create new
	var created: Dictionary = await create_entity(entity_type, entity_name, summary, tags, metadata)
	if not bool(created.get("ok", false)):
		return created
	return {"ok": true, "id": str(created.get("id", "")), "existing": false}

func get_artifact_record(artifact_id: String) -> Dictionary:
	var payload := {
		"table": "artifacts",
		"where": {"id": artifact_id},
		"limit": 1,
	}
	var res: Dictionary = await _post_json(base_url.rstrip("/") + "/substrate/query", payload)
	if not bool(res.get("ok", false)):
		return res
	var result: Dictionary = res.get("result", {})
	var cols: Array = result.get("columns", [])
	var rows: Array = result.get("rows", [])
	if rows.is_empty():
		return {"ok": false, "error": "Artifact not found: %s" % artifact_id}
	var row_any: Variant = rows[0]
	if typeof(row_any) != TYPE_ARRAY:
		return {"ok": false, "error": "Invalid query row shape"}
	var row: Array = row_any
	var rec := {
		"id": _row_get(cols, row, "id"),
		"artifact_type": _row_get(cols, row, "artifact_type"),
		"uri": _row_get(cols, row, "uri"),
		"hash": _row_get(cols, row, "hash"),
		"created_at": _row_get(cols, row, "created_at"),
		"metadata_json": _row_get(cols, row, "metadata_json"),
	}
	return {"ok": true, "record": rec}

func load_artifact_json_from_uri(uri: String) -> Variant:
	# v0: hub uses file:// URIs for JSON artifacts; keep this robust on Windows.
	if not uri.begins_with("file:"):
		return null
	var path := uri
	# Replace file:/// with "/" so Linux absolute paths keep their leading slash.
	# file:///home/user/path → /home/user/path  (Linux)
	# file:///C:/path       → /C:/path          (Windows, normalized below)
	path = path.replace("file:///", "/")
	path = path.replace("file://", "")
	# Normalize Windows drive letter: /C:/path → C:/path
	if path.length() > 2 and path[0] == "/" and path[2] == ":":
		path = path.substr(1)
	if not FileAccess.file_exists(path):
		return null
	var lower := path.to_lower()
	# Guard: do not attempt to parse binary artifacts as JSON.
	# (Common case: TTS audio artifacts are .wav and begin with "RIFF".)
	var binary_exts := [".wav", ".mp3", ".ogg", ".flac", ".png", ".jpg", ".jpeg", ".webp", ".gif"]
	for ext in binary_exts:
		if lower.ends_with(ext):
			return null
	var raw := FileAccess.get_file_as_string(path)
	if raw.is_empty():
		return null
	# Extra guard (covers misnamed files): WAV starts with RIFF.
	if raw.begins_with("RIFF"):
		return null
	return JSON.parse_string(raw)

func get_artifact_json(artifact_id: String) -> Dictionary:
	var rec_res: Dictionary = await get_artifact_record(artifact_id)
	if not bool(rec_res.get("ok", false)):
		return rec_res
	var rec: Dictionary = rec_res.get("record", {})
	var uri := str(rec.get("uri", "")).strip_edges()
	if uri.is_empty():
		return {"ok": false, "error": "Artifact has no uri: %s" % artifact_id}
	var u_lower := uri.to_lower()
	if u_lower.ends_with(".wav") or u_lower.ends_with(".mp3") or u_lower.ends_with(".ogg") or u_lower.ends_with(".flac"):
		return {"ok": false, "error": "Artifact is audio, not JSON", "uri": uri, "record": rec}
	if u_lower.ends_with(".png") or u_lower.ends_with(".jpg") or u_lower.ends_with(".jpeg") or u_lower.ends_with(".webp") or u_lower.ends_with(".gif"):
		return {"ok": false, "error": "Artifact is an image, not JSON", "uri": uri, "record": rec}
	var any: Variant = load_artifact_json_from_uri(uri)
	if any == null:
		return {"ok": false, "error": "Failed to load artifact JSON from uri", "uri": uri}
	if typeof(any) != TYPE_DICTIONARY:
		return {"ok": false, "error": "Artifact JSON is not a dictionary", "uri": uri}
	return {"ok": true, "json": any, "uri": uri, "record": rec}

func submit_job(job_type: String, input: Dictionary, output_target: Dictionary = {}, metadata: Dictionary = {}) -> Dictionary:
	var payload := {
		"type": job_type,
		"input": input,
		"output_target": output_target,
		"metadata": metadata,
	}
	return await _post_json(base_url.rstrip("/") + "/jobs", payload)

func get_job(job_id: String) -> Dictionary:
	var url := base_url.rstrip("/") + "/jobs/" + job_id
	return await _get_json(url)

func poll_job_until_done(job_id: String, timeout_sec: float = 30.0, poll_interval_sec: float = 0.25) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var timeout_ms := int(timeout_sec * 1000.0)
	while true:
		var res: Dictionary = await get_job(job_id)
		if not bool(res.get("ok", false)):
			return res
		var job: Dictionary = res.get("job", {})
		var status := str(job.get("status", "")).strip_edges()
		if status in ["completed", "failed"]:
			return res
		if (Time.get_ticks_msec() - t0) > timeout_ms:
			return {"ok": false, "error": "Job timed out", "job_id": job_id}
		await get_tree().create_timer(poll_interval_sec).timeout
	# Analyzer guard (should be unreachable)
	return {"ok": false, "error": "unreachable"}

func await_job_done(job_id: String, timeout_sec: float = 30.0) -> Dictionary:
	# Prefer WS for progress; fall back to polling.
	var started := Time.get_ticks_msec()
	var timeout_ms := int(timeout_sec * 1000.0)
	var ws_ok := ensure_ws_connected()
	if not ws_ok:
		return await poll_job_until_done(job_id, timeout_sec, 0.25)

	while true:
		if (Time.get_ticks_msec() - started) > timeout_ms:
			return {"ok": false, "error": "Job timed out", "job_id": job_id}
		# Wait for a job_done signal that matches this job_id.
		var args: Array = await job_done
		if args.size() < 3:
			continue
		var jid := str(args[0])
		var status := str(args[1])
		var payload: Dictionary = args[2] if typeof(args[2]) == TYPE_DICTIONARY else {}
		if jid == job_id:
			return {"ok": true, "status": status, "payload": payload}
	# Analyzer guard (should be unreachable)
	return {"ok": false, "error": "unreachable"}

func _body_mentions_missing_uri_hash(body: Dictionary) -> bool:
	# FastAPI 422 body often looks like: {"detail":[{"loc":["body","uri"],...}, {"loc":["body","hash"],...}]}
	var detail_any: Variant = body.get("detail", null)
	if typeof(detail_any) != TYPE_ARRAY:
		return false
	var detail: Array = detail_any
	var missing_uri := false
	var missing_hash := false
	for item_any in detail:
		if typeof(item_any) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = item_any
		var loc_any: Variant = item.get("loc", null)
		if typeof(loc_any) != TYPE_ARRAY:
			continue
		var loc: Array = loc_any
		# Expect ["body","uri"] or ["body","hash"]
		if loc.size() >= 2 and str(loc[0]) == "body":
			var field := str(loc[1])
			if field == "uri":
				missing_uri = true
			elif field == "hash":
				missing_hash = true
	return missing_uri and missing_hash

func _create_artifact_via_workspace_file(artifact_type: String, inline_json: Dictionary, metadata: Dictionary) -> Dictionary:
	var root := await _get_workspace_root()
	if root.is_empty():
		return {"ok": false, "error": "Hub does not support inline_json and workspace root is not available (GET /workspace failed)."}

	# Compute artifacts dir from root (hub convention).
	var artifacts_dir := root.path_join("artifacts")
	var dir := DirAccess.open(artifacts_dir)
	if dir == null:
		DirAccess.make_dir_recursive_absolute(artifacts_dir)

	# Serialize JSON and compute sha256.
	var json_text := JSON.stringify(inline_json, "\t")
	var bytes: PackedByteArray = json_text.to_utf8_buffer()
	var hc := HashingContext.new()
	hc.start(HashingContext.HASH_SHA256)
	hc.update(bytes)
	var digest: PackedByteArray = hc.finish()
	var hex := digest.hex_encode()

	# Write file with stable-ish name.
	var safe_type := artifact_type.replace("/", "_").replace(":", "_")
	var ts := str(Time.get_unix_time_from_system())
	var filename := "%s_%s_%s.json" % [safe_type, ts, hex.substr(0, 8)]
	var abs_path := artifacts_dir.path_join(filename)
	var f := FileAccess.open(abs_path, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "error": "Failed to write artifact file to hub workspace artifacts dir", "path": abs_path}
	f.store_buffer(bytes)
	f.close()

	# Build file:// uri (normalize to forward slashes).
	# Linux: abs_path starts with /, so "file://" + "/home/..." = "file:///home/..." (3 slashes correct)
	# Windows: abs_path = "C:/...", so "file:///" + "C:/..." = "file:///C:/..." (3 slashes correct)
	var uri_path := abs_path.replace("\\", "/")
	var uri := ("file://" + uri_path) if uri_path.begins_with("/") else ("file:///" + uri_path)

	var payload := {
		"artifact_type": artifact_type,
		"uri": uri,
		"hash": hex,
		"metadata": metadata,
	}
	return await _post_json(base_url.rstrip("/") + "/substrate/artifacts", payload)

# ── Verse system endpoints ─────────────────────────────────────────────

func scensyn_verse_character_prompts(
	odu_name: String,
	turn_context: Dictionary,
	resonance: float = 0.5,
	complement_odu: String = "",
	stability: float = 0.5,
	crossings: int = 0,
	turn_seed: String = "",
) -> Dictionary:
	var payload := {
		"odu_name": odu_name,
		"resonance": resonance,
		"complement_odu": complement_odu,
		"stability": stability,
		"crossings": int(crossings),
		"turn_seed": turn_seed,
		"turn_context": turn_context,
	}
	return await _post_json(base_url.rstrip("/") + "/scensyn/verse/character-prompts", payload)

func scensyn_verse_seekers_journey_prompt(
	odu_name: String,
	turn_context: Dictionary,
	previous_paragraphs: Array = [],
	turn_number: int = 1,
	resonance: float = 0.5,
	complement_odu: String = "",
	stability: float = 0.5,
	crossings: int = 0,
	turn_seed: String = "",
) -> Dictionary:
	var payload := {
		"odu_name": odu_name,
		"resonance": resonance,
		"complement_odu": complement_odu,
		"stability": stability,
		"crossings": int(crossings),
		"turn_seed": turn_seed,
		"turn_context": turn_context,
		"previous_paragraphs": previous_paragraphs,
		"turn_number": int(turn_number),
	}
	return await _post_json(base_url.rstrip("/") + "/scensyn/verse/seekers-journey-prompt", payload)

func scensyn_verse_heartbeat(past_readings: Array = [], seed: String = "") -> Dictionary:
	var payload := {
		"past_readings": past_readings,
		"seed": seed,
	}
	return await _post_json(base_url.rstrip("/") + "/scensyn/verse/heartbeat", payload)

# ── Closure algebra (stfx_core via Hub /closure/*) ────────────────────────────
# Latent Reality closure operators shared across the Synesyn stack:
#   field   -> the un-collapsed superposition (proxistance / scale, set by depth)
#   collapse-> a determinate, provenanced manifestation (chosen by row index)
#   twin    -> the Ìbejì complement of a row (decentering)
# A seed is supplied either as an explicit binary matrix, or resolved from a
# pluggable lexicon (family or symbols). The kernel itself is culture-neutral.
func _closure_seed_payload(lexicon: String, family: String, depth: int, seed_matrix: Array, symbols: Array) -> Dictionary:
	var payload := {"depth": int(depth)}
	if not seed_matrix.is_empty():
		payload["seed_matrix"] = seed_matrix
	else:
		payload["lexicon"] = str(lexicon).strip_edges()
		if not symbols.is_empty():
			payload["symbols"] = symbols
		elif not family.is_empty():
			payload["family"] = str(family).strip_edges()
	return payload

func closure_lexicons() -> Dictionary:
	return await _get_json(base_url.rstrip("/") + "/closure/lexicons")

func closure_field(lexicon: String = "ifa_odu", family: String = "", depth: int = 3, seed_matrix: Array = [], symbols: Array = []) -> Dictionary:
	var payload := _closure_seed_payload(lexicon, family, depth, seed_matrix, symbols)
	return await _post_json(base_url.rstrip("/") + "/closure/field", payload)

func closure_collapse(index: int, lexicon: String = "ifa_odu", family: String = "", depth: int = 3, seed_matrix: Array = [], symbols: Array = []) -> Dictionary:
	var payload := _closure_seed_payload(lexicon, family, depth, seed_matrix, symbols)
	payload["index"] = int(index)
	return await _post_json(base_url.rstrip("/") + "/closure/collapse", payload)

func closure_twin(index: int, lexicon: String = "ifa_odu", family: String = "", depth: int = 3, seed_matrix: Array = [], symbols: Array = []) -> Dictionary:
	var payload := _closure_seed_payload(lexicon, family, depth, seed_matrix, symbols)
	payload["index"] = int(index)
	return await _post_json(base_url.rstrip("/") + "/closure/twin", payload)

func closure_neighbourhood(index: int, radius: int = 8, lexicon: String = "ifa_odu", family: String = "", depth: int = 3, seed_matrix: Array = [], symbols: Array = []) -> Dictionary:
	var payload := _closure_seed_payload(lexicon, family, depth, seed_matrix, symbols)
	payload["index"] = int(index)
	payload["radius"] = int(radius)
	return await _post_json(base_url.rstrip("/") + "/closure/neighbourhood", payload)

func _row_get(cols: Array, row: Array, col_name: String) -> String:
	var idx := cols.find(col_name)
	if idx == -1 or idx >= row.size():
		return ""
	return str(row[idx])
