extends Node

## Phase 5.1: Task Integration Test Suite
## Tests all task creation and integration functionality

signal test_completed(passed: bool, details: String)

var test_results: Array = []
var total_tests: int = 0
var passed_tests: int = 0

func _ready():
	print("Phase 5.1 Test Suite: Task Integration")
	add_to_group("test_suites")

func run_all_tests():
	"""Run all Phase 5.1 task integration tests"""
	print("\n=== Starting Phase 5.1: Task Integration Tests ===")
	test_results.clear()
	total_tests = 0
	passed_tests = 0
	
	# Test categories
	_test_task_creation_from_session()
	_test_document_references_integration()
	_test_session_insights_integration()
	_test_multiple_task_creation()
	_test_ai_task_suggestions()
	_test_workplan_integration()
	
	_print_test_summary()
	test_completed.emit(passed_tests == total_tests, "Phase 5.1 Tests: %d/%d passed" % [passed_tests, total_tests])

# === CORE TASK CREATION TESTS ===

func _test_task_creation_from_session():
	"""Test basic task creation from edit session"""
	print("\n--- Testing Task Creation from Session ---")
	
	# Test 1: Create task from single document session
	_run_test("Create task from single document", func():
		# Setup test session
		DocumentSessionManager.clear_session()
		var test_doc = DocumentSessionManager.load_document_from_string(
			"This is a test proposal document with multiple sections.", 
			"test_proposal.md"
		)
		test_doc.update_content("This is a test proposal document with multiple sections.\n\nSection 1: Overview\nSection 2: Details", "user", "manual")
		
		# Create task from session
		var task = DocumentSessionManager.create_task_from_edit_session()
		
		return task != null and \
			not task.title.is_empty() and \
			task.has_edit_session_origin() and \
			task.get_document_count() == 1 and \
			task.auto_generated == true
	)
	
	# Test 2: Task creation with empty session should fail
	_run_test("Task creation fails with empty session", func():
		DocumentSessionManager.clear_session()
		var task = DocumentSessionManager.create_task_from_edit_session()
		return task == null
	)

func _test_document_references_integration():
	"""Test document references and snapshots in tasks"""
	print("\n--- Testing Document References Integration ---")
	
	# Test 1: Single document reference
	_run_test("Single document reference creation", func():
		DocumentSessionManager.clear_session()
		var test_doc = DocumentSessionManager.load_document_from_string(
			"Test document content for reference testing", 
			"reference_test.md"
		)
		test_doc.is_primary = true
		
		var task = DocumentSessionManager.create_task_from_edit_session()
		var primary_doc = task.get_primary_document()
		
		return task.get_document_count() == 1 and \
			not primary_doc.is_empty() and \
			primary_doc.get("is_primary", false) == true
	)

func _test_session_insights_integration():
	"""Test session insights and analytics integration"""
	print("\n--- Testing Session Insights Integration ---")
	
	# Test 1: Session insights are captured
	_run_test("Session insights integration", func():
		DocumentSessionManager.clear_session()
		var test_doc = DocumentSessionManager.load_document_from_string("Test content for insights", "insights_test.md")
		test_doc.update_content("Updated test content for insights analysis", "user", "manual")
		
		var task = DocumentSessionManager.create_task_from_edit_session()
		
		return not task.session_insights.is_empty() and \
			not task.productivity_metrics.is_empty() and \
			not task.source_session_summary.is_empty()
	)

func _test_multiple_task_creation():
	"""Test multiple task creation from session"""
	print("\n--- Testing Multiple Task Creation ---")
	
	# Test 1: Create multiple tasks with different configs
	_run_test("Create multiple tasks with configs", func():
		DocumentSessionManager.clear_session()
		var doc1 = DocumentSessionManager.load_document_from_string("Document 1", "doc1.md")
		var doc2 = DocumentSessionManager.load_document_from_string("Document 2", "doc2.md")
		
		var task_configs = [
			{"title": "Review Task", "priority": 1, "estimated_duration": 30},
			{"title": "Follow-up Task", "priority": 2, "estimated_duration": 45}
		]
		
		var created_tasks = DocumentSessionManager.create_multiple_tasks_from_session(task_configs)
		
		return created_tasks.size() == 2 and \
			created_tasks[0].title == "Review Task" and \
			created_tasks[0].priority == 1
	)

func _test_ai_task_suggestions():
	"""Test AI-powered task suggestions"""
	print("\n--- Testing AI Task Suggestions ---")
	
	# Test 1: Get task creation suggestions
	_run_test("Get task creation suggestions", func():
		DocumentSessionManager.clear_session()
		var test_doc = DocumentSessionManager.load_document_from_string("Test document for suggestions", "suggestions_test.md")
		test_doc.update_content("Updated content with TODO items to fix", "user", "manual")
		
		var suggestions = DocumentSessionManager.get_task_creation_suggestions()
		
		return not suggestions.has("error") and \
			suggestions.has("recommended_tasks") and \
			suggestions.has("session_analysis")
	)

func _test_workplan_integration():
	"""Test integration with workplan system"""
	print("\n--- Testing Workplan Integration ---")
	
	# Test 1: Task references edit session ID
	_run_test("Task references edit session ID", func():
		DocumentSessionManager.clear_session()
		var test_doc = DocumentSessionManager.load_document_from_string("Workplan test content", "workplan_test.md")
		var session_id = DocumentSessionManager.current_session_id
		
		var task = DocumentSessionManager.create_task_from_edit_session()
		
		return task.edit_session_id == session_id and task.has_edit_session_origin()
	)

# === TEST INFRASTRUCTURE ===

func _run_test(test_name: String, test_func: Callable) -> bool:
	"""Run a single test and record results"""
	total_tests += 1
	var start_time = Time.get_ticks_msec()
	
	var result = false
	var error_message = ""
	if true:
		result = test_func.call()
	else:
		error_message = "Exception occurred during test execution"
		result = false
	
	var duration = Time.get_ticks_msec() - start_time
	
	if result:
		passed_tests += 1
		print("✅ %s (%.1fms)" % [test_name, duration])
	else:
		print("❌ %s (%.1fms) - %s" % [test_name, duration, error_message])
	
	test_results.append({
		"name": test_name,
		"passed": result,
		"duration": duration,
		"error": error_message
	})
	
	return result

func _print_test_summary():
	"""Print comprehensive test summary"""
	print("\n" + "=".repeat(60))
	print("PHASE 5.1 TASK INTEGRATION TEST SUMMARY")
	print("=".repeat(60))
	print("Total Tests: %d" % total_tests)
	print("Passed: %d" % passed_tests)
	print("Failed: %d" % (total_tests - passed_tests))
	print("Success Rate: %.1f%%" % ((float(passed_tests) / total_tests) * 100))
	
	print("\nPhase 5.1 Task Integration: %s" % ("✅ PASSED" if passed_tests == total_tests else "❌ FAILED"))
	print("=".repeat(60))

# Manual test triggers
func _input(event):
	"""Handle manual test triggers"""
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_F9:
				print("F9: Running Phase 5.1 Task Integration tests...")
				run_all_tests() 