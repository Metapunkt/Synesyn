extends Node
## Dogfood walkthrough: fictional community content plan inside ReadyMade.
## Creates a workplan, tasks with publish dates/channels, scratchpad notes,
## markdown export, and a friction log. Exits 0 on success.

const POSTS_PATH := "res://readymade/dogfood/example_community_posts.json"
const WORKPLAN_NAME := "Example Art Collective Nov–Dec 2026"
const FRICTION_PATH_REL := "dogfood_friction_content_plan.json"

var _failures: int = 0
var _checks: int = 0
var _friction: Array = []


func _ready() -> void:
	print("=== ReadyMade dogfood: example community content plan ===")
	await get_tree().process_frame
	await get_tree().process_frame

	var manager: Node = get_node_or_null("/root/WorkplanManager")
	_expect(manager != null, "WorkplanManager autoload present")
	if manager == null:
		_quit_fail()
		return

	# Wait for WorkplanManager deferred init.
	var waited: int = 0
	while manager.get("current_workplan") == null and waited < 60:
		await get_tree().process_frame
		waited += 1

	var posts: Array = _load_posts()
	_expect(posts.size() >= 20, "fixture has weekday coverage (%d posts)" % posts.size())

	_log_friction(
		"bulk_entry",
		"high",
		"No CSV/JSON bulk import in UI — dogfood loads fixture via script. Entering ~25 dated posts by hand would be prohibitive."
	)
	_log_friction(
		"recurring_tasks",
		"medium",
		"WorkplanTask.recurring_pattern exists but no UI to set or expand weekly Friday #general roundups."
	)
	_log_friction(
		"discord_subchannels",
		"medium",
		"Fixed: workplan custom_channels (add/rename/remove) merge into the task dialog; org-specific destination lists are user data, not a product mode."
	)
	_log_friction(
		"markdown_export",
		"high",
		"Export dialog previously defaulted to .tres only — content planners need .md handoff (fixed in this branch)."
	)
	_log_friction(
		"timezone_schedule",
		"low",
		"publish_date is a string date; no Europe/Oslo 11:00 time field or timezone on the task model."
	)
	_log_friction(
		"channel_cap_warnings",
		"low",
		"No warning when a channel exceeds ~2 posts/week — planner must track rhythm manually."
	)
	_log_friction(
		"search_filter_campaign",
		"medium",
		"Calendar filter_mode has a channel TODO; campaign_tag / content_theme not first-class filters."
	)

	# Create or replace workplan.
	if manager.available_workplans.has(WORKPLAN_NAME):
		print("Dogfood: removing prior workplan ", WORKPLAN_NAME)
		if manager.has_method("delete_workplan"):
			manager.delete_workplan(WORKPLAN_NAME)
		await get_tree().process_frame

	var created: bool = manager.create_new_workplan(
		WORKPLAN_NAME,
		"Dogfood: Example Art Collective content plan (fictional). Europe/Oslo ~11:00 weekdays."
	)
	_expect(created, "create_new_workplan")
	var workplan: Workplan = manager.get_current_workplan() as Workplan
	_expect(workplan != null, "current workplan after create")
	if workplan == null:
		_quit_fail()
		return

	# Example destinations only — never shipped as ModeManager defaults.
	var example_channels: Array[String] = [
		"#general",
		"#studio-notes",
		"#reading-group",
		"#open-studio",
		"#exhibitions",
	]
	_expect(manager.set_custom_channels(example_channels), "set example custom_channels on workplan")
	_expect(manager.get_custom_channels().size() == example_channels.size(), "example custom_channels loaded")
	_expect(ModeManager.get_available_modes().size() == 3, "only three generic product modes")
	_expect(ModeManager.get_available_modes().has("social_media"), "social_media mode present")

	var draft_count: int = 0
	var placeholder_count: int = 0
	var open_slot_count: int = 0
	var needs_approval_count: int = 0
	for post_any in posts:
		var post: Dictionary = post_any
		var task := WorkplanTask.new()
		task.title = String(post.get("title", "Untitled"))
		task.channel = String(post.get("channel", ""))
		if not task.channel.is_empty():
			task.channels = [task.channel]
		task.format = "Discord post"
		task.formats = ["Discord post"]
		task.publish_date = String(post.get("date", ""))
		task.scheduled_date = String(post.get("date", ""))
		task.deadline = String(post.get("date", ""))
		task.content_theme = String(post.get("theme", ""))
		task.campaign_tag = "example-collective-2026-11"
		task.target_audience = "Example Art Collective"
		task.generated_content = String(post.get("draft", ""))
		task.core_idea = String(post.get("theme", ""))
		var status_str: String = String(post.get("status", "draft"))
		var source_str: String = String(post.get("source", ""))
		var image_str: String = String(post.get("image", ""))
		var notes_parts: PackedStringArray = PackedStringArray()
		notes_parts.append("STATUS: %s" % status_str)
		notes_parts.append("SOURCE: %s" % source_str)
		notes_parts.append("TZ: %s %s" % [String(post.get("tz", "")), String(post.get("time", ""))])
		if not image_str.is_empty():
			notes_parts.append("IMAGE: %s" % image_str)
		if bool(post.get("open_thread", false)):
			notes_parts.append("OPEN_THREAD: yes")
		if bool(post.get("weekend_light", false)):
			notes_parts.append("WEEKEND_LIGHT: yes")
		var plan_notes_any: Variant = post.get("plan_notes", [])
		if typeof(plan_notes_any) == TYPE_ARRAY:
			for note_any in plan_notes_any:
				var note_line: String = String(note_any).strip_edges()
				if not note_line.is_empty():
					notes_parts.append(note_line)
		task.notes = "\n".join(notes_parts)
		task.status = "To Do"
		if status_str == "placeholder":
			task.priority = 1
		elif status_str == "open_slot":
			task.priority = 0
		else:
			task.priority = 2

		var month_key: String = _month_key(task.publish_date)
		workplan.add_task_to_month(month_key, task)
		if status_str == "placeholder":
			placeholder_count += 1
		elif status_str == "open_slot":
			open_slot_count += 1
		elif status_str == "needs_approval":
			needs_approval_count += 1
		else:
			draft_count += 1

	manager.save_current_workplan()
	_expect(workplan.get_total_tasks() == posts.size(), "task count matches fixture")
	_expect(open_slot_count >= 3, "at least three open slots across the month")
	_expect(needs_approval_count >= 1, "welcome post needs_approval present")
	print(
		"Dogfood: %d drafts, %d placeholders, %d open_slots, %d needs_approval"
		% [draft_count, placeholder_count, open_slot_count, needs_approval_count]
	)

	await _exercise_scratchpad()

	_log_friction(
		"templates_for_discord",
		"low",
		"No Discord-specific content template; used generated_content field as draft body instead."
	)

	var export_dir: String = RuntimeConfig.get_readymade_data_dir().path_join("exports")
	DirAccess.make_dir_recursive_absolute(export_dir)
	var export_path: String = export_dir.path_join("example_collective_nov2026.md")
	var exported: bool = manager.export_workplan_as_markdown(WORKPLAN_NAME, export_path)
	_expect(exported, "export_workplan_as_markdown")
	_expect(FileAccess.file_exists(export_path), "markdown export file exists")
	if FileAccess.file_exists(export_path):
		var md: String = FileAccess.get_file_as_string(export_path)
		_expect(md.find("#general") >= 0, "export mentions #general")
		_expect(md.find("open_slot") >= 0, "export carries open_slot plan status")
		_expect(md.find("needs_approval") >= 0, "export carries needs_approval for welcome")
		_expect(md.find("Welcome to the collective") >= 0, "pinned welcome post present")
		_expect(md.find("Starting from the scrap pile") >= 0, "month opener present")
		_expect(md.find("The system proposes; a person closes") >= 0, "process-rule draft present")
		_expect(md.find("#studio-notes") >= 0 and md.find("do-nothing path") >= 0, "weekend still present")
		_expect(md.find("This week in the studio map") >= 0, "Friday postcard framing present")
		_expect(md.find("#reading-group") >= 0, "reading-group channel present")
		_log_friction(
			"bulk_revise",
			"high",
			"ReadyMade has no bulk re-import/update of existing tasks from JSON — fixture rewritten outside the UI and dogfood recreates the workplan."
		)
		print("Dogfood: exported markdown to ", export_path)

	var friction_path: String = RuntimeConfig.get_readymade_data_dir().path_join(FRICTION_PATH_REL)
	DirAccess.make_dir_recursive_absolute(friction_path.get_base_dir())
	var friction_doc := {
		"workplan": WORKPLAN_NAME,
		"tasks": workplan.get_total_tasks(),
		"drafts": draft_count,
		"placeholders": placeholder_count,
		"open_slots": open_slot_count,
		"export_path": export_path,
		"friction": _friction,
	}
	var ff := FileAccess.open(friction_path, FileAccess.WRITE)
	if ff:
		ff.store_string(JSON.stringify(friction_doc, "\t"))
		ff.close()
		print("Dogfood: friction log at ", friction_path)
	else:
		_expect(false, "write friction log")

	const MarkdownExportScript = preload("res://readymade/scripts/workplan_markdown_export.gd")
	var sorted_tasks: Array = MarkdownExportScript._collect_sorted_tasks(workplan)
	_expect(sorted_tasks.size() == posts.size(), "markdown export sort sees all tasks")

	print("=== Dogfood results: %d checks, %d failures, %d friction items ===" % [_checks, _failures, _friction.size()])
	if _failures > 0:
		_quit_fail()
	else:
		print("ReadyMade dogfood PASSED")
		get_tree().quit(0)


func _exercise_scratchpad() -> void:
	print("-- scratchpad brainstorm notes --")
	var packed: PackedScene = load("res://readymade/ui/scratchpad.tscn") as PackedScene
	if packed == null:
		_log_friction("scratchpad_scene", "high", "Could not load scratchpad.tscn")
		_expect(false, "scratchpad.tscn loads")
		return
	var pad: Node = packed.instantiate()
	add_child(pad)
	await get_tree().process_frame
	var text_edit: TextEdit = pad.find_child("TextEdit", true, false) as TextEdit
	_expect(text_edit != null, "scratchpad TextEdit found")
	if text_edit:
		text_edit.text = (
			"Example Art Collective brainstorm (ReadyMade scratchpad)\n"
			+ "- Channels: #general #studio-notes #reading-group #open-studio #exhibitions\n"
			+ "- Rhythm: Europe/Oslo 11:00 weekdays; weekend light; ≤2/channel/week; Friday #general.\n"
			+ "- Open slots for timely updates; nothing else pre-scheduled beyond the fixture.\n"
		)
		var save_path: String = RuntimeConfig.get_readymade_data_dir().path_join(
			"scratchpad/example_collective_brainstorm.md"
		)
		DirAccess.make_dir_recursive_absolute(save_path.get_base_dir())
		var sf := FileAccess.open(save_path, FileAccess.WRITE)
		if sf:
			sf.store_string(text_edit.text)
			sf.close()
			_expect(true, "scratchpad notes saved under Documents/Synesyn/readymade")
			print("Dogfood: scratchpad notes at ", save_path)
		else:
			_expect(false, "scratchpad notes save")
	pad.queue_free()
	await get_tree().process_frame


func _load_posts() -> Array:
	if not FileAccess.file_exists(POSTS_PATH):
		push_error("Missing posts fixture: " + POSTS_PATH)
		return []
	var raw: String = FileAccess.get_file_as_string(POSTS_PATH)
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_ARRAY:
		push_error("Posts fixture is not an array")
		return []
	return parsed as Array


func _month_key(date_str: String) -> String:
	if date_str.length() >= 7:
		return date_str.substr(0, 7)
	return "undated"


func _log_friction(friction_id: String, severity: String, detail: String) -> void:
	_friction.append({"id": friction_id, "severity": severity, "detail": detail})
	print("FRICTION [%s] %s: %s" % [severity, friction_id, detail])


func _expect(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: ", label)
	else:
		_failures += 1
		push_error("  FAIL: " + label)
		print("  FAIL: ", label)


func _quit_fail() -> void:
	push_error("ReadyMade dogfood FAILED with %d failure(s)" % _failures)
	get_tree().quit(1)
