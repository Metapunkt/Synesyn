extends Node
class_name PerformanceTestSuite

## Phase 5.2 Performance Optimization Test Suite
## Tests lazy loading, context window management, UI optimization, and large document handling

signal test_completed(test_name: String, success: bool, message: String)
signal all_tests_completed(total_tests: int, passed_tests: int)

# Test configuration
var test_results: Array = []
var current_test_index: int = 0
var test_start_time: float = 0.0

# Test data
var large_test_content: String = ""
var medium_test_content: String = ""
var small_test_content: String = ""

# Performance benchmarks
var performance_benchmarks: Dictionary = {
	"max_load_time": 1.0,      # 1 second max for document loading
	"max_memory_mb": 50.0,     # 50MB max memory usage
	"max_context_time": 0.5,   # 500ms max for context generation
	"max_ui_create_time": 0.1, # 100ms max for UI component creation
	"min_memory_efficiency": 0.6 # 60% minimum memory efficiency
}

func _ready():
	print("PerformanceTestSuite: Initializing Phase 5.2 performance tests...")
	_generate_test_content()
	call_deferred("run_all_tests")

func _generate_test_content():
	"""Generate test content of various sizes"""
	# Small content (5KB)
	small_test_content = "This is a small test document. ".repeat(200)
	
	# Medium content (50KB)
	var medium_paragraph = """This is a medium-sized test document designed to test normal document handling. 
It contains multiple paragraphs with various content types including headers, lists, and structured text.
This paragraph is repeated many times to reach the target size for performance testing.

## Section Header
- List item 1
- List item 2  
- List item 3

Some additional content with formatting and structure to make it realistic.
"""
	medium_test_content = medium_paragraph.repeat(100)
	
	# Large content (500KB)
	var large_paragraph = """This is a large test document designed to test lazy loading and performance optimization.
It contains extensive content that would typically be found in long-form documents such as reports,
manuscripts, technical documentation, or extensive articles.

### Performance Testing Section
This section is specifically designed to test the performance characteristics of the document management system.
We include various types of content including:

1. **Structured Lists**: Multiple levels of organization
   - Primary items
   - Secondary items
     - Tertiary items
     - Additional detail items

2. **Code Blocks**: 
   ```
   function example_code() {
       var result = "This is example code";
       return result;
   }
   ```

3. **Lengthy Paragraphs**: Extended prose that simulates real-world document content with complex sentence structures, detailed explanations, and comprehensive coverage of topics that would be found in professional documents.

4. **Tables and Data**: Structured information that requires careful rendering and memory management.

The purpose of this extensive content is to ensure that the lazy loading system works correctly with documents that exceed the typical size thresholds. This helps verify that:

- Chunks are loaded efficiently
- Memory usage remains optimal
- Context windows are properly managed
- UI performance is maintained
- User experience remains smooth

This paragraph pattern is repeated many times to create a document large enough to trigger lazy loading mechanisms and test the performance optimization features thoroughly.
"""
	large_test_content = large_paragraph.repeat(200)  # Creates ~500KB document
	
	print("PerformanceTestSuite: Generated test content - Small: %d chars, Medium: %d chars, Large: %d chars" % [
		small_test_content.length(),
		medium_test_content.length(), 
		large_test_content.length()
	])

func run_all_tests():
	"""Run the complete Phase 5.2 performance test suite"""
	print("PerformanceTestSuite: Starting Phase 5.2 performance test suite...")
	test_results.clear()
	test_start_time = Time.get_unix_time_from_system()
	
	# Test Categories:
	await run_lazy_loading_tests()
	await run_context_window_tests()
	await run_memory_management_tests()
	await run_ui_optimization_tests()
	await run_large_document_tests()
	await run_performance_benchmark_tests()
	
	_complete_test_suite()

func run_lazy_loading_tests() -> void:
	"""Test lazy loading functionality"""
	print("PerformanceTestSuite: Running lazy loading tests...")
	
	# Test 1: Large document lazy initialization
	var test_name = "Large Document Lazy Initialization"
	var start_time = Time.get_unix_time_from_system()
	
	if not DocumentSessionManager:
		_record_test_result(test_name, false, "DocumentSessionManager not available")
		return
	
	var doc = DocumentSessionManager.DocumentContext.new("", large_test_content)
	var init_time = Time.get_unix_time_from_system() - start_time
	
	var success = doc.is_large_document and init_time < performance_benchmarks.max_load_time
	var message = "Init time: %.3fs, Large doc: %s, Chunks: %d" % [
		init_time, 
		str(doc.is_large_document),
		doc.content_chunks.size()
	]
	_record_test_result(test_name, success, message)
	
	# Test 2: Chunk loading performance
	test_name = "Chunk Loading Performance"
	start_time = Time.get_unix_time_from_system()
	
	var chunk_loaded = doc.ensure_chunk_loaded(1)
	var chunk_time = Time.get_unix_time_from_system() - start_time
	
	success = chunk_loaded and chunk_time < 0.1  # 100ms max
	message = "Chunk loaded: %s, Time: %.3fs" % [str(chunk_loaded), chunk_time]
	_record_test_result(test_name, success, message)
	
	# Test 3: Content window retrieval
	test_name = "Content Window Retrieval"
	start_time = Time.get_unix_time_from_system()
	
	var content_window = doc.get_content_window(1000, 5000)
	var window_time = Time.get_unix_time_from_system() - start_time
	
	success = content_window.length() > 0 and window_time < 0.2  # 200ms max
	message = "Window size: %d chars, Time: %.3fs" % [content_window.length(), window_time]
	_record_test_result(test_name, success, message)
	
	await get_tree().process_frame

func run_context_window_tests() -> void:
	"""Test context window management"""
	print("PerformanceTestSuite: Running context window tests...")
	
	if not DocumentSessionManager:
		_record_test_result("Context Window Tests", false, "DocumentSessionManager not available")
		return
	
	# Setup test documents
	DocumentSessionManager.clear_session()
	var doc1 = DocumentSessionManager.load_document_from_string(medium_test_content, "test_doc_1.txt")
	var doc2 = DocumentSessionManager.load_document_from_string(small_test_content, "test_doc_2.txt")
	
	# Test 1: Single document context window
	var test_name = "Single Document Context Window"
	var start_time = Time.get_unix_time_from_system()
	
	var context_window = doc1.create_context_window(4000)  # 4K token limit
	var context_time = Time.get_unix_time_from_system() - start_time
	
	var success = (
		context_window.tokens_used > 0 and 
		context_window.tokens_used <= 4000 and
		context_time < performance_benchmarks.max_context_time
	)
	var message = "Tokens: %d, Time: %.3fs, Truncated: %s" % [
		context_window.tokens_used,
		context_time,
		str(context_window.truncated)
	]
	_record_test_result(test_name, success, message)
	
	# Test 2: Multi-document context window
	test_name = "Multi-Document Context Window"
	start_time = Time.get_unix_time_from_system()
	
	var multi_context = DocumentSessionManager.create_optimized_context_window(8000, true)
	var multi_time = Time.get_unix_time_from_system() - start_time
	
	success = (
		multi_context.documents_included >= 2 and
		multi_context.tokens_used > 0 and
		multi_time < performance_benchmarks.max_context_time
	)
	message = "Documents: %d, Tokens: %d, Time: %.3fs" % [
		multi_context.documents_included,
		multi_context.tokens_used,
		multi_time
	]
	_record_test_result(test_name, success, message)
	
	# Test 3: Context caching
	test_name = "Context Window Caching"
	start_time = Time.get_unix_time_from_system()
	
	# Create same context again - should be cached
	var cached_context = doc1.create_context_window(4000)
	var cache_time = Time.get_unix_time_from_system() - start_time
	
	success = cache_time < 0.01  # Should be very fast from cache
	message = "Cache time: %.3fs (should be < 0.01s)" % cache_time
	_record_test_result(test_name, success, message)
	
	await get_tree().process_frame

func run_memory_management_tests() -> void:
	"""Test memory management and optimization"""
	print("PerformanceTestSuite: Running memory management tests...")
	
	if not DocumentSessionManager:
		_record_test_result("Memory Management Tests", false, "DocumentSessionManager not available")
		return
	
	# Test 1: Memory usage tracking
	var test_name = "Memory Usage Tracking"
	
	DocumentSessionManager.clear_session()
	var initial_memory = DocumentSessionManager.get_memory_usage_summary()
	
	# Load multiple documents
	for i in range(3):
		DocumentSessionManager.load_document_from_string(medium_test_content, "memory_test_%d.txt" % i)
	
	var loaded_memory = DocumentSessionManager.get_memory_usage_summary()
	
	var success = (
		loaded_memory.total_memory > initial_memory.total_memory and
		loaded_memory.document_count == 3 and
		loaded_memory.total_memory < performance_benchmarks.max_memory_mb * 1000000
	)
	var message = "Memory: %.1f MB, Docs: %d, Efficiency: %.1f%%" % [
		loaded_memory.total_memory / 1000000.0,
		loaded_memory.document_count,
		loaded_memory.memory_efficiency * 100
	]
	_record_test_result(test_name, success, message)
	
	# Test 2: Memory optimization
	test_name = "Memory Optimization"
	var pre_optimize_memory = DocumentSessionManager.get_memory_usage_summary()
	var start_time = Time.get_unix_time_from_system()
	
	DocumentSessionManager.optimize_session_performance()
	var optimize_time = Time.get_unix_time_from_system() - start_time
	
	var post_optimize_memory = DocumentSessionManager.get_memory_usage_summary()
	
	success = optimize_time < 1.0  # Should complete quickly
	message = "Optimization time: %.3fs, Memory change: %.1f MB" % [
		optimize_time,
		(post_optimize_memory.total_memory - pre_optimize_memory.total_memory) / 1000000.0
	]
	_record_test_result(test_name, success, message)
	
	# Test 3: Performance report generation
	test_name = "Performance Report Generation"
	start_time = Time.get_unix_time_from_system()
	
	var performance_report = DocumentSessionManager.get_session_performance_report()
	var report_time = Time.get_unix_time_from_system() - start_time
	
	success = (
		performance_report.has("session_info") and
		performance_report.has("performance_summary") and
		performance_report.has("optimization_recommendations") and
		report_time < 0.5
	)
	message = "Report time: %.3fs, Recommendations: %d" % [
		report_time,
		performance_report.optimization_recommendations.size()
	]
	_record_test_result(test_name, success, message)
	
	await get_tree().process_frame

func run_ui_optimization_tests() -> void:
	"""Test UI optimization features"""
	print("PerformanceTestSuite: Running UI optimization tests...")
	
	# Test 1: Component pool creation
	var test_name = "UI Component Pool Creation"
	var start_time = Time.get_unix_time_from_system()
	
	# Simulate mission control dashboard if available
	var task_card_pool = []
	for i in range(10):
		var mock_card = Control.new()
		mock_card.name = "MockTaskCard_%d" % i
		task_card_pool.append(mock_card)
	
	var pool_time = Time.get_unix_time_from_system() - start_time
	
	var success = pool_time < performance_benchmarks.max_ui_create_time * 10  # 1s for 10 components
	var message = "Created %d components in %.3fs" % [task_card_pool.size(), pool_time]
	_record_test_result(test_name, success, message)
	
	# Clean up mock components
	for card in task_card_pool:
		card.queue_free()
	
	# Test 2: Component reuse simulation
	test_name = "Component Reuse Simulation"
	start_time = Time.get_unix_time_from_system()
	
	var reuse_pool = []
	var reused_components = 0
	
	# Simulate creating and reusing components
	for i in range(20):
		var component
		if reuse_pool.size() > 0:
			component = reuse_pool.pop_back()
			reused_components += 1
		else:
			component = Control.new()
		
		# Simulate use
		component.name = "Component_%d" % i
		
		# Return to pool sometimes
		if i % 3 == 0:
			reuse_pool.append(component)
		else:
			component.queue_free()
	
	var reuse_time = Time.get_unix_time_from_system() - start_time
	
	# Clean up remaining pool
	for component in reuse_pool:
		component.queue_free()
	
	success = reused_components > 0 and reuse_time < 0.1
	message = "Reused %d components in %.3fs" % [reused_components, reuse_time]
	_record_test_result(test_name, success, message)
	
	await get_tree().process_frame

func run_large_document_tests() -> void:
	"""Test handling of large documents"""
	print("PerformanceTestSuite: Running large document tests...")
	
	if not DocumentSessionManager:
		_record_test_result("Large Document Tests", false, "DocumentSessionManager not available")
		return
	
	# Test 1: Large document loading
	var test_name = "Large Document Loading"
	var start_time = Time.get_unix_time_from_system()
	
	DocumentSessionManager.clear_session()
	var large_doc = DocumentSessionManager.load_document_from_string(large_test_content, "large_test.txt")
	var load_time = Time.get_unix_time_from_system() - start_time
	
	var success = (
		large_doc != null and
		load_time < performance_benchmarks.max_load_time * 2 and  # Allow 2x time for large docs
		large_doc.is_large_document
	)
	var message = "Load time: %.3fs, Size: %.1f KB, Lazy: %s" % [
		load_time,
		large_test_content.length() / 1000.0,
		str(large_doc.is_large_document)
	]
	_record_test_result(test_name, success, message)
	
	# Test 2: Large document context creation
	test_name = "Large Document Context Creation"
	start_time = Time.get_unix_time_from_system()
	
	var large_context = DocumentSessionManager.create_optimized_context_window(8000, false)
	var context_time = Time.get_unix_time_from_system() - start_time
	
	success = (
		large_context.tokens_used > 0 and
		large_context.tokens_used <= 8000 and
		context_time < performance_benchmarks.max_context_time * 2
	)
	message = "Context time: %.3fs, Tokens: %d, Truncated: %s" % [
		context_time,
		large_context.tokens_used,
		str(large_context.truncated)
	]
	_record_test_result(test_name, success, message)
	
	# Test 3: Large document memory efficiency
	test_name = "Large Document Memory Efficiency"
	
	var memory_report = large_doc.get_performance_report()
	var efficiency = float(memory_report.memory_usage.content_size) / float(memory_report.memory_usage.total_memory_footprint)
	
	success = efficiency >= performance_benchmarks.min_memory_efficiency
	message = "Memory efficiency: %.1f%% (min: %.1f%%)" % [
		efficiency * 100,
		performance_benchmarks.min_memory_efficiency * 100
	]
	_record_test_result(test_name, success, message)
	
	await get_tree().process_frame

func run_performance_benchmark_tests() -> void:
	"""Run comprehensive performance benchmarks"""
	print("PerformanceTestSuite: Running performance benchmarks...")
	
	if not DocumentSessionManager:
		_record_test_result("Performance Benchmarks", false, "DocumentSessionManager not available")
		return
	
	# Test 1: Overall system performance
	var test_name = "Overall System Performance"
	var start_time = Time.get_unix_time_from_system()
	
	# Comprehensive workflow test
	DocumentSessionManager.clear_session()
	
	# Load multiple documents of different sizes
	var small_doc = DocumentSessionManager.load_document_from_string(small_test_content, "benchmark_small.txt")
	var medium_doc = DocumentSessionManager.load_document_from_string(medium_test_content, "benchmark_medium.txt")
	var large_doc = DocumentSessionManager.load_document_from_string(large_test_content, "benchmark_large.txt")
	
	# Create contexts
	var small_context = small_doc.create_context_window(2000)
	var medium_context = medium_doc.create_context_window(4000)
	var large_context = large_doc.create_context_window(8000)
	
	# Get performance report
	var final_report = DocumentSessionManager.get_session_performance_report()
	
	var total_time = Time.get_unix_time_from_system() - start_time
	
	var success = (
		total_time < 5.0 and  # Complete workflow in 5 seconds
		final_report.session_info.total_documents == 3 and
		final_report.performance_summary.memory_efficiency_score >= performance_benchmarks.min_memory_efficiency
	)
	var message = "Total time: %.3fs, Memory efficiency: %.1f%%, Documents: %d" % [
		total_time,
		final_report.performance_summary.memory_efficiency_score * 100,
		final_report.session_info.total_documents
	]
	_record_test_result(test_name, success, message)
	
	# Test 2: Performance under load
	test_name = "Performance Under Load"
	start_time = Time.get_unix_time_from_system()
	
	# Stress test with many operations
	for i in range(10):
		var context = DocumentSessionManager.create_optimized_context_window(4000, true)
		DocumentSessionManager.optimize_session_performance()
	
	var load_time = Time.get_unix_time_from_system() - start_time
	
	success = load_time < 3.0  # Should handle load test in 3 seconds
	message = "Load test time: %.3fs (10 context + optimize cycles)" % load_time
	_record_test_result(test_name, success, message)
	
	await get_tree().process_frame

func _record_test_result(test_name: String, success: bool, message: String):
	"""Record a test result"""
	var result = {
		"name": test_name,
		"success": success,
		"message": message,
		"timestamp": Time.get_unix_time_from_system()
	}
	test_results.append(result)
	
	var status = "✓ PASS" if success else "✗ FAIL"
	print("PerformanceTestSuite: [%s] %s - %s" % [status, test_name, message])
	
	test_completed.emit(test_name, success, message)

func _complete_test_suite():
	"""Complete the test suite and report results"""
	var total_tests = test_results.size()
	var passed_tests = 0
	var failed_tests = []
	
	for result in test_results:
		if result.success:
			passed_tests += 1
		else:
			failed_tests.append(result.name)
	
	var total_time = Time.get_unix_time_from_system() - test_start_time
	var pass_rate = float(passed_tests) / float(total_tests) * 100.0
	
	print("\n" + "=".repeat(60))
	print("PHASE 5.2 PERFORMANCE TEST SUITE COMPLETE")
	print("=".repeat(60))
	print("Total Tests: %d" % total_tests)
	print("Passed: %d" % passed_tests)
	print("Failed: %d" % (total_tests - passed_tests))
	print("Pass Rate: %.1f%%" % pass_rate)
	print("Total Time: %.3f seconds" % total_time)
	
	if failed_tests.size() > 0:
		print("\nFailed Tests:")
		for test_name in failed_tests:
			print("  - %s" % test_name)
	
	print("\nPerformance Benchmarks:")
	print("  Max Load Time: %.1fs" % performance_benchmarks.max_load_time)
	print("  Max Memory: %.1f MB" % performance_benchmarks.max_memory_mb)
	print("  Max Context Time: %.1fs" % performance_benchmarks.max_context_time)
	print("  Max UI Create Time: %.1fs" % performance_benchmarks.max_ui_create_time)
	print("  Min Memory Efficiency: %.1f%%" % (performance_benchmarks.min_memory_efficiency * 100))
	
	print("=".repeat(60))
	
	all_tests_completed.emit(total_tests, passed_tests)

func run_manual_test():
	"""Manual test trigger for F10 key"""
	print("PerformanceTestSuite: Manual test triggered!")
	run_all_tests()

func _input(event):
	"""Handle manual test triggers"""
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_F10:
				run_manual_test()

func get_test_results() -> Array:
	"""Get all test results"""
	return test_results.duplicate()

func get_performance_summary() -> Dictionary:
	"""Get performance summary"""
	var summary = {
		"total_tests": test_results.size(),
		"passed_tests": 0,
		"failed_tests": 0,
		"pass_rate": 0.0,
		"benchmarks": performance_benchmarks.duplicate(),
		"test_duration": 0.0
	}
	
	for result in test_results:
		if result.success:
			summary.passed_tests += 1
		else:
			summary.failed_tests += 1
	
	if summary.total_tests > 0:
		summary.pass_rate = float(summary.passed_tests) / float(summary.total_tests) * 100.0
	
	if test_results.size() > 0:
		summary.test_duration = test_results[-1].timestamp - test_start_time
	
	return summary 