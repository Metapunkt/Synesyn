extends RefCounted
class_name SynpunktUiHubUtils

const SyndocSlidesUtilsScript = preload("res://addons/synpunkt/scripts/internal/syndoc_slides_utils.gd")

static func init_artifacts_toggle(owner: Control) -> void:
	var root: Node = owner.get("_root")
	var body_any := root.get_node_or_null("Body") if root else null
	if body_any and body_any is HSplitContainer:
		owner.set("_artifacts_last_split_offset", int((body_any as HSplitContainer).split_offset))
	var toggle_artifacts: BaseButton = owner.get("_toggle_artifacts")
	if toggle_artifacts:
		set_artifacts_visible(owner, bool(toggle_artifacts.button_pressed), false)


static func on_toggle_artifacts(owner: Control, pressed: bool) -> void:
	set_artifacts_visible(owner, pressed, true)


static func set_artifacts_visible(owner: Control, visible: bool, announce: bool) -> void:
	owner.set("_artifacts_visible", visible)
	var root: Node = owner.get("_root")
	var body_any := root.get_node_or_null("Body") if root else null
	if not body_any or not (body_any is HSplitContainer):
		return
	var body: HSplitContainer = body_any
	var left_any := body.get_node_or_null("Left")
	if left_any and left_any is Control:
		var left: Control = left_any
		if not visible:
			owner.set("_artifacts_last_split_offset", int(body.split_offset))
			left.visible = false
			body.split_offset = 0
			if announce:
				owner.call("_set_status", "Artifacts panel hidden.")
		else:
			left.visible = true
			body.split_offset = int(owner.get("_artifacts_last_split_offset"))
			if announce:
				owner.call("_set_status", "Artifacts panel shown.")


static func init_host_join_ui(owner: Control) -> void:
	var cfg: Dictionary = RuntimeConfig.load_config()
	var hub_cfg: Dictionary = cfg.get("hub", {}) if typeof(cfg.get("hub", {})) == TYPE_DICTIONARY else {}
	var join_hub_url: LineEdit = owner.get("_join_hub_url")
	var hub: Node = owner.get("_hub")
	if join_hub_url:
		join_hub_url.text = str(hub_cfg.get("base_url", hub.base_url if hub else "")).strip_edges()
	var join_use_auth: BaseButton = owner.get("_join_use_auth")
	var join_auth_token: LineEdit = owner.get("_join_auth_token")
	if join_use_auth and join_auth_token:
		var auth_cfg: Dictionary = hub_cfg.get("auth", {}) if typeof(hub_cfg.get("auth", {})) == TYPE_DICTIONARY else {}
		join_use_auth.button_pressed = bool(auth_cfg.get("enabled", false))
		join_auth_token.text = str(auth_cfg.get("token", "")).strip_edges()
	var host_ip: OptionButton = owner.get("_host_ip")
	if host_ip:
		host_ip.clear()
		var ips := get_local_ipv4_candidates()
		if ips.is_empty():
			ips = ["127.0.0.1"]
		for i in range(ips.size()):
			host_ip.add_item(ips[i], i)


static func get_local_ipv4_candidates() -> Array[String]:
	var out: Array[String] = []
	for ip_any in IP.get_local_addresses():
		var ip := str(ip_any).strip_edges()
		if ip.is_empty() or ip.contains(":") or ip == "127.0.0.1" or ip.begins_with("169.254."):
			continue
		out.append(ip)
	out.sort()
	return out


static func get_host_share_url(owner: Control) -> String:
	var ip := "127.0.0.1"
	var host_ip: OptionButton = owner.get("_host_ip")
	if host_ip and host_ip.item_count > 0:
		ip = host_ip.get_item_text(host_ip.selected).strip_edges()
	var port := 17777
	var host_port: SpinBox = owner.get("_host_port")
	if host_port:
		port = int(host_port.value)
	return "http://%s:%d" % [ip, port]


static func on_copy_host_url(owner: Control) -> void:
	var url := get_host_share_url(owner)
	DisplayServer.clipboard_set(url)
	owner.call("_set_status", "Host URL copied: %s" % url)


static func apply_hub_settings_in_memory(owner: Control, url: String, use_auth: bool, token: String) -> void:
	var norm_url := str(ProviderModePolicy.get_hub_base_url({"hub": {"base_url": url}})).strip_edges()
	var hub: Node = owner.get("_hub")
	if hub:
		hub.base_url = norm_url
		hub.auth_enabled = bool(use_auth)
		hub.auth_token = token.strip_edges()
	var hub_url: LineEdit = owner.get("_hub_url")
	if hub_url and hub:
		hub_url.text = hub.base_url


static func on_join_test(owner: Control) -> void:
	var join_hub_url: LineEdit = owner.get("_join_hub_url")
	if not join_hub_url:
		return
	var url := join_hub_url.text.strip_edges()
	if url.is_empty():
		owner.call("_set_status", "Join: Hub URL is empty.")
		return
	var join_use_auth: BaseButton = owner.get("_join_use_auth")
	var join_auth_token: LineEdit = owner.get("_join_auth_token")
	var use_auth := bool(join_use_auth.button_pressed) if join_use_auth else false
	var token := join_auth_token.text.strip_edges() if join_auth_token else ""
	apply_hub_settings_in_memory(owner, url, use_auth, token)
	owner.call("_set_status", "Join: Testing hub health…")
	var hub: Node = owner.get("_hub")
	var res: Dictionary = await hub.check_health()
	if bool(res.get("ok", false)):
		owner.call("_set_status", "Join: OK (hub reachable).")
	else:
		owner.call("_set_status", "Join: FAIL (%s)" % str(res.get("error", res)))


static func on_join_save(owner: Control) -> void:
	var join_hub_url: LineEdit = owner.get("_join_hub_url")
	if not join_hub_url:
		return
	var url := join_hub_url.text.strip_edges()
	if url.is_empty():
		owner.call("_set_status", "Join: Hub URL is empty.")
		return
	var join_use_auth: BaseButton = owner.get("_join_use_auth")
	var join_auth_token: LineEdit = owner.get("_join_auth_token")
	var use_auth := bool(join_use_auth.button_pressed) if join_use_auth else false
	var token := join_auth_token.text.strip_edges() if join_auth_token else ""
	var cfg: Dictionary = RuntimeConfig.load_config()
	var hub_cfg: Dictionary = cfg.get("hub", {}) if typeof(cfg.get("hub", {})) == TYPE_DICTIONARY else {}
	hub_cfg["base_url"] = str(ProviderModePolicy.get_hub_base_url({"hub": {"base_url": url}})).strip_edges()
	hub_cfg["auth"] = {"enabled": use_auth, "token": token}
	cfg["hub"] = hub_cfg
	if RuntimeConfig.save_config(cfg):
		var hub: Node = owner.get("_hub")
		hub.configure_from_runtime_config()
		var hub_url: LineEdit = owner.get("_hub_url")
		if hub_url:
			hub_url.text = hub.base_url
		owner.call("_set_status", "Join: Saved hub settings.")
	else:
		owner.call("_set_status", "Join: Failed to save config.")


static func on_export_slides_deck(owner: Control) -> void:
	var export_slides_deck: Button = owner.get("_export_slides_deck")
	if not export_slides_deck:
		return
	var flowdoc_model_any: Variant = owner.get("_flowdoc_model")
	var flowdoc_model: Dictionary = flowdoc_model_any if typeof(flowdoc_model_any) == TYPE_DICTIONARY else {}
	if flowdoc_model.is_empty():
		owner.call("_set_status", "Load or generate a SynDoc first.")
		return
	var deck := SyndocSlidesUtilsScript.flowdoc_to_slides_deck(flowdoc_model)
	var meta := {"provenance": {"generated_by": "synpunkt.syndoc.export_slides_deck", "session_id": owner.get("_session_id")}, "refs": {"syndoc_artifact_id": owner.get("_active_flowdoc_id")}}
	var hub: Node = owner.get("_hub")
	var res: Dictionary = await hub.create_artifact_inline_json("json.slides_deck", deck, meta)
	if bool(res.get("ok", false)):
		var id := str(res.get("id", "")).strip_edges()
		var slides_deck_artifact_id: LineEdit = owner.get("_slides_deck_artifact_id")
		if slides_deck_artifact_id:
			slides_deck_artifact_id.text = id
		owner.call("_set_status", "Exported slides deck: %s" % id)
	else:
		owner.call("_set_status", "Slides export failed: %s" % str(res.get("error", res)))


static func on_import_slides_deck(owner: Control) -> void:
	var import_slides_deck: Button = owner.get("_import_slides_deck")
	if not import_slides_deck:
		return
	var slides_deck_artifact_id: LineEdit = owner.get("_slides_deck_artifact_id")
	var id := slides_deck_artifact_id.text.strip_edges() if slides_deck_artifact_id else ""
	if id.is_empty():
		owner.call("_set_status", "Provide a slides deck artifact id first.")
		return
	var hub: Node = owner.get("_hub")
	var res: Dictionary = await hub.get_artifact_json(id)
	if not bool(res.get("ok", false)):
		owner.call("_set_status", "Slides import failed: %s" % str(res.get("error", res)))
		return
	var deck_any: Variant = res.get("json", {})
	if typeof(deck_any) != TYPE_DICTIONARY:
		owner.call("_set_status", "Slides import failed: artifact JSON is not a dictionary.")
		return
	var deck: Dictionary = deck_any
	var flowdoc := SyndocSlidesUtilsScript.slides_deck_to_flowdoc(deck)
	owner.set("_flowdoc_model", flowdoc)
	var flowdoc_json: TextEdit = owner.get("_flowdoc_json")
	if flowdoc_json:
		flowdoc_json.text = JSON.stringify(flowdoc, "\t")
	owner.call("_sync_from_raw_json")
	owner.call("_set_status", "Imported slides deck into SynDoc.")
