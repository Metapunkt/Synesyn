extends RefCounted
class_name MetapunktUiStateUtils

static func _coerce_int(v: Variant, default_value: int) -> int:
	match typeof(v):
		TYPE_INT:
			return int(v)
		TYPE_FLOAT:
			return floori(v)
		TYPE_STRING:
			var s := str(v).strip_edges()
			return s.to_int() if not s.is_empty() else default_value
		_:
			return default_value


static func load_ui_state(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if not f:
		return {}
	var txt := f.get_as_text()
	f.close()
	var obj := JSON.parse_string(txt)
	return obj if typeof(obj) == TYPE_DICTIONARY else {}


static func apply_ui_state(
	owner: Control,
	state: Dictionary,
	slop_host: LineEdit,
	slop_port: SpinBox,
	hub_url: LineEdit,
	hub_preset: OptionButton,
	agent_spawn_path: LineEdit,
	role_override_text: TextEdit,
	agentdef_path: LineEdit,
	console_args: TextEdit,
	controls_tabs: TabContainer
) -> void:
	if slop_host and state.has("slop_host"):
		slop_host.text = str(state.get("slop_host"))
	if slop_port and state.has("slop_port"):
		slop_port.value = float(_coerce_int(state.get("slop_port"), 8080))
	if hub_url and state.has("hub_url"):
		hub_url.text = str(state.get("hub_url"))
	if hub_preset and state.has("hub_preset"):
		var i := _coerce_int(state.get("hub_preset"), 0)
		if i >= 0 and i < hub_preset.item_count:
			hub_preset.select(i)
	if agent_spawn_path and state.has("agent_spawn_path"):
		agent_spawn_path.text = str(state.get("agent_spawn_path"))
	if role_override_text and state.has("role_override_text"):
		role_override_text.text = str(state.get("role_override_text"))
	if agentdef_path and state.has("agentdef_path"):
		agentdef_path.text = str(state.get("agentdef_path"))
	if console_args and state.has("console_args"):
		console_args.text = str(state.get("console_args"))
	if controls_tabs and state.has("controls_tab"):
		var t := _coerce_int(state.get("controls_tab"), 0)
		controls_tabs.current_tab = clamp(t, 0, controls_tabs.get_tab_count() - 1)
	var top_split := owner.get_node_or_null("VBoxContainer/TopSplit") as VSplitContainer
	if top_split and state.has("top_split_offset"):
		top_split.split_offset = _coerce_int(state.get("top_split_offset"), top_split.split_offset)
	var main_split := owner.get_node_or_null("VBoxContainer/TopSplit/VSplitContainer") as VSplitContainer
	if main_split and state.has("main_split_offset"):
		main_split.split_offset = _coerce_int(state.get("main_split_offset"), main_split.split_offset)


static func gather_ui_state(
	owner: Control,
	slop_host: LineEdit,
	slop_port: SpinBox,
	hub_url: LineEdit,
	hub_preset: OptionButton,
	agent_spawn_path: LineEdit,
	role_override_text: TextEdit,
	agentdef_path: LineEdit,
	console_args: TextEdit,
	controls_tabs: TabContainer
) -> Dictionary:
	var state := {}
	state["slop_host"] = (slop_host.text if slop_host else "")
	state["slop_port"] = int(slop_port.value) if slop_port else 8080
	state["hub_url"] = (hub_url.text if hub_url else "")
	state["hub_preset"] = (hub_preset.selected if hub_preset else 0)
	state["agent_spawn_path"] = (agent_spawn_path.text if agent_spawn_path else "")
	state["role_override_text"] = (role_override_text.text if role_override_text else "")
	state["agentdef_path"] = (agentdef_path.text if agentdef_path else "")
	state["console_args"] = (console_args.text if console_args else "{}")
	state["controls_tab"] = (controls_tabs.current_tab if controls_tabs else 0)
	var top_split := owner.get_node_or_null("VBoxContainer/TopSplit") as VSplitContainer
	if top_split:
		state["top_split_offset"] = top_split.split_offset
	var main_split := owner.get_node_or_null("VBoxContainer/TopSplit/VSplitContainer") as VSplitContainer
	if main_split:
		state["main_split_offset"] = main_split.split_offset
	return state


static func save_ui_state_now(path: String, state: Dictionary) -> void:
	var dest: String = path.strip_edges()
	if dest.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
	var f := FileAccess.open(dest, FileAccess.WRITE)
	if not f:
		return
	f.store_string(JSON.stringify(state, "\t"))
	f.close()
