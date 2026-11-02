extends Node

## What a ScenSyn session runs alongside a Story Stage: vis_story renders feeding the
## slideshow, verse reading and heartbeat ruminations from external input, render
## requests from the stage's settings, and the AI model controls. Attached as a child of
## the stage by ScenSynStageHost.attach_session_services().
##
## GameSessionStartupUtils reads its collaborators off an owner by name, so the field
## names below (_hub, vis_story_service, continuity_service, render_purpose_service,
## verse_reading_service, game_flow_manager, _last_vis_story_export_packet_id) are what
## that code expects and must not be renamed.

const ScenSynRenderPurposeServiceScript = preload("res://ScenSyn/scripts/services/scensyn_render_purpose_service.gd")
const ScenSynVisStoryServiceScript = preload("res://ScenSyn/scripts/services/scensyn_vis_story_service.gd")
const ScenSynContinuityServiceScript = preload("res://ScenSyn/scripts/services/scensyn_continuity_service.gd")
const ScenSynVerseReadingServiceScript = preload("res://ScenSyn/scripts/services/scensyn_verse_reading_service.gd")
const GameSessionStartupUtilsRef = preload("res://ScenSyn/scripts/core/game_session_startup_utils.gd")
const GameSessionNarrativeUtilsScript = preload("res://ScenSyn/scripts/core/game_session_narrative_utils.gd")
const PORTRAIT_CHECKPOINT := "Juggernaut-XL_v9_RunDiffusionPhoto_v2.safetensors"

var _stage: Node = null
var _hub: HubSubstrateClient = null
var render_purpose_service: ScenSynRenderPurposeService = null
var vis_story_service: ScenSynVisStoryService = null
var continuity_service: ScenSynContinuityService = null
var verse_reading_service = null
var _last_vis_story_export_packet_id: String = ""
var game_flow_manager = null

var hamburger_settings_panel: Control = null
var _settings_vbox: VBoxContainer = null
var _model_selector: OptionButton = null
var _provider_label: Label = null
var _api_key_edit: LineEdit = null
var _api_key_save_btn: Button = null
var _temp_override_check: CheckBox = null
var _temp_model_selector: OptionButton = null
var _temp_override_enabled := false
var _temp_model_name := ""


func hub() -> HubSubstrateClient:
	if _hub == null:
		_hub = HubSubstrateClient.new()
		add_child(_hub)
		_hub.configure_from_runtime_config()
	return _hub


func _get_render_purpose_service() -> ScenSynRenderPurposeService:
	if render_purpose_service != null and is_instance_valid(render_purpose_service):
		return render_purpose_service
	render_purpose_service = ScenSynRenderPurposeServiceScript.new()
	add_child(render_purpose_service)
	# Refresh sprites when portrait renders are materialized.
	if render_purpose_service.has_signal("sprite_materialized"):
		render_purpose_service.sprite_materialized.connect(_on_synpunkt_sprite_materialized)
	if render_purpose_service.has_signal("sprite_materialization_failed"):
		render_purpose_service.sprite_materialization_failed.connect(_on_synpunkt_sprite_materialization_failed)
	return render_purpose_service


func setup(stage: Node) -> void:
	_stage = stage
	print("StoryStage: _setup_vis_story_pipeline() ENTER")
	if _hub == null:
		hub()
		print("StoryStage: vis_story hub client created")
	vis_story_service = ScenSynVisStoryServiceScript.new()
	continuity_service = ScenSynContinuityServiceScript.new()
	_get_render_purpose_service()
	verse_reading_service = ScenSynVerseReadingServiceScript.new()
	add_child(verse_reading_service)
	game_flow_manager = Global.get_game_flow_manager() if Global and Global.has_method("get_game_flow_manager") else null
	var mpm = Global.get_metaprompt_manager() if Global and Global.has_method("get_metaprompt_manager") else null
	if mpm != null and verse_reading_service != null and mpm.has_method("set_verse_reading_service"):
		mpm.set_verse_reading_service(verse_reading_service)

	if render_purpose_service.has_signal("vis_story_images_ready"):
		if not render_purpose_service.vis_story_images_ready.is_connected(_on_vis_story_images_ready):
			render_purpose_service.vis_story_images_ready.connect(_on_vis_story_images_ready)

	# Fed by vis_story renders, so scoped to scenarios that declare [VIS_STORY].
	if _stage.background_controller and _stage.scenario_section_enabled("vis_story", false):
		_stage.background_controller.enable_slideshow()

	var listener = Global.get_external_input_listener() if Global and Global.has_method("get_external_input_listener") else null
	if listener == null or not listener.has_signal("data_received"):
		print("StoryStage: external input listener not available")
		print("StoryStage: _setup_vis_story_pipeline() EXIT")
		return
	_disconnect_stale_static_callbacks(listener)
	if not listener.data_received.is_connected(_relay_vis_story):
		listener.data_received.connect(_relay_vis_story)
	if not listener.data_received.is_connected(_relay_verse):
		listener.data_received.connect(_relay_verse)
	if not listener.data_received.is_connected(_relay_turn_to_slideshow):
		listener.data_received.connect(_relay_turn_to_slideshow)
	if verse_reading_service.has_signal("heartbeat_rumination_available"):
		var hb_cb := Callable(GameSessionStartupUtilsRef, "_on_heartbeat_rumination")
		if not verse_reading_service.heartbeat_rumination_available.is_connected(hb_cb):
			verse_reading_service.heartbeat_rumination_available.connect(hb_cb)
	print("StoryStage: vis_story + verse + slideshow pipelines connected")
	print("StoryStage: _setup_vis_story_pipeline() EXIT")


## A session view that was left for this stage may still have its own static callbacks
## on the listener; they would export the same turn twice.
func _disconnect_stale_static_callbacks(listener: Node) -> void:
	for conn in listener.data_received.get_connections():
		if typeof(conn) != TYPE_DICTIONARY:
			continue
		var callable_val: Variant = conn.get("callable", null)
		if callable_val == null:
			continue
		var cb: Callable = callable_val
		var method_name: String = cb.get_method()
		if method_name in ["_on_external_input_for_vis_story", "_on_external_input_for_verse"]:
			listener.data_received.disconnect(cb)
			print("StoryStage: disconnected stale static callback: %s" % method_name)


func _relay_vis_story(data: Dictionary) -> void:
	await GameSessionStartupUtilsRef._maybe_export_vis_story_for_external_input(self, data)


func _relay_verse(data: Dictionary) -> void:
	GameSessionStartupUtilsRef._on_external_input_for_verse(data, self)


func _relay_turn_to_slideshow(data: Dictionary) -> void:
	var turn_packet: Variant = data.get("turn_packet", null)
	if typeof(turn_packet) != TYPE_DICTIONARY:
		return
	var cycle_id: int = int(data.get("window_id", 0))
	if cycle_id > 0:
		_stage.notify_turn_started(cycle_id)


func _on_vis_story_images_ready(_job_id: String, turn_id: int, image_paths: Array, _meta: Dictionary) -> void:
	if not _stage.background_controller:
		return
	print("StoryStage: vis_story images ready — %d images for turn %d" % [image_paths.size(), turn_id])
	_stage.background_controller.enqueue_images(image_paths, turn_id)


func _on_synpunkt_sprite_materialized(job_id: String, character_name: String, animation_frames: String, _dst_abs: String, _meta: Dictionary) -> void:
	var char_s: String = String(character_name).strip_edges()
	var anim_s: String = String(animation_frames).strip_edges()
	if anim_s.is_empty():
		anim_s = "idle"
	_stage.set_render_status("Sprite materialized. job=%s %s/%s" % [str(job_id).left(12), char_s, anim_s])
	_stage.refresh_character_art(char_s)


func _on_synpunkt_sprite_materialization_failed(job_id: String, error: String, _meta: Dictionary) -> void:
	_stage.set_render_status("Sprite materialization failed. job=%s err=%s" % [str(job_id).left(12), str(error)])


# ── Render requests ──────────────────────────────────────────────────────

func request_render(kind: String) -> void:
	match kind:
		"background":
			await _render_background()
		"portrait":
			await _render_portrait()
		"prop_card":
			await _render_prop_card()


func _render_background() -> void:
	var svc: ScenSynRenderPurposeService = _get_render_purpose_service()
	_stage.set_render_status("Submitting background render…")
	var res: Dictionary = await svc.submit_background_render({})
	if res.get("ok", false) == true:
		_stage.set_render_status("Background render queued. job=%s" % str(res.get("job_id", "")).left(12))
	else:
		_stage.set_render_status("Background render submit failed: %s" % str(res.get("error", res)))


func _portrait_request(speaker_text: String, animation: String) -> Dictionary:
	return {
		"character_slug": speaker_text,
		"materialize_to_sprites_generated": true,
		"animation_frames": animation,
		"transparent_background": true,
		"frame_count": 4,
		"checkpoint_name": PORTRAIT_CHECKPOINT,
	}


func _render_portrait() -> void:
	var svc: ScenSynRenderPurposeService = _get_render_purpose_service()
	var speaker_text: String = _stage.current_speaker_for_render()
	_stage.set_render_status("Submitting portrait renders (idle + talking)…")
	var res_idle: Dictionary = await svc.submit_portrait_render(_portrait_request(speaker_text, "idle"))
	if res_idle.get("ok", false) != true:
		_stage.set_render_status("Portrait idle render submit failed: %s" % str(res_idle.get("error", res_idle)))
		return
	var res_talking: Dictionary = await svc.submit_portrait_render(_portrait_request(speaker_text, "talking"))
	if res_talking.get("ok", false) == true:
		_stage.set_render_status("Portrait renders queued. idle=%s talking=%s speaker=%s" % [str(res_idle.get("job_id", "")).left(12), str(res_talking.get("job_id", "")).left(12), speaker_text])
	else:
		_stage.set_render_status("Portrait talking render submit failed: %s (idle job=%s speaker=%s)" % [str(res_talking.get("error", res_talking)), str(res_idle.get("job_id", "")).left(12), speaker_text])


func _render_prop_card() -> void:
	var svc: ScenSynRenderPurposeService = _get_render_purpose_service()
	_stage.set_render_status("Submitting prop card render…")
	var res: Dictionary = await svc.submit_prop_card_render({})
	if res.get("ok", false) == true:
		_stage.set_render_status("Prop card render queued. job=%s" % str(res.get("job_id", "")).left(12))
	else:
		_stage.set_render_status("Prop card render submit failed: %s" % str(res.get("error", res)))


# ── AI model controls (mirrors the session view's hamburger menu) ────────

func ensure_model_controls() -> void:
	hamburger_settings_panel = _stage.settings_panel
	if _settings_vbox == null:
		_settings_vbox = _stage._settings_vbox
	GameSessionNarrativeUtilsScript.ensure_ai_model_controls(self)


func _ai_model_manager() -> Object:
	var plugin_manager = Global.get_plugin_manager() if Global and Global.has_method("get_plugin_manager") else null
	return plugin_manager.get_ai_model_manager() if plugin_manager and plugin_manager.has_method("get_ai_model_manager") else null


func _on_model_selected_scensyn(_index: int) -> void:
	var model_text: String = _model_selector.get_item_text(_model_selector.selected)
	var ai_model_manager: Object = _ai_model_manager()
	if ai_model_manager and ai_model_manager.has_method("set_current_model"):
		var res = ai_model_manager.set_current_model(model_text)
		if res is Dictionary and res.get("success", false):
			_update_provider_label()
		else:
			push_warning("StoryStage: Failed to set model '" + model_text + "': " + String(res.get("error", "unknown")))


func _update_provider_label() -> void:
	if not _model_selector:
		return
	var model_text: String = _model_selector.get_item_text(_model_selector.selected)
	var ai_model_manager: Object = _ai_model_manager()
	var provider := ""
	if ai_model_manager and ai_model_manager.has_method("get_provider_for_model"):
		provider = String(ai_model_manager.get_provider_for_model(model_text))
	if _provider_label:
		_provider_label.text = "Provider: " + (provider if provider != "" else "unknown")


func _on_api_key_save_pressed() -> void:
	var api_key: String = String(_api_key_edit.text).strip_edges()
	if api_key == "":
		return
	var model_text: String = _model_selector.get_item_text(_model_selector.selected)
	var ai_model_manager: Object = _ai_model_manager()
	if not ai_model_manager:
		return
	var provider: String = String(ai_model_manager.get_provider_for_model(model_text)) if ai_model_manager.has_method("get_provider_for_model") else ""
	if provider != "" and ai_model_manager.has_method("set_api_key"):
		ai_model_manager.set_api_key(provider, api_key)


func _on_temp_override_toggled(is_enabled: bool) -> void:
	_temp_override_enabled = is_enabled
	if _temp_model_selector:
		_temp_model_selector.disabled = not is_enabled


func _on_temp_model_selected(_index: int) -> void:
	if _temp_model_selector:
		_temp_model_name = _temp_model_selector.get_item_text(_temp_model_selector.selected)
