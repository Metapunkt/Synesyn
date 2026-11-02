extends Control

@onready var open_scensyn_button: Button = %OpenScenSynButton
@onready var open_readymade_button: Button = %OpenReadyMadeButton
@onready var open_tools_button: Button = %OpenToolsButton
@onready var open_story_log_player_button: Button = get_node_or_null("%OpenStoryLogPlayerButton") as Button
@onready var shell_margin: MarginContainer = $ShellCenter/ShellMargin
@onready var shell_row: HBoxContainer = $ShellCenter/ShellMargin/ShellRow
@onready var brand_margin: MarginContainer = $ShellCenter/ShellMargin/ShellRow/BrandCard/BrandMargin
@onready var brand_vbox: VBoxContainer = $ShellCenter/ShellMargin/ShellRow/BrandCard/BrandMargin/BrandVBox
@onready var brand_logo_rect: TextureRect = $ShellCenter/ShellMargin/ShellRow/BrandCard/BrandMargin/BrandVBox/TextureRect
@onready var brand_title_label: Label = $ShellCenter/ShellMargin/ShellRow/BrandCard/BrandMargin/BrandVBox/Title
@onready var brand_subtitle_label: Label = $ShellCenter/ShellMargin/ShellRow/BrandCard/BrandMargin/BrandVBox/Subtitle
@onready var brand_support_label: Label = $ShellCenter/ShellMargin/ShellRow/BrandCard/BrandMargin/BrandVBox/BrandSupportText
@onready var right_column: VBoxContainer = $ShellCenter/ShellMargin/ShellRow/RightColumn
@onready var launch_margin: MarginContainer = $ShellCenter/ShellMargin/ShellRow/RightColumn/LaunchCard/LaunchMargin
@onready var launch_vbox: VBoxContainer = $ShellCenter/ShellMargin/ShellRow/RightColumn/LaunchCard/LaunchMargin/LaunchVBox
@onready var hub_margin: MarginContainer = $ShellCenter/ShellMargin/ShellRow/RightColumn/HubCard/HubMargin
@onready var hub_vbox: VBoxContainer = $ShellCenter/ShellMargin/ShellRow/RightColumn/HubCard/HubMargin/HubVBox
@onready var hub_section_title: Label = $ShellCenter/ShellMargin/ShellRow/RightColumn/HubCard/HubMargin/HubVBox/HubSectionTitle
@onready var hub_section_description: Label = $ShellCenter/ShellMargin/ShellRow/RightColumn/HubCard/HubMargin/HubVBox/HubSectionDescription
@onready var hub_buttons_grid: GridContainer = $ShellCenter/ShellMargin/ShellRow/RightColumn/HubCard/HubMargin/HubVBox/HubButtons
@onready var help_margin: MarginContainer = $ShellCenter/ShellMargin/ShellRow/RightColumn/HelpCard/HelpMargin
@onready var help_vbox: VBoxContainer = $ShellCenter/ShellMargin/ShellRow/RightColumn/HelpCard/HelpMargin/HelpVBox
@onready var help_title_label: Label = $ShellCenter/ShellMargin/ShellRow/RightColumn/HelpCard/HelpMargin/HelpVBox/HelpTitle
@onready var help_description_label: Label = $ShellCenter/ShellMargin/ShellRow/RightColumn/HelpCard/HelpMargin/HelpVBox/HelpDescription

@onready var hub_status_label: Label = get_node_or_null("%HubStatusLabel") as Label
@onready var hub_url_label: Label = get_node_or_null("%HubUrlLabel") as Label
@onready var start_hub_button: Button = get_node_or_null("%StartHubButton") as Button
@onready var stop_hub_button: Button = get_node_or_null("%StopHubButton") as Button
@onready var restart_hub_button: Button = get_node_or_null("%RestartHubButton") as Button
@onready var open_hub_config_button: Button = get_node_or_null("%OpenHubConfigButton") as Button
@onready var how_to_button: Button = get_node_or_null("%HowToButton") as Button
@onready var how_to_popup: PopupPanel = get_node_or_null("%HowToPopup") as PopupPanel
@onready var how_to_rich_text: RichTextLabel = get_node_or_null("%HowToRichText") as RichTextLabel
@onready var how_to_close_button: Button = get_node_or_null("%HowToCloseButton") as Button

@onready var _bg_color_rect: ColorRect = %ColorRect
@onready var _brand_card: PanelContainer = $ShellCenter/ShellMargin/ShellRow/BrandCard
@onready var _launch_card: PanelContainer = $ShellCenter/ShellMargin/ShellRow/RightColumn/LaunchCard
@onready var _hub_card: PanelContainer = $ShellCenter/ShellMargin/ShellRow/RightColumn/HubCard
@onready var _help_card: PanelContainer = $ShellCenter/ShellMargin/ShellRow/RightColumn/HelpCard
@onready var _brand_bg: TextureRect = %BrandBg
@onready var _launch_bg: TextureRect = %LaunchBg
@onready var _hub_bg: TextureRect = %HubBg
@onready var _help_bg: TextureRect = %HelpBg

const HubProcessManagerScript = preload("res://ScenSyn/scripts/services/hub_process_manager.gd")
const ProviderModePolicyScript = preload("res://addons/synesyn_core/scripts/provider_mode_policy.gd")
const SynesynToolsNavScript = preload("res://ScenSyn/scripts/synesyn_tools_nav.gd")
const _LOGO_DARK_TEX := preload("res://Synesyn_icons/synesyn_icon.png")
const _LOGO_WHITE_TEX := preload("res://Synesyn_icons/synesyn_icon_white.png")
const _GLASS_DARK_TEX := preload("res://Synesyn_icons/synesyn-backgrounds/bg_card_glass_tile_dark.png")
const _GLASS_LIGHT_TEX := preload("res://Synesyn_icons/synesyn-backgrounds/bg_card_glass_tile_light.png")

var _runtime_cfg: Dictionary = {}
var _hub_process_manager: Node = null
var _hub_started_here: bool = false
var _hub_poll_timer: Timer = null
var _hub_poll_inflight: bool = false
var _hub_starting_until_ms: int = 0

func _update_brand_logo() -> void:
	if not is_instance_valid(brand_logo_rect) or not ThemeManager:
		return
	brand_logo_rect.texture = _LOGO_WHITE_TEX if ThemeManager.is_dark() else _LOGO_DARK_TEX
	brand_logo_rect.modulate = Color(1, 1, 1, 1)

func _update_theme_toggle_label() -> void:
	var btn: Button = get_node_or_null("%ThemeToggleButton") as Button
	if is_instance_valid(btn) and ThemeManager:
		btn.text = "Switch to Light Mode" if ThemeManager.is_dark() else "Switch to Dark Mode"

func _on_theme_changed(_new_mode: String) -> void:
	_update_brand_logo()
	_update_card_styles()
	_update_theme_toggle_label()

func _update_card_styles() -> void:
	## Theme type variations own card/button/label colors. Keep only root bg + glass texture.
	if not ThemeManager:
		return
	var is_dark_mode: bool = ThemeManager.is_dark()
	var root_bg: Color = ThemeManager.get_semantic_color("base")
	if root_bg == Color.MAGENTA:
		root_bg = (
			Color(0.039, 0.055, 0.078, 1.0) if is_dark_mode else Color(0.953, 0.965, 0.984, 1.0)
		)
	if is_instance_valid(_bg_color_rect):
		_bg_color_rect.color = root_bg
	if is_instance_valid(hub_status_label):
		hub_status_label.remove_theme_color_override("font_color")
	if is_instance_valid(hub_url_label):
		hub_url_label.remove_theme_color_override("font_color")
	var glass_tex: Texture2D = _GLASS_DARK_TEX if is_dark_mode else _GLASS_LIGHT_TEX
	var glass_alpha: float = 0.35 if is_dark_mode else 0.75
	for bg_node: TextureRect in [_brand_bg, _launch_bg, _hub_bg, _help_bg]:
		if is_instance_valid(bg_node):
			bg_node.texture = glass_tex
			bg_node.modulate = Color(1.0, 1.0, 1.0, glass_alpha)
			bg_node.visible = true

func _ready() -> void:
	# Apply user runtime config early (before launching apps) so exports are not tied to project.godot.
	_update_brand_logo()
	_update_card_styles()
	_update_theme_toggle_label()
	if ThemeManager:
		if not ThemeManager.mode_changed.is_connected(_on_theme_changed):
			ThemeManager.mode_changed.connect(_on_theme_changed)
	var theme_btn: Button = get_node_or_null("%ThemeToggleButton") as Button
	if is_instance_valid(theme_btn):
		theme_btn.pressed.connect(func(): if ThemeManager: ThemeManager.toggle_mode())
	var cfg: Dictionary = RuntimeConfig.load_config()
	_runtime_cfg = cfg
	_apply_runtime_config(cfg)
	# Pre-arm startup grace before first UI poll so users don't see a transient
	# "Hub: down (HTTP request failed ...)" flash during normal autostart.
	var hub_cfg_any: Variant = _runtime_cfg.get("hub", {})
	var hub_cfg: Dictionary = hub_cfg_any if typeof(hub_cfg_any) == TYPE_DICTIONARY else {}
	var base_url_preview := _get_hub_base_url_safe()
	if bool(hub_cfg.get("autostart", true)) and _is_localhost_url(base_url_preview):
		_hub_starting_until_ms = int(Time.get_ticks_msec()) + 12000

	if open_scensyn_button:
		open_scensyn_button.pressed.connect(func(): get_tree().change_scene_to_file("res://ScenSyn/scenes/main_menu.tscn"))
	if open_readymade_button:
		open_readymade_button.pressed.connect(func(): get_tree().change_scene_to_file("res://readymade/readymade_main.tscn"))
	if open_story_log_player_button:
		open_story_log_player_button.pressed.connect(func(): get_tree().change_scene_to_file("res://playback/story_log_player.tscn"))
	if open_tools_button:
		# Same Tools shell as ScenSyn → Tools; Back returns to this launcher.
		open_tools_button.disabled = false
		open_tools_button.pressed.connect(_on_open_tools_pressed)

	_apply_launcher_density()
	var viewport_node: Viewport = get_viewport()
	if viewport_node and not viewport_node.size_changed.is_connected(_on_viewport_size_changed):
		viewport_node.size_changed.connect(_on_viewport_size_changed)

	_setup_hub_controls()

	# IMPORTANT: do NOT stop the hub on scene changes.
	# Switching from the Launcher into ScenSyn/ReadyMade removes this node from
	# the scene tree, which triggers _exit_tree(). If we stop the hub there, it
	# looks like "hub voice randomly dies" right after launching ScenSyn.
	# Instead, stop the hub only when the application is actually quitting.
	# Godot 4: SceneTree doesn't expose a `tree_exiting` signal. Use the window
	# close notification instead (fires when the application is quitting).

	# Keep autostart default behavior, but don’t block UI if it fails.
	call_deferred("_autostart_hub_if_configured")

func _on_open_tools_pressed() -> void:
	SynesynToolsNavScript.open_from(
		get_tree(),
		SynesynToolsNavScript.RETURN_LAUNCHER_PATH
	)


func _on_viewport_size_changed() -> void:
	_apply_launcher_density()

func _apply_launcher_density() -> void:
	var tree_ref: SceneTree = get_tree()
	if tree_ref == null or tree_ref.root == null:
		return
	var viewport_size_local: Vector2 = tree_ref.root.get_visible_rect().size
	var viewport_height: float = viewport_size_local.y
	var viewport_width: float = viewport_size_local.x
	var is_compact: bool = viewport_height < 760.0
	var is_tight: bool = viewport_height < 690.0

	if shell_margin:
		var horizontal_margin: int = 24 if is_compact else 40
		var vertical_margin: int = 20 if is_tight else (24 if is_compact else 32)
		shell_margin.add_theme_constant_override("margin_left", horizontal_margin)
		shell_margin.add_theme_constant_override("margin_top", vertical_margin)
		shell_margin.add_theme_constant_override("margin_right", horizontal_margin)
		shell_margin.add_theme_constant_override("margin_bottom", vertical_margin)

	if shell_row:
		shell_row.add_theme_constant_override("separation", 16 if is_compact else 24)
		shell_row.custom_minimum_size = Vector2(maxf(0.0, minf(1080.0, viewport_width - 48.0)), 0.0)

	if brand_margin:
		var brand_inner_margin: int = 4 if is_tight else (6 if is_compact else 10)
		brand_margin.add_theme_constant_override("margin_left", brand_inner_margin)
		brand_margin.add_theme_constant_override("margin_top", brand_inner_margin)
		brand_margin.add_theme_constant_override("margin_right", brand_inner_margin)
		brand_margin.add_theme_constant_override("margin_bottom", brand_inner_margin)
	if launch_margin:
		var launch_inner_margin: int = 3 if is_tight else (4 if is_compact else 6)
		launch_margin.add_theme_constant_override("margin_left", launch_inner_margin)
		launch_margin.add_theme_constant_override("margin_top", launch_inner_margin)
		launch_margin.add_theme_constant_override("margin_right", launch_inner_margin)
		launch_margin.add_theme_constant_override("margin_bottom", launch_inner_margin)
	if hub_margin:
		var hub_inner_margin_left: int = 4 if is_compact else 6
		var hub_inner_margin_vertical: int = 2 if is_tight else 4
		hub_margin.add_theme_constant_override("margin_left", hub_inner_margin_left)
		hub_margin.add_theme_constant_override("margin_top", hub_inner_margin_vertical)
		hub_margin.add_theme_constant_override("margin_right", hub_inner_margin_left)
		hub_margin.add_theme_constant_override("margin_bottom", hub_inner_margin_vertical)
	if help_margin:
		var help_inner_margin_left: int = 4 if is_compact else 6
		var help_inner_margin_vertical: int = 2 if is_tight else 4
		help_margin.add_theme_constant_override("margin_left", help_inner_margin_left)
		help_margin.add_theme_constant_override("margin_top", help_inner_margin_vertical)
		help_margin.add_theme_constant_override("margin_right", help_inner_margin_left)
		help_margin.add_theme_constant_override("margin_bottom", help_inner_margin_vertical)

	if brand_vbox:
		brand_vbox.add_theme_constant_override("separation", 10 if is_tight else (12 if is_compact else 16))
	if right_column:
		right_column.add_theme_constant_override("separation", 14 if is_compact else 18)
	if launch_vbox:
		launch_vbox.add_theme_constant_override("separation", 8 if is_tight else (10 if is_compact else 12))
	if hub_vbox:
		hub_vbox.add_theme_constant_override("separation", 8 if is_tight else (10 if is_compact else 12))
	if help_vbox:
		help_vbox.add_theme_constant_override("separation", 6 if is_tight else 8)

	if brand_logo_rect:
		var logo_size: float = 90.0 if is_tight else (110.0 if is_compact else 140.0)
		brand_logo_rect.custom_minimum_size = Vector2(logo_size, logo_size)
	if brand_title_label:
		brand_title_label.add_theme_font_size_override("font_size", 32 if is_tight else (36 if is_compact else 42))
	if brand_subtitle_label:
		brand_subtitle_label.add_theme_font_size_override("font_size", 15 if is_tight else (16 if is_compact else 17))
	if brand_support_label:
		brand_support_label.add_theme_font_size_override("font_size", 13 if is_compact else 15)
		brand_support_label.visible = not is_tight

	if hub_section_title:
		hub_section_title.add_theme_font_size_override("font_size", 18 if is_compact else 20)
	if hub_section_description:
		hub_section_description.add_theme_font_size_override("font_size", 13 if is_compact else 14)
	if help_title_label:
		help_title_label.add_theme_font_size_override("font_size", 16 if is_compact else 18)
	if help_description_label:
		help_description_label.add_theme_font_size_override("font_size", 13 if is_compact else 14)

	var launch_button_height: float = 40.0 if is_tight else (46.0 if is_compact else 56.0)
	var secondary_button_height: float = 34.0 if is_tight else (38.0 if is_compact else 42.0)
	var how_to_button_height: float = 36.0 if is_tight else (40.0 if is_compact else 46.0)
	var launch_button_font: int = 16 if is_compact else 18

	for launcher_button in [open_scensyn_button, open_readymade_button, open_story_log_player_button, open_tools_button]:
		if is_instance_valid(launcher_button):
			launcher_button.custom_minimum_size = Vector2(0.0, launch_button_height)
			launcher_button.add_theme_font_size_override("font_size", launch_button_font)

	for hub_button in [start_hub_button, stop_hub_button, restart_hub_button, open_hub_config_button]:
		if is_instance_valid(hub_button):
			hub_button.custom_minimum_size = Vector2(0.0, secondary_button_height)

	if is_instance_valid(how_to_button):
		how_to_button.custom_minimum_size = Vector2(0.0, how_to_button_height)
		how_to_button.add_theme_font_size_override("font_size", 15 if is_compact else 16)

	if hub_buttons_grid:
		hub_buttons_grid.columns = 2

func _apply_runtime_config(cfg: Dictionary) -> void:
	# Voice config
	if typeof(VoiceService) != TYPE_NIL and VoiceService and VoiceService.has_method("apply_runtime_config"):
		var voice_cfg: Dictionary = cfg.get("voice", {})
		VoiceService.apply_runtime_config(
			str(voice_cfg.get("provider_mode", "")),
			str(voice_cfg.get("hub_url", "")),
			str(voice_cfg.get("service_url", "")),
			str(voice_cfg.get("hub_tts_provider_preference", "auto"))
		)

func _setup_hub_controls() -> void:
	# Landing-page UX: show hub status and provide manual Start/Stop/Config buttons.
	if is_instance_valid(start_hub_button):
		start_hub_button.pressed.connect(_on_start_hub_pressed)
	if is_instance_valid(stop_hub_button):
		stop_hub_button.pressed.connect(_on_stop_hub_pressed)
	if is_instance_valid(restart_hub_button):
		restart_hub_button.pressed.connect(_on_restart_hub_pressed)
	if is_instance_valid(open_hub_config_button):
		open_hub_config_button.pressed.connect(_on_open_hub_config_pressed)
	if is_instance_valid(how_to_button):
		how_to_button.pressed.connect(_on_how_to_pressed)
	if is_instance_valid(how_to_close_button):
		how_to_close_button.pressed.connect(func() -> void:
			if is_instance_valid(how_to_popup):
				how_to_popup.hide()
		)

	if is_instance_valid(hub_status_label):
		hub_status_label.text = "Hub: checking…"
	if is_instance_valid(hub_url_label):
		hub_url_label.text = "URL: " + _get_hub_base_url_safe()

	# Poll /health periodically so the user can see what’s running.
	_hub_poll_timer = Timer.new()
	_hub_poll_timer.wait_time = 1.0
	_hub_poll_timer.one_shot = false
	_hub_poll_timer.timeout.connect(_on_hub_poll_timer_timeout)
	add_child(_hub_poll_timer)
	_hub_poll_timer.start()

	# First refresh.
	call_deferred("_refresh_hub_ui")

func _on_hub_poll_timer_timeout() -> void:
	await _refresh_hub_ui()

func _refresh_hub_ui() -> void:
	if _hub_poll_inflight:
		return
	_hub_poll_inflight = true
	await _refresh_hub_ui_async()
	_hub_poll_inflight = false

func _refresh_hub_ui_async() -> void:
	var base_url := _get_hub_base_url_safe()
	var hub_cfg := _get_hub_cfg()
	var autostart_txt := "on" if bool(hub_cfg.get("autostart", true)) else "off"

	if is_instance_valid(hub_url_label):
		hub_url_label.text = "URL: %s (autostart %s)" % [base_url, autostart_txt]

	var ok := false
	var reason := ""
	var now_ms := int(Time.get_ticks_msec())
	var in_startup_grace := (_hub_starting_until_ms > 0 and now_ms < _hub_starting_until_ms)
	if not base_url.is_empty():
		var health: Dictionary = await _get_json(base_url.rstrip("/") + "/health", 1.0)
		if bool(health.get("ok", false)):
			var payload_any: Variant = health.get("data", {})
			var payload: Dictionary = payload_any if typeof(payload_any) == TYPE_DICTIONARY else {}
			ok = bool(payload.get("ok", false))
			reason = str(payload.get("reason", "")).strip_edges()
		else:
			reason = str(health.get("error", "")).strip_edges()

	if is_instance_valid(hub_status_label):
		if ok:
			_hub_starting_until_ms = 0
			hub_status_label.text = "Hub: running"
		else:
			if in_startup_grace:
				hub_status_label.text = "Hub: starting..."
			else:
				hub_status_label.text = "Hub: down" if reason.is_empty() else ("Hub: down (%s)" % reason)

	# Button state
	var can_start := (not ok) and _is_localhost_url(base_url)
	if is_instance_valid(start_hub_button):
		start_hub_button.disabled = not can_start

	var pm_running := false
	if is_instance_valid(_hub_process_manager) and _hub_process_manager.has_method("is_running"):
		pm_running = bool(_hub_process_manager.call("is_running"))
	# Stop/restart is possible even if we didn't spawn the process, as long as the hub is reachable on localhost.
	var can_stop := ok and _is_localhost_url(base_url)
	if is_instance_valid(stop_hub_button):
		stop_hub_button.disabled = not can_stop
	if is_instance_valid(restart_hub_button):
		# Restart requires an exec path to start after shutdown.
		restart_hub_button.disabled = not _is_localhost_url(base_url)

func _autostart_hub_if_configured() -> void:
	# Use a separate method to keep _ready() non-async.
	# Keep grace active while autostart orchestration runs.
	if _hub_starting_until_ms <= int(Time.get_ticks_msec()):
		_hub_starting_until_ms = int(Time.get_ticks_msec()) + 12000
	await _ensure_hub_running_async(false)
	await _refresh_hub_ui()
	await _ensure_workspace_selected_async()

func _load_workspace_state() -> Dictionary:
	# Load Services-panel persisted workspace selection (if present).
	# Primary: Documents/Synesyn/synesyn/config/workspace_state.json
	# Fallback: user://workspace_state.json
	var candidates: Array[String] = []
	var cfg_path := RuntimeConfig.get_config_path_abs()
	if not cfg_path.strip_edges().is_empty():
		candidates.append(cfg_path.get_base_dir().path_join("workspace_state.json"))
	candidates.append(ProjectSettings.globalize_path("user://workspace_state.json"))

	for p in candidates:
		if p.strip_edges().is_empty() or (not FileAccess.file_exists(p)):
			continue
		var f := FileAccess.open(p, FileAccess.READ)
		if not f:
			continue
		var raw := f.get_as_text()
		f.close()
		var parsed_any: Variant = JSON.parse_string(raw)
		if typeof(parsed_any) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = parsed_any
		if str(d.get("name", "")).strip_edges().is_empty():
			continue
		return d
	return {}

func _ensure_workspace_selected_async() -> void:
	# Deterministic fix: apply persisted workspace selection to the hub on startup.
	# This ensures hub state matches what the Services panel last applied, even if the hub
	# boots with a stale workspace persisted elsewhere.
	var state: Dictionary = _load_workspace_state()
	if state.is_empty():
		return
	var name := str(state.get("name", "")).strip_edges()
	var slug := str(state.get("slug", "")).strip_edges()
	var root_base := str(state.get("root_base", "")).strip_edges()
	if name.is_empty() or slug.is_empty():
		return

	# Default base root: Documents/Synesyn/Workspaces
	if root_base.is_empty():
		root_base = str(OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)).path_join("Synesyn").path_join("Workspaces")

	var base_url := _get_hub_base_url_safe()
	if base_url.is_empty():
		return

	# Wait briefly for hub to be reachable.
	for _i in range(25):
		var health: Dictionary = await _get_json(base_url.rstrip("/") + "/health", 1.0)
		if bool(health.get("ok", false)) and bool(health.get("data", {}).get("ok", false)):
			break
		await get_tree().create_timer(0.2).timeout

	# If hub already matches, no-op.
	var ws_res: Dictionary = await _get_json(base_url.rstrip("/") + "/workspace", 2.0)
	if bool(ws_res.get("ok", false)):
		var data_any: Variant = ws_res.get("data", null)
		if typeof(data_any) == TYPE_DICTIONARY:
			var data: Dictionary = data_any
			var ws_any: Variant = data.get("workspace", null)
			if typeof(ws_any) == TYPE_DICTIONARY:
				var ws: Dictionary = ws_any
				var cur_slug := str(ws.get("slug", "") if ws.get("slug") != null else "").strip_edges()
				var cur_name := str(ws.get("name", "") if ws.get("name") != null else "").strip_edges()
				if cur_slug == slug and cur_name == name:
					return

	# Back-compat with hub builds: send a workspace-root path (base_root/slug).
	var workspace_root := root_base.path_join(slug)
	var payload := {"name": name, "slug": slug, "root": workspace_root}
	await _post_json(base_url.rstrip("/") + "/workspace/select", payload, 4.0)
	await _refresh_hub_ui()

func _ensure_hub_running_async(force_start: bool) -> void:
	var hub_cfg: Dictionary = _get_hub_cfg()
	if (not force_start) and (not bool(hub_cfg.get("autostart", true))):
		return

	var base_url := _get_hub_base_url_safe()
	if base_url.is_empty():
		return
	if not _is_localhost_url(base_url):
		# If user configured a remote hub, do not attempt to start a local process.
		return

	# If hub is already up, just ensure VoiceService knows about it and return.
	var health: Dictionary = await _get_json(base_url.rstrip("/") + "/health", 2.5)
	# NOTE: Reachability is "we got a response", not "workspace is configured".
	# Workspace selection is handled separately (bootstrapper / Services panel).
	if bool(health.get("ok", false)):
		# Hub already running — (re-)apply voice config so VoiceService
		# performs a fresh health check against the live hub.  The earlier
		# _apply_runtime_config() in _ready() likely ran before the hub
		# was reachable, so VoiceClient may still think the service is down.
		_apply_runtime_config(_runtime_cfg)
		return

	var exec_path := HubLocator.find_hub_exe(_runtime_cfg)
	if exec_path.is_empty():
		var configured := HubLocator.get_configured_path(_runtime_cfg)
		if not configured.is_empty():
			push_warning("SynesynLauncher: hub.exec_path does not exist: %s" % configured)
		push_warning("SynesynLauncher: hub autostart skipped (hub not found). Expected %s." % HubLocator.describe_expected_location())
		return

	if not is_instance_valid(_hub_process_manager):
		_hub_process_manager = HubProcessManagerScript.new()
		add_child(_hub_process_manager)

	# Start hub process (non-blocking).
	if _hub_process_manager.has_method("start_hub"):
		# Godot is strict about typed arrays when calling typed methods via `call()`.
		var args: Array[String] = []
		var started := bool(_hub_process_manager.call("start_hub", exec_path, args))
		_hub_started_here = started
		if started:
			# Suppress transient "down" messages while process bootstraps.
			_hub_starting_until_ms = int(Time.get_ticks_msec()) + 12000
			# NOTE: create_process() returning a pid only means we spawned a process.
			# With onefile PyInstaller builds, the hub can take a few seconds to unpack.
			# Wait/retry health so we don't immediately report "timeout" and confuse the user.
			var pid := int(_hub_process_manager.call("get_pid")) if _hub_process_manager.has_method("get_pid") else -1
			push_warning("SynesynLauncher: spawned Synesyn Hub (pid=%s): %s" % [str(pid), exec_path])
			# Register PID for deterministic stop_on_exit handling (autoload survives scene changes).
			if pid > 0 and typeof(WorkspaceBootstrapper) != TYPE_NIL and WorkspaceBootstrapper and WorkspaceBootstrapper.has_method("register_hub_process"):
				WorkspaceBootstrapper.register_hub_process(pid, exec_path)

			var reachable := false
			var workspace_ok := false
			for i in range(40):
				health = await _get_json(base_url.rstrip("/") + "/health", 2.5)
				if bool(health.get("ok", false)):
					reachable = true
					workspace_ok = bool(health.get("data", {}).get("ok", false))
					break
				# If the process already exited, stop waiting.
				if pid > 0 and OS.has_method("is_process_running") and (not OS.is_process_running(pid)):
					break
				await get_tree().create_timer(0.25).timeout

			if reachable:
				_hub_starting_until_ms = 0
				push_warning("SynesynLauncher: hub is reachable (/health responded). workspace_configured=%s" % str(workspace_ok))
				# NOW that the hub is confirmed reachable, (re-)apply voice config
				# so VoiceService performs a health check against the live hub.
				# This is the same call that "Save & Apply Providers" makes.
				_apply_runtime_config(_runtime_cfg)
			else:
				var died := (pid > 0 and OS.has_method("is_process_running") and (not OS.is_process_running(pid)))
				push_warning("SynesynLauncher: hub spawn did not become reachable%s." % (" (process exited)" if died else " (still starting or blocked)"))
		else:
			push_warning("SynesynLauncher: failed to start Synesyn Hub: %s" % exec_path)

func _notification(what: int) -> void:
	# Hub shutdown on app exit is handled by the `WorkspaceBootstrapper` autoload.
	# Keeping hub lifecycle out of UI scenes avoids "hub stopped on scene change"
	# regressions and makes app exit behavior consistent regardless of which scene
	# is active at quit time.
	pass

func _on_start_hub_pressed() -> void:
	await _ensure_hub_running_async(true)
	await _refresh_hub_ui()
	await _ensure_workspace_selected_async()

func _on_stop_hub_pressed() -> void:
	var base_url := _get_hub_base_url_safe()
	# Prefer graceful shutdown via hub endpoint (works even when we don't know PID).
	var shut: Dictionary = await _post_json(base_url.rstrip("/") + "/admin/shutdown", {}, 2.0)
	if not bool(shut.get("ok", false)):
		# Fall back to kill if we started it.
		if _hub_started_here and is_instance_valid(_hub_process_manager) and _hub_process_manager.has_method("stop_hub"):
			_hub_process_manager.call("stop_hub")
	_hub_started_here = false
	await _refresh_hub_ui()

func _on_restart_hub_pressed() -> void:
	await _on_stop_hub_pressed()
	# Give the process a moment to exit and the port to free.
	await get_tree().create_timer(0.35).timeout
	await _ensure_hub_running_async(true)
	await _refresh_hub_ui()
	await _ensure_workspace_selected_async()

func _on_open_hub_config_pressed() -> void:
	# Ensure config exists on disk so the user can edit it.
	var cfg: Dictionary = RuntimeConfig.load_config()
	RuntimeConfig.save_config(cfg)
	var cfg_path_abs := RuntimeConfig.get_config_path_abs()
	if cfg_path_abs.strip_edges().is_empty():
		return
	cfg_path_abs = cfg_path_abs.replace("/", "\\") if OS.get_name() == "Windows" else cfg_path_abs
	# This is normal diagnostics, not a warning; warnings show prominently in the debugger.
	print("SynesynLauncher: Open hub config requested: %s" % cfg_path_abs)

	# Prefer showing the file in the OS file manager.
	# Best option: use Godot's built-in "show in file manager" when available.
	# On Windows this is typically more reliable than hand-rolling Explorer args.
	if OS.has_method("shell_show_in_file_manager"):
		OS.shell_show_in_file_manager(cfg_path_abs, true)
		return

	# Windows fallback: cmd.exe start explorer.exe /select,"<path>"
	if OS.get_name() == "Windows":
		var cmd_line := "start \"\" explorer.exe /select,\"%s\"" % cfg_path_abs
		var pid := OS.create_process("cmd.exe", PackedStringArray(["/c", cmd_line]), false)
		if pid > 0:
			return
		OS.execute("cmd.exe", PackedStringArray(["/c", cmd_line]))
		return

	OS.shell_open(cfg_path_abs.get_base_dir())

func _on_how_to_pressed() -> void:
	if not is_instance_valid(how_to_popup) or not is_instance_valid(how_to_rich_text):
		return
	var doc_path := "res://docs/how_to.md"
	var raw := ""
	if FileAccess.file_exists(doc_path):
		raw = FileAccess.get_file_as_string(doc_path)
	if raw.strip_edges().is_empty():
		raw = "Help file not found: %s" % doc_path
	# RichTextLabel can't render Markdown directly; show plain text for now.
	# Assigning .text is the most robust way to ensure it renders.
	how_to_rich_text.text = raw
	how_to_popup.popup_centered()

func _is_localhost_url(url: String) -> bool:
	var u := url.strip_edges().to_lower()
	return (u.find("127.0.0.1") != -1) or (u.find("localhost") != -1)

func _get_hub_base_url_safe() -> String:
	return str(ProviderModePolicyScript.get_hub_base_url(_runtime_cfg)).strip_edges()

func _get_hub_cfg() -> Dictionary:
	var hub_cfg_any: Variant = _runtime_cfg.get("hub", {})
	return hub_cfg_any if typeof(hub_cfg_any) == TYPE_DICTIONARY else {}

func _get_json(url: String, timeout_sec: float) -> Dictionary:
	var attempts := 3
	var last_err: Variant = "unknown"
	for i in range(attempts):
		var http := HTTPRequest.new()
		http.timeout = float(timeout_sec)
		add_child(http)
		# Disable proxies for localhost calls (matches PowerShell `-Proxy $null` behavior).
		if _is_localhost_url(url):
			http.set_http_proxy("", -1)
			http.set_https_proxy("", -1)
		var headers := ["Accept: application/json"]
		var err := http.request(url, headers, HTTPClient.METHOD_GET)
		if err != OK:
			last_err = "HTTPRequest.request failed: %s" % error_string(err)
			http.queue_free()
			if i < attempts - 1:
				await get_tree().create_timer(0.2 * float(i + 1)).timeout
				continue
			return {"ok": false, "error": last_err}
		# Godot can't always infer the signal payload type; declare explicitly to avoid parser/analyzer errors.
		var completed: Array = await http.request_completed
		http.queue_free()

		var result_code: int = completed[0]
		var response_code: int = completed[1]
		var resp_body: PackedByteArray = completed[3]
		if result_code != HTTPRequest.RESULT_SUCCESS:
			last_err = "HTTP request failed: %s" % result_code
			if i < attempts - 1:
				await get_tree().create_timer(0.2 * float(i + 1)).timeout
				continue
			return {"ok": false, "error": last_err}

		var parsed: Variant = {}
		var s := resp_body.get_string_from_utf8()
		if not s.is_empty():
			parsed = JSON.parse_string(s)
		if response_code < 200 or response_code >= 300:
			return {"ok": false, "error": {"status": response_code, "body": parsed}}
		if typeof(parsed) == TYPE_DICTIONARY:
			return {"ok": true, "data": parsed}
		return {"ok": true, "data": {}}

	return {"ok": false, "error": last_err}

func _post_json(url: String, payload: Dictionary, timeout_sec: float) -> Dictionary:
	var attempts := 3
	var last_err: Variant = "unknown"
	for i in range(attempts):
		var http := HTTPRequest.new()
		http.timeout = float(timeout_sec)
		add_child(http)
		# Disable proxies for localhost calls (matches PowerShell `-Proxy $null` behavior).
		if _is_localhost_url(url):
			http.set_http_proxy("", -1)
			http.set_https_proxy("", -1)
		var headers := ["Content-Type: application/json", "Accept: application/json"]
		var body := JSON.stringify(payload)
		var err := http.request(url, headers, HTTPClient.METHOD_POST, body)
		if err != OK:
			last_err = "HTTPRequest.request failed: %s" % error_string(err)
			http.queue_free()
			if i < attempts - 1:
				await get_tree().create_timer(0.2 * float(i + 1)).timeout
				continue
			return {"ok": false, "error": last_err}
		var completed: Array = await http.request_completed
		http.queue_free()

		var result_code: int = completed[0]
		var response_code: int = completed[1]
		var resp_body: PackedByteArray = completed[3]
		if result_code != HTTPRequest.RESULT_SUCCESS:
			last_err = "HTTP request failed: %s" % result_code
			if i < attempts - 1:
				await get_tree().create_timer(0.2 * float(i + 1)).timeout
				continue
			return {"ok": false, "error": last_err}

		var parsed: Variant = {}
		var s := resp_body.get_string_from_utf8()
		if not s.is_empty():
			parsed = JSON.parse_string(s)
		if response_code < 200 or response_code >= 300:
			return {"ok": false, "error": {"status": response_code, "body": parsed}}
		if typeof(parsed) == TYPE_DICTIONARY:
			return {"ok": true, "data": parsed}
		return {"ok": true, "data": {}}

	return {"ok": false, "error": last_err}
