extends RefCounted
class_name SynpunktStartupUtils

static func ready(owner: Control) -> void:
	var hub := HubSubstrateClient.new()
	owner.set("_hub", hub)
	owner.add_child(hub)
	var present_image_resolve_http := HTTPRequest.new()
	present_image_resolve_http.timeout = 30.0
	present_image_resolve_http.set_http_proxy("", -1)
	present_image_resolve_http.set_https_proxy("", -1)
	owner.set("_present_image_resolve_http", present_image_resolve_http)
	owner.add_child(present_image_resolve_http)
	present_image_resolve_http.request_completed.connect(owner._on_present_image_resolve_completed)
	hub.configure_from_runtime_config()
	var hub_url: LineEdit = owner.get("_hub_url")
	if hub_url:
		hub_url.text = hub.base_url
	owner.call("_init_render_settings_ui")
	owner.call("_init_ui_connections_all")
	owner.call("_init_render_jobs_ui")
	owner.call("_init_advanced_refs_ui")
	owner.call("_load_how_to_text")
	if not Engine.is_editor_hint():
		owner.call_deferred("_autostart_hub_if_configured")
	var workflow_select: OptionButton = owner.get("_workflow_select")
	if workflow_select and not Engine.is_editor_hint():
		owner.call_deferred("_kick_refresh_render_workflow_selector")
	if not Engine.is_editor_hint():
		owner.call_deferred("_kick_refresh_render_results")
		owner.call_deferred("_refresh_render_jobs", 100, "startup")
	owner.set("_session_id", SynesynSession.get_or_create_session_id("synpunkt"))
	var render := SynesynRenderService.new()
	owner.set("_render", render)
	owner.add_child(render)
	render.set_hub_client(hub)
	render.comfy.status_changed.connect(func(t: String): owner._set_status("[Render] " + t))
	render.comfy.progress_changed.connect(func(stage: String, pct: float):
		owner._set_status("[Render] %s %.0f%%" % [stage, pct])
	)
	hub.hub_event_received.connect(owner._on_hub_event_received)
	owner.call("_ensure_render_results_bound")
	owner.call("_init_host_join_ui")
	var host_copy_url: Button = owner.get("_host_copy_url")
	if host_copy_url:
		host_copy_url.pressed.connect(owner._on_copy_host_url)
	var join_test: Button = owner.get("_join_test")
	if join_test:
		join_test.pressed.connect(func(): await owner._on_join_test())
	var join_save: Button = owner.get("_join_save")
	if join_save:
		join_save.pressed.connect(owner._on_join_save)
	owner.call("_init_artifacts_toggle")
	var toggle_artifacts: BaseButton = owner.get("_toggle_artifacts")
	if toggle_artifacts:
		toggle_artifacts.toggled.connect(owner._on_toggle_artifacts)
	var refresh_btn: Button = owner.get("_refresh_btn")
	if refresh_btn:
		refresh_btn.pressed.connect(owner._on_refresh_closures_pressed)
	var load_btn: Button = owner.get("_load_btn")
	if load_btn:
		load_btn.pressed.connect(owner._on_load_selected_closure_pressed)
	var refresh_store_closures_btn: Button = owner.get("_refresh_store_closures_btn")
	if refresh_store_closures_btn:
		refresh_store_closures_btn.pressed.connect(owner._on_refresh_store_closures_pressed)
	var refresh_store_context_packs_btn: Button = owner.get("_refresh_store_context_packs_btn")
	if refresh_store_context_packs_btn:
		refresh_store_context_packs_btn.pressed.connect(owner._on_refresh_store_context_packs_pressed)
	var delete_closure_btn: Button = owner.get("_delete_closure_btn")
	if delete_closure_btn:
		delete_closure_btn.pressed.connect(owner._on_delete_selected_closure_pressed)
	var create_demo_closure: Button = owner.get("_create_demo_closure")
	if create_demo_closure:
		create_demo_closure.pressed.connect(owner._on_create_demo_closure_pressed)
	var refresh_flowdocs_btn: Button = owner.get("_refresh_flowdocs_btn")
	if refresh_flowdocs_btn:
		refresh_flowdocs_btn.pressed.connect(owner._on_refresh_flowdocs_pressed)
	var load_flowdoc_btn: Button = owner.get("_load_flowdoc_btn")
	if load_flowdoc_btn:
		load_flowdoc_btn.pressed.connect(owner._on_load_selected_flowdoc_pressed)
	var delete_syndoc_btn: Button = owner.get("_delete_syndoc_btn")
	if delete_syndoc_btn:
		delete_syndoc_btn.pressed.connect(owner._on_delete_selected_syndoc_pressed)
	var new_empty_flowdoc: Button = owner.get("_new_empty_flowdoc")
	if new_empty_flowdoc:
		new_empty_flowdoc.pressed.connect(owner._on_new_empty_flowdoc)
	var apply_hub_url: Button = owner.get("_apply_hub_url")
	if apply_hub_url:
		apply_hub_url.pressed.connect(owner._on_apply_hub_url)
	var generate_btn: Button = owner.get("_generate_btn")
	if generate_btn:
		generate_btn.pressed.connect(owner._on_generate_flowdoc)
	var save_btn: Button = owner.get("_save_btn")
	if save_btn:
		save_btn.pressed.connect(owner._on_save_flowdoc_pressed)
	var save_version_btn: Button = owner.get("_save_version_btn")
	if save_version_btn:
		save_version_btn.pressed.connect(owner._on_save_flowdoc_version_pressed)
	var validate_btn: Button = owner.get("_validate_btn")
	if validate_btn:
		validate_btn.pressed.connect(owner._on_validate_flowdoc)
	var import_slides_deck: Button = owner.get("_import_slides_deck")
	if import_slides_deck:
		import_slides_deck.pressed.connect(func(): await owner._on_import_slides_deck())
	var export_slides_deck: Button = owner.get("_export_slides_deck")
	if export_slides_deck:
		export_slides_deck.pressed.connect(func(): await owner._on_export_slides_deck())


static func autostart_hub_if_configured(owner: Control) -> void:
	if Engine.is_editor_hint():
		return
	var hub: Node = owner.get("_hub")
	if not is_instance_valid(hub):
		return
	var cfg: Dictionary = RuntimeConfig.load_config()
	var hub_cfg_any: Variant = cfg.get("hub", {})
	var hub_cfg: Dictionary = hub_cfg_any if typeof(hub_cfg_any) == TYPE_DICTIONARY else {}
	if not bool(hub_cfg.get("autostart", true)):
		return
	var base_url := str(ProviderModePolicy.get_hub_base_url(cfg)).strip_edges()
	if base_url.is_empty():
		return
	var u := base_url.to_lower()
	var is_local := (u.find("127.0.0.1") != -1) or (u.find("localhost") != -1) or (u.find("[::1]") != -1)
	if not is_local:
		return
	var health: Dictionary = await hub.check_health()
	if bool(health.get("ok", false)):
		return
	var exec_path := HubLocator.find_hub_exe(cfg)
	if exec_path.is_empty():
		owner.call("_set_status", "Hub down. Autostart enabled, but hub not found at %s." % HubLocator.describe_expected_location())
		return
	var args: PackedStringArray = PackedStringArray([])
	var pid := OS.create_process(exec_path, args, false)
	if pid <= 0:
		owner.call("_set_status", "Hub down. Autostart failed to start hub process.")
		return
	for _i in range(30):
		await owner.get_tree().create_timer(0.25).timeout
		var h2: Dictionary = await hub.check_health()
		if bool(h2.get("ok", false)):
			owner.call("_set_status", "Hub started.")
			return
	owner.call("_set_status", "Hub starting… (still not reachable; try again shortly)")
