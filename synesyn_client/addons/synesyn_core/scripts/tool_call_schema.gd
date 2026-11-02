## Purpose: Standard tool-call schema (Metapunkt integration) for ops/args/errors + correlation IDs.
##
## This is intentionally small and shared across apps to prevent drift.
extends RefCounted
class_name ToolCallSchema

const SCHEMA_VERSION := 1

static func _now_unix() -> float:
	return float(Time.get_unix_time_from_system())

static func _new_call_id() -> String:
	# Short correlation id: <unix>_<rand>
	var r := int(randi() % 1000000)
	return "%s_%06d" % [str(Time.get_unix_time_from_system()), r]

static func make_call(op: String, args: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	var call_id := str(ctx.get("call_id", "")).strip_edges()
	if call_id.is_empty():
		call_id = _new_call_id()
	var agent_id_str := str(ctx.get("agent_id", "")).strip_edges()
	var user_id_str := str(ctx.get("user_id", "")).strip_edges()
	var turn_id_str := str(ctx.get("turn_id", "")).strip_edges()
	var session_id_str := str(ctx.get("session_id", "")).strip_edges()
	var agent_id_val: Variant = null
	var user_id_val: Variant = null
	var turn_id_val: Variant = null
	var session_id_val: Variant = null
	if not agent_id_str.is_empty():
		agent_id_val = agent_id_str
	if not user_id_str.is_empty():
		user_id_val = user_id_str
	if not turn_id_str.is_empty():
		turn_id_val = turn_id_str
	if not session_id_str.is_empty():
		session_id_val = session_id_str
	return {
		"schema_version": SCHEMA_VERSION,
		"call_id": call_id,
		"op": String(op).strip_edges(),
		"args": args if args != null else {},
		"ts": _now_unix(),
		# Optional context for logging/correlation
		"agent_id": agent_id_val,
		"user_id": user_id_val,
		"turn_id": turn_id_val,
		"session_id": session_id_val,
		"scopes": ctx.get("scopes", []),
	}

static func ok(call_env: Dictionary, result: Variant) -> Dictionary:
	return {
		"ok": true,
		"schema_version": SCHEMA_VERSION,
		"call_id": str(call_env.get("call_id", "")),
		"op": str(call_env.get("op", "")),
		"result": result,
	}

static func fail(call_env: Dictionary, code: String, message: String, details: Variant = null) -> Dictionary:
	var err := {
		"code": String(code).strip_edges(),
		"message": String(message),
		"details": details,
	}
	# Back-compat: keep a top-level "error" string for older callers.
	return {
		"ok": false,
		"schema_version": SCHEMA_VERSION,
		"call_id": str(call_env.get("call_id", "")),
		"op": str(call_env.get("op", "")),
		"error": String(message),
		"error_obj": err,
	}

static func is_envelope(v: Variant) -> bool:
	return typeof(v) == TYPE_DICTIONARY and (v as Dictionary).has("ok") and (v as Dictionary).has("op") and (v as Dictionary).has("call_id")


