extends Window
class_name TaskDialog

const WorkplanDependenciesScript = preload("res://readymade/scripts/workplan_dependencies.gd")

# UI References
@onready var title_edit: LineEdit = $ScrollContainer/VBoxContainer/TabContainer/BasicInfo/BasicInfoVBox/TitleContainer/TitleEdit
@onready var core_idea_edit: TextEdit = $ScrollContainer/VBoxContainer/TabContainer/BasicInfo/BasicInfoVBox/CoreIdeaContainer/CoreIdeaEdit

# Static checkboxes
@onready var video_check: CheckBox = $"ScrollContainer/VBoxContainer/TabContainer/BasicInfo/BasicInfoVBox/FormatsContainer/FormatsGrid/VideoCheck"
@onready var article_check: CheckBox = $"ScrollContainer/VBoxContainer/TabContainer/BasicInfo/BasicInfoVBox/FormatsContainer/FormatsGrid/ArticleCheck"
@onready var carousel_check: CheckBox = $"ScrollContainer/VBoxContainer/TabContainer/BasicInfo/BasicInfoVBox/FormatsContainer/FormatsGrid/CarouselCheck"
@onready var infographic_check: CheckBox = $"ScrollContainer/VBoxContainer/TabContainer/BasicInfo/BasicInfoVBox/FormatsContainer/FormatsGrid/InfographicCheck"
@onready var podcast_check: CheckBox = $"ScrollContainer/VBoxContainer/TabContainer/BasicInfo/BasicInfoVBox/FormatsContainer/FormatsGrid/PodcastCheck"
@onready var livestream_check: CheckBox = $"ScrollContainer/VBoxContainer/TabContainer/BasicInfo/BasicInfoVBox/FormatsContainer/FormatsGrid/LiveStreamCheck"
@onready var shorttext_check: CheckBox = $"ScrollContainer/VBoxContainer/TabContainer/BasicInfo/BasicInfoVBox/FormatsContainer/FormatsGrid/ShortTextCheck"
@onready var image_check: CheckBox = $"ScrollContainer/VBoxContainer/TabContainer/BasicInfo/BasicInfoVBox/FormatsContainer/FormatsGrid/ImageCheck"

@onready var youtube_check: CheckBox = $"ScrollContainer/VBoxContainer/TabContainer/BasicInfo/BasicInfoVBox/ChannelsContainer/ChannelsGrid/YouTubeCheck"
@onready var instagram_check: CheckBox = $"ScrollContainer/VBoxContainer/TabContainer/BasicInfo/BasicInfoVBox/ChannelsContainer/ChannelsGrid/InstagramCheck"
@onready var tiktok_check: CheckBox = $"ScrollContainer/VBoxContainer/TabContainer/BasicInfo/BasicInfoVBox/ChannelsContainer/ChannelsGrid/TikTokCheck"
@onready var facebook_check: CheckBox = $"ScrollContainer/VBoxContainer/TabContainer/BasicInfo/BasicInfoVBox/ChannelsContainer/ChannelsGrid/FacebookCheck"
@onready var twitter_check: CheckBox = $"ScrollContainer/VBoxContainer/TabContainer/BasicInfo/BasicInfoVBox/ChannelsContainer/ChannelsGrid/TwitterCheck"
@onready var linkedin_check: CheckBox = $"ScrollContainer/VBoxContainer/TabContainer/BasicInfo/BasicInfoVBox/ChannelsContainer/ChannelsGrid/LinkedInCheck"
@onready var discord_check: CheckBox = $"ScrollContainer/VBoxContainer/TabContainer/BasicInfo/BasicInfoVBox/ChannelsContainer/ChannelsGrid/DiscordCheck"

# Other UI elements
@onready var format_other_check: CheckBox = $"ScrollContainer/VBoxContainer/TabContainer/BasicInfo/BasicInfoVBox/FormatsContainer/FormatOtherContainer/FormatOtherCheck"
@onready var format_other_edit: LineEdit = $"ScrollContainer/VBoxContainer/TabContainer/BasicInfo/BasicInfoVBox/FormatsContainer/FormatOtherContainer/FormatOtherEdit"
@onready var channel_other_check: CheckBox = $"ScrollContainer/VBoxContainer/TabContainer/BasicInfo/BasicInfoVBox/ChannelsContainer/ChannelOtherContainer/ChannelOtherCheck"
@onready var channel_other_edit: LineEdit = $"ScrollContainer/VBoxContainer/TabContainer/BasicInfo/BasicInfoVBox/ChannelsContainer/ChannelOtherContainer/ChannelOtherEdit"

@onready var roleplay_check: CheckBox = $"ScrollContainer/VBoxContainer/TabContainer/BasicInfo/BasicInfoVBox/CosmicContainer/CosmicGrid/RolePlayCheck"
@onready var hypothetical_check: CheckBox = $"ScrollContainer/VBoxContainer/TabContainer/BasicInfo/BasicInfoVBox/CosmicContainer/CosmicGrid/HypotheticalCheck"
@onready var iterative_check: CheckBox = $"ScrollContainer/VBoxContainer/TabContainer/BasicInfo/BasicInfoVBox/CosmicContainer/CosmicGrid/IterativeCheck"
@onready var abductive_check: CheckBox = $"ScrollContainer/VBoxContainer/TabContainer/BasicInfo/BasicInfoVBox/CosmicContainer/CosmicGrid/AbductiveCheck"
@onready var cosmic_other_check: CheckBox = $"ScrollContainer/VBoxContainer/TabContainer/BasicInfo/BasicInfoVBox/CosmicContainer/CosmicOtherContainer/CosmicOtherCheck"
@onready var cosmic_other_edit: LineEdit = $"ScrollContainer/VBoxContainer/TabContainer/BasicInfo/BasicInfoVBox/CosmicContainer/CosmicOtherContainer/CosmicOtherEdit"

@onready var priority_option: OptionButton = $"ScrollContainer/VBoxContainer/TabContainer/BasicInfo/BasicInfoVBox/PriorityContainer/PriorityOption"
@onready var depends_on_edit: LineEdit = $"ScrollContainer/VBoxContainer/TabContainer/BasicInfo/BasicInfoVBox/DependsOnContainer/DependsOnEdit"
@onready var blocked_hint_label: Label = $"ScrollContainer/VBoxContainer/TabContainer/BasicInfo/BasicInfoVBox/DependsOnContainer/BlockedHintLabel"
@onready var assignee_option: OptionButton = $"ScrollContainer/VBoxContainer/TabContainer/BasicInfo/BasicInfoVBox/AssigneeContainer/AssigneeOption"
@onready var assignee_edit: LineEdit = $"ScrollContainer/VBoxContainer/TabContainer/BasicInfo/BasicInfoVBox/AssigneeContainer/AssigneeEdit"
@onready var approval_log_text: TextEdit = $"ScrollContainer/VBoxContainer/TabContainer/BasicInfo/BasicInfoVBox/ApprovalLogContainer/ApprovalLogText"
@onready var notes_edit: TextEdit = $"ScrollContainer/VBoxContainer/TabContainer/BasicInfo/BasicInfoVBox/NotesContainer/NotesEdit"

# Calendar tab
@onready var deadline_edit: LineEdit = $"ScrollContainer/VBoxContainer/TabContainer/Calendar/CalendarVBox/DeadlineContainer/DeadlineRow/DeadlineEdit"
@onready var scheduled_edit: LineEdit = $"ScrollContainer/VBoxContainer/TabContainer/Calendar/CalendarVBox/ScheduledContainer/ScheduledRow/ScheduledEdit"
@onready var publish_date_edit: LineEdit = $"ScrollContainer/VBoxContainer/TabContainer/Calendar/CalendarVBox/PublishContainer/PublishRow/PublishEdit"
@onready var publish_time_edit: LineEdit = $"ScrollContainer/VBoxContainer/TabContainer/Calendar/CalendarVBox/PublishContainer/PublishTimeRow/PublishTimeEdit"
@onready var publish_timezone_edit: LineEdit = $"ScrollContainer/VBoxContainer/TabContainer/Calendar/CalendarVBox/PublishContainer/PublishTimeRow/PublishTimezoneEdit"
@onready var content_status_option: OptionButton = $"ScrollContainer/VBoxContainer/TabContainer/Calendar/CalendarVBox/ContentStatusContainer/ContentStatusOption"
@onready var recurring_option: OptionButton = $"ScrollContainer/VBoxContainer/TabContainer/Calendar/CalendarVBox/RecurringContainer/RecurringOption"
@onready var weekday_mon: CheckBox = $"ScrollContainer/VBoxContainer/TabContainer/Calendar/CalendarVBox/RecurringWeekdaysContainer/WeekdayMon"
@onready var weekday_tue: CheckBox = $"ScrollContainer/VBoxContainer/TabContainer/Calendar/CalendarVBox/RecurringWeekdaysContainer/WeekdayTue"
@onready var weekday_wed: CheckBox = $"ScrollContainer/VBoxContainer/TabContainer/Calendar/CalendarVBox/RecurringWeekdaysContainer/WeekdayWed"
@onready var weekday_thu: CheckBox = $"ScrollContainer/VBoxContainer/TabContainer/Calendar/CalendarVBox/RecurringWeekdaysContainer/WeekdayThu"
@onready var weekday_fri: CheckBox = $"ScrollContainer/VBoxContainer/TabContainer/Calendar/CalendarVBox/RecurringWeekdaysContainer/WeekdayFri"
@onready var weekday_sat: CheckBox = $"ScrollContainer/VBoxContainer/TabContainer/Calendar/CalendarVBox/RecurringWeekdaysContainer/WeekdaySat"
@onready var weekday_sun: CheckBox = $"ScrollContainer/VBoxContainer/TabContainer/Calendar/CalendarVBox/RecurringWeekdaysContainer/WeekdaySun"
@onready var recurring_end_edit: LineEdit = $"ScrollContainer/VBoxContainer/TabContainer/Calendar/CalendarVBox/RecurringEndContainer/RecurringEndEdit"
@onready var expand_recurrence_button: Button = $"ScrollContainer/VBoxContainer/TabContainer/Calendar/CalendarVBox/RecurringEndContainer/ExpandRecurrenceButton"
@onready var duration_spin: SpinBox = $"ScrollContainer/VBoxContainer/TabContainer/Calendar/CalendarVBox/DurationContainer/DurationSpin"

signal recurrence_expand_requested(task: WorkplanTask, instance_count: int)

# Strategy tab  
@onready var campaign_edit: LineEdit = $"ScrollContainer/VBoxContainer/TabContainer/Strategy/StrategyVBox/CampaignContainer/CampaignEdit"
@onready var theme_edit: LineEdit = $"ScrollContainer/VBoxContainer/TabContainer/Strategy/StrategyVBox/ThemeContainer/ThemeEdit"
@onready var audience_edit: LineEdit = $"ScrollContainer/VBoxContainer/TabContainer/Strategy/StrategyVBox/AudienceContainer/AudienceEdit"
@onready var performance_edit: TextEdit = $"ScrollContainer/VBoxContainer/TabContainer/Strategy/StrategyVBox/PerformanceContainer/PerformanceEdit"

# Dynamic format and channel containers
@onready var formats_grid: GridContainer = $"ScrollContainer/VBoxContainer/TabContainer/BasicInfo/BasicInfoVBox/FormatsContainer/FormatsGrid"
@onready var channels_grid: GridContainer = $"ScrollContainer/VBoxContainer/TabContainer/BasicInfo/BasicInfoVBox/ChannelsContainer/ChannelsGrid"
@onready var format_other_container: HBoxContainer = $"ScrollContainer/VBoxContainer/TabContainer/BasicInfo/BasicInfoVBox/FormatsContainer/FormatOtherContainer"
@onready var channel_other_container: HBoxContainer = $"ScrollContainer/VBoxContainer/TabContainer/BasicInfo/BasicInfoVBox/ChannelsContainer/ChannelOtherContainer"

# Mode filtering toggles
@onready var format_filter_toggle: CheckBox = $"ScrollContainer/VBoxContainer/TabContainer/BasicInfo/BasicInfoVBox/FormatsContainer/FormatsHeaderContainer/FormatFilterToggle"
@onready var channel_filter_toggle: CheckBox = $"ScrollContainer/VBoxContainer/TabContainer/BasicInfo/BasicInfoVBox/ChannelsContainer/ChannelsHeaderContainer/ChannelFilterToggle"

# Strategy mode guidance
@onready var mode_guidance_text: Label = $"ScrollContainer/VBoxContainer/TabContainer/Strategy/StrategyVBox/ModeStrategyContainer/ModeGuidanceText"

# Mode-aware dynamic checkboxes
var format_checkboxes: Array[CheckBox] = []
var channel_checkboxes: Array[CheckBox] = []

# Static checkbox arrays for easy management
var static_format_checkboxes: Array[CheckBox] = []
var static_channel_checkboxes: Array[CheckBox] = []

var editing_task: WorkplanTask = null
var is_edit_mode: bool = false

func _ready():
	_setup_ui()
	_setup_recurring_options()
	_setup_content_status_options()
	_setup_assignee_options()
	_collect_static_checkboxes()
	_setup_mode_aware_options()
	const ReadableTextScript = preload("res://readymade/scripts/readymade_readable_text.gd")
	if approval_log_text != null:
		ReadableTextScript.apply_report_text_edit(approval_log_text)
	
	# Connect to mode changes
	if ModeManager:
		ModeManager.mode_changed.connect(_on_mode_changed)
	
	# Connect filter toggle signals
	format_filter_toggle.toggled.connect(_on_format_filter_toggled)
	channel_filter_toggle.toggled.connect(_on_channel_filter_toggled)
	if expand_recurrence_button:
		expand_recurrence_button.pressed.connect(_on_expand_recurrence_pressed)
	if depends_on_edit:
		depends_on_edit.text_changed.connect(func(_t: String): _refresh_blocked_hint())
	if assignee_option:
		assignee_option.item_selected.connect(_on_assignee_option_selected)
	# Re-apply calendar dates when the Calendar tab is shown (hidden tabs can miss first paint).
	var tabs: TabContainer = $ScrollContainer/VBoxContainer/TabContainer as TabContainer
	if tabs != null:
		tabs.tab_changed.connect(_on_task_dialog_tab_changed)
	about_to_popup.connect(_on_about_to_popup_refresh_dates)


func _setup_content_status_options() -> void:
	if content_status_option == null:
		return
	content_status_option.clear()
	for status_id in WorkplanTask.CONTENT_STATUSES:
		content_status_option.add_item(String(status_id))


func _setup_assignee_options() -> void:
	if assignee_option == null:
		return
	assignee_option.clear()
	assignee_option.add_item("(none)")
	assignee_option.add_item("(custom / agent…)")
	var workplan: Workplan = _current_workplan()
	if workplan == null:
		return
	for person_any in workplan.people:
		if typeof(person_any) != TYPE_DICTIONARY:
			continue
		var person: Dictionary = person_any
		var person_name: String = String(person.get("name", "")).strip_edges()
		if person_name.is_empty():
			continue
		var role_label: String = String(person.get("role", "")).strip_edges()
		var label_text: String = person_name if role_label.is_empty() else "%s (%s)" % [person_name, role_label]
		assignee_option.add_item(label_text)
		assignee_option.set_item_metadata(assignee_option.item_count - 1, person_name)


func _current_workplan() -> Workplan:
	var manager: Node = get_node_or_null("/root/WorkplanManager")
	if manager != null and manager.has_method("get_current_workplan"):
		return manager.get_current_workplan() as Workplan
	return null


func _on_assignee_option_selected(index: int) -> void:
	if assignee_edit == null or assignee_option == null:
		return
	if index <= 0:
		assignee_edit.text = ""
		return
	if index == 1:
		# Keep free-text edit for custom/agent values.
		return
	var meta: Variant = assignee_option.get_item_metadata(index)
	if meta == null:
		return
	assignee_edit.text = str(meta)


func _refresh_blocked_hint() -> void:
	if blocked_hint_label == null:
		return
	var workplan: Workplan = _current_workplan()
	var probe := WorkplanTask.new()
	if editing_task != null:
		probe.task_id = editing_task.task_id
	probe.depends_on = WorkplanDependenciesScript.normalize_ids(
		depends_on_edit.text if depends_on_edit else ""
	)
	if workplan != null and WorkplanDependenciesScript.would_create_cycle(probe.task_id, probe.depends_on, workplan):
		blocked_hint_label.text = "⚠ That dependency set would create a cycle."
		return
	if WorkplanDependenciesScript.is_blocked(probe, workplan):
		blocked_hint_label.text = "Blocked — predecessor(s) not Done (or missing)."
	else:
		blocked_hint_label.text = ""


func _format_approval_log(entries: Array) -> String:
	if entries.is_empty():
		return ""
	var lines: PackedStringArray = PackedStringArray()
	for entry_any in entries:
		if typeof(entry_any) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_any
		var line: String = "%s → %s @ %s" % [
			String(entry.get("from", "")),
			String(entry.get("to", "")),
			String(entry.get("at", "")),
		]
		var person: String = String(entry.get("person", "")).strip_edges()
		var note: String = String(entry.get("note", "")).strip_edges()
		if not person.is_empty():
			line += " (%s)" % person
		if not note.is_empty():
			line += " — %s" % note
		lines.append(line)
	return "\n".join(lines)


func _get_selected_assignee() -> String:
	if assignee_edit != null and not assignee_edit.text.strip_edges().is_empty():
		return assignee_edit.text.strip_edges()
	if assignee_option == null or assignee_option.selected <= 0:
		return ""
	if assignee_option.selected == 1:
		return ""
	var meta: Variant = assignee_option.get_item_metadata(assignee_option.selected)
	if meta == null:
		return ""
	return str(meta)

func _collect_static_checkboxes():
	"""Collect static checkboxes for easy management"""
	static_format_checkboxes = [video_check, article_check, carousel_check, infographic_check, podcast_check, livestream_check, shorttext_check, image_check]
	static_channel_checkboxes = [youtube_check, instagram_check, tiktok_check, facebook_check, twitter_check, linkedin_check, discord_check]

func _on_format_filter_toggled(toggled_on: bool):
	"""Handle format filter toggle"""
	if toggled_on:
		_show_mode_filtered_formats()
	else:
		_show_all_formats()

func _on_channel_filter_toggled(toggled_on: bool):
	"""Handle channel filter toggle"""
	if toggled_on:
		_show_mode_filtered_channels()
	else:
		_show_all_channels()

func _show_mode_filtered_formats():
	"""Show only mode-specific formats"""
	# Hide static checkboxes
	for checkbox in static_format_checkboxes:
		if checkbox and is_instance_valid(checkbox):
			checkbox.visible = false
	
	# Create/show dynamic checkboxes
	_create_format_checkboxes()

func _show_all_formats():
	"""Show all format options from all modes"""
	# Hide static checkboxes
	for checkbox in static_format_checkboxes:
		if checkbox and is_instance_valid(checkbox):
			checkbox.visible = false
	
	# Create comprehensive list from all modes
	_create_all_format_checkboxes()

func _show_mode_filtered_channels():
	"""Show only mode-specific channels"""
	# Hide static checkboxes  
	for checkbox in static_channel_checkboxes:
		if checkbox and is_instance_valid(checkbox):
			checkbox.visible = false
	
	# Create/show dynamic checkboxes
	_create_channel_checkboxes()

func _show_all_channels():
	"""Show all channel options from all modes"""
	# Hide static checkboxes
	for checkbox in static_channel_checkboxes:
		if checkbox and is_instance_valid(checkbox):
			checkbox.visible = false
	
	# Create comprehensive list from all modes
	_create_all_channel_checkboxes()

func _update_strategy_guidance():
	"""Update strategy guidance based on current mode"""
	if not mode_guidance_text:
		return
		
	var current_mode = ModeManager.get_current_mode()
	var guidance_text = ""
	
	match current_mode:
		"social_media":
			guidance_text = """🎯 Social Media Strategy Focus:
• Hook attention in first 3 seconds
• Use trending hashtags and platform-specific formats  
• Optimize for platform algorithms (timing, engagement)
• Include clear call-to-action for audience interaction
• Consider visual appeal and mobile-first design"""
		"creative_writing":
			guidance_text = """🎯 Creative Writing Strategy Focus:
• Develop compelling characters with clear motivations
• Build engaging narrative structure and pacing
• Use vivid imagery and emotional resonance
• Consider target audience and genre conventions
• Focus on authentic voice and unique perspective"""
		"academic_writing":
			guidance_text = """🎯 Academic Writing Strategy Focus:
• Present clear thesis and logical argument structure
• Use credible sources and proper citations
• Maintain objective, scholarly tone
• Follow discipline-specific formatting guidelines
• Ensure methodological rigor and evidence-based claims"""
		_:
			guidance_text = "Strategy guidance will appear here based on your current work mode."
	
	mode_guidance_text.text = guidance_text

func _setup_ui():
	"""Initialize UI components"""
	# Set window properties
	min_size = Vector2i(650, 550)
	
	# Setup priority options
	if priority_option:
		priority_option.add_item("Low (0)")
		priority_option.add_item("Medium (1)")
		priority_option.add_item("High (2)")
		priority_option.add_item("Critical (3)")

	# Keep cosmic picker labels in sync with CosmicInstruments.labeled_display.
	if roleplay_check:
		roleplay_check.text = CosmicInstruments.labeled_display(CosmicInstruments.CODE_RP)
	if hypothetical_check:
		hypothetical_check.text = CosmicInstruments.labeled_display(CosmicInstruments.CODE_HF)
	if iterative_check:
		iterative_check.text = CosmicInstruments.labeled_display(CosmicInstruments.CODE_IR)
	if abductive_check:
		abductive_check.text = CosmicInstruments.labeled_display(CosmicInstruments.CODE_AH)
	
	# Initially disable "Other" text fields
	if format_other_edit:
		format_other_edit.editable = false
	if channel_other_edit:
		channel_other_edit.editable = false
	if cosmic_other_edit:
		cosmic_other_edit.editable = false

func _setup_recurring_options():
	"""Setup recurring pattern options"""
	if recurring_option:
		recurring_option.add_item("None")
		recurring_option.add_item("Daily")
		recurring_option.add_item("Weekly")
		recurring_option.add_item("Monthly")
		recurring_option.add_item("Custom")

func _setup_mode_aware_options():
	"""Setup dynamic format and channel options based on current mode"""
	# Check if mode filter is enabled and setup accordingly
	if format_filter_toggle.button_pressed:
		_create_format_checkboxes()
	else:
		_create_all_format_checkboxes()
		
	if channel_filter_toggle.button_pressed:
		_create_channel_checkboxes()
	else:
		_create_all_channel_checkboxes()
		
	_update_strategy_guidance()

func _create_format_checkboxes():
	"""Create format checkboxes based on current mode"""
	# Clear existing format checkboxes
	for checkbox in format_checkboxes:
		if checkbox and is_instance_valid(checkbox):
			checkbox.queue_free()
	format_checkboxes.clear()
	
	# Get current mode formats
	var formats = ModeManager.get_current_formats()
	
	# Create new format checkboxes
	for format_name in formats:
		var checkbox = CheckBox.new()
		checkbox.text = format_name
		checkbox.name = format_name.replace(" ", "").replace("/", "") + "Check"
		formats_grid.add_child(checkbox)
		format_checkboxes.append(checkbox)

func _create_channel_checkboxes():
	"""Create channel checkboxes: mode platforms + workplan custom destinations"""
	# Clear existing channel checkboxes
	for checkbox in channel_checkboxes:
		if checkbox and is_instance_valid(checkbox):
			checkbox.queue_free()
	channel_checkboxes.clear()

	var channels: Array[String] = _collect_effective_channels(false)

	for channel_name in channels:
		var checkbox = CheckBox.new()
		checkbox.text = channel_name
		checkbox.name = channel_name.replace(" ", "").replace("/", "").replace("#", "") + "Check"
		channels_grid.add_child(checkbox)
		channel_checkboxes.append(checkbox)

func _create_all_format_checkboxes():
	"""Create format checkboxes from ALL modes"""
	# Clear existing format checkboxes
	for checkbox in format_checkboxes:
		if checkbox and is_instance_valid(checkbox):
			checkbox.queue_free()
	format_checkboxes.clear()
	
	# Get formats from all modes
	var all_formats: Array[String] = []
	var all_modes = ModeManager.get_available_modes()
	
	for mode_id in all_modes:
		var mode_config = ModeManager.get_mode_config(mode_id)
		var mode_formats = mode_config.formats
		for format in mode_formats:
			if not all_formats.has(format):
				all_formats.append(format)
	
	# Create format checkboxes for all options
	for format_name in all_formats:
		var checkbox = CheckBox.new()
		checkbox.text = format_name
		checkbox.name = format_name.replace(" ", "").replace("/", "") + "Check"
		formats_grid.add_child(checkbox)
		format_checkboxes.append(checkbox)

func _create_all_channel_checkboxes():
	"""Create channel checkboxes from ALL modes plus workplan custom destinations"""
	# Clear existing channel checkboxes
	for checkbox in channel_checkboxes:
		if checkbox and is_instance_valid(checkbox):
			checkbox.queue_free()
	channel_checkboxes.clear()

	var all_channels: Array[String] = _collect_effective_channels(true)

	for channel_name in all_channels:
		var checkbox = CheckBox.new()
		checkbox.text = channel_name
		checkbox.name = channel_name.replace(" ", "").replace("/", "").replace("#", "") + "Check"
		channels_grid.add_child(checkbox)
		channel_checkboxes.append(checkbox)


func _collect_effective_channels(from_all_modes: bool) -> Array[String]:
	"""Merge mode platform venues with the current workplan's custom destinations."""
	var combined: Array[String] = []
	if ModeManager != null:
		if from_all_modes:
			for mode_id in ModeManager.get_available_modes():
				var mode_config = ModeManager.get_mode_config(mode_id)
				for channel_label in mode_config.channels:
					if not combined.has(channel_label):
						combined.append(channel_label)
		else:
			for channel_label in ModeManager.get_current_channels():
				if not combined.has(channel_label):
					combined.append(channel_label)
	var workplan_manager: Node = get_node_or_null("/root/WorkplanManager")
	if workplan_manager != null and workplan_manager.has_method("get_custom_channels"):
		for channel_label in workplan_manager.get_custom_channels():
			if not combined.has(channel_label):
				combined.append(channel_label)
	return combined

func _on_mode_changed(_new_mode: String):
	"""Handle mode change by recreating options"""
	if format_filter_toggle.button_pressed:
		_create_format_checkboxes()
	if channel_filter_toggle.button_pressed:
		_create_channel_checkboxes()
	
	# Update strategy guidance
	_update_strategy_guidance()
	
	# If dialog is open and not in edit mode, update defaults
	if visible and not is_edit_mode:
		_set_mode_aware_defaults()

func _set_mode_aware_defaults():
	"""Set defaults based on current mode"""
	# Clear all selections first
	_clear_dynamic_checkboxes()
	
	# Set mode-appropriate defaults
	var current_mode = ModeManager.get_current_mode()
	match current_mode:
		"social_media":
			_select_checkbox_by_text(format_checkboxes, "Video")
			_select_checkbox_by_text(format_checkboxes, "Image(s)")
			_select_checkbox_by_text(channel_checkboxes, "Instagram")
		"creative_writing":
			_select_checkbox_by_text(format_checkboxes, "Novel Chapter")
			_select_checkbox_by_text(channel_checkboxes, "Writing Portfolio")
		"academic_writing":
			_select_checkbox_by_text(format_checkboxes, "Research Paper")
			_select_checkbox_by_text(channel_checkboxes, "Academic Journal")

func _select_checkbox_by_text(checkboxes: Array[CheckBox], text: String):
	"""Helper to select a checkbox by its text"""
	for checkbox in checkboxes:
		if checkbox.text == text:
			checkbox.button_pressed = true
			break

func _clear_dynamic_checkboxes():
	"""Clear all dynamic checkbox selections"""
	for checkbox in format_checkboxes:
		checkbox.button_pressed = false
	for checkbox in channel_checkboxes:
		checkbox.button_pressed = false

func show_add_dialog():
	"""Show dialog for adding a new task"""
	is_edit_mode = false
	editing_task = null
	title = "Add New Task"
	_clear_fields()
	_set_default_values()
	popup_centered()

func show_edit_dialog(task: WorkplanTask):
	"""Show dialog for editing an existing task"""
	is_edit_mode = true
	editing_task = task
	title = "Edit Task"
	_populate_fields(task)
	popup_centered()
	# Deferred second pass: ensures Calendar LineEdits keep saved YYYY-MM-DD values.
	call_deferred("_populate_calendar_date_fields", task)


func _ymd_only(raw: String) -> String:
	"""Normalize stored date/datetime strings to YYYY-MM-DD for LineEdit fields."""
	var cleaned: String = raw.strip_edges()
	if cleaned.is_empty():
		return ""
	if cleaned.contains("T"):
		cleaned = cleaned.split("T")[0]
	if cleaned.contains(" "):
		cleaned = cleaned.split(" ")[0]
	if cleaned.length() >= 10:
		return cleaned.substr(0, 10)
	return cleaned


func _populate_calendar_date_fields(task: WorkplanTask) -> void:
	"""Prefill publish / start / deadline so placeholders are never left over saved values."""
	if task == null:
		return
	if deadline_edit:
		deadline_edit.text = _ymd_only(task.deadline)
	if publish_date_edit:
		publish_date_edit.text = _ymd_only(task.publish_date)
	if publish_time_edit:
		publish_time_edit.text = task.publish_time.strip_edges()
	if publish_timezone_edit:
		publish_timezone_edit.text = task.publish_timezone.strip_edges()
	if scheduled_edit:
		# UI label is "Start date"; prefer start_date, fall back to scheduled_date.
		var start_raw: String = task.start_date if not task.start_date.strip_edges().is_empty() else task.scheduled_date
		scheduled_edit.text = _ymd_only(start_raw)


func _on_task_dialog_tab_changed(tab_index: int) -> void:
	if editing_task == null:
		return
	var tabs: TabContainer = $ScrollContainer/VBoxContainer/TabContainer as TabContainer
	if tabs == null:
		return
	var tab_control: Control = tabs.get_tab_control(tab_index)
	if tab_control != null and String(tab_control.name) == "Calendar":
		_populate_calendar_date_fields(editing_task)


func _on_about_to_popup_refresh_dates() -> void:
	if is_edit_mode and editing_task != null:
		_populate_calendar_date_fields(editing_task)

func _clear_fields():
	"""Clear all form fields"""
	title_edit.text = ""
	core_idea_edit.text = ""
	priority_option.selected = 0
	notes_edit.text = ""
	
	# Clear dynamic format and channel checkboxes
	_clear_dynamic_checkboxes()
	
	# Clear legacy static checkboxes (for backward compatibility)
	if video_check:
		video_check.button_pressed = false
	if article_check:
		article_check.button_pressed = false
	if carousel_check:
		carousel_check.button_pressed = false
	if infographic_check:
		infographic_check.button_pressed = false
	if podcast_check:
		podcast_check.button_pressed = false
	if livestream_check:
		livestream_check.button_pressed = false
	if shorttext_check:
		shorttext_check.button_pressed = false
	if image_check:
		image_check.button_pressed = false
	if format_other_check:
		format_other_check.button_pressed = false
		if format_other_edit:
			format_other_edit.text = ""
	
	if youtube_check:
		youtube_check.button_pressed = false
	if instagram_check:
		instagram_check.button_pressed = false
	if tiktok_check:
		tiktok_check.button_pressed = false
	if facebook_check:
		facebook_check.button_pressed = false
	if twitter_check:
		twitter_check.button_pressed = false
	if linkedin_check:
		linkedin_check.button_pressed = false
	if discord_check:
		discord_check.button_pressed = false
	if channel_other_check:
		channel_other_check.button_pressed = false
		if channel_other_edit:
			channel_other_edit.text = ""
	
	# Clear cosmic instrument checkboxes
	roleplay_check.button_pressed = false
	hypothetical_check.button_pressed = false
	iterative_check.button_pressed = false
	abductive_check.button_pressed = false
	cosmic_other_check.button_pressed = false
	if cosmic_other_edit:
		cosmic_other_edit.text = ""
	
	# Clear calendar fields
	deadline_edit.text = ""
	scheduled_edit.text = ""
	publish_date_edit.text = ""
	if publish_time_edit:
		publish_time_edit.text = ""
	if publish_timezone_edit:
		publish_timezone_edit.text = ""
	recurring_option.selected = 0
	duration_spin.value = 60
	
	# Clear strategy fields
	campaign_edit.text = ""
	theme_edit.text = ""
	audience_edit.text = ""
	performance_edit.text = ""

func _set_default_values():
	"""Set default values for new tasks"""
	# Set default dates
	scheduled_edit.text = _get_formatted_date(0)  # Today
	deadline_edit.text = _get_formatted_date(7)   # 1 week
	publish_date_edit.text = _get_formatted_date(30)  # 1 month

func _core_idea_for_display(task: WorkplanTask) -> String:
	"""Prefer core_idea; fall back so imported tasks without that column still edit/save."""
	if task == null:
		return ""
	var idea: String = task.core_idea.strip_edges()
	if not idea.is_empty():
		return idea
	var draft: String = task.generated_content.strip_edges()
	if not draft.is_empty():
		return draft
	var notes_text: String = task.notes.strip_edges()
	if not notes_text.is_empty():
		# First line of notes is enough for a required core-idea field.
		var first_line: String = notes_text.split("\n")[0].strip_edges()
		if not first_line.is_empty():
			return first_line
	return task.title.strip_edges()


func _populate_fields(task: WorkplanTask):
	"""Populate dialog fields with existing task data"""
	# Ensure task properties are synced before populating
	task.sync_array_properties()
	
	title_edit.text = task.title
	core_idea_edit.text = _core_idea_for_display(task)
	notes_edit.text = task.notes
	priority_option.selected = task.priority
	_setup_assignee_options()
	if depends_on_edit:
		depends_on_edit.text = "; ".join(WorkplanDependenciesScript.normalize_ids(task.depends_on))
	if assignee_edit:
		assignee_edit.text = task.assignee
	if assignee_option:
		var matched := false
		for i in range(assignee_option.item_count):
			var meta: Variant = assignee_option.get_item_metadata(i)
			# Items 0/1 ("(none)" / custom) have null metadata — String(null) errors on Godot 4.7+.
			if meta == null:
				continue
			if str(meta) == task.assignee and not task.assignee.is_empty():
				assignee_option.selected = i
				matched = true
				break
		if not matched:
			assignee_option.selected = 1 if not task.assignee.is_empty() else 0
	if approval_log_text:
		approval_log_text.text = _format_approval_log(task.approval_log)
	_refresh_blocked_hint()
	
	# Handle formats
	for format in task.formats:
		_set_checkbox_by_text(format_checkboxes, format, true)
		_set_static_checkbox_by_text(format, true)
	
	# Handle channels
	for channel in task.channels:
		_set_checkbox_by_text(channel_checkboxes, channel, true)
		_set_static_channel_checkbox_by_text(channel, true)
	
	# Handle cosmic instruments
	for instrument in task.cosmic_instruments:
		_set_cosmic_checkbox_by_text(instrument, true)
	
	# Calendar fields (normalized YYYY-MM-DD; start_date preferred for Start date field)
	_populate_calendar_date_fields(task)
	recurring_option.selected = _get_recurring_index(task.recurring_pattern)
	duration_spin.value = task.duration_minutes
	task.migrate_content_status_from_notes()
	_set_content_status_selection(task.get_content_status())
	_set_weekday_selection(task.recurring_weekdays)
	if recurring_end_edit:
		recurring_end_edit.text = task.recurring_end_date
	
	# Strategy fields
	campaign_edit.text = task.campaign_tag
	theme_edit.text = task.content_theme
	audience_edit.text = task.target_audience
	performance_edit.text = task.performance_notes

func _set_checkbox_by_text(checkboxes: Array[CheckBox], text: String, pressed: bool):
	"""Set checkbox state by text"""
	for checkbox in checkboxes:
		if checkbox.text == text:
			checkbox.button_pressed = pressed
			break

func _set_static_checkbox_by_text(format: String, pressed: bool):
	"""Set static format checkbox state"""
	match format.to_lower():
		"video":
			if video_check: video_check.button_pressed = pressed
		"article":
			if article_check: article_check.button_pressed = pressed
		"carousel":
			if carousel_check: carousel_check.button_pressed = pressed
		"infographic":
			if infographic_check: infographic_check.button_pressed = pressed
		"podcast":
			if podcast_check: podcast_check.button_pressed = pressed
		"live stream":
			if livestream_check: livestream_check.button_pressed = pressed
		"short text":
			if shorttext_check: shorttext_check.button_pressed = pressed
		"image(s)":
			if image_check: image_check.button_pressed = pressed

func _set_static_channel_checkbox_by_text(channel: String, pressed: bool):
	"""Set static channel checkbox state"""
	match channel.to_lower():
		"youtube":
			if youtube_check: youtube_check.button_pressed = pressed
		"instagram":
			if instagram_check: instagram_check.button_pressed = pressed
		"tiktok":
			if tiktok_check: tiktok_check.button_pressed = pressed
		"facebook":
			if facebook_check: facebook_check.button_pressed = pressed
		"twitter/x":
			if twitter_check: twitter_check.button_pressed = pressed
		"linkedin":
			if linkedin_check: linkedin_check.button_pressed = pressed
		"discord":
			if discord_check: discord_check.button_pressed = pressed

func _set_cosmic_checkbox_by_text(instrument: String, pressed: bool):
	"""Set cosmic instrument checkbox state using ADR 0024 vocabulary."""
	var code: String = CosmicInstruments.canonicalize(instrument)
	match code:
		CosmicInstruments.CODE_RP:
			roleplay_check.button_pressed = pressed
		CosmicInstruments.CODE_HF:
			hypothetical_check.button_pressed = pressed
		CosmicInstruments.CODE_IR:
			iterative_check.button_pressed = pressed
		CosmicInstruments.CODE_AH:
			abductive_check.button_pressed = pressed
		_:
			if not instrument.strip_edges().is_empty() and cosmic_other_edit:
				cosmic_other_edit.text = instrument
				if cosmic_other_check:
					cosmic_other_check.button_pressed = pressed

func _get_recurring_index(pattern: String) -> int:
	"""Get index for recurring pattern"""
	match pattern.to_lower():
		"daily": return 1
		"weekly": return 2
		"monthly": return 3
		"custom": return 4
		_: return 0

func _get_formatted_date(days_offset: int) -> String:
	"""Get formatted date string with offset"""
	var _current_time = Time.get_datetime_dict_from_system()
	var timestamp = Time.get_unix_time_from_system() + (days_offset * 24 * 60 * 60)
	var date_dict = Time.get_datetime_dict_from_unix_time(timestamp)
	return "%04d-%02d-%02d" % [date_dict.year, date_dict.month, date_dict.day]

func _get_selected_formats() -> Array[String]:
	"""Get array of selected formats"""
	var formats: Array[String] = []
	
	# Get from dynamic checkboxes
	for checkbox in format_checkboxes:
		if checkbox.button_pressed:
			formats.append(checkbox.text)
	
	# Legacy support: Check static checkboxes if they exist and are selected
	if video_check and video_check.button_pressed and not formats.has("Video"): 
		formats.append("Video")
	if article_check and article_check.button_pressed and not formats.has("Article"): 
		formats.append("Article")
	if carousel_check and carousel_check.button_pressed and not formats.has("Carousel"): 
		formats.append("Carousel")
	if infographic_check and infographic_check.button_pressed and not formats.has("Infographic"): 
		formats.append("Infographic")
	if podcast_check and podcast_check.button_pressed and not formats.has("Podcast"): 
		formats.append("Podcast")
	if livestream_check and livestream_check.button_pressed and not formats.has("Live Stream"): 
		formats.append("Live Stream")
	if shorttext_check and shorttext_check.button_pressed and not formats.has("Short Text"): 
		formats.append("Short Text")
	if image_check and image_check.button_pressed and not formats.has("Image(s)"): 
		formats.append("Image(s)")
	
	if format_other_check and format_other_check.button_pressed and format_other_edit.text.strip_edges() != "":
		formats.append(format_other_edit.text.strip_edges())
	
	return formats

func _get_selected_channels() -> Array[String]:
	"""Get array of selected channels"""
	var channels: Array[String] = []
	
	# Get from dynamic checkboxes
	for checkbox in channel_checkboxes:
		if checkbox.button_pressed:
			channels.append(checkbox.text)
	
	# Legacy support: Check static checkboxes if they exist and are selected
	if youtube_check and youtube_check.button_pressed and not channels.has("YouTube"): 
		channels.append("YouTube")
	if instagram_check and instagram_check.button_pressed and not channels.has("Instagram"): 
		channels.append("Instagram")
	if tiktok_check and tiktok_check.button_pressed and not channels.has("TikTok"): 
		channels.append("TikTok")
	if facebook_check and facebook_check.button_pressed and not channels.has("Facebook"): 
		channels.append("Facebook")
	if twitter_check and twitter_check.button_pressed and not channels.has("Twitter/X"): 
		channels.append("Twitter/X")
	if linkedin_check and linkedin_check.button_pressed and not channels.has("LinkedIn"): 
		channels.append("LinkedIn")
	if discord_check and discord_check.button_pressed and not channels.has("Discord"): 
		channels.append("Discord")
	
	if channel_other_check and channel_other_check.button_pressed and channel_other_edit.text.strip_edges() != "":
		channels.append(channel_other_edit.text.strip_edges())
	
	return channels

func _get_selected_cosmic_instruments() -> Array[String]:
	"""Get array of selected cosmic instruments"""
	var instruments: Array[String] = []
	
	if roleplay_check.button_pressed:
		instruments.append("Role Play (Dimensional Shifter)")
	if hypothetical_check.button_pressed:
		instruments.append("Hypothetical Framings (Reality Benders)")
	if iterative_check.button_pressed:
		instruments.append("Iterative Refinement (Gravitational Drift)")
	if abductive_check.button_pressed:
		instruments.append("Abductive Hypothesis Generation (Quantum Reasoning)")
	
	if cosmic_other_check.button_pressed and cosmic_other_edit.text.strip_edges() != "":
		instruments.append(cosmic_other_edit.text.strip_edges())
	
	return instruments

func _get_recurring_pattern() -> String:
	"""Get selected recurring pattern"""
	match recurring_option.selected:
		1: return "Daily"
		2: return "Weekly"
		3: return "Monthly"
		4: return "Custom"
		_: return "None"


func _set_content_status_selection(status_id: String) -> void:
	if content_status_option == null:
		return
	var cleaned: String = status_id.strip_edges().to_lower()
	var idx: int = WorkplanTask.CONTENT_STATUSES.find(cleaned)
	if idx < 0:
		idx = 0
	content_status_option.selected = idx


func _get_selected_content_status() -> String:
	if content_status_option == null or content_status_option.selected < 0:
		return "draft"
	return content_status_option.get_item_text(content_status_option.selected)


func _set_weekday_selection(weekdays: Array) -> void:
	var boxes: Array = [
		weekday_mon, weekday_tue, weekday_wed, weekday_thu, weekday_fri, weekday_sat, weekday_sun
	]
	for i in range(boxes.size()):
		var box: CheckBox = boxes[i] as CheckBox
		if box:
			box.button_pressed = weekdays.has(i)


func _get_selected_weekdays() -> Array[int]:
	var selected: Array[int] = []
	var boxes: Array = [
		weekday_mon, weekday_tue, weekday_wed, weekday_thu, weekday_fri, weekday_sat, weekday_sun
	]
	for i in range(boxes.size()):
		var box: CheckBox = boxes[i] as CheckBox
		if box and box.button_pressed:
			selected.append(i)
	return selected


func _on_expand_recurrence_pressed() -> void:
	"""Stamp weekly recurrence on the editing/new task and expand into the workplan."""
	const RecurrenceScript = preload("res://readymade/scripts/workplan_recurrence.gd")
	var task: WorkplanTask = editing_task if (is_edit_mode and editing_task) else WorkplanTask.new()
	if title_edit.text.strip_edges().is_empty():
		_show_error_dialog("Enter a title before expanding recurrence.")
		return
	task.title = title_edit.text.strip_edges()
	task.core_idea = core_idea_edit.text.strip_edges()
	task.publish_date = publish_date_edit.text.strip_edges()
	task.channel = ""
	var channels_sel: Array[String] = _get_selected_channels()
	if not channels_sel.is_empty():
		task.channel = channels_sel[0]
		task.channels = channels_sel
	task.campaign_tag = campaign_edit.text
	task.content_theme = theme_edit.text
	task.set_content_status(_get_selected_content_status())
	RecurrenceScript.apply_weekly_to_task(task, _get_selected_weekdays(), recurring_end_edit.text if recurring_end_edit else "")
	task.recurring_pattern = "weekly"
	var manager: Node = get_node_or_null("/root/WorkplanManager")
	var workplan: Workplan = null
	if manager != null and manager.has_method("get_current_workplan"):
		workplan = manager.get_current_workplan() as Workplan
	if workplan == null:
		_show_error_dialog("No current workplan to expand into.")
		return
	var added: int = RecurrenceScript.expand_into_workplan(workplan, task)
	if manager.has_method("save_current_workplan"):
		manager.save_current_workplan()
	recurrence_expand_requested.emit(task, added)
	print("TaskDialog: expanded recurrence into %d dated tasks" % added)

func _on_confirmed():
	"""Handle dialog confirmation"""
	# Validate required fields
	if title_edit.text.strip_edges() == "":
		_show_error_dialog("Please enter a task title.")
		return
	
	var idea_text: String = core_idea_edit.text.strip_edges()
	if idea_text.is_empty() and is_edit_mode and editing_task != null:
		# Imported tasks may lack core_idea; keep a stable fallback so unedited OK works.
		idea_text = _core_idea_for_display(editing_task)
		if core_idea_edit and idea_text:
			core_idea_edit.text = idea_text
	if idea_text.is_empty():
		_show_error_dialog("Please enter a core idea for the task.")
		return
	
	# Create or update task
	var task: WorkplanTask
	if is_edit_mode and editing_task:
		task = editing_task
	else:
		task = WorkplanTask.new()
	
	# Populate task data
	task.title = title_edit.text.strip_edges()
	task.core_idea = idea_text
	task.notes = notes_edit.text
	task.priority = priority_option.selected
	task.formats = _get_selected_formats()
	task.channels = _get_selected_channels()
	task.cosmic_instruments = _get_selected_cosmic_instruments()
	# Prefer LineEdit values; never wipe a saved date with an empty field (placeholder-only).
	var deadline_text: String = _ymd_only(deadline_edit.text) if deadline_edit else ""
	var start_text: String = _ymd_only(scheduled_edit.text) if scheduled_edit else ""
	var publish_text: String = _ymd_only(publish_date_edit.text) if publish_date_edit else ""
	if not deadline_text.is_empty() or not is_edit_mode:
		task.deadline = deadline_text
	if not start_text.is_empty() or not is_edit_mode:
		task.start_date = start_text
		task.scheduled_date = start_text
	if not publish_text.is_empty() or not is_edit_mode:
		task.publish_date = publish_text
	if publish_time_edit:
		var time_text: String = publish_time_edit.text.strip_edges()
		if not time_text.is_empty() or not is_edit_mode:
			task.publish_time = time_text
	if publish_timezone_edit:
		var zone_text: String = publish_timezone_edit.text.strip_edges()
		if not zone_text.is_empty() or not is_edit_mode:
			task.publish_timezone = zone_text
	task.recurring_pattern = _get_recurring_pattern()
	task.recurring_weekdays = _get_selected_weekdays()
	if recurring_end_edit:
		task.recurring_end_date = recurring_end_edit.text.strip_edges()
	task.duration_minutes = int(duration_spin.value)
	task.estimated_duration = int(duration_spin.value)  # Sync both duration fields
	task.campaign_tag = campaign_edit.text
	task.content_theme = theme_edit.text
	task.target_audience = audience_edit.text
	task.performance_notes = performance_edit.text
	task.set_content_status(_get_selected_content_status())
	var dep_raw: String = depends_on_edit.text if depends_on_edit else ""
	var workplan: Workplan = _current_workplan()
	task.ensure_task_id()
	if workplan != null and WorkplanDependenciesScript.would_create_cycle(task.task_id, dep_raw, workplan):
		_show_error_dialog("That depends_on list would create a cycle. Clear or change predecessors.")
		return
	WorkplanDependenciesScript.set_depends_on(task, dep_raw)
	task.assignee = _get_selected_assignee()
	
	# Sync legacy properties for backward compatibility
	task.sync_legacy_properties()
	
	# Emit signal and close
	if is_edit_mode:
		task_updated.emit(task)
	else:
		task_created.emit(task)
	
	hide()

func _show_error_dialog(message: String):
	"""Show error dialog"""
	print("Error: " + message)

# "Other" checkbox handlers
func _on_format_other_check_toggled(toggled_on: bool):
	if format_other_edit:
		format_other_edit.editable = toggled_on
		if not toggled_on:
			format_other_edit.text = ""

func _on_channel_other_check_toggled(toggled_on: bool):
	if channel_other_edit:
		channel_other_edit.editable = toggled_on
		if not toggled_on:
			channel_other_edit.text = ""

func _on_cosmic_other_check_toggled(toggled_on: bool):
	if cosmic_other_edit:
		cosmic_other_edit.editable = toggled_on
		if not toggled_on:
			cosmic_other_edit.text = ""

# Date button handlers
func _on_deadline_today_pressed():
	deadline_edit.text = _get_formatted_date(0)

func _on_deadline_week_pressed():
	deadline_edit.text = _get_formatted_date(7)

func _on_deadline_month_pressed():
	deadline_edit.text = _get_formatted_date(30)

func _on_scheduled_today_pressed():
	scheduled_edit.text = _get_formatted_date(0)

func _on_scheduled_tomorrow_pressed():
	scheduled_edit.text = _get_formatted_date(1)

func _on_scheduled_week_pressed():
	scheduled_edit.text = _get_formatted_date(7)

func _on_publish_week_pressed():
	publish_date_edit.text = _get_formatted_date(7)

func _on_publish_month_pressed():
	publish_date_edit.text = _get_formatted_date(30)

# Signals
signal task_created(task: WorkplanTask)
signal task_updated(task: WorkplanTask) 
