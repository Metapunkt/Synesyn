extends RefCounted
## Round 5 hardening acceptance (kept separate for script line limits).


static func run_all(host: Node) -> void:
	_test_tasks_row_copy_markdown_feedback(host)
	_test_calendar_cadence_banner_own_row(host)
	_test_undo_hides_menu_before_rebuild(host)
	_test_campaign_report_text_contrast(host)


static func _expect(host: Node, condition: bool, label: String) -> void:
	host.call("_expect", condition, label)


static func _test_tasks_row_copy_markdown_feedback(host: Node) -> void:
	print("-- Tasks row Copy as Markdown clipboard + ✓ Copied --")
	const MarkdownScript = preload("res://readymade/scripts/workplan_task_markdown.gd")
	var dash = preload("res://readymade/ui/mission_control_dashboard.gd").new()
	host.add_child(dash)
	var task := WorkplanTask.new()
	task.title = "Issue announcement"
	task.ensure_task_id()
	task.core_idea = "Announce the release"
	task.channel = "#general"
	task.generated_content = "Hello community"
	var expected_md: String = MarkdownScript.to_clipboard_markdown(task, null)
	_expect(host, expected_md.find("Issue announcement") >= 0, "markdown includes task title")
	_expect(host, expected_md.find("Hello community") >= 0, "markdown includes draft body")
	var copy_btn := Button.new()
	copy_btn.text = "📋 Copy as Markdown"
	dash.add_child(copy_btn)
	dash._on_copy_task_markdown_pressed(task, copy_btn)
	# Headless CI has no clipboard backend; still assert UI feedback + markdown payload.
	var clip: String = DisplayServer.clipboard_get()
	if not clip.is_empty():
		_expect(host, clip.find("Issue announcement") >= 0, "clipboard has task title markdown")
		_expect(host, clip.find("Hello community") >= 0, "clipboard has draft body")
	else:
		_expect(host, not expected_md.is_empty(), "markdown payload ready when clipboard unsupported")
	_expect(host, copy_btn.text.find("Copied") >= 0, "row button shows ✓ Copied feedback")
	var toast_found := false
	for child in dash.get_children():
		if child is Label and (
			String(child.name).find("Copied") >= 0 or (child as Label).text.find("Copied") >= 0
		):
			toast_found = true
			break
	_expect(host, toast_found, "Copied toast label added")
	var card: Control = dash._create_task_card(task)
	_expect(host, card != null, "Tasks row card created")
	var wired_btn: Button = null
	if card != null:
		for node in card.find_children("*", "Button", true, false):
			if node is Button and String((node as Button).text).find("Copy as Markdown") >= 0:
				wired_btn = node as Button
				break
	_expect(host, wired_btn != null, "Tasks row has Copy as Markdown button")
	if wired_btn != null:
		wired_btn.emit_signal("pressed")
		_expect(host, wired_btn.text.find("Copied") >= 0, "pressed row button flips to ✓ Copied")
	if card != null:
		card.queue_free()
	copy_btn.queue_free()
	dash.queue_free()


static func _test_calendar_cadence_banner_own_row(host: Node) -> void:
	print("-- calendar Cadence banner own row + min width --")
	var cal_src: String = FileAccess.get_file_as_string(
		"res://readymade/ui/internal/mission_control_calendar_base.gd"
	)
	_expect(host, cal_src.find("_calendar_banner_host") >= 0, "banner host helper present")
	_expect(
		host,
		cal_src.find("custom_minimum_size = Vector2(160") >= 0 and cal_src.find("AUTOWRAP_OFF") >= 0,
		"Cadence banner has min width and no vertical wrap"
	)
	_expect(host, cal_src.find("_ensure_left_sidebar_split") >= 0, "left sidebar split guard referenced")
	var dash = preload("res://readymade/ui/mission_control_dashboard.gd").new()
	host.add_child(dash)
	_expect(host, dash.has_method("_calendar_banner_host"), "dashboard has banner host helper")
	_expect(host, dash.has_method("_ensure_left_sidebar_split"), "sidebar split helper present")
	dash._ensure_left_sidebar_split()
	dash.queue_free()


static func _test_undo_hides_menu_before_rebuild(host: Node) -> void:
	print("-- Undo hides context menu before calendar rebuild --")
	var cal_src: String = FileAccess.get_file_as_string(
		"res://readymade/ui/internal/mission_control_calendar_base.gd"
	)
	_expect(
		host,
		cal_src.find("call_deferred(\"_run_calendar_context_action\"") < 0,
		"Undo/action runs synchronously after hide (not deferred)"
	)
	_expect(
		host,
		cal_src.find("menu.hide()") >= 0 and cal_src.find("menu.queue_free()") >= 0,
		"dismiss hides then queue_frees"
	)
	var dash = preload("res://readymade/ui/mission_control_dashboard.gd").new()
	host.add_child(dash)
	var menu := PopupMenu.new()
	menu.name = "CalendarContextMenu"
	dash.add_child(menu)
	menu.add_item("Undo last reschedule", 5)
	menu.popup()
	dash.calendar_context_menu = menu
	_expect(host, menu.visible, "menu visible before Undo")
	dash.context_menu_task = WorkplanTask.new()
	dash._on_calendar_context_menu_id_pressed(5)
	_expect(host, dash.calendar_context_menu == null, "ref cleared on Undo")
	_expect(host, not is_instance_valid(menu) or not menu.visible, "menu hidden same frame as Undo")
	dash.queue_free()


static func _test_campaign_report_text_contrast(host: Node) -> void:
	print("-- Campaign dashboard report TextEdit contrast --")
	const ReadableTextScript = preload("res://readymade/scripts/readymade_readable_text.gd")
	_expect(
		host,
		FileAccess.file_exists("res://readymade/ui/campaign_dashboard.tscn"),
		"live Campaigns tab uses campaign_dashboard.tscn"
	)
	var main_src: String = FileAccess.get_file_as_string("res://readymade/ui/mission_control_dashboard.tscn")
	_expect(
		host,
		main_src.find("campaign_dashboard.tscn") >= 0 and main_src.find("CampaignDashboard") >= 0,
		"Mission Control embeds CampaignDashboard scene"
	)
	var theme_src: String = FileAccess.get_file_as_string("res://readymade/ui/readymade_theme_light.tres")
	_expect(
		host,
		theme_src.find("font_readonly_color") >= 0 and theme_src.find("styles/read_only") >= 0,
		"light theme defines TextEdit readonly font + style"
	)
	var scene: PackedScene = load("res://readymade/ui/campaign_dashboard.tscn")
	_expect(host, scene != null, "campaign_dashboard.tscn loads")
	if scene == null:
		return
	var dash: Node = scene.instantiate()
	host.add_child(dash)
	var report: TextEdit = dash.get("report_text") as TextEdit
	_expect(host, report != null, "report_text TextEdit present")
	if report == null:
		dash.queue_free()
		return
	_expect(host, report.editable == false, "report TextEdit is read-only")
	# _ready already applied contrast; re-assert effective colors.
	var font_color: Color = ReadableTextScript.effective_report_font_color(report)
	var bg_color: Color = ReadableTextScript.effective_report_bg_color(report)
	var ratio: float = ReadableTextScript.contrast_ratio(font_color, bg_color)
	_expect(host, font_color.get_luminance() < 0.35, "report font is dark")
	_expect(host, bg_color.get_luminance() > 0.85, "report background is light")
	_expect(host, ratio >= 4.5, "report font/background contrast meets WCAG AA (%.2f)" % ratio)
	dash.queue_free()
