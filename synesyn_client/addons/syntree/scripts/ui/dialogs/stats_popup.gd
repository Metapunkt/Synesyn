## Purpose: ui/dialogs/stats_popup.gd
# scripts/ui/dialogs/stats_popup.gd
@tool
extends PopupPanel

@onready var stats_container: VBoxContainer = %StatsContainer
@onready var refresh_button: Button = %RefreshStatsButton
@onready var close_button: Button = %CloseStatsButton

var _content_state: ContentStateResource = null

func set_resources(content_state: ContentStateResource) -> void:
	_content_state = content_state

func _ready() -> void:
	refresh_button.pressed.connect(_on_refresh_pressed)
	close_button.pressed.connect(_on_close_pressed)

func show_dialog() -> void:
	refresh_stats()
	popup_centered()

func refresh_stats() -> void:
	if not is_instance_valid(_content_state):
		return
		
	var stats = {
		"total_sources": 0,
		"active_sources": 0,
		"metaprompts": 0,
		"source_types": {},
		"content_types": {},
		"source_origins": {},
		"total_size": 0
	}
	
	var source_ids = _content_state.get_source_ids()
	stats.total_sources = source_ids.size()
	
	for source_id in source_ids:
		var source_data = _content_state.get_source_data(source_id)
		if source_data.is_empty():
			continue
			
		var meta = source_data.get("meta", {})
		var ai_context = meta.get("ai_context", {})
		
		# Count active sources
		if ai_context.get("is_active", false):
			stats.active_sources += 1
			
		# Count metaprompts
		if ai_context.get("metaprompt", false):
			stats.metaprompts += 1
			
		# Track source types (file extension)
		var source_type = meta.get("source_type", "unknown")
		stats.source_types[source_type] = stats.source_types.get(source_type, 0) + 1
		
		# Track content types (e.g., code, docs - if available, otherwise maybe reuse source_type?)
		var content_type = meta.get("content_type", source_type)
		stats.content_types[content_type] = stats.content_types.get(content_type, 0) + 1
		
		# --- Track Source Origin --- 
		var origin = meta.get("source_origin", "file")
		stats.source_origins[origin] = stats.source_origins.get(origin, 0) + 1
		# --- End Track Source Origin ---
		
		# Track size - Handle different content types
		var content_value = source_data.get("content")
		var size_to_add = 0
		if content_value is String:
			size_to_add = content_value.length()
		elif content_value is Dictionary or content_value is Array:
			# Approximate size by stringifying non-string content
			size_to_add = JSON.stringify(content_value).length()
		# else: size remains 0 for null or other types
		
		stats.total_size += size_to_add
	
	_update_stats_display(stats)

func _update_stats_display(stats: Dictionary) -> void:
	# Clear existing stats
	for child in stats_container.get_children():
		child.queue_free()
		
	# Add stats labels
	_add_stat_label("Total Sources", str(stats.total_sources))
	_add_stat_label("Active Sources", str(stats.active_sources))
	_add_stat_label("Metaprompts", str(stats.metaprompts))
	
	# --- Source Origin Breakdown (Moved Up) --- 
	_add_stat_header("Source Origins:")
	for origin in stats.source_origins:
		_add_stat_label("  " + origin.capitalize(), str(stats.source_origins[origin]))
	# --- End Source Origin --- 

	# Source types breakdown (File Extensions)
	_add_stat_header("Source Types (Extensions):")
	for type in stats.source_types:
		_add_stat_label("  " + type.capitalize(), str(stats.source_types[type]))
	
	# --- Content types breakdown (REMOVED) --- 
	# _add_stat_header("Content Types:")
	# for type in stats.content_types:
	# 	_add_stat_label("  " + type.capitalize(), str(stats.content_types[type]))
	
	# Size stats
	_add_stat_label("Total Content Size", _format_size(stats.total_size))

func _add_stat_label(title: String, value: String) -> void:
	var hbox = HBoxContainer.new()
	var title_label = Label.new()
	var value_label = Label.new()
	
	title_label.text = title + ":"
	value_label.text = value
	
	hbox.add_child(title_label)
	hbox.add_child(value_label)
	stats_container.add_child(hbox)

func _add_stat_header(text: String) -> void:
	var label = Label.new()
	label.text = text
	
	# --- Add Dark Background Style --- 
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = Color(0.2, 0.2, 0.2, 1.0) # Dark gray background
	# Add some padding so text isn't right at the edge
	style_box.content_margin_left = 5
	style_box.content_margin_right = 5
	style_box.content_margin_top = 2
	style_box.content_margin_bottom = 2
	
	label.add_theme_stylebox_override("normal", style_box)
	# --- End Style --- 
	
	stats_container.add_child(label)

func _format_size(bytes: int) -> String:
	if bytes < 1024:
		return str(bytes) + " B"
	elif bytes < 1024 * 1024:
		return "%.1f KB" % (bytes / 1024.0)
	else:
		return "%.1f MB" % (bytes / (1024.0 * 1024.0))

func _on_refresh_pressed() -> void:
	refresh_stats()

func _on_close_pressed() -> void:
	hide()
