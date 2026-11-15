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
