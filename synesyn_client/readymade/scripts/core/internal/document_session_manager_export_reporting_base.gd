extends "res://readymade/scripts/core/internal/document_session_manager_session_core_base.gd"
class_name DocumentSessionManagerExportReportingBase

func generate_edit_session_report(format: ExportFormat = ExportFormat.HTML, save_path: String = "") -> String:
	"""Generate comprehensive edit session report in specified format"""
	var report_data = _compile_comprehensive_report_data()
	var report_content = ""
	var file_extension = ""
	
	match format:
		ExportFormat.HTML:
			report_content = _generate_html_report(report_data)
			file_extension = ".html"
		ExportFormat.MARKDOWN:
			report_content = _generate_markdown_report(report_data)
			file_extension = ".md"
		ExportFormat.JSON:
			report_content = JSON.stringify(report_data, "\t")
			file_extension = ".json"
		ExportFormat.PLAIN_TEXT:
			report_content = _generate_text_report(report_data)
			file_extension = ".txt"
		ExportFormat.PDF_READY:
			report_content = _generate_pdf_ready_html(report_data)
			file_extension = ".html"
		ExportFormat.RTFD:
			report_content = _generate_rtfd_report(report_data)
			file_extension = ".rtfd"
	
	# Generate file path if not provided
	var final_path = save_path
	if final_path.is_empty():
		var timestamp = Time.get_datetime_string_from_system().replace(":", "-").replace(" ", "_")
		var session_name_clean = session_name.replace(" ", "_") if not session_name.is_empty() else "session"
		final_path = (
			RuntimeConfig.get_readymade_data_dir()
			.path_join("reports")
			.path_join("edit_session_report_%s_%s%s" % [session_name_clean, timestamp, file_extension])
		)
	
	# Ensure reports directory exists
	_ensure_reports_directory()
	
	# Save report
	var file = FileAccess.open(final_path, FileAccess.WRITE)
	if not file:
		var error = "Failed to create report file: " + final_path
		push_error("DocumentSessionManager: " + error)
		export_failed.emit(error)
		return ""
	
	file.store_string(report_content)
	file.close()
	
	print("DocumentSessionManager: Generated %s report: %s" % [export_format_names[format], final_path])
	report_generated.emit(final_path, export_format_names[format])
	return final_path

func _compile_comprehensive_report_data() -> Dictionary:
	"""Compile all data for comprehensive reporting"""
	var report_data = {
		"metadata": {
			"report_generated": Time.get_datetime_string_from_system(),
			"session_name": session_name,
			"session_duration": _calculate_session_duration(),
			"edit_mode": current_edit_mode,
			"total_documents": active_documents.size(),
			"readymade_version": "Phase 4.6"
		},
		"session_overview": _get_enhanced_session_statistics(),
		"document_analysis": _get_detailed_document_analysis(),
		"change_timeline": _get_change_timeline(),
		"productivity_metrics": _calculate_productivity_metrics(),
		"collaboration_data": _analyze_collaboration_patterns(),
		"content_insights": _generate_content_insights(),
		"recommendations": _generate_improvement_recommendations()
	}
	
	return report_data

func _get_enhanced_session_statistics() -> Dictionary:
	"""Get enhanced session statistics with deeper analytics"""
	var base_stats = _calculate_session_statistics()
	
	# Add enhanced metrics
	base_stats["average_words_per_document"] = float(base_stats.total_words) / max(1, base_stats.total_documents)
	base_stats["average_edits_per_document"] = float(base_stats.total_edits) / max(1, base_stats.total_documents)
	base_stats["productivity_score"] = _calculate_productivity_score()
	base_stats["session_complexity"] = _calculate_session_complexity()
	base_stats["edit_distribution"] = _analyze_edit_distribution()
	base_stats["time_analysis"] = _analyze_time_patterns()
	
	return base_stats

func _get_detailed_document_analysis() -> Array:
	"""Get detailed analysis for each document"""
	var analysis = []
	
	for document in active_documents:
		var doc_analysis = {
			"name": document.file_name,
			"path": document.file_path,
			"is_primary": document.is_primary,
			"metrics": {
				"word_count": document.word_count,
				"character_count": document.content.length(),
				"line_count": document.content.split("\n").size(),
				"paragraph_count": _count_paragraphs(document.content)
			},
			"change_analysis": document.change_statistics,
			"content_quality": _analyze_content_quality(document),
			"edit_patterns": _analyze_edit_patterns(document),
			"time_analysis": _analyze_document_time_patterns(document)
		}
		analysis.append(doc_analysis)
	
	return analysis

func _get_change_timeline() -> Array:
	"""Generate chronological timeline of all changes"""
	var timeline = []
	
	for document in active_documents:
		for change in document.edit_history:
			timeline.append({
				"document": document.file_name,
				"timestamp": change.timestamp,
				"description": change.change_description,
				"change_type": change.change_type,
				"edit_mode": change.edit_mode,
				"significant": change.significant_change,
				"words_delta": change.get("words_delta", 0),
				"characters_delta": change.get("characters_delta", 0)
			})
	
	# Sort by timestamp
	timeline.sort_custom(func(a, b): return a.timestamp < b.timestamp)
	
	return timeline

func _calculate_productivity_metrics() -> Dictionary:
	"""Calculate comprehensive productivity metrics"""
	var metrics = {
		"words_per_minute": 0.0,
		"edits_per_minute": 0.0,
		"efficiency_score": 0.0,
		"focus_periods": [],
		"peak_productivity_time": "",
		"consistency_score": 0.0
	}
	
	var total_time = _calculate_session_duration()
	if total_time > 0:
		var total_words = _calculate_session_statistics().total_words
		var total_edits = _calculate_session_statistics().total_edits
		
		metrics.words_per_minute = (total_words / total_time) * 60.0
		metrics.edits_per_minute = (total_edits / total_time) * 60.0
		metrics.efficiency_score = _calculate_efficiency_score()
		metrics.focus_periods = _identify_focus_periods()
		metrics.peak_productivity_time = _find_peak_productivity_time()
		metrics.consistency_score = _calculate_consistency_score()
	
	return metrics

func _analyze_collaboration_patterns() -> Dictionary:
	"""Analyze collaboration patterns (future enhancement for multi-user)"""
	return {
		"single_user_session": true,
		"edit_modes_used": _calculate_session_statistics().edit_modes_used,
		"mode_transitions": _analyze_mode_transitions(),
		"collaborative_potential": _assess_collaborative_potential()
	}

func _generate_content_insights() -> Dictionary:
	"""Generate insights about content patterns and quality"""
	var insights = {
		"content_themes": _identify_content_themes(),
		"writing_style": _analyze_writing_style(),
		"document_relationships": _analyze_document_relationships(),
		"complexity_analysis": _analyze_content_complexity(),
		"improvement_areas": _identify_improvement_areas()
	}
	
	return insights

func _generate_improvement_recommendations() -> Array:
	"""Generate personalized improvement recommendations"""
	var recommendations = []
	var stats = _get_enhanced_session_statistics()
	
	# Productivity recommendations
	if stats.edit_distribution.get("frequent_small_edits", 0) > 0.7:
		recommendations.append({
			"category": "productivity",
			"title": "Consider Batch Editing",
			"description": "You make many small edits. Try batching related changes together for better flow.",
			"priority": "medium"
		})
	
	if stats.productivity_score < 0.5:
		recommendations.append({
			"category": "productivity", 
			"title": "Improve Editing Velocity",
			"description": "Your editing velocity could be improved. Consider using keyboard shortcuts and templates.",
			"priority": "high"
		})
	
	# Content quality recommendations
	for document in active_documents:
		var quality = _analyze_content_quality(document)
		if quality.get("readability_score", 1.0) < 0.6:
			recommendations.append({
				"category": "quality",
				"title": "Improve Readability in " + document.file_name,
				"description": "Consider shorter sentences and clearer structure for better readability.",
				"priority": "medium"
			})
	
	# Workflow recommendations
	if active_documents.size() > 3 and not _has_clear_primary_focus():
		recommendations.append({
			"category": "workflow",
			"title": "Focus on Primary Document",
			"description": "With multiple documents, ensure clear primary focus for better productivity.",
			"priority": "low"
		})
	
	return recommendations

# Export document functions
func export_document(document: DocumentContext, format: ExportFormat, export_path: String = "") -> String:
	"""Export a single document with change tracking information"""
	if not document:
		export_failed.emit("Invalid document provided for export")
		return ""
	
	var content = ""
	var file_extension = ""
	
	match format:
		ExportFormat.HTML:
			content = _export_document_as_html(document)
			file_extension = ".html"
		ExportFormat.MARKDOWN:
			content = _export_document_as_markdown(document)
			file_extension = ".md"
		ExportFormat.JSON:
			content = JSON.stringify(_export_document_as_json(document), "\t")
			file_extension = ".json"
		ExportFormat.PLAIN_TEXT:
			content = _export_document_as_text(document)
			file_extension = ".txt"
		ExportFormat.PDF_READY:
			content = _export_document_as_pdf_ready(document)
			file_extension = ".html"
	
	# Generate file path if not provided
	var final_path = export_path
	if final_path.is_empty():
		var timestamp = Time.get_datetime_string_from_system().replace(":", "-").replace(" ", "_")
		var doc_name = document.file_name.get_basename()
		final_path = (
			RuntimeConfig.get_readymade_data_dir()
			.path_join("exports")
			.path_join("%s_export_%s%s" % [doc_name, timestamp, file_extension])
		)
	
	# Ensure exports directory exists
	_ensure_exports_directory()
	
	# Save exported document
	var file = FileAccess.open(final_path, FileAccess.WRITE)
	if not file:
		var error = "Failed to create export file: " + final_path
		push_error("DocumentSessionManager: " + error)
		export_failed.emit(error)
		return ""
	
	file.store_string(content)
	file.close()
	
	print("DocumentSessionManager: Exported document '%s' as %s: %s" % [document.file_name, export_format_names[format], final_path])
	document_exported.emit(final_path, export_format_names[format])
	return final_path

func export_all_documents(format: ExportFormat, export_directory: String = "") -> Array:
	"""Export all documents in the session"""
	var exported_files = []
	var export_dir = export_directory
	
	if export_dir.is_empty():
		var timestamp = Time.get_datetime_string_from_system().replace(":", "-").replace(" ", "_")
		export_dir = (
			RuntimeConfig.get_readymade_data_dir()
			.path_join("exports")
			.path_join("session_export_%s" % timestamp)
			+ "/"
		)
	
	# Ensure export directory exists
	DirAccess.make_dir_recursive_absolute(export_dir)
	
	for document in active_documents:
		var doc_name = document.file_name.get_basename()
		var export_path = export_dir + doc_name + "_export"
		var exported_path = export_document(document, format, export_path)
		if not exported_path.is_empty():
			exported_files.append(exported_path)
	
	return exported_files

# Session sharing functions
func create_shareable_session_package() -> Dictionary:
	"""Create a package suitable for sharing with other users"""
	var share_package = {
		"version": "1.0",
		"created": Time.get_datetime_string_from_system(),
		"session_info": {
			"name": session_name,
			"edit_mode": current_edit_mode,
			"document_count": active_documents.size()
		},
		"session_summary": get_session_change_summary(),
		"documents": [],
		"analytics": _get_enhanced_session_statistics(),
		"sharing_metadata": {
			"anonymized": true,
			"includes_content": false,  # For privacy
			"includes_analytics": true
		}
	}
	
	# Add anonymized document information
	for i in range(active_documents.size()):
		var document = active_documents[i]
		share_package.documents.append({
			"id": "doc_%d" % i,
			"name": "Document_%d" % (i + 1),  # Anonymized name
			"word_count": document.word_count,
			"edit_count": document.change_statistics.get("total_edits", 0),
			"is_primary": document.is_primary,
			"change_summary": _get_anonymized_change_summary(document)
		})
	
	session_shared.emit(share_package)
	return share_package

func export_session_for_sharing(share_path: String = "") -> String:
	"""Export session package for sharing"""
	var share_data = create_shareable_session_package()
	
	var final_path = share_path
	if final_path.is_empty():
		var timestamp = Time.get_datetime_string_from_system().replace(":", "-").replace(" ", "_")
		final_path = (
			RuntimeConfig.get_readymade_data_dir()
			.path_join("shared")
			.path_join("session_share_%s.json" % timestamp)
		)
	
	# Ensure shared directory exists
	_ensure_shared_directory()
	
	# Save share package
	var file = FileAccess.open(final_path, FileAccess.WRITE)
	if not file:
		var error = "Failed to create share file: " + final_path
		push_error("DocumentSessionManager: " + error)
		export_failed.emit(error)
		return ""
	
	file.store_string(JSON.stringify(share_data, "\t"))
	file.close()
	
	print("DocumentSessionManager: Created shareable session package: %s" % final_path)
	return final_path

# Helper functions for export and reporting
func _ensure_reports_directory():
	"""Ensure reports directory exists under Documents/Synesyn"""
	DirAccess.make_dir_recursive_absolute(
		RuntimeConfig.get_readymade_data_dir().path_join("reports")
	)

func _ensure_exports_directory():
	"""Ensure exports directory exists under Documents/Synesyn"""
	DirAccess.make_dir_recursive_absolute(
		RuntimeConfig.get_readymade_data_dir().path_join("exports")
	)

func _ensure_shared_directory():
	"""Ensure shared directory exists under Documents/Synesyn"""
	DirAccess.make_dir_recursive_absolute(
		RuntimeConfig.get_readymade_data_dir().path_join("shared")
	)

func _calculate_session_duration() -> float:
	"""Calculate total session duration in seconds"""
	if active_documents.is_empty():
		return 0.0
	
	var earliest = active_documents[0].creation_time
	var latest = active_documents[0].last_modified
	
	for document in active_documents:
		if document.creation_time < earliest:
			earliest = document.creation_time
		if document.last_modified > latest:
			latest = document.last_modified
	
	return latest - earliest

func _calculate_productivity_score() -> float:
	"""Calculate overall productivity score (0.0 to 1.0)"""
	var stats = _calculate_session_statistics()
	var duration = _calculate_session_duration()
	
	if duration <= 0:
		return 0.0
	
	# Factors: words per minute, edits frequency, focus consistency
	var words_per_minute = (stats.total_words / duration) * 60.0
	var edits_per_minute = (stats.total_edits / duration) * 60.0
	
	# Normalize scores (these are example targets)
	var word_score = min(1.0, words_per_minute / 50.0)  # 50 WPM target
	var edit_score = min(1.0, edits_per_minute / 5.0)   # 5 edits/min target
	var focus_score = _calculate_focus_score()
	
	return (word_score + edit_score + focus_score) / 3.0

func _calculate_session_complexity() -> String:
	"""Calculate session complexity level"""
	var stats = _calculate_session_statistics()
	
	if stats.total_documents <= 1 and stats.total_edits <= 10:
		return "Simple"
	elif stats.total_documents <= 3 and stats.total_edits <= 50:
		return "Moderate"
	elif stats.total_documents <= 5 and stats.total_edits <= 150:
		return "Complex"
	else:
		return "Very Complex"

# Continue with more helper functions...
func _analyze_edit_distribution() -> Dictionary:
	"""Analyze distribution of edit types and patterns"""
	var distribution = {
		"frequent_small_edits": 0.0,
		"major_revisions": 0.0,
		"consistent_pace": 0.0,
		"burst_editing": 0.0
	}
	
	var total_edits = 0
	var small_edits = 0
	var major_edits = 0
	
	for document in active_documents:
		for change in document.edit_history:
			total_edits += 1
			var words_delta = abs(change.get("words_delta", 0))
			
			if words_delta <= 5:
				small_edits += 1
			elif words_delta >= 20:
				major_edits += 1
	
	if total_edits > 0:
		distribution.frequent_small_edits = float(small_edits) / total_edits
		distribution.major_revisions = float(major_edits) / total_edits
	
	return distribution

# Placeholder implementations for complex analysis functions
# These would be expanded with more sophisticated algorithms

func _analyze_time_patterns() -> Dictionary:
	"""Analyze editing time patterns"""
	return {
		"peak_hours": [],
		"average_session_length": _calculate_session_duration(),
		"editing_rhythm": "steady"  # Could be "burst", "steady", "inconsistent"
	}

func _count_paragraphs(content: String) -> int:
	"""Count paragraphs in content"""
	return content.split("\n\n").size()

func _analyze_content_quality(_document: DocumentContext) -> Dictionary:
	"""Analyze content quality metrics"""
	return {
		"readability_score": 0.75,  # Placeholder
		"structure_score": 0.8,
		"consistency_score": 0.7
	}

func _analyze_edit_patterns(_document: DocumentContext) -> Dictionary:
	"""Analyze editing patterns for a document"""
	return {
		"edit_frequency": "moderate",
		"revision_depth": "surface",
		"focus_areas": []
	}

func _analyze_document_time_patterns(document: DocumentContext) -> Dictionary:
	"""Analyze time patterns for a specific document"""
	return {
		"total_time": document.last_modified - document.creation_time,
		"active_editing_time": 0,  # Would need more sophisticated tracking
		"breaks_taken": 0
	}

func _calculate_efficiency_score() -> float:
	"""Calculate editing efficiency score"""
	return 0.75  # Placeholder - would use sophisticated metrics

func _identify_focus_periods() -> Array:
	"""Identify periods of focused editing"""
	return []  # Placeholder

func _find_peak_productivity_time() -> String:
	"""Find the time of day with peak productivity"""
	return "Unknown"  # Placeholder

# _calculate_consistency_score function moved to Phase 5.1 section with full implementation

func _analyze_mode_transitions() -> Dictionary:
	"""Analyze transitions between edit modes"""
	return {
		"total_transitions": 0,
		"most_used_transition": "developmental -> structural"
	}

func _assess_collaborative_potential() -> String:
	"""Assess potential for collaborative editing"""
	return "Medium"  # Based on document structure and edit patterns

func _identify_content_themes() -> Array:
	"""Identify themes in content across documents"""
	return []  # Would use text analysis

func _analyze_writing_style() -> Dictionary:
	"""Analyze writing style characteristics"""
	return {
		"formality_level": "moderate",
		"sentence_complexity": "moderate",
		"vocabulary_richness": "good"
	}

func _analyze_content_complexity() -> Dictionary:
	"""Analyze content complexity"""
	return {
		"reading_level": "intermediate",
		"concept_density": "moderate",
		"structural_complexity": "simple"
	}

func _identify_improvement_areas() -> Array:
	"""Identify areas for content improvement"""
	return []  # Would analyze patterns and suggest improvements

func _has_clear_primary_focus() -> bool:
	"""Check if session has clear primary document focus"""
	if not primary_document:
		return false
	
	var primary_edits = primary_document.change_statistics.get("total_edits", 0)
	var total_edits = _calculate_session_statistics().total_edits
	
	return primary_edits > (total_edits * 0.5)  # Primary doc has >50% of edits

func _calculate_focus_score() -> float:
	"""Calculate focus score based on editing patterns"""
	return 0.8  # Placeholder

func _get_anonymized_change_summary(document: DocumentContext) -> Dictionary:
	"""Get anonymized change summary for sharing"""
	return {
		"total_edits": document.change_statistics.get("total_edits", 0),
		"words_added": document.change_statistics.get("words_added", 0),
		"words_removed": document.change_statistics.get("words_removed", 0),
		"edit_velocity": document.change_statistics.get("change_velocity", 0.0)
	}

# Report generation functions for different formats
func _generate_html_report(data: Dictionary) -> String:
	"""Generate HTML report"""
	var html = """<!DOCTYPE html>
<html>
<head>
	<title>Edit Session Report - %s</title>
	<style>
		body { font-family: Arial, sans-serif; margin: 40px; }
		.header { background: #f0f0f0; padding: 20px; border-radius: 5px; }
		.section { margin: 20px 0; }
		.metric { background: #f9f9f9; padding: 10px; margin: 5px 0; border-left: 4px solid #007acc; }
		.document { border: 1px solid #ddd; padding: 15px; margin: 10px 0; border-radius: 5px; }
		.recommendation { background: #fff3cd; padding: 10px; margin: 5px 0; border-radius: 3px; }
		table { border-collapse: collapse; width: 100%%; }
		th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
		th { background-color: #f2f2f2; }
	</style>
</head>
<body>
	<div class="header">
		<h1>Edit Session Report</h1>
		<p><strong>Session:</strong> %s</p>
		<p><strong>Generated:</strong> %s</p>
		<p><strong>Duration:</strong> %.1f minutes</p>
	</div>
""" % [
		data.metadata.session_name,
		data.metadata.session_name,
		data.metadata.report_generated,
		data.metadata.session_duration / 60.0
	]
	
	# Add session overview
	html += "<div class='section'><h2>Session Overview</h2>\n"
	var overview = data.session_overview
	html += "<div class='metric'>Documents: %d</div>\n" % overview.total_documents
	html += "<div class='metric'>Total Words: %d</div>\n" % overview.total_words
	html += "<div class='metric'>Total Edits: %d</div>\n" % overview.total_edits
	html += "<div class='metric'>Productivity Score: %.1f%%</div>\n" % (overview.productivity_score * 100)
	html += "</div>\n"
	
	# Add document analysis
	html += "<div class='section'><h2>Document Analysis</h2>\n"
	for doc in data.document_analysis:
		html += "<div class='document'>\n"
		html += "<h3>%s %s</h3>\n" % [doc.name, "(PRIMARY)" if doc.is_primary else ""]
		html += "<p>Words: %d | Edits: %d</p>\n" % [doc.metrics.word_count, doc.change_analysis.get("total_edits", 0)]
		html += "</div>\n"
	html += "</div>\n"
	
	# Add recommendations
	if data.recommendations.size() > 0:
		html += "<div class='section'><h2>Recommendations</h2>\n"
		for rec in data.recommendations:
			html += "<div class='recommendation'><strong>%s:</strong> %s</div>\n" % [rec.title, rec.description]
		html += "</div>\n"
	
	html += "</body></html>"
	return html

func _generate_markdown_report(data: Dictionary) -> String:
	"""Generate Markdown report"""
	var md = "# Edit Session Report\n\n"
	md += "**Session:** %s  \n" % data.metadata.session_name
	md += "**Generated:** %s  \n" % data.metadata.report_generated
	md += "**Duration:** %.1f minutes  \n\n" % (data.metadata.session_duration / 60.0)
	
	md += "## Session Overview\n\n"
	var overview = data.session_overview
	md += "- **Documents:** %d\n" % overview.total_documents
	md += "- **Total Words:** %d\n" % overview.total_words
	md += "- **Total Edits:** %d\n" % overview.total_edits
	md += "- **Productivity Score:** %.1f%%\n\n" % (overview.productivity_score * 100)
	
	md += "## Document Analysis\n\n"
	for doc in data.document_analysis:
		md += "### %s %s\n\n" % [doc.name, "(PRIMARY)" if doc.is_primary else ""]
		md += "- Words: %d\n" % doc.metrics.word_count
		md += "- Edits: %d\n\n" % doc.change_analysis.get("total_edits", 0)
	
	if data.recommendations.size() > 0:
		md += "## Recommendations\n\n"
		for rec in data.recommendations:
			md += "- **%s:** %s\n" % [rec.title, rec.description]
	
	return md

func _generate_text_report(data: Dictionary) -> String:
	"""Generate plain text report"""
	var text = "EDIT SESSION REPORT\n"
	text += "==================================================\n\n"
	text += "Session: %s\n" % data.metadata.session_name
	text += "Generated: %s\n" % data.metadata.report_generated
	text += "Duration: %.1f minutes\n\n" % (data.metadata.session_duration / 60.0)
	
	text += "SESSION OVERVIEW\n"
	text += "--------------------\n"
	var overview = data.session_overview
	text += "Documents: %d\n" % overview.total_documents
	text += "Total Words: %d\n" % overview.total_words
	text += "Total Edits: %d\n" % overview.total_edits
	text += "Productivity Score: %.1f%%\n\n" % (overview.productivity_score * 100)
	
	text += "DOCUMENT ANALYSIS\n"
	text += "--------------------\n"
	for doc in data.document_analysis:
		text += "%s %s\n" % [doc.name, "(PRIMARY)" if doc.is_primary else ""]
		text += "  Words: %d | Edits: %d\n\n" % [doc.metrics.word_count, doc.change_analysis.get("total_edits", 0)]
	
	if data.recommendations.size() > 0:
		text += "RECOMMENDATIONS\n"
		text += "--------------------\n"
		for rec in data.recommendations:
			text += "- %s: %s\n" % [rec.title, rec.description]
	
	return text

func _generate_pdf_ready_html(data: Dictionary) -> String:
	"""Generate PDF-ready HTML with print styles"""
	var html = _generate_html_report(data)
	# Add print-specific CSS
	var print_css = """
	<style media="print">
		body { margin: 1in; }
		.header { page-break-after: avoid; }
		.document { page-break-inside: avoid; }
		@page { margin: 1in; }
	</style>
"""
	html = html.replace("</head>", print_css + "</head>")
	return html

func _generate_rtfd_report(data: Dictionary) -> String:
	"""Generate Rich Text Format report"""
	# Simplified RTF - would need more sophisticated formatting
	return _generate_text_report(data)

# Document export format functions
func _export_document_as_html(document: DocumentContext) -> String:
	"""Export document as HTML with change tracking info"""
	var html = """<!DOCTYPE html>
<html>
<head>
	<title>%s</title>
	<style>
		body { font-family: Arial, sans-serif; margin: 40px; line-height: 1.6; }
		.header { background: #f0f0f0; padding: 15px; border-radius: 5px; margin-bottom: 20px; }
		.content { background: white; padding: 20px; }
		.change-info { background: #e8f4f8; padding: 10px; margin: 10px 0; border-left: 4px solid #007acc; }
	</style>
</head>
<body>
	<div class="header">
		<h1>%s</h1>
		<p><strong>Word Count:</strong> %d | <strong>Edits:</strong> %d | <strong>Status:</strong> %s</p>
	</div>
	<div class="change-info">
		<h3>Change Summary</h3>
		<p>%s</p>
	</div>
	<div class="content">
		%s
	</div>
</body>
</html>""" % [
		document.file_name,
		document.file_name,
		document.word_count,
		document.change_statistics.get("total_edits", 0),
		"Unsaved Changes" if document.has_unsaved_changes() else "Saved",
		document.generate_change_summary().replace("\n", "<br>"),
		document.content.replace("\n", "<br>")
	]
	return html

func _export_document_as_markdown(document: DocumentContext) -> String:
	"""Export document as Markdown with change tracking info"""
	var md = "# %s\n\n" % document.file_name
	md += "**Word Count:** %d | **Edits:** %d | **Status:** %s\n\n" % [
		document.word_count,
		document.change_statistics.get("total_edits", 0),
		"Unsaved Changes" if document.has_unsaved_changes() else "Saved"
	]
	md += "## Change Summary\n\n"
	md += document.generate_change_summary() + "\n\n"
	md += "## Content\n\n"
	md += document.content
	return md

func _export_document_as_json(document: DocumentContext) -> Dictionary:
	"""Export document as JSON with complete metadata"""
	return {
		"document_info": {
			"name": document.file_name,
			"path": document.file_path,
			"word_count": document.word_count,
			"is_primary": document.is_primary
		},
		"content": document.content,
		"change_tracking": document.export_change_history(),
		"export_metadata": {
			"exported_at": Time.get_datetime_string_from_system(),
			"readymade_version": "Phase 4.6"
		}
	}

func _export_document_as_text(document: DocumentContext) -> String:
	"""Export document as plain text with change info header"""
	var text = "%s\n" % document.file_name
	text += "========================================\n\n"
	text += "Word Count: %d | Edits: %d | Status: %s\n\n" % [
		document.word_count,
		document.change_statistics.get("total_edits", 0),
		"Unsaved Changes" if document.has_unsaved_changes() else "Saved"
	]
	text += "CHANGE SUMMARY:\n"
	text += "--------------------\n"
	text += document.generate_change_summary() + "\n\n"
	text += "CONTENT:\n"
	text += "--------------------\n"
	text += document.content
	return text

func _export_document_as_pdf_ready(document: DocumentContext) -> String:
	"""Export document as PDF-ready HTML"""
	var html = _export_document_as_html(document)
	var print_css = """
	<style media="print">
		body { margin: 1in; }
		.header { page-break-after: avoid; }
		@page { margin: 1in; }
	</style>
"""
	html = html.replace("</head>", print_css + "</head>")
	return html

