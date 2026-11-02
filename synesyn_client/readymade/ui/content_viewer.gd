extends Control
class_name ContentViewer
## Content viewer for displaying and editing completed tasks with rich formatting

const WorkplanTaskScript = preload("res://readymade/data/workplan_task.gd")

# UI Components
@onready var content_tabs: TabContainer = $VBoxContainer/ContentTabs
@onready var task_selector: OptionButton = $VBoxContainer/HeaderContainer/TaskSelector
@onready var refresh_button: Button = $VBoxContainer/HeaderContainer/RefreshButton
@onready var export_button: Button = $VBoxContainer/HeaderContainer/ExportButton
@onready var close_tab_button: Button = $VBoxContainer/HeaderContainer/CloseTabButton
@onready var export_dialog: FileDialog = $VBoxContainer/ExportDialog

# Content display components (will be created dynamically)
var current_tasks: Array = []
var open_tabs: Dictionary = {}  # task_title -> tab_index

signal task_selected(task: WorkplanTask)
signal content_modified(task: WorkplanTask, new_content: String)

func _ready():
	_setup_ui()
	_connect_signals()

func _setup_ui():
	"""Initialize the content viewer UI"""
	# Setup header controls
	if refresh_button:
		refresh_button.text = "🔄 Refresh"
		refresh_button.tooltip_text = "Refresh completed tasks list"
	
	if export_button:
		export_button.text = "📤 Export"
		export_button.tooltip_text = "Export current content to file"
	
	if export_dialog:
		export_dialog.title = "Export Content"
		export_dialog.access = FileDialog.ACCESS_FILESYSTEM
		export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		export_dialog.filters = PackedStringArray([
			"*.md ; Markdown Document",
			"*.html ; HTML Document",
			"*.txt ; Plain Text File",
			"*.json ; JSON Data File"
		])

	if close_tab_button:
		close_tab_button.text = "❌ Close Tab"
		close_tab_button.tooltip_text = "Close current tab"
	
	if task_selector:
		task_selector.tooltip_text = "Select a completed task to view"
	
	# Setup content tabs
	if content_tabs:
		# Enable tab close buttons (Godot 4 default behavior)
		pass

func _connect_signals():
	"""Connect UI signals"""
	if refresh_button:
		refresh_button.pressed.connect(_on_refresh_pressed)
	
	if export_button:
		export_button.pressed.connect(_on_export_pressed)
	
	if close_tab_button:
		close_tab_button.pressed.connect(_on_close_tab_pressed)
	
	if task_selector:
		task_selector.item_selected.connect(_on_task_selected)
	
	if content_tabs:
		content_tabs.tab_selected.connect(_on_tab_selected)
		
	if export_dialog:
		export_dialog.file_selected.connect(_on_file_selected)

func load_completed_tasks(tasks: Array):
	"""Load completed tasks into the selector"""
	print("ContentViewer: load_completed_tasks called with ", tasks.size(), " tasks")
	current_tasks.clear()
	
	# Filter for tasks with generated content (any status)
	for task in tasks:
		if not task.generated_content.is_empty():
			current_tasks.append(task)
			print("ContentViewer: Added task: ", task.title, " (", task.status, ")")
		else:
			print("ContentViewer: Skipped task: ", task.title, " (status: ", task.status, ", has_content: ", not task.generated_content.is_empty(), ")")
	
	print("ContentViewer: Final task count: ", current_tasks.size())
	_update_task_selector()

func _update_task_selector():
	"""Update the task selector dropdown"""
	if not task_selector:
		return
	
	task_selector.clear()
	task_selector.add_item("Select a completed task...")
	
	for i in range(current_tasks.size()):
		var task = current_tasks[i]
		var item_text = "%s (%s)" % [task.title, task.format]
		task_selector.add_item(item_text)

func _on_task_selected(index: int):
	"""Handle task selection from dropdown"""
	if index <= 0 or index > current_tasks.size():
		return
	
	var selected_task = current_tasks[index - 1]
	open_task_in_tab(selected_task)

func open_task_in_tab(task: WorkplanTask):
	"""Open a task in a new tab or switch to existing tab"""
	if not content_tabs:
		return
	
	# Check if task is already open
	if task.title in open_tabs:
		var existing_tab_index = open_tabs[task.title]
		if existing_tab_index < content_tabs.get_tab_count():
			content_tabs.current_tab = existing_tab_index
			return
	
	# Create new tab
	var tab_content = _create_task_tab(task)
	content_tabs.add_child(tab_content)
	
	var new_tab_index = content_tabs.get_tab_count() - 1
	content_tabs.set_tab_title(new_tab_index, task.title)
	content_tabs.current_tab = new_tab_index
	
	open_tabs[task.title] = new_tab_index
	
	task_selected.emit(task)

func _create_task_tab(task: WorkplanTask) -> Control:
	"""Create a formatted tab for displaying task content"""
	var tab = ScrollContainer.new()
	tab.name = "Tab_" + task.title.replace(" ", "_")
	
	# Set proper size flags for the scroll container
	tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	# Disable horizontal scrolling to force content to fit within width
	tab.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tab.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	
	var main_container = VBoxContainer.new()
	main_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab.add_child(main_container)
	
	# Task header with metadata
	var header_panel = _create_task_header(task)
	main_container.add_child(header_panel)
	
	# Content editor
	var content_editor = _create_content_editor(task)
	main_container.add_child(content_editor)
	
	# Quality analysis panel
	var quality_panel = _create_quality_panel(task)
	main_container.add_child(quality_panel)
	
	return tab

func _create_task_header(task: WorkplanTask) -> Control:
	"""Create the task metadata header"""
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 120)
	
	var vbox = VBoxContainer.new()
	panel.add_child(vbox)
	
	# Title and status
	var title_container = HBoxContainer.new()
	vbox.add_child(title_container)
	
	var title_label = Label.new()
	title_label.text = task.title
	title_label.add_theme_font_size_override("font_size", 18)
	title_label.add_theme_color_override("font_color", Color(0.05, 0.05, 0.05))
	title_container.add_child(title_label)
	
	var status_badge = Label.new()
	status_badge.text = "✅ " + task.status
	status_badge.add_theme_color_override("font_color", task.get_status_color())
	title_container.add_child(status_badge)
	
	# Metadata grid - use 2 columns for better layout
	var metadata_grid = GridContainer.new()
	metadata_grid.columns = 2
	metadata_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(metadata_grid)
	
	_add_metadata_item(metadata_grid, "📹 Format:", task.format)
	_add_metadata_item(metadata_grid, "📱 Channel:", task.channel)
	_add_metadata_item(metadata_grid, "🔭 Cosmic Instrument:", task.cosmic_instrument)
	_add_metadata_item(metadata_grid, "⚡ Priority:", str(task.priority))
	_add_metadata_item(metadata_grid, "📅 Completed:", task.completion_date)
	_add_metadata_item(metadata_grid, "📄 File:", task.deliverable_path.get_file() if not task.deliverable_path.is_empty() else "N/A")
	
	return panel

func _add_metadata_item(grid: GridContainer, label: String, value: String):
	"""Add a metadata item to the grid"""
	var label_node = Label.new()
	label_node.text = label
	label_node.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1))
	label_node.size_flags_horizontal = Control.SIZE_SHRINK_END
	grid.add_child(label_node)
	
	var value_node = Label.new()
	value_node.text = value if not value.is_empty() else "Not specified"
	value_node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	value_node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(value_node)

func _create_content_editor(task: WorkplanTask) -> Control:
	"""Create the main content editor"""
	var container = VBoxContainer.new()
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	# Editor header
	var editor_header = HBoxContainer.new()
	editor_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.add_child(editor_header)
	
	var editor_label = Label.new()
	editor_label.text = "📝 Generated Content"
	editor_label.add_theme_font_size_override("font_size", 14)
	editor_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	editor_header.add_child(editor_label)
	
	var word_count_label = Label.new()
	word_count_label.name = "WordCount"
	word_count_label.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1))
	word_count_label.size_flags_horizontal = Control.SIZE_SHRINK_END
	editor_header.add_child(word_count_label)
	
	# Content editor
	var text_edit = TextEdit.new()
	text_edit.name = "ContentEditor"
	text_edit.text = _format_content_with_signature(task.generated_content)
	text_edit.custom_minimum_size = Vector2(600, 400)
	text_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Enable text wrapping to prevent horizontal overflow
	text_edit.wrap_mode = 1  # Enable word wrapping
	text_edit.placeholder_text = "Generated content will appear here..."
	container.add_child(text_edit)
	
	# Update word count
	_update_word_count(text_edit, word_count_label)
	text_edit.text_changed.connect(_update_word_count.bind(text_edit, word_count_label))
	text_edit.text_changed.connect(_on_content_modified.bind(task, text_edit))
	
	return container

func _create_quality_panel(task: WorkplanTask) -> Control:
	"""Create the mode-aware quality analysis panel"""
	var panel = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var vbox = VBoxContainer.new()
	panel.add_child(vbox)
	
	# Mode-aware title
	var mode_info = _get_current_mode_info()
	var title_text = "📊 Quality Analysis"
	if not mode_info.is_empty():
		title_text += " (" + mode_info + ")"
	
	var title_label = Label.new()
	title_label.text = title_text
	title_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(title_label)
	
	# Mode-aware quality metrics
	var metrics_grid = GridContainer.new()
	metrics_grid.columns = 2
	vbox.add_child(metrics_grid)
	
	_add_mode_aware_quality_metrics(metrics_grid, task)
	
	return panel

func _get_current_mode_info() -> String:
	"""Get current mode information for display"""
	if not ModeManager:
		return ""
	
	var _config = ModeManager.get_current_config()
	return _config.icon + " " + _config.name if _config else ""

func _add_mode_aware_quality_metrics(grid: GridContainer, task: WorkplanTask):
	"""Add quality metrics based on current mode"""
	if not ModeManager:
		# Fallback to generic metrics
		_add_quality_metric(grid, "Readability:", "N/A")
		_add_quality_metric(grid, "Sentiment:", "N/A")
		_add_quality_metric(grid, "Keyword Difficulty:", "N/A")
		return
	
	var current_mode = ModeManager.get_current_mode()
	var _config = ModeManager.get_current_config()
	
	# Add basic metrics that apply to all modes
	var word_count = task.generated_content.split(" ", false).size()
	_add_quality_metric(grid, "Word Count:", str(word_count))
	
	# Add mode-specific metrics based on mode configuration
	match current_mode:
		"social_media":
			_add_social_media_metrics(grid, task)
		"creative_writing":
			_add_creative_writing_metrics(grid, task)
		"academic_writing":
			_add_academic_writing_metrics(grid, task)
		_:
			# Generic fallback
			_add_quality_metric(grid, "Content Type:", "General")

func _add_social_media_metrics(grid: GridContainer, task: WorkplanTask):
	"""Add social media specific quality metrics"""
	var content = task.generated_content
	
	# Character count for social platforms
	var char_count = content.length()
	_add_quality_metric(grid, "📱 Character Count:", str(char_count))
	
	# Platform suitability
	var platform_fit = "Good"
	if char_count > 280:
		platform_fit = "Too long for Twitter"
	elif char_count < 50:
		platform_fit = "Too short"
	_add_quality_metric(grid, "📋 Platform Fit:", platform_fit)
	
	# Hashtag analysis
	var hashtag_count = content.count("#")
	_add_quality_metric(grid, "🏷️ Hashtags:", str(hashtag_count))
	
	# Engagement potential (simple heuristic)
	var engagement_score = _calculate_engagement_score(content)
	_add_quality_metric(grid, "🚀 Engagement Score:", engagement_score)

func _add_creative_writing_metrics(grid: GridContainer, task: WorkplanTask):
	"""Add creative writing specific quality metrics"""
	var content = task.generated_content
	
	# Reading time estimate
	var word_count = content.split(" ", false).size()
	var reading_time = max(1.0, float(word_count) / 200.0)  # Average 200 words per minute
	_add_quality_metric(grid, "📖 Reading Time:", str(reading_time) + " min")
	
	# Narrative elements
	var dialogue_count = content.count("\"")
	_add_quality_metric(grid, "💬 Dialogue Lines:", str(int(float(dialogue_count) / 2.0)))  # Pairs of quotes
	
	# Pacing analysis (sentences per paragraph)
	var paragraphs = content.split("\n\n", false)
	var avg_sentences = 0.0
	if paragraphs.size() > 0:
		var total_sentences = content.count(".") + content.count("!") + content.count("?")
		avg_sentences = float(total_sentences) / float(paragraphs.size())
	_add_quality_metric(grid, "📏 Avg Sentences/Para:", "%.1f" % avg_sentences)
	
	# Character development hints
	var character_indicators = content.count("he ") + content.count("she ") + content.count("they ")
	_add_quality_metric(grid, "👥 Character Focus:", "High" if character_indicators > 10 else "Moderate")

func _add_academic_writing_metrics(grid: GridContainer, task: WorkplanTask):
	"""Add academic writing specific quality metrics"""
	var content = task.generated_content
	
	# Citation analysis (simple detection)
	var citation_count = content.count("(") + content.count("[")  # Simple citation detection
	_add_quality_metric(grid, "📚 Citations:", str(citation_count))
	
	# Academic tone indicators
	var formal_words = ["therefore", "however", "furthermore", "consequently", "thus", "moreover"]
	var formal_count = 0
	for word in formal_words:
		formal_count += content.to_lower().count(word)
	_add_quality_metric(grid, "🎓 Academic Tone:", "Strong" if formal_count > 3 else "Moderate")
	
	# Argument structure (paragraphs as sections)
	var paragraphs = content.split("\n\n", false)
	_add_quality_metric(grid, "📋 Sections:", str(paragraphs.size()))
	
	# Reference quality (basic heuristic)
	var reference_quality = "Good" if citation_count > 2 else "Needs more sources"
	_add_quality_metric(grid, "🔍 Reference Quality:", reference_quality)

func _calculate_engagement_score(content: String) -> String:
	"""Calculate a simple engagement score for social media content"""
	var score = 0
	
	# Questions engage users
	score += content.count("?") * 10
	
	# Exclamation points show enthusiasm
	score += content.count("!") * 5
	
	# Emojis are engaging (detect by checking for emoji-like patterns)
	var emoji_indicators = ["🎯", "✨", "🚀", "💡", "📱", "🔥", "💯", "👥", "📊", "🎭", "🎓"]
	for emoji in emoji_indicators:
		score += content.count(emoji) * 8
	
	# Action words
	var action_words = ["discover", "learn", "explore", "join", "share", "follow", "comment"]
	for word in action_words:
		score += content.to_lower().count(word) * 3
	
	# Return qualitative score
	if score >= 50:
		return "High"
	elif score >= 25:
		return "Medium"
	else:
		return "Low"

func _add_quality_metric(grid: GridContainer, label: String, value: String):
	"""Add a quality metric item to the grid"""
	var label_node = Label.new()
	label_node.text = label
	label_node.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1))
	grid.add_child(label_node)
	
	var value_node = Label.new()
	value_node.text = value
	grid.add_child(value_node)

func _update_word_count(text_edit: TextEdit, label: Label):
	"""Update the word count label based on TextEdit content"""
	var word_count = text_edit.text.split(" ", false).size()
	label.text = "%d words" % word_count

func _on_content_modified(task: WorkplanTask, text_edit: TextEdit):
	"""Handle content modification in TextEdit"""
	var modified_content = _remove_signature_from_content(text_edit.text)
	task.generated_content = modified_content
	content_modified.emit(task, modified_content)

func _on_refresh_pressed():
	"""Handle refresh button press"""
	# Re-fetch tasks from a source, assuming a parent node handles this
	if get_parent() and get_parent().has_method("refresh_workplan_data"):
		get_parent().refresh_workplan_data()
		print("ContentViewer: Refresh requested.")

func _on_export_pressed():
	"""Show the file dialog for exporting content."""
	var current_tab_index = content_tabs.current_tab
	if current_tab_index < 0:
		return
	
	var task = _get_task_for_tab(current_tab_index)
	if not task:
		return
	
	export_dialog.current_file = "%s.md" % task.title.to_snake_case()
	export_dialog.popup_centered()

func _on_close_tab_pressed():
	"""Close the currently active tab"""
	var current_tab_index = content_tabs.current_tab
	if current_tab_index < 0:
		return
	
	var tab_to_close = content_tabs.get_child(current_tab_index)
	var task_title = content_tabs.get_tab_title(current_tab_index)
	
	if tab_to_close:
		open_tabs.erase(task_title)
		content_tabs.remove_child(tab_to_close)
		tab_to_close.queue_free()
		
		# Adjust indices of remaining tabs
		var new_open_tabs = {}
		for title in open_tabs.keys():
			var old_index = open_tabs[title]
			if old_index > current_tab_index:
				new_open_tabs[title] = old_index - 1
			else:
				new_open_tabs[title] = old_index
		open_tabs = new_open_tabs

func _on_tab_selected(_tab_index: int):
	"""Handle tab selection"""
	# Placeholder for future logic if needed
	pass

func _find_task_by_title(title: String) -> WorkplanTask:
	"""Find a task in the current list by its title"""
	for task in current_tasks:
		if task.title == title:
			return task
	return null

# --- Export Conversion Helpers ---

func _on_file_selected(path: String):
	"""Handle file selection from export dialog and save content."""
	var extension = path.get_extension().to_lower()
	
	var current_tab_index = content_tabs.current_tab
	if current_tab_index < 0:
		return
		
	var task = _get_task_for_tab(current_tab_index)
	var text_edit = _get_text_edit_for_tab(current_tab_index)
	if not task or not text_edit:
		return

	var content_to_save = ""
	match extension:
		"md":
			content_to_save = text_edit.text
		"html":
			content_to_save = _convert_to_html(task, text_edit.text)
		"txt":
			content_to_save = _convert_to_txt(task, text_edit.text)
		"json":
			content_to_save = _convert_to_json(task, text_edit.text)
		_:
			print("Error: Unsupported file format for export.")
			return

	var file = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		print("Error: Could not open file for writing at path: ", path)
		return
	
	file.store_string(content_to_save)
	file.close()
	print("✅ Content successfully exported to: ", path)

func _convert_to_html(task: WorkplanTask, content: String) -> String:
	"""Converts task data and content to a self-contained HTML document."""
	var html = "<html><head><title>%s</title>" % task.title
	html += "<style>body{font-family:sans-serif;line-height:1.6;max-width:800px;margin:auto;padding:20px;} h1{color:#333;} pre{background-color:#f4f4f4;padding:15px;border-radius:5px;white-space:pre-wrap;}</style>"
	html += "</head><body>"
	html += "<h1>%s</h1>" % task.title
	html += "<h2>Metadata</h2><ul>"
	html += "<li><b>Format:</b> %s</li>" % task.format
	html += "<li><b>Channel:</b> %s</li>" % task.channel
	html += "<li><b>Completed:</b> %s</li>" % task.completion_date
	html += "</ul><hr>"
	# Basic Markdown to HTML conversion
	var body_content = content.replace("\n", "<br>")
	# This is a very basic parser, can be expanded
	body_content = body_content.replace("### ", "<h3>").replace("\n", "</h3>\n")
	body_content = body_content.replace("## ", "<h2>").replace("\n", "</h2>\n")
	html += "<h2>Content</h2><div>%s</div>" % body_content
	html += "</body></html>"
	return html

func _convert_to_txt(task: WorkplanTask, content: String) -> String:
	"""Converts task data and content to plain text."""
	var txt = "Title: %s\n" % task.title
	txt += "Format: %s\n" % task.format
	txt += "Channel: %s\n" % task.channel
	txt += "--------------------\n\n"
	# Strip basic markdown for plain text
	var plain_content = content.replace("### ", "").replace("## ", "")
	txt += plain_content
	return txt

func _convert_to_json(task: WorkplanTask, content: String) -> String:
	"""Converts task data to a JSON string."""
	var data = {
		"title": task.title,
		"core_idea": task.core_idea,
		"format": task.format,
		"channel": task.channel,
		"completion_date": task.completion_date,
		"generated_content_md": content, # Store original markdown
		"signature": "Generated by ReadyMade A1 Synthesis Engine"
	}
	return JSON.stringify(data, "  ")

# --- Tab Helpers ---

func _get_text_edit_for_tab(tab_index: int) -> TextEdit:
	"""Find the TextEdit node for a specific tab."""
	if tab_index < 0 or tab_index >= content_tabs.get_tab_count():
		return null
	var tab_node = content_tabs.get_child(tab_index)
	if not tab_node:
		return null
	# The TextEdit is nested inside containers
	return tab_node.find_child("ContentEditor", true, false)

func _get_task_for_tab(tab_index: int) -> WorkplanTask:
	"""Find the WorkplanTask associated with an open tab index."""
	if tab_index < 0 or tab_index >= content_tabs.get_tab_count():
		return null
	
	var tab_node = content_tabs.get_child(tab_index)
	if not tab_node:
		return null
	
	var task_title = content_tabs.get_tab_title(tab_index)
	if not task_title:
		return null
	
	return _find_task_by_title(task_title)

# --- Content Formatting ---

func _format_content_with_signature(content: String) -> String:
	"""Appends a signature to the content if not already present."""
	if content.is_empty():
		return content
	
	# Check if signature is already present to avoid duplication
	var signature = "\n\n---\n*Generated by ReadyMade A1 Synthesis Engine*"
	
	if content.ends_with("*Generated by ReadyMade A1 Synthesis Engine*") or content.contains("Generated by ReadyMade A1 Synthesis Engine"):
		return content  # Signature already present
	
	return content + signature

func _remove_signature_from_content(content: String) -> String:
	"""Remove ReadyMade signature from content"""
	if content.is_empty():
		return content
	
	# Remove the signature pattern if present
	var signature_patterns = [
		"\n\n---\n*Generated by ReadyMade A1 Synthesis Engine*",
		"\n---\n*Generated by ReadyMade A1 Synthesis Engine*",
		"---\n*Generated by ReadyMade A1 Synthesis Engine*",
		"*Generated by ReadyMade A1 Synthesis Engine*"
	]
	
	var cleaned_content = content
	for pattern in signature_patterns:
		if cleaned_content.ends_with(pattern):
			cleaned_content = cleaned_content.substr(0, cleaned_content.length() - pattern.length())
			break
	
	return cleaned_content.strip_edges()
 
