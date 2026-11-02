extends RefCounted
class_name GameSessionStoryLogUtils

const WorkshopResumeHydrateScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_resume_hydrate.gd"
)

static func on_load_story_log_pressed(owner: Node) -> void:
	if owner.get("_load_log_dialog") == null:
		var load_log_dialog = FileDialog.new()
		load_log_dialog.access = FileDialog.ACCESS_FILESYSTEM
		load_log_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		load_log_dialog.title = "Select Story Log JSON"
		load_log_dialog.filters = PackedStringArray(["*.json ; JSON files"])
		owner.add_child(load_log_dialog)
		load_log_dialog.file_selected.connect(owner._on_story_log_file_selected)
		owner.set("_load_log_dialog", load_log_dialog)
	var dlg: FileDialog = owner.get("_load_log_dialog")
	dlg.current_dir = RuntimeConfig.get_scensyn_story_log_dir()
	dlg.popup_centered_ratio(0.6)


static func on_new_story_log_pressed(owner: Node) -> void:
	var confirm_dialog = ConfirmationDialog.new()
	confirm_dialog.dialog_text = "Are you sure you want to create a new story log?\n\nThis will:\n• Clear the current story log display\n• Create a new session JSON file\n• Start a fresh story\n\nYour previous story log file will remain saved."
	confirm_dialog.title = "New Story Log"
	confirm_dialog.ok_button_text = "Create New"
	confirm_dialog.cancel_button_text = "Cancel"
	var theme_path = "res://ScenSyn/themes/SynesynUtility_light.tres"
	if ResourceLoader.exists(theme_path):
		confirm_dialog.theme = load(theme_path)
	owner.add_child(confirm_dialog)
	confirm_dialog.confirmed.connect(func():
		create_new_story_log(owner)
		confirm_dialog.queue_free()
	)
	confirm_dialog.canceled.connect(func():
		confirm_dialog.queue_free()
	)
	confirm_dialog.popup_centered()


static func prepare_workshop_resume(owner: Node, json_path: String) -> void:
	if json_path.is_empty():
		return
	owner.set("_is_loading_story_log", true)
	if Global:
		Global.is_loading_story_log = true
	_restore_workshop_scenario_from_path(json_path)


static func create_new_story_log(owner: Node) -> void:
	print("GameSession: Creating new story log")
	owner.call("_on_stop_tts_pressed")
	var story_log_system: Node = owner.get("story_log_system")
	if story_log_system:
		var timestamp = Time.get_unix_time_from_system()
		if story_log_system.has_method("set_session_id"):
			story_log_system.call("set_session_id", str(timestamp))
		else:
			story_log_system.session_id = str(timestamp)
		print("GameSession: New session ID: ", story_log_system.session_id)
	if story_log_system and story_log_system.has_node("%VBoxContainer"):
		var msg_container = story_log_system.get_node("%VBoxContainer")
		var child_count = msg_container.get_child_count()
		print("GameSession: Clearing ", child_count, " existing UI messages")
		for child in msg_container.get_children():
			child.queue_free()
	if story_log_system:
		story_log_system.story_log = []
		print("GameSession: Cleared story_log_system.story_log array")
	var current_state := StoryState.get_state()
	var new_state := current_state.duplicate(true)
	new_state["story_log"] = []
	new_state["current_turn"] = 0
	StoryState.set_state(new_state)
	print("GameSession: Cleared StoryState.story_log")
	owner.set("last_displayed_message_index", 0)
	if Global:
		Global.opening_spoken_log = false
		Global.opening_spoken_stage = false
		Global.opening_welcome_text = ""
	var game_flow_manager = owner.get("game_flow_manager")
	var scenario_data = game_flow_manager.get_current_scenario() if game_flow_manager else {}
	var welcome_message = ""
	var welcome_sender: String = "Narrator"
	if scenario_data.has("name") and scenario_data.has("objective"):
		if Global.current_session_type == "workshop_catalyst":
			welcome_sender = "Workshop Catalyst"
			var objective_text: String = str(scenario_data.objective).strip_edges()
			welcome_message = (
				"%s\n\n"
				% objective_text
			)
			welcome_message += (
				"[font_size=12][i]Speak or type below. "
				+ "Review Thinking Map and Session Record proposals before committing.[/i][/font_size]"
			)
		else:
			welcome_message = "[font_size=16][b]Welcome to " + scenario_data.name + "[/b][/font_size]\n\n"
			welcome_message += scenario_data.objective + "\n\n"
			welcome_message += "The story begins now. Choose your actions wisely and work together to navigate the challenges ahead."
		if Global:
			Global.opening_welcome_text = welcome_message
			Global.opening_spoken_log = false
			Global.opening_spoken_stage = false
	else:
		welcome_message = "[font_size=16][b]Welcome to the Story[/b][/font_size]\n\nThe narrative begins now. Work together to shape the story through your choices and actions."
	StoryState.add_log_entry(welcome_sender, welcome_message)
	print("GameSession: New story log created with welcome message")


static func on_story_log_file_selected(owner: Node, path: String) -> void:
	if path == "":
		return
	owner.call("_on_stop_tts_pressed")
	if Global:
		Global.is_loading_story_log = true
	apply_story_log_from_json(owner, path)
	if Global:
		Global.opening_spoken_log = false
		Global.opening_spoken_stage = false
		Global.opening_welcome_text = ""
		Global.is_loading_story_log = false


static func apply_story_log_from_json(owner: Node, path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		print("GameSession: Failed to open story log file: ", path)
		return
	var json_text := file.get_as_text()
	file.close()
	var json := JSON.new()
	var res := json.parse(json_text)
	if res != OK:
		print("GameSession: Failed to parse story log JSON: ", json.get_error_message())
		return
	var data = json.data
	if typeof(data) != TYPE_ARRAY:
		print("GameSession: Invalid story log format (expected array)")
		return
	var is_temp_loader: bool = (owner.get("_is_temp_story_log_loader") == true)
	owner.set("_is_loading_story_log", true)
	if Global:
		Global.is_loading_story_log = true
	if Global and Global.current_session_type == "workshop_catalyst":
		_restore_workshop_scenario_from_path(path)
	var story_log_system: Node = owner.get("story_log_system")
	if story_log_system and not is_temp_loader:
		if not (Global and Global.current_session_type == "workshop_catalyst"):
			_reuse_loaded_story_log_stem(story_log_system, path)
		if story_log_system.has_node("%VBoxContainer"):
			var msg_container = story_log_system.get_node("%VBoxContainer")
			var child_count = msg_container.get_child_count()
			print("GameSession: Clearing ", child_count, " existing UI messages from story log")
			for child in msg_container.get_children():
				child.queue_free()
		story_log_system.story_log = []
		print("GameSession: Cleared story_log_system.story_log array")
	var original_emitter := Global.get_tts_emitter() if Global else "story_stage"
	if Global:
		Global.set_tts_emitter("story_stage")
	owner.set("last_displayed_message_index", 0)
	var current_state := StoryState.get_state()
	var new_state := current_state.duplicate(true)
	new_state["story_log"] = []
	new_state["current_turn"] = 0
	StoryState.set_state(new_state)
	var seen := {}
	var narrator_welcome_seen := false
	for entry in data:
		if typeof(entry) == TYPE_DICTIONARY and entry.has("sender") and entry.has("message"):
			var s := String(entry.sender)
			var m := String(entry.message)
			var norm := String(owner.call("_normalize_loaded_text", m))
			var cleaned_m := m
			if cleaned_m.begins_with(s + ":"):
				cleaned_m = cleaned_m.substr((s + ":").length()).strip_edges()
			var bbcode_prefix := "[font_size=16][b]" + s + ":[/b][/font_size]"
			if cleaned_m.begins_with(bbcode_prefix):
				cleaned_m = cleaned_m.substr(bbcode_prefix.length()).strip_edges()
			if norm.begins_with(s + ":"):
				norm = norm.substr((s + ":").length()).strip_edges()
			if norm.find("Welcome to") != -1:
				if narrator_welcome_seen:
					continue
				narrator_welcome_seen = true
				if s == "":
					s = "Narrator"
			var key := s + "\u241F" + norm
			if seen.has(key):
				continue
			seen[key] = true
			StoryState.add_log_entry(s, cleaned_m)
	StoryState.set("current_turn", StoryState.get_state().get("story_log", []).size())
	if Global and Global.current_session_type == "workshop_catalyst":
		_apply_workshop_sidecar(owner, path)
		_fork_workshop_save_stem(story_log_system)
		_acknowledge_workshop_resume(owner)
	if not is_temp_loader:
		owner.call("update_display_from_story_state")
	if Global:
		Global.set_tts_emitter(original_emitter)
		Global.is_loading_story_log = false
	owner.set("_is_loading_story_log", false)
	print("GameSession: Story log loaded from ", path)


static func _restore_workshop_scenario_from_path(json_path: String) -> void:
	var restored: Dictionary = WorkshopResumeHydrateScript.scenario_from_resume_path(json_path)
	if restored.is_empty():
		return
	if Global and Global.has_method("set_custom_workshop_scenario"):
		Global.set_custom_workshop_scenario(restored)


static func _reuse_loaded_story_log_stem(story_log_system: Node, path: String) -> void:
	var slash_index := path.rfind("/")
	var file_name := path.substr(slash_index + 1) if slash_index != -1 else path
	var file_stem := file_name.substr(0, file_name.length() - 5) if file_name.ends_with(".json") else file_name
	if story_log_system.has_method("set_artifact_file_stem"):
		story_log_system.call("set_artifact_file_stem", file_stem)
	var last_underscore_index := file_stem.rfind("_")
	if last_underscore_index != -1 and last_underscore_index < file_stem.length() - 1:
		var new_session_id := file_stem.substr(last_underscore_index + 1)
		if new_session_id != "":
			if story_log_system.has_method("set_session_id"):
				story_log_system.call("set_session_id", new_session_id)
			else:
				story_log_system.session_id = new_session_id
			if story_log_system.has_method("set_artifact_file_stem"):
				story_log_system.call("set_artifact_file_stem", file_stem)


static func _apply_workshop_sidecar(owner: Node, path: String) -> void:
	var ws_path := ""
	if path.ends_with(".json"):
		ws_path = path.substr(0, path.length() - 5) + ".workshop.json"
	if ws_path == "" or not FileAccess.file_exists(ws_path):
		return
	var ws_file := FileAccess.open(ws_path, FileAccess.READ)
	if not ws_file:
		return
	var ws_text := ws_file.get_as_text()
	ws_file.close()
	var ws_parsed = JSON.parse_string(ws_text)
	if typeof(ws_parsed) != TYPE_DICTIONARY:
		return
	var ws_loaded: Dictionary = _annotate_loaded_workshop_state(ws_parsed)
	var cs: Dictionary = StoryState.get_state()
	var ns: Dictionary = cs.duplicate(true)
	ns["workshop_catalyst"] = ws_loaded
	StoryState.set_state(ns)
	print("GameSession: Loaded workshop state from ", ws_path)
	var wc_controller: Node = owner.get_node_or_null("WorkshopCatalystController")
	if wc_controller and wc_controller.has_method("reload_from_loaded_state"):
		wc_controller.call("reload_from_loaded_state")


static func _fork_workshop_save_stem(story_log_system: Node) -> void:
	if story_log_system == null:
		return
	if story_log_system.has_method("set_session_id"):
		story_log_system.call("set_session_id", str(Time.get_unix_time_from_system()))
	elif "session_id" in story_log_system:
		story_log_system.session_id = str(Time.get_unix_time_from_system())


static func _acknowledge_workshop_resume(owner: Node) -> void:
	var wc_controller: Node = owner.get_node_or_null("WorkshopCatalystController")
	if wc_controller:
		wc_controller.set("_session_auto_opened", true)
		if typeof(StoryState) != TYPE_NIL and StoryState:
			var story_log_any: Variant = StoryState.get_state().get("story_log", [])
			if typeof(story_log_any) == TYPE_ARRAY and not (story_log_any as Array).is_empty():
				wc_controller.set("_last_proactive_log_index", (story_log_any as Array).size() - 1)
	if typeof(AICharacterAgent) != TYPE_NIL and AICharacterAgent:
		if AICharacterAgent.has_method("mark_story_log_caught_up"):
			AICharacterAgent.call("mark_story_log_caught_up")

static func _annotate_loaded_workshop_state(ws: Dictionary) -> Dictionary:
	var annotated: Dictionary = ws.duplicate(true)
	annotated["resume_mode"] = "continue_prior_session"
	var session_id_text: String = str(annotated.get("session_id", "")).strip_edges()
	if session_id_text.is_empty():
		session_id_text = "previous session"
	var buckets_any: Variant = annotated.get("buckets", {})
	var buckets: Dictionary = buckets_any if typeof(buckets_any) == TYPE_DICTIONARY else {}
	var decisions_count: int = _bucket_count(buckets, "decisions")
	var open_questions_count: int = _bucket_count(buckets, "open_questions")
	var stage_history_any: Variant = annotated.get("stage_history", [])
	var stage_history: Array = stage_history_any if typeof(stage_history_any) == TYPE_ARRAY else []
	var summary_parts: Array[String] = ["Resumed from %s." % session_id_text]
	if decisions_count > 0:
		summary_parts.append("%d decisions carried forward." % decisions_count)
	if open_questions_count > 0:
		summary_parts.append("%d open questions still in play." % open_questions_count)
	if not stage_history.is_empty():
		var last_stage_any: Variant = stage_history.back()
		if typeof(last_stage_any) == TYPE_DICTIONARY:
			var last_stage: Dictionary = last_stage_any
			var stage_name: String = str(last_stage.get("stage_name", "")).strip_edges()
			if not stage_name.is_empty():
				summary_parts.append("Last completed stage: %s." % stage_name)
	annotated["resume_summary"] = " ".join(summary_parts)
	return annotated

static func _bucket_count(buckets: Dictionary, bucket_key: String) -> int:
	var items_any: Variant = buckets.get(bucket_key, [])
	var items: Array = items_any if typeof(items_any) == TYPE_ARRAY else []
	var count_value: int = 0
	for item_any in items:
		if str(item_any).strip_edges() != "":
			count_value += 1
	return count_value
