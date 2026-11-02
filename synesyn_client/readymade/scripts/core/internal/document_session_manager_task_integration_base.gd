extends "res://readymade/scripts/core/internal/document_session_manager_export_reporting_base.gd"
class_name DocumentSessionManagerTaskIntegrationBase

func create_task_from_edit_session(task_title: String = "", task_notes: String = "") -> WorkplanTask:
	"""Create a WorkplanTask from the current edit session"""
	if active_documents.is_empty():
		push_error("Cannot create task from empty edit session")
		return null
	
	# Create new task with session integration
	var task = WorkplanTask.new()
	
	# Basic task setup
	task.title = task_title if not task_title.is_empty() else _generate_task_title_from_session()
	task.notes = task_notes if not task_notes.is_empty() else _generate_task_notes_from_session()
	task.auto_generated = true
	task.edit_session_id = session_name if not session_name.is_empty() else _generate_session_id()
	
	# Add document references
	for doc in active_documents:
		var doc_ref = {
			"name": doc.file_name,
			"path": doc.file_path,
			"word_count": doc.word_count,
			"is_primary": doc.is_primary,
			"last_modified": doc.last_modified,
			"total_edits": doc.change_statistics.get("total_edits", 0),
			"session_id": doc.edit_session_id
		}
		task.add_document_reference(doc_ref)
		
		# Create document snapshot
		var snapshot = {
			"document_name": doc.file_name,
			"content_preview": doc.content.substr(0, 500) + "..." if doc.content.length() > 500 else doc.content,
			"word_count": doc.word_count,
			"timestamp": Time.get_unix_time_from_system(),
			"change_summary": doc.generate_change_summary()
		}
		task.document_snapshots.append(snapshot)
	
	# Set session insights and analytics
	var insights = _generate_content_insights()
	task.set_session_insights(insights)
	
	var productivity_metrics = get_session_productivity_metrics()
	task.set_productivity_metrics(productivity_metrics)
	
	# Generate session summary
	task.source_session_summary = _generate_session_summary_for_task()
	
	# Apply AI-driven suggestions
	task.estimated_duration = task.estimate_task_duration_from_session()
	task.priority = task.suggest_task_priority_from_session()
	task.content_theme = task.get_content_theme_from_session()
	
	# Set formats and channels based on document analysis
	var suggested_formats = _suggest_formats_from_documents()
	var suggested_channels = _suggest_channels_from_documents()
	
	task.formats = suggested_formats
	task.channels = suggested_channels
	
	# Enhanced description with session data
	task.notes = task.create_enhanced_description()
	
	return task

func create_multiple_tasks_from_session(task_configs: Array) -> Array:
	"""Create multiple tasks from session with different configurations"""
	var created_tasks = []
	
	for config in task_configs:
		var task_title = config.get("title", "")
		var task_notes = config.get("notes", "")
		var custom_documents = config.get("documents", [])  # Specific documents for this task
		
		var task = create_task_from_edit_session(task_title, task_notes)
		if task != null:
			# If specific documents are requested, filter references
			if not custom_documents.is_empty():
				task.referenced_documents = task.referenced_documents.filter(
					func(doc_ref): return doc_ref.name in custom_documents
				)
			
			# Apply custom configuration
			if config.has("priority"):
				task.priority = config.priority
			if config.has("estimated_duration"):
				task.estimated_duration = config.estimated_duration
			if config.has("formats"):
				task.formats = config.formats
			if config.has("channels"):
				task.channels = config.channels
			
			created_tasks.append(task)
	
	return created_tasks

func get_task_creation_suggestions() -> Dictionary:
	"""Get AI-powered suggestions for task creation from current session"""
	if active_documents.is_empty():
		return {"error": "No documents in session"}
	
	var suggestions = {
		"recommended_tasks": [],
		"session_analysis": {},
		"productivity_insights": {},
		"collaboration_opportunities": []
	}
	
	# Analyze session for task suggestions
	var session_insights = _generate_content_insights()
	suggestions.session_analysis = session_insights
	
	# Generate task recommendations based on document types and content
	var task_recommendations = _generate_task_recommendations()
	suggestions.recommended_tasks = task_recommendations
	
	# Add productivity insights
	suggestions.productivity_insights = get_session_productivity_metrics()
	
	# Identify collaboration opportunities
	suggestions.collaboration_opportunities = _identify_collaboration_opportunities()
	
	return suggestions

func _generate_task_title_from_session() -> String:
	"""Generate appropriate task title from session context"""
	var primary_doc = get_primary_document()
	if primary_doc != null:
		var doc_name = primary_doc.file_name.get_basename()
		
		# Analyze document name and content for context
		if "proposal" in doc_name.to_lower():
			return "Finalize %s Proposal" % doc_name.capitalize()
		elif "report" in doc_name.to_lower():
			return "Complete %s Report" % doc_name.capitalize()
		elif "meeting" in doc_name.to_lower():
			return "Review Meeting Notes: %s" % doc_name.capitalize()
		elif "plan" in doc_name.to_lower():
			return "Execute %s Plan" % doc_name.capitalize()
		else:
			return "Review and Finalize %s" % doc_name.capitalize()
	
	# Fallback based on document count
	if active_documents.size() > 1:
		return "Multi-Document Review Session (%d docs)" % active_documents.size()
	else:
		return "Document Review and Editing Task"

func _generate_task_notes_from_session() -> String:
	"""Generate task notes from session analysis"""
	var notes = "Task created from edit session on %s\n\n" % Time.get_datetime_string_from_system()
	
	# Add session statistics
	var total_words = 0
	var total_edits = 0
	for doc in active_documents:
		total_words += doc.word_count
		total_edits += doc.change_statistics.get("total_edits", 0)
	
	notes += "Session Statistics:\n"
	notes += "• Documents edited: %d\n" % active_documents.size()
	notes += "• Total words: %d\n" % total_words
	notes += "• Total edits made: %d\n\n" % total_edits
	
	# Add specific document information
	notes += "Documents in this session:\n"
	for doc in active_documents:
		var status = "(PRIMARY)" if doc.is_primary else ""
		notes += "• %s %s - %d words, %d edits\n" % [
			doc.file_name, 
			status, 
			doc.word_count, 
			doc.change_statistics.get("total_edits", 0)
		]
	
	# Add any specific insights
	var insights = _generate_content_insights()
	if insights.has("key_themes"):
		notes += "\nKey themes identified: %s\n" % ", ".join(insights.key_themes)
	
	return notes.strip_edges()

func _generate_session_summary_for_task() -> String:
	"""Generate concise session summary for task reference"""
	var summary = ""
	var session_duration = _calculate_session_duration()
	
	summary += "Edit session lasted %.1f minutes with %d documents. " % [session_duration / 60.0, active_documents.size()]
	
	var total_edits = 0
	for doc in active_documents:
		total_edits += doc.change_statistics.get("total_edits", 0)
	
	summary += "Made %d total edits across all documents. " % total_edits
	
	var productivity_score = get_session_productivity_metrics().get("productivity_score", 0.0)
	if productivity_score > 0.7:
		summary += "High productivity session with consistent editing pace."
	elif productivity_score > 0.4:
		summary += "Moderate productivity with focused editing periods."
	else:
		summary += "Exploratory session with varied editing patterns."
	
	return summary

func _suggest_formats_from_documents() -> Array[String]:
	"""Suggest content formats based on document analysis"""
	var suggested_formats: Array[String] = []
	
	for doc in active_documents:
		var _content_lower = doc.content.to_lower()
		var name_lower = doc.file_name.to_lower()
		
		# Analyze content type
		if "blog" in name_lower or "article" in name_lower:
			if "blog post" not in suggested_formats:
				suggested_formats.append("blog post")
		elif "report" in name_lower or "analysis" in name_lower:
			if "report" not in suggested_formats:
				suggested_formats.append("report")
		elif "proposal" in name_lower:
			if "proposal" not in suggested_formats:
				suggested_formats.append("proposal")
		elif "email" in name_lower or "message" in name_lower:
			if "email" not in suggested_formats:
				suggested_formats.append("email")
		elif "social" in name_lower or "post" in name_lower:
			if "social media" not in suggested_formats:
				suggested_formats.append("social media")
		
		# Content-based detection
		if _content_lower.contains("## ") or _content_lower.contains("# "):
			if "documentation" not in suggested_formats:
				suggested_formats.append("documentation")
	
	# Default format if none detected
	if suggested_formats.is_empty():
		suggested_formats.append("document")
	
	return suggested_formats

func _suggest_channels_from_documents() -> Array[String]:
	"""Suggest distribution channels based on document analysis"""
	var suggested_channels: Array[String] = []
	
	for doc in active_documents:
		var _content_lower = doc.content.to_lower()
		var name_lower = doc.file_name.to_lower()
		
		# Channel detection logic
		if "blog" in name_lower or "website" in name_lower:
			if "website" not in suggested_channels:
				suggested_channels.append("website")
		elif "email" in name_lower or "newsletter" in name_lower:
			if "email" not in suggested_channels:
				suggested_channels.append("email")
		elif "social" in name_lower or "twitter" in name_lower or "linkedin" in name_lower:
			if "social media" not in suggested_channels:
				suggested_channels.append("social media")
		elif "internal" in name_lower or "team" in name_lower or "meeting" in name_lower:
			if "internal" not in suggested_channels:
				suggested_channels.append("internal")
		elif "presentation" in name_lower or "slide" in name_lower:
			if "presentation" not in suggested_channels:
				suggested_channels.append("presentation")
	
	# Default channel if none detected
	if suggested_channels.is_empty():
		suggested_channels.append("direct")
	
	return suggested_channels

func _generate_task_recommendations() -> Array:
	"""Generate AI-powered task recommendations based on session analysis"""
	var recommendations = []
	
	# Analyze each document for specific task opportunities
	for doc in active_documents:
		var doc_recommendations = _analyze_document_for_tasks(doc)
		recommendations.append_array(doc_recommendations)
	
	# Add session-level recommendations
	var session_recommendations = _analyze_session_for_tasks()
	recommendations.append_array(session_recommendations)
	
	return recommendations

func _analyze_document_for_tasks(doc: DocumentContext) -> Array:
	"""Analyze individual document for task creation opportunities"""
	var doc_tasks = []
	var content_lower = doc.content.to_lower()
	
	# TODO detection
	if "todo" in content_lower or "to-do" in content_lower or "fixme" in content_lower:
		doc_tasks.append({
			"title": "Address TODOs in %s" % doc.file_name,
			"priority": 1,
			"estimated_duration": 30,
			"reason": "Document contains TODO items that need attention"
		})
	
	# Review needs detection
	if doc.change_statistics.get("total_edits", 0) > 20:
		doc_tasks.append({
			"title": "Editorial Review of %s" % doc.file_name,
			"priority": 1,
			"estimated_duration": 45,
			"reason": "Document has significant edits requiring review"
		})
	
	# Formatting needs
	if doc.content.length() > 2000 and doc.content.count("\n\n") < 5:
		doc_tasks.append({
			"title": "Format and Structure %s" % doc.file_name,
			"priority": 0,
			"estimated_duration": 30,
			"reason": "Long document may benefit from better structure"
		})
	
	return doc_tasks

func _analyze_session_for_tasks() -> Array:
	"""Analyze overall session for task opportunities"""
	var session_tasks = []
	
	# Multi-document coordination
	if active_documents.size() > 2:
		session_tasks.append({
			"title": "Coordinate Multi-Document Changes",
			"priority": 1,
			"estimated_duration": 60,
			"reason": "Multiple documents edited - may need coordination"
		})
	
	# High-activity session follow-up
	var total_edits = 0
	for doc in active_documents:
		total_edits += doc.change_statistics.get("total_edits", 0)
	
	if total_edits > 50:
		session_tasks.append({
			"title": "Review Intensive Edit Session Changes",
			"priority": 2,
			"estimated_duration": 45,
			"reason": "High-activity session may need quality review"
		})
	
	return session_tasks

func _identify_collaboration_opportunities() -> Array:
	"""Identify opportunities for collaborative tasks"""
	var opportunities = []
	
	# Multiple document types suggest different expertise needs
	var doc_types = []
	for doc in active_documents:
		var name_lower = doc.file_name.to_lower()
		if "technical" in name_lower or "spec" in name_lower:
			if "technical" not in doc_types: doc_types.append("technical")
		elif "marketing" in name_lower or "promo" in name_lower:
			if "marketing" not in doc_types: doc_types.append("marketing")
		elif "design" in name_lower or "ui" in name_lower:
			if "design" not in doc_types: doc_types.append("design")
	
	if doc_types.size() > 1:
		opportunities.append({
			"type": "cross_functional_review",
			"description": "Documents span multiple domains (%s) - consider cross-functional review" % ", ".join(doc_types),
			"suggested_roles": doc_types
		})
	
	# Large documents might benefit from collaborative editing
	for doc in active_documents:
		if doc.word_count > 1500:
			opportunities.append({
				"type": "collaborative_editing",
				"description": "Large document (%s) could benefit from collaborative review" % doc.file_name,
				"document": doc.file_name
			})
	
	return opportunities

func get_session_productivity_metrics() -> Dictionary:
	"""Get comprehensive productivity metrics for the session"""
	var metrics = {
		"productivity_score": 0.0,
		"words_per_minute": 0.0,
		"edits_per_minute": 0.0,
		"total_words": 0,
		"total_edits": 0,
		"session_duration": 0.0,
		"efficiency_score": 0.0,
		"consistency_score": 0.0
	}
	
	if active_documents.is_empty():
		return metrics
	
	# Calculate totals
	for doc in active_documents:
		metrics.total_words += doc.word_count
		metrics.total_edits += doc.change_statistics.get("total_edits", 0)
	
	# Calculate session duration
	metrics.session_duration = _calculate_session_duration()
	var duration_minutes = metrics.session_duration / 60.0
	
	if duration_minutes > 0:
		metrics.words_per_minute = metrics.total_words / duration_minutes
		metrics.edits_per_minute = metrics.total_edits / duration_minutes
		
		# Calculate productivity score (normalized to 0-1)
		var base_productivity = min(metrics.words_per_minute / 50.0, 1.0)  # 50 WPM as baseline
		var edit_efficiency = min(metrics.edits_per_minute / 5.0, 1.0)     # 5 EPM as baseline
		metrics.productivity_score = (base_productivity + edit_efficiency) / 2.0
		
		# Efficiency score based on edit-to-word ratio
		if metrics.total_words > 0:
			var edit_ratio = float(metrics.total_edits) / metrics.total_words
			metrics.efficiency_score = 1.0 - min(edit_ratio, 1.0)  # Lower edit ratio = higher efficiency
		
		# Consistency score based on edit distribution
		metrics.consistency_score = _calculate_consistency_score()
	
	return metrics

func _calculate_consistency_score() -> float:
	"""Calculate how consistently the user was editing throughout the session"""
	if active_documents.is_empty():
		return 0.0
	
	# Analyze edit timing consistency across all documents
	var all_edit_times = []
	for doc in active_documents:
		for edit in doc.edit_history:
			all_edit_times.append(edit.timestamp)
	
	if all_edit_times.size() < 2:
		return 1.0  # Perfect consistency if only one edit
	
	all_edit_times.sort()
	
	# Calculate variance in edit intervals
	var intervals = []
	for i in range(1, all_edit_times.size()):
		intervals.append(all_edit_times[i] - all_edit_times[i-1])
	
	if intervals.is_empty():
		return 1.0
	
	var mean_interval = 0.0
	for interval in intervals:
		mean_interval += interval
	mean_interval /= intervals.size()
	
	var variance = 0.0
	for interval in intervals:
		variance += pow(interval - mean_interval, 2)
	variance /= intervals.size()
	
	# Convert variance to consistency score (0-1, higher is more consistent)
	var std_dev = sqrt(variance)
	var coefficient_of_variation = std_dev / mean_interval if mean_interval > 0 else 0
	
	# Normalize to 0-1 scale (lower CV = higher consistency)
	return max(0.0, 1.0 - min(coefficient_of_variation / 2.0, 1.0))

