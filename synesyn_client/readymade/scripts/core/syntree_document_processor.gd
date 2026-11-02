extends Node

## ReadyMade SynTree Document Processor - Integrates document editing with SynTree analysis
## This singleton processes documents through SynTree's content source system for enhanced analysis

signal document_analysis_completed(document: DocumentSessionManager.DocumentContext, analysis: Dictionary)
signal document_analysis_failed(document: DocumentSessionManager.DocumentContext, error: String)
signal syntree_processing_started(document: DocumentSessionManager.DocumentContext)

# SynTree integration variables
var syntree_available: bool = false
var content_source_resource = null
var content_bus = null

# Processing state
var processing_queue: Array[DocumentSessionManager.DocumentContext] = []
var current_processing: DocumentSessionManager.DocumentContext = null
var analysis_cache: Dictionary = {}

func _ready():
	print("SynTreeDocumentProcessor: Initializing...")
	_check_syntree_availability()
	_connect_to_document_session_manager()
	print("SynTreeDocumentProcessor: Ready")

func _check_syntree_availability():
	"""Check if SynTree is available and accessible"""
	# Check if ContentBus is available (SynTree's main communication hub)
	if has_node("/root/ContentBus"):
		content_bus = get_node("/root/ContentBus")
		print("SynTreeDocumentProcessor: ContentBus found")
		
		# Check if content source resource is available
		if content_bus.has_method("get_content_source_resource"):
			content_source_resource = content_bus.get_content_source_resource()
			if content_source_resource:
				syntree_available = true
				print("SynTreeDocumentProcessor: SynTree integration available")
			else:
				print("SynTreeDocumentProcessor: ContentSourceResource not available")
		else:
			print("SynTreeDocumentProcessor: ContentBus missing required methods")
	else:
		print("SynTreeDocumentProcessor: SynTree ContentBus not found - analysis features disabled")

func _connect_to_document_session_manager():
	"""Connect to DocumentSessionManager signals"""
	if DocumentSessionManager:
		DocumentSessionManager.document_loaded.connect(_on_document_loaded)
		DocumentSessionManager.primary_document_changed.connect(_on_primary_document_changed)
		print("SynTreeDocumentProcessor: Connected to DocumentSessionManager")

func is_syntree_available() -> bool:
	"""Check if SynTree integration is available"""
	return syntree_available

func process_document_with_syntree(document: DocumentSessionManager.DocumentContext) -> bool:
	"""Process a document through SynTree's analysis system"""
	if not is_syntree_available():
		push_error("SynTreeDocumentProcessor: SynTree not available for document processing")
		document_analysis_failed.emit(document, "SynTree integration not available")
		return false
	
	if not document:
		push_error("SynTreeDocumentProcessor: Invalid document provided")
		return false
	
	print("SynTreeDocumentProcessor: Processing document through SynTree: ", document.file_name)
	
	# Check cache first
	var cache_key = _get_document_cache_key(document)
	if cache_key in analysis_cache:
		var cached_analysis = analysis_cache[cache_key]
		print("SynTreeDocumentProcessor: Using cached analysis for: ", document.file_name)
		document.syntree_analysis = cached_analysis
		document_analysis_completed.emit(document, cached_analysis)
		return true
	
	# Add to processing queue
	if document not in processing_queue:
		processing_queue.append(document)
		syntree_processing_started.emit(document)
	
	# Start processing if not already processing
	if not current_processing:
		_process_next_in_queue()
	
	return true

func _process_next_in_queue():
	"""Process the next document in the queue"""
	if processing_queue.is_empty():
		current_processing = null
		return
	
	current_processing = processing_queue.pop_front()
	print("SynTreeDocumentProcessor: Starting analysis for: ", current_processing.file_name)
	
	# Create SynTree content source from document
	var content_source_data = _create_syntree_content_source(current_processing)
	
	if content_source_data.is_empty():
		_finish_processing_with_error("Failed to create SynTree content source")
		return
	
	# Process through SynTree
	_analyze_with_syntree(content_source_data)

func _create_syntree_content_source(document: DocumentSessionManager.DocumentContext) -> Dictionary:
	"""Create a SynTree-compatible content source from a document"""
	var source_id = "edit_session_" + document.file_name.get_basename() + "_" + str(Time.get_unix_time_from_system())
	var timestamp = Time.get_datetime_string_from_system()
	
	# Split document content into logical nodes
	var nodes = _split_document_into_nodes(document.content)
	
	var content_source = {
		"meta": {
			"source_id": source_id,
			"name": "Edit Session: " + document.file_name,
			"path": document.file_path if not document.file_path.is_empty() else "edit_session/" + document.file_name,
			"source_type": "document",
			"author": "ReadyMade Edit Session",
			"created": timestamp,
			"modified": timestamp,
			"ai_context": {
				"is_active": true,
				"is_stack": false,
				"metaprompt": false,
				"model_metadata": {}
			}
		},
		"content": {
			"nodes": nodes
		},
		"format_version": "1.0.0"
	}
	
	return content_source

func _split_document_into_nodes(content: String) -> Array[Dictionary]:
	"""Split document content into logical nodes for SynTree analysis"""
	var nodes = []
	var lines = content.split("\n")
	
	if lines.is_empty():
		return nodes
	
	# Simple node creation strategy - can be enhanced with more sophisticated parsing
	var current_section = ""
	var current_content = ""
	var node_counter = 1
	
	for line in lines:
		line = line.strip_edges()
		
		# Detect section headers (lines starting with # or all caps, etc.)
		if _is_section_header(line):
			# Save previous section if it exists
			if not current_content.is_empty():
				nodes.append(_create_content_node(current_section, current_content, node_counter))
				node_counter += 1
			
			# Start new section
			current_section = line
			current_content = ""
		else:
			# Add to current content
			if not current_content.is_empty():
				current_content += "\n"
			current_content += line
	
	# Add final section
	if not current_content.is_empty():
		nodes.append(_create_content_node(current_section, current_content, node_counter))
	
	# If no sections found, create a single node with all content
	if nodes.is_empty():
		nodes.append(_create_content_node("Document Content", content, 1))
	
	return nodes

func _is_section_header(line: String) -> bool:
	"""Determine if a line is likely a section header"""
	line = line.strip_edges()
	
	# Check for markdown headers
	if line.begins_with("#"):
		return true
	
	# Check for all caps (likely a header)
	if line.length() > 0 and line.length() < 100 and line == line.to_upper() and _remove_digits(line).length() > 0:
		return true
	
	# Check for lines that end with colon (often section headers)
	if line.ends_with(":") and line.length() < 100:
		return true
	
	return false

func _create_content_node(title: String, content: String, id: int) -> Dictionary:
	"""Create a SynTree content node"""
	var node_id = "node_%d" % id
	var node_title = title if not title.is_empty() else "Section %d" % id
	
	return {
		"node_id": node_id,
		"title": node_title,
		"content": content,
		"type": "text",
		"parents": [],
		"children": [],
		"dependencies": []
	}

func _analyze_with_syntree(content_source_data: Dictionary):
	"""Analyze content using SynTree's processing capabilities"""
	if not content_source_resource:
		_finish_processing_with_error("ContentSourceResource not available")
		return
	
	# For now, we'll do a simplified analysis without actually adding to SynTree
	# This avoids potential issues with SynTree's internal state
	var analysis_result = _perform_simplified_analysis(content_source_data)
	_finish_processing_with_success(analysis_result)

func _perform_simplified_analysis(content_source_data: Dictionary) -> Dictionary:
	"""Perform simplified document analysis without full SynTree integration"""
	var analysis = {
		"source_id": content_source_data.meta.source_id,
		"timestamp": Time.get_datetime_string_from_system(),
		"nodes": [],
		"structure": {},
		"statistics": {},
		"relationships": [],
		"quality_metrics": {}
	}
	
	# Analyze individual nodes
	var nodes = content_source_data.content.nodes
	for node in nodes:
		var node_analysis = _analyze_node(node)
		analysis.nodes.append(node_analysis)
	
	# Analyze document structure
	analysis.structure = _analyze_document_structure(nodes)
	
	# Calculate statistics
	analysis.statistics = _calculate_document_statistics(content_source_data)
	
	# Analyze relationships between nodes
	analysis.relationships = _analyze_node_relationships(nodes)
	
	# Calculate quality metrics
	analysis.quality_metrics = _calculate_quality_metrics(content_source_data, analysis)
	
	return analysis

func _analyze_node(node: Dictionary) -> Dictionary:
	"""Analyze a single content node"""
	var content = node.get("content", "")
	var words = content.split(" ", false)
	
	return {
		"node_id": node.get("node_id", ""),
		"title": node.get("title", ""),
		"word_count": words.size(),
		"character_count": content.length(),
		"paragraph_count": content.split("\n\n", false).size(),
		"readability_score": _calculate_readability_score(content),
		"key_themes": _extract_key_themes(content),
		"sentiment": _analyze_sentiment(content)
	}

func _analyze_document_structure(nodes: Array) -> Dictionary:
	"""Analyze the overall document structure"""
	return {
		"node_count": nodes.size(),
		"has_clear_sections": nodes.size() > 1,
		"section_balance": _calculate_section_balance(nodes),
		"logical_flow": _assess_logical_flow(nodes)
	}

func _calculate_document_statistics(content_source_data: Dictionary) -> Dictionary:
	"""Calculate comprehensive document statistics"""
	var all_content = ""
	var nodes = content_source_data.content.nodes
	
	for node in nodes:
		all_content += node.get("content", "") + " "
	
	var words = all_content.split(" ", false)
	var sentences = all_content.split(".", false)
	
	return {
		"total_words": words.size(),
		"total_characters": all_content.length(),
		"total_sentences": sentences.size(),
		"average_words_per_sentence": float(words.size()) / max(1, sentences.size()),
		"document_length_category": _categorize_document_length(words.size())
	}

func _analyze_node_relationships(nodes: Array) -> Array[Dictionary]:
	"""Analyze relationships between document nodes"""
	var relationships = []
	
	for i in range(nodes.size()):
		for j in range(i + 1, nodes.size()):
			var node1 = nodes[i]
			var node2 = nodes[j]
			
			var similarity = _calculate_content_similarity(
				node1.get("content", ""),
				node2.get("content", "")
			)
			
			if similarity > 0.1:  # Threshold for related content
				relationships.append({
					"node1_id": node1.get("node_id", ""),
					"node2_id": node2.get("node_id", ""),
					"similarity": similarity,
					"relationship_type": _classify_relationship(similarity)
				})
	
	return relationships

func _calculate_quality_metrics(_content_source_data: Dictionary, analysis: Dictionary) -> Dictionary:
	"""Calculate document quality metrics"""
	var stats = analysis.get("statistics", {})
	var structure = analysis.get("structure", {})
	
	var readability_scores = []
	for node_analysis in analysis.get("nodes", []):
		readability_scores.append(node_analysis.get("readability_score", 0.0))
	
	var avg_readability = 0.0
	if readability_scores.size() > 0:
		avg_readability = readability_scores.reduce(func(a, b): return a + b) / readability_scores.size()
	
	return {
		"overall_readability": avg_readability,
		"structure_quality": _calculate_structure_quality(structure),
		"content_density": _calculate_content_density(stats),
		"consistency_score": _calculate_consistency_score(analysis),
		"completeness_score": _calculate_completeness_score(analysis)
	}

# Helper functions for analysis
func _calculate_readability_score(content: String) -> float:
	"""Simple readability score calculation"""
	var words = content.split(" ", false)
	var sentences = content.split(".", false)
	
	if sentences.size() == 0:
		return 0.0
	
	var avg_words_per_sentence = float(words.size()) / sentences.size()
	
	# Simple readability score (lower is better)
	# Based on sentence length - shorter sentences are more readable
	if avg_words_per_sentence <= 15:
		return 1.0
	elif avg_words_per_sentence <= 20:
		return 0.8
	elif avg_words_per_sentence <= 25:
		return 0.6
	else:
		return 0.4

func _extract_key_themes(content: String) -> Array[String]:
	"""Extract key themes from content (simplified implementation)"""
	var words = content.to_lower().split(" ", false)
	var word_counts = {}
	
	# Count word frequencies
	for word in words:
		# Remove punctuation manually
		word = _remove_punctuation(word).strip_edges()
		if word.length() > 4:  # Only consider longer words
			word_counts[word] = word_counts.get(word, 0) + 1
	
	# Get top themes
	var themes = []
	var sorted_words = word_counts.keys()
	sorted_words.sort_custom(func(a, b): return word_counts[a] > word_counts[b])
	
	for i in range(min(5, sorted_words.size())):
		themes.append(sorted_words[i])
	
	return themes

func _analyze_sentiment(content: String) -> String:
	"""Simple sentiment analysis"""
	var positive_words = ["good", "great", "excellent", "amazing", "wonderful", "fantastic", "positive", "success", "achieve", "win"]
	var negative_words = ["bad", "terrible", "awful", "horrible", "negative", "fail", "failure", "problem", "issue", "difficult"]
	
	var content_lower = content.to_lower()
	var positive_count = 0
	var negative_count = 0
	
	for word in positive_words:
		positive_count += content_lower.count(word)
	
	for word in negative_words:
		negative_count += content_lower.count(word)
	
	if positive_count > negative_count:
		return "positive"
	elif negative_count > positive_count:
		return "negative"
	else:
		return "neutral"

func _calculate_section_balance(nodes: Array) -> float:
	"""Calculate how balanced the sections are in terms of content"""
	if nodes.size() <= 1:
		return 1.0
	
	var word_counts = []
	for node in nodes:
		var content = node.get("content", "")
		word_counts.append(content.split(" ", false).size())
	
	var total_words = word_counts.reduce(func(a, b): return a + b, 0)
	var avg_words = float(total_words) / nodes.size()
	
	# Calculate variance
	var variance = 0.0
	for count in word_counts:
		variance += pow(count - avg_words, 2)
	variance /= nodes.size()
	
	# Convert to balance score (lower variance = better balance)
	var std_dev = sqrt(variance)
	var coefficient_of_variation = std_dev / max(1, avg_words)
	
	return max(0.0, 1.0 - coefficient_of_variation)

func _assess_logical_flow(nodes: Array) -> float:
	"""Assess the logical flow between sections"""
	if nodes.size() <= 1:
		return 1.0
	
	var flow_score = 0.0
	var connections = 0
	
	for i in range(nodes.size() - 1):
		var current_content = nodes[i].get("content", "")
		var next_content = nodes[i + 1].get("content", "")
		
		# Simple flow assessment based on content similarity at boundaries
		var similarity = _calculate_content_similarity(current_content, next_content)
		flow_score += similarity
		connections += 1
	
	return flow_score / max(1, connections)

func _calculate_content_similarity(content1: String, content2: String) -> float:
	"""Calculate similarity between two content pieces"""
	var words1 = content1.to_lower().split(" ", false)
	var words2 = content2.to_lower().split(" ", false)
	
	var common_words = 0
	var total_unique_words = 0
	
	var all_words = {}
	for word in words1:
		all_words[word] = true
	for word in words2:
		all_words[word] = true
	
	total_unique_words = all_words.size()
	
	for word in words1:
		if word in words2:
			common_words += 1
	
	return float(common_words) / max(1, total_unique_words)

func _classify_relationship(similarity: float) -> String:
	"""Classify relationship type based on similarity"""
	if similarity > 0.7:
		return "highly_related"
	elif similarity > 0.4:
		return "moderately_related"
	elif similarity > 0.1:
		return "somewhat_related"
	else:
		return "unrelated"

func _remove_punctuation(text: String) -> String:
	"""Remove common punctuation from text"""
	var punctuation = ".,!?;:\"'()[]{}$%^&*-+=<>|\\/@#~`"
	var result = ""
	
	for ch in text:
		if not ch in punctuation:
			result += ch
	
	return result

func _remove_digits(text: String) -> String:
	"""Remove digits from text"""
	var result = ""
	
	for ch in text:
		if not ch.is_valid_int():
			result += ch
	
	return result

func _categorize_document_length(word_count: int) -> String:
	"""Categorize document by length"""
	if word_count < 100:
		return "very_short"
	elif word_count < 500:
		return "short"
	elif word_count < 2000:
		return "medium"
	elif word_count < 5000:
		return "long"
	else:
		return "very_long"

func _calculate_structure_quality(structure: Dictionary) -> float:
	"""Calculate overall structure quality score"""
	var score = 0.0
	
	if structure.get("has_clear_sections", false):
		score += 0.3
	
	score += structure.get("section_balance", 0.0) * 0.4
	score += structure.get("logical_flow", 0.0) * 0.3
	
	return score

func _calculate_content_density(stats: Dictionary) -> float:
	"""Calculate content density score"""
	var words_per_sentence = stats.get("average_words_per_sentence", 0.0)
	
	# Optimal range is 15-20 words per sentence
	if words_per_sentence >= 15 and words_per_sentence <= 20:
		return 1.0
	elif words_per_sentence >= 10 and words_per_sentence <= 25:
		return 0.8
	else:
		return 0.6

func _calculate_consistency_score(analysis: Dictionary) -> float:
	"""Calculate consistency across the document"""
	var nodes = analysis.get("nodes", [])
	if nodes.size() <= 1:
		return 1.0
	
	var readability_scores = []
	for node in nodes:
		readability_scores.append(node.get("readability_score", 0.0))
	
	# Calculate variance in readability scores
	var avg = readability_scores.reduce(func(a, b): return a + b) / readability_scores.size()
	var variance = 0.0
	
	for score in readability_scores:
		variance += pow(score - avg, 2)
	variance /= readability_scores.size()
	
	# Lower variance = higher consistency
	return max(0.0, 1.0 - sqrt(variance))

func _calculate_completeness_score(analysis: Dictionary) -> float:
	"""Calculate document completeness score"""
	var structure = analysis.get("structure", {})
	var stats = analysis.get("statistics", {})
	
	var score = 0.0
	
	# Has multiple sections
	if structure.get("has_clear_sections", false):
		score += 0.3
	
	# Adequate length
	var word_count = stats.get("total_words", 0)
	if word_count >= 100:
		score += 0.3
	
	# Balanced structure
	score += structure.get("section_balance", 0.0) * 0.4
	
	return score

# Processing completion handlers
func _finish_processing_with_success(analysis: Dictionary):
	"""Complete processing with successful analysis"""
	if current_processing:
		current_processing.syntree_analysis = analysis
		
		# Cache the analysis
		var cache_key = _get_document_cache_key(current_processing)
		analysis_cache[cache_key] = analysis
		
		print("SynTreeDocumentProcessor: Analysis completed for: ", current_processing.file_name)
		document_analysis_completed.emit(current_processing, analysis)
		
		current_processing = null
		
		# Process next in queue
		call_deferred("_process_next_in_queue")

func _finish_processing_with_error(error_message: String):
	"""Complete processing with error"""
	if current_processing:
		push_error("SynTreeDocumentProcessor: Analysis failed for %s: %s" % [current_processing.file_name, error_message])
		document_analysis_failed.emit(current_processing, error_message)
		
		current_processing = null
		
		# Process next in queue
		call_deferred("_process_next_in_queue")

func _get_document_cache_key(document: DocumentSessionManager.DocumentContext) -> String:
	"""Generate a cache key for a document"""
	var content_hash = hash(document.content)
	return "%s_%d" % [document.file_name, content_hash]

# Signal handlers
func _on_document_loaded(document):
	"""Handle document loaded signal"""
	if is_syntree_available():
		print("SynTreeDocumentProcessor: Auto-processing newly loaded document: ", document.file_name)
		process_document_with_syntree(document)

func _on_primary_document_changed(document):
	"""Handle primary document changed signal"""
	if is_syntree_available() and document:
		print("SynTreeDocumentProcessor: Auto-processing new primary document: ", document.file_name)
		process_document_with_syntree(document)

# Public API
func get_analysis_for_document(document: DocumentSessionManager.DocumentContext) -> Dictionary:
	"""Get cached analysis for a document"""
	if document and document.syntree_analysis:
		return document.syntree_analysis
	return {}

func clear_analysis_cache():
	"""Clear the analysis cache"""
	analysis_cache.clear()
	print("SynTreeDocumentProcessor: Analysis cache cleared")

func get_processing_status() -> Dictionary:
	"""Get current processing status"""
	return {
		"is_processing": current_processing != null,
		"current_document": current_processing.file_name if current_processing else "",
		"queue_size": processing_queue.size(),
		"cache_size": analysis_cache.size()
	} 
