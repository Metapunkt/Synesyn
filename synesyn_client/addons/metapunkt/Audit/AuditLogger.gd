extends Node
class_name AuditLogger

# Logs agent actions, decisions, errors.
# MUST include user_id from context when available.
# Implements SLOP /audit endpoint logic (or logs locally).

signal event_emitted(event: Dictionary)

@export var enable_jsonl: bool = true
@export var enable_hub_forwarding: bool = true
@export var hub_base_url: String = "http://127.0.0.1:17777"
@export var hub_source_id: String = "metapunkt"
@export var schema_version: int = 1
@export var app_id: String = "metapunkt"
@export var default_session_id: String = "" # optional; can be set by the host app
@export var default_turn_id: String = "" # optional; can be set by the host app

var _log_path: String = ""
var _http: HTTPRequest
var _seq: int = 0

func _log_dir() -> String:
	return RuntimeConfig.get_metapunkt_data_dir().path_join("logs") + "/"

func _ready():
	# Prefer Synesyn runtime config if available (keeps hub URL consistent across apps).
	# This is best-effort: Metapunkt can also run standalone.
	if ResourceLoader.exists("res://addons/synesyn_core/scripts/runtime_config.gd"):
		var cfg: Dictionary = RuntimeConfig.load_config()
		var hub_cfg_any: Variant = cfg.get("hub", {})
		if typeof(hub_cfg_any) == TYPE_DICTIONARY:
			var hub_cfg: Dictionary = hub_cfg_any
			var base_url := str(hub_cfg.get("base_url", "")).strip_edges()
			if not base_url.is_empty():
				hub_base_url = base_url

	if enable_jsonl:
		var log_dir: String = _log_dir()
		DirAccess.make_dir_recursive_absolute(log_dir)
		_log_path = "%saudit_%s.jsonl" % [log_dir, str(Time.get_unix_time_from_system())]
	if enable_hub_forwarding:
		_http = HTTPRequest.new()
		add_child(_http)

func log_event(event_type: String, data: Dictionary, user_id: String = ""):
	_seq += 1
	var t = Time.get_unix_time_from_system()
	var session_override := ""
	if data != null and data is Dictionary and data.has("session_id"):
		session_override = str(data.get("session_id", "")).strip_edges()
	var evt = {
		"schema_version": schema_version,
		"event_type": "metapunkt.%s" % event_type,
		"source_id": hub_source_id,
		"seq": _seq,
		"t_received": float(t),
		"t_device": float(t),
		"session_id": (
			session_override if not session_override.is_empty()
			else (default_session_id if not default_session_id.is_empty() else null)
		),
		"payload": {
			"data": data,
			"user_id": user_id,
			"app_id": app_id,
		},
		"provenance": {
			"component": "metapunkt",
		},
	}

	# Local JSONL (debug + offline fallback)
	if enable_jsonl and not _log_path.is_empty():
		var f = FileAccess.open(_log_path, FileAccess.WRITE_READ)
		if f:
			f.seek_end()
			f.store_string(JSON.stringify(evt) + "\n")
			f.close()

	# Best-effort hub forwarding (system-of-record path)
	if enable_hub_forwarding and _http:
		var url = hub_base_url.rstrip("/") + "/substrate/events"
		var headers = ["Content-Type: application/json"]
		# Remove null session_id so Pydantic Optional[str] is satisfied either way
		var send_evt = evt.duplicate(true)
		if send_evt.get("session_id") == null:
			send_evt.erase("session_id")
		_http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(send_evt))

	print("Audit Log [%s]: %s (User: %s)" % [event_type, data, user_id if user_id else "N/A"])
	event_emitted.emit(evt)

# Canonical orchestration event emission (no metapunkt.* prefix).
func emit_event(event_type: String, payload: Dictionary, user_id: String = "", provenance: Dictionary = {}, session_id: String = "") -> void:
	_seq += 1
	var t = Time.get_unix_time_from_system()
	var sid := session_id.strip_edges()
	if sid.is_empty():
		sid = default_session_id

	var evt := {
		"schema_version": schema_version,
		"event_type": event_type,
		"source_id": hub_source_id,
		"seq": _seq,
		"t_received": float(t),
		"t_device": float(t),
		"session_id": (sid if not sid.is_empty() else null),
		"payload": payload,
		"provenance": provenance if provenance != null else {},
	}
	# Attach turn_id for correlation if caller didn't provide one.
	if evt["payload"] != null and typeof(evt["payload"]) == TYPE_DICTIONARY:
		var p: Dictionary = evt["payload"]
		if not p.has("turn_id") and not default_turn_id.strip_edges().is_empty():
			p["turn_id"] = default_turn_id.strip_edges()

	# Local JSONL (debug + offline fallback)
	if enable_jsonl and not _log_path.is_empty():
		var f = FileAccess.open(_log_path, FileAccess.WRITE_READ)
		if f:
			f.seek_end()
			f.store_string(JSON.stringify(evt) + "\n")
			f.close()

	# Best-effort hub forwarding
	if enable_hub_forwarding:
		_post_json_best_effort("/substrate/events", evt)

	event_emitted.emit(evt)

# --- Hub substrate adapter (best-effort) ---
func hub_create_artifact_inline_json(artifact_type: String, inline_json: Dictionary, metadata: Dictionary = {}) -> void:
	if not enable_hub_forwarding:
		return
	var meta := metadata.duplicate(true) if metadata else {}
	if not meta.has("provenance"):
		meta["provenance"] = {"generated_by": "metapunkt"}
	var payload := {"artifact_type": artifact_type, "inline_json": inline_json, "metadata": meta}
	_post_json_best_effort("/substrate/artifacts", payload)

func hub_create_artifact_inline_json_async(artifact_type: String, inline_json: Dictionary, metadata: Dictionary = {}) -> Dictionary:
	"""
	Create an inline_json artifact and return the hub response (best-effort).
	This is used when we need an exportable artifact id for traceability (v1).
	"""
	if not enable_hub_forwarding:
		return {"ok": false, "error": "hub_forwarding_disabled"}
	if hub_base_url.strip_edges().is_empty():
		return {"ok": false, "error": "hub_base_url_empty"}
	var meta := metadata.duplicate(true) if metadata else {}
	if not meta.has("provenance"):
		meta["provenance"] = {"generated_by": "metapunkt"}
	var payload := {"artifact_type": artifact_type, "inline_json": inline_json, "metadata": meta}

	var http := HTTPRequest.new()
	add_child(http)
	var result: Dictionary = {"ok": false, "error": "request_failed"}
	http.request_completed.connect(func(_rc: int, sc: int, _h: PackedStringArray, b: PackedByteArray):
		var txt := b.get_string_from_utf8()
		var body_any := JSON.parse_string(txt) if not txt.is_empty() else {}
		if sc >= 200 and sc < 300:
			result = {"ok": true, "data": body_any, "status": sc}
		else:
			result = {"ok": false, "error": {"status": sc, "body": body_any}}
		if is_instance_valid(http):
			http.queue_free()
	)
	var url := hub_base_url.rstrip("/") + "/substrate/artifacts"
	var err := http.request(url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(payload))
	if err != OK:
		if is_instance_valid(http):
			http.queue_free()
		return {"ok": false, "error": "HTTPRequest.request failed: %s" % error_string(err)}
	await http.request_completed
	return result

func hub_create_entity(entity_type: String, entity_name: String = "", summary: String = "", tags: Array = [], metadata: Dictionary = {}) -> void:
	if not enable_hub_forwarding:
		return
	var name_val: Variant = null
	if not entity_name.strip_edges().is_empty():
		name_val = entity_name
	var summary_val: Variant = null
	if not summary.strip_edges().is_empty():
		summary_val = summary
	var payload := {
		"entity_type": entity_type,
		"name": name_val,
		"summary": summary_val,
		"tags": tags,
		"metadata": metadata,
	}
	_post_json_best_effort("/substrate/entities", payload)

func hub_create_relation(relation_type: String, from_entity_id: String, to_entity_id: String, weight: float = 0.0, metadata: Dictionary = {}) -> void:
	if not enable_hub_forwarding:
		return
	var weight_val: Variant = null
	if not is_equal_approx(weight, 0.0):
		weight_val = weight
	var payload := {
		"relation_type": relation_type,
		"from_entity_id": from_entity_id,
		"to_entity_id": to_entity_id,
		"weight": weight_val,
		"metadata": metadata,
	}
	_post_json_best_effort("/substrate/relations", payload)

func _post_json_best_effort(path: String, body: Dictionary) -> void:
	if hub_base_url.strip_edges().is_empty():
		return
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(func(_rc: int, _sc: int, _h: PackedStringArray, _b: PackedByteArray):
		if is_instance_valid(http):
			http.queue_free()
	)
	var url := hub_base_url.rstrip("/") + path
	http.request(url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body))