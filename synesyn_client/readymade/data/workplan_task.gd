# workplan_task.gd
@tool
extends Resource
class_name WorkplanTask
## A task in the content creation workplan with full workflow state management

@export var title: String = ""
@export var core_idea: String = ""
@export var format: String = ""  # Legacy single format (kept for backward compatibility)
@export var channel: String = ""  # Legacy single channel (kept for backward compatibility)
@export var cosmic_instrument: String = ""  # Legacy single instrument (kept for backward compatibility)
@export var formats: Array[String] = []  # New: Multiple formats support
@export var channels: Array[String] = []  # New: Multiple channels support
@export var cosmic_instruments: Array[String] = []  # New: Multiple cosmic instruments support
@export var priority: int = 0
@export var notes: String = ""
@export var status: String = "To Do"  # To Do, In Progress, Review, Done
@export var generated_content: String = ""
@export var deliverable_path: String = ""
@export var estimated_duration: int = 60  # minutes
@export var duration_minutes: int = 60  # Alias for estimated_duration for dialog compatibility
@export var start_date: String = ""
@export var completion_date: String = ""

# Calendar-related fields
@export var created_date: String = ""
@export var deadline: String = ""  # When task should be completed
@export var scheduled_date: String = ""  # When task is scheduled to be worked on
@export var publish_date: String = ""  # When content should go live
@export var campaign_tag: String = ""  # Group related content
@export var recurring_pattern: String = ""  # daily, weekly, monthly, custom
@export var content_theme: String = ""  # For strategic planning
@export var target_audience: String = ""  # Who this content is for
@export var performance_notes: String = ""  # Track what works

# Phase 5.1: Edit Session Integration
@export var edit_session_id: String = ""  # Reference to originating edit session
@export var referenced_documents: Array[Dictionary] = []  # Documents from edit session
@export var session_insights: Dictionary = {}  # Analytics and insights from edit session
@export var source_session_summary: String = ""  # Human-readable session summary
@export var productivity_metrics: Dictionary = {}  # Metrics from the edit session
@export var auto_generated: bool = false  # Flag indicating task was auto-created from session
@export var document_snapshots: Array[Dictionary] = []  # Content snapshots at task creation

func _init():
	if created_date.is_empty():
		created_date = Time.get_datetime_string_from_system()
	
	# Initialize duration_minutes to match estimated_duration
	duration_minutes = estimated_duration
	
	# Initialize arrays if they're empty and we have legacy single values
	if formats.is_empty() and not format.is_empty():
		formats = [format]
	if channels.is_empty() and not channel.is_empty():
		channels = [channel]
	if cosmic_instruments.is_empty() and not cosmic_instrument.is_empty():
		cosmic_instruments = [cosmic_instrument]

func start_task():
	"""Mark task as started and record start time"""
	if status == "To Do":
		status = "In Progress"
		start_date = Time.get_datetime_string_from_system()

func complete_task():
	"""Mark task as completed and record completion time"""
	status = "Done"
	completion_date = Time.get_datetime_string_from_system()

func send_for_review():
	"""Move task to review status"""
	status = "Review"

func get_status_color() -> Color:
	"""Get color for status visualization"""
	match status:
		"To Do":
			return Color.GRAY
		"In Progress":
			return Color.ORANGE
		"Review":
			return Color.YELLOW
		"Done":
			return Color.GREEN
		_:
			return Color.WHITE

func get_priority_color() -> Color:
	"""Get color for priority visualization"""
	match priority:
		0:
			return Color.GREEN  # Low priority
		1:
			return Color.YELLOW  # Medium priority  
		2:
			return Color.ORANGE  # High priority
		3:
			return Color.RED  # Critical priority
		_:
			return Color.GRAY

func is_overdue() -> bool:
	"""Check if task is past its deadline"""
	if deadline.is_empty():
		return false
	
	var deadline_time = Time.get_datetime_dict_from_datetime_string(deadline, false)
	var _current_time = Time.get_datetime_dict_from_system()
	
	# Simple comparison - could be enhanced with proper date parsing
	var deadline_unix = Time.get_unix_time_from_datetime_dict(deadline_time)
	var current_unix = Time.get_unix_time_from_system()
	
	return current_unix > deadline_unix and status != "Done"

func is_due_soon(days_ahead: int = 3) -> bool:
	"""Check if task is due within specified days"""
	if deadline.is_empty():
		return false
	
	var deadline_time = Time.get_datetime_dict_from_datetime_string(deadline, false)
	var _current_time = Time.get_datetime_dict_from_system()
	
	var deadline_unix = Time.get_unix_time_from_datetime_dict(deadline_time)
	var current_unix = Time.get_unix_time_from_system()
	var days_in_seconds = days_ahead * 24 * 60 * 60
	
	return (deadline_unix - current_unix) <= days_in_seconds and (deadline_unix - current_unix) > 0

func get_days_until_deadline() -> int:
	"""Get number of days until deadline (negative if overdue)"""
	if deadline.is_empty():
		return 999  # No deadline
	
	var deadline_time = Time.get_datetime_dict_from_datetime_string(deadline, false)
	var _current_time = Time.get_datetime_dict_from_system()
	
	var deadline_unix = Time.get_unix_time_from_datetime_dict(deadline_time)
	var current_unix = Time.get_unix_time_from_system()
	
	return int((deadline_unix - current_unix) / (24 * 60 * 60))

func get_calendar_display_date() -> String:
	"""Get the most relevant date for calendar display"""
	if not scheduled_date.is_empty():
		return scheduled_date
	elif not deadline.is_empty():
		return deadline
	elif not publish_date.is_empty():
		return publish_date
	else:
		return created_date

func get_date_label() -> String:
	"""Get label for the date being displayed"""
	if not scheduled_date.is_empty():
		return "Scheduled"
	elif not deadline.is_empty():
		return "Deadline"
	elif not publish_date.is_empty():
		return "Publish"
	else:
		return "Created"

func sync_legacy_properties():
	"""Sync between legacy single properties and new array properties"""
	# Sync single properties from arrays (use first item if available)
	format = formats[0] if not formats.is_empty() else ""
	channel = channels[0] if not channels.is_empty() else ""
	cosmic_instrument = cosmic_instruments[0] if not cosmic_instruments.is_empty() else ""
	
	# Sync duration fields
	duration_minutes = estimated_duration

func sync_array_properties():
	"""Sync arrays from legacy single properties"""
	if not format.is_empty() and (formats.is_empty() or not formats.has(format)):
		if formats.is_empty():
			formats.append(format)
		else:
			formats.append(format)
	if not channel.is_empty() and (channels.is_empty() or not channels.has(channel)):
		if channels.is_empty():
			channels.append(channel)
		else:
			channels.append(channel)
	if not cosmic_instrument.is_empty() and (cosmic_instruments.is_empty() or not cosmic_instruments.has(cosmic_instrument)):
		if cosmic_instruments.is_empty():
			cosmic_instruments.append(cosmic_instrument)
		else:
			cosmic_instruments.append(cosmic_instrument)

func get_formats_display() -> String:
	"""Get formatted string of all formats for display"""
	return ", ".join(formats) if not formats.is_empty() else format

func get_channels_display() -> String:
	"""Get formatted string of all channels for display"""
	return ", ".join(channels) if not channels.is_empty() else channel

func get_cosmic_instruments_display() -> String:
	"""Get formatted string of all cosmic instruments for display"""
	return ", ".join(cosmic_instruments) if not cosmic_instruments.is_empty() else cosmic_instrument

func clone() -> WorkplanTask:
	"""Create a copy of this task for recurring content"""
	var new_task = WorkplanTask.new()
	new_task.title = title
	new_task.core_idea = core_idea
	new_task.format = format
	new_task.channel = channel
	new_task.cosmic_instrument = cosmic_instrument
	new_task.formats = formats.duplicate()
	new_task.channels = channels.duplicate()
	new_task.cosmic_instruments = cosmic_instruments.duplicate()
	new_task.priority = priority
	new_task.notes = notes
	new_task.estimated_duration = estimated_duration
	new_task.duration_minutes = duration_minutes
	new_task.campaign_tag = campaign_tag
	new_task.recurring_pattern = recurring_pattern
	new_task.content_theme = content_theme
	new_task.target_audience = target_audience
	# Copy edit session data
	new_task.edit_session_id = edit_session_id
	new_task.referenced_documents = referenced_documents.duplicate(true)
	new_task.session_insights = session_insights.duplicate(true)
	new_task.source_session_summary = source_session_summary
	new_task.productivity_metrics = productivity_metrics.duplicate(true)
	new_task.auto_generated = auto_generated
	new_task.document_snapshots = document_snapshots.duplicate(true)
	# Don't copy dates, status, or generated content
	return new_task

# === PHASE 5.1: EDIT SESSION INTEGRATION METHODS ===

func add_document_reference(document_info: Dictionary):
	"""Add a document reference from edit session"""
	if not referenced_documents.has(document_info):
		referenced_documents.append(document_info)

func set_session_insights(insights: Dictionary):
	"""Set analytics and insights from edit session"""
	session_insights = insights.duplicate(true)

func set_productivity_metrics(metrics: Dictionary):
	"""Set productivity metrics from edit session"""
	productivity_metrics = metrics.duplicate(true)

func get_document_count() -> int:
	"""Get number of referenced documents"""
	return referenced_documents.size()

func get_primary_document() -> Dictionary:
	"""Get the primary document reference if available"""
	for doc_ref in referenced_documents:
		if doc_ref.get("is_primary", false):
			return doc_ref
	
	# Return first document if no primary is marked
	if referenced_documents.size() > 0:
		return referenced_documents[0]
	
	return {}

func has_edit_session_origin() -> bool:
	"""Check if task originated from an edit session"""
	return not edit_session_id.is_empty()

func get_session_productivity_score() -> float:
	"""Get productivity score from edit session if available"""
	return productivity_metrics.get("productivity_score", 0.0)

func get_session_words_per_minute() -> float:
	"""Get words per minute from edit session if available"""
	return productivity_metrics.get("words_per_minute", 0.0)

func get_session_edit_count() -> int:
	"""Get total edits from edit session if available"""
	return productivity_metrics.get("total_edits", 0)

func get_document_references_summary() -> String:
	"""Get a formatted summary of referenced documents"""
	if referenced_documents.is_empty():
		return "No documents referenced"
	
	var summary = "Referenced Documents (%d):\n" % referenced_documents.size()
	for i in range(referenced_documents.size()):
		var doc = referenced_documents[i]
		var doc_name = doc.get("name", "Unknown Document")
		var is_primary = doc.get("is_primary", false)
		var word_count = doc.get("word_count", 0)
		
		summary += "• %s%s (%d words)\n" % [
			doc_name,
			" (PRIMARY)" if is_primary else "",
			word_count
		]
	
	return summary.strip_edges()

func get_session_insights_summary() -> String:
	"""Get a formatted summary of session insights"""
	if session_insights.is_empty():
		return "No session insights available"
	
	var summary = "Edit Session Insights:\n"
	
	# Add complexity assessment
	var complexity = session_insights.get("session_complexity", "Unknown")
	summary += "• Session Complexity: %s\n" % complexity
	
	# Add productivity insights
	var productivity_score = get_session_productivity_score()
	if productivity_score > 0:
		summary += "• Productivity Score: %.1f%%\n" % (productivity_score * 100)
	
	# Add document relationships
	var relationships = session_insights.get("document_relationships", [])
	if relationships.size() > 0:
		summary += "• Document Relationships: %d found\n" % relationships.size()
	
	# Add recommendations count
	var recommendations = session_insights.get("recommendations", [])
	if recommendations.size() > 0:
		summary += "• Improvement Recommendations: %d\n" % recommendations.size()
	
	return summary.strip_edges()

func create_enhanced_description() -> String:
	"""Create enhanced description incorporating session data"""
	var enhanced = notes
	
	# Add session summary if available
	if not source_session_summary.is_empty():
		enhanced += "\n\n[Edit Session Summary]\n" + source_session_summary
	
	# Add document references
	var doc_summary = get_document_references_summary()
	if doc_summary != "No documents referenced":
		enhanced += "\n\n[" + doc_summary + "]"
	
	# Add session insights
	var insights_summary = get_session_insights_summary()
	if insights_summary != "No session insights available":
		enhanced += "\n\n[" + insights_summary + "]"
	
	# Add productivity context
	if not productivity_metrics.is_empty():
		enhanced += "\n\n[Productivity Context]"
		var wpm = get_session_words_per_minute()
		var edits = get_session_edit_count()
		if wpm > 0:
			enhanced += "\n• Editing Speed: %.1f words/minute" % wpm
		if edits > 0:
			enhanced += "\n• Total Edits: %d" % edits
	
	return enhanced.strip_edges()

func estimate_task_duration_from_session() -> int:
	"""Estimate task duration based on edit session data"""
	var base_duration = estimated_duration
	
	# Adjust based on session complexity
	var complexity = session_insights.get("session_complexity", "")
	match complexity:
		"Simple":
			base_duration = max(30, base_duration - 15)  # Reduce for simple sessions
		"Complex":
			base_duration += 30  # Add time for complex sessions
		"Very Complex":
			base_duration += 60  # Add more time for very complex sessions
	
	# Adjust based on productivity score
	var productivity_score = get_session_productivity_score()
	if productivity_score > 0.7:
		base_duration = max(30, base_duration - 15)  # High productivity = faster work
	elif productivity_score < 0.5:
		base_duration += 15  # Low productivity = need more time
	
	# Adjust based on document count
	var doc_count = get_document_count()
	if doc_count > 3:
		base_duration += (doc_count - 3) * 10  # Extra time for multiple documents
	
	return base_duration

func suggest_task_priority_from_session() -> int:
	"""Suggest task priority based on edit session insights"""
	var suggested_priority = priority
	
	# High activity sessions might indicate high priority
	var total_edits = get_session_edit_count()
	if total_edits > 50:
		suggested_priority = max(suggested_priority, 2)  # High priority
	elif total_edits > 20:
		suggested_priority = max(suggested_priority, 1)  # Medium priority
	
	# Multiple documents might indicate complex, important work
	if get_document_count() > 2:
		suggested_priority = max(suggested_priority, 1)  # At least medium priority
	
	# Check for urgent recommendations from session
	var recommendations = session_insights.get("recommendations", [])
	for rec in recommendations:
		if rec.get("priority", "") == "high":
			suggested_priority = max(suggested_priority, 2)
			break
	
	return min(suggested_priority, 3)  # Cap at critical priority

func get_content_theme_from_session() -> String:
	"""Extract content theme from session data"""
	# Try to extract theme from document content or session insights
	var content_themes = session_insights.get("content_themes", [])
	if content_themes.size() > 0:
		return content_themes[0]  # Use first identified theme
	
	# Fallback to analyzing document names
	var primary_doc = get_primary_document()
	if not primary_doc.is_empty():
		var doc_name = primary_doc.get("name", "")
		if "proposal" in doc_name.to_lower():
			return "Business Proposal"
		elif "research" in doc_name.to_lower():
			return "Research & Analysis"
		elif "meeting" in doc_name.to_lower():
			return "Meeting Documentation"
		elif "plan" in doc_name.to_lower():
			return "Strategic Planning"
	
	return content_theme  # Return existing theme if no insights available
