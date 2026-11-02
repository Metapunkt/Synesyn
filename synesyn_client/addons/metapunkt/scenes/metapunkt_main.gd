@tool
extends Control

## Metapunkt panel controller (editor + runtime).
##
## Intent:
## - The scene `metapunkt_main.tscn` provides layout only.
## - This script binds the UI lists to live Metapunkt state (EndpointHandler + modules).
## - If nothing shows in the lists, the most common reasons are:
##   - no agents have been spawned yet (Resources/Tasks empty is expected), or
##   - the SLOP server couldn't bind (port conflict), so EndpointHandler may be degraded.

# NOTE:
# Do NOT shadow the `EndpointHandler` class_name with a `const EndpointHandler = preload(...)`.
# Doing so breaks typed casts and makes dot-access look like "Invalid access to property" at runtime.
const _EndpointHandlerScript = preload("res://addons/metapunkt/Networking/SLOPServer/EndpointHandler.gd")
const AgentDefinition = preload("res://addons/metapunkt/Core/AgentRegistry/AgentDefinition.gd")
const _SynterfaceCatalog = preload("res://addons/metapunkt/Core/Ports/synterface_catalog.gd")
const _JsonSchemaValidator = preload("res://addons/metapunkt/Core/Ports/json_schema_validator.gd")
const _MetapunktUiParseUtilsScript = preload("res://addons/metapunkt/scenes/internal/metapunkt_ui_parse_utils.gd")
const _MetapunktPanelStatusUtilsScript = preload("res://addons/metapunkt/scenes/internal/metapunkt_panel_status_utils.gd")
const _MetapunktSynterfaceSlotsUtilsScript = preload("res://addons/metapunkt/scenes/internal/metapunkt_synterface_slots_utils.gd")
const _MetapunktUiStateUtilsScript = preload("res://addons/metapunkt/scenes/internal/metapunkt_ui_state_utils.gd")
const _MetapunktPacksUtilsScript = preload("res://addons/metapunkt/scenes/internal/metapunkt_packs_utils.gd")
const _MetapunktAgentDefUtilsScript = preload("res://addons/metapunkt/scenes/internal/metapunkt_agentdef_utils.gd")
const _CapabilityPackRegistryScript = preload("res://addons/metapunkt/Packs/capability_pack_registry.gd")

@onready var _endpoint: Node = get_node_or_null("MetapunktEndpointHandler")
@onready var _components: ItemList = get_node_or_null("%ComponentList") as ItemList
@onready var _tasks: ItemList = get_node_or_null("%TaskList") as ItemList
@onready var _resources: ItemList = get_node_or_null("%ResourceList") as ItemList
@onready var _patterns: ItemList = get_node_or_null("%PatternList") as ItemList
@onready var _status: TextEdit = get_node_or_null("%StatusText") as TextEdit

# Controls strip
@onready var _slop_host: LineEdit = get_node_or_null("%SlopHost") as LineEdit
@onready var _slop_port: SpinBox = get_node_or_null("%SlopPort") as SpinBox
@onready var _slop_bound: Label = get_node_or_null("%SlopBound") as Label
@onready var _hub_url: LineEdit = get_node_or_null("%HubUrl") as LineEdit
@onready var _hub_preset: OptionButton = get_node_or_null("%HubPreset") as OptionButton
@onready var _hub_state: Label = get_node_or_null("%HubState") as Label

# Controls tabs (Services / Agents / Roles / AgentDefs / Console)
@onready var _controls_tabs: TabContainer = get_node_or_null("MarginContainer/ScrollContainer/VBoxContainer/TopSplit/ControlsPanel/MarginContainer/ControlsTabs") as TabContainer

# Agents tab
@onready var _agent_spawn_path: LineEdit = get_node_or_null("%AgentSpawnPath") as LineEdit
@onready var _agent_spawn_status: Label = get_node_or_null("%AgentSpawnStatus") as Label
@onready var _agent_list: OptionButton = get_node_or_null("%AgentList") as OptionButton
@onready var _agent_manage_status: Label = get_node_or_null("%AgentManageStatus") as Label
@onready var _agent_spawn_dialog: FileDialog = get_node_or_null("%AgentSpawnFileDialog") as FileDialog

# Console tab
@onready var _console_agent: OptionButton = get_node_or_null("%ConsoleAgent") as OptionButton
@onready var _console_tool: OptionButton = get_node_or_null("%ConsoleTool") as OptionButton
@onready var _console_op: OptionButton = get_node_or_null("%ConsoleOp") as OptionButton
@onready var _console_args: TextEdit = get_node_or_null("%ConsoleArgs") as TextEdit
@onready var _console_result: TextEdit = get_node_or_null("%ConsoleResult") as TextEdit
@onready var _console_status: Label = get_node_or_null("%ConsoleStatus") as Label

# Roles tab
@onready var _role_override_text: TextEdit = get_node_or_null("%RoleOverrideText") as TextEdit
@onready var _role_status: Label = get_node_or_null("%RoleStatus") as Label

# AgentDefs tab
@onready var _agentdef_path: LineEdit = get_node_or_null("%AgentDefPath") as LineEdit
@onready var _agentdef_status: Label = get_node_or_null("%AgentDefStatus") as Label
@onready var _agentdef_id: LineEdit = get_node_or_null("%AgentDefId") as LineEdit
@onready var _agentdef_name: LineEdit = get_node_or_null("%AgentDefName") as LineEdit
@onready var _agentdef_role: LineEdit = get_node_or_null("%AgentDefRole") as LineEdit
@onready var _agentdef_schema_version: LineEdit = get_node_or_null("%AgentDefSchemaVersion") as LineEdit
@onready var _agentdef_required_synterfaces: LineEdit = get_node_or_null("%AgentDefRequiredSynterfaces") as LineEdit
@onready var _agentdef_logic_type: OptionButton = get_node_or_null("%AgentDefLogicType") as OptionButton
@onready var _agentdef_logic_path: LineEdit = get_node_or_null("%AgentDefLogicPath") as LineEdit
@onready var _agentdef_tools: LineEdit = get_node_or_null("%AgentDefTools") as LineEdit
@onready var _agentdef_description: LineEdit = get_node_or_null("%AgentDefDescription") as LineEdit
@onready var _agentdef_persona: TextEdit = get_node_or_null("%AgentDefPersona") as TextEdit
@onready var _agentdef_capabilities: TextEdit = get_node_or_null("%AgentDefCapabilities") as TextEdit
@onready var _agentdef_synterface_defaults: TextEdit = get_node_or_null("%AgentDefSynterfaceDefaults") as TextEdit
@onready var _agentdef_binding_hints: TextEdit = get_node_or_null("%AgentDefBindingHints") as TextEdit
@onready var _agentdef_bindings_preview: TextEdit = get_node_or_null("%AgentDefBindingsPreview") as TextEdit
@onready var _known_synterfaces_list: ItemList = get_node_or_null("%KnownSynterfacesList") as ItemList
@onready var _known_synterfaces_desc: Label = get_node_or_null("%KnownSynterfacesDesc") as Label
@onready var _known_synterfaces_copy: Button = get_node_or_null("%KnownSynterfacesCopyButton") as Button
@onready var _synterface_issues_list: ItemList = get_node_or_null("%SynterfaceIssuesList") as ItemList
@onready var _synterface_impl_picker: OptionButton = get_node_or_null("%SynterfaceImplPicker") as OptionButton
@onready var _synterface_overrides_path: Label = get_node_or_null("%SynterfaceOverridesPathLabel") as Label
@onready var _user_synterfaces_path: Label = get_node_or_null("%UserSynterfacesPathLabel") as Label
@onready var _open_user_synterfaces_button: Button = get_node_or_null("%OpenUserSynterfacesButton") as Button
@onready var _user_synterfaces_issues_label: Label = get_node_or_null("%UserSynterfacesIssuesLabel") as Label
@onready var _agent_slots_list: ItemList = get_node_or_null("%AgentSlotsList") as ItemList
@onready var _agent_slot_picker: OptionButton = get_node_or_null("%AgentSlotAgentPicker") as OptionButton
@onready var _agent_slot_assignments_path: Label = get_node_or_null("%AgentSlotAssignmentsPathLabel") as Label
@onready var _agent_slots_status: Label = get_node_or_null("%AgentSlotsStatusLabel") as Label
@onready var _agent_slots_publish_button: Button = get_node_or_null("%AgentSlotPublishButton") as Button
@onready var _agentdef_template_btn: Button = get_node_or_null("%AgentDefTemplateButton") as Button
@onready var _agentdef_template_menu: PopupMenu = get_node_or_null("%AgentDefTemplateMenu") as PopupMenu
@onready var _agentdef_load_dialog: FileDialog = get_node_or_null("%AgentDefLoadDialog") as FileDialog
@onready var _agentdef_save_dialog: FileDialog = get_node_or_null("%AgentDefSaveDialog") as FileDialog
@onready var _agentdef_logic_dialog: FileDialog = get_node_or_null("%AgentDefLogicDialog") as FileDialog

var _last_refresh_ms: int = 0
var _refresh_interval_ms: int = 600

var _editing_agentdef: AgentDefinition = null
var _ui_state_apply_guard: bool = false
var _ui_save_timer: Timer = null
var _tool_details_cache: Dictionary = {} # tool_name -> details dict
var _known_synterfaces_signature: String = ""
var _synterface_issues_signature: String = ""
var _selected_issue_sid: String = ""
var _agent_slots_signature: String = ""
var _selected_slot_id: String = ""
var _agent_slots_last_validation_sig: String = ""

# Packs tab (built programmatically)
var _packs_registry: _CapabilityPackRegistryScript = null
var _packs_ui: Dictionary = {} # keys from _MetapunktPacksUtilsScript.build_packs_tab()

func _coerce_int(v: Variant, default_value: int) -> int:
	return _MetapunktUiParseUtilsScript.coerce_int(v, default_value)

func _ready() -> void:
	_last_refresh_ms = 0
	_ensure_ui_save_timer()
	_apply_ui_state(_load_ui_state())
	_refresh()
	# Ensure Known Synterfaces list is populated even before any AgentDef is loaded/created.
	_refresh_known_synterfaces_ui()
	_ensure_role_override_text_loaded()
	_init_packs_tab()
	_init_agentdef_guidance()
	_queue_ui_state_save() # ensures file exists after first open


func _init_agentdef_guidance() -> void:
	## Adds placeholder text and tooltips to AgentDef form fields that
	## a facilitator might find cryptic without in-panel guidance.
	if _agentdef_role:
		_agentdef_role.placeholder_text = "e.g. facilitator, narrator, analyst"
		_agentdef_role.tooltip_text = "The functional role this agent plays. Used by the role policy to determine which tools and actions it is allowed to use."
	if _agentdef_required_synterfaces:
		_agentdef_required_synterfaces.placeholder_text = "e.g. conversation_io, thread_scope, ui_hooks"
		_agentdef_required_synterfaces.tooltip_text = "Comma-separated list of synterface IDs this agent needs bound before it can run.\nSee 'Known Synterfaces' below for available IDs and descriptions."
	if _agentdef_tools:
		_agentdef_tools.placeholder_text = "e.g. SynTree, GodotUtils"
		_agentdef_tools.tooltip_text = "Comma-separated list of tool names the agent is allowed to call. Must match entries registered in the ToolRegistry."
	if _agentdef_synterface_defaults:
		_agentdef_synterface_defaults.placeholder_text = '{"conversation_io": {"scope": "global"}}'
		_agentdef_synterface_defaults.tooltip_text = "JSON object: per-synterface default values the host uses when binding this agent.\nLeave as {} if the host's own defaults are appropriate."
	if _agentdef_binding_hints:
		_agentdef_binding_hints.placeholder_text = '{"default_scope": "scensyn", "spawn_root_group": "game_session"}'
		_agentdef_binding_hints.tooltip_text = "JSON object: hints for the host's bind_synterfaces() call.\nCommon keys:\n• default_scope — namespace for scoped synterfaces (e.g. \"scensyn\")\n• spawn_root_group — scene group to search for the agent's root node"
	if _agentdef_logic_path:
		_agentdef_logic_path.placeholder_text = "res://path/to/behavior_tree.tres"
		_agentdef_logic_path.tooltip_text = "Path to the LimboAI behaviour tree (.tres) or other decision-logic resource for this agent."
	if _agentdef_description:
		_agentdef_description.placeholder_text = "Brief description of what this agent does"
	if _agentdef_id:
		_agentdef_id.tooltip_text = "Unique identifier for this agent. Used in slot assignments and SLOP /agents API calls."
	if _agent_spawn_path:
		_agent_spawn_path.placeholder_text = "res://path/to/agent_definition.tres"
		_agent_spawn_path.tooltip_text = "Path to an AgentDefinition .tres file. Use the Browse button or the AgentDefs tab to create/save one."

func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if (now - _last_refresh_ms) < _refresh_interval_ms:
		return
	_last_refresh_ms = now
	_refresh()

func _refresh() -> void:
	_refresh_components()
	_refresh_tasks()
	_refresh_resources()
	_refresh_patterns()
	_refresh_status()
	_refresh_controls_strip()
	_refresh_agents_tab()
	_refresh_console_tab()
	_refresh_synterface_issues_ui()
	_refresh_known_synterfaces_ui()
	_refresh_agent_slots_ui()


func _refresh_agents_tab() -> void:
	# Keep the agent dropdown reasonably fresh without user clicks.
	# (Cheap: agent count tends to be small.)
	if not _agent_list:
		return
	_update_agent_list()


func _refresh_console_tab() -> void:
	if not _console_agent or not _console_tool or not _console_op:
		return
	_update_agent_list_into(_console_agent, true)
	# Don't clobber user selection every refresh tick.
	# Rebuild tools list only when empty; user can force refresh via the button.
	if _console_tool.item_count <= 0:
		_update_tool_list()

func _get_app_host_router() -> Object:
	var tree := Engine.get_main_loop() as SceneTree
	if not tree or not tree.root:
		return null
	var host := tree.root.get_node_or_null("MetapunktAppHost")
	if not host:
		return null
	var o: Object = host as Object
	if o and o.has_method("get_synterface_issues") and o.has_method("set_override") and o.has_method("clear_override"):
		return o
	return null

func _get_router_obj_any() -> Object:
	var tree := Engine.get_main_loop() as SceneTree
	if not tree or not tree.root:
		return null
	var host := tree.root.get_node_or_null("MetapunktAppHost")
	return host as Object

func _refresh_synterface_issues_ui() -> void:
	_MetapunktSynterfaceSlotsUtilsScript.refresh_synterface_issues_ui(self)

func _format_user_synterfaces_issues(host: Object) -> String:
	return _MetapunktSynterfaceSlotsUtilsScript.format_user_synterfaces_issues(host)

func _on_open_user_synterfaces_pressed() -> void:
	_MetapunktSynterfaceSlotsUtilsScript.on_open_user_synterfaces_pressed(self)

func _open_in_file_manager(path_abs: String) -> void:
	_MetapunktSynterfaceSlotsUtilsScript.open_in_file_manager(self, path_abs)

func _refresh_agent_slots_ui() -> void:
	_MetapunktSynterfaceSlotsUtilsScript.refresh_agent_slots_ui(self)

func _validate_slot_assignments_ui(host: Object, slots: Dictionary, agents: Array, ep_obj: Object) -> void:
	_MetapunktSynterfaceSlotsUtilsScript.validate_slot_assignments_ui(self, host, slots, agents, ep_obj)

func _on_agent_slot_selected(index: int) -> void:
	_MetapunktSynterfaceSlotsUtilsScript.on_agent_slot_selected(self, index)

func _on_agent_slot_assign_pressed() -> void:
	_MetapunktSynterfaceSlotsUtilsScript.on_agent_slot_assign_pressed(self)

func _on_agent_slot_clear_pressed() -> void:
	_MetapunktSynterfaceSlotsUtilsScript.on_agent_slot_clear_pressed(self)

func _on_agent_slots_publish_pressed() -> void:
	await _MetapunktSynterfaceSlotsUtilsScript.on_agent_slots_publish_pressed(self)

func _update_synterface_impl_picker(impls: Array) -> void:
	_MetapunktSynterfaceSlotsUtilsScript.update_synterface_impl_picker(self, impls)

func _on_synterface_issue_selected(index: int) -> void:
	_MetapunktSynterfaceSlotsUtilsScript.on_synterface_issue_selected(self, index)

func _on_synterface_set_override_pressed() -> void:
	_MetapunktSynterfaceSlotsUtilsScript.on_synterface_set_override_pressed(self)

func _on_synterface_clear_override_pressed() -> void:
	_MetapunktSynterfaceSlotsUtilsScript.on_synterface_clear_override_pressed(self)


func _set_label(lbl: Label, msg: String) -> void:
	if lbl: lbl.text = msg


func _clear_label(lbl: Label) -> void:
	if lbl: lbl.text = ""


func _refresh_controls_strip() -> void:
	_MetapunktPanelStatusUtilsScript.refresh_controls_strip(_endpoint, _slop_bound, _hub_state, _hub_url)

func _refresh_components() -> void:
	_MetapunktPanelStatusUtilsScript.refresh_components(_endpoint, _components)

func _refresh_tasks() -> void:
	_MetapunktPanelStatusUtilsScript.refresh_tasks(_endpoint, _tasks)

func _refresh_resources() -> void:
	_MetapunktPanelStatusUtilsScript.refresh_resources(_endpoint, _resources)

func _refresh_patterns() -> void:
	_MetapunktPanelStatusUtilsScript.refresh_patterns(_patterns)

func _refresh_status() -> void:
	_MetapunktPanelStatusUtilsScript.refresh_status(_endpoint, _status)


func _get_endpoint_obj() -> Object:
	return _MetapunktPanelStatusUtilsScript.get_endpoint_obj(_endpoint)


func _get_hub_events_obj(ep_obj: Object) -> Object:
	return _MetapunktPanelStatusUtilsScript.get_hub_events_obj(ep_obj)


func _get_audit_logger_obj(ep_obj: Object) -> Object:
	return _MetapunktPanelStatusUtilsScript.get_audit_logger_obj(ep_obj)


func _hub_preset_event_types(idx: int) -> Array[String]:
	return _MetapunktPanelStatusUtilsScript.hub_preset_event_types(idx)


func _get_agent_registry(ep_obj: Object) -> Object:
	return _MetapunktPanelStatusUtilsScript.get_agent_registry(ep_obj)

func _update_agent_list_into(ob: OptionButton, include_none: bool) -> void:
	_MetapunktPanelStatusUtilsScript.update_agent_list_into(_endpoint, ob, include_none)


func _update_agent_list() -> void:
	if not _endpoint or not _agent_list:
		return
	_update_agent_list_into(_agent_list, false)


func _parse_json_object(text: String) -> Dictionary:
	return _MetapunktUiParseUtilsScript.parse_json_object(text)


func _stringify_json(d: Dictionary) -> String:
	return _MetapunktUiParseUtilsScript.stringify_json(d)


func _parse_tools_csv(text: String) -> Array:
	return _MetapunktUiParseUtilsScript.parse_csv(text)

func _parse_synterfaces_csv(text: String) -> Array:
	# Accept comma and newline separated synterfaces for ergonomics.
	return _MetapunktUiParseUtilsScript.parse_csv(text.replace("\n", ","))

func _get_merged_synterface_catalog() -> Dictionary:
	# Core + (optional) host-defined synterface catalog.
	var catalog: Dictionary = _SynterfaceCatalog.get_core_synterface_catalog_v1()
	var tree := Engine.get_main_loop() as SceneTree
	if not tree:
		return catalog
	var host := tree.root.get_node_or_null("MetapunktAppHost")
	if host and host.has_method("get_synterface_catalog"):
		var hc = host.call("get_synterface_catalog")
		if typeof(hc) == TYPE_DICTIONARY:
			for k in (hc as Dictionary).keys():
				catalog[k] = (hc as Dictionary)[k]
	return catalog

func _refresh_known_synterfaces_ui() -> void:
	if not _known_synterfaces_list:
		return
	var catalog: Dictionary = _get_merged_synterface_catalog()
	var keys: Array = catalog.keys()
	keys.sort()
	var sig := ",".join(keys)
	if sig == _known_synterfaces_signature and _known_synterfaces_list.item_count == keys.size():
		return
	_known_synterfaces_signature = sig

	var prev_selected: String = ""
	if _known_synterfaces_list.is_anything_selected():
		prev_selected = str(_known_synterfaces_list.get_item_text(_known_synterfaces_list.get_selected_items()[0])).strip_edges()

	_known_synterfaces_list.clear()
	for k in keys:
		var pid := str(k).strip_edges()
		if pid.is_empty():
			continue
		var i := _known_synterfaces_list.item_count
		_known_synterfaces_list.add_item(pid)
		_known_synterfaces_list.set_item_metadata(i, catalog.get(pid, {}))

	# Restore selection when possible, otherwise select first item (if any).
	if not prev_selected.is_empty():
		for i2 in range(_known_synterfaces_list.item_count):
			if str(_known_synterfaces_list.get_item_text(i2)).strip_edges() == prev_selected:
				_known_synterfaces_list.select(i2)
				_on_known_synterface_selected(i2)
				return
	if _known_synterfaces_list.item_count > 0:
		_known_synterfaces_list.select(0)
		_on_known_synterface_selected(0)
	else:
		_on_known_synterface_selected(-1)

func _on_known_synterface_selected(index: int) -> void:
	if not _known_synterfaces_desc:
		return
	if not _known_synterfaces_list or index < 0 or index >= _known_synterfaces_list.item_count:
		_known_synterfaces_desc.text = ""
		return
	var md_any: Variant = _known_synterfaces_list.get_item_metadata(index)
	var md: Dictionary = md_any if typeof(md_any) == TYPE_DICTIONARY else {}
	var desc := str(md.get("description", "")).strip_edges()
	var ver := str(md.get("version", "")).strip_edges()
	var header := str(_known_synterfaces_list.get_item_text(index)).strip_edges()
	var msg := header
	if not ver.is_empty():
		msg += " (%s)" % ver
	if not desc.is_empty():
		msg += "\n" + desc
	_known_synterfaces_desc.text = msg

func _on_known_synterface_copy_pressed() -> void:
	if not _known_synterfaces_list:
		return
	var selected := _known_synterfaces_list.get_selected_items()
	if selected.is_empty():
		if _known_synterfaces_desc:
			_known_synterfaces_desc.text = "Select a synterface id above to copy it."
		return
	var idx: int = int(selected[0])
	if idx < 0 or idx >= _known_synterfaces_list.item_count:
		return
	var pid := str(_known_synterfaces_list.get_item_text(idx)).strip_edges()
	if pid.is_empty():
		return
	DisplayServer.clipboard_set(pid)
	if _known_synterfaces_desc:
		# Keep the existing description, but prepend a short confirmation.
		var md_any: Variant = _known_synterfaces_list.get_item_metadata(idx)
		var md: Dictionary = md_any if typeof(md_any) == TYPE_DICTIONARY else {}
		var desc := str(md.get("description", "")).strip_edges()
		var ver := str(md.get("version", "")).strip_edges()
		var msg := "Copied: %s" % pid
		var header := pid + (" (%s)" % ver if not ver.is_empty() else "")
		if not desc.is_empty():
			_known_synterfaces_desc.text = msg + "\n" + header + "\n" + desc
		else:
			_known_synterfaces_desc.text = msg + "\n" + header


func _on_agentdef_template_pressed() -> void:
	if not _agentdef_template_menu:
		return
	_agentdef_template_menu.popup_centered()


func _on_agentdef_template_id_pressed(id: int) -> void:
	match id:
		0:
			_apply_agentdef_template_scensyn_narrator()
		1:
			_apply_agentdef_template_readymade_a1()
		_:
			return


func _apply_agentdef_template_scensyn_narrator() -> void:
	# A conservative starter template: core synterfaces + a namespaced story_state synterface.
	_editing_agentdef = AgentDefinition.new()
	_editing_agentdef.schema_version = "metapunkt.agentdef.v1"
	_editing_agentdef.agent_id = "scensyn_narrator"
	_editing_agentdef.agent_name = "ScenSyn Narrator"
	_editing_agentdef.role = "roleplay"
	_editing_agentdef.logic_type = "limboai"
	_editing_agentdef.logic_config = {"path": "res://ScenSyn/behavior_trees/narrator_bt.tres"}
	_editing_agentdef.required_tools = ["SynTree"]
	_editing_agentdef.required_synterfaces = ["conversation_io", "thread_scope", "ui_hooks", "scene_root", "scensyn.story_state"]
	# legacy
	_editing_agentdef.binding_hints = {"default_scope": "scensyn", "spawn_root_group": "game_session"}
	_editing_agentdef.synterface_defaults = {}
	# legacy
	_editing_agentdef.description = "Template: ScenSyn Narrator agent (Metapunkt-managed) with explicit synterfaces/bindings."
	_editing_agentdef.persona = ""
	_editing_agentdef.capabilities = {}
	if _agentdef_path:
		_agentdef_path.text = ""
	_agentdef_fill_form_from_resource(_editing_agentdef)
	_agentdef_set_status("Template loaded: ScenSyn Narrator")


func _apply_agentdef_template_readymade_a1() -> void:
	_editing_agentdef = AgentDefinition.new()
	_editing_agentdef.schema_version = "metapunkt.agentdef.v1"
	_editing_agentdef.agent_id = "readymade_a1"
	_editing_agentdef.agent_name = "ReadyMade A1 Synthesis Engine"
	_editing_agentdef.role = "facilitator"
	_editing_agentdef.logic_type = "limboai"
	_editing_agentdef.logic_config = {"path": "res://readymade/behavior_trees/a1_weekly_synthesis.tres"}
	_editing_agentdef.required_tools = ["SynTree", "GodotUtils"]
	_editing_agentdef.required_synterfaces = ["conversation_io", "thread_scope", "ui_hooks", "workplan", "readymade.workplan"]
	# legacy
	_editing_agentdef.binding_hints = {"default_scope": "readymade"}
	_editing_agentdef.synterface_defaults = {}
	# legacy
	_editing_agentdef.description = "Template: ReadyMade A1 agent with explicit workplan + UI hooks synterfaces."
	_editing_agentdef.persona = ""
	_editing_agentdef.capabilities = {}
	if _agentdef_path:
		_agentdef_path.text = ""
	_agentdef_fill_form_from_resource(_editing_agentdef)
	_agentdef_set_status("Template loaded: ReadyMade A1")

func _agentdef_validate_for_save(defn: AgentDefinition) -> Dictionary:
	return _MetapunktAgentDefUtilsScript.validate_for_save(self, defn)


func _logic_type_selected_text() -> String:
	return _MetapunktAgentDefUtilsScript.logic_type_selected_text(self)


func _agentdef_apply_form_to_resource(defn: AgentDefinition) -> void:
	_MetapunktAgentDefUtilsScript.apply_form_to_resource(self, defn)


func _agentdef_fill_form_from_resource(defn: AgentDefinition) -> void:
	_MetapunktAgentDefUtilsScript.fill_form_from_resource(self, defn)


func _on_agentdef_validate_bindings_pressed() -> void:
	_MetapunktAgentDefUtilsScript.on_validate_bindings_pressed(self)


func _agentdef_ensure_editing() -> AgentDefinition:
	if _editing_agentdef:
		return _editing_agentdef
	_editing_agentdef = AgentDefinition.new()
	_agentdef_fill_form_from_resource(_editing_agentdef)
	return _editing_agentdef


func _agentdef_set_status(msg: String) -> void:
	_set_label(_agentdef_status, msg)


func _roles_set_status(msg: String) -> void:
	_set_label(_role_status, msg)


func _agent_set_spawn_status(msg: String) -> void:
	_set_label(_agent_spawn_status, msg)


func _agent_set_manage_status(msg: String) -> void:
	_set_label(_agent_manage_status, msg)


func _get_role_policy(ep_obj: Object) -> Object:
	if not ep_obj:
		return null
	var rp_any: Variant = ep_obj.get("role_policy")
	return rp_any as Object


func _ensure_role_override_text_loaded() -> void:
	if not _endpoint or not _role_override_text:
		return
	var ep_obj := _get_endpoint_obj()
	var rp := _get_role_policy(ep_obj)
	if not rp or not rp.has_method("get_policy_dict"):
		return
	var pol: Dictionary = rp.call("get_policy_dict")
	var ov_any: Variant = pol.get("override", {})
	var ov: Dictionary = ov_any if typeof(ov_any) == TYPE_DICTIONARY else {}
	if _role_override_text.text.strip_edges().is_empty():
		_role_override_text.text = _stringify_json(ov) if not ov.is_empty() else "{}"


func _get_tool_registry(ep_obj: Object) -> Object:
	if not ep_obj:
		return null
	var tr_any: Variant = ep_obj.get("tool_registry")
	return tr_any as Object


func _update_tool_list() -> void:
	if not _console_tool or not _console_op:
		return
	var ep_obj := _get_endpoint_obj()
	var tr := _get_tool_registry(ep_obj)
	var prev_tool := ""
	if _console_tool.item_count > 0:
		prev_tool = str(_console_tool.get_item_metadata(_console_tool.selected)).strip_edges()
	_console_tool.clear()
	_tool_details_cache.clear()
	if not tr or not tr.has_method("list_tool_names"):
		_console_tool.add_item("(tool registry unavailable)")
		_console_tool.set_item_metadata(0, "")
		_console_op.clear()
		_console_op.add_item("(no ops)")
		_console_op.set_item_metadata(0, "")
		return
	var names: Array = tr.call("list_tool_names")
	names.sort()
	for n_any in names:
		var n := str(n_any).strip_edges()
		if n.is_empty():
			continue
		var details: Dictionary = tr.call("get_tool_details", n) if tr.has_method("get_tool_details") else {}
		_tool_details_cache[n] = details
		var i := _console_tool.item_count
		_console_tool.add_item(n)
		_console_tool.set_item_metadata(i, n)
	if _console_tool.item_count == 0:
		_console_tool.add_item("(no tools)")
		_console_tool.set_item_metadata(0, "")
	# Preserve previous selection when possible; otherwise default to first item.
	if not prev_tool.is_empty():
		for i in range(_console_tool.item_count):
			if str(_console_tool.get_item_metadata(i)).strip_edges() == prev_tool:
				_console_tool.select(i)
				_on_console_tool_selected(i)
				return
	_console_tool.select(0)
	_on_console_tool_selected(0)


func _update_ops_for_tool(tool_name: String) -> void:
	if not _console_op:
		return
	_console_op.clear()
	if tool_name.is_empty():
		_console_op.add_item("(no ops)")
		_console_op.set_item_metadata(0, "")
		_console_op.select(0)
		return
	var details: Dictionary = _tool_details_cache.get(tool_name, {})
	var ops_any: Variant = details.get("operations", [])
	var ops: Array = ops_any if typeof(ops_any) == TYPE_ARRAY else []
	if ops.is_empty():
		_console_op.add_item("(default)")
		_console_op.set_item_metadata(0, "")
		_console_op.select(0)
		return
	for op_any in ops:
		var op := str(op_any).strip_edges()
		if op.is_empty():
			continue
		var i := _console_op.item_count
		_console_op.add_item(op)
		_console_op.set_item_metadata(i, op)
	_console_op.select(0)


func _get_action_dispatcher(ep_obj: Object) -> Object:
	if not ep_obj:
		return null
	var ad_any: Variant = ep_obj.get("action_dispatcher")
	return ad_any as Object


func _console_set_status(msg: String) -> void:
	_set_label(_console_status, msg)


func _console_set_result(any: Variant) -> void:
	if not _console_result:
		return
	if typeof(any) == TYPE_DICTIONARY or typeof(any) == TYPE_ARRAY:
		_console_result.text = JSON.stringify(any, "\t")
	else:
		_console_result.text = str(any)


func _ensure_ui_save_timer() -> void:
	if _ui_save_timer:
		return
	_ui_save_timer = Timer.new()
	_ui_save_timer.one_shot = true
	_ui_save_timer.wait_time = 0.35
	_ui_save_timer.timeout.connect(_save_ui_state_now)
	# Editor/plugin startup can be sensitive to add_child timing; defer to avoid "parent busy" errors.
	add_child.call_deferred(_ui_save_timer)

func _start_ui_save_timer() -> void:
	if not _ui_save_timer:
		return
	# Ensure timer is actually in the SceneTree before starting.
	if not _ui_save_timer.is_inside_tree():
		call_deferred("_start_ui_save_timer")
		return
	_ui_save_timer.start()


func _queue_ui_state_save() -> void:
	if _ui_state_apply_guard:
		return
	_ensure_ui_save_timer()
	if _ui_save_timer:
		_start_ui_save_timer()


func _ui_state_path() -> String:
	var dest: String = RuntimeConfig.get_metapunkt_data_dir().path_join("ui_state.json")
	RuntimeConfig.migrate_file_if_needed(dest, ["user://metapunkt/ui_state.json"])
	return dest


func _load_ui_state() -> Dictionary:
	return _MetapunktUiStateUtilsScript.load_ui_state(_ui_state_path())


func _apply_ui_state(state: Dictionary) -> void:
	_ui_state_apply_guard = true
	_MetapunktUiStateUtilsScript.apply_ui_state(
		self, state, _slop_host, _slop_port, _hub_url, _hub_preset,
		_agent_spawn_path, _role_override_text, _agentdef_path, _console_args, _controls_tabs
	)
	_ui_state_apply_guard = false


func _gather_ui_state() -> Dictionary:
	return _MetapunktUiStateUtilsScript.gather_ui_state(
		self, _slop_host, _slop_port, _hub_url, _hub_preset,
		_agent_spawn_path, _role_override_text, _agentdef_path, _console_args, _controls_tabs
	)


func _save_ui_state_now() -> void:
	if _ui_state_apply_guard:
		return
	_MetapunktUiStateUtilsScript.save_ui_state_now(_ui_state_path(), _gather_ui_state())


func _on_agent_spawn_browse_pressed() -> void:
	if _agent_spawn_dialog:
		_agent_spawn_dialog.popup_centered_ratio(0.75)


func _on_agent_spawn_file_selected(path: String) -> void:
	if _agent_spawn_path:
		_agent_spawn_path.text = path
	_queue_ui_state_save()


func _on_agent_spawn_pressed() -> void:
	_agent_set_spawn_status("")
	var ep_obj := _get_endpoint_obj()
	if not ep_obj or not ep_obj.has_method("spawn_agent"):
		_agent_set_spawn_status("EndpointHandler missing spawn_agent()")
		return
	var p := (_agent_spawn_path.text.strip_edges() if _agent_spawn_path else "")
	if p.is_empty():
		_agent_set_spawn_status("Provide an AgentDefinition path (.tres).")
		return
	var res: Dictionary = await ep_obj.call("spawn_agent", p, "")
	if bool(res.get("ok", false)):
		_agent_set_spawn_status("Spawned: %s" % str(res.get("agent_id", "")))
	else:
		_agent_set_spawn_status("Spawn failed: %s" % str(res.get("error", "unknown")))
	_update_agent_list()


func _on_agent_refresh_pressed() -> void:
	_agent_set_manage_status("")
	_update_agent_list()


func _on_agent_stop_pressed() -> void:
	_agent_set_manage_status("")
	var ep_obj := _get_endpoint_obj()
	if not ep_obj or not ep_obj.has_method("stop_agent"):
		_agent_set_manage_status("EndpointHandler missing stop_agent()")
		return
	if not _agent_list or _agent_list.item_count == 0:
		return
	var idx := _agent_list.selected
	var aid := str(_agent_list.get_item_metadata(idx)).strip_edges()
	if aid.is_empty():
		return
	var res: Dictionary = await ep_obj.call("stop_agent", aid, "")
	if bool(res.get("ok", false)):
		_agent_set_manage_status("Stopped: %s" % aid)
	else:
		_agent_set_manage_status("Stop failed: %s" % str(res.get("error", "unknown")))
	_update_agent_list()


func _on_role_load_pressed() -> void:
	_roles_set_status("")
	var ep_obj := _get_endpoint_obj()
	var rp := _get_role_policy(ep_obj)
	if not rp or not rp.has_method("load_override_from_user"):
		_roles_set_status("RolePolicy unavailable")
		return
	rp.call("load_override_from_user")
	var pol: Dictionary = rp.call("get_policy_dict") if rp.has_method("get_policy_dict") else {}
	var ov_any: Variant = pol.get("override", {})
	var ov: Dictionary = ov_any if typeof(ov_any) == TYPE_DICTIONARY else {}
	if _role_override_text:
		_role_override_text.text = _stringify_json(ov) if not ov.is_empty() else "{}"
	_roles_set_status("Loaded override from Documents/Synesyn")
	_queue_ui_state_save()


func _on_role_save_pressed() -> void:
	_roles_set_status("")
	var ep_obj := _get_endpoint_obj()
	var rp := _get_role_policy(ep_obj)
	if not rp or not rp.has_method("save_override_to_user"):
		_roles_set_status("RolePolicy unavailable")
		return
	var ov: Dictionary = _parse_json_object(_role_override_text.text if _role_override_text else "")
	if ov.is_empty() and (_role_override_text and _role_override_text.text.strip_edges() not in ["", "{}", "{ }"]):
		_roles_set_status("Save failed: override must be a JSON object")
		return
	var ok := bool(rp.call("save_override_to_user", ov))
	if not ok:
		_roles_set_status("Save failed")
		return
	rp.call("load_override_from_user")
	_roles_set_status("Saved override to Documents/Synesyn")
	_queue_ui_state_save()


func _on_role_publish_pressed() -> void:
	_roles_set_status("")
	var ep_obj := _get_endpoint_obj()
	var rp := _get_role_policy(ep_obj)
	var audit := _get_audit_logger_obj(ep_obj)
	if not rp or not rp.has_method("get_policy_dict"):
		_roles_set_status("RolePolicy unavailable")
		return
	if not audit or not audit.has_method("hub_create_artifact_inline_json_async"):
		_roles_set_status("AuditLogger hub publishing unavailable")
		return
	# Ensure local override is saved before publishing snapshot
	_on_role_save_pressed()
	var pol: Dictionary = rp.call("get_policy_dict")
	var meta := {"provenance": {"generated_by": "metapunkt.ui"}}
	var res: Dictionary = await audit.call("hub_create_artifact_inline_json_async", "metapunkt.role_policy", pol, meta)
	if bool(res.get("ok", false)):
		_roles_set_status("Published to hub (status %s)" % str(res.get("status", "")))
	else:
		_roles_set_status("Publish failed: %s" % str(res.get("error", "unknown")))
	_queue_ui_state_save()


func _on_agentdef_new_pressed() -> void:
	_editing_agentdef = AgentDefinition.new()
	if _agentdef_path:
		_agentdef_path.text = ""
	_agentdef_fill_form_from_resource(_editing_agentdef)
	_agentdef_set_status("New AgentDefinition")
	_queue_ui_state_save()


func _on_agentdef_load_dialog_pressed() -> void:
	if _agentdef_load_dialog:
		_agentdef_load_dialog.popup_centered_ratio(0.75)


func _on_agentdef_load_file_selected(path: String) -> void:
	if _agentdef_path:
		_agentdef_path.text = path
	var def_any := load(path)
	if not (def_any is AgentDefinition):
		_agentdef_set_status("Load failed: not an AgentDefinition")
		return
	_editing_agentdef = def_any
	_agentdef_fill_form_from_resource(_editing_agentdef)
	_agentdef_set_status("Loaded: %s" % path)
	_queue_ui_state_save()


func _on_agentdef_logic_browse_pressed() -> void:
	if _agentdef_logic_dialog:
		_agentdef_logic_dialog.popup_centered_ratio(0.75)


func _on_agentdef_logic_file_selected(path: String) -> void:
	if _agentdef_logic_path:
		_agentdef_logic_path.text = path
	_queue_ui_state_save()


func _on_agentdef_save_pressed() -> void:
	_agentdef_set_status("")
	var defn := _agentdef_ensure_editing()
	_agentdef_apply_form_to_resource(defn)
	var v: Dictionary = _agentdef_validate_for_save(defn)
	var errs: Array = v.get("errors", [])
	var warns: Array = v.get("warnings", [])
	if not errs.is_empty():
		_agentdef_set_status("Validation failed: %s" % str(errs))
		return
	var p := (_agentdef_path.text.strip_edges() if _agentdef_path else "")
	if p.is_empty():
		if _agentdef_save_dialog:
			_agentdef_save_dialog.popup_centered_ratio(0.75)
		else:
			_agentdef_set_status("Provide a save path")
		return
	# Runtime safety: res:// is read-only in exported builds.
	if not Engine.is_editor_hint() and p.begins_with("res://"):
		_agentdef_set_status("Cannot save to res:// at runtime. Use Documents/Synesyn")
		return
	var err := ResourceSaver.save(defn, p)
	if err != OK:
		_agentdef_set_status("Save failed: %s" % error_string(err))
		return
	if not warns.is_empty():
		_agentdef_set_status("Saved (warnings): %s | %s" % [p, str(warns)])
	else:
		_agentdef_set_status("Saved: %s" % p)
	_queue_ui_state_save()


func _on_agentdef_save_file_selected(path: String) -> void:
	if _agentdef_path:
		_agentdef_path.text = path
	_on_agentdef_save_pressed()


func _on_console_refresh_agents_pressed() -> void:
	_update_agent_list_into(_console_agent, true)
	_queue_ui_state_save()


func _on_console_refresh_tools_pressed() -> void:
	_update_tool_list()
	_queue_ui_state_save()


func _on_console_tool_selected(_idx: int) -> void:
	var tool_name := ""
	if _console_tool and _console_tool.item_count > 0:
		tool_name = str(_console_tool.get_item_metadata(_console_tool.selected)).strip_edges()
	_update_ops_for_tool(tool_name)
	_queue_ui_state_save()


func _on_console_run_pressed() -> void:
	_console_set_status("")
	var ep_obj := _get_endpoint_obj()
	var ad := _get_action_dispatcher(ep_obj)
	if not ad or not ad.has_method("dispatch_action"):
		_console_set_status("ActionDispatcher unavailable")
		return

	var agent_id := ""
	if _console_agent and _console_agent.item_count > 0:
		agent_id = str(_console_agent.get_item_metadata(_console_agent.selected)).strip_edges()

	var tool_name := ""
	if _console_tool and _console_tool.item_count > 0:
		tool_name = str(_console_tool.get_item_metadata(_console_tool.selected)).strip_edges()
	if tool_name.is_empty():
		_console_set_status("Select a tool")
		return

	var op := ""
	if _console_op and _console_op.item_count > 0:
		op = str(_console_op.get_item_metadata(_console_op.selected)).strip_edges()

	var args_any := JSON.parse_string(_console_args.text if _console_args else "{}")
	if typeof(args_any) != TYPE_DICTIONARY:
		_console_set_status("Args must be a JSON object")
		return
	var args: Dictionary = args_any
	if not op.is_empty() and not args.has("operation"):
		args["operation"] = op

	_console_set_status("Running…")
	var res: Dictionary = await ad.call("dispatch_action", agent_id, tool_name, args, "", [])
	_console_set_result(res)
	_console_set_status("Done")
	_queue_ui_state_save()


func _on_controls_tab_changed(_idx: int) -> void:
	_queue_ui_state_save()


func _on_any_ui_state_changed(_a = null) -> void:
	_queue_ui_state_save()

func _on_slop_start_pressed() -> void:
	var ep_obj := _get_endpoint_obj()
	if not ep_obj:
		return
	var host := (_slop_host.text.strip_edges() if _slop_host else "127.0.0.1")
	if host.is_empty():
		host = "127.0.0.1"
	var port := 8080
	if _slop_port:
		port = int(_slop_port.value)
	# EndpointHandler.start_server() includes port fallback logic.
	if ep_obj.has_method("start_server"):
		ep_obj.call("start_server", host, port)
	_refresh()


func _on_slop_stop_pressed() -> void:
	var ep_obj := _get_endpoint_obj()
	if not ep_obj:
		return
	if ep_obj.has_method("stop_server"):
		ep_obj.call("stop_server")
	_refresh()


func _on_hub_connect_pressed() -> void:
	var ep_obj := _get_endpoint_obj()
	if not ep_obj:
		return
	var url := (_hub_url.text.strip_edges() if _hub_url else "")
	var hub := _get_hub_events_obj(ep_obj)
	if hub and hub.has_method("connect_to_hub"):
		# Keep AuditLogger aligned (used elsewhere as canonical hub URL).
		var audit := _get_audit_logger_obj(ep_obj)
		if audit:
			audit.set("hub_base_url", url)
		hub.call("connect_to_hub", url)
	_refresh()


func _on_hub_disconnect_pressed() -> void:
	var ep_obj := _get_endpoint_obj()
	if not ep_obj:
		return
	var hub := _get_hub_events_obj(ep_obj)
	if hub and hub.has_method("disconnect_from_hub"):
		hub.call("disconnect_from_hub")
	_refresh()


func _on_hub_subscribe_pressed() -> void:
	var ep_obj := _get_endpoint_obj()
	if not ep_obj:
		return
	var hub := _get_hub_events_obj(ep_obj)
	if not hub:
		return
	var idx := (_hub_preset.selected if _hub_preset else 0)
	var types := _hub_preset_event_types(idx)
	if hub.has_method("subscribe"):
		hub.call("subscribe", types)
	_refresh()


# ---------------------------------------------------------------------------
# Packs tab
# ---------------------------------------------------------------------------

func _init_packs_tab() -> void:
	if not _controls_tabs:
		return
	# Build UI
	_packs_ui = _MetapunktPacksUtilsScript.build_packs_tab(_controls_tabs)
	# Create registry with ToolRegistry + AuditLogger from EndpointHandler
	var ep_obj := _get_endpoint_obj()
	var tr := _get_tool_registry(ep_obj)
	var audit := _get_audit_logger_obj(ep_obj)
	_packs_registry = _CapabilityPackRegistryScript.new(tr, audit)
	# Wire signals
	var install_btn: Button = _packs_ui.get("install_btn")
	var refresh_btn: Button = _packs_ui.get("refresh_btn")
	var uninstall_btn: Button = _packs_ui.get("uninstall_btn")
	var pack_list: ItemList = _packs_ui.get("list")
	var install_dialog: FileDialog = _packs_ui.get("install_dialog")
	if install_btn:
		install_btn.pressed.connect(_on_pack_install_pressed)
	var reinstall_bundled_btn: Button = _packs_ui.get("reinstall_bundled_btn")
	if reinstall_bundled_btn:
		reinstall_bundled_btn.pressed.connect(_on_pack_reinstall_bundled_pressed)
	if refresh_btn:
		refresh_btn.pressed.connect(_on_pack_refresh_pressed)
	if uninstall_btn:
		uninstall_btn.pressed.connect(_on_pack_uninstall_pressed)
	if pack_list:
		pack_list.item_selected.connect(_on_pack_list_selected)
	if install_dialog:
		install_dialog.dir_selected.connect(_on_pack_install_dir_selected)
	# Auto-install bundled packs that aren't yet installed
	_auto_install_bundled_packs()
	# Initial refresh + load enabled pack tools/panels
	_refresh_packs()


func _auto_install_bundled_packs() -> void:
	## Scans res://addons/metapunkt/Packs/ for bundled packs and installs any
	## that are not already present in the user packs directory.
	var bundled_root := "res://addons/metapunkt/Packs"
	var dir := DirAccess.open(bundled_root)
	if not dir:
		return
	var installed: Array[Dictionary] = CapabilityPackStore.list_installed()
	var installed_ids: Array[String] = []
	for pack_entry in installed:
		installed_ids.append(str(pack_entry.get("id", "")))

	dir.list_dir_begin()
	var entry_name := dir.get_next()
	while not entry_name.is_empty():
		if dir.current_is_dir() and not entry_name.begins_with(".") and not entry_name.begins_with("_"):
			var pack_dir := bundled_root.path_join(entry_name)
			# Check if it has a pack.json
			if FileAccess.file_exists(pack_dir.path_join("pack.json")):
				var manifest := CapabilityPackManifest.load_from_directory(pack_dir)
				if manifest.is_valid and manifest.id not in installed_ids and not CapabilityPackStore.is_bundled_dismissed(manifest.id):
					var result: Dictionary = CapabilityPackStore.install_from_directory(pack_dir)
					if bool(result.get("ok", false)):
						print("[Metapunkt] Auto-installed bundled pack: %s v%s" % [manifest.id, manifest.version])
						# Enable all capabilities by default for bundled packs
						for cap_any in manifest.capabilities:
							if typeof(cap_any) == TYPE_DICTIONARY:
								var cap_id := str((cap_any as Dictionary).get("capability_id", ""))
								if not cap_id.is_empty():
									CapabilityPackStore.set_capability_enabled(manifest.id, manifest.version, cap_id, true)
					else:
						push_warning("[Metapunkt] Failed to auto-install bundled pack '%s': %s" % [entry_name, str(result.get("error", ""))])
		entry_name = dir.get_next()
	dir.list_dir_end()


func _refresh_packs() -> void:
	var pack_list: ItemList = _packs_ui.get("list")
	var status_label: Label = _packs_ui.get("status")
	var panels_container: TabContainer = _packs_ui.get("panels_container")
	if not pack_list:
		return
	_MetapunktPacksUtilsScript.refresh_pack_list(pack_list, status_label)
	if _packs_registry:
		var result := _packs_registry.refresh_all(panels_container)
		if status_label:
			status_label.text += " | Tools: %d, Panels: %d" % [result.get("tools_registered", 0), result.get("panels_mounted", 0)]


func _on_pack_install_pressed() -> void:
	var install_dialog: FileDialog = _packs_ui.get("install_dialog")
	if install_dialog:
		install_dialog.popup_centered_ratio(0.6)


func _on_pack_reinstall_bundled_pressed() -> void:
	var status_label: Label = _packs_ui.get("status")
	_MetapunktPacksUtilsScript.reinstall_bundled_packs(status_label, _packs_registry)
	_refresh_packs()


func _on_pack_install_dir_selected(dir_path: String) -> void:
	var status_label: Label = _packs_ui.get("status")
	_MetapunktPacksUtilsScript.install_pack_from_path(dir_path, status_label, _packs_registry)
	_refresh_packs()


func _on_pack_refresh_pressed() -> void:
	_refresh_packs()


func _on_pack_uninstall_pressed() -> void:
	var pack_list: ItemList = _packs_ui.get("list")
	var status_label: Label = _packs_ui.get("status")
	if pack_list:
		_MetapunktPacksUtilsScript.uninstall_selected(pack_list, status_label, _packs_registry)
		_clear_pack_details_ui()
		_refresh_packs()


func _clear_pack_details_ui() -> void:
	## Clear the details label, capability toggles, and unmount all panels.
	var details_label: Label = _packs_ui.get("details")
	var caps_container: VBoxContainer = _packs_ui.get("caps_container")
	var panels_container: TabContainer = _packs_ui.get("panels_container")
	if details_label:
		details_label.text = ""
	if caps_container:
		for child_node in caps_container.get_children():
			caps_container.remove_child(child_node)
			child_node.queue_free()
	if panels_container:
		for child_node in panels_container.get_children():
			panels_container.remove_child(child_node)
			child_node.queue_free()


func _on_pack_list_selected(idx: int) -> void:
	var pack_list: ItemList = _packs_ui.get("list")
	var details_label: Label = _packs_ui.get("details")
	var caps_container: VBoxContainer = _packs_ui.get("caps_container")
	if not pack_list or idx < 0 or idx >= pack_list.item_count:
		return
	var pack_info: Dictionary = pack_list.get_item_metadata(idx)
	_MetapunktPacksUtilsScript.show_pack_details(pack_info, details_label, caps_container, _packs_registry)
