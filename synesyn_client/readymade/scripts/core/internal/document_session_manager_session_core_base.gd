extends "res://readymade/scripts/core/internal/document_session_manager_base.gd"
class_name DocumentSessionManagerSessionCoreBase

func _ready():
	print("DocumentSessionManager: Initializing...")
	_load_session_preferences()
	print("DocumentSessionManager: Ready")

func _generate_session_id() -> String:
	"""Generate unique session ID for the session manager"""
	var timestamp = Time.get_unix_time_from_system()
	var random_suffix = randi() % 10000
	return "session_%d_%04d" % [timestamp, random_suffix]

func get_available_edit_modes() -> Array:
	"""Get list of available edit modes"""
	return edit_modes.duplicate()

func get_edit_mode_display_names() -> Dictionary:
	"""Get edit mode display names"""
	return edit_mode_display_names.duplicate()

func set_edit_mode(mode: String):
	"""Set current edit mode"""
	if mode in edit_modes:
		current_edit_mode = mode
		print("DocumentSessionManager: Edit mode changed to: ", mode)
	else:
		push_error("DocumentSessionManager: Invalid edit mode: " + mode)

func get_current_edit_mode() -> String:
	"""Get current edit mode"""
	return current_edit_mode

func load_document(file_path: String) -> DocumentContext:
	"""Load a document from file path"""
	print("DocumentSessionManager: Loading document: ", file_path)
	
	if not FileAccess.file_exists(file_path):
		push_error("DocumentSessionManager: File does not exist: " + file_path)
		return null
	
	# Check if document is already loaded
	for doc in active_documents:
		if doc.file_path == file_path:
			print("DocumentSessionManager: Document already loaded: ", file_path)
			return doc
	
	# Load file content
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		push_error("DocumentSessionManager: Failed to open file: " + file_path)
		return null
	
	var content = file.get_as_text()
	file.close()
	
	# Create document context
	var document = DocumentContext.new(file_path, content)
	active_documents.append(document)
	
	# Set as primary if it's the first document
	if active_documents.size() == 1:
		set_primary_document(document)
	
	document_loaded.emit(document)
	print("DocumentSessionManager: Document loaded successfully: ", document.file_name)
	
	return document

func load_document_from_string(content: String, doc_name: String = "Untitled") -> DocumentContext:
	"""Load a document from string content"""
	print("DocumentSessionManager: Loading document from string: ", doc_name)
	
	var document = DocumentContext.new("", content)
	document.file_name = doc_name
	active_documents.append(document)
	
	# Set as primary if it's the first document
	if active_documents.size() == 1:
		set_primary_document(document)
	
	document_loaded.emit(document)
	print("DocumentSessionManager: Document from string loaded successfully: ", doc_name)
	
	return document

func set_primary_document(document: DocumentContext):
	"""Set the primary document for editing"""
	if document in active_documents:
		# Clear previous primary
		if primary_document:
			primary_document.is_primary = false
		
		primary_document = document
		document.is_primary = true
		primary_document_changed.emit(document)
		print("DocumentSessionManager: Primary document set to: ", document.file_name)
	else:
		push_error("DocumentSessionManager: Cannot set primary - document not in active session")

func remove_document(document: DocumentContext):
	"""Remove a document from the session"""
	if document in active_documents:
		var was_primary = document.is_primary
		active_documents.erase(document)
		
		# If this was the primary document, set a new one
		if was_primary and active_documents.size() > 0:
			set_primary_document(active_documents[0])
		elif was_primary:
			primary_document = null
		
		document_removed.emit(document.file_path if not document.file_path.is_empty() else document.file_name)
		print("DocumentSessionManager: Document removed: ", document.file_name)

func clear_session():
	"""Clear all documents from the session"""
	active_documents.clear()
	primary_document = null
	session_cleared.emit()
	print("DocumentSessionManager: Session cleared")

func get_active_documents() -> Array:
	"""Get list of active documents"""
	return active_documents.duplicate()

func get_primary_document() -> DocumentContext:
	"""Get the primary document"""
	return primary_document

func get_document_by_path(file_path: String) -> DocumentContext:
	"""Get document by file path"""
	for doc in active_documents:
		if doc.file_path == file_path:
			return doc
	return null

func update_document_content(document: DocumentContext, new_content: String, change_source: String = "user"):
	"""Update content of a document with change tracking"""
	if document in active_documents:
		document.update_content(new_content, current_edit_mode, change_source)
		print("DocumentSessionManager: Document content updated: ", document.file_name)
	else:
		push_error("DocumentSessionManager: Cannot update document not in active session")

func save_document(document: DocumentContext) -> bool:
	"""Save document to file"""
	if document.file_path.is_empty():
		push_error("DocumentSessionManager: Cannot save - no file path set")
		return false
	
	var file = FileAccess.open(document.file_path, FileAccess.WRITE)
	if not file:
		push_error("DocumentSessionManager: Failed to open file for writing: " + document.file_path)
		return false
	
	file.store_string(document.content)
	file.close()
	
	# Update original content to mark as saved
	document.original_content = document.content
	print("DocumentSessionManager: Document saved: ", document.file_name)
	return true

func save_document_as(document: DocumentContext, file_path: String) -> bool:
	"""Save document to a new file path"""
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if not file:
		push_error("DocumentSessionManager: Failed to open file for writing: " + file_path)
		return false
	
	file.store_string(document.content)
	file.close()
	
	# Update document paths
	document.file_path = file_path
	document.file_name = file_path.get_file()
	document.original_content = document.content
	
	print("DocumentSessionManager: Document saved as: ", file_path)
	return true

func get_session_summary() -> Dictionary:
	"""Get summary of current session"""
	var total_words = 0
	var documents_with_changes = 0
	
	for doc in active_documents:
		total_words += doc.word_count
		if doc.has_unsaved_changes():
			documents_with_changes += 1
	
	return {
		"document_count": active_documents.size(),
		"total_words": total_words,
		"primary_document": primary_document.file_name if primary_document else "None",
		"unsaved_changes": documents_with_changes,
		"edit_mode": current_edit_mode
	}

func get_multi_document_context() -> Dictionary:
	"""Get comprehensive context for multi-document sessions"""
	var context = {
		"session_summary": get_session_summary(),
		"primary_document": null,
		"additional_documents": [],
		"relationships": [],
		"cross_references": []
	}
	
	if primary_document:
		context.primary_document = {
			"name": primary_document.file_name,
			"word_count": primary_document.word_count,
			"preview": _get_document_preview(primary_document),
			"last_modified": primary_document.last_modified,
			"has_changes": primary_document.has_unsaved_changes()
		}
	
	# Add additional documents
	for doc in active_documents:
		if doc != primary_document:
			context.additional_documents.append({
				"name": doc.file_name,
				"word_count": doc.word_count,
				"preview": _get_document_preview(doc),
				"last_modified": doc.last_modified,
				"has_changes": doc.has_unsaved_changes()
			})
	
	# Analyze relationships between documents
	context.relationships = _analyze_document_relationships()
	
	return context

func _get_document_preview(document: DocumentContext, lines: int = 3) -> String:
	"""Get a preview of document content"""
	var preview_lines = document.content.split("\n", false, lines + 1)
	var preview = ""
	
	for i in range(min(lines, preview_lines.size())):
		preview += preview_lines[i] + "\n"
	
	if preview_lines.size() > lines:
		preview += "..."
	
	return preview.strip_edges()

func _analyze_document_relationships() -> Array:
	"""Analyze relationships between documents in the session"""
	var relationships = []
	
	if active_documents.size() < 2:
		return relationships
	
	# Simple relationship analysis - could be enhanced with more sophisticated NLP
	for i in range(active_documents.size()):
		for j in range(i + 1, active_documents.size()):
			var doc1 = active_documents[i]
			var doc2 = active_documents[j]
			
			var relationship = _compare_documents(doc1, doc2)
			if relationship.similarity > 0.1:  # Threshold for considering documents related
				relationships.append(relationship)
	
	return relationships

func _compare_documents(doc1: DocumentContext, doc2: DocumentContext) -> Dictionary:
	"""Compare two documents for similarities and relationships"""
	var words1 = _extract_keywords(doc1.content)
	var words2 = _extract_keywords(doc2.content)
	
	var common_words = []
	var total_unique_words = 0
	
	for word in words1:
		if word in words2:
			common_words.append(word)
	
	total_unique_words = len(words1) + len(words2) - len(common_words)
	var similarity = float(len(common_words)) / max(1, total_unique_words)
	
	return {
		"doc1_name": doc1.file_name,
		"doc2_name": doc2.file_name,
		"similarity": similarity,
		"common_keywords": common_words.slice(0, 10),  # Top 10 common words
		"relationship_type": _classify_relationship(similarity)
	}

func _extract_keywords(content: String) -> Array:
	"""Extract keywords from document content (simplified implementation)"""
	var words = content.to_lower().split(" ", false)
	var filtered_words = []
	
	# Simple stop words (could be expanded)
	var stop_words = ["the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for", "of", "with", "by", "is", "are", "was", "were", "be", "been", "have", "has", "had", "do", "does", "did", "will", "would", "should", "could", "may", "might", "must", "can", "this", "that", "these", "those", "i", "you", "he", "she", "it", "we", "they", "me", "him", "her", "us", "them"]
	
	for word in words:
		# Remove punctuation and filter short words and stop words
		word = _remove_punctuation(word).strip_edges()
		if word.length() > 3 and word not in stop_words:
			filtered_words.append(word)
	
	return filtered_words

func _classify_relationship(similarity: float) -> String:
	"""Classify the relationship between documents based on similarity"""
	if similarity > 0.7:
		return "highly_related"
	elif similarity > 0.4:
		return "moderately_related"
	elif similarity > 0.1:
		return "somewhat_related"
	else:
		return "unrelated"

func get_document_context_for_llm(include_all_documents: bool = false) -> Dictionary:
	"""Get formatted document context for LLM prompts"""
	var context = {
		"session_info": get_session_summary(),
		"primary_document": null,
		"supporting_documents": [],
		"context_type": "single_document"
	}
	
	if not primary_document:
		return context
	
	# Always include primary document
	context.primary_document = {
		"name": primary_document.file_name,
		"content_preview": _get_document_preview(primary_document, 5),
		"word_count": primary_document.word_count,
		"edit_mode": current_edit_mode
	}
	
	# Include additional documents if requested
	if include_all_documents and active_documents.size() > 1:
		context.context_type = "multi_document"
		
		for doc in active_documents:
			if doc != primary_document:
				context.supporting_documents.append({
					"name": doc.file_name,
					"content_preview": _get_document_preview(doc, 3),
					"word_count": doc.word_count,
					"relationship_to_primary": _get_relationship_to_primary(doc)
				})
	
	return context

func _get_relationship_to_primary(document: DocumentContext) -> String:
	"""Get the relationship of a document to the primary document"""
	if not primary_document:
		return "no_primary"
	
	var comparison = _compare_documents(primary_document, document)
	return comparison.relationship_type

func switch_primary_document(new_primary: DocumentContext):
	"""Switch primary document with enhanced context preservation"""
	if new_primary not in active_documents:
		push_error("DocumentSessionManager: Cannot switch to document not in session")
		return
	
	var old_primary = primary_document
	set_primary_document(new_primary)
	
	# Log the context switch
	print("DocumentSessionManager: Switched primary document from '%s' to '%s'" % [
		old_primary.file_name if old_primary else "None",
		new_primary.file_name
	])

func get_documents_by_type() -> Dictionary:
	"""Categorize documents by their apparent type/purpose"""
	var categorized = {
		"primary": [],
		"drafts": [],
		"research": [],
		"notes": [],
		"references": [],
		"other": []
	}
	
	for doc in active_documents:
		var category = _categorize_document(doc)
		if category in categorized:
			categorized[category].append(doc)
		else:
			categorized.other.append(doc)
	
	return categorized

func _categorize_document(document: DocumentContext) -> String:
	"""Categorize a document based on its name and content"""
	var name_lower = document.file_name.to_lower()
	
	# Simple categorization based on filename patterns
	if "draft" in name_lower or "version" in name_lower:
		return "drafts"
	elif "research" in name_lower or "source" in name_lower or "reference" in name_lower:
		return "research"
	elif "notes" in name_lower or "todo" in name_lower or "ideas" in name_lower:
		return "notes"
	elif "ref" in name_lower or "bib" in name_lower or "citation" in name_lower:
		return "references"
	elif document.is_primary:
		return "primary"
	else:
		return "other"

func _load_session_preferences():
	"""Load session preferences from project settings"""
	if ProjectSettings.has_setting("readymade/default_edit_mode"):
		var saved_mode = ProjectSettings.get_setting("readymade/default_edit_mode", "developmental")
		if saved_mode in edit_modes:
			current_edit_mode = saved_mode
			print("DocumentSessionManager: Loaded edit mode preference: ", saved_mode)

func _save_session_preferences():
	"""Save session preferences to project settings"""
	ProjectSettings.set_setting("readymade/default_edit_mode", current_edit_mode)
	var err = ProjectSettings.save()
	if err != OK:
		push_error("DocumentSessionManager: Failed to save preferences: " + str(err))
	else:
		print("DocumentSessionManager: Saved edit mode preference: ", current_edit_mode)

# === SESSION SAVE/LOAD FUNCTIONALITY ===


func save_session(session_path: String = "") -> bool:
	"""Save complete editing session with change tracking"""
	var save_path = session_path
	if save_path.is_empty():
		save_path = _generate_default_session_path()
	
	var session_data = {
		"session_info": {
			"version": "1.0",
			"created": Time.get_unix_time_from_system(),
			"session_name": session_name,
			"edit_mode": current_edit_mode,
			"primary_document_path": primary_document.file_path if primary_document else ""
		},
		"documents": [],
		"relationships": _analyze_document_relationships(),
		"session_statistics": _calculate_session_statistics()
	}
	
	# Export all documents with their change history
	for document in active_documents:
		var doc_data = document.export_change_history()
		doc_data["is_primary"] = document.is_primary
		session_data.documents.append(doc_data)
	
	# Save session file
	var file = FileAccess.open(save_path, FileAccess.WRITE)
	if not file:
		var error = "Failed to create session file: " + save_path
		push_error("DocumentSessionManager: " + error)
		session_save_failed.emit(error)
		return false
	
	file.store_string(JSON.stringify(session_data))
	file.close()
	
	print("DocumentSessionManager: Session saved to: ", save_path)
	session_saved.emit(save_path)
	return true

func load_session(session_path: String) -> bool:
	"""Load editing session with change tracking"""
	if not FileAccess.file_exists(session_path):
		var error = "Session file does not exist: " + session_path
		push_error("DocumentSessionManager: " + error)
		session_load_failed.emit(error)
		return false
	
	var file = FileAccess.open(session_path, FileAccess.READ)
	if not file:
		var error = "Failed to open session file: " + session_path
		push_error("DocumentSessionManager: " + error)
		session_load_failed.emit(error)
		return false
	
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var parse_result = json.parse(json_string)
	
	if parse_result != OK:
		var error = "Failed to parse session file: " + session_path
		push_error("DocumentSessionManager: " + error)
		session_load_failed.emit(error)
		return false
	
	var session_data = json.data
	
	# Validate session data
	if not session_data.has_all(["session_info", "documents"]):
		var error = "Invalid session file format: " + session_path
		push_error("DocumentSessionManager: " + error)
		session_load_failed.emit(error)
		return false
	
	# Clear current session
	clear_session()
	
	# Restore session info
	var session_info = session_data.session_info
	session_name = session_info.get("session_name", "")
	current_edit_mode = session_info.get("edit_mode", "developmental")
	
	# Load documents
	var primary_doc_path = session_info.get("primary_document_path", "")
	var loaded_primary = null
	
	for doc_data in session_data.documents:
		var document = _restore_document_from_data(doc_data)
		if document:
			active_documents.append(document)
			if doc_data.get("is_primary", false) or document.file_path == primary_doc_path:
				loaded_primary = document
	
	# Set primary document
	if loaded_primary:
		set_primary_document(loaded_primary)
	elif active_documents.size() > 0:
		set_primary_document(active_documents[0])
	
	print("DocumentSessionManager: Session loaded from: ", session_path)
	print("DocumentSessionManager: Loaded %d documents" % active_documents.size())
	session_loaded.emit(session_path)
	return true

func _generate_default_session_path() -> String:
	"""Generate default session file path under Documents/Synesyn"""
	var timestamp = Time.get_unix_time_from_system()
	var session_dir: String = (
		RuntimeConfig.get_readymade_data_dir().path_join("sessions") + "/"
	)
	var error: Error = DirAccess.make_dir_recursive_absolute(session_dir)
	if error != OK and error != ERR_ALREADY_EXISTS:
		push_warning("DocumentSessionManager: Failed to create sessions directory: " + str(error))
	
	return session_dir + "session_%d.json" % timestamp

func _restore_document_from_data(doc_data: Dictionary) -> DocumentContext:
	"""Restore document from session data"""
	var doc_info = doc_data.get("document_info", {})
	var content_info = doc_data.get("content_info", {})
	
	var file_path = doc_info.get("file_path", "")
	var current_content = ""
	
	# Try to load current content from file if it exists
	if not file_path.is_empty() and FileAccess.file_exists(file_path):
		var file = FileAccess.open(file_path, FileAccess.READ)
		if file:
			current_content = file.get_as_text()
			file.close()
	else:
		# Use content from session if file doesn't exist
		current_content = content_info.get("current_content", "")
	
	# Create document
	var document = DocumentContext.new(file_path, current_content)
	
	# Import change history
	if not document.import_change_history(doc_data):
		push_warning("DocumentSessionManager: Failed to import change history for: " + document.file_name)
	
	return document

func _calculate_session_statistics() -> Dictionary:
	"""Calculate overall session statistics"""
	var stats = {
		"total_documents": active_documents.size(),
		"total_words": 0,
		"total_edits": 0,
		"total_time_span": 0,
		"edit_modes_used": [],
		"documents_with_changes": 0
	}
	
	var earliest_creation = 0
	var latest_modification = 0
	
	for document in active_documents:
		stats.total_words += document.word_count
		stats.total_edits += document.change_statistics.get("total_edits", 0)
		
		if document.has_unsaved_changes():
			stats.documents_with_changes += 1
		
		# Track edit modes used across all documents
		var doc_modes = document.change_statistics.get("edit_modes_used", [])
		for mode in doc_modes:
			if mode not in stats.edit_modes_used:
				stats.edit_modes_used.append(mode)
		
		# Track time span
		if earliest_creation == 0 or document.creation_time < earliest_creation:
			earliest_creation = document.creation_time
		if document.last_modified > latest_modification:
			latest_modification = document.last_modified
	
	if earliest_creation > 0:
		stats.total_time_span = latest_modification - earliest_creation
	
	return stats

func get_session_change_summary() -> String:
	"""Generate comprehensive session change summary"""
	var summary = "Edit Session Change Summary\n"
	summary += "========================================\n\n"
	
	var stats = _calculate_session_statistics()
	
	# Overall session info
	summary += "Session Overview:\n"
	summary += "• Documents: %d\n" % stats.total_documents
	summary += "• Total words: %d\n" % stats.total_words
	summary += "• Total edits: %d\n" % stats.total_edits
	summary += "• Documents with changes: %d\n" % stats.documents_with_changes
	summary += "• Edit modes used: %s\n" % ", ".join(stats.edit_modes_used)
	
	if stats.total_time_span > 0:
		var hours = stats.total_time_span / 3600
		var minutes = (stats.total_time_span % 3600) / 60
		summary += "• Session duration: %d hours, %d minutes\n" % [hours, minutes]
	
	summary += "\n"
	
	# Individual document summaries
	summary += "Document Details:\n"
	for i in range(active_documents.size()):
		var document = active_documents[i]
		summary += "\n%d. %s %s\n" % [i + 1, document.file_name, "(PRIMARY)" if document.is_primary else ""]
		
		var doc_stats = document.change_statistics
		summary += "   • Edits: %d\n" % doc_stats.get("total_edits", 0)
		summary += "   • Words: %d (+%d/-%d)\n" % [
			document.word_count,
			doc_stats.get("words_added", 0),
			doc_stats.get("words_removed", 0)
		]
		summary += "   • Edit velocity: %.1f changes/min\n" % doc_stats.get("change_velocity", 0.0)
		
		if document.has_unsaved_changes():
			summary += "   • Status: HAS UNSAVED CHANGES\n"
		else:
			summary += "   • Status: Saved\n"
	
	return summary

func export_session_for_analysis() -> Dictionary:
	"""Export session data for external analysis"""
	var export_data = {
		"session_metadata": {
			"export_time": Time.get_unix_time_from_system(),
			"session_name": session_name,
			"edit_mode": current_edit_mode
		},
		"documents": [],
		"session_statistics": _calculate_session_statistics(),
		"relationships": _analyze_document_relationships()
	}
	
	for document in active_documents:
		export_data.documents.append({
			"name": document.file_name,
			"path": document.file_path,
			"change_history": document.get_change_history_summary(),
			"change_summary": document.generate_change_summary()
		})
	
	return export_data

func _remove_punctuation(text: String) -> String:
	"""Remove common punctuation from text"""
	var punctuation = ".,!?;:\"'()[]{}$%^&*-+=<>|\\/@#~`"
	var result = ""
	
	for ch in text:
		if not ch in punctuation:
			result += ch
	
	return result 

