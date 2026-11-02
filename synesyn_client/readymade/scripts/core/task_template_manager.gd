extends Node

## Task Template Manager - Provides mode-specific task templates
## Integrates with ModeManager to offer relevant templates for each work mode

const WorkplanTaskScript = preload("res://readymade/data/workplan_task.gd")

# Template definition class
class TaskTemplate:
	var id: String
	var name: String
	var description: String
	var mode: String
	var default_values: Dictionary
	
	func _init(p_id: String = "", p_name: String = "", p_desc: String = "", p_mode: String = "", p_defaults: Dictionary = {}):
		id = p_id
		name = p_name
		description = p_desc
		mode = p_mode
		default_values = p_defaults

# Template storage
var templates: Dictionary = {}

func _ready():
	_setup_default_templates()
	print("TaskTemplateManager: Initialized with ", templates.size(), " templates")

func _setup_default_templates():
	"""Initialize default task templates for each mode"""
	_setup_social_media_templates()
	_setup_creative_writing_templates()
	_setup_academic_writing_templates()

func _setup_social_media_templates():
	"""Setup templates for social media mode"""
	
	# Instagram Post Template
	templates["instagram_post"] = TaskTemplate.new(
		"instagram_post",
		"Instagram Post",
		"Create an engaging Instagram post with visual content",
		"social_media",
		{
			"format": "Image",
			"channels": "Instagram",
			"cosmic_instruments": "Role-Play",
			"estimated_duration": 30,
			"target_audience": "General followers",
			"priority": 1
		}
	)
	
	# Twitter Thread Template
	templates["twitter_thread"] = TaskTemplate.new(
		"twitter_thread",
		"Twitter Thread",
		"Create a multi-tweet thread on a specific topic",
		"social_media",
		{
			"format": "Short Text",
			"channels": "Twitter",
			"cosmic_instruments": "Iterative",
			"estimated_duration": 45,
			"target_audience": "Twitter followers",
			"priority": 1
		}
	)
	
	# Content Calendar Entry
	templates["content_calendar"] = TaskTemplate.new(
		"content_calendar",
		"Content Calendar Entry",
		"Plan and schedule content for multiple platforms",
		"social_media",
		{
			"format": "Article",
			"channels": "Multiple",
			"cosmic_instruments": "Hypothetical",
			"estimated_duration": 60,
			"target_audience": "Cross-platform audience",
			"priority": 2
		}
	)
	
	# Hashtag Research
	templates["hashtag_research"] = TaskTemplate.new(
		"hashtag_research",
		"Hashtag Research",
		"Research and compile relevant hashtags for campaign",
		"social_media",
		{
			"format": "Other: Hashtag List",
			"channels": "Multiple",
			"cosmic_instruments": "Abductive",
			"estimated_duration": 90,
			"target_audience": "Target demographics",
			"priority": 0
		}
	)

func _setup_creative_writing_templates():
	"""Setup templates for creative writing mode"""
	
	# Character Profile
	templates["character_profile"] = TaskTemplate.new(
		"character_profile",
		"Character Profile",
		"Develop a detailed character profile with background and motivations",
		"creative_writing",
		{
			"core_idea": "Character development for story",
			"notes": "Include: background, personality, goals, conflicts, appearance",
			"estimated_duration": 120,
			"priority": 2
		}
	)
	
	# Scene Draft
	templates["scene_draft"] = TaskTemplate.new(
		"scene_draft",
		"Scene Draft",
		"Write a complete scene with dialogue and action",
		"creative_writing",
		{
			"core_idea": "Scene writing",
			"notes": "Focus on: dialogue, pacing, sensory details, character interaction",
			"estimated_duration": 180,
			"priority": 2
		}
	)
	
	# Chapter Outline
	templates["chapter_outline"] = TaskTemplate.new(
		"chapter_outline",
		"Chapter Outline",
		"Create detailed outline for a chapter or story section",
		"creative_writing",
		{
			"core_idea": "Story structure planning",
			"notes": "Include: plot points, character arcs, themes, transitions",
			"estimated_duration": 90,
			"priority": 1
		}
	)
	
	# Plot Development
	templates["plot_development"] = TaskTemplate.new(
		"plot_development",
		"Plot Development",
		"Develop main plot points and story structure",
		"creative_writing",
		{
			"core_idea": "Overall story arc development",
			"notes": "Focus on: conflict, resolution, pacing, character growth",
			"estimated_duration": 240,
			"priority": 3
		}
	)

func _setup_academic_writing_templates():
	"""Setup templates for academic writing mode"""
	
	# Research Note
	templates["research_note"] = TaskTemplate.new(
		"research_note",
		"Research Note",
		"Document findings from academic sources with citations",
		"academic_writing",
		{
			"core_idea": "Research documentation",
			"notes": "Include: source details, key findings, personal analysis, citations",
			"estimated_duration": 60,
			"priority": 1
		}
	)
	
	# Literature Review Section
	templates["literature_review"] = TaskTemplate.new(
		"literature_review",
		"Literature Review Section",
		"Write a section of literature review with critical analysis",
		"academic_writing",
		{
			"core_idea": "Literature analysis and synthesis",
			"notes": "Include: source comparison, gaps identified, theoretical framework",
			"estimated_duration": 300,
			"priority": 3
		}
	)
	
	# Citation Check
	templates["citation_check"] = TaskTemplate.new(
		"citation_check",
		"Citation Check",
		"Review and verify all citations for accuracy and format",
		"academic_writing",
		{
			"core_idea": "Citation verification and formatting",
			"notes": "Check: format consistency, source accuracy, reference completeness",
			"estimated_duration": 90,
			"priority": 1
		}
	)
	
	# Thesis Section
	templates["thesis_section"] = TaskTemplate.new(
		"thesis_section",
		"Thesis Section",
		"Write a major section of thesis or research paper",
		"academic_writing",
		{
			"core_idea": "Academic writing with rigorous analysis",
			"notes": "Include: clear argument, evidence support, scholarly tone, proper citations",
			"estimated_duration": 480,
			"priority": 3
		}
	)

func get_templates_for_mode(mode_key: String) -> Array[TaskTemplate]:
	"""Get all templates for a specific mode"""
	var mode_templates: Array[TaskTemplate] = []
	
	for template_id in templates:
		var template = templates[template_id]
		if template.mode == mode_key:
			mode_templates.append(template)
	
	return mode_templates

func get_current_mode_templates() -> Array[TaskTemplate]:
	"""Get templates for the current mode"""
	if not ModeManager:
		return []
	
	return get_templates_for_mode(ModeManager.get_current_mode())

func get_template(template_id: String) -> TaskTemplate:
	"""Get a specific template by ID"""
	if template_id in templates:
		return templates[template_id]
	else:
		push_error("TaskTemplateManager: Unknown template ID: " + template_id)
		return null

func create_task_from_template(template_id: String, custom_title: String = ""):
	"""Create a new WorkplanTask from a template"""
	var template = get_template(template_id)
	if not template:
		return null
	
	var task = WorkplanTask.new()
	
	# Set basic info
	task.title = custom_title if not custom_title.is_empty() else template.name
	task.core_idea = template.default_values.get("core_idea", template.description)
	task.notes = template.default_values.get("notes", "")
	task.priority = template.default_values.get("priority", 1)
	
	# Set mode-specific fields based on template
	match template.mode:
		"social_media":
			_apply_social_media_template(task, template)
		"creative_writing":
			_apply_creative_writing_template(task, template)
		"academic_writing":
			_apply_academic_writing_template(task, template)
	
	# Set common fields
	task.estimated_duration = template.default_values.get("estimated_duration", 60)
	task.status = "Not Started"
	
	# Set default deadline (1 week from now)
	var _now = Time.get_datetime_dict_from_system()
	var deadline_time = Time.get_unix_time_from_system() + (7 * 24 * 60 * 60)  # 7 days
	var deadline_dict = Time.get_datetime_dict_from_unix_time(deadline_time)
	task.deadline = "%04d-%02d-%02d" % [deadline_dict.year, deadline_dict.month, deadline_dict.day]
	
	print("TaskTemplateManager: Created task from template '", template_id, "' with title '", task.title, "'")
	
	return task

func _apply_social_media_template(task, template: TaskTemplate):
	"""Apply social media specific template values"""
	# Handle legacy single format
	task.format = template.default_values.get("format", "")
	
	# Handle new array properties - convert strings to arrays if needed
	var channels_value = template.default_values.get("channels", "")
	if channels_value is String and not channels_value.is_empty():
		task.channels = [channels_value]
	elif channels_value is Array:
		task.channels = channels_value
	else:
		task.channels = []
	
	var cosmic_value = template.default_values.get("cosmic_instruments", "")
	if cosmic_value is String and not cosmic_value.is_empty():
		task.cosmic_instruments = [cosmic_value]
	elif cosmic_value is Array:
		task.cosmic_instruments = cosmic_value
	else:
		task.cosmic_instruments = []
	
	# Handle formats array
	var formats_value = template.default_values.get("formats", "")
	if formats_value is String and not formats_value.is_empty():
		task.formats = [formats_value]
	elif formats_value is Array:
		task.formats = formats_value
	elif not task.format.is_empty():
		task.formats = [task.format]
	else:
		task.formats = []
	
	task.target_audience = template.default_values.get("target_audience", "")

func _apply_creative_writing_template(task, template: TaskTemplate):
	"""Apply creative writing specific template values"""
	# Handle legacy single properties
	task.format = template.default_values.get("format", "")
	task.channel = template.default_values.get("channel", "")
	task.cosmic_instrument = template.default_values.get("cosmic_instrument", "")
	
	# Initialize array properties for creative writing
	var formats_value = template.default_values.get("formats", "")
	if formats_value is Array:
		task.formats = formats_value
	elif formats_value is String and not formats_value.is_empty():
		task.formats = [formats_value]
	elif not task.format.is_empty():
		task.formats = [task.format]
	else:
		task.formats = []
	
	var channels_value = template.default_values.get("channels", "")
	if channels_value is Array:
		task.channels = channels_value
	elif channels_value is String and not channels_value.is_empty():
		task.channels = [channels_value]
	elif not task.channel.is_empty():
		task.channels = [task.channel]
	else:
		task.channels = []
	
	var cosmic_value = template.default_values.get("cosmic_instruments", "")
	if cosmic_value is Array:
		task.cosmic_instruments = cosmic_value
	elif cosmic_value is String and not cosmic_value.is_empty():
		task.cosmic_instruments = [cosmic_value]
	elif not task.cosmic_instrument.is_empty():
		task.cosmic_instruments = [task.cosmic_instrument]
	else:
		task.cosmic_instruments = []

func _apply_academic_writing_template(task, template: TaskTemplate):
	"""Apply academic writing specific template values"""
	# Handle legacy single properties
	task.format = template.default_values.get("format", "")
	task.channel = template.default_values.get("channel", "")
	task.cosmic_instrument = template.default_values.get("cosmic_instrument", "")
	
	# Initialize array properties for academic writing
	var formats_value = template.default_values.get("formats", "")
	if formats_value is Array:
		task.formats = formats_value
	elif formats_value is String and not formats_value.is_empty():
		task.formats = [formats_value]
	elif not task.format.is_empty():
		task.formats = [task.format]
	else:
		task.formats = []
	
	var channels_value = template.default_values.get("channels", "")
	if channels_value is Array:
		task.channels = channels_value
	elif channels_value is String and not channels_value.is_empty():
		task.channels = [channels_value]
	elif not task.channel.is_empty():
		task.channels = [task.channel]
	else:
		task.channels = []
	
	var cosmic_value = template.default_values.get("cosmic_instruments", "")
	if cosmic_value is Array:
		task.cosmic_instruments = cosmic_value
	elif cosmic_value is String and not cosmic_value.is_empty():
		task.cosmic_instruments = [cosmic_value]
	elif not task.cosmic_instrument.is_empty():
		task.cosmic_instruments = [task.cosmic_instrument]
	else:
		task.cosmic_instruments = []

func get_template_names_for_mode(mode_key: String) -> Array[String]:
	"""Get template names for a specific mode (for UI dropdowns)"""
	var names: Array[String] = []
	var mode_templates = get_templates_for_mode(mode_key)
	
	for template in mode_templates:
		names.append(template.name)
	
	return names

func get_template_by_name(template_name: String, mode_key: String = "") -> TaskTemplate:
	"""Get template by display name, optionally filtered by mode"""
	for template_id in templates:
		var template = templates[template_id]
		if template.name == template_name:
			if mode_key.is_empty() or template.mode == mode_key:
				return template
	
	return null 
