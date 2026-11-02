extends Node

## ReadyMade Mode Manager - Handles switching between different work modes
## This singleton manages mode configurations and notifies UI components of mode changes

signal mode_changed(new_mode: String)

# Mode configuration class
class ModeConfig:
	var name: String
	var icon: String
	var default_task_templates: Array[String]
	var ai_prompt_prefix: String
	var content_viewer_priorities: Array[String]
	var formats: Array[String]
	var channels: Array[String]
	
	func _init(p_name: String = "", p_icon: String = "", p_templates: Array[String] = [], p_prompt: String = "", p_priorities: Array[String] = [], p_formats: Array[String] = [], p_channels: Array[String] = []):
		name = p_name
		icon = p_icon
		default_task_templates = p_templates
		ai_prompt_prefix = p_prompt
		content_viewer_priorities = p_priorities
		formats = p_formats
		channels = p_channels

# Available modes
var mode_configs: Dictionary = {}
var current_mode: String = "social_media"

func _ready():
	print("ModeManager: Initializing...")
	_setup_default_modes()
	_load_user_preference()
	print("ModeManager: Ready with mode: %s" % current_mode)

func _setup_default_modes():
	"""Initialize the default mode configurations"""
	mode_configs["social_media"] = ModeConfig.new(
		"Social Media Focus",
		"📱",
		["instagram_post", "twitter_thread", "content_calendar", "hashtag_research"],
		"You are a social media expert focused on creating engaging, viral content. Emphasize platform-specific formats, trends, and audience engagement.",
		["character_count", "platform_optimization", "hashtag_analysis", "engagement_metrics"],
		[
			"Video",
			"Image(s)",
			"Carousel",
			"Short Text",
			"Live Stream",
			"Stories",
			"Reels",
			"Infographic"
		],
		[
			"Instagram",
			"TikTok",
			"YouTube",
			"Twitter/X",
			"Facebook", 
			"LinkedIn",
			"Snapchat",
			"Pinterest"
		]
	)
	
	mode_configs["creative_writing"] = ModeConfig.new(
		"Creative Writing Focus",
		"🎭",
		["character_profile", "scene_draft", "chapter_outline", "plot_development"],
		"You are a creative writing coach focused on storytelling, character development, and narrative craft. Emphasize literary techniques, emotional depth, and narrative structure.",
		["reading_time", "dialogue_analysis", "pacing_metrics", "character_focus"],
		[
			"Novel Chapter",
			"Short Story",
			"Script/Screenplay",
			"Poetry",
			"Blog Post",
			"Character Profile",
			"Scene Outline",
			"Dialogue"
		],
		[
			"Publishing Platform",
			"Literary Blog",
			"Writing Portfolio",
			"Medium",
			"Wattpad",
			"AO3 (Archive of Our Own)",
			"Goodreads",
			"Literary Journal"
		]
	)
	
	mode_configs["academic_writing"] = ModeConfig.new(
		"Academic Writing Focus",
		"🎓",
		["research_note", "literature_review", "citation_check", "thesis_section"],
		"You are an academic writing assistant focused on scholarly rigor, proper citation, and clear argumentation. Emphasize evidence-based reasoning, academic conventions, and formal structure.",
		["citation_count", "academic_tone", "argument_structure", "evidence_quality"],
		[
			"Research Paper",
			"Literature Review",
			"Thesis Chapter",  
			"Conference Abstract",
			"Journal Article",
			"Research Proposal",
			"Citation Analysis",
			"Academic Blog Post"
		],
		[
			"Academic Journal",
			"Conference Proceedings",
			"University Repository",
			"ResearchGate",
			"Academia.edu",
			"ORCID Profile",
			"Institutional Website",
			"Peer Review Platform"
		]
	)

func get_available_modes() -> Array[String]:
	"""Get list of available mode keys"""
	var modes: Array[String] = []
	for key in mode_configs.keys():
		modes.append(key)
	return modes

func get_mode_config(mode_key: String) -> ModeConfig:
	"""Get configuration for a specific mode"""
	if mode_key in mode_configs:
		return mode_configs[mode_key]
	else:
		push_error("ModeManager: Unknown mode '%s', falling back to social_media" % mode_key)
		return mode_configs["social_media"]

func get_current_config() -> ModeConfig:
	"""Get current mode configuration"""
	return get_mode_config(current_mode)

func set_mode(mode_key: String):
	"""Change the current mode"""
	if mode_key == current_mode:
		return # No change needed
	
	if mode_key not in mode_configs:
		push_error("ModeManager: Cannot set unknown mode '%s'" % mode_key)
		return
	
	var old_mode = current_mode
	current_mode = mode_key
	
	print("ModeManager: Mode changed from '%s' to '%s'" % [old_mode, current_mode])
	
	# Save preference and emit signal
	_save_user_preference()
	mode_changed.emit(current_mode)

func get_current_mode() -> String:
	"""Get current mode key"""
	return current_mode

func _load_user_preference():
	"""Load user's preferred mode from project settings"""
	if ProjectSettings.has_setting("readymade/default_mode"):
		var saved_mode = ProjectSettings.get_setting("readymade/default_mode", "social_media")
		if saved_mode in mode_configs:
			current_mode = saved_mode
			print("ModeManager: Loaded user preference: %s" % current_mode)
		else:
			print("ModeManager: Invalid saved mode '%s', using default" % saved_mode)

func _save_user_preference():
	"""Save current mode as user preference"""
	ProjectSettings.set_setting("readymade/default_mode", current_mode)
	var err = ProjectSettings.save()
	if err != OK:
		push_error("ModeManager: Failed to save user preference: %s" % err)
	else:
		print("ModeManager: Saved user preference: %s" % current_mode)

func get_current_content_viewer_priorities() -> Array[String]:
	"""Get content viewer priorities for current mode"""
	return get_current_config().content_viewer_priorities

func get_current_formats() -> Array[String]:
	"""Get available formats for current mode"""
	return get_current_config().formats

func get_current_channels() -> Array[String]:
	"""Get available channels for current mode"""
	return get_current_config().channels 
