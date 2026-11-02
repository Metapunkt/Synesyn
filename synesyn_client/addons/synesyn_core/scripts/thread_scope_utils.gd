## Purpose: Thread scope utilities (naming + sanitization for cross-app thread isolation)
##
## v1 goal: allow multiple Synesyn apps/surfaces to share a substrate while keeping
## conversation threads isolated by default (no collisions / no accidental bleed).
extends RefCounted
class_name ThreadScopeUtils

static func sanitize_scope(scope: String) -> String:
	var s := String(scope).strip_edges().to_lower()
	if s.is_empty():
		return "shared"

	# Replace path separators and whitespace to keep it safe as a directory name.
	s = s.replace("\\", "_").replace("/", "_").replace(" ", "_").replace(":", "_")

	# Allow only a conservative set of characters.
	var out := ""
	for i in s.length():
		var ch := s[i]
		var ok := (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch in ["_", "-", "."]
		out += ch if ok else "_"

	# Collapse repeated underscores.
	while out.find("__") != -1:
		out = out.replace("__", "_")
	out = out.strip_edges()
	if out.is_empty():
		return "shared"
	return out

static func app_scope(app_id: String, workspace_slug: String = "") -> String:
	# Convention:
	# - default: "<app_id>"
	# - workspace-specific: "<app_id>.<workspace_slug>"
	var a := sanitize_scope(app_id)
	if workspace_slug.strip_edges().is_empty():
		return a
	return sanitize_scope("%s.%s" % [a, workspace_slug])


