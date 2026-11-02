extends Node
## Base state and virtual surface for DocumentSessionManager split.

## ReadyMade Document Session Manager - Handles document editing sessions
## This singleton manages document contexts, multi-document sessions, and editing state

signal document_loaded(document)
signal primary_document_changed(document)
signal document_removed(document_path: String)
signal session_cleared()

# Document context class to hold document metadata and content
class DocumentContext:
	var file_path: String = ""
	var file_name: String = ""
	var content: String = ""
	var original_content: String = ""
	var last_modified: int = 0
	var word_count: int = 0
	var is_primary: bool = false
	var selection_start: int = -1
	var selection_end: int = -1
	var edit_history = []  # Array[Dictionary]
	var syntree_analysis: Dictionary = {}
	
	# Enhanced change tracking
	var change_statistics: Dictionary = {}
	var edit_session_id: String = ""
	var creation_time: int = 0
	var last_auto_save: int = 0
	var change_markers = []  # Array[Dictionary]
	
	# === PHASE 5.2: PERFORMANCE OPTIMIZATION ===
	# Lazy loading properties
	var is_fully_loaded: bool = false
	var file_size: int = 0
	var content_chunks: Array = []  # For large documents
	var chunk_size: int = 50000  # 50KB chunks
	var loaded_chunks: Dictionary = {}  # chunk_index -> content
	var is_large_document: bool = false
	var large_doc_threshold: int = 100000  # 100KB threshold
	
	# Context window management
	var context_windows: Array = []  # Managed context windows for LLM
	var max_context_tokens: int = 8000  # Default context limit
	var current_context_usage: int = 0
	var context_priorities: Dictionary = {}  # Track priority sections
	var context_window_cache: Dictionary = {}  # Cache processed contexts
	
	# Performance metrics
	var performance_metrics: Dictionary = {
		"load_time": 0.0,
		"processing_time": 0.0,
		"memory_usage": 0,
		"chunk_load_times": {},
		"context_generation_time": 0.0,
		"ui_render_time": 0.0,
		"last_performance_check": 0
	}
	
	# Memory management
	var memory_monitor: Dictionary = {
		"content_size": 0,
		"edit_history_size": 0,
		"chunk_cache_size": 0,
		"context_cache_size": 0,
		"total_memory_footprint": 0
	}
	
	func _init(path: String = "", text: String = ""):
		var start_time := float(Time.get_unix_time_from_system())
		
		if not path.is_empty():
			file_path = path
			file_name = path.get_file()
			
			# Check file size for lazy loading decision
			if FileAccess.file_exists(path):
				var file = FileAccess.open(path, FileAccess.READ)
				if file:
					file_size = file.get_length()
					file.close()
					is_large_document = file_size > large_doc_threshold
		
		# Initialize content with lazy loading consideration
		if is_large_document and not text.is_empty():
			_initialize_lazy_loading(text)
		else:
			content = text
			original_content = text
			is_fully_loaded = true
		
		creation_time = int(Time.get_unix_time_from_system())
		last_modified = creation_time
		edit_session_id = _generate_session_id()
		_calculate_word_count()
		_initialize_change_statistics()
		_initialize_performance_tracking()
		
		# Track initialization time
		performance_metrics.load_time = float(Time.get_unix_time_from_system()) - start_time
		
	func _initialize_lazy_loading(full_content: String):
		"""Initialize lazy loading for large documents"""
		if full_content.length() < large_doc_threshold:
			content = full_content
			original_content = full_content
			is_fully_loaded = true
			return
		
		# Split content into chunks
		var total_length = full_content.length()
		var chunk_count = int((total_length + chunk_size - 1) / float(chunk_size))
		
		for i in range(chunk_count):
			var start_pos = i * chunk_size
			var end_pos = min(start_pos + chunk_size, total_length)
			var chunk_content = full_content.substr(start_pos, end_pos - start_pos)
			content_chunks.append(chunk_content)
		
		# Load first chunk immediately
		if content_chunks.size() > 0:
			loaded_chunks[0] = content_chunks[0]
			content = content_chunks[0]
			original_content = content_chunks[0]
		
		is_fully_loaded = false
		print("DocumentContext: Initialized lazy loading for large document (%d chunks)" % chunk_count)
	
	func ensure_chunk_loaded(chunk_index: int) -> bool:
		"""Ensure specific chunk is loaded into memory"""
		if chunk_index >= content_chunks.size():
			return false
		
		if chunk_index in loaded_chunks:
			return true
		
		var start_time = Time.get_unix_time_from_system()
		loaded_chunks[chunk_index] = content_chunks[chunk_index]
		
		# Track chunk load performance
		var load_time = Time.get_unix_time_from_system() - start_time
		performance_metrics.chunk_load_times[chunk_index] = load_time
		
		# Update memory usage
		_update_memory_usage()
		
		return true
	
	func get_content_window(start_pos: int, length: int) -> String:
		"""Get content window with lazy loading support"""
		if is_fully_loaded:
			return content.substr(start_pos, length)
		
		# Calculate which chunks are needed
		var end_pos = start_pos + length
		var start_chunk = int(start_pos / float(chunk_size))
		var end_chunk = int(end_pos / float(chunk_size))
		
		var window_content = ""
		for chunk_idx in range(start_chunk, end_chunk + 1):
			if ensure_chunk_loaded(chunk_idx):
				var chunk_start = max(0, start_pos - chunk_idx * chunk_size)
				var chunk_end = min(chunk_size, end_pos - chunk_idx * chunk_size)
				
				if chunk_end > chunk_start:
					window_content += loaded_chunks[chunk_idx].substr(chunk_start, chunk_end - chunk_start)
		
		return window_content
	
	func get_full_content() -> String:
		"""Get complete document content, loading all chunks if necessary"""
		if is_fully_loaded:
			return content
		
		var start_time = Time.get_unix_time_from_system()
		
		# Load all chunks
		var full_content = ""
		for i in range(content_chunks.size()):
			ensure_chunk_loaded(i)
			full_content += loaded_chunks[i]
		
		content = full_content
		original_content = full_content
		is_fully_loaded = true
		
		performance_metrics.processing_time = Time.get_unix_time_from_system() - start_time
		_update_memory_usage()
		
		return content
	
	func create_context_window(max_tokens: int = 8000, priority_sections: Array = []) -> Dictionary:
		"""Create optimized context window for LLM processing"""
		var start_time = Time.get_unix_time_from_system()
		
		# Check cache first
		var cache_key = "%d_%s" % [max_tokens, str(priority_sections)]
		if cache_key in context_window_cache:
			return context_window_cache[cache_key]
		
		var context_window = {
			"content": "",
			"tokens_used": 0,
			"sections_included": [],
			"truncated": false,
			"priority_content": "",
			"supporting_content": "",
			"metadata": {
				"file_name": file_name,
				"word_count": word_count,
				"selection_info": "",
				"context_type": "optimized"
			}
		}
		
		# Estimate tokens (roughly 4 chars per token)
		var available_tokens = max_tokens - 500  # Reserve space for metadata
		var _available_chars = available_tokens * 4
		
		# Build context prioritizing important sections
		var context_content = ""
		var tokens_used = 0
		
		# Add priority sections first
		for section in priority_sections:
			if section.has("content") and section.has("priority"):
				var section_content = section.content
				var section_tokens = section_content.length() / 4
				
				if tokens_used + section_tokens <= available_tokens:
					context_content += section_content + "\n\n"
					tokens_used += section_tokens
					context_window.sections_included.append(section.get("title", "Priority Section"))
		
		# Add general content if space remains
		if tokens_used < available_tokens * 0.8:  # Use 80% for priority, 20% for general
			var remaining_tokens = available_tokens - tokens_used
			var remaining_chars = remaining_tokens * 4
			
			var general_content = ""
			if is_fully_loaded:
				general_content = content
			else:
				# Get strategic chunks for unfilled content
				var chunk_samples = _get_strategic_chunks(remaining_chars)
				general_content = chunk_samples
			
			if general_content.length() > remaining_chars:
				general_content = general_content.substr(0, remaining_chars)
				context_window.truncated = true
			
			context_content += general_content
			tokens_used += int(general_content.length() / 4.0)
		
		# Finalize context window
		context_window.content = context_content
		context_window.tokens_used = tokens_used
		context_window.metadata.selection_info = "Selected %d sections, %d tokens" % [context_window.sections_included.size(), tokens_used]
		
		# Cache the result
		context_window_cache[cache_key] = context_window
		
		# Track performance
		performance_metrics.context_generation_time = Time.get_unix_time_from_system() - start_time
		
		return context_window
	
	func _get_strategic_chunks(max_chars: int) -> String:
		"""Get strategic content chunks for context when not fully loaded"""
		var strategic_content = ""
		var chars_used = 0
		
		# Always include beginning
		if ensure_chunk_loaded(0):
			var chunk_content = loaded_chunks[0]
			var chunk_portion = min(chunk_content.length(), int(max_chars / 3.0))
			strategic_content += chunk_content.substr(0, chunk_portion)
			chars_used += chunk_portion
		
		# Include middle if available
		if content_chunks.size() > 2 and chars_used < max_chars:
			var middle_chunk = int(content_chunks.size() / 2.0)
			if ensure_chunk_loaded(middle_chunk):
				var remaining_chars = max_chars - chars_used
				var chunk_content = loaded_chunks[middle_chunk]
				var chunk_portion = min(chunk_content.length(), int(remaining_chars / 2.0))
				strategic_content += "\n\n... [middle section] ...\n\n"
				strategic_content += chunk_content.substr(0, chunk_portion)
				chars_used += chunk_portion
		
		# Include end if available
		if content_chunks.size() > 1 and chars_used < max_chars:
			var last_chunk = content_chunks.size() - 1
			if ensure_chunk_loaded(last_chunk):
				var remaining_chars = max_chars - chars_used
				var chunk_content = loaded_chunks[last_chunk]
				var chunk_portion = min(chunk_content.length(), remaining_chars)
				strategic_content += "\n\n... [end section] ...\n\n"
				strategic_content += chunk_content.substr(max(0, chunk_content.length() - chunk_portion))
		
		return strategic_content
	
	func _update_memory_usage():
		"""Update memory usage tracking"""
		memory_monitor.content_size = content.length()
		memory_monitor.edit_history_size = str(edit_history).length()
		memory_monitor.chunk_cache_size = 0
		
		for chunk_content in loaded_chunks.values():
			memory_monitor.chunk_cache_size += chunk_content.length()
		
		memory_monitor.context_cache_size = 0
		for cached_context in context_window_cache.values():
			memory_monitor.context_cache_size += str(cached_context).length()
		
		memory_monitor.total_memory_footprint = (
			memory_monitor.content_size +
			memory_monitor.edit_history_size +
			memory_monitor.chunk_cache_size +
			memory_monitor.context_cache_size
		)
	
	func optimize_memory_usage():
		"""Optimize memory usage by clearing unnecessary caches"""
		var start_time = Time.get_unix_time_from_system()
		
		# Clear old context cache entries
		if context_window_cache.size() > 10:
			context_window_cache.clear()
		
		# Unload non-essential chunks if memory usage is high
		if memory_monitor.total_memory_footprint > 1000000:  # 1MB threshold
			var chunks_to_unload = []
			
			# Keep first, last, and recently accessed chunks
			for chunk_idx in loaded_chunks.keys():
				if chunk_idx != 0 and chunk_idx != content_chunks.size() - 1:
					# Check if recently accessed (simple heuristic)
					var load_time = performance_metrics.chunk_load_times.get(chunk_idx, 0)
					if load_time < Time.get_unix_time_from_system() - 300:  # 5 minutes ago
						chunks_to_unload.append(chunk_idx)
			
			# Unload half of the identified chunks
			for i in range(int(chunks_to_unload.size() / 2.0)):
				loaded_chunks.erase(chunks_to_unload[i])
		
		_update_memory_usage()
		
		var optimization_time = Time.get_unix_time_from_system() - start_time
		performance_metrics.last_performance_check = Time.get_unix_time_from_system()
		
		print("DocumentContext: Memory optimized in %.3f seconds" % optimization_time)
	
	func get_performance_report() -> Dictionary:
		"""Get comprehensive performance report"""
		_update_memory_usage()
		
		return {
			"document_info": {
				"file_name": file_name,
				"file_size": file_size,
				"is_large_document": is_large_document,
				"is_fully_loaded": is_fully_loaded,
				"chunks_total": content_chunks.size(),
				"chunks_loaded": loaded_chunks.size()
			},
			"performance_metrics": performance_metrics.duplicate(),
			"memory_usage": memory_monitor.duplicate(),
			"context_management": {
				"context_cache_entries": context_window_cache.size(),
				"max_context_tokens": max_context_tokens,
				"current_context_usage": current_context_usage
			},
			"optimization_suggestions": _get_optimization_suggestions()
		}
	
	func _get_optimization_suggestions() -> Array:
		"""Get optimization suggestions based on current performance"""
		var suggestions = []
		
		if memory_monitor.total_memory_footprint > 2000000:  # 2MB
			suggestions.append("Consider clearing edit history or optimizing memory usage")
		
		if loaded_chunks.size() > 10:
			suggestions.append("Large number of chunks loaded - consider memory optimization")
		
		if context_window_cache.size() > 20:
			suggestions.append("Context cache is large - consider clearing old entries")
		
		if not is_fully_loaded and performance_metrics.chunk_load_times.size() > 0:
			var avg_load_time = 0.0
			for time in performance_metrics.chunk_load_times.values():
				avg_load_time += time
			avg_load_time /= performance_metrics.chunk_load_times.size()
			
			if avg_load_time > 0.1:  # 100ms
				suggestions.append("Chunk loading is slow - consider optimizing I/O operations")
		
		return suggestions
	
	func _initialize_performance_tracking():
		"""Initialize performance tracking for this document"""
		performance_metrics.last_performance_check = Time.get_unix_time_from_system()
		_update_memory_usage()
	
	func _generate_session_id() -> String:
		"""Generate unique session ID for this document"""
		var timestamp = Time.get_unix_time_from_system()
		var random_suffix = randi() % 10000
		return "session_%d_%04d" % [timestamp, random_suffix]
	
	func _initialize_change_statistics():
		"""Initialize change tracking statistics"""
		change_statistics = {
			"total_edits": 0,
			"words_added": 0,
			"words_removed": 0,
			"characters_added": 0,
			"characters_removed": 0,
			"edit_modes_used": [],
			"time_spent_editing": 0,
			"last_significant_change": 0,
			"change_velocity": 0.0  # changes per minute
		}
	
	func _calculate_word_count():
		# Simple word count - split by whitespace and filter empty strings
		var words = content.split(" ", false)
		word_count = words.size()
	
	func update_content(new_content: String, edit_mode: String = "", change_source: String = "user"):
		"""Update document content and track changes with enhanced tracking"""
		if new_content != content:
			var timestamp = int(Time.get_unix_time_from_system())
			var _old_word_count = word_count
			var _old_char_count = content.length()
			
			# Calculate detailed changes
			var change_analysis = _analyze_content_changes(content, new_content)
			
			# Add to edit history with enhanced data
			var edit_entry = {
				"timestamp": timestamp,
				"edit_id": _generate_edit_id(),
				"old_content": content,
				"new_content": new_content,
				"change_description": change_analysis.description,
				"change_type": change_analysis.change_type,
				"edit_mode": edit_mode,
				"change_source": change_source,
				"words_delta": change_analysis.words_delta,
				"chars_delta": change_analysis.chars_delta,
				"significant_change": change_analysis.is_significant,
				"affected_sections": change_analysis.affected_sections,
				"selection_context": _get_selection_context_for_change()
			}
			edit_history.append(edit_entry)
			
			# Update change statistics
			_update_change_statistics(change_analysis, edit_mode, timestamp)
			
			# Add change marker for visualization
			_add_change_marker(change_analysis, timestamp)
			
			content = new_content
			last_modified = int(timestamp)
			_calculate_word_count()
			
			# Check if significant change should trigger auto-save consideration
			if change_analysis.is_significant:
				change_statistics.last_significant_change = timestamp
	
	func _generate_edit_id() -> String:
		"""Generate unique ID for this edit"""
		var edit_count = edit_history.size()
		return "edit_%s_%03d" % [edit_session_id, edit_count + 1]
	
	func _analyze_content_changes(old_content: String, new_content: String) -> Dictionary:
		"""Perform detailed analysis of content changes"""
		var old_words = old_content.split(" ", false)
		var new_words = new_content.split(" ", false)
		var old_chars = old_content.length()
		var new_chars = new_content.length()
		
		var words_delta = new_words.size() - old_words.size()
		var chars_delta = new_chars - old_chars
		
		# Determine change type
		var change_type = ""
		if words_delta > 0:
			change_type = "addition"
		elif words_delta < 0:
			change_type = "deletion" 
		elif chars_delta != 0:
			change_type = "modification"
		else:
			change_type = "formatting"
		
		# Check if this is a significant change
		var is_significant = abs(words_delta) > 5 or abs(chars_delta) > 50
		
		# Analyze affected sections (simplified)
		var affected_sections = _identify_affected_sections(old_content, new_content)
		
		# Generate description
		var description = _generate_detailed_change_description(words_delta, chars_delta, change_type)
		
		return {
			"words_delta": words_delta,
			"chars_delta": chars_delta,
			"change_type": change_type,
			"is_significant": is_significant,
			"affected_sections": affected_sections,
			"description": description
		}
	
	func _update_change_statistics(change_analysis: Dictionary, edit_mode: String, timestamp: int):
		"""Update document change statistics"""
		change_statistics.total_edits += 1
		
		if change_analysis.words_delta > 0:
			change_statistics.words_added += change_analysis.words_delta
		else:
			change_statistics.words_removed += abs(change_analysis.words_delta)
		
		if change_analysis.chars_delta > 0:
			change_statistics.characters_added += change_analysis.chars_delta
		else:
			change_statistics.characters_removed += abs(change_analysis.chars_delta)
		
		# Track edit modes used
		if not edit_mode.is_empty() and edit_mode not in change_statistics.edit_modes_used:
			change_statistics.edit_modes_used.append(edit_mode)
		
		# Calculate editing velocity (changes per minute)
		var time_since_creation = timestamp - creation_time
		if time_since_creation > 0:
			change_statistics.change_velocity = float(change_statistics.total_edits) / (time_since_creation / 60.0)
	
	func _add_change_marker(change_analysis: Dictionary, timestamp: int):
		"""Add visual change marker for UI display"""
		var marker = {
			"timestamp": timestamp,
			"change_type": change_analysis.change_type,
			"description": change_analysis.description,
			"significance": "major" if change_analysis.is_significant else "minor",
			"position": selection_start if selection_start >= 0 else 0,
			"length": abs(change_analysis.chars_delta)
		}
		
		change_markers.append(marker)
		
		# Keep only recent markers (last 50 changes)
		if change_markers.size() > 50:
			change_markers = change_markers.slice(-50)
	
	func _identify_affected_sections(old_content: String, new_content: String) -> Array:
		"""Identify which sections of the document were affected (simplified implementation)"""
		var sections = []
		
		# Split content into paragraphs and compare
		var old_paragraphs = old_content.split("\n\n", false)
		var new_paragraphs = new_content.split("\n\n", false)
		
		# Find changed paragraphs (simplified diff)
		for i in range(max(old_paragraphs.size(), new_paragraphs.size())):
			var old_para = old_paragraphs[i] if i < old_paragraphs.size() else ""
			var new_para = new_paragraphs[i] if i < new_paragraphs.size() else ""
			
			if old_para != new_para:
				sections.append("Paragraph %d" % (i + 1))
		
		return sections
	
	func _generate_detailed_change_description(words_delta: int, chars_delta: int, change_type: String) -> String:
		"""Generate detailed description of changes"""
		var description = ""
		
		match change_type:
			"addition":
				description = "Added %d words (%d characters)" % [words_delta, chars_delta]
			"deletion":
				description = "Removed %d words (%d characters)" % [abs(words_delta), abs(chars_delta)]
			"modification":
				if words_delta == 0:
					description = "Modified text (%d character change)" % chars_delta
				else:
					description = "Modified text (%d words, %d characters)" % [words_delta, chars_delta]
			"formatting":
				description = "Formatting changes"
		
		return description
	
	func _get_selection_context_for_change() -> Dictionary:
		"""Get context information about current selection for change tracking"""
		if selection_start >= 0 and selection_end >= 0:
			return {
				"start": selection_start,
				"end": selection_end,
				"length": selection_end - selection_start,
				"selected_text": get_selected_text()
			}
		return {}
	
	func _get_change_description(old_text: String, new_text: String) -> String:
		"""Generate a description of what changed"""
		var old_words = old_text.split(" ", false).size()
		var new_words = new_text.split(" ", false).size()
		var word_diff = new_words - old_words
		
		if word_diff > 0:
			return "Added %d words" % word_diff
		elif word_diff < 0:
			return "Removed %d words" % abs(word_diff)
		else:
			return "Content modified"
	
	func get_selected_text() -> String:
		"""Get currently selected text"""
		if selection_start >= 0 and selection_end >= 0 and selection_end > selection_start:
			return content.substr(selection_start, selection_end - selection_start)
		return ""
	
	func set_selection(start: int, end: int):
		"""Set text selection range"""
		selection_start = start
		selection_end = end
	
	func has_unsaved_changes() -> bool:
		"""Check if document has unsaved changes"""
		return content != original_content
	
	func get_summary() -> Dictionary:
		"""Get document summary for UI display"""
		return {
			"name": file_name,
			"path": file_path,
			"word_count": word_count,
			"is_primary": is_primary,
			"has_changes": has_unsaved_changes(),
			"last_modified": last_modified,
			"creation_time": creation_time,
			"total_edits": change_statistics.total_edits,
			"session_id": edit_session_id,
			"change_velocity": change_statistics.change_velocity
		}
	
	func get_change_history_summary() -> Dictionary:
		"""Get summary of document change history"""
		var recent_changes = []
		var total_changes = edit_history.size()
		
		# Get last 10 changes for summary
		var start_index = max(0, total_changes - 10)
		for i in range(start_index, total_changes):
			var change = edit_history[i]
			recent_changes.append({
				"timestamp": change.timestamp,
				"description": change.change_description,
				"type": change.change_type,
				"significant": change.significant_change,
				"edit_mode": change.edit_mode
			})
		
		return {
			"total_changes": total_changes,
			"recent_changes": recent_changes,
			"statistics": change_statistics.duplicate(),
			"time_span": last_modified - creation_time,
			"unsaved_changes": has_unsaved_changes()
		}
	
	func get_change_markers_for_visualization() -> Array:
		"""Get change markers for UI visualization"""
		return change_markers.duplicate()
	
	func generate_change_summary() -> String:
		"""Generate human-readable change summary"""
		var summary = "Document Change Summary for '%s':\n\n" % file_name
		
		# Overall statistics
		summary += "• Total edits: %d\n" % change_statistics.total_edits
		summary += "• Words added: %d, removed: %d\n" % [change_statistics.words_added, change_statistics.words_removed]
		summary += "• Characters added: %d, removed: %d\n" % [change_statistics.characters_added, change_statistics.characters_removed]
		summary += "• Edit velocity: %.1f changes/minute\n" % change_statistics.change_velocity
		
		if change_statistics.edit_modes_used.size() > 0:
			summary += "• Edit modes used: %s\n" % ", ".join(change_statistics.edit_modes_used)
		
		# Recent significant changes
		var significant_changes = []
		for change in edit_history:
			if change.significant_change:
				significant_changes.append(change)
		
		if significant_changes.size() > 0:
			summary += "\nSignificant Changes:\n"
			var recent_significant = significant_changes.slice(-5)  # Last 5 significant changes
			for change in recent_significant:
				var time_str = Time.get_datetime_string_from_unix_time(change.timestamp)
				summary += "• %s - %s (%s)\n" % [time_str, change.change_description, change.edit_mode]
		
		return summary
	
	func export_change_history() -> Dictionary:
		"""Export complete change history for session save/load"""
		return {
			"document_info": {
				"file_path": file_path,
				"file_name": file_name,
				"session_id": edit_session_id,
				"creation_time": creation_time
			},
			"content_info": {
				"original_content": original_content,
				"current_content": content,
				"word_count": word_count
			},
			"change_tracking": {
				"edit_history": edit_history.duplicate(),
				"change_statistics": change_statistics.duplicate(),
				"change_markers": change_markers.duplicate()
			}
		}
	
	func import_change_history(data: Dictionary) -> bool:
		"""Import change history from session load"""
		if not data.has_all(["document_info", "content_info", "change_tracking"]):
			push_error("DocumentContext: Invalid change history data format")
			return false
		
		# Restore document info
		var doc_info = data.get("document_info", {})
		if doc_info.is_empty():
			push_error("DocumentContext: Missing document_info in change history data")
			return false
		
		if not file_path.is_empty() and file_path != doc_info.get("file_path", ""):
			push_warning("DocumentContext: File path mismatch during import")
		
		edit_session_id = doc_info.get("session_id", _generate_session_id())
		creation_time = doc_info.get("creation_time", Time.get_unix_time_from_system())
		
		# Restore content info
		var content_info = data.get("content_info", {})
		if not content_info.is_empty():
			original_content = content_info.get("original_content", "")
			# Note: Don't restore current_content as it should reflect actual current state
		
		# Restore change tracking
		var tracking = data.get("change_tracking", {})
		if not tracking.is_empty():
			edit_history = tracking.get("edit_history", [])
			change_statistics = tracking.get("change_statistics", {})
			change_markers = tracking.get("change_markers", [])
		
		# Ensure change statistics is properly initialized
		if change_statistics.is_empty():
			_initialize_change_statistics()
		
		print("DocumentContext: Successfully imported change history for '%s'" % file_name)
		return true

# Session management
var active_documents = []  # Array[DocumentContext]
var primary_document: DocumentContext = null
var current_edit_mode: String = "developmental"
var session_name: String = ""

# Edit modes
var edit_modes = [  # Array[String]
	"developmental",
	"structural", 
	"content",
	"line",
	"copy",
	"proofreading"
]

var edit_mode_display_names: Dictionary = {
	"developmental": "Developmental Editing",
	"structural": "Structural Editing",
	"content": "Content Editing", 
	"line": "Line Editing",
	"copy": "Copy Editing",
	"proofreading": "Proofreading"
}

signal session_saved(session_path: String)
signal session_loaded(session_path: String)
signal session_save_failed(error: String)
signal session_load_failed(error: String)
signal report_generated(report_path: String, report_type: String)
signal document_exported(document_path: String, export_format: String)
signal session_shared(share_data: Dictionary)
signal export_failed(error: String)
enum ExportFormat {
	HTML,
	MARKDOWN,
	JSON,
	PLAIN_TEXT,
	PDF_READY,
	RTFD
}
var export_format_names = {
	ExportFormat.HTML: "HTML Report",
	ExportFormat.MARKDOWN: "Markdown",
	ExportFormat.JSON: "JSON Data",
	ExportFormat.PLAIN_TEXT: "Plain Text",
	ExportFormat.PDF_READY: "PDF-Ready HTML",
	ExportFormat.RTFD: "Rich Text"
}

# Virtual method stubs implemented by split base classes.
func _ready():
	pass
func _generate_session_id() -> String:
	return ""
func get_available_edit_modes() -> Array:
	return []
func get_edit_mode_display_names() -> Dictionary:
	return {}
func set_edit_mode(mode: String):
	pass
func get_current_edit_mode() -> String:
	return ""
func load_document(file_path: String) -> DocumentContext:
	return null
func load_document_from_string(content: String, doc_name: String = "Untitled") -> DocumentContext:
	return null
func set_primary_document(document: DocumentContext):
	pass
func remove_document(document: DocumentContext):
	pass
func clear_session():
	pass
func get_active_documents() -> Array:
	return []
func get_primary_document() -> DocumentContext:
	return null
func get_document_by_path(file_path: String) -> DocumentContext:
	return null
func update_document_content(document: DocumentContext, new_content: String, change_source: String = "user"):
	pass
func save_document(document: DocumentContext) -> bool:
	return false
func save_document_as(document: DocumentContext, file_path: String) -> bool:
	return false
func get_session_summary() -> Dictionary:
	return {}
func get_multi_document_context() -> Dictionary:
	return {}
func _get_document_preview(document: DocumentContext, lines: int = 3) -> String:
	return ""
func _analyze_document_relationships() -> Array:
	return []
func _compare_documents(doc1: DocumentContext, doc2: DocumentContext) -> Dictionary:
	return {}
func _extract_keywords(content: String) -> Array:
	return []
func _classify_relationship(similarity: float) -> String:
	return ""
func get_document_context_for_llm(include_all_documents: bool = false) -> Dictionary:
	return {}
func _get_relationship_to_primary(document: DocumentContext) -> String:
	return ""
func switch_primary_document(new_primary: DocumentContext):
	pass
func get_documents_by_type() -> Dictionary:
	return {}
func _categorize_document(document: DocumentContext) -> String:
	return ""
func _load_session_preferences():
	pass
func _save_session_preferences():
	pass
func save_session(session_path: String = "") -> bool:
	return false
func load_session(session_path: String) -> bool:
	return false
func _generate_default_session_path() -> String:
	return ""
func _restore_document_from_data(doc_data: Dictionary) -> DocumentContext:
	return null
func _calculate_session_statistics() -> Dictionary:
	return {}
func get_session_change_summary() -> String:
	return ""
func export_session_for_analysis() -> Dictionary:
	return {}
func _remove_punctuation(text: String) -> String:
	return ""
func generate_edit_session_report(format: ExportFormat = ExportFormat.HTML, save_path: String = "") -> String:
	return ""
func _compile_comprehensive_report_data() -> Dictionary:
	return {}
func _get_enhanced_session_statistics() -> Dictionary:
	return {}
func _get_detailed_document_analysis() -> Array:
	return []
func _get_change_timeline() -> Array:
	return []
func _calculate_productivity_metrics() -> Dictionary:
	return {}
func _analyze_collaboration_patterns() -> Dictionary:
	return {}
func _generate_content_insights() -> Dictionary:
	return {}
func _generate_improvement_recommendations() -> Array:
	return []
func export_document(document: DocumentContext, format: ExportFormat, export_path: String = "") -> String:
	return ""
func export_all_documents(format: ExportFormat, export_directory: String = "") -> Array:
	return []
func create_shareable_session_package() -> Dictionary:
	return {}
func export_session_for_sharing(share_path: String = "") -> String:
	return ""
func _ensure_reports_directory():
	pass
func _ensure_exports_directory():
	pass
func _ensure_shared_directory():
	pass
func _calculate_session_duration() -> float:
	return 0.0
func _calculate_productivity_score() -> float:
	return 0.0
func _calculate_session_complexity() -> String:
	return ""
func _analyze_edit_distribution() -> Dictionary:
	return {}
func _analyze_time_patterns() -> Dictionary:
	return {}
func _count_paragraphs(content: String) -> int:
	return 0
func _analyze_content_quality(_document: DocumentContext) -> Dictionary:
	return {}
func _analyze_edit_patterns(_document: DocumentContext) -> Dictionary:
	return {}
func _analyze_document_time_patterns(document: DocumentContext) -> Dictionary:
	return {}
func _calculate_efficiency_score() -> float:
	return 0.0
func _identify_focus_periods() -> Array:
	return []
func _find_peak_productivity_time() -> String:
	return ""
func _analyze_mode_transitions() -> Dictionary:
	return {}
func _assess_collaborative_potential() -> String:
	return ""
func _identify_content_themes() -> Array:
	return []
func _analyze_writing_style() -> Dictionary:
	return {}
func _analyze_content_complexity() -> Dictionary:
	return {}
func _identify_improvement_areas() -> Array:
	return []
func _has_clear_primary_focus() -> bool:
	return false
func _calculate_focus_score() -> float:
	return 0.0
func _get_anonymized_change_summary(document: DocumentContext) -> Dictionary:
	return {}
func _generate_html_report(data: Dictionary) -> String:
	return ""
func _generate_markdown_report(data: Dictionary) -> String:
	return ""
func _generate_text_report(data: Dictionary) -> String:
	return ""
func _generate_pdf_ready_html(data: Dictionary) -> String:
	return ""
func _generate_rtfd_report(data: Dictionary) -> String:
	return ""
func _export_document_as_html(document: DocumentContext) -> String:
	return ""
func _export_document_as_markdown(document: DocumentContext) -> String:
	return ""
func _export_document_as_json(document: DocumentContext) -> Dictionary:
	return {}
func _export_document_as_text(document: DocumentContext) -> String:
	return ""
func _export_document_as_pdf_ready(document: DocumentContext) -> String:
	return ""
func create_task_from_edit_session(task_title: String = "", task_notes: String = "") -> WorkplanTask:
	return null
func create_multiple_tasks_from_session(task_configs: Array) -> Array:
	return []
func get_task_creation_suggestions() -> Dictionary:
	return {}
func _generate_task_title_from_session() -> String:
	return ""
func _generate_task_notes_from_session() -> String:
	return ""
func _generate_session_summary_for_task() -> String:
	return ""
func _suggest_formats_from_documents() -> Array[String]:
	return []
func _suggest_channels_from_documents() -> Array[String]:
	return []
func _generate_task_recommendations() -> Array:
	return []
func _analyze_document_for_tasks(doc: DocumentContext) -> Array:
	return []
func _analyze_session_for_tasks() -> Array:
	return []
func _identify_collaboration_opportunities() -> Array:
	return []
func get_session_productivity_metrics() -> Dictionary:
	return {}
func _calculate_consistency_score() -> float:
	return 0.0
func load_document_lazy(file_path: String, force_full_load: bool = false) -> DocumentContext:
	return null
func create_optimized_context_window(max_tokens: int = 8000, include_all_docs: bool = false) -> Dictionary:
	return {}
func optimize_session_performance():
	pass
func _cleanup_session_caches():
	pass
func get_session_performance_report() -> Dictionary:
	return {}
func _calculate_memory_efficiency() -> float:
	return 0.0
func _calculate_context_efficiency() -> float:
	return 0.0
func _generate_session_optimization_recommendations(report: Dictionary) -> Array:
	return []
func preload_document_chunks(document: DocumentContext, priority_chunks: Array = []):
	pass
func create_context_window_for_task(task_description: String, max_tokens: int = 8000) -> Dictionary:
	return {}
func enable_performance_monitoring(enable: bool = true):
	pass
func get_memory_usage_summary() -> Dictionary:
	return {}
