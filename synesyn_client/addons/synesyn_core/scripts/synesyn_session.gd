extends RefCounted
class_name SynesynSession

# Shared helper for application-layer session identity.
# Purpose:
# - Provide a stable per-run session_id that any app (ScenSyn, ReadyMade, etc.) can use
# - Allows Metapunkt audit forwarding to attach x-session-id / session_id consistently
#
# Storage:
# - stored on SceneTree.root meta so it’s available cross-scene without adding new autoloads.

static func _root() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root if tree else null

static func _meta_key(app_id: String) -> String:
	var a := _sanitize_app_id(app_id)
	return "synesyn_session_id_%s" % a

static func _turn_meta_key(app_id: String) -> String:
	var a := _sanitize_app_id(app_id)
	return "synesyn_turn_id_%s" % a

static func _sanitize_app_id(app_id: String) -> String:
	var a := String(app_id).strip_edges().to_lower()
	if a.is_empty():
		return "unknown_app"
	var out := ""
	for i in range(a.length()):
		var ch := a[i]
		var ok := (
			(ch >= "a" and ch <= "z")
			or (ch >= "0" and ch <= "9")
			or ch == "_"
		)
		out += ch if ok else "_"
	return out

static func _generate_session_id(app_id: String) -> String:
	# Deterministic enough for local-first usage; can be replaced with ULID later.
	var t := Time.get_unix_time_from_system()
	var r := randi() % 1000000
	var a := String(app_id).strip_edges().to_lower()
	if a.is_empty():
		a = "app"
	return "sess_%s_%d_%06d" % [a, t, r]

static func get_or_create_session_id(app_id: String) -> String:
	var root := _root()
	if not root:
		return _generate_session_id(app_id)
	var key := _meta_key(app_id)
	if root.has_meta(key):
		return str(root.get_meta(key, "")).strip_edges()
	var sid := _generate_session_id(app_id)
	root.set_meta(key, sid)
	return sid

static func set_current_turn_id(app_id: String, turn_id: String) -> void:
	var root := _root()
	if not root:
		return
	var tid := String(turn_id).strip_edges()
	if tid.is_empty():
		return
	var key := _turn_meta_key(app_id)
	root.set_meta(key, tid)

static func get_current_turn_id(app_id: String) -> String:
	var root := _root()
	if not root:
		return ""
	var key := _turn_meta_key(app_id)
	if not root.has_meta(key):
		return ""
	return str(root.get_meta(key, "")).strip_edges()


