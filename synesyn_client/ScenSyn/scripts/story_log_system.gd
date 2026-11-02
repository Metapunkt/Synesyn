extends Control

const WorkshopResumeHydrateScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_resume_hydrate.gd"
)

var SAVE_DIR: String = RuntimeConfig.get_scensyn_story_log_dir()
var HTML_SAVE_DIR: String = RuntimeConfig.get_scensyn_story_log_dir() + "storylogs_html_version/"
const PLAYER_COLOR = Color(0.96, 0.975, 1.0, 0.98)
const AI_COLOR = Color(0.94, 0.96, 0.995, 0.96)
const BANNER_COLOR = Color(0.88, 0.93, 0.99, 0.98)
const NARRATOR_COLOR = Color(0.945, 0.96, 0.99, 0.98)
const STORY_LOG_TEXT_COLOR = Color(0.08, 0.16, 0.32, 1)
# Dark-mode cards stay on the navy surface ladder (avoid near-white slabs).
const PLAYER_COLOR_DARK = Color(0.12, 0.16, 0.22, 0.96)
const AI_COLOR_DARK = Color(0.11, 0.15, 0.21, 0.96)
const BANNER_COLOR_DARK = Color(0.13, 0.18, 0.26, 0.96)
const NARRATOR_COLOR_DARK = Color(0.11, 0.155, 0.215, 0.96)
const STORY_LOG_TEXT_COLOR_DARK = Color(0.88, 0.91, 0.95, 1)

# Rotating palette for per-character color distinction.
# Subtle hue shifts within a cool blue family so cards remain cohesive.
const CHARACTER_COLOR_PALETTE: Array[Color] = [
	Color(0.94, 0.96, 0.995, 0.96),  # soft blue (first character)
	Color(0.93, 0.97, 0.99, 0.96),  # ice blue tint
	Color(0.938, 0.998, 0.960, 0.96),  # sage tint
	Color(0.998, 0.955, 0.938, 0.96),  # warm sand tint
	Color(0.998, 0.938, 0.960, 0.96),  # rose tint
	Color(0.955, 0.998, 0.938, 0.96),  # mint tint
]
const CHARACTER_COLOR_PALETTE_DARK: Array[Color] = [
	Color(0.13, 0.18, 0.26, 0.96),
	Color(0.12, 0.17, 0.24, 0.96),
	Color(0.12, 0.19, 0.18, 0.96),
	Color(0.18, 0.15, 0.14, 0.96),
	Color(0.18, 0.14, 0.18, 0.96),
	Color(0.14, 0.19, 0.16, 0.96),
]
# Maps character (sender) name → assigned Color. Populated lazily on first appearance.
var _character_color_map: Dictionary = {}

# Ensure BBCode [b] renders as real bold by providing a bold font.
# Without this, some themes/fonts have no bold variant and [b] can look identical.
const ChatFontRegular: Font = preload("res://tools/fonts/Noto_Sans/static/NotoSans-Regular.ttf")
const ChatFontBold: Font = preload("res://tools/fonts/Noto_Sans/static/NotoSans-Bold.ttf")

@onready var scroll_container = $ScrollContainer
@onready var message_container = %VBoxContainer
#@onready var message_container = %MarginContainer
@onready var line_edit = $HBoxContainer/LineEdit
@onready var send_button = $HBoxContainer/Button
#@onready var dummy_label = %DummyRichTextLabel
@onready var timer = $Timer
@onready var Network = %Network

var session_id: String = ""
var _artifact_file_stem: String = ""
var story_log: Array = []

func _ready():		
	send_button.connect("pressed", _on_send_pressed)
	timer.connect("timeout", _on_timer_timeout)
	timer.start(2.0)  # Start timer for test messages
	custom_minimum_size = Vector2(0, 120)
	
	# Ensure the save directories exist in a runtime-safe location.
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(HTML_SAVE_DIR))
	
	set_session_id(generate_session_id())
	if ThemeManager and not ThemeManager.mode_changed.is_connected(_on_theme_mode_changed):
		ThemeManager.mode_changed.connect(_on_theme_mode_changed)

func generate_session_id() -> String:
	return str(Time.get_unix_time_from_system())

func set_session_id(new_session_id: String) -> void:
	session_id = String(new_session_id).strip_edges()
	if session_id.is_empty():
		session_id = generate_session_id()
	_artifact_file_stem = _build_file_stem()

func set_artifact_file_stem(file_stem: String) -> void:
	var cleaned_stem: String = String(file_stem).strip_edges()
	if cleaned_stem.is_empty():
		_artifact_file_stem = _build_file_stem()
	else:
		_artifact_file_stem = cleaned_stem

func get_artifact_file_stem() -> String:
	if _artifact_file_stem.is_empty():
		_artifact_file_stem = _build_file_stem()
	return _artifact_file_stem

func get_current_html_story_log_path() -> String:
	return HTML_SAVE_DIR + get_artifact_file_stem() + ".html"

func get_current_markdown_story_log_path() -> String:
	return SAVE_DIR + get_artifact_file_stem() + ".md"

# Returns a human-readable file stem: "<scenario-slug>_<YYYY-MM-DD_HHmm>_<unix>"
# Used for all export file names so sessions are immediately identifiable in a folder.
func _build_file_stem() -> String:
	var scenario_slug := "session"
	if Global and Global.has_method("get_game_flow_manager"):
		var gfm = Global.get_game_flow_manager()
		if gfm and gfm.has_method("get_scenario_name"):
			var sn := str(gfm.get_scenario_name()).strip_edges()
			if sn != "":
				scenario_slug = sn.to_lower().replace(" ", "-")
				# Strip non-alphanumeric except hyphens / underscores
				var clean := ""
				for ch in scenario_slug:
					if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "-" or ch == "_":
						clean += ch
				scenario_slug = clean.substr(0, 48)  # cap length
	var dt := Time.get_datetime_dict_from_system()
	var date_part := "%04d-%02d-%02d_%02d%02d" % [dt.year, dt.month, dt.day, dt.hour, dt.minute]
	return "%s_%s_%s" % [scenario_slug, date_part, session_id]

# Returns the active AI model name for provenance metadata.
func _get_ai_model_name() -> String:
	if not (Global and Global.has_method("get_plugin_manager")):
		return "unknown"
	var pm = Global.get_plugin_manager()
	if not pm:
		return "unknown"
	var aim = pm.get_ai_model_manager() if pm.has_method("get_ai_model_manager") else null
	if not aim:
		return "unknown"
	return str(aim.get_current_model()) if aim.has_method("get_current_model") else "unknown"

## How the session was staged, so a player can restage the log without the session:
## the art folders are found from collection and scenario the way ScenSynStageHost
## finds them, and voice_overrides lends one speaker another's voice. Added in
## synesyn_provenance_v2; a v1 sidecar has no `stage` block.
func _get_stage_provenance() -> Dictionary:
	var scen: Dictionary = {}
	var gfm: Object = Global.get_game_flow_manager() if Global and Global.has_method("get_game_flow_manager") else null
	if gfm and gfm.has_method("get_current_scenario"):
		var scen_any: Variant = gfm.get_current_scenario()
		if typeof(scen_any) == TYPE_DICTIONARY:
			scen = scen_any
	var collection: String = str(scen.get("_collection_id", Global.current_collection_id if Global else "")).strip_edges()
	var voice_overrides: Dictionary = {}
	if gfm and gfm.has_method("get_metaprompt_manager"):
		var mgr: Object = gfm.get_metaprompt_manager()
		if mgr and mgr.has_method("get_voice_overrides"):
			var overrides_any: Variant = mgr.get_voice_overrides(scen)
			if typeof(overrides_any) == TYPE_DICTIONARY:
				voice_overrides = overrides_any
	var cast: Array[String] = []
	for entry in story_log:
		var sender := String(entry.get("sender", "")).strip_edges()
		if sender != "" and sender != "_meta" and sender not in cast:
			cast.append(sender)
	return {
		"collection": collection,
		"scenario_key": str(scen.get("scenario_key", "")).strip_edges(),
		"scenario_name": str(scen.get("_scenario_name", scen.get("name", ""))).strip_edges(),
		"default_background": str(scen.get("default_background", "")).strip_edges(),
		"cast": cast,
		"voice_overrides": voice_overrides,
	}

# Returns unique participant display names from the story log (excludes Narrator and blank).
func _get_participants() -> Array[String]:
	var seen: Dictionary = {}
	for entry in story_log:
		var s := String(entry.get("sender", ""))
		if s != "" and s != "Narrator" and s != "_meta":
			seen[s] = true
	var result: Array[String] = []
	for k in seen.keys():
		result.append(str(k))
	return result

func _is_dark_story_log() -> bool:
	return ThemeManager != null and ThemeManager.is_dark()


func _is_local_player_sender(sender: String) -> bool:
	if sender.strip_edges() == "":
		return false
	if is_instance_valid(Network) and Network.has_method("get_peer_name"):
		var peer_name: String = str(Network.get_peer_name(multiplayer.get_unique_id()))
		if sender == peer_name:
			return true
	if Global and Global.has_method("get_current_character"):
		var current_character: Dictionary = Global.get_current_character()
		var character_name: String = str(current_character.get("name", "")).strip_edges()
		if character_name != "" and sender == character_name:
			return true
	return false


func _get_story_log_fill_color(sender: String) -> Color:
	var is_dark_mode: bool = _is_dark_story_log()
	if sender == "":
		return BANNER_COLOR_DARK if is_dark_mode else BANNER_COLOR
	if sender == "Narrator":
		return NARRATOR_COLOR_DARK if is_dark_mode else NARRATOR_COLOR
	if _is_local_player_sender(sender):
		return PLAYER_COLOR_DARK if is_dark_mode else PLAYER_COLOR
	# System senders (Session Record, Facilitator, Facilitator Note) use a distinct banner-adjacent tint.
	var system_senders: Array[String] = ["Session Record", "Facilitator", "Facilitator Note"]
	if sender in system_senders:
		return BANNER_COLOR_DARK if is_dark_mode else BANNER_COLOR
	# Named AI characters each get a stable per-sender hue index; resolve against
	# the active mode palette so theme toggles cannot leave light fills in dark mode.
	if not _character_color_map.has(sender):
		_character_color_map[sender] = int(_character_color_map.size())
	var palette: Array[Color] = (
		CHARACTER_COLOR_PALETTE_DARK if is_dark_mode else CHARACTER_COLOR_PALETTE
	)
	var palette_idx: int = int(_character_color_map[sender]) % palette.size()
	return palette[palette_idx]


func _on_theme_mode_changed(_mode: String) -> void:
	_restyle_visible_messages()


func _story_log_text_color() -> Color:
	return STORY_LOG_TEXT_COLOR_DARK if _is_dark_story_log() else STORY_LOG_TEXT_COLOR


func _story_log_font_sizes() -> Vector2i:
	var is_workshop_session: bool = (
		Global
		and str(Global.current_session_type) == "workshop_catalyst"
	)
	if is_workshop_session:
		return Vector2i(18, 19)
	return Vector2i(30, 26)


func _populate_story_log_label(
	label_node: RichTextLabel,
	sender_name: String,
	message_text: String
) -> void:
	var font_sizes: Vector2i = _story_log_font_sizes()
	var message_font_size: int = font_sizes.x
	var speaker_font_size: int = font_sizes.y
	var text_color: Color = _story_log_text_color()
	var color_hex: String = text_color.to_html(false)
	label_node.clear()
	label_node.add_theme_font_size_override("normal_font_size", message_font_size)
	label_node.add_theme_font_override("normal_font", ChatFontRegular)
	label_node.add_theme_font_override("bold_font", ChatFontBold)
	label_node.add_theme_color_override("default_color", text_color)
	# Explicit BBCode color so theme toggles cannot leave dark-mode ink on light cards.
	var body_bbcode: String = message_text
	if sender_name != "":
		body_bbcode = (
			"[font_size=%d][b]%s:[/b][/font_size] %s"
			% [speaker_font_size, sender_name, message_text]
		)
	label_node.append_text("[color=#%s]%s[/color]" % [color_hex, body_bbcode])


func _restyle_visible_messages() -> void:
	if not is_instance_valid(message_container):
		return
	for child_node: Node in message_container.get_children():
		var panel_container: PanelContainer = child_node as PanelContainer
		if not panel_container or not panel_container.has_meta("story_log_sender"):
			continue
		var sender_name: String = str(panel_container.get_meta("story_log_sender"))
		var message_text: String = str(panel_container.get_meta("story_log_message"))
		var fill_color: Color = _get_story_log_fill_color(sender_name)
		var card_style: StyleBoxFlat = _build_story_log_card_style(fill_color)
		panel_container.add_theme_stylebox_override("panel", card_style)
		var label_node: RichTextLabel = panel_container.find_child("StoryLogMessageLabel", true, false) as RichTextLabel
		if label_node:
			_populate_story_log_label(label_node, sender_name, message_text)

func _build_story_log_card_style(fill_color: Color) -> StyleBoxFlat:
	var card_style := StyleBoxFlat.new()
	card_style.content_margin_left = 18.0
	card_style.content_margin_top = 16.0
	card_style.content_margin_right = 18.0
	card_style.content_margin_bottom = 14.0
	card_style.bg_color = fill_color
	# No stroke — soft AA borders wash out fills in both light and dark.
	card_style.border_width_left = 0
	card_style.border_width_top = 0
	card_style.border_width_right = 0
	card_style.border_width_bottom = 0
	card_style.border_color = Color(0, 0, 0, 0)
	card_style.corner_radius_top_left = 12
	card_style.corner_radius_top_right = 12
	card_style.corner_radius_bottom_right = 12
	card_style.corner_radius_bottom_left = 12
	card_style.shadow_color = Color(0, 0, 0, 0)
	card_style.shadow_size = 0
	card_style.shadow_offset = Vector2(0, 2)
	return card_style

func add_message(text: String, sender: String) -> void:
	print("Debug: StoryLogSystem add_message called. Text:", text, " Sender:", sender)
	# Normalize trailing newlines to avoid save/display discrepancies
	var normalized_text := String(text)
	while normalized_text.ends_with("\n"):
		normalized_text = normalized_text.substr(0, normalized_text.length() - 1)

	# Skip if last entry is identical (prevents duplicates due to double-path adds)
	if not story_log.is_empty():
		var last: Dictionary = story_log.back()
		var last_sender := String(last.get("sender", ""))
		var last_message := String(last.get("message", ""))
		while last_message.ends_with("\n"):
			last_message = last_message.substr(0, last_message.length() - 1)
		if last_sender == sender and last_message == normalized_text:
			return

	# Create a PanelContainer for the card fill (not the RichTextLabel).
	# Putting the fill on the label left player bubbles stuck on light fills after
	# theme toggles / peer-name mismatches.
	var panel_container := PanelContainer.new()
	panel_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel_container.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	panel_container.set_meta("story_log_sender", sender)
	panel_container.set_meta("story_log_message", normalized_text)

	var margin_container := MarginContainer.new()
	margin_container.add_theme_constant_override("margin_top", 16 if sender == "" else 12)
	margin_container.add_theme_constant_override("margin_left", 15)
	margin_container.add_theme_constant_override("margin_bottom", 10)
	margin_container.add_theme_constant_override("margin_right", 10)

	var label := RichTextLabel.new()
	label.name = "StoryLogMessageLabel"
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.selection_enabled = true
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	label.add_theme_constant_override("line_separation", 4)
	var fill_color: Color = _get_story_log_fill_color(sender)
	var style_box: StyleBoxFlat = _build_story_log_card_style(fill_color)
	panel_container.add_theme_stylebox_override("panel", style_box)
	_populate_story_log_label(label, sender, normalized_text)

	panel_container.add_child(margin_container)
	margin_container.add_child(label)
	message_container.add_child(panel_container)
	print("Debug: New label added to ScrollContainer")
	
	# Add message to story_log array
	var timestamp = get_current_datetime()
	story_log.append({"sender": sender, "message": normalized_text, "timestamp": timestamp, "timestamp_us": Time.get_ticks_usec()})
	
	# Save the updated story log
	save_story_log()
	
	await get_tree().process_frame
	
	scroll_container.scroll_vertical = scroll_container.get_v_scroll_bar().max_value
	print("Debug: Scrolled to bottom of ScrollContainer")

func message_to_html(sender: String, message: String) -> String:
	# Strip any sender-name prefix that was baked into the message string.
	for size_tag in ["[font_size=16]", "[font_size=26]", "[font_size=18]"]:
		var prefix: String = size_tag + "[b]" + sender + ":[/b][/font_size]"
		if message.begins_with(prefix):
			message = message.substr(prefix.length()).strip_edges()
			break

	# Convert common BBCode to HTML
	var rx_font_size := RegEx.new()
	rx_font_size.compile("\\[font_size=(\\d+)\\](.*?)\\[/font_size\\]")
	message = rx_font_size.sub(message, "<span style='font-size:%1px'>$2</span>", true)
	message = message.replace("[b]", "<strong>").replace("[/b]", "</strong>")
	message = message.replace("[i]", "<em>").replace("[/i]", "</em>")
	message = message.replace("[u]", "<u>").replace("[/u]", "</u>")
	message = message.replace("\n", "<br>")

	var html: String = "<p>"
	if sender != "":
		html += "<strong class='speaker'>" + sender + ":</strong> "
	html += message + "</p>\n"
	return html

func save_story_log():
	# Ensure save directories exist
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(SAVE_DIR)):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIR))
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(HTML_SAVE_DIR)):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(HTML_SAVE_DIR))

	var stem := get_artifact_file_stem()
	var scenario_name := ""
	if Global and Global.has_method("get_game_flow_manager"):
		var gfm = Global.get_game_flow_manager()
		if gfm and gfm.has_method("get_scenario_name"):
			scenario_name = str(gfm.get_scenario_name())
	var ai_model := _get_ai_model_name()
	var participants := _get_participants()
	var now_str := get_current_datetime()

	# --- JSON (array format unchanged for backward-compatible loading) ---
	var json_file_path: String = SAVE_DIR + stem + ".json"
	var json_file := FileAccess.open(json_file_path, FileAccess.WRITE)
	if json_file:
		json_file.store_string(JSON.stringify(story_log, "  "))
		json_file.close()
		print("JSON story log saved: ", json_file_path)
	else:
		print("Failed to save JSON story log: ", json_file_path)

	# --- Provenance sidecar (.provenance.json) ---
	# Stores metadata separately so the main JSON array stays loader-compatible.
	var provenance: Dictionary = {
		"schema": "synesyn_provenance_v2",
		"session_id": session_id,
		"file_stem": stem,
		"session_type": Global.current_session_type if Global else "",
		"scenario": scenario_name,
		"ai_model": ai_model,
		"participants": participants,
		"entry_count": story_log.size(),
		"saved_at": now_str,
		"stage": _get_stage_provenance(),
	}
	var prov_path: String = SAVE_DIR + stem + ".provenance.json"
	var prov_file := FileAccess.open(prov_path, FileAccess.WRITE)
	if prov_file:
		prov_file.store_string(JSON.stringify(provenance, "  "))
		prov_file.close()
	else:
		print("Failed to save provenance sidecar: ", prov_path)

	# --- Workshop Catalyst sidecar (unchanged) ---
	if Global and Global.current_session_type == "workshop_catalyst" and typeof(StoryState) != TYPE_NIL and StoryState:
		var state_dict: Dictionary = StoryState.get_state()
		var ws_any: Variant = state_dict.get("workshop_catalyst", {})
		if typeof(ws_any) == TYPE_DICTIONARY:
			var ws_to_save: Dictionary = (ws_any as Dictionary).duplicate(true)
			if Global and Global.has_method("get_current_scenario"):
				var scenario_now: Dictionary = Global.get_current_scenario()
				var snapshot: Dictionary = WorkshopResumeHydrateScript.compact_scenario_snapshot(
					scenario_now
				)
				if not snapshot.is_empty():
					ws_to_save["scenario_snapshot"] = snapshot
			var ws_path: String = SAVE_DIR + stem + ".workshop.json"
			var ws_file := FileAccess.open(ws_path, FileAccess.WRITE)
			if ws_file:
				ws_file.store_string(JSON.stringify(ws_to_save, "  "))
				ws_file.close()
				print("Workshop state saved: ", ws_path)

	# --- HTML ---
	var participants_html := "—"
	if not participants.is_empty():
		participants_html = ", ".join(participants)
	var html_file_path: String = HTML_SAVE_DIR + stem + ".html"
	var html_file := FileAccess.open(html_file_path, FileAccess.WRITE)
	if html_file:
		var html_content: String = """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <style>
	body { font-family: Arial, sans-serif; line-height: 1.6; max-width: 860px; margin: 0 auto; padding: 20px; }
	h1 { color: #333; margin-bottom: 4px; }
	.header { background: #f4f4f4; padding: 16px 20px; margin-bottom: 24px; border-left: 4px solid #aaa; }
	.header p { margin: 4px 0; font-size: 0.95em; }
	.meta-key { color: #555; font-weight: bold; }
	.story-content p { margin: 6px 0; }
	strong.speaker { font-size: 1.05em; }
  </style>
</head>
<body>
  <div class="header">
	<h1>Synesyn Session Transcript</h1>
	<p><span class="meta-key">Scenario:</span> %s</p>
	<p><span class="meta-key">Date:</span> %s</p>
	<p><span class="meta-key">AI model:</span> %s</p>
	<p><span class="meta-key">Participants:</span> %s</p>
	<p><span class="meta-key">Session ID:</span> %s</p>
  </div>
  <div class="story-content">
""" % [scenario_name, now_str, ai_model, participants_html, session_id]

		for entry in story_log:
			html_content += message_to_html(entry.sender, entry.message)

		html_content += "\n  </div>\n</body>\n</html>\n"
		html_file.store_string(html_content)
		html_file.close()
		print("HTML story log saved: ", html_file_path)
	else:
		print("Failed to save HTML story log: ", html_file_path)

	# --- Markdown ---
	var participants_md := participants.is_empty() and "—" or ", ".join(participants)
	var md_file_path: String = SAVE_DIR + stem + ".md"
	var md_file := FileAccess.open(md_file_path, FileAccess.WRITE)
	if md_file:
		var md_content: String = "# Synesyn Session Transcript\n\n"
		md_content += "| | |\n|---|---|\n"
		md_content += "| **Scenario** | %s |\n" % scenario_name
		md_content += "| **Date** | %s |\n" % now_str
		md_content += "| **AI model** | %s |\n" % ai_model
		md_content += "| **Participants** | %s |\n" % participants_md
		md_content += "| **Session ID** | %s |\n\n" % session_id
		md_content += "---\n\n"
		for entry in story_log:
			var s := String(entry.get("sender", ""))
			var m := String(entry.get("message", ""))
			# Strip BBCode tags for plain Markdown
			m = _strip_bbcode(m)
			if s != "":
				md_content += "**%s:** %s\n\n" % [s, m]
			else:
				md_content += "%s\n\n" % m
		md_file.store_string(md_content)
		md_file.close()
		print("Markdown story log saved: ", md_file_path)
	else:
		print("Failed to save Markdown story log: ", md_file_path)

# Strip common BBCode tags to produce clean plain text for Markdown export.
func _strip_bbcode(text: String) -> String:
	var result := text
	# Tags with parameters: [font_size=N], [color=...], etc.
	var param_tags := ["font_size", "color", "url"]
	for tag in param_tags:
		while true:
			var open_start := result.find("[" + tag)
			if open_start == -1:
				break
			var open_end := result.find("]", open_start)
			if open_end == -1:
				break
			result = result.substr(0, open_start) + result.substr(open_end + 1)
	# Self-closing or simple tags: [b], [/b], [i], [/i], [u], [/u], etc.
	var simple_tags := ["[b]", "[/b]", "[i]", "[/i]", "[u]", "[/u]",
		"[/font_size]", "[/color]", "[/url]", "[center]", "[/center]",
		"[right]", "[/right]", "[code]", "[/code]"]
	for tag in simple_tags:
		result = result.replace(tag, "")
	return result
		
#func load_story_log(previous_session_id: String):
	#var file_path = SAVE_DIR + "session_" + previous_session_id + ".json"
	#if FileAccess.file_exists(file_path):
		#var file = FileAccess.open(file_path, FileAccess.READ)
		#var json_string = file.get_as_text()
		#file.close()
		#var json = JSON.new()
		#var parse_result = json.parse(json_string)
		#if parse_result == OK:
			#story_log = json.get_data()
			#set_full_log(JSON.stringify(story_log))
		#else:
			#print("Failed to parse story log JSON")
	#else:
		#print("No story log file found for session: ", previous_session_id)

func load_story_log(previous_session_id: String):
	var json_file_path = SAVE_DIR + "session_" + previous_session_id + ".json"
	if FileAccess.file_exists(json_file_path):
		var file = FileAccess.open(json_file_path, FileAccess.READ)
		var json_string = file.get_as_text()
		file.close()
		var json = JSON.new()
		var parse_result = json.parse(json_string)
		if parse_result == OK:
			story_log = json.get_data()
			set_full_log(JSON.stringify(story_log))
		else:
			print("Failed to parse story log JSON")
	else:
		print("No JSON story log file found for session: ", previous_session_id)
	
	# Load HTML version (if needed)
	var html_file_path = HTML_SAVE_DIR + "session_" + previous_session_id + ".html"
	if FileAccess.file_exists(html_file_path):
		print("HTML story log file found: ", html_file_path)
	else:
		print("No HTML story log file found for session: ", previous_session_id)

func get_current_datetime() -> String:
	var datetime = Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d %02d:%02d:%02d" % [
		datetime.year, datetime.month, datetime.day,
		datetime.hour, datetime.minute, datetime.second
	]
						
func _on_send_pressed():
	pass
	#var text = line_edit.text.strip_edges()
	#if text != "":
		#var player_name = Network.get_peer_name(multiplayer.get_unique_id())
		#add_message(text, player_name)
		#line_edit.clear()

func _on_timer_timeout():
#	add_message("This is a test message from the system.")
	pass

func set_full_log(full_log: String):
	for child in message_container.get_children():
		child.queue_free()
	message_container.clear()
	
	var messages = full_log.strip_edges().split("\n\n", true)
	
	for msg in messages:
		if msg != "":
			var sender_and_msg = msg.split(": ", false, 1)
			if sender_and_msg.size() == 2:
				var sender = sender_and_msg[0].strip_edges()
				var message = sender_and_msg[1]
				add_message(message, sender)
			else:
				add_message(msg, "")
	
	await get_tree().process_frame
	
	scroll_container.scroll_vertical = scroll_container.get_v_scroll_bar().max_value
	print("Debug: Story Log synced and scrolled to bottom.")
