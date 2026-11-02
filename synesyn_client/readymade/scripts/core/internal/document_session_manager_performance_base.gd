extends "res://readymade/scripts/core/internal/document_session_manager_task_integration_base.gd"
class_name DocumentSessionManagerPerformanceBase

func load_document_lazy(file_path: String, force_full_load: bool = false) -> DocumentContext:
	"""Load document with lazy loading optimization"""
	var start_time = Time.get_unix_time_from_system()
	
	print("DocumentSessionManager: Loading document with lazy loading: ", file_path)
	
	if not FileAccess.file_exists(file_path):
		push_error("DocumentSessionManager: File does not exist: " + file_path)
		return null
	
	# Check if document is already loaded
	for doc in active_documents:
		if doc.file_path == file_path:
			print("DocumentSessionManager: Document already loaded: ", file_path)
			return doc
	
	# Check file size for optimization decision
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		push_error("DocumentSessionManager: Failed to open file: " + file_path)
		return null
	
	var file_size = file.get_length()
	var is_large_file = file_size > 100000  # 100KB threshold
	
	# Load content based on size and user preference
	var content = ""
	if force_full_load or not is_large_file:
		content = file.get_as_text()
	else:
		# For large files, load strategically
		content = file.get_as_text()  # Still load fully but enable lazy features
	
	file.close()
	
	# Create document context with performance optimization
	var document = DocumentContext.new(file_path, content)
	active_documents.append(document)
	
	# Set as primary if it's the first document
	if active_documents.size() == 1:
		set_primary_document(document)
	
	# Track performance
	var load_time = Time.get_unix_time_from_system() - start_time
	print("DocumentSessionManager: Document loaded in %.3f seconds (lazy: %s)" % [load_time, str(is_large_file)])
	
	document_loaded.emit(document)
	return document

func create_optimized_context_window(max_tokens: int = 8000, include_all_docs: bool = false) -> Dictionary:
	"""Create optimized context window for LLM processing"""
	var start_time = Time.get_unix_time_from_system()
	
	if active_documents.is_empty():
		return {
			"content": "",
			"tokens_used": 0,
			"documents_included": 0,
			"truncated": false,
			"error": "No documents loaded"
		}
	
	var context_window = {
		"content": "",
		"tokens_used": 0,
		"documents_included": 0,
		"truncated": false,
		"primary_document": "",
		"supporting_documents": [],
		"metadata": {
			"generation_time": 0.0,
			"optimization_level": "high",
			"context_strategy": "priority_based"
		}
	}
	
	# Calculate available tokens per document
	var available_tokens = max_tokens - 200  # Reserve for metadata
	var tokens_per_doc = available_tokens
	
	if include_all_docs and active_documents.size() > 1:
		tokens_per_doc = float(available_tokens) / float(active_documents.size())
	
	# Process primary document first
	if primary_document:
		var primary_context = primary_document.create_context_window(int(tokens_per_doc * 0.7))
		context_window.content += "=== PRIMARY DOCUMENT: %s ===\n\n" % primary_document.file_name
		context_window.content += primary_context.content + "\n\n"
		context_window.tokens_used += primary_context.tokens_used
		context_window.primary_document = primary_document.file_name
		context_window.documents_included += 1
		
		if primary_context.truncated:
			context_window.truncated = true
	
	# Add supporting documents if requested and space allows
	if include_all_docs and context_window.tokens_used < available_tokens * 0.8:
		var remaining_tokens = available_tokens - context_window.tokens_used
		var remaining_docs = active_documents.size() - 1
		
		if remaining_docs > 0:
			var tokens_per_supporting = float(remaining_tokens) / float(remaining_docs)
				
			for doc in active_documents:
				if doc != primary_document and context_window.tokens_used < available_tokens * 0.9:
					var supporting_context = doc.create_context_window(int(tokens_per_supporting))
					context_window.content += "=== SUPPORTING DOCUMENT: %s ===\n\n" % doc.file_name
					context_window.content += supporting_context.content + "\n\n"
					context_window.tokens_used += supporting_context.tokens_used
					context_window.supporting_documents.append(doc.file_name)
					context_window.documents_included += 1
					
					if supporting_context.truncated:
						context_window.truncated = true
	
	# Finalize context window
	context_window.metadata.generation_time = Time.get_unix_time_from_system() - start_time
	
	print("DocumentSessionManager: Created optimized context window (%d tokens, %d docs) in %.3f seconds" % [
		context_window.tokens_used, 
		context_window.documents_included,
		context_window.metadata.generation_time
	])
	
	return context_window

func optimize_session_performance():
	"""Optimize performance across all documents in the session"""
	var start_time = Time.get_unix_time_from_system()
	var optimized_count = 0
	
	print("DocumentSessionManager: Starting session performance optimization...")
	
	for doc in active_documents:
		if doc.has_method("optimize_memory_usage"):
			doc.optimize_memory_usage()
			optimized_count += 1
	
	# Clean up session-level caches
	_cleanup_session_caches()
	
	var optimization_time = Time.get_unix_time_from_system() - start_time
	print("DocumentSessionManager: Optimized %d documents in %.3f seconds" % [optimized_count, optimization_time])

func _cleanup_session_caches():
	"""Clean up session-level caches and temporary data"""
	# This would clean up any session-level caches
	# For now, just log the cleanup
	print("DocumentSessionManager: Session caches cleaned up")

func get_session_performance_report() -> Dictionary:
	"""Get comprehensive performance report for the entire session"""
	var report = {
		"session_info": {
			"total_documents": active_documents.size(),
			"primary_document": primary_document.file_name if primary_document else "None",
			"session_duration": Time.get_unix_time_from_system() - (primary_document.creation_time if primary_document else 0),
			"total_memory_usage": 0
		},
		"document_reports": [],
		"performance_summary": {
			"total_load_time": 0.0,
			"total_processing_time": 0.0,
			"average_chunk_load_time": 0.0,
			"context_generation_efficiency": 0.0,
			"memory_efficiency_score": 0.0
		},
		"optimization_recommendations": []
	}
	
	# Collect individual document reports
	for doc in active_documents:
		if doc.has_method("get_performance_report"):
			var doc_report = doc.get_performance_report()
			report.document_reports.append(doc_report)
			
			# Aggregate metrics
			report.performance_summary.total_load_time += doc_report.performance_metrics.load_time
			report.performance_summary.total_processing_time += doc_report.performance_metrics.processing_time
			report.session_info.total_memory_usage += doc_report.memory_usage.total_memory_footprint
	
	# Calculate efficiency scores
	if report.document_reports.size() > 0:
		report.performance_summary.memory_efficiency_score = _calculate_memory_efficiency()
		report.performance_summary.context_generation_efficiency = _calculate_context_efficiency()
	
	# Generate recommendations
	report.optimization_recommendations = _generate_session_optimization_recommendations(report)
	
	return report

func _calculate_memory_efficiency() -> float:
	"""Calculate memory efficiency score (0-1)"""
	var total_memory = 0
	var total_content_size = 0
	
	for doc in active_documents:
		if doc.has_method("get_performance_report"):
			var doc_report = doc.get_performance_report()
			total_memory += doc_report.memory_usage.total_memory_footprint
			total_content_size += doc_report.memory_usage.content_size
	
	if total_memory == 0:
		return 1.0
	
	# Efficiency = content_size / total_memory (higher is better)
	var efficiency = float(total_content_size) / float(total_memory)
	return min(efficiency, 1.0)

func _calculate_context_efficiency() -> float:
	"""Calculate context generation efficiency score (0-1)"""
	var total_context_time = 0.0
	var total_context_requests = 0
	
	for doc in active_documents:
		if doc.has_method("get_performance_report"):
			var doc_report = doc.get_performance_report()
			total_context_time += doc_report.performance_metrics.context_generation_time
			total_context_requests += doc_report.context_management.context_cache_entries
	
	if total_context_requests == 0:
		return 1.0
	
	# Efficiency = 1 / (average_time_per_request * 10) (lower time is better)
	var avg_time = total_context_time / total_context_requests
	return max(0.0, 1.0 - (avg_time * 10))

func _generate_session_optimization_recommendations(report: Dictionary) -> Array:
	"""Generate optimization recommendations based on session performance"""
	var recommendations = []
	
	# Memory usage recommendations
	if report.session_info.total_memory_usage > 10000000:  # 10MB
		recommendations.append({
			"type": "memory",
			"priority": "high",
			"title": "High Memory Usage",
			"description": "Session is using %.1f MB of memory. Consider optimizing or closing unused documents." % (report.session_info.total_memory_usage / 1000000.0),
			"action": "optimize_memory"
		})
	
	# Large document recommendations
	var large_docs = 0
	for doc_report in report.document_reports:
		if doc_report.document_info.is_large_document:
			large_docs += 1
	
	if large_docs > 0:
		recommendations.append({
			"type": "performance",
			"priority": "medium",
			"title": "Large Documents Detected",
			"description": "%d large documents detected. Consider using lazy loading features." % large_docs,
			"action": "enable_lazy_loading"
		})
	
	# Context efficiency recommendations
	if report.performance_summary.context_generation_efficiency < 0.5:
		recommendations.append({
			"type": "context",
			"priority": "medium",
			"title": "Context Generation Slow",
			"description": "Context generation is taking longer than expected. Consider optimizing context windows.",
			"action": "optimize_context_windows"
		})
	
	# Session duration recommendations
	if report.session_info.session_duration > 7200:  # 2 hours
		recommendations.append({
			"type": "workflow",
			"priority": "low",
			"title": "Long Session Duration",
			"description": "Session has been active for %.1f hours. Consider saving progress and taking breaks." % (report.session_info.session_duration / 3600.0),
			"action": "save_session_progress"
		})
	
	return recommendations

func preload_document_chunks(document: DocumentContext, priority_chunks: Array = []):
	"""Preload specific chunks for better performance"""
	if not document.has_method("ensure_chunk_loaded"):
		return
	
	var start_time = Time.get_unix_time_from_system()
	var loaded_count = 0
	
	# Load priority chunks first
	for chunk_idx in priority_chunks:
		if document.ensure_chunk_loaded(chunk_idx):
			loaded_count += 1
	
	# Load adjacent chunks for smooth navigation
	if priority_chunks.size() > 0:
		for chunk_idx in priority_chunks:
			# Load previous and next chunks
			if document.ensure_chunk_loaded(chunk_idx - 1):
				loaded_count += 1
			if document.ensure_chunk_loaded(chunk_idx + 1):
				loaded_count += 1
	
	var preload_time = Time.get_unix_time_from_system() - start_time
	print("DocumentSessionManager: Preloaded %d chunks in %.3f seconds" % [loaded_count, preload_time])

func create_context_window_for_task(task_description: String, max_tokens: int = 8000) -> Dictionary:
	"""Create optimized context window specifically for task processing"""
	var context_window = create_optimized_context_window(max_tokens, true)
	
	# Add task-specific context
	context_window.content = "=== TASK CONTEXT ===\n\n" + task_description + "\n\n" + context_window.content
	context_window.tokens_used += int(task_description.length() / 4.0)  # Estimate token usage
	
	return context_window

func enable_performance_monitoring(enable: bool = true):
	"""Enable or disable performance monitoring"""
	for doc in active_documents:
		if doc.has_method("_initialize_performance_tracking"):
			if enable:
				doc._initialize_performance_tracking()
			# Could add disable logic here if needed
	
	print("DocumentSessionManager: Performance monitoring %s" % ("enabled" if enable else "disabled"))

func get_memory_usage_summary() -> Dictionary:
	"""Get quick memory usage summary"""
	var summary = {
		"total_memory": 0,
		"document_count": active_documents.size(),
		"average_per_document": 0,
		"largest_document": "",
		"largest_document_size": 0,
		"memory_efficiency": 0.0
	}
	
	for doc in active_documents:
		if doc.has_method("get_performance_report"):
			var doc_report = doc.get_performance_report()
			var doc_memory = doc_report.memory_usage.total_memory_footprint
			summary.total_memory += doc_memory
			
			if doc_memory > summary.largest_document_size:
				summary.largest_document_size = doc_memory
				summary.largest_document = doc.file_name
	
	if summary.document_count > 0:
		summary.average_per_document = summary.total_memory / summary.document_count
	
	summary.memory_efficiency = _calculate_memory_efficiency()
	
	return summary

# === END PHASE 5.2 METHODS ===
