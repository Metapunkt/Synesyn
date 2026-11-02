extends Window
class_name TaskDialog

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
@onready var notes_edit: TextEdit = $"ScrollContainer/VBoxContainer/TabContainer/BasicInfo/BasicInfoVBox/NotesContainer/NotesEdit"

# Calendar tab
@onready var deadline_edit: LineEdit = $"ScrollContainer/VBoxContainer/TabContainer/Calendar/CalendarVBox/DeadlineContainer/DeadlineRow/DeadlineEdit"
@onready var scheduled_edit: LineEdit = $"ScrollContainer/VBoxContainer/TabContainer/Calendar/CalendarVBox/ScheduledContainer/ScheduledRow/ScheduledEdit"
@onready var publish_date_edit: LineEdit = $"ScrollContainer/VBoxContainer/TabContainer/Calendar/CalendarVBox/PublishContainer/PublishRow/PublishEdit"
@onready var recurring_option: OptionButton = $"ScrollContainer/VBoxContainer/TabContainer/Calendar/CalendarVBox/RecurringContainer/RecurringOption"
@onready var duration_spin: SpinBox = $"ScrollContainer/VBoxContainer/TabContainer/Calendar/CalendarVBox/DurationContainer/DurationSpin"

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
	_collect_static_checkboxes()
	_setup_mode_aware_options()
	
	# Connect to mode changes
	if ModeManager:
		ModeManager.mode_changed.connect(_on_mode_changed)
	
	# Connect filter toggle signals
	format_filter_toggle.toggled.connect(_on_format_filter_toggled)
	channel_filter_toggle.toggled.connect(_on_channel_filter_toggled)

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
	"""Create channel checkboxes based on current mode"""
	# Clear existing channel checkboxes
	for checkbox in channel_checkboxes:
		if checkbox and is_instance_valid(checkbox):
			checkbox.queue_free()
	channel_checkboxes.clear()
	
	# Get current mode channels
	var channels = ModeManager.get_current_channels()
	
	# Create new channel checkboxes
	for channel_name in channels:
		var checkbox = CheckBox.new()
		checkbox.text = channel_name
		checkbox.name = channel_name.replace(" ", "").replace("/", "") + "Check"
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
	"""Create channel checkboxes from ALL modes"""
	# Clear existing channel checkboxes
	for checkbox in channel_checkboxes:
		if checkbox and is_instance_valid(checkbox):
			checkbox.queue_free()
	channel_checkboxes.clear()
	
	# Get channels from all modes
	var all_channels: Array[String] = []
	var all_modes = ModeManager.get_available_modes()
	
	for mode_id in all_modes:
		var mode_config = ModeManager.get_mode_config(mode_id)
		var mode_channels = mode_config.channels
		for channel in mode_channels:
			if not all_channels.has(channel):
				all_channels.append(channel)
	
	# Create channel checkboxes for all options
	for channel_name in all_channels:
		var checkbox = CheckBox.new()
		checkbox.text = channel_name
		checkbox.name = channel_name.replace(" ", "").replace("/", "") + "Check"
		channels_grid.add_child(checkbox)
		channel_checkboxes.append(checkbox)

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

func _populate_fields(task: WorkplanTask):
	"""Populate dialog fields with existing task data"""
	# Ensure task properties are synced before populating
	task.sync_array_properties()
	
	title_edit.text = task.title
	core_idea_edit.text = task.core_idea
	notes_edit.text = task.notes
	priority_option.selected = task.priority
	
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
	
	# Calendar fields
	deadline_edit.text = task.deadline
	scheduled_edit.text = task.scheduled_date
	publish_date_edit.text = task.publish_date
	recurring_option.selected = _get_recurring_index(task.recurring_pattern)
	duration_spin.value = task.duration_minutes
	
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
	"""Set cosmic instrument checkbox state"""
	match instrument.to_lower():
		"role play (dimensional shifter)":
			roleplay_check.button_pressed = pressed
		"hypothetical framings (reality benders)":
			hypothetical_check.button_pressed = pressed
		"iterative refinement (gravitational drift)":
			iterative_check.button_pressed = pressed
		"abductive hypothesis generation (quantum reasoning)":
			abductive_check.button_pressed = pressed

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

func _on_confirmed():
	"""Handle dialog confirmation"""
	# Validate required fields
	if title_edit.text.strip_edges() == "":
		_show_error_dialog("Please enter a task title.")
		return
	
	if core_idea_edit.text.strip_edges() == "":
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
	task.core_idea = core_idea_edit.text.strip_edges()
	task.notes = notes_edit.text
	task.priority = priority_option.selected
	task.formats = _get_selected_formats()
	task.channels = _get_selected_channels()
	task.cosmic_instruments = _get_selected_cosmic_instruments()
	task.deadline = deadline_edit.text
	task.scheduled_date = scheduled_edit.text
	task.publish_date = publish_date_edit.text
	task.recurring_pattern = _get_recurring_pattern()
	task.duration_minutes = int(duration_spin.value)
	task.estimated_duration = int(duration_spin.value)  # Sync both duration fields
	task.campaign_tag = campaign_edit.text
	task.content_theme = theme_edit.text
	task.target_audience = audience_edit.text
	task.performance_notes = performance_edit.text
	
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
