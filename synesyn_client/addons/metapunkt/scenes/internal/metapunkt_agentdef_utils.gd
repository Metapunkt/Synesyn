extends RefCounted
class_name MetapunktAgentDefUtils

const AgentDefinition = preload("res://addons/metapunkt/Core/AgentRegistry/AgentDefinition.gd")
const _JsonSchemaValidator = preload("res://addons/metapunkt/Core/Ports/json_schema_validator.gd")

static func validate_for_save(owner, defn: AgentDefinition) -> Dictionary:
	var errs: Array = []
	var warns: Array = []

	if owner._agentdef_synterface_defaults:
		var defaults_text: String = owner._agentdef_synterface_defaults.text.strip_edges()
		if not defaults_text.is_empty():
			var parsed_defaults = JSON.parse_string(defaults_text)
			if typeof(parsed_defaults) != TYPE_DICTIONARY:
				errs.append("synterface_defaults must be a JSON object")
	if owner._agentdef_binding_hints:
		var hints_text: String = owner._agentdef_binding_hints.text.strip_edges()
		if not hints_text.is_empty():
			var parsed_hints = JSON.parse_string(hints_text)
			if typeof(parsed_hints) != TYPE_DICTIONARY:
				errs.append("binding_hints must be a JSON object")
	if owner._agentdef_capabilities:
		var capabilities_text: String = owner._agentdef_capabilities.text.strip_edges()
		if not capabilities_text.is_empty():
			var parsed_capabilities = JSON.parse_string(capabilities_text)
			if typeof(parsed_capabilities) != TYPE_DICTIONARY:
				errs.append("capabilities must be a JSON object")

	var req_any: Variant = defn.get("required_synterfaces")
	var required: Array = req_any if typeof(req_any) == TYPE_ARRAY else []
	if required and not required.is_empty():
		var catalog: Dictionary = owner._get_merged_synterface_catalog()
		for port_any in required:
			var port_id: String = str(port_any).strip_edges()
			if port_id.is_empty():
				continue
			if not catalog.has(port_id):
				if port_id.find(".") != -1:
					warns.append("Unknown (namespaced) required_synterface not present in current catalog: %s" % port_id)
				else:
					errs.append("Unknown required_synterface: %s" % port_id)

	var logic_type: String = defn.logic_type.strip_edges().to_lower()
	if logic_type == "limboai":
		var logic_path := ""
		if typeof(defn.logic_config) == TYPE_DICTIONARY:
			logic_path = str(defn.logic_config.get("path", "")).strip_edges()
		if logic_path.is_empty():
			errs.append("limboai requires logic_config.path")

	return {"errors": errs, "warnings": warns}

static func logic_type_selected_text(owner) -> String:
	if not owner._agentdef_logic_type:
		return "behaviortree"
	var selected_index: int = owner._agentdef_logic_type.selected
	return str(owner._agentdef_logic_type.get_item_text(selected_index)).strip_edges()

static func apply_form_to_resource(owner, defn: AgentDefinition) -> void:
	defn.agent_id = (owner._agentdef_id.text.strip_edges() if owner._agentdef_id else "")
	defn.agent_name = (owner._agentdef_name.text.strip_edges() if owner._agentdef_name else "")
	defn.role = (owner._agentdef_role.text.strip_edges() if owner._agentdef_role else "")
	if owner._agentdef_schema_version:
		var schema_version: String = owner._agentdef_schema_version.text.strip_edges()
		defn.schema_version = (schema_version if not schema_version.is_empty() else defn.schema_version)
	defn.logic_type = logic_type_selected_text(owner)
	defn.description = (owner._agentdef_description.text.strip_edges() if owner._agentdef_description else "")
	defn.persona = (owner._agentdef_persona.text if owner._agentdef_persona else "")
	defn.required_tools = owner._parse_tools_csv(owner._agentdef_tools.text if owner._agentdef_tools else "")
	defn.required_synterfaces = owner._parse_synterfaces_csv(owner._agentdef_required_synterfaces.text if owner._agentdef_required_synterfaces else "")
	var logic_path: String = (owner._agentdef_logic_path.text.strip_edges() if owner._agentdef_logic_path else "")
	defn.logic_config = ({"path": logic_path} if not logic_path.is_empty() else {})
	defn.capabilities = owner._parse_json_object(owner._agentdef_capabilities.text if owner._agentdef_capabilities else "")
	defn.synterface_defaults = owner._parse_json_object(owner._agentdef_synterface_defaults.text if owner._agentdef_synterface_defaults else "")
	defn.binding_hints = owner._parse_json_object(owner._agentdef_binding_hints.text if owner._agentdef_binding_hints else "")

static func fill_form_from_resource(owner, defn: AgentDefinition) -> void:
	if owner._agentdef_id:
		owner._agentdef_id.text = defn.agent_id
	if owner._agentdef_name:
		owner._agentdef_name.text = defn.agent_name
	if owner._agentdef_role:
		owner._agentdef_role.text = defn.role
	if owner._agentdef_schema_version:
		var sv_any: Variant = defn.get("schema_version")
		var schema_version: String = str(sv_any).strip_edges() if sv_any != null else ""
		owner._agentdef_schema_version.text = (schema_version if not schema_version.is_empty() else "metapunkt.agentdef.v1")
	if owner._agentdef_description:
		owner._agentdef_description.text = defn.description
	if owner._agentdef_persona:
		owner._agentdef_persona.text = defn.persona
	if owner._agentdef_tools:
		var tools: Array = defn.required_tools if defn.required_tools else []
		owner._agentdef_tools.text = ", ".join(tools)
	if owner._agentdef_required_synterfaces:
		var req_any: Variant = defn.get("required_synterfaces")
		var required: Array = req_any if typeof(req_any) == TYPE_ARRAY else []
		owner._agentdef_required_synterfaces.text = ", ".join(required) if required else ""
	if owner._agentdef_logic_path:
		var logic_path: String = str(defn.logic_config.get("path", "")).strip_edges() if typeof(defn.logic_config) == TYPE_DICTIONARY else ""
		owner._agentdef_logic_path.text = logic_path
	if owner._agentdef_capabilities:
		var caps: Dictionary = defn.capabilities if typeof(defn.capabilities) == TYPE_DICTIONARY else {}
		owner._agentdef_capabilities.text = owner._stringify_json(caps) if not caps.is_empty() else "{}"
	if owner._agentdef_synterface_defaults:
		var defaults_any: Variant = defn.get("synterface_defaults")
		var defaults_dict: Dictionary = defaults_any if typeof(defaults_any) == TYPE_DICTIONARY else {}
		owner._agentdef_synterface_defaults.text = owner._stringify_json(defaults_dict) if not defaults_dict.is_empty() else "{}"
	if owner._agentdef_binding_hints:
		var hints_any: Variant = defn.get("binding_hints")
		var hints_dict: Dictionary = hints_any if typeof(hints_any) == TYPE_DICTIONARY else {}
		owner._agentdef_binding_hints.text = owner._stringify_json(hints_dict) if not hints_dict.is_empty() else "{}"
	if owner._agentdef_logic_type:
		var want: String = defn.logic_type.strip_edges()
		for item_index in range(owner._agentdef_logic_type.item_count):
			if str(owner._agentdef_logic_type.get_item_text(item_index)).strip_edges() == want:
				owner._agentdef_logic_type.select(item_index)
				break

	owner._refresh_known_synterfaces_ui()
	if owner._agentdef_bindings_preview:
		owner._agentdef_bindings_preview.text = "{}"

static func on_validate_bindings_pressed(owner) -> void:
	owner._agentdef_set_status("")
	var defn: AgentDefinition = owner._agentdef_ensure_editing()
	apply_form_to_resource(owner, defn)

	var validation: Dictionary = validate_for_save(owner, defn)
	var errs: Array = validation.get("errors", [])
	var warns: Array = validation.get("warnings", [])
	if not errs.is_empty():
		owner._agentdef_set_status("Validation failed: %s" % str(errs))
		return

	var required_any: Variant = defn.get("required_synterfaces")
	var required: Array = required_any if typeof(required_any) == TYPE_ARRAY else []
	if required.is_empty():
		owner._agentdef_set_status("No required_synterfaces set (nothing to bind).")
		if owner._agentdef_bindings_preview:
			owner._agentdef_bindings_preview.text = "{}"
		return

	var tree := Engine.get_main_loop() as SceneTree
	var host := tree.root.get_node_or_null("MetapunktAppHost") if tree else null
	if not host or not host.has_method("bind_synterfaces"):
		owner._agentdef_set_status("Preflight failed: MetapunktAppHost missing bind_synterfaces() (needed for synterfaces: %s)" % str(required))
		return

	var catalog: Dictionary = owner._get_merged_synterface_catalog()
	var unknown_hard: Array = []
	var unknown_soft: Array = []
	for port_any in required:
		var port_id: String = str(port_any).strip_edges()
		if port_id.is_empty():
			continue
		if not catalog.has(port_id):
			if port_id.find(".") != -1:
				unknown_soft.append(port_id)
			else:
				unknown_hard.append(port_id)
	if not unknown_hard.is_empty():
		owner._agentdef_set_status("Preflight failed: unknown required_synterfaces: %s" % str(unknown_hard))
		return

	var hints: Dictionary = defn.get("binding_hints") if typeof(defn.get("binding_hints")) == TYPE_DICTIONARY else {}
	var bind_res_any: Variant = host.call("bind_synterfaces", required, hints)
	if typeof(bind_res_any) != TYPE_DICTIONARY:
		owner._agentdef_set_status("Preflight failed: MetapunktAppHost.bind_synterfaces returned non-dictionary")
		return
	var bind_res: Dictionary = bind_res_any
	if not bool(bind_res.get("ok", false)):
		var err: String = str(bind_res.get("error", "")).strip_edges()
		var miss_any: Variant = bind_res.get("missing")
		if err.is_empty() and typeof(miss_any) == TYPE_ARRAY and not (miss_any as Array).is_empty():
			err = "Missing synterfaces: %s" % str(miss_any)
		if err.is_empty():
			err = "bind_synterfaces failed"
		owner._agentdef_set_status("Preflight failed: %s" % err)
		return

	var syn_any: Variant = bind_res.get("synterfaces")
	if typeof(syn_any) != TYPE_DICTIONARY:
		owner._agentdef_set_status("Preflight failed: bind_synterfaces missing 'synterfaces' dictionary")
		return
	var synterfaces: Dictionary = syn_any
	for port_any in required:
		var port_id: String = str(port_any).strip_edges()
		if port_id.is_empty():
			continue
		if not synterfaces.has(port_id):
			owner._agentdef_set_status("Preflight failed: host did not bind required synterface '%s'" % port_id)
			return
		var binding_any: Variant = synterfaces.get(port_id)
		if typeof(binding_any) != TYPE_DICTIONARY:
			owner._agentdef_set_status("Preflight failed: synterface '%s' binding must be a Dictionary" % port_id)
			return
		if catalog.has(port_id):
			var entry: Dictionary = catalog.get(port_id, {})
			var schema_any: Variant = entry.get("schema")
			if typeof(schema_any) == TYPE_DICTIONARY and not (schema_any as Dictionary).is_empty():
				var schema_result: Dictionary = _JsonSchemaValidator.validate(binding_any, schema_any, "$.%s" % port_id)
				if not bool(schema_result.get("ok", false)):
					owner._agentdef_set_status("Preflight failed: synterface '%s' invalid: %s" % [port_id, str(schema_result.get("error", "schema validation failed"))])
					return

	if owner._agentdef_bindings_preview:
		owner._agentdef_bindings_preview.text = JSON.stringify(synterfaces, "\t")
	var msg := "Preflight OK: bound %d synterfaces" % synterfaces.size()
	if not warns.is_empty():
		msg += " | warnings: %s" % str(warns)
	if not unknown_soft.is_empty():
		msg += " | unknown namespaced synterfaces skipped schema: %s" % str(unknown_soft)
	owner._agentdef_set_status(msg)
