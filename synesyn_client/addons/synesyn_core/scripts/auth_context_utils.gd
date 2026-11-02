## Purpose: Small helper for producing stable AuthContext values (user_id/scopes) in apps.
## This is intentionally lightweight: v0 uses "local identity" strings; future work can swap in hub-verified JWT claims.
extends RefCounted
class_name AuthContextUtils

static func get_user_id(app_id: String, role_hint: String = "") -> String:
	var aid := app_id.strip_edges().to_lower()
	if aid.is_empty():
		aid = "app"
	var rh := role_hint.strip_edges().to_lower()
	if not rh.is_empty():
		return "%s.%s" % [aid, rh]

	# Best-effort: human-friendly identity from environment, else device unique id.
	var uname := str(OS.get_environment("USERNAME")).strip_edges()
	if uname.is_empty():
		uname = str(OS.get_environment("USER")).strip_edges()
	if uname.is_empty():
		uname = str(OS.get_unique_id()).strip_edges()
	if uname.is_empty():
		uname = "guest"
	return "%s.%s" % [aid, uname]

static func get_scopes(_app_id: String) -> Array:
	# v0: keep empty unless the host app has a concrete scope model.
	# (Scopes can still be provided through SLOP headers for HTTP clients.)
	return []


