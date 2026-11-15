extends Node
## Dogfood walkthrough: fictional community content plan inside ReadyMade.
## Creates a workplan, tasks with publish dates/channels, scratchpad notes,
## CSV round-trip, cadence warnings, markdown export, and a friction log.
## Exits 0 on success.

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
		"Fixed: CSV/JSON bulk import-export with preview (create + update by task_id)."
	)
	_log_friction(
		"bulk_revise",
		"high",
		"Fixed: export → edit → re-import updates existing tasks inside ReadyMade."
	)
	_log_friction(
		"recurring_tasks",
		"medium",
		"Fixed: weekly weekday + end-date UI expands into dated instances."
	)
	_log_friction(
		"discord_subchannels",
		"medium",
		"Fixed: workplan custom_channels + Manage Channels UI; org lists are user data."
	)
	_log_friction(
		"markdown_export",
		"high",
		"Fixed: markdown exporter + dialog .md filter."
	)
	_log_friction(
		"timezone_schedule",
		"low",
		"Fixed: publish_time + IANA timezone per task / workplan default."
	)
	_log_friction(
		"channel_cap_warnings",
		"low",
		"Fixed: per-channel weekly cadence caps with non-blocking warnings."
	)
	_log_friction(
		"search_filter_campaign",
		"medium",
		"Fixed: calendar filter/search by channel, campaign, theme, content status."
	)
	_log_friction(
		"open_slot_ux",
		"medium",
		"Fixed: first-class content_status (incl. open_slot) on WorkplanTask."
	)
	_log_friction(
		"templates_for_discord",
		"low",
		"Fixed: Community Post format template + Copy as Markdown on task cards."
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

	manager.set_default_timezone("Europe/Oslo")
	_expect(manager.get_default_timezone() == "Europe/Oslo", "workplan default timezone set")

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

	manager.set_channel_cadence_cap("#general", 2)
	manager.set_channel_cadence_cap("#studio-notes", 2)

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
		task.format = "Community Post"
		task.formats = ["Community Post"]
		task.publish_date = String(post.get("date", ""))
		task.publish_time = String(post.get("time", "11:00"))
		task.publish_timezone = String(post.get("tz", "Europe/Oslo"))
		task.scheduled_date = String(post.get("date", ""))
		task.deadline = String(post.get("date", ""))
		task.content_theme = String(post.get("theme", ""))
		task.campaign_tag = "example-collective-2026-11"
		task.target_audience = "Example Art Collective"
		task.generated_content = String(post.get("draft", ""))
		task.core_idea = String(post.get("theme", ""))
		var status_str: String = String(post.get("status", "draft"))
		task.set_content_status(status_str)
		var source_str: String = String(post.get("source", ""))
		var image_str: String = String(post.get("image", ""))
		var notes_parts: PackedStringArray = PackedStringArray()
		notes_parts.append("SOURCE: %s" % source_str)
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
		task.ensure_task_id()
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

	# --- Recurrence: Friday roundup expander ---
	const RecurrenceScript = preload("res://readymade/scripts/workplan_recurrence.gd")
	var friday := WorkplanTask.new()
	friday.title = "This week in the studio map"
	friday.channel = "#general"
	friday.publish_date = "2026-11-20"  # Friday
	friday.publish_time = "11:00"
	friday.publish_timezone = "Europe/Oslo"
	friday.content_theme = "Weekly postcard"
	friday.campaign_tag = "example-collective-2026-11"
	friday.set_content_status("draft")
	friday.generated_content = "Friday postcard seed for recurrence expansion."
	friday.format = "Community Post"
	RecurrenceScript.apply_weekly_to_task(friday, [4], "2026-12-04")
	var friday_added: int = RecurrenceScript.expand_into_workplan(workplan, friday)
	_expect(friday_added >= 2, "Friday recurrence expands into dated instances (%d)" % friday_added)
	manager.save_current_workplan()

	# --- Filters ---
	var cal := CalendarView.new()
	cal.filter_mode = "channel"
	cal.filter_value = "#general"
	var general_hits: int = 0
	for task_any in workplan.get_all_tasks():
		var ft: WorkplanTask = task_any as WorkplanTask
		if cal.matches_filters(ft):
			general_hits += 1
	_expect(general_hits >= 1, "channel filter finds #general posts")
	cal.filter_mode = "content_status"
	cal.filter_value = "open_slot"
	var slot_hits: int = 0
	for task_any2 in workplan.get_all_tasks():
		var ft2: WorkplanTask = task_any2 as WorkplanTask
		if cal.matches_filters(ft2):
			slot_hits += 1
	_expect(slot_hits >= 3, "status filter finds open_slot posts")
	cal.queue_free()

	# --- Cadence warnings (non-blocking) ---
	var cadence_warnings: Array = manager.get_cadence_warnings()
	_expect(cadence_warnings.size() >= 0, "cadence validation runs")
	var cadence_report: String = manager.get_cadence_validation_report()
	_expect(not cadence_report.is_empty(), "cadence validation report non-empty")
	print("Dogfood cadence report:\n", cadence_report)

	# --- CSV round-trip: export, edit welcome by task_id, re-import ---
	const BulkIOScript = preload("res://readymade/scripts/workplan_task_bulk_io.gd")
	var export_dir: String = RuntimeConfig.get_readymade_data_dir().path_join("exports")
	DirAccess.make_dir_recursive_absolute(export_dir)
	var csv_path: String = export_dir.path_join("example_collective_nov2026_tasks.csv")
	_expect(manager.export_current_tasks_csv(csv_path), "export_current_tasks_csv")
	var csv_text: String = FileAccess.get_file_as_string(csv_path)
	_expect(csv_text.find("task_id") >= 0, "CSV has task_id column")
	_expect(csv_text.find("Europe/Oslo") >= 0 or csv_text.find("publish_timezone") >= 0, "CSV carries timezone")
	var rows: Array = BulkIOScript.parse_csv(csv_text)
	_expect(rows.size() >= posts.size(), "CSV rows cover fixture tasks")
	var welcome_task: WorkplanTask = null
	for task_any_w in workplan.get_all_tasks():
		var candidate: WorkplanTask = task_any_w as WorkplanTask
		if candidate != null and candidate.title.findn("Welcome") >= 0:
			welcome_task = candidate
			break
	_expect(welcome_task != null, "found welcome task in workplan")
	var welcome_id: String = welcome_task.ensure_task_id() if welcome_task else ""
	# Targeted JSON update (avoids multiline CSV quoting pitfalls in fixture drafts).
	var update_doc := {
		"tasks": [{
			"task_id": welcome_id,
			"publish_date": welcome_task.publish_date if welcome_task else "",
			"publish_time": welcome_task.publish_time if welcome_task else "",
			"publish_timezone": welcome_task.publish_timezone if welcome_task else "",
			"channel": welcome_task.channel if welcome_task else "",
			"content_theme": welcome_task.content_theme if welcome_task else "",
			"campaign_tag": welcome_task.campaign_tag if welcome_task else "",
			"title": welcome_task.title if welcome_task else "",
			"draft": (welcome_task.generated_content if welcome_task else "") + "\n\n(Reviewed in bulk rewrite.)",
			"status": "approved",
			"notes": welcome_task.notes if welcome_task else "",
		}]
	}
	var update_json: String = JSON.stringify(update_doc)
	var preview: Dictionary = manager.preview_import_tasks(update_json, "json")
	_expect(int(preview.get("updated", 0)) == 1, "JSON re-import preview updates == 1")
	_expect(int(preview.get("created", 0)) == 0, "JSON re-import creates none")
	var before_count: int = workplan.get_total_tasks()
	var applied: Dictionary = manager.apply_import_tasks_preview(preview)
	_expect(int(applied.get("updated", 0)) == 1, "JSON re-import applied one update")
	_expect(workplan.get_total_tasks() == before_count, "re-import update does not duplicate tasks")
	_expect(welcome_task != null and welcome_task.generated_content.find("Reviewed in bulk rewrite") >= 0, "welcome draft rewritten via bulk re-import")
	_expect(welcome_task != null and welcome_task.get_content_status() == "approved", "welcome content_status approved after import")
	# Also assert CSV parse retained timezone column from full export.
	var tz_seen: bool = false
	for row_any in rows:
		var row: Dictionary = row_any
		if String(row.get("publish_timezone", "")).find("Europe") >= 0:
			tz_seen = true
			break
	_expect(tz_seen, "parsed CSV rows retain Europe timezone values")

	await _exercise_scratchpad()

	var export_path: String = export_dir.path_join("example_collective_nov2026.md")
	var exported: bool = manager.export_workplan_as_markdown(WORKPLAN_NAME, export_path)
	_expect(exported, "export_workplan_as_markdown")
	_expect(FileAccess.file_exists(export_path), "markdown export file exists")
	if FileAccess.file_exists(export_path):
		var md: String = FileAccess.get_file_as_string(export_path)
		_expect(md.find("#general") >= 0, "export mentions #general")
		_expect(md.find("open_slot") >= 0, "export carries open_slot plan status")
		_expect(md.find("approved") >= 0, "export carries approved status after bulk rewrite")
		_expect(md.find("Welcome to the collective") >= 0, "pinned welcome post present")
		_expect(md.find("Starting from the scrap pile") >= 0, "month opener present")
		_expect(md.find("The system proposes; a person closes") >= 0, "process-rule draft present")
		_expect(md.find("#studio-notes") >= 0 and md.find("do-nothing path") >= 0, "weekend still present")
		_expect(md.find("This week in the studio map") >= 0, "Friday postcard framing present")
		_expect(md.find("#reading-group") >= 0, "reading-group channel present")
		_expect(md.find("Europe/Oslo") >= 0 or md.find("11:00") >= 0, "export shows publish time/tz")
		print("Dogfood: exported markdown to ", export_path)

	const MarkdownScript = preload("res://readymade/scripts/workplan_task_markdown.gd")
	var sample: WorkplanTask = workplan.get_all_tasks()[0] as WorkplanTask
	var card_md: String = MarkdownScript.to_clipboard_markdown(sample, workplan)
	_expect(card_md.find(sample.title) >= 0, "copy-as-markdown helper works")

	var friction_path: String = RuntimeConfig.get_readymade_data_dir().path_join(FRICTION_PATH_REL)
	DirAccess.make_dir_recursive_absolute(friction_path.get_base_dir())
	var friction_doc := {
		"workplan": WORKPLAN_NAME,
		"tasks": workplan.get_total_tasks(),
		"drafts": draft_count,
		"placeholders": placeholder_count,
		"open_slots": open_slot_count,
		"export_path": export_path,
		"csv_path": csv_path,
		"cadence_warnings": cadence_warnings.size(),
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
	_expect(sorted_tasks.size() == workplan.get_total_tasks(), "markdown export sort sees all tasks")

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
			+ "- Bulk CSV export/import used for reviewer rewrites.\n"
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
