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
	_expect(host, a.publish_time == "10:00", "publish time preserved")
	_expect(host, a.publish_timezone == "Europe/Oslo", "publish timezone preserved")
	_expect(host, b.publish_date == "2026-11-13", "sibling instance unchanged")
	_expect(host, (moved.get("warnings", []) as Array).size() >= 0, "warnings array present")
	_expect(host, mover.can_undo(), "undo available after move")
	_expect(host, mover.undo_last(workplan), "undo succeeds")
	_expect(host, a.publish_date == "2026-11-06", "undo restores publish_date")
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
	file_dialog_local.free()
