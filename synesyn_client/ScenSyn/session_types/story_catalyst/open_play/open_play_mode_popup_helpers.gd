extends RefCounted
class_name OpenPlayModePopupHelpers

## Open Play helpers for GameModePopup: library dropdown population, selection
## load, tab preview copy, and create-button labeling. Keeps game_mode_popup.gd
## under the project line-limit ratchet.

const StoryScenarioContractScript = preload(
	"res://ScenSyn/session_types/story_catalyst/open_play/story_scenario_contract.gd"
)

## Dropdown sentinel: create a brand-new story (not a library entry).
const CREATE_NEW_SCENARIO_ID: String = "__create_new__"
const CREATE_NEW_DISPLAY_LABEL: String = "— Create new story —"


static func is_create_new_id(scenario_id: String) -> bool:
	var clean_id: String = scenario_id.strip_edges()
	return clean_id.is_empty() or clean_id == CREATE_NEW_SCENARIO_ID


static func populate_scenario_dropdown(option_button: OptionButton) -> void:
	if option_button == null:
		return
	# Always offer an explicit create-new choice first so a prior library save
	# (e.g. "Library Harbour") is never the forced default.
	option_button.add_item(CREATE_NEW_DISPLAY_LABEL)
	option_button.set_item_metadata(0, CREATE_NEW_SCENARIO_ID)
	var saved_entries: Array[Dictionary] = StoryScenarioContractScript.list_saved_scenarios()
	for entry_any: Variant in saved_entries:
		if typeof(entry_any) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_any
		var scenario_id: String = String(entry.get("id", "")).strip_edges()
		if scenario_id.is_empty() or is_create_new_id(scenario_id):
			continue
		var display_name: String = String(entry.get("name", "Untitled Story")).strip_edges()
		if display_name.is_empty():
			display_name = scenario_id
		option_button.add_item(display_name)
		option_button.set_item_metadata(option_button.item_count - 1, scenario_id)


static func render_empty_state(
	scenario_label: RichTextLabel,
	about_label: RichTextLabel,
	how_to_label: RichTextLabel
) -> void:
	if scenario_label:
		scenario_label.text = (
			"[b]Open Play — create a new story.[/b]\n\n"
			+ "The Scenario dropdown starts on \"" + CREATE_NEW_DISPLAY_LABEL + "\". "
			+ "Use \"Create / describe Story Scenario\" to craft a fun narrative "
			+ "roleplay (setting, cast, plot twists, genre tags). Finished stories "
			+ "appear below that option and can be selected again later to review/edit.\n\n"
			+ "[i]Multiplayer joiners receive the host story automatically on Confirm.[/i]"
		)
	if about_label:
		about_label.text = (
			"[i]Open Play is for narrative fun and roleplay — no teaching meters "
			+ "or curriculum overlays. Setting and tags appear here after you draft.[/i]"
		)
	if how_to_label:
		how_to_label.text = (
			"[i]After you finish a draft, pick a character on the next screen and play. "
			+ "Plot twists are optional dramatic fuel, not graded outcomes.[/i]"
		)


static func render_story_tabs(
	scenario: Dictionary,
	scenario_label: RichTextLabel,
	about_label: RichTextLabel,
	how_to_label: RichTextLabel,
	is_multiplayer_host_note: bool
) -> void:
	var tags_any: Variant = scenario.get("tags", [])
	var tags_text: String = ""
	if typeof(tags_any) == TYPE_ARRAY and not (tags_any as Array).is_empty():
		var tag_parts: Array[String] = []
		for tag_any: Variant in tags_any:
			var tag_label: String = String(tag_any).strip_edges()
			if not tag_label.is_empty():
				tag_parts.append(tag_label)
		tags_text = ", ".join(tag_parts)
	var multiplayer_note: String = ""
	if is_multiplayer_host_note:
		multiplayer_note = (
			"\n\n[i]Hosting will sync this Open Play story to joining instances on Confirm.[/i]"
		)
	if scenario_label:
		scenario_label.text = (
			"[b]Open Play scenario:[/b] %s\n\nObjective: %s\n\n"
			+ "[i]Saved and selectable — ready for character selection after Confirm.[/i]"
			+ multiplayer_note
		) % [
			String(scenario.get("name", "Untitled Story")),
			String(scenario.get("objective", "")),
		]
	if about_label:
		var about_body: String = String(scenario.get("about_text", "")).strip_edges()
		if about_body.is_empty():
			about_body = String(scenario.get("description", scenario.get("setting", "")))
		if not tags_text.is_empty():
			about_body = (
				("[b]Tags:[/b] " + tags_text + "\n\n" + about_body).strip_edges()
			)
		about_label.text = (
			about_body if not about_body.is_empty()
			else "[i]No additional background was added for this draft.[/i]"
		)
	if how_to_label:
		var how_body: String = String(scenario.get("how_to_text", "")).strip_edges()
		how_to_label.text = (
			how_body if not how_body.is_empty()
			else "[i]Finish Confirm, pick a character, then play.[/i]"
		)


static func refresh_create_button(
	button: Button,
	is_open_play: bool,
	uses_custom_story: bool,
	selected_scenario_name: String,
	host_scenario: Dictionary
) -> void:
	if button == null:
		return
	button.visible = is_open_play
	if not is_open_play:
		return
	if StoryScenarioContractScript.looks_like_custom(host_scenario):
		button.text = "Review host Story Scenario"
		button.tooltip_text = "Review the Open Play story currently hosted on the network."
	elif (
		uses_custom_story
		and not selected_scenario_name.is_empty()
		and not is_create_new_id(selected_scenario_name)
	):
		button.text = "Review / edit selected Story Scenario"
		button.tooltip_text = (
			"Edit the selected saved scenario. To start fresh, pick "
			+ "\"" + CREATE_NEW_DISPLAY_LABEL + "\" in the Scenario dropdown "
			+ "(or Shift+click this button)."
		)
	else:
		button.text = "Create / describe Story Scenario"
		button.tooltip_text = (
			"Craft a new Open Play story. Finished stories appear in the Scenario dropdown."
		)


static func load_saved_into_session(scenario_id: String) -> Dictionary:
	## Returns {ok, scenario, error_text}. Caller updates popup flags / UI.
	var loaded: Dictionary = StoryScenarioContractScript.load_saved_scenario(scenario_id)
	if loaded.is_empty():
		return {
			"ok": false,
			"scenario": {},
			"error_text": "[color=red]Could not load saved Open Play scenario.[/color]",
		}
	if not Global.set_custom_story_scenario(loaded):
		return {
			"ok": false,
			"scenario": {},
			"error_text": "[color=red]The Open Play scenario could not be loaded.[/color]",
		}
	return {"ok": true, "scenario": loaded, "error_text": ""}


static func compute_mode_popup_size(
	tree_ref: SceneTree,
	window_max_size: Vector2i,
	default_width: float,
	default_height: float,
	min_width: float,
	max_width: float,
	min_height: float,
	width_fraction: float,
	margin_x: float,
	margin_y: float
) -> Vector2i:
	## Horizontal-responsive GameModePopup size: grows with viewport width.
	if tree_ref == null or tree_ref.root == null:
		return Vector2i(int(default_width), int(default_height))
	var viewport_size: Vector2 = tree_ref.root.get_visible_rect().size
	var effective_margin_x: float = margin_x
	if viewport_size.x < 720.0:
		effective_margin_x = 24.0
	var available_width: float = maxf(280.0, viewport_size.x - effective_margin_x)
	var available_height: float = maxf(320.0, viewport_size.y - margin_y)
	var width_cap: float = minf(available_width, max_width)
	if window_max_size.x > 0:
		width_cap = minf(width_cap, float(window_max_size.x))
	var target_width: float = maxf(default_width, viewport_size.x * width_fraction)
	var popup_width: float = clampf(target_width, min_width, width_cap)
	var popup_height: float = minf(default_height, available_height)
	if available_height >= min_height:
		popup_height = maxf(min_height, popup_height)
	else:
		popup_height = available_height
	if window_max_size.y > 0:
		popup_height = minf(popup_height, float(window_max_size.y))
	return Vector2i(int(round(popup_width)), int(round(popup_height)))


## Places a Popup/Window after it is visible. Export builds with viewport or
## DPI stretch can leave popup_centered() at (0,0) with a click-offset; editor
## play usually has matching window and viewport sizes so the bug stays hidden.
static func place_centered(popup: Window, popup_size: Vector2i) -> void:
	if popup == null:
		return
	var requested: Vector2i = Vector2i(maxi(1, popup_size.x), maxi(1, popup_size.y))
	popup.size = requested
	var tree_ref: SceneTree = popup.get_tree()
	if tree_ref == null or tree_ref.root == null:
		popup.popup_centered(requested)
		return
	var parent_window: Window = tree_ref.root
	if popup.is_embedded():
		var vis: Vector2 = parent_window.get_visible_rect().size
		if vis.x < 2.0 or vis.y < 2.0:
			popup.popup_centered(requested)
			return
		var pos_x: int = int(round((vis.x - float(requested.x)) * 0.5))
		var pos_y: int = int(round((vis.y - float(requested.y)) * 0.5))
		popup.position = Vector2i(maxi(0, pos_x), maxi(0, pos_y))
		return
	var vis_size: Vector2 = parent_window.get_visible_rect().size
	var parent_px: Vector2i = parent_window.size
	var scale_x: float = float(parent_px.x) / maxf(1.0, vis_size.x)
	var scale_y: float = float(parent_px.y) / maxf(1.0, vis_size.y)
	var native_size: Vector2i = Vector2i(
		maxi(1, int(round(float(requested.x) * scale_x))),
		maxi(1, int(round(float(requested.y) * scale_y)))
	)
	popup.size = native_size
	popup.position = parent_window.position + (parent_px - native_size) / 2


## Full-rect Control overlays (Join / My Sessions / Story Builder) must fill
## the viewport. A top_level Control as a VBox child sizes to the card and
## sits at (0,0) in exported builds.
static func fit_control_overlay(dialog_node: Control) -> void:
	if dialog_node == null:
		return
	dialog_node.top_level = false
	dialog_node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var viewport: Viewport = dialog_node.get_viewport()
	if viewport == null:
		return
	var view_size: Vector2 = viewport.get_visible_rect().size
	dialog_node.position = Vector2.ZERO
	dialog_node.size = view_size


static func compute_story_builder_popup_size(
	tree_ref: SceneTree,
	window_max_size: Vector2i,
	margin_x: float,
	margin_y: float,
	min_width: float,
	min_height: float,
	max_width: float,
	max_height: float
) -> Vector2i:
	if tree_ref == null or tree_ref.root == null:
		return Vector2i(int(min_width), int(min_height))
	var viewport_size: Vector2 = tree_ref.root.get_visible_rect().size
	var available_width: float = maxf(320.0, viewport_size.x - margin_x)
	var available_height: float = maxf(360.0, viewport_size.y - margin_y)
	var popup_width: float = minf(max_width, available_width)
	var popup_height: float = minf(max_height, available_height)
	if available_width >= min_width:
		popup_width = maxf(min_width, popup_width)
	else:
		popup_width = available_width
	if available_height >= min_height:
		popup_height = maxf(min_height, popup_height)
	else:
		popup_height = available_height
	# popup_centered() positions from the requested size, but Window clamps the
	# applied size to max_size — keep requested == applied to avoid off-center.
	if window_max_size.x > 0:
		popup_width = minf(popup_width, float(window_max_size.x))
	if window_max_size.y > 0:
		popup_height = minf(popup_height, float(window_max_size.y))
	return Vector2i(int(round(popup_width)), int(round(popup_height)))


static func resolve_review_scenario(
	uses_custom_story: bool,
	selected_scenario_name: String
) -> Dictionary:
	## Empty dict => caller starts a fresh AI draft (no library name/id bleed).
	if not uses_custom_story or is_create_new_id(selected_scenario_name):
		return {}
	var selected_id: String = selected_scenario_name.strip_edges()
	var review_scenario: Dictionary = Global.get_current_scenario()
	var review_id: String = String(review_scenario.get("id", "")).strip_edges()
	if not review_scenario.is_empty() and review_id == selected_id:
		return review_scenario
	return StoryScenarioContractScript.load_saved_scenario(selected_id)


static func clear_global_story_session(global_node: Object) -> void:
	## Drop any loaded Open Play library scenario from session state.
	if global_node == null:
		return
	global_node.set("current_scenario", {})
	global_node.set("current_scenario_metaprompt", "")
	global_node.set("is_scenario_selected", false)
	if global_node.has_method("set_character_templates"):
		global_node.call("set_character_templates", [])
	if global_node.has_method("set_character_pool"):
		global_node.call("set_character_pool", [])
	if global_node.has_method("set_selected_characters"):
		global_node.call("set_selected_characters", [])
	if not global_node.has_method("get_game_flow_manager"):
		return
	var gfm: Variant = global_node.call("get_game_flow_manager")
	if gfm is Object and (gfm as Object).has_method("set_current_scenario"):
		(gfm as Object).call("set_current_scenario", {})


static func mount_story_builder(
	host: Control,
	builder_scene: PackedScene,
	uses_custom_story: bool,
	selected_scenario_name: String,
	on_saved: Callable,
	on_cancelled: Callable
) -> Control:
	## Instantiates the embedded Story Builder and loads review vs fresh draft.
	if host == null or builder_scene == null:
		return null
	var builder_node: Control = builder_scene.instantiate() as Control
	if builder_node == null:
		return null
	builder_node.embedded_mode = true
	builder_node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	builder_node.size_flags_vertical = Control.SIZE_EXPAND_FILL
	host.add_child(builder_node)
	if builder_node.has_method("configure_for_open_play_overlay"):
		builder_node.call("configure_for_open_play_overlay")
	var review_scenario: Dictionary = resolve_review_scenario(
		uses_custom_story,
		selected_scenario_name
	)
	if (
		not review_scenario.is_empty()
		and builder_node.has_method("load_existing_open_play_scenario")
	):
		builder_node.call("load_existing_open_play_scenario", review_scenario)
	elif builder_node.has_method("start_scenario_building"):
		builder_node.call("start_scenario_building")
	if builder_node.has_signal("scenario_saved") and on_saved.is_valid():
		builder_node.connect("scenario_saved", on_saved)
	if builder_node.has_signal("builder_cancelled") and on_cancelled.is_valid():
		builder_node.connect("builder_cancelled", on_cancelled)
	return builder_node
