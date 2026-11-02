extends Control

## Shared Synesyn Tools shell. Opened from the launcher or ScenSyn main menu.
## Back returns via SynesynToolsNav (set by open_from).

const SynesynToolsNavScript = preload("res://ScenSyn/scripts/synesyn_tools_nav.gd")

@onready var back_button: Button = %BackButton
@onready var open_story_stage_button: Button = %OpenStoryStageButton
@onready var theme_toggle_button: Button = %ThemeToggleButton

const _TABS_PATH := "OuterMargin/VBox/TabsCard/Tabs"
const _SYNTREE_PANEL_PATH := "OuterMargin/VBox/TabsCard/Tabs/SynTree/SynTreePanel"
const _SYNAXES_PANEL_PATH := "OuterMargin/VBox/TabsCard/Tabs/SynAxes/SynAxesPanel"
const _BG_PATH := "Background"
const _HEADER_CARD_PATH := "OuterMargin/VBox/HeaderCard"
const _TABS_CARD_PATH := "OuterMargin/VBox/TabsCard"
const _NAV_TARGET_SYNPUNKT_CLOSURES := "synpunkt_closures"

const _LOGO_DARK := preload("res://Synesyn_icons/Synesyn_logo.svg")
const _LOGO_WHITE := preload("res://Synesyn_icons/Synesyn_logo_white.svg")

const _DARK_SHELL_COLOR := Color(0.039, 0.055, 0.078, 1)
const _LIGHT_SHELL_COLOR := Color(0.953, 0.965, 0.984, 1)
const _DARK_CARD_COLOR := Color(0.1, 0.14, 0.2, 0.92)
const _LIGHT_CARD_COLOR := Color(0.996, 0.994, 1, 0.98)
const _DARK_CARD_BORDER := Color(0.227, 0.3, 0.361, 0.7)
const _LIGHT_CARD_BORDER := Color(0.55, 0.68, 0.88, 0.35)

func _ready() -> void:
	if back_button:
		back_button.pressed.connect(_go_back)
	if open_story_stage_button:
		open_story_stage_button.pressed.connect(_open_story_stage)
	if theme_toggle_button:
		theme_toggle_button.pressed.connect(_on_theme_toggle_pressed)
	if ThemeManager:
		ThemeManager.mode_changed.connect(_on_mode_changed)
		_apply_surface_colors(ThemeManager.is_dark())
		_update_toggle_label(ThemeManager.is_dark())
	_apply_tab_tooltips()
	call_deferred("_stabilize_tabs_layout")
	call_deferred("_wire_synaxes_navigation")
	call_deferred("_consume_pending_tools_action")
	_bootstrap_syntree_panel()

func _on_theme_toggle_pressed() -> void:
	ThemeManager.toggle_mode()

func _on_mode_changed(new_mode: String) -> void:
	var is_dark: bool = new_mode == "dark"
	_apply_surface_colors(is_dark)
	_update_toggle_label(is_dark)

func _apply_surface_colors(is_dark: bool) -> void:
	var shell_color: Color = _DARK_SHELL_COLOR if is_dark else _LIGHT_SHELL_COLOR
	var card_color: Color = _DARK_CARD_COLOR if is_dark else _LIGHT_CARD_COLOR
	var card_border: Color = _DARK_CARD_BORDER if is_dark else _LIGHT_CARD_BORDER
	var bg: Panel = get_node_or_null(_BG_PATH)
	if bg:
		var style: StyleBoxFlat = bg.get("theme_override_styles/panel") as StyleBoxFlat
		if style:
			style.bg_color = shell_color
	for card_path in [_HEADER_CARD_PATH, _TABS_CARD_PATH]:
		var card: PanelContainer = get_node_or_null(card_path)
		if card:
			var style: StyleBoxFlat = card.get("theme_override_styles/panel") as StyleBoxFlat
			if style:
				style.bg_color = card_color
				style.border_color = card_border
	var header_logo: TextureRect = get_node_or_null("%HeaderLogo") as TextureRect
	if is_instance_valid(header_logo):
		header_logo.texture = _LOGO_WHITE if is_dark else _LOGO_DARK

func _update_toggle_label(is_dark: bool) -> void:
	if not theme_toggle_button:
		return
	theme_toggle_button.text = "☀" if is_dark else "🌙"
	theme_toggle_button.tooltip_text = "Switch to light mode" if is_dark else "Switch to dark mode"

# In an exported build the SynTree EditorPlugin never runs, so SynTreePanel's
# _runtime_bootstrap_if_needed() must be triggered explicitly once the scene tree
# has settled and PluginManager has finished its own init.
func _bootstrap_syntree_panel() -> void:
	if Engine.is_editor_hint():
		return
	var panel: Node = get_node_or_null(_SYNTREE_PANEL_PATH)
	if not is_instance_valid(panel) or not panel.has_method("_runtime_bootstrap_if_needed"):
		return
	# Wait for PluginManager to signal readiness before handing off to SynTree.
	if is_instance_valid(PluginManager) and PluginManager.has_method("is_ready"):
		if not bool(PluginManager.is_ready()):
			if PluginManager.has_signal("initialization_completed"):
				await PluginManager.initialization_completed
			else:
				await get_tree().create_timer(0.5).timeout
	panel._runtime_bootstrap_if_needed()

func _apply_tab_tooltips() -> void:
	var tabs_node := get_node_or_null(_TABS_PATH) as TabContainer
	if not is_instance_valid(tabs_node):
		return
	var descriptions: Array[String] = [
		"Settings — Hub, AI model, voice, and workspace. Do this once before a live session.",
		"SynTree — AI-powered assistant: chat with your documents, generate ideas, and build content sources.",
		"SynAxes — Walk your material as a space and leave with a few closures you can stand behind.",
		"Metapunkt — Orchestration layer: manage Metapunkt Packs, pipelines, and long-term memory.",
		"Story Stage (coming soon) — Runs inside Play for scenarios that use it. This tab is a placeholder.",
		"SynPunkt — Slide deck builder: compose, layout, and export presentation decks from your session artifacts.",
	]
	var tab_titles: Array[String] = [
		"Settings",
		"SynTree",
		"SynAxes",
		"Metapunkt",
		"Story Stage (coming soon)",
		"SynPunkt",
	]
	for tab_idx in range(mini(descriptions.size(), tabs_node.get_tab_count())):
		tabs_node.set_tab_title(tab_idx, tab_titles[tab_idx])
		tabs_node.set_tab_tooltip(tab_idx, descriptions[tab_idx])


func _stabilize_tabs_layout() -> void:
	var tabs_node := get_node_or_null(_TABS_PATH) as TabContainer
	if not is_instance_valid(tabs_node):
		return
	tabs_node.update_minimum_size()
	if tabs_node is Container:
		(tabs_node as Container).queue_sort()
	var current_panel: Control = tabs_node.get_current_tab_control()
	if is_instance_valid(current_panel):
		current_panel.update_minimum_size()
		if current_panel is Container:
			(current_panel as Container).queue_sort()


func _wire_synaxes_navigation() -> void:
	## Best-effort: SynAxes emits navigate_requested; host switches Tools tabs.
	## Addon must not reach into this scene tree (REQ-NDP-008 / REQ-NDP-019).
	var panel: Node = get_node_or_null(_SYNAXES_PANEL_PATH)
	if not is_instance_valid(panel):
		return
	if not panel.has_signal("navigate_requested"):
		return
	var cb := Callable(self, "_on_synaxes_navigate_requested")
	if not panel.is_connected("navigate_requested", cb):
		panel.connect("navigate_requested", cb)


func _consume_pending_tools_action() -> void:
	## REQ-NDP-016: Workshop Propose themes → SynAxes tab + session preload + discover.
	var pending: Dictionary = SynesynToolsNavScript.take_pending_action()
	if pending.is_empty():
		return
	var action_name: String = str(pending.get("action", "")).strip_edges()
	if action_name != SynesynToolsNavScript.ACTION_PROPOSE_THEMES:
		return
	_select_tools_tab("SynAxes")
	var panel: Node = get_node_or_null(_SYNAXES_PANEL_PATH)
	if not is_instance_valid(panel):
		return
	# Wait one frame so SynAxes runtime _ready (hub + controllers) has finished.
	await get_tree().process_frame
	if panel.has_method("begin_propose_themes"):
		var session_id: String = str(pending.get("session_id", "")).strip_edges()
		await panel.begin_propose_themes(session_id)


func _select_tools_tab(tab_name: String) -> void:
	var tabs_node: TabContainer = get_node_or_null(_TABS_PATH) as TabContainer
	if not is_instance_valid(tabs_node):
		return
	var wanted: String = tab_name.strip_edges().to_lower()
	if wanted == "settings":
		wanted = "services"
	for tab_idx in range(tabs_node.get_tab_count()):
		var child_node: Node = tabs_node.get_child(tab_idx)
		if child_node != null and str(child_node.name).strip_edges().to_lower() == wanted:
			tabs_node.current_tab = tab_idx
			return
		var title_id: String = tabs_node.get_tab_title(tab_idx).strip_edges().to_lower()
		if title_id == wanted or (wanted == "services" and title_id == "settings"):
			tabs_node.current_tab = tab_idx
			return


func _on_synaxes_navigate_requested(target: String) -> void:
	var target_key: String = target.strip_edges().to_lower()
	if target_key != _NAV_TARGET_SYNPUNKT_CLOSURES:
		return
	var tabs_node: TabContainer = get_node_or_null(_TABS_PATH) as TabContainer
	if not is_instance_valid(tabs_node):
		return
	for tab_idx in range(tabs_node.get_tab_count()):
		var child_node: Node = tabs_node.get_child(tab_idx)
		if child_node != null and str(child_node.name) == "SynPunkt":
			tabs_node.current_tab = tab_idx
			return
		if tabs_node.get_tab_title(tab_idx).strip_edges().to_lower() == "synpunkt":
			tabs_node.current_tab = tab_idx
			return


func _go_back() -> void:
	get_tree().change_scene_to_file(SynesynToolsNavScript.get_return_scene())

func _open_story_stage() -> void:
	# Use a shell scene so Story Stage can be used "directly" without requiring
	# changes to Story Stage internals to add navigation UX.
	get_tree().change_scene_to_file("res://ScenSyn/scenes/story_stage_shell.tscn")
