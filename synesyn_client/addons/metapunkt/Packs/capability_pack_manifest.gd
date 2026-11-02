## Capability Pack manifest loader and validator (v0).
##
## Loads and validates pack.json files. Does NOT perform I/O beyond reading the manifest.
extends RefCounted
class_name CapabilityPackManifest

const MANIFEST_FILENAME := "pack.json"
const SUPPORTED_CAPABILITY_TYPES: Array[String] = ["tool", "ui_panel"]

# --- Parsed fields ---
var id: String = ""
var pack_name: String = ""
var version: String = ""
var description: String = ""
var author: String = ""
var pack_license: String = ""
var synesyn_min_version: String = ""
var schemas: Dictionary = {}
var capabilities: Array = []
var permissions: Dictionary = {}
var limits: Dictionary = {}
var raw: Dictionary = {}

# --- Validation ---
var is_valid: bool = false
var validation_errors: Array[String] = []


static func load_from_directory(dir_path: String) -> CapabilityPackManifest:
	var manifest := CapabilityPackManifest.new()
	var file_path := dir_path.path_join(MANIFEST_FILENAME)

	if not FileAccess.file_exists(file_path):
		manifest.validation_errors.append("pack.json not found at: %s" % file_path)
		return manifest

	var file := FileAccess.open(file_path, FileAccess.READ)
	if not file:
		manifest.validation_errors.append("Cannot open pack.json: %s" % file_path)
		return manifest

	var text := file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		manifest.validation_errors.append("pack.json is not a valid JSON object")
		return manifest

	manifest.raw = parsed
	manifest._parse_and_validate(parsed, dir_path)
	return manifest


func _parse_and_validate(data: Dictionary, dir_path: String) -> void:
	id = str(data.get("id", "")).strip_edges()
	if id.is_empty():
		validation_errors.append("Missing required field: id")

	pack_name = str(data.get("name", "")).strip_edges()
	if pack_name.is_empty():
		validation_errors.append("Missing required field: name")

	version = str(data.get("version", "")).strip_edges()
	if version.is_empty():
		validation_errors.append("Missing required field: version")

	description = str(data.get("description", "")).strip_edges()
	author = str(data.get("author", "")).strip_edges()
	pack_license = str(data.get("license", "")).strip_edges()
	synesyn_min_version = str(data.get("synesyn_min_version", "")).strip_edges()

	var schemas_any: Variant = data.get("schemas", {})
	if typeof(schemas_any) == TYPE_DICTIONARY:
		schemas = schemas_any

	var perms_any: Variant = data.get("permissions", {})
	if typeof(perms_any) != TYPE_DICTIONARY:
		validation_errors.append("permissions must be a JSON object")
	else:
		permissions = perms_any
		_validate_permissions()

	var limits_any: Variant = data.get("limits", {})
	if typeof(limits_any) == TYPE_DICTIONARY:
		limits = limits_any

	var caps_any: Variant = data.get("capabilities", [])
	if typeof(caps_any) != TYPE_ARRAY:
		validation_errors.append("capabilities must be an array")
	else:
		capabilities = []
		for cap_any in caps_any:
			if typeof(cap_any) != TYPE_DICTIONARY:
				validation_errors.append("Each capability must be a JSON object")
				continue
			_validate_capability(cap_any, dir_path)
			capabilities.append(cap_any)
		if capabilities.is_empty():
			validation_errors.append("At least one capability is required")

	# Forbid secret values in manifest
	var secrets_any: Variant = permissions.get("secrets", [])
	if typeof(secrets_any) == TYPE_ARRAY:
		for secret_entry in secrets_any:
			if typeof(secret_entry) == TYPE_DICTIONARY:
				if (secret_entry as Dictionary).has("value"):
					validation_errors.append("Secret values must NOT be in pack.json")

	is_valid = validation_errors.is_empty()


func _validate_capability(cap: Dictionary, dir_path: String) -> void:
	var cap_id := str(cap.get("capability_id", "")).strip_edges()
	if cap_id.is_empty():
		validation_errors.append("Capability missing capability_id")

	var cap_type := str(cap.get("type", "")).strip_edges()
	if cap_type.is_empty():
		validation_errors.append("Capability '%s' missing type" % cap_id)
	elif cap_type not in SUPPORTED_CAPABILITY_TYPES:
		validation_errors.append("Capability '%s' unsupported type: %s" % [cap_id, cap_type])

	var ep_any: Variant = cap.get("entrypoints", {})
	if typeof(ep_any) != TYPE_DICTIONARY:
		validation_errors.append("Capability '%s' entrypoints must be a JSON object" % cap_id)
		return
	var ep: Dictionary = ep_any

	if cap_type == "tool":
		if str(ep.get("tool_name", "")).strip_edges().is_empty():
			validation_errors.append("Tool capability '%s' missing entrypoints.tool_name" % cap_id)
		# Best-effort: check schema files exist
		for schema_key in ["args_schema", "result_schema"]:
			var rel_path := str(ep.get(schema_key, "")).strip_edges()
			if not rel_path.is_empty():
				if not FileAccess.file_exists(dir_path.path_join(rel_path)):
					validation_errors.append("Tool '%s' %s not found: %s" % [cap_id, schema_key, rel_path])

	elif cap_type == "ui_panel":
		if str(ep.get("scene_path", "")).strip_edges().is_empty():
			validation_errors.append("UI panel '%s' missing entrypoints.scene_path" % cap_id)


func _validate_permissions() -> void:
	var net_any: Variant = permissions.get("network", {})
	if typeof(net_any) == TYPE_DICTIONARY:
		var allow_any: Variant = (net_any as Dictionary).get("allow", [])
		if typeof(allow_any) != TYPE_ARRAY:
			validation_errors.append("permissions.network.allow must be an array")

	var fs_any: Variant = permissions.get("filesystem", {})
	if typeof(fs_any) == TYPE_DICTIONARY:
		for scope_key in ["read", "write"]:
			var scope_any: Variant = (fs_any as Dictionary).get(scope_key, [])
			if typeof(scope_any) != TYPE_ARRAY:
				validation_errors.append("permissions.filesystem.%s must be an array" % scope_key)

	var danger_any: Variant = permissions.get("dangerous_actions", [])
	if typeof(danger_any) != TYPE_ARRAY:
		validation_errors.append("permissions.dangerous_actions must be an array")


func get_tool_capabilities() -> Array:
	return capabilities.filter(func(c): return str(c.get("type", "")) == "tool")


func get_ui_panel_capabilities() -> Array:
	return capabilities.filter(func(c): return str(c.get("type", "")) == "ui_panel")


func get_permission_summary() -> String:
	var parts: Array[String] = []
	var net_any: Variant = permissions.get("network", {})
	if typeof(net_any) == TYPE_DICTIONARY:
		var allow_any: Variant = (net_any as Dictionary).get("allow", [])
		if typeof(allow_any) == TYPE_ARRAY and not (allow_any as Array).is_empty():
			parts.append("Network: %s" % str(allow_any))
	var fs_any: Variant = permissions.get("filesystem", {})
	if typeof(fs_any) == TYPE_DICTIONARY:
		var fs: Dictionary = fs_any
		if typeof(fs.get("read", [])) == TYPE_ARRAY and not (fs.get("read", []) as Array).is_empty():
			parts.append("Read: %s" % str(fs.get("read")))
		if typeof(fs.get("write", [])) == TYPE_ARRAY and not (fs.get("write", []) as Array).is_empty():
			parts.append("Write: %s" % str(fs.get("write")))
	var secrets_any: Variant = permissions.get("secrets", [])
	if typeof(secrets_any) == TYPE_ARRAY and not (secrets_any as Array).is_empty():
		parts.append("Secrets: %s" % str(secrets_any))
	if parts.is_empty():
		return "No special permissions"
	return " | ".join(parts)
