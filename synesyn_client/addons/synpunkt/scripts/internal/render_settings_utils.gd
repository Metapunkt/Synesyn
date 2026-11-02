extends RefCounted
class_name SynpunktRenderSettingsUtils

static func init_render_settings_ui(owner: Control) -> void:
	var cfg: Dictionary = RuntimeConfig.load_config()
	var render_cfg_any: Variant = cfg.get("render", {})
	var render_cfg: Dictionary = render_cfg_any if typeof(render_cfg_any) == TYPE_DICTIONARY else {}
	var auto_any: Variant = render_cfg.get("auto_save_workflows", null)
	if auto_any == null:
		owner.set("_render_auto_save_workflows_enabled", bool(render_cfg.get("prompt_save_workflow", false)))
	else:
		owner.set("_render_auto_save_workflows_enabled", bool(auto_any))
	var auto_save_workflows: BaseButton = owner.get("_auto_save_workflows")
	if auto_save_workflows:
		auto_save_workflows.button_pressed = bool(owner.get("_render_auto_save_workflows_enabled"))
		if not auto_save_workflows.toggled.is_connected(owner._on_auto_save_workflows_toggled):
			auto_save_workflows.toggled.connect(owner._on_auto_save_workflows_toggled)
	load_render_artifact_naming_settings(owner, cfg)
	load_comfy_url_settings(owner, cfg)
	load_render_route_mode_settings(owner, cfg)


static func load_comfy_url_settings(owner: Control, cfg: Dictionary) -> void:
	var render_cfg_any: Variant = cfg.get("render", {})
	var render_cfg: Dictionary = render_cfg_any if typeof(render_cfg_any) == TYPE_DICTIONARY else {}
	var current_url := str(render_cfg.get("comfy_url", "")).strip_edges()
	var comfy_url: LineEdit = owner.get("_comfy_url")
	if comfy_url and not current_url.is_empty():
		comfy_url.text = current_url
	var hist_any: Variant = render_cfg.get("comfy_url_history", [])
	owner.set("_comfy_url_recent", [])
	var comfy_url_recent_any: Variant = owner.get("_comfy_url_recent")
	var comfy_url_recent: Array = comfy_url_recent_any if typeof(comfy_url_recent_any) == TYPE_ARRAY else []
	if typeof(hist_any) == TYPE_ARRAY:
		for v in (hist_any as Array):
			var u := str(v).strip_edges()
			if u.is_empty():
				continue
			if comfy_url_recent.has(u):
				continue
			comfy_url_recent.append(u)
			if comfy_url_recent.size() >= 5:
				break
	owner.set("_comfy_url_recent", comfy_url_recent)
	refresh_comfy_url_history_picker(owner)


static func save_comfy_url_settings(owner: Control) -> bool:
	var cfg: Dictionary = RuntimeConfig.load_config()
	var render_cfg_any: Variant = cfg.get("render", {})
	var render_cfg: Dictionary = render_cfg_any if typeof(render_cfg_any) == TYPE_DICTIONARY else {}
	var comfy_url: LineEdit = owner.get("_comfy_url")
	if comfy_url:
		render_cfg["comfy_url"] = comfy_url.text.strip_edges()
	render_cfg["comfy_url_history"] = owner.get("_comfy_url_recent")
	cfg["render"] = render_cfg
	return RuntimeConfig.save_config(cfg)


static func load_render_route_mode_settings(owner: Control, cfg: Dictionary) -> void:
	var render_cfg_any: Variant = cfg.get("render", {})
	var render_cfg: Dictionary = render_cfg_any if typeof(render_cfg_any) == TYPE_DICTIONARY else {}
	var mode := str(render_cfg.get("routing_mode", "direct")).strip_edges().to_lower()
	if mode != "hub":
		mode = "direct"
	owner.set("_render_route_mode", mode)
	var render_route_mode_picker: OptionButton = owner.get("_render_route_mode_picker")
	if render_route_mode_picker:
		render_route_mode_picker.select(1 if mode == "hub" else 0)


static func save_render_route_mode_settings(owner: Control) -> bool:
	var cfg: Dictionary = RuntimeConfig.load_config()
	var render_cfg_any: Variant = cfg.get("render", {})
	var render_cfg: Dictionary = render_cfg_any if typeof(render_cfg_any) == TYPE_DICTIONARY else {}
	render_cfg["routing_mode"] = str(owner.get("_render_route_mode")).strip_edges().to_lower()
	cfg["render"] = render_cfg
	return RuntimeConfig.save_config(cfg)


static func on_render_route_mode_selected(owner: Control, idx: int) -> void:
	var mode := "hub" if int(idx) == 1 else "direct"
	owner.set("_render_route_mode", mode)
	if save_render_route_mode_settings(owner):
		owner.call("_set_status", "Render route set to %s/comfyui." % mode)
	else:
		owner.call("_set_status", "Render route save failed (kept in-memory: %s)." % mode)


static func refresh_comfy_url_history_picker(owner: Control) -> void:
	var comfy_url_history: OptionButton = owner.get("_comfy_url_history")
	if not comfy_url_history:
		return
	owner.set("_comfy_url_history_refreshing", true)
	comfy_url_history.clear()
	comfy_url_history.add_item("Recent URLs…", 0)
	comfy_url_history.set_item_metadata(0, {"kind": "placeholder"})
	var idx := 1
	var comfy_url_recent_any: Variant = owner.get("_comfy_url_recent")
	var comfy_url_recent: Array = comfy_url_recent_any if typeof(comfy_url_recent_any) == TYPE_ARRAY else []
	for url_any in comfy_url_recent:
		var url := str(url_any).strip_edges()
		comfy_url_history.add_item(url, idx)
		comfy_url_history.set_item_metadata(idx, {"kind": "url", "url": url})
		idx += 1
	comfy_url_history.select(0)
	owner.set("_comfy_url_history_refreshing", false)


static func on_comfy_url_history_selected(owner: Control, idx: int) -> void:
	var refreshing := bool(owner.get("_comfy_url_history_refreshing"))
	var comfy_url_history: OptionButton = owner.get("_comfy_url_history")
	var comfy_url: LineEdit = owner.get("_comfy_url")
	if refreshing or not comfy_url_history or not comfy_url:
		return
	var md: Variant = comfy_url_history.get_item_metadata(idx)
	if md == null or typeof(md) != TYPE_DICTIONARY:
		return
	var meta: Dictionary = md
	if str(meta.get("kind", "")).strip_edges() != "url":
		return
	var url := str(meta.get("url", "")).strip_edges()
	if url.is_empty():
		return
	comfy_url.text = url
	save_comfy_url_settings(owner)
	owner.call("_set_status", "ComfyUI URL selected: %s" % url)


static func remember_comfy_url(owner: Control, url: String) -> void:
	var u := String(url).strip_edges()
	if u.is_empty():
		return
	var next: Array[String] = [u]
	var comfy_url_recent_any: Variant = owner.get("_comfy_url_recent")
	var comfy_url_recent: Array = comfy_url_recent_any if typeof(comfy_url_recent_any) == TYPE_ARRAY else []
	for existing_any in comfy_url_recent:
		var existing := str(existing_any).strip_edges()
		if existing == u:
			continue
		next.append(existing)
		if next.size() >= 5:
			break
	owner.set("_comfy_url_recent", next)
	var comfy_url: LineEdit = owner.get("_comfy_url")
	if comfy_url:
		comfy_url.text = u
	save_comfy_url_settings(owner)
	refresh_comfy_url_history_picker(owner)


static func on_auto_save_workflows_toggled(owner: Control, enabled: bool) -> void:
	owner.set("_render_auto_save_workflows_enabled", bool(enabled))
	var cfg: Dictionary = RuntimeConfig.load_config()
	var render_cfg_any: Variant = cfg.get("render", {})
	var render_cfg: Dictionary = render_cfg_any if typeof(render_cfg_any) == TYPE_DICTIONARY else {}
	render_cfg["auto_save_workflows"] = bool(owner.get("_render_auto_save_workflows_enabled"))
	cfg["render"] = render_cfg
	if RuntimeConfig.save_config(cfg):
		owner.call("_set_status", "Render: saved setting (auto_save_workflows=%s)." % str(owner.get("_render_auto_save_workflows_enabled")))
	else:
		owner.call("_set_status", "Render: failed to save setting.")


static func load_render_artifact_naming_settings(owner: Control, cfg: Dictionary) -> void:
	var render_cfg_any: Variant = cfg.get("render", {})
	var render_cfg: Dictionary = render_cfg_any if typeof(render_cfg_any) == TYPE_DICTIONARY else {}
	var prefix := str(render_cfg.get("artifact_name_prefix", "Render")).strip_edges()
	if prefix.is_empty():
		prefix = "Render"
	owner.set("_render_artifact_name_prefix", prefix)
	owner.set("_render_artifact_name_next_index", max(1, int(render_cfg.get("artifact_name_next_index", 1))))
	var render_artifact_name_default: LineEdit = owner.get("_render_artifact_name_default")
	if render_artifact_name_default:
		render_artifact_name_default.text = str(owner.get("_render_artifact_name_prefix"))


static func save_render_artifact_naming_settings(owner: Control) -> bool:
	var cfg: Dictionary = RuntimeConfig.load_config()
	var render_cfg_any: Variant = cfg.get("render", {})
	var render_cfg: Dictionary = render_cfg_any if typeof(render_cfg_any) == TYPE_DICTIONARY else {}
	render_cfg["artifact_name_prefix"] = owner.get("_render_artifact_name_prefix")
	render_cfg["artifact_name_next_index"] = owner.get("_render_artifact_name_next_index")
	if render_cfg.has("artifact_name_overrides"):
		render_cfg.erase("artifact_name_overrides")
	cfg["render"] = render_cfg
	return RuntimeConfig.save_config(cfg)


static func next_default_render_artifact_name(owner: Control) -> String:
	var idx := max(1, int(owner.get("_render_artifact_name_next_index")))
	var out := "%s %04d" % [str(owner.get("_render_artifact_name_prefix")), idx]
	owner.set("_render_artifact_name_next_index", idx + 1)
	save_render_artifact_naming_settings(owner)
	return out


static func artifact_display_name_from_metadata_json(metadata_text: String) -> String:
	var txt := String(metadata_text).strip_edges()
	if txt.is_empty():
		return ""
	var m_any: Variant = JSON.parse_string(txt)
	if typeof(m_any) != TYPE_DICTIONARY:
		return ""
	var m: Dictionary = m_any
	var name := str(m.get("display_name", "")).strip_edges()
	if not name.is_empty():
		return name
	var ui_any: Variant = m.get("ui", {})
	if typeof(ui_any) == TYPE_DICTIONARY:
		var ui: Dictionary = ui_any
		name = str(ui.get("display_name", "")).strip_edges()
		if not name.is_empty():
			return name
	return ""


static func metadata_dict_from_text(metadata_text: String) -> Dictionary:
	var txt := String(metadata_text).strip_edges()
	if txt.is_empty():
		return {}
	var any: Variant = JSON.parse_string(txt)
	return any if typeof(any) == TYPE_DICTIONARY else {}


static func artifact_ext_from_uri(owner: Control, uri: String) -> String:
	var u := String(uri).strip_edges()
	if u.is_empty():
		return ""
	var p := str(owner.call("_path_from_file_uri", u))
	if p.is_empty():
		p = u
	var ext := p.get_extension().strip_edges().to_lower()
	return ext


static func artifact_size_from_uri(owner: Control, uri: String) -> int:
	var p := str(owner.call("_path_from_file_uri", uri))
	if p.is_empty() or not FileAccess.file_exists(p):
		return -1
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return -1
	var n := int(f.get_length())
	f.close()
	return n


static func artifact_size_human(bytes_count: int) -> String:
	if bytes_count < 0:
		return "?"
	if bytes_count < 1024:
		return "%d B" % bytes_count
	if bytes_count < 1024 * 1024:
		return "%.1f KB" % (float(bytes_count) / 1024.0)
	return "%.2f MB" % (float(bytes_count) / 1024.0 / 1024.0)


static func artifact_display_name_for_id(_artifact_id: String, metadata_text: String = "") -> String:
	return artifact_display_name_from_metadata_json(metadata_text)


static func artifact_item_label(artifact_id: String, created_at: String = "", metadata_text: String = "") -> String:
	var aid := String(artifact_id).strip_edges()
	var created := String(created_at).strip_edges()
	var name := artifact_display_name_for_id(aid, metadata_text)
	if name.is_empty():
		return "%s (%s)" % [aid, created] if not created.is_empty() else aid
	var core := "%s  [%s]" % [name, aid.left(12)]
	return "%s  (%s)" % [core, created] if not created.is_empty() else core


static func save_render_artifact_default_name_from_ui(owner: Control) -> void:
	var render_artifact_name_default: LineEdit = owner.get("_render_artifact_name_default")
	if not render_artifact_name_default:
		return
	var prefix := render_artifact_name_default.text.strip_edges()
	if prefix.is_empty():
		owner.call("_set_status", "Render: default artifact name cannot be empty.")
		return
	owner.set("_render_artifact_name_prefix", prefix)
	if save_render_artifact_naming_settings(owner):
		owner.call("_set_status", "Render: saved default artifact name prefix '%s'." % prefix)
	else:
		owner.call("_set_status", "Render: failed to save default artifact name prefix.")
