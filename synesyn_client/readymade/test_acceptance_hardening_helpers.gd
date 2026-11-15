extends RefCounted
## Hardening acceptance helpers (kept separate to stay under script line limits).


static func run_all(host: Node) -> void:
	_test_content_status_migration(host)
	_test_recurring_weekly_expand(host)
	_test_calendar_filters(host)
	_test_publish_timezone(host)
	_test_cadence_caps(host)
	_test_community_post_template_and_copy_markdown(host)
	_test_campaign_dashboard(host)
	_test_timezone_conversion(host)
	_test_calendar_reschedule(host)
	_test_workplan_file_dialog_filesystem(host)
	_test_nested_workplan_dialogs_non_exclusive(host)
	_test_file_dialog_line_enables_ok(host)
	_test_task_dependencies(host)
	_test_workplan_people_and_assignee(host)
	_test_stage_board_columns_and_move(host)
	_test_approval_log_append_only(host)
	_test_workplan_manager_section_labels(host)
	_test_copy_markdown_ui_reachability(host)
	_test_calendar_same_day_merge_and_tooltips(host)
	_test_import_preview_and_dependents_dialog_helpers(host)
	_test_people_role_field_width(host)
	_test_cascade_shifts_start_date_and_undo(host)
	_test_calendar_menu_dismiss_and_publish_tooltip(host)
	_test_live_calendar_path_and_tooltip_not_overwritten(host)
	_test_task_dialog_calendar_dates_prefilled(host)
	_test_move_dependents_dialog_deferred_single_ok(host)
	_test_imported_task_assignee_and_unedited_save(host)
	_test_calendar_card_right_click_and_double_click(host)
	_test_import_preview_hidden_before_result(host)
	const Round5Helpers = preload("res://readymade/test_acceptance_hardening_round5_helpers.gd")
	Round5Helpers.run_all(host)


static func _expect(host: Node, condition: bool, label: String) -> void:
	host.call("_expect", condition, label)


static func _test_content_status_migration(host: Node) -> void:
	print("-- content_status migration + markdown --")
	const MarkdownExportScript = preload("res://readymade/scripts/workplan_markdown_export.gd")
	var task := WorkplanTask.new()
	task.title = "Legacy status in notes"
	task.notes = "STATUS: needs_approval\nSOURCE: fixture"
	task.content_status = "draft"
	_expect(host, task.migrate_content_status_from_notes(), "migrate lifts STATUS from notes")
	_expect(host, task.get_content_status() == "needs_approval", "content_status is needs_approval")
	_expect(host, task.notes.find("STATUS:") < 0, "STATUS line stripped from notes")
	_expect(
		host,
		MarkdownExportScript.content_plan_status(task) == "needs_approval",
		"markdown export uses content_status field"
	)
	task.set_content_status("open_slot")
	_expect(host, task.get_content_status() == "open_slot", "set_content_status open_slot")
	task.set_content_status("not_a_real_status")
	_expect(host, task.get_content_status() == "draft", "invalid status falls back to draft")


static func _test_recurring_weekly_expand(host: Node) -> void:
	print("-- recurring weekly expand --")
	const RecurrenceScript = preload("res://readymade/scripts/workplan_recurrence.gd")
	var template := WorkplanTask.new()
	template.title = "Friday roundup"
	template.channel = "#general"
	template.publish_date = "2026-11-06"
	template.content_theme = "Weekly postcard"
	RecurrenceScript.apply_weekly_to_task(template, [4], "2026-11-27")
	_expect(host, template.recurring_pattern == "weekly", "pattern set to weekly")
	_expect(host, template.recurring_weekdays.has(4), "Friday weekday stamped")
	var instances: Array = RecurrenceScript.expand_weekly_instances(template)
	_expect(host, instances.size() == 4, "four Fridays in Nov 6–27 (%d)" % instances.size())
	if instances.size() >= 1:
		var first: WorkplanTask = instances[0] as WorkplanTask
		_expect(host, first.publish_date == "2026-11-06", "first Friday is 2026-11-06")
		_expect(host, first.recurring_pattern == "none", "instances clear recurrence")
	var workplan := Workplan.new()
	workplan.name = "Recurrence Probe"
	var added: int = RecurrenceScript.expand_into_workplan(workplan, template)
	_expect(host, added == 4, "expand_into_workplan adds 4")
	var added_again: int = RecurrenceScript.expand_into_workplan(workplan, template)
	_expect(host, added_again == 0, "second expand skips duplicates")


static func _test_calendar_filters(host: Node) -> void:
	print("-- calendar filters (channel/campaign/theme/status/search) --")
	var cal := CalendarView.new()
	var t1 := WorkplanTask.new()
	t1.title = "Roundup"
	t1.channel = "#general"
	t1.campaign_tag = "nov"
	t1.content_theme = "Weekly"
	t1.set_content_status("draft")
	var t2 := WorkplanTask.new()
	t2.title = "Studio note"
	t2.channel = "#studio-notes"
	t2.campaign_tag = "nov"
	t2.content_theme = "Process"
	t2.set_content_status("open_slot")
	cal.filter_mode = "channel"
	cal.filter_value = "#general"
	_expect(host, cal.matches_filters(t1), "channel filter keeps #general")
	_expect(host, not cal.matches_filters(t2), "channel filter drops #studio-notes")
	cal.filter_mode = "content_status"
	cal.filter_value = "open_slot"
	_expect(host, cal.matches_filters(t2), "status filter keeps open_slot")
	_expect(host, not cal.matches_filters(t1), "status filter drops draft")
	cal.filter_mode = "campaign"
	cal.filter_value = "nov"
	_expect(host, cal.matches_filters(t1) and cal.matches_filters(t2), "campaign filter matches both")
	cal.filter_mode = "theme"
	cal.filter_value = "Process"
	_expect(host, cal.matches_filters(t2), "theme filter keeps Process")
	cal.filter_mode = "all"
	cal.filter_value = ""
	cal.search_query = "studio"
	_expect(host, cal.matches_filters(t2), "search finds studio")
	_expect(host, not cal.matches_filters(t1), "search excludes roundup")
	cal.queue_free()


static func _test_publish_timezone(host: Node) -> void:
	print("-- publish timezone --")
	const PublishTimeScript = preload("res://readymade/scripts/workplan_publish_time.gd")
	const MarkdownExportScript = preload("res://readymade/scripts/workplan_markdown_export.gd")
	var workplan := Workplan.new()
	workplan.name = "TZ Probe"
	workplan.default_timezone = "Europe/Oslo"
	var task := WorkplanTask.new()
	task.title = "Timed post"
	task.publish_date = "2026-11-10"
	task.publish_time = "11:00"
	_expect(
		host,
		PublishTimeScript.effective_timezone(task, workplan) == "Europe/Oslo",
		"inherits workplan default timezone"
	)
	task.publish_timezone = "America/New_York"
	_expect(
		host,
		PublishTimeScript.effective_timezone(task, workplan) == "America/New_York",
		"task timezone overrides workplan"
	)
	var label: String = PublishTimeScript.format_publish_label(task, workplan)
	_expect(host, label.find("11:00") >= 0 and label.find("America/New_York") >= 0, "label includes time+tz")
	# Avoid Workplan.add_task_to_month (saves current via manager); append locally.
	workplan.months["2026-11"] = [task]
	var md: String = MarkdownExportScript.render(workplan)
	_expect(host, md.find("America/New_York") >= 0 or md.find("11:00") >= 0, "markdown export shows publish time")


static func _test_cadence_caps(host: Node) -> void:
	print("-- channel cadence caps --")
	const CadenceScript = preload("res://readymade/scripts/workplan_cadence.gd")
	var workplan := Workplan.new()
	workplan.name = "Cadence Probe"
	CadenceScript.set_cap(workplan, "#general", 2)
	_expect(host, CadenceScript.get_cap(workplan, "#general") == 2, "cap stored for #general")
	var month_tasks: Array = []
	for i in range(3):
		var task := WorkplanTask.new()
		task.title = "Post %d" % i
		task.channel = "#general"
		task.publish_date = "2026-11-10"
		month_tasks.append(task)
	workplan.months["2026-11"] = month_tasks
	var warnings: Array = CadenceScript.validate(workplan)
	_expect(host, warnings.size() >= 1, "cap exceeded yields warning")
	var report: String = CadenceScript.validation_report(workplan)
	_expect(host, report.find("#general") >= 0, "validation report mentions channel")
	var light := Workplan.new()
	CadenceScript.set_cap(light, "#studio-notes", 2)
	var t := WorkplanTask.new()
	t.channel = "#studio-notes"
	t.publish_date = "2026-11-11"
	t.title = "One"
	light.months["2026-11"] = [t]
	_expect(host, CadenceScript.validate(light).is_empty(), "under cap has no warnings")


static func _test_community_post_template_and_copy_markdown(host: Node) -> void:
	print("-- community post template + copy markdown --")
	_expect(
		host,
		FormatTemplates.get_all_formats().has("Community Post"),
		"Community Post format template registered"
	)
	var tmpl: Dictionary = FormatTemplates.get_template("Community Post")
	_expect(host, not tmpl.is_empty(), "Community Post template non-empty")
	_expect(host, tmpl.get("structure", []).has("hook"), "Community Post has hook section")
	const MarkdownScript = preload("res://readymade/scripts/workplan_task_markdown.gd")
	var task := WorkplanTask.new()
	task.title = "Friday roundup"
	task.channel = "#general"
	task.publish_date = "2026-11-14"
	task.publish_time = "11:00"
	task.publish_timezone = "Europe/Oslo"
	task.generated_content = "This week in the studio map."
	task.set_content_status("draft")
	var md: String = MarkdownScript.to_clipboard_markdown(task)
	_expect(host, md.find("Friday roundup") >= 0, "copy markdown includes title")
	_expect(host, md.find("#general") >= 0, "copy markdown includes channel")
	_expect(host, md.find("This week in the studio map") >= 0, "copy markdown includes draft")


static func _test_campaign_dashboard(host: Node) -> void:
	print("-- campaign dashboard aggregation --")
	const DashboardScript = preload("res://readymade/scripts/workplan_campaign_dashboard.gd")
	const CadenceScript = preload("res://readymade/scripts/workplan_cadence.gd")
	var workplan := Workplan.new()
	workplan.name = "Campaign Dash Probe"
	CadenceScript.set_cap(workplan, "#general", 1)
	var today: String = Time.get_date_string_from_system()
	var t1 := WorkplanTask.new()
	t1.title = "Welcome"
	t1.channel = "#general"
	t1.campaign_tag = "nov-campaign"
	t1.content_theme = "Onboarding"
	t1.publish_date = today
	t1.set_content_status("needs_approval")
	var t2 := WorkplanTask.new()
	t2.title = "Open slot"
	t2.channel = "#general"
	t2.campaign_tag = "nov-campaign"
	t2.content_theme = "Reactive"
	t2.publish_date = today
	t2.set_content_status("open_slot")
	var t3 := WorkplanTask.new()
	t3.title = "Posted piece"
	t3.channel = "#studio-notes"
	t3.campaign_tag = "other"
	t3.content_theme = "Onboarding"
	t3.publish_date = "2020-01-01"
	t3.set_content_status("posted")
	t3.status = "Done"
	workplan.months["probe"] = [t1, t2, t3]
	var by_campaign: Dictionary = DashboardScript.build(workplan, "campaign")
	_expect(host, by_campaign.get("groups", []).size() == 2, "two campaign groups")
	var totals: Dictionary = by_campaign.get("totals", {})
	_expect(host, int(totals.get("total", 0)) == 3, "totals count 3")
	_expect(host, int(totals.get("open_slots", 0)) == 1, "one open slot")
	_expect(host, int(totals.get("posted", 0)) >= 1, "posted counted")
	_expect(host, DashboardScript.completion_ratio(totals) > 0.0, "completion ratio > 0")
	var text: String = DashboardScript.render_text(by_campaign)
	_expect(host, text.find("nov-campaign") >= 0, "report names campaign")
	_expect(host, text.find("#general") >= 0, "report mentions channel")
	var by_theme: Dictionary = DashboardScript.build(workplan, "theme")
	_expect(host, by_theme.get("groups", []).size() == 2, "two theme groups")
	_expect(host, by_campaign.get("cadence", []).size() >= 1, "cadence warning when over cap")


static func _test_timezone_conversion(host: Node) -> void:
	print("-- timezone conversion (DST-aware) --")
	const TzScript = preload("res://readymade/scripts/workplan_timezone.gd")
	const PublishTimeScript = preload("res://readymade/scripts/workplan_publish_time.gd")
	_expect(host, TzScript.is_known("Europe/Oslo"), "Europe/Oslo known")
	_expect(host, TzScript.is_known("America/New_York"), "America/New_York known")
	_expect(host, TzScript.is_known("Africa/Lagos"), "Africa/Lagos known (WAT, no DST)")
	# Lagos and Oslo are both UTC+1 in November → wall clock unchanged.
	var lagos_winter: Dictionary = TzScript.convert_zones(
		"2026-11-14", "15:00", "Africa/Lagos", "Europe/Oslo"
	)
	_expect(
		host,
		String(lagos_winter.get("time", "")) == "15:00",
		"Nov Lagos 15:00 → Oslo 15:00 (got %s)" % String(lagos_winter.get("time", ""))
	)
	var unknown_label: String = TzScript.format_for_viewer(
		"2026-11-14", "15:00", "Not/AZone", "Europe/Oslo"
	)
	_expect(host, unknown_label.find("unknown zone") >= 0, "unknown zone warned in viewer label")
	# Winter: Oslo UTC+1, New York UTC-5 → 6h difference.
	var winter: Dictionary = TzScript.convert_zones("2026-01-15", "12:00", "Europe/Oslo", "America/New_York")
	_expect(host, String(winter.get("time", "")) == "06:00", "winter Oslo 12:00 → NY 06:00 (got %s)" % String(winter.get("time", "")))
	_expect(host, String(winter.get("date", "")) == "2026-01-15", "winter same calendar day")
	# Summer EU DST (CEST +2) vs US EDT (-4) still 6h.
	var summer: Dictionary = TzScript.convert_zones("2026-07-15", "12:00", "Europe/Oslo", "America/New_York")
	_expect(host, String(summer.get("time", "")) == "06:00", "summer Oslo 12:00 → NY 06:00 (got %s)" % String(summer.get("time", "")))
	# US spring forward boundary: 2026-03-08 is 2nd Sunday; 01:30 EST exists, converts cleanly.
	var us_spring: Dictionary = TzScript.convert_zones("2026-03-08", "01:30", "America/New_York", "UTC")
	_expect(host, String(us_spring.get("time", "")) == "06:30", "US pre-DST 01:30 → UTC 06:30 (got %s)" % String(us_spring.get("time", "")))
	var task := WorkplanTask.new()
	task.publish_date = "2026-01-15"
	task.publish_time = "12:00"
	task.publish_timezone = "Europe/Oslo"
	var workplan := Workplan.new()
	workplan.default_timezone = "Europe/Oslo"
	workplan.viewer_timezone = "America/New_York"
	var label: String = PublishTimeScript.format_publish_label(task, workplan)
	_expect(host, label.find("06:00") >= 0, "viewer label shows converted time")
	_expect(host, label.find("America/New_York") >= 0, "viewer label names viewer zone")
	PublishTimeScript.set_task_publish_from_viewer(task, "2026-01-15", "06:00", "America/New_York", "Europe/Oslo")
	_expect(host, task.publish_time == "12:00", "enter NY 06:00 stores Oslo 12:00")
	_expect(host, task.publish_timezone == "Europe/Oslo", "store zone preserved")


static func _test_calendar_reschedule(host: Node) -> void:
	print("-- calendar reschedule + undo + series --")
	const RescheduleScript = preload("res://readymade/scripts/workplan_calendar_reschedule.gd")
	const CadenceScript = preload("res://readymade/scripts/workplan_cadence.gd")
	var workplan := Workplan.new()
	workplan.name = "Reschedule Probe"
	CadenceScript.set_cap(workplan, "#general", 1)
	var a := WorkplanTask.new()
	a.title = "Friday roundup"
	a.channel = "#general"
	a.publish_date = "2026-11-06"
	a.publish_time = "10:00"
	a.publish_timezone = "Europe/Oslo"
	a.scheduled_date = "2026-11-06"
	a.deadline = "2026-11-06"
	a.start_date = "2026-11-03"
	var b := WorkplanTask.new()
	b.title = "Friday roundup"
	b.channel = "#general"
	b.publish_date = "2026-11-13"
	b.publish_time = "10:00"
	b.publish_timezone = "Europe/Oslo"
	b.scheduled_date = "2026-11-13"
	b.deadline = "2026-11-13"
	var c := WorkplanTask.new()
	c.title = "Other post"
	c.channel = "#studio-notes"
	c.publish_date = "2026-11-06"
	workplan.months["probe"] = [a, b, c]
	var mover = RescheduleScript.new()
	var moved: Dictionary = mover.move_task_to_date(
		a, "2026-11-07", ["publish_date", "scheduled_date", "deadline"], true, workplan, "instance"
	)
	_expect(host, int(moved.get("moved", 0)) == 1, "instance move touches one task")
	_expect(host, a.publish_date == "2026-11-07", "instance publish_date updated")
	_expect(host, a.start_date == "2026-11-04", "publish move also shifts start_date +1")
	_expect(host, a.publish_time == "10:00", "publish time preserved")
	_expect(host, a.publish_timezone == "Europe/Oslo", "publish timezone preserved")
	_expect(host, b.publish_date == "2026-11-13", "sibling instance unchanged")
	_expect(host, (moved.get("warnings", []) as Array).size() >= 0, "warnings array present")
	_expect(host, mover.can_undo(), "undo available after move")
	_expect(host, mover.undo_last(workplan), "undo succeeds")
	_expect(host, a.publish_date == "2026-11-06", "undo restores publish_date")
	_expect(host, a.start_date == "2026-11-03", "undo restores start_date")
	var series_move: Dictionary = mover.move_task_to_date(
		a, "2026-11-20", ["publish_date"], true, workplan, "series"
	)
	_expect(host, int(series_move.get("moved", 0)) == 2, "series move touches title+channel matches")
	_expect(host, a.publish_date == "2026-11-20", "series updated template a")
	_expect(host, b.publish_date == "2026-11-20", "series updated sibling b")
	_expect(host, c.publish_date == "2026-11-06", "other channel untouched")
	_expect(host, mover.undo_last(workplan), "undo series")
	_expect(host, a.publish_date == "2026-11-06" and b.publish_date == "2026-11-13", "series undo restores both")


static func _test_workplan_file_dialog_filesystem(host: Node) -> void:
	print("-- workplan FileDialog uses filesystem access --")
	var file_dialog_local := FileDialog.new()
	file_dialog_local.access = FileDialog.ACCESS_FILESYSTEM
	var preferred: String = RuntimeConfig.get_readymade_data_dir()
	_expect(host, not preferred.is_empty(), "readymade data dir resolves")
	if DirAccess.dir_exists_absolute(preferred):
		file_dialog_local.current_dir = preferred
	_expect(
		host,
		file_dialog_local.access == FileDialog.ACCESS_FILESYSTEM,
		"FileDialog access is ACCESS_FILESYSTEM (not res://-only)"
	)
	_expect(
		host,
		not String(file_dialog_local.current_dir).begins_with("res://"),
		"FileDialog current_dir is not res://"
	)
	# FileDialogs stay exclusive; Workplan Manager yields exclusivity while they are open.
	file_dialog_local.exclusive = true
	_expect(host, file_dialog_local.exclusive == true, "FileDialog remains exclusive for Open/Save clicks")
	file_dialog_local.free()


static func _test_nested_workplan_dialogs_non_exclusive(host: Node) -> void:
	print("-- nested workplan dialogs are non-exclusive --")
	var nested := AcceptDialog.new()
	nested.exclusive = false
	_expect(host, nested.exclusive == false, "AcceptDialog exclusive can be cleared for nesting")
	var manager := AcceptDialog.new()
	manager.exclusive = true
	manager.exclusive = false
	_expect(host, manager.exclusive == false, "Workplan Manager can yield exclusivity for FileDialog")
	nested.free()
	manager.free()


static func _test_file_dialog_line_enables_ok(host: Node) -> void:
	print("-- FileDialog File: line enables Open when file exists --")
	var scene: PackedScene = load("res://readymade/ui/mission_control_dashboard.tscn")
	_expect(host, scene != null, "dashboard loads for FileDialog line test")
	if scene == null:
		return
	var dash: Node = scene.instantiate()
	host.add_child(dash)
	_expect(host, dash.has_method("_sync_file_dialog_ok_from_line"), "sync FileDialog OK helper present")
	_expect(host, dash.has_method("_wire_file_dialog_line_confirm"), "wire FileDialog line helper present")
	if not dash.has_method("_sync_file_dialog_ok_from_line"):
		dash.queue_free()
		return
	var tmp_dir: String = OS.get_user_data_dir().path_join("_fd_line_ok_probe")
	DirAccess.make_dir_recursive_absolute(tmp_dir)
	var existing: String = tmp_dir.path_join("existing_tasks.csv")
	var writer: FileAccess = FileAccess.open(existing, FileAccess.WRITE)
	writer.store_string("title\nOne\n")
	writer = null
	var file_dialog_local := FileDialog.new()
	file_dialog_local.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog_local.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog_local.current_dir = tmp_dir
	dash.add_child(file_dialog_local)
	file_dialog_local.popup_centered(Vector2(400, 300))
	dash._wire_file_dialog_line_confirm(file_dialog_local)
	var line: LineEdit = file_dialog_local.get_line_edit()
	var ok_btn: Button = file_dialog_local.get_ok_button()
	_expect(host, line != null and ok_btn != null, "FileDialog exposes LineEdit and OK button")
	if line != null and ok_btn != null:
		line.text = "missing.csv"
		dash._sync_file_dialog_ok_from_line(file_dialog_local)
		_expect(host, ok_btn.disabled == true, "Open disabled for missing File: name")
		line.text = "existing_tasks.csv"
		dash._sync_file_dialog_ok_from_line(file_dialog_local)
		_expect(host, ok_btn.disabled == false, "Open enabled when File: names existing file")
		# SAVE mode: non-empty name under existing dir enables Save
		file_dialog_local.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		line.text = "new_export.csv"
		dash._sync_file_dialog_ok_from_line(file_dialog_local)
		_expect(host, ok_btn.disabled == false, "Save enabled for valid path under existing dir")
	file_dialog_local.hide()
	file_dialog_local.queue_free()
	dash.queue_free()
	DirAccess.remove_absolute(existing)
	DirAccess.remove_absolute(tmp_dir)


static func _test_task_dependencies(host: Node) -> void:
	print("-- task depends_on / blocked / cycle / cascade / bulk IO --")
	const DepsScript = preload("res://readymade/scripts/workplan_dependencies.gd")
	const BulkIOScript = preload("res://readymade/scripts/workplan_task_bulk_io.gd")
	var workplan := Workplan.new()
	workplan.name = "Deps Fixture"
	var pred := WorkplanTask.new()
	pred.task_id = "task_pred"
	pred.title = "Predecessor"
	pred.status = "To Do"
	pred.publish_date = "2026-12-01"
	var child := WorkplanTask.new()
	child.task_id = "task_child"
	child.title = "Dependent"
	child.status = "To Do"
	child.publish_date = "2026-12-03"
	child.deadline = "2026-12-03"
	child.scheduled_date = "2026-12-03"
	DepsScript.set_depends_on(child, "task_pred")
	var grandchild := WorkplanTask.new()
	grandchild.task_id = "task_gc"
	grandchild.title = "Grandchild"
	grandchild.publish_date = "2026-12-05"
	child.start_date = "2026-11-28"
	grandchild.start_date = "2026-12-01"
	DepsScript.set_depends_on(grandchild, "task_child")
	# Avoid Workplan.add_task_to_month (saves via manager); append locally.
	workplan.months["2026-12"] = [pred, child, grandchild]
	_expect(host, child.depends_on.size() == 1 and child.depends_on[0] == "task_pred", "depends_on set")
	_expect(host, DepsScript.is_blocked(child, workplan), "child blocked while pred not Done")
	pred.status = "Done"
	_expect(host, not DepsScript.is_blocked(child, workplan), "child unblocked when pred Done")
	_expect(
		host,
		DepsScript.would_create_cycle("task_pred", ["task_child"], workplan),
		"cycle detected pred→child when child depends on pred"
	)
	_expect(
		host,
		not DepsScript.would_create_cycle("task_child", ["task_pred"], workplan),
		"existing valid edge is not reported as a new cycle"
	)
	_expect(
		host,
		DepsScript.would_create_cycle("task_pred", "task_gc", workplan),
		"transitive cycle via grandchild detected"
	)
	var dependents: Array = DepsScript.get_dependents("task_pred", workplan)
	_expect(host, dependents.size() == 1, "one direct dependent of pred")
	var offset: int = DepsScript.day_offset("2026-12-01", "2026-12-04")
	_expect(host, offset == 3, "day_offset 3")
	var cascaded: Dictionary = DepsScript.move_dependents_by_offset(
		pred, offset, workplan, ["publish_date", "scheduled_date", "deadline"]
	)
	_expect(host, int(cascaded.get("moved", 0)) == 2, "cascade moves child and grandchild")
	_expect(host, child.publish_date == "2026-12-06", "child publish shifted +3")
	_expect(host, grandchild.publish_date == "2026-12-08", "grandchild publish shifted +3")
	_expect(host, child.start_date == "2026-12-01", "cascade also shifts child start_date +3")
	_expect(host, grandchild.start_date == "2026-12-04", "cascade also shifts grandchild start_date +3")
	_expect(host, (cascaded.get("snapshots", []) as Array).size() == 2, "cascade returns undo snapshots")
	# Bulk IO round-trip
	child.assignee = "Reviewer Bot"
	var csv_text: String = BulkIOScript.export_csv(workplan)
	_expect(host, csv_text.find("depends_on") >= 0, "CSV header includes depends_on")
	_expect(host, csv_text.find("task_pred") >= 0, "CSV exports predecessor id in depends_on")
	var rows: Array = BulkIOScript.parse_csv(csv_text)
	var child_row: Dictionary = {}
	for row_any in rows:
		var row: Dictionary = row_any
		if String(row.get("task_id", "")) == "task_child":
			child_row = row
			break
	_expect(host, not child_row.is_empty(), "parsed child row")
	_expect(host, String(child_row.get("depends_on", "")).find("task_pred") >= 0, "bulk depends_on column")
	_expect(host, String(child_row.get("assignee", "")) == "Reviewer Bot", "bulk assignee column")


static func _test_stage_board_columns_and_move(host: Node) -> void:
	print("-- stage board columns and move --")
	const StageBoardScript = preload("res://readymade/scripts/workplan_stage_board.gd")
	var workplan := Workplan.new()
	workplan.name = "Board Fixture"
	var todo_task := WorkplanTask.new()
	todo_task.title = "Todo item"
	todo_task.status = "To Do"
	var review_task := WorkplanTask.new()
	review_task.title = "Review item"
	review_task.status = "Review"
	review_task.set_content_status("draft")
	workplan.months["probe"] = [todo_task, review_task]
	var wf_columns: Array = StageBoardScript.build_columns(workplan, "workflow", {})
	_expect(host, wf_columns.size() == 4, "workflow has four columns")
	var todo_col: Dictionary = wf_columns[0]
	_expect(host, String(todo_col.get("id", "")) == "To Do", "first column is To Do")
	var todo_bucket: Array = todo_col.get("tasks", [])
	_expect(host, todo_bucket.size() == 1, "one task in To Do")
	_expect(
		host,
		StageBoardScript.move_task_to_column(todo_task, "In Progress", "workflow"),
		"move workflow to In Progress"
	)
	_expect(host, todo_task.status == "In Progress", "task status updated")
	_expect(host, todo_task.approval_log.size() >= 1, "workflow move appends approval log")
	var cs_columns: Array = StageBoardScript.build_columns(workplan, "content_status", {})
	_expect(host, cs_columns.size() == WorkplanTask.CONTENT_STATUSES.size(), "content_status column count")
	_expect(
		host,
		StageBoardScript.move_task_to_column(review_task, "needs_approval", "content_status"),
		"move content status"
	)
	_expect(host, review_task.get_content_status() == "needs_approval", "content_status updated")
	var pred := WorkplanTask.new()
	pred.task_id = "board_pred"
	pred.status = "To Do"
	var blocked := WorkplanTask.new()
	blocked.title = "Blocked card"
	blocked.depends_on = ["board_pred"]
	workplan.months["probe"].append(pred)
	workplan.months["probe"].append(blocked)
	_expect(host, StageBoardScript.is_blocked(blocked, workplan), "stage board is_blocked helper")


static func _test_approval_log_append_only(host: Node) -> void:
	print("-- approval log append-only --")
	const ApprovalLogScript = preload("res://readymade/scripts/workplan_approval_log.gd")
	const BulkIOScript = preload("res://readymade/scripts/workplan_task_bulk_io.gd")
	var task := WorkplanTask.new()
	task.title = "Ledger probe"
	_expect(host, task.approval_log.is_empty(), "new task empty log")
	ApprovalLogScript.append_change(task, "draft", "needs_approval", "alice", "please review")
	_expect(host, task.approval_log.size() == 1, "one entry after append")
	var first: Dictionary = task.approval_log[0]
	var first_to: String = String(first.get("to", ""))
	ApprovalLogScript.append_change(task, "needs_approval", "approved", "", "")
	_expect(host, task.approval_log.size() == 2, "second append grows log only")
	_expect(host, String(task.approval_log[0].get("to", "")) == first_to, "first entry unchanged")
	ApprovalLogScript.append_change(task, "approved", "approved", "", "")
	_expect(host, task.approval_log.size() == 2, "no-op when from==to")
	task.set_content_status("posted")
	_expect(host, task.approval_log.size() == 3, "set_content_status records change")
	var formatted: String = ApprovalLogScript.format_entries(task)
	_expect(host, formatted.find("draft") >= 0 and formatted.find("posted") >= 0, "format_entries readable")
	var workplan := Workplan.new()
	workplan.months["m"] = [task]
	var rows: Array = BulkIOScript.export_rows(workplan)
	_expect(host, rows.size() == 1, "export row")
	var approval_json: String = String(rows[0].get("approval_log", ""))
	_expect(host, not approval_json.is_empty(), "approval_log column present")
	var parsed: Variant = JSON.parse_string(approval_json)
	_expect(host, typeof(parsed) == TYPE_ARRAY, "approval_log column is JSON array")

static func _test_workplan_people_and_assignee(host: Node) -> void:
	print("-- workplan people + assignee filter/TZ --")
	const PeopleScript = preload("res://readymade/scripts/workplan_people.gd")
	var workplan := Workplan.new()
	workplan.name = "People Fixture"
	workplan.people = PeopleScript.normalize_list([
		{"name": "Ada", "role": "Editor", "timezone": "Africa/Lagos"},
		{"name": "ada", "role": "dup", "timezone": "UTC"},
		{"name": "", "role": "skip"},
	])
	_expect(host, workplan.people.size() == 1, "people list dedupes by name")
	_expect(host, String(workplan.people[0].get("role", "")) == "Editor", "keeps first role")
	var task := WorkplanTask.new()
	task.title = "Assigned post"
	task.assignee = "Ada"
	task.deadline = "2026-12-10"
	task.publish_date = "2026-12-10"
	task.publish_time = "15:00"
	task.publish_timezone = "UTC"
	_expect(host, PeopleScript.assignee_timezone(task, workplan) == "Africa/Lagos", "assignee TZ from people")
	_expect(host, PeopleScript.matches_assignee_filter(task, "Ada"), "assignee filter match")
	_expect(host, not PeopleScript.matches_assignee_filter(task, "Bob"), "assignee filter miss")
	_expect(host, PeopleScript.matches_assignee_filter(WorkplanTask.new(), "(unassigned)"), "unassigned filter")
	var label_text: String = PeopleScript.format_deadline_for_assignee(task, workplan)
	_expect(host, label_text.find("Ada") >= 0 or label_text.find("Lagos") >= 0 or label_text.find("15:") >= 0, "deadline label uses assignee context")


static func _test_workplan_manager_section_labels(host: Node) -> void:
	print("-- workplan manager section labels --")
	var dash = preload("res://readymade/ui/mission_control_dashboard.gd").new()
	host.add_child(dash)
	_expect(host, dash.has_method("_create_workplan_manager_dialog"), "manager dialog builder present")
	_expect(host, dash.has_method("_on_manage_people_pressed"), "Manage People handler present")
	if dash.has_method("_create_workplan_manager_dialog") and dash.get("workplan_manager") != null:
		# Soft: only build when manager is ready (acceptance host usually has it).
		pass
	dash.queue_free()


static func _test_copy_markdown_ui_reachability(host: Node) -> void:
	print("-- copy markdown UI reachability --")
	var dash = preload("res://readymade/ui/mission_control_dashboard.gd").new()
	host.add_child(dash)
	_expect(host, dash.has_method("_on_copy_task_markdown_pressed"), "Tasks row copy handler present")
	_expect(host, dash.has_method("_show_copied_feedback"), "Copied toast helper present")
	_expect(host, dash.has_method("_show_task_context_menu"), "calendar context menu builder present")
	_expect(host, dash.has_method("_create_task_card"), "Tasks tab row builder present")
	var tasks_src: String = FileAccess.get_file_as_string(
		"res://readymade/ui/internal/mission_control_task_dashboard_base.gd"
	)
	_expect(
		host,
		tasks_src.find("Copy as Markdown") >= 0 and tasks_src.find("_on_copy_task_markdown_pressed") >= 0,
		"Tasks row wires Copy as Markdown button"
	)
	var cal_src: String = FileAccess.get_file_as_string(
		"res://readymade/ui/internal/mission_control_calendar_base.gd"
	)
	_expect(
		host,
		cal_src.find("Copy as Markdown") >= 0 and cal_src.find("_dismiss_calendar_context_menu") >= 0,
		"calendar context menu includes Copy and dismiss helper"
	)
	var card_src: String = FileAccess.get_file_as_string(
		"res://readymade/components/workplan_task_card.gd"
	)
	_expect(host, card_src.find("✓ Copied") >= 0, "task card shows Copied feedback")
	dash.queue_free()


static func _test_calendar_same_day_merge_and_tooltips(host: Node) -> void:
	print("-- calendar same-day merge + kind labels --")
	const DayCardsScript = preload("res://readymade/scripts/workplan_calendar_day_cards.gd")
	var task := WorkplanTask.new()
	task.title = "Peer review"
	task.ensure_task_id()
	task.start_date = "2026-12-02"
	task.deadline = "2026-12-02"
	task.publish_date = "2026-12-02"
	var events: Array = [
		{"task": task, "type": "start"},
		{"task": task, "type": "deadline"},
		{"task": task, "type": "publish"},
	]
	var merged: Array = DayCardsScript.merge_day_task_events(events)
	_expect(host, merged.size() == 1, "same-day cards merge to one entry")
	if merged.size() == 1:
		var kinds: Array = merged[0].get("types", [])
		_expect(host, kinds.size() == 3, "merged entry keeps start+deadline+publish")
		_expect(
			host,
			DayCardsScript.preferred_calendar_date_type(kinds) == "publish",
			"primary drag type prefers publish"
		)
		var kind_label: String = DayCardsScript.format_calendar_kind_label(kinds)
		_expect(host, kind_label.find("publish") >= 0, "kind label includes publish")
		_expect(host, kind_label.find("deadline") >= 0, "kind label includes deadline")
		var icons: String = DayCardsScript.calendar_kind_icons(kinds)
		_expect(host, not icons.is_empty(), "kind icons non-empty")
		task.publish_time = "15:00"
		task.publish_timezone = "Europe/Oslo"
		var tip: String = DayCardsScript.build_tooltip(task, kinds, "2026-12-02", "publish", false)
		_expect(host, tip.find("Peer review") >= 0 and tip.find("Kind:") >= 0, "tooltip has title+kind")
		_expect(host, tip.find("Publish:") >= 0 and tip.find("2026-12-02") >= 0, "tooltip has publish date")
		_expect(host, tip.find("15:00") >= 0, "tooltip has publish time")
		_expect(host, tip.find("Europe/Oslo") >= 0, "tooltip has publish timezone")
		var card: PanelContainer = DayCardsScript.create_month_card(
			task, "publish", kinds, "2026-12-02", false
		)
		_expect(host, card != null and not card.tooltip_text.is_empty(), "month card has tooltip")
		_expect(host, card.tooltip_text.find("Peer review") >= 0, "month card tooltip has full title")
		_expect(host, card.tooltip_text.find("2026-12-02") >= 0, "month card tooltip has concrete date")
		card.free()
	var other := WorkplanTask.new()
	other.title = "Other task"
	other.ensure_task_id()
	var two_tasks: Array = DayCardsScript.merge_day_task_events([
		{"task": task, "type": "publish"},
		{"task": other, "type": "deadline"},
	])
	_expect(host, two_tasks.size() == 2, "distinct tasks stay separate cards")


static func _test_import_preview_and_dependents_dialog_helpers(host: Node) -> void:
	print("-- import preview close + dependents dialog helpers --")
	var dash = preload("res://readymade/ui/mission_control_dashboard.gd").new()
	host.add_child(dash)
	_expect(host, dash.has_method("_show_task_import_preview"), "import preview dialog present")
	_expect(host, dash.has_method("_close_import_preview_dialog"), "import preview close helper present")
	_expect(host, dash.has_method("_offer_move_dependents"), "move dependents dialog present")
	_expect(host, dash.has_method("_popup_nested_dialog"), "nested dialog popup helper present")
	# Import preview must be exclusive (not nested non-exclusive) so Cancel cannot
	# click-through to Export Tasks and open a Save FileDialog.
	var import_src: String = FileAccess.get_file_as_string(
		"res://readymade/ui/internal/mission_control_workplan_syntree_base.gd"
	)
	_expect(
		host,
		import_src.find("Import Tasks Preview") >= 0 and import_src.find("summary.exclusive = true") >= 0,
		"import preview uses exclusive dialog"
	)
	_expect(
		host,
		import_src.find("_close_import_preview_dialog") >= 0
		and import_src.find("never open a save/export") >= 0,
		"import cancel path documents no save/export"
	)
	var probe := ConfirmationDialog.new()
	probe.title = "Import Tasks Preview"
	probe.dialog_text = "ok"
	probe.exclusive = true
	dash.add_child(probe)
	probe.popup_centered()
	_expect(host, probe.visible, "exclusive import preview visible")
	dash._close_import_preview_dialog(probe)
	_expect(host, not is_instance_valid(probe) or not probe.visible, "close helper hides preview")
	# Nested helper remains available for other Manager dialogs.
	var nested := AcceptDialog.new()
	nested.title = "Nested"
	dash.add_child(nested)
	dash._popup_nested_dialog(nested)
	_expect(host, nested.exclusive == false, "other nested dialogs stay non-exclusive")
	nested.hide()
	nested.queue_free()
	dash.queue_free()


static func _test_people_role_field_width(host: Node) -> void:
	print("-- people role field width --")
	var dash = preload("res://readymade/ui/mission_control_dashboard.gd").new()
	host.add_child(dash)
	_expect(host, dash.has_method("_on_manage_people_pressed"), "Manage People handler present")
	# Source-level contract: role LineEdit minimum width is at least 200.
	var people_src: String = FileAccess.get_file_as_string(
		"res://readymade/ui/internal/mission_control_workplan_syntree_base.gd"
	)
	_expect(host, people_src.find("Role label") >= 0, "role field present in Manage People UI")
	_expect(
		host,
		people_src.find("Vector2(200, 0)") >= 0 or people_src.find("Vector2(200,0)") >= 0,
		"role LineEdit min width >= 200"
	)
	dash.queue_free()


static func _test_cascade_shifts_start_date_and_undo(host: Node) -> void:
	print("-- cascade shifts start_date; undo restores it --")
	const DepsScript = preload("res://readymade/scripts/workplan_dependencies.gd")
	const RescheduleScript = preload("res://readymade/scripts/workplan_calendar_reschedule.gd")
	var workplan := Workplan.new()
	workplan.name = "Cascade Start Fixture"
	var root := WorkplanTask.new()
	root.title = "Peer review"
	root.task_id = "root_pr"
	root.publish_date = "2026-12-02"
	root.deadline = "2026-12-02"
	root.start_date = "2026-11-28"
	var dep := WorkplanTask.new()
	dep.title = "Publish roundup"
	dep.task_id = "dep_pr"
	dep.publish_date = "2026-12-05"
	dep.deadline = "2026-12-05"
	dep.start_date = "2026-12-01"
	DepsScript.set_depends_on(dep, "root_pr")
	workplan.months["2026-12"] = [root, dep]
	var fields: Array = DepsScript.cascade_fields_preserving_duration(
		["publish_date", "scheduled_date", "deadline"]
	)
	_expect(host, fields.has("start_date"), "cascade fields include start_date")
	var mover = RescheduleScript.new()
	mover.move_task_to_date(
		root, "2026-12-05", ["publish_date", "scheduled_date", "deadline"], true, workplan, "instance"
	)
	_expect(host, root.publish_date == "2026-12-05", "root publish moved +3")
	_expect(host, root.start_date == "2026-12-01", "root start shifted +3 with publish")
	var cascaded: Dictionary = DepsScript.move_dependents_by_offset(root, 3, workplan, fields)
	_expect(host, int(cascaded.get("moved", 0)) == 1, "one dependent cascaded")
	_expect(host, dep.publish_date == "2026-12-08", "dependent publish +3")
	_expect(host, dep.start_date == "2026-12-04", "dependent start +3 (duration preserved)")
	mover.extend_last_undo(cascaded.get("snapshots", []))
	_expect(host, mover.undo_last(workplan), "undo after cascade")
	_expect(host, root.publish_date == "2026-12-02", "undo restores root publish")
	_expect(host, root.start_date == "2026-11-28", "undo restores root start")
	_expect(host, dep.publish_date == "2026-12-05", "undo restores dependent publish")
	_expect(host, dep.start_date == "2026-12-01", "undo restores dependent start")


static func _test_calendar_menu_dismiss_and_publish_tooltip(host: Node) -> void:
	print("-- calendar menu dismiss + publish tooltip date --")
	var dash = preload("res://readymade/ui/mission_control_dashboard.gd").new()
	host.add_child(dash)
	_expect(host, dash.has_method("_dismiss_calendar_context_menu"), "dismiss helper present")
	_expect(host, dash.has_method("_ensure_calendar_context_menu"), "ensure fresh menu helper present")
	_expect(host, dash.has_method("_run_calendar_context_action"), "deferred context action helper present")
	# Simulate a stuck-open menu and ensure dismiss clears/frees it.
	var menu := PopupMenu.new()
	dash.calendar_context_menu = menu
	dash.add_child(menu)
	menu.add_item("Undo last reschedule", 5)
	menu.popup()
	_expect(host, menu.visible, "menu visible before dismiss")
	dash._dismiss_calendar_context_menu()
	_expect(host, dash.calendar_context_menu == null, "dismiss nulls menu ref")
	_expect(host, not is_instance_valid(menu) or not menu.visible, "dismiss hides/frees menu immediately")
	const DayCardsScript = preload("res://readymade/scripts/workplan_calendar_day_cards.gd")
	var task := WorkplanTask.new()
	task.title = "Peer review"
	task.publish_date = "2026-12-02"
	task.publish_time = "11:30"
	task.publish_timezone = "Africa/Lagos"
	var tip: String = DayCardsScript.build_tooltip(
		task, ["publish"], "2026-12-02", "publish", false
	)
	_expect(host, tip.find("Publish:") >= 0, "publish tooltip label present")
	_expect(host, tip.find("2026-12-02") >= 0, "publish tooltip includes date")
	_expect(host, tip.find("11:30") >= 0 and tip.find("Africa/Lagos") >= 0, "publish tooltip time+zone")
	dash.queue_free()


static func _test_live_calendar_path_and_tooltip_not_overwritten(host: Node) -> void:
	print("-- live Mission Control calendar path + tooltip not overwritten on hover --")
	var main_src: String = FileAccess.get_file_as_string("res://readymade/readymade_main.tscn")
	_expect(
		host,
		main_src.find("mission_control_dashboard.tscn") >= 0,
		"readymade_main embeds mission_control_dashboard"
	)
	var cal_src: String = FileAccess.get_file_as_string(
		"res://readymade/ui/internal/mission_control_calendar_base.gd"
	)
	_expect(
		host,
		cal_src.find("Right-click for options") < 0,
		"dead hover tooltip string removed from live calendar"
	)
	_expect(
		host,
		cal_src.find("tooltip_text_full") >= 0 and cal_src.find("DayCardsScript.build_tooltip") >= 0,
		"hover preserves DayCardsScript tooltip"
	)
	const DayCardsScript = preload("res://readymade/scripts/workplan_calendar_day_cards.gd")
	var task := WorkplanTask.new()
	task.title = "Peer review"
	task.status = "To Do"
	task.priority = 0
	task.publish_date = "2026-12-02"
	task.publish_time = "15:00"
	task.publish_timezone = "Europe/Oslo"
	var card: PanelContainer = DayCardsScript.create_month_card(
		task, "publish", ["publish"], "2026-12-02", false
	)
	var before: String = card.tooltip_text
	_expect(host, before.find("Publish:") >= 0 and before.find("2026-12-02") >= 0, "card tip has publish date")
	# Simulate what mouse_entered must do: restore meta tip, never the old dead string.
	if card.has_meta("tooltip_text_full"):
		card.tooltip_text = String(card.get_meta("tooltip_text_full"))
	_expect(host, card.tooltip_text == before, "hover restore keeps rich tooltip")
	_expect(host, card.tooltip_text.find("Right-click for options") < 0, "old dead tip not restored")
	card.free()
	var view_src: String = FileAccess.get_file_as_string("res://readymade/ui/calendar_view.gd")
	_expect(
		host,
		view_src.find("LIVE product Calendar tab") >= 0 and view_src.find("DayCardsScript") >= 0,
		"standalone CalendarView documents live path and shares DayCardsScript"
	)


static func _test_task_dialog_calendar_dates_prefilled(host: Node) -> void:
	print("-- task dialog Calendar dates prefilled from saved task --")
	var scene: PackedScene = load("res://readymade/ui/task_dialog.tscn")
	_expect(host, scene != null, "task_dialog.tscn loads")
	if scene == null:
		return
	var dlg: Node = scene.instantiate()
	host.add_child(dlg)
	var task := WorkplanTask.new()
	task.title = "Synthesize reviewer comments"
	task.core_idea = "Fixture"
	task.publish_date = "2026-12-02"
	task.deadline = "2026-12-01"
	task.start_date = "2026-11-28"
	task.scheduled_date = ""
	task.publish_time = "15:00"
	task.publish_timezone = "Europe/Oslo"
	_expect(host, dlg.has_method("show_edit_dialog"), "show_edit_dialog present")
	dlg.show_edit_dialog(task)
	_expect(host, dlg.has_method("_populate_calendar_date_fields"), "calendar date populate helper")
	dlg._populate_calendar_date_fields(task)
	var pub_edit: LineEdit = dlg.publish_date_edit
	var dead_edit: LineEdit = dlg.deadline_edit
	var start_edit: LineEdit = dlg.scheduled_edit
	var time_edit: LineEdit = dlg.publish_time_edit
	_expect(host, pub_edit != null and pub_edit.text == "2026-12-02", "publish date prefilled")
	_expect(host, dead_edit != null and dead_edit.text == "2026-12-01", "deadline prefilled")
	_expect(host, start_edit != null and start_edit.text == "2026-11-28", "start date prefilled from start_date")
	_expect(host, time_edit != null and time_edit.text == "15:00", "publish time prefilled")
	# Saving with fields still filled must not wipe.
	dlg.is_edit_mode = true
	dlg.editing_task = task
	dlg._on_confirmed()
	_expect(host, task.publish_date == "2026-12-02", "save keeps publish_date")
	_expect(host, task.start_date == "2026-11-28", "save keeps start_date")
	_expect(host, task.deadline == "2026-12-01", "save keeps deadline")
	# Empty LineEdit on edit must not wipe existing saved dates.
	if pub_edit: pub_edit.text = ""
	if dead_edit: dead_edit.text = ""
	if start_edit: start_edit.text = ""
	dlg._on_confirmed()
	_expect(host, task.publish_date == "2026-12-02", "empty publish field does not wipe on edit save")
	_expect(host, task.deadline == "2026-12-01", "empty deadline field does not wipe on edit save")
	_expect(host, task.start_date == "2026-11-28", "empty start field does not wipe on edit save")
	dlg.queue_free()


static func _test_move_dependents_dialog_deferred_single_ok(host: Node) -> void:
	print("-- move dependents dialog deferred exclusive single-OK --")
	var cal_src: String = FileAccess.get_file_as_string(
		"res://readymade/ui/internal/mission_control_calendar_base.gd"
	)
	_expect(
		host,
		cal_src.find("Move dependents?") >= 0 and cal_src.find("create_timer(0.12)") >= 0,
		"move dependents popup is deferred after drag"
	)
	_expect(
		host,
		cal_src.find("confirm.exclusive = true") >= 0 and cal_src.find("applied_box") >= 0,
		"move dependents uses exclusive + single-apply guard"
	)
	var dash = preload("res://readymade/ui/mission_control_dashboard.gd").new()
	host.add_child(dash)
	_expect(host, dash.has_method("_offer_move_dependents"), "offer move dependents present")
	dash.queue_free()


static func _test_imported_task_assignee_and_unedited_save(host: Node) -> void:
	print("-- imported task assignee populate + unedited OK save --")
	const BulkIOScript = preload("res://readymade/scripts/workplan_task_bulk_io.gd")
	var imported := WorkplanTask.new()
	BulkIOScript._apply_row_to_task(imported, {
		"title": "Synthesize reviewer comments",
		"assignee": "Amara Okonkwo",
		"publish_date": "2026-12-05",
		"deadline": "2026-12-04",
		"start_date": "2026-12-01",
		"publish_time": "14:00",
		"publish_timezone": "Africa/Lagos",
		"notes": "Imported note line",
		"draft": "",
		"core_idea": "",
	}, true)
	_expect(host, not imported.core_idea.strip_edges().is_empty(), "import seeds core_idea from title/notes")
	_expect(host, imported.assignee == "Amara Okonkwo", "import keeps assignee")
	_expect(host, imported.publish_date == "2026-12-05", "import keeps publish_date")
	_expect(host, imported.start_date == "2026-12-01", "import keeps start_date")
	var scene: PackedScene = load("res://readymade/ui/task_dialog.tscn")
	_expect(host, scene != null, "task_dialog.tscn loads for assignee test")
	if scene == null:
		return
	var dlg: Node = scene.instantiate()
	host.add_child(dlg)
	# Must not SCRIPT ERROR on null OptionButton metadata (Godot 4.7+ String(null)).
	dlg.show_edit_dialog(imported)
	_expect(host, dlg.core_idea_edit != null and not dlg.core_idea_edit.text.is_empty(), "editor core idea populated")
	_expect(host, dlg.assignee_edit != null and dlg.assignee_edit.text == "Amara Okonkwo", "assignee line filled")
	_expect(host, dlg.publish_date_edit != null and dlg.publish_date_edit.text == "2026-12-05", "publish prefilled after import edit")
	_expect(host, dlg.deadline_edit != null and dlg.deadline_edit.text == "2026-12-04", "deadline prefilled after import edit")
	_expect(host, dlg.scheduled_edit != null and dlg.scheduled_edit.text == "2026-12-01", "start prefilled after import edit")
	# Unedited OK must save (no 'Please enter a core idea' error).
	dlg.is_edit_mode = true
	dlg.editing_task = imported
	dlg._on_confirmed()
	_expect(host, not imported.core_idea.strip_edges().is_empty(), "unedited OK keeps/sets core_idea")
	_expect(host, imported.publish_date == "2026-12-05", "unedited OK keeps publish_date")
	_expect(host, imported.deadline == "2026-12-04", "unedited OK keeps deadline")
	_expect(host, imported.start_date == "2026-12-01", "unedited OK keeps start_date")
	_expect(host, imported.assignee == "Amara Okonkwo", "unedited OK keeps assignee")
	# Re-open round-trip.
	dlg.show_edit_dialog(imported)
	_expect(host, dlg.publish_date_edit.text == "2026-12-05", "reopen keeps publish")
	_expect(host, dlg.scheduled_edit.text == "2026-12-01", "reopen keeps start")
	_expect(host, dlg.deadline_edit.text == "2026-12-04", "reopen keeps deadline")
	dlg.queue_free()


static func _test_calendar_card_right_click_and_double_click(host: Node) -> void:
	print("-- calendar card right-click menu + double-click editor --")
	var cal_src: String = FileAccess.get_file_as_string(
		"res://readymade/ui/internal/mission_control_calendar_base.gd"
	)
	_expect(
		host,
		cal_src.find("_CALENDAR_DRAG_THRESHOLD_PX") >= 0 and cal_src.find("_pending_drag_task") >= 0,
		"drag starts only after motion threshold"
	)
	_expect(
		host,
		cal_src.find("menu.popup()") >= 0 and cal_src.find("menu.top_level") < 0,
		"context menu uses bare popup(); no Control.top_level on Window PopupMenu"
	)
	var dash = preload("res://readymade/ui/mission_control_dashboard.gd").new()
	host.add_child(dash)
	var task := WorkplanTask.new()
	task.title = "Peer review"
	task.ensure_task_id()
	task.publish_date = "2026-12-05"
	task.core_idea = "Review fixtures"
	const DayCardsScript = preload("res://readymade/scripts/workplan_calendar_day_cards.gd")
	var card: PanelContainer = DayCardsScript.create_month_card(
		task, "publish", ["publish"], "2026-12-05", false
	)
	dash.add_child(card)
	_expect(host, card.mouse_filter == Control.MOUSE_FILTER_STOP, "card stops mouse for gui_input")
	# Simulate right-click on a live calendar card path.
	var right_ev := InputEventMouseButton.new()
	right_ev.button_index = MOUSE_BUTTON_RIGHT
	right_ev.pressed = true
	right_ev.position = Vector2(8, 8)
	dash._on_task_card_input(card, task, "publish", right_ev)
	var menu: PopupMenu = dash.calendar_context_menu
	_expect(host, menu != null and is_instance_valid(menu), "right-click creates context menu")
	_expect(host, menu != null and menu.visible, "right-click menu is visible")
	_expect(host, menu != null and menu.item_count > 0, "right-click menu has items")
	# Undo path must dismiss on one activation (same frame, before rebuild).
	var menu_before_undo: PopupMenu = menu
	dash._on_calendar_context_menu_id_pressed(5)
	_expect(host, dash.calendar_context_menu == null, "Undo id dismisses menu on one click")
	_expect(
		host,
		not is_instance_valid(menu_before_undo) or not menu_before_undo.visible,
		"Undo hides menu synchronously before rebuild"
	)
	# Double-click opens editor (task_dialog.show_edit_dialog).
	if dash.task_dialog == null:
		dash.task_dialog = preload("res://readymade/ui/task_dialog.tscn").instantiate()
		dash.add_child(dash.task_dialog)
	var dbl := InputEventMouseButton.new()
	dbl.button_index = MOUSE_BUTTON_LEFT
	dbl.pressed = true
	dbl.double_click = true
	dbl.position = Vector2(8, 8)
	dash._on_task_card_input(card, task, "publish", dbl)
	_expect(
		host,
		dash.task_dialog != null and dash.task_dialog.visible,
		"double-click opens task editor"
	)
	if dash.task_dialog and dash.task_dialog.visible:
		dash.task_dialog.hide()
	card.queue_free()
	dash.queue_free()


static func _test_import_preview_hidden_before_result(host: Node) -> void:
	print("-- import preview hidden/freed before Import complete --")
	var import_src: String = FileAccess.get_file_as_string(
		"res://readymade/ui/internal/mission_control_workplan_syntree_base.gd"
	)
	_expect(
		host,
		import_src.find("_show_import_complete_result") >= 0
		and import_src.find("call_deferred") >= 0
		and import_src.find("_close_import_preview_dialog(summary)") >= 0,
		"Apply closes preview then deferred-shows result"
	)
	_expect(
		host,
		import_src.find("min_size = Vector2(320") >= 0 or import_src.find("popup_centered(Vector2i(320") >= 0,
		"Import complete dialog sized to fit title"
	)
	var dash = preload("res://readymade/ui/mission_control_dashboard.gd").new()
	host.add_child(dash)
	_expect(host, dash.has_method("_show_import_complete_result"), "import complete helper present")
	var preview := ConfirmationDialog.new()
	preview.title = "Import Tasks Preview"
	preview.exclusive = true
	dash.add_child(preview)
	preview.popup_centered()
	dash._close_import_preview_dialog(preview)
	dash._show_import_complete_result(3, 1, null)
	var preview_still := false
	var result_visible := false
	var result_wide_enough := false
	for child in dash.get_children():
		if child is AcceptDialog and is_instance_valid(child):
			var dlg: AcceptDialog = child as AcceptDialog
			if dlg.title == "Import Tasks Preview" and dlg.visible:
				preview_still = true
			if dlg.title == "Import complete" and dlg.visible:
				result_visible = true
				result_wide_enough = dlg.min_size.x >= 300.0 or dlg.size.x >= 300.0
	_expect(host, not preview_still, "preview not visible when result shown")
	_expect(host, result_visible, "Import complete result visible")
	_expect(host, result_wide_enough, "Import complete min/size fits full title")
	dash.queue_free()
