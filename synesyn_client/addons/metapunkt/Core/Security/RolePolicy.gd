extends Object
class_name RolePolicy

# Role/tool policy for Metapunkt.
# Goal: a small, explicit allowlist model that is easy to export as a v1 artifact.
#
# Precedence:
# - If AgentDefinition.required_tools is non-empty -> that is the allowlist (explicit per-agent contract).
# - Else -> role-based defaults.

var _defaults := {
	# Broad developer role (local-first): allow all registered tools.
	"developer": {"allow_all": true, "tools": []},
	# Character/roleplay: keep it conservative by default.
	"roleplay": {"allow_all": false, "tools": ["SynTree"]},
	# Facilitator: can talk and use general Godot utils, but not destructive ops unless explicitly required_tools includes them.
	"facilitator": {"allow_all": false, "tools": ["SynTree", "GodotUtils"]},
	# System: treated as developer (explicitly trusted).
	"system": {"allow_all": true, "tools": []},
}

var _override: Dictionary = {}


func _policy_path() -> String:
	var dest: String = RuntimeConfig.get_metapunkt_data_dir().path_join("role_policy.json")
	RuntimeConfig.migrate_file_if_needed(dest, ["user://metapunkt/role_policy.json"])
	return dest


func load_override_from_user() -> void:
	var policy_path: String = _policy_path()
	if not FileAccess.file_exists(policy_path):
		_override = {}
		return
	var f := FileAccess.open(policy_path, FileAccess.READ)
	if not f:
		_override = {}
		return
	var txt := f.get_as_text()
	f.close()
	var obj := JSON.parse_string(txt)
	if typeof(obj) == TYPE_DICTIONARY:
		_override = obj
	else:
		_override = {}


func get_policy_dict() -> Dictionary:
	var out := {
		"schema_version": 1,
		"defaults": _defaults.duplicate(true),
		"override": _override.duplicate(true),
	}
	return out


func save_override_to_user(override_dict: Dictionary) -> bool:
	_override = override_dict.duplicate(true)
	var policy_path: String = _policy_path()
	DirAccess.make_dir_recursive_absolute(policy_path.get_base_dir())
	var f := FileAccess.open(policy_path, FileAccess.WRITE)
	if not f:
		return false
	f.store_string(JSON.stringify(_override, "\t"))
	f.close()
	return true


func resolve_allowed_tools_for_agent(definition, all_tools: Array[String]) -> Dictionary:
	# Returns: {allow_all: bool, tools: Array[String], reason: String}
	if not definition:
		return {"allow_all": true, "tools": all_tools, "reason": "no_definition"}

	# 1) explicit per-agent allowlist
	# Godot 4: Object.get() does not accept a default value parameter.
	var req_any: Variant = definition.get("required_tools") if definition.has_method("get") else null
	if typeof(req_any) == TYPE_ARRAY:
		var req: Array = req_any
		if req.size() > 0:
			var tools: Array[String] = []
			for t in req:
				var s := str(t).strip_edges()
				if not s.is_empty():
					tools.append(s)
			return {"allow_all": false, "tools": tools, "reason": "agent_required_tools"}

	# 2) role defaults + overrides
	var role := ""
	if definition.has_method("get"):
		var role_any: Variant = definition.get("role")
		role = str(role_any).strip_edges().to_lower() if role_any != null else ""
	if role.is_empty():
		role = "developer"

	var merged = _defaults.get(role, _defaults.get("developer", {}))
	if typeof(_override) == TYPE_DICTIONARY and _override.has(role):
		var o: Variant = _override.get(role)
		if typeof(o) == TYPE_DICTIONARY:
			# Shallow merge: override allow_all/tools if provided
			var od: Dictionary = o
			if od.has("allow_all"):
				merged["allow_all"] = bool(od.get("allow_all"))
			if od.has("tools") and typeof(od.get("tools")) == TYPE_ARRAY:
				merged["tools"] = od.get("tools")

	var allow_all := bool(merged.get("allow_all", false))
	if allow_all:
		return {"allow_all": true, "tools": all_tools, "reason": "role_allow_all:%s" % role}

	var tools_out: Array[String] = []
	var arr_any: Variant = merged.get("tools", [])
	if typeof(arr_any) == TYPE_ARRAY:
		for t in arr_any:
			var s := str(t).strip_edges()
			if not s.is_empty():
				tools_out.append(s)
	return {"allow_all": false, "tools": tools_out, "reason": "role_allowlist:%s" % role}


func is_tool_allowed(definition, tool_name: String, all_tools: Array[String]) -> Dictionary:
	var resolved := resolve_allowed_tools_for_agent(definition, all_tools)
	if bool(resolved.get("allow_all", false)):
		return {"ok": true, "reason": resolved.get("reason", "")}
	var allow: Array = resolved.get("tools", [])
	var t := tool_name.strip_edges()
	var ok := allow.has(t)
	return {"ok": ok, "reason": resolved.get("reason", ""), "allowed_tools": allow}


