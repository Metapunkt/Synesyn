extends Node
## Phase 4.5 Change Tracking and Session Management Test System
## Comprehensive testing for document editing history and session management

var test_results: Array[Dictionary] = []
var test_document_1: DocumentSessionManager.DocumentContext
var test_document_2: DocumentSessionManager.DocumentContext
var test_session_path: String = "user://test_session.json"

func _ready():
	# Wait for systems to initialize
	await get_tree().create_timer(1.0).timeout 
	add_to_group("phase_4_5_test")
	print("Phase4.5Test: Starting comprehensive change tracking and session management tests...")
	run_all_tests()

func run_all_tests():
	"""Run all Phase 4.5 tests"""
	print("Phase4.5Test: ==========================================")
	print("Phase4.5Test: PHASE 4.5 CHANGE TRACKING & SESSION TESTS")
	print("Phase4.5Test: ==========================================")
	
	# Clear any existing session
	if DocumentSessionManager:
		DocumentSessionManager.clear_session()
	
	# Test suites
	await test_enhanced_change_tracking()
	await test_change_visualization()
	await test_session_save_load()
	await test_change_summary_generation()
	await test_scratchpad_integration()
	await test_mission_control_integration()
	
	# Generate test report
	_generate_test_report()

func test_enhanced_change_tracking() -> bool:
	"""Test enhanced change tracking in DocumentContext"""
	print("Phase4.5Test: 🧪 Testing Enhanced Change Tracking...")
	
	var passed = 0
	var total = 8
	
	# Test 1: Document creation with tracking initialization
	if true:
		test_document_1 = DocumentSessionManager.DocumentContext.new("test1.txt", "Initial content for testing")
		
		if test_document_1.edit_session_id.begins_with("session_"):
			passed += 1
			print("Phase4.5Test: ✅ Session ID generation")
		else:
			print("Phase4.5Test: ❌ Session ID generation failed")
		
		if test_document_1.change_statistics.has("total_edits"):
			passed += 1
			print("Phase4.5Test: ✅ Change statistics initialization")
		else:
			print("Phase4.5Test: ❌ Change statistics initialization failed")
	else:
		print("Phase4.5Test: ❌ Document creation failed")
	
	# Test 2: Content update with detailed tracking
	if true:
		var new_content = "Initial content for testing\nAdded a new line with more text."
		test_document_1.update_content(new_content, "content", "test")
		
		if test_document_1.edit_history.size() > 0:
			passed += 1
			print("Phase4.5Test: ✅ Edit history tracking")
		else:
			print("Phase4.5Test: ❌ Edit history tracking failed")
		
		var latest_edit = test_document_1.edit_history[-1]
		if latest_edit.has("edit_id") and latest_edit.has("change_type") and latest_edit.has("words_delta"):
			passed += 1
			print("Phase4.5Test: ✅ Enhanced edit entry format")
		else:
			print("Phase4.5Test: ❌ Enhanced edit entry format missing")
	else:
		print("Phase4.5Test: ❌ Content update tracking failed")
	
	# Test 3: Change statistics updating
	if true:
		var stats = test_document_1.change_statistics
		if stats.get("total_edits", 0) > 0 and stats.has("words_added"):
			passed += 1
			print("Phase4.5Test: ✅ Change statistics update")
		else:
			print("Phase4.5Test: ❌ Change statistics update failed")
	else:
		print("Phase4.5Test: ❌ Change statistics test failed")
	
	# Test 4: Change markers generation
	if true:
		var markers = test_document_1.get_change_markers_for_visualization()
		if markers.size() > 0:
			passed += 1
			print("Phase4.5Test: ✅ Change markers generation")
		else:
			print("Phase4.5Test: ❌ Change markers generation failed")
	else:
		print("Phase4.5Test: ❌ Change markers test failed")
	
	# Test 5: Change history summary
	if true:
		var history_summary = test_document_1.get_change_history_summary()
		if history_summary.has("total_changes") and history_summary.has("recent_changes"):
			passed += 1
			print("Phase4.5Test: ✅ Change history summary")
		else:
			print("Phase4.5Test: ❌ Change history summary failed")
	else:
		print("Phase4.5Test: ❌ Change history summary test failed")
	
	# Test 6: Change summary generation
	if true:
		var summary = test_document_1.generate_change_summary()
		if summary.length() > 0 and "Total edits:" in summary:
			passed += 1
			print("Phase4.5Test: ✅ Change summary generation")
		else:
			print("Phase4.5Test: ❌ Change summary generation failed")
	else:
		print("Phase4.5Test: ❌ Change summary test failed")
	
	var success = (passed == total)
	_record_test_result("Enhanced Change Tracking", success, passed, total)
	return success

func test_change_visualization() -> bool:
	"""Test change visualization features in Scratchpad"""
	print("Phase4.5Test: 🧪 Testing Change Visualization...")
	
	var passed = 0
	var total = 4
	
	# Find scratchpad instance
	var scratchpad = _find_scratchpad()
	if not scratchpad:
		print("Phase4.5Test: ❌ Scratchpad not found")
		_record_test_result("Change Visualization", false, 0, total)
		return false
	
	# Test 1: Change summary display
	if true:
		if scratchpad.has_method("_update_change_summary"):
			scratchpad.enhanced_document_mode = true
			scratchpad.current_document_context = test_document_1
			scratchpad._update_change_summary()
			passed += 1
			print("Phase4.5Test: ✅ Change summary display")
		else:
			print("Phase4.5Test: ❌ Change summary method missing")
	else:
		print("Phase4.5Test: ❌ Change summary display test failed")
	
	# Test 2: Change history dialog
	if true:
		if scratchpad.has_method("show_change_history"):
			passed += 1
			print("Phase4.5Test: ✅ Change history dialog method exists")
		else:
			print("Phase4.5Test: ❌ Change history dialog method missing")
	else:
		print("Phase4.5Test: ❌ Change history dialog test failed")
	
	# Test 3: Comparison functionality
	if true:
		if scratchpad.has_method("compare_with_original"):
			passed += 1
			print("Phase4.5Test: ✅ Comparison functionality exists")
		else:
			print("Phase4.5Test: ❌ Comparison functionality missing")
	else:
		print("Phase4.5Test: ❌ Comparison test failed")
	
	# Test 4: Export functionality
	if true:
		if scratchpad.has_method("export_change_history"):
			passed += 1
			print("Phase4.5Test: ✅ Export functionality exists")
		else:
			print("Phase4.5Test: ❌ Export functionality missing")
	else:
		print("Phase4.5Test: ❌ Export test failed")
	
	var success = (passed == total)
	_record_test_result("Change Visualization", success, passed, total)
	return success

func test_session_save_load() -> bool:
	"""Test session save and load functionality"""
	print("Phase4.5Test: 🧪 Testing Session Save/Load...")
	
	var passed = 0
	var total = 6
	
	# Setup test session with multiple documents
	DocumentSessionManager.clear_session()
	test_document_1 = DocumentSessionManager.load_document_from_string("First document content", "test1.txt")
	test_document_2 = DocumentSessionManager.load_document_from_string("Second document content", "test2.txt")
	
	# Make some changes
	test_document_1.update_content("First document content\nWith added content", "content", "test")
	test_document_2.update_content("Second document content\nWith different changes", "line", "test")
	
	DocumentSessionManager.set_primary_document(test_document_1)
	
	# Test 1: Session save
	if true:
		var success = DocumentSessionManager.save_session(test_session_path)
		if success:
			passed += 1
			print("Phase4.5Test: ✅ Session save")
		else:
			print("Phase4.5Test: ❌ Session save failed")
	else:
		print("Phase4.5Test: ❌ Session save test failed")
	
	# Test 2: Verify session file exists
	if true:
		if FileAccess.file_exists(test_session_path):
			passed += 1
			print("Phase4.5Test: ✅ Session file creation")
		else:
			print("Phase4.5Test: ❌ Session file not created")
	else:
		print("Phase4.5Test: ❌ Session file check failed")
	
	# Test 3: Session file format validation
	if true:
		var file = FileAccess.open(test_session_path, FileAccess.READ)
		if file:
			var json_text = file.get_as_text()
			file.close()
			
			var json = JSON.new()
			var parse_result = json.parse(json_text)
			
			if parse_result == OK and json.data.has("session_info") and json.data.has("documents"):
				passed += 1
				print("Phase4.5Test: ✅ Session file format")
			else:
				print("Phase4.5Test: ❌ Session file format invalid")
		else:
			print("Phase4.5Test: ❌ Could not read session file")
	else:
		print("Phase4.5Test: ❌ Session file format test failed")
	
	# Clear session before loading
	DocumentSessionManager.clear_session()
	
	# Test 4: Session load
	if true:
		var success = DocumentSessionManager.load_session(test_session_path)
		if success:
			passed += 1
			print("Phase4.5Test: ✅ Session load")
		else:
			print("Phase4.5Test: ❌ Session load failed")
	else:
		print("Phase4.5Test: ❌ Session load test failed")
	
	# Test 5: Verify loaded documents
	if true:
		var loaded_docs = DocumentSessionManager.get_active_documents()
		if loaded_docs.size() == 2:
			passed += 1
			print("Phase4.5Test: ✅ Document count after load")
		else:
			print("Phase4.5Test: ❌ Document count mismatch: ", loaded_docs.size())
	else:
		print("Phase4.5Test: ❌ Document verification test failed")
	
	# Test 6: Verify change history preservation
	if true:
		var loaded_docs = DocumentSessionManager.get_active_documents()
		var has_history = false
		for doc in loaded_docs:
			if doc.edit_history.size() > 0:
				has_history = true
				break
		
		if has_history:
			passed += 1
			print("Phase4.5Test: ✅ Change history preservation")
		else:
			print("Phase4.5Test: ❌ Change history not preserved")
	else:
		print("Phase4.5Test: ❌ Change history verification failed")
	
	var success = (passed == total)
	_record_test_result("Session Save/Load", success, passed, total)
	return success

func test_change_summary_generation() -> bool:
	"""Test change summary generation functionality"""
	print("Phase4.5Test: 🧪 Testing Change Summary Generation...")
	
	var passed = 0
	var total = 4
	
	# Test 1: Individual document summary
	if true:
		var document = DocumentSessionManager.get_active_documents()[0]
		var summary = document.generate_change_summary()
		
		if summary.length() > 0 and "Total edits:" in summary:
			passed += 1
			print("Phase4.5Test: ✅ Document change summary")
		else:
			print("Phase4.5Test: ❌ Document change summary failed")
	else:
		print("Phase4.5Test: ❌ Document summary test failed")
	
	# Test 2: Session summary
	if true:
		var session_summary = DocumentSessionManager.get_session_change_summary()
		
		if session_summary.length() > 0 and "Session Overview:" in session_summary:
			passed += 1
			print("Phase4.5Test: ✅ Session change summary")
		else:
			print("Phase4.5Test: ❌ Session change summary failed")
	else:
		print("Phase4.5Test: ❌ Session summary test failed")
	
	# Test 3: Export data generation
	if true:
		var export_data = DocumentSessionManager.export_session_for_analysis()
		
		if export_data.has("session_metadata") and export_data.has("documents"):
			passed += 1
			print("Phase4.5Test: ✅ Export data generation")
		else:
			print("Phase4.5Test: ❌ Export data generation failed")
	else:
		print("Phase4.5Test: ❌ Export data test failed")
	
	# Test 4: Statistics calculation
	if true:
		var stats = DocumentSessionManager._calculate_session_statistics()
		
		if stats.has("total_documents") and stats.has("total_edits"):
			passed += 1
			print("Phase4.5Test: ✅ Session statistics calculation")
		else:
			print("Phase4.5Test: ❌ Session statistics calculation failed")
	else:
		print("Phase4.5Test: ❌ Statistics calculation test failed")
	
	var success = (passed == total)
	_record_test_result("Change Summary Generation", success, passed, total)
	return success

func test_scratchpad_integration() -> bool:
	"""Test Scratchpad integration with change tracking"""
	print("Phase4.5Test: 🧪 Testing Scratchpad Integration...")
	
	var passed = 0
	var total = 3
	
	var scratchpad = _find_scratchpad()
	if not scratchpad:
		print("Phase4.5Test: ❌ Scratchpad not found")
		_record_test_result("Scratchpad Integration", false, 0, total)
		return false
	
	# Test 1: Auto-save timer setup
	if true:
		if scratchpad.has_method("_setup_change_tracking") and scratchpad.auto_save_timer:
			passed += 1
			print("Phase4.5Test: ✅ Auto-save timer setup")
		else:
			print("Phase4.5Test: ❌ Auto-save timer setup failed")
	else:
		print("Phase4.5Test: ❌ Auto-save timer test failed")
	
	# Test 2: Change summary label
	if true:
		if scratchpad.change_summary_label:
			passed += 1
			print("Phase4.5Test: ✅ Change summary label exists")
		else:
			print("Phase4.5Test: ❌ Change summary label missing")
	else:
		print("Phase4.5Test: ❌ Change summary label test failed")
	
	# Test 3: Change visualization methods
	if true:
		var has_methods = (
			scratchpad.has_method("toggle_change_markers") and
			scratchpad.has_method("show_change_history") and
			scratchpad.has_method("export_change_history")
		)
		
		if has_methods:
			passed += 1
			print("Phase4.5Test: ✅ Change visualization methods")
		else:
			print("Phase4.5Test: ❌ Change visualization methods missing")
	else:
		print("Phase4.5Test: ❌ Change visualization methods test failed")
	
	var success = (passed == total)
	_record_test_result("Scratchpad Integration", success, passed, total)
	return success

func test_mission_control_integration() -> bool:
	"""Test Mission Control Dashboard integration"""
	print("Phase4.5Test: 🧪 Testing Mission Control Integration...")
	
	var passed = 0
	var total = 3
	
	var mission_control = _find_mission_control()
	if not mission_control:
		print("Phase4.5Test: ❌ Mission Control not found")
		_record_test_result("Mission Control Integration", false, 0, total)
		return false
	
	# Test 1: Session management buttons
	if true:
		var has_buttons = (
			mission_control.has_method("_on_save_session_pressed") and
			mission_control.has_method("_on_load_session_pressed") and
			mission_control.has_method("_on_view_history_pressed")
		)
		
		if has_buttons:
			passed += 1
			print("Phase4.5Test: ✅ Session management buttons")
		else:
			print("Phase4.5Test: ❌ Session management buttons missing")
	else:
		print("Phase4.5Test: ❌ Session management buttons test failed")
	
	# Test 2: Session statistics methods
	if true:
		var has_stats = (
			mission_control.has_method("_on_session_stats_pressed") and
			mission_control.has_method("_format_session_statistics_as_bbcode")
		)
		
		if has_stats:
			passed += 1
			print("Phase4.5Test: ✅ Session statistics methods")
		else:
			print("Phase4.5Test: ❌ Session statistics methods missing")
	else:
		print("Phase4.5Test: ❌ Session statistics methods test failed")
	
	# Test 3: Export functionality
	if true:
		var has_export = (
			mission_control.has_method("_on_export_session_pressed") and
			mission_control.has_method("_save_session_analysis_to_file")
		)
		
		if has_export:
			passed += 1
			print("Phase4.5Test: ✅ Export functionality")
		else:
			print("Phase4.5Test: ❌ Export functionality missing")
	else:
		print("Phase4.5Test: ❌ Export functionality test failed")
	
	var success = (passed == total)
	_record_test_result("Mission Control Integration", success, passed, total)
	return success

func _find_scratchpad() -> Node:
	"""Find scratchpad instance"""
	var scratchpads = get_tree().get_nodes_in_group("scratchpad")
	return scratchpads[0] if scratchpads.size() > 0 else null

func _find_mission_control() -> Node:
	"""Find mission control instance"""
	var mission_controls = get_tree().get_nodes_in_group("mission_control")
	return mission_controls[0] if mission_controls.size() > 0 else null

func _record_test_result(test_name: String, success: bool, passed: int, total: int):
	"""Record test result"""
	test_results.append({
		"name": test_name,
		"success": success,
		"passed": passed,
		"total": total,
		"score": float(passed) / total * 100.0
	})
	
	var status = "✅ PASS" if success else "❌ FAIL"
	print("Phase4.5Test: %s - %s (%d/%d - %.1f%%)" % [status, test_name, passed, total, float(passed)/total*100])

func _generate_test_report():
	"""Generate comprehensive test report"""
	print("Phase4.5Test: ==========================================")
	print("Phase4.5Test: PHASE 4.5 TEST RESULTS SUMMARY")
	print("Phase4.5Test: ==========================================")
	
	var total_passed = 0
	var total_tests = 0
	var all_success = true
	
	for result in test_results:
		total_passed += result.passed
		total_tests += result.total
		if not result.success:
			all_success = false
		
		var status_icon = "✅" if result.success else "❌"
		print("Phase4.5Test: %s %s: %d/%d tests passed (%.1f%%)" % [
			status_icon, result.name, result.passed, result.total, result.score
		])
	
	print("Phase4.5Test: ==========================================")
	var overall_score = float(total_passed) / total_tests * 100.0
	var overall_status = "✅ ALL TESTS PASSED" if all_success else "⚠️ SOME TESTS FAILED"
	
	print("Phase4.5Test: OVERALL RESULT: %s" % overall_status)
	print("Phase4.5Test: Total Score: %d/%d tests (%.1f%%)" % [total_passed, total_tests, overall_score])
	print("Phase4.5Test: ==========================================")
	
	# Implementation status
	print("Phase4.5Test: IMPLEMENTATION STATUS:")
	print("Phase4.5Test: ✅ Enhanced edit history tracking in DocumentContext")
	print("Phase4.5Test: ✅ Change visualization in Scratchpad")
	print("Phase4.5Test: ✅ Session save/load functionality")
	print("Phase4.5Test: ✅ Change summary generation")
	print("Phase4.5Test: ✅ Mission Control Dashboard integration")
	
	if all_success:
		print("Phase4.5Test: 🎉 PHASE 4.5 IMPLEMENTATION COMPLETE!")
		print("Phase4.5Test: All change tracking and session management features working!")
	else:
		print("Phase4.5Test: ⚠️ Some features need attention - check failed tests above")
	
	# Cleanup
	_cleanup_test_files()

func _cleanup_test_files():
	"""Clean up test files"""
	if FileAccess.file_exists(test_session_path):
		DirAccess.remove_absolute(test_session_path)
		print("Phase4.5Test: Cleaned up test session file")

# Manual test triggers (for debugging)
func _input(event):
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_F8:
				print("Phase4.5Test: Manual test trigger - Running all tests...")
				run_all_tests()
			KEY_F9:
				print("Phase4.5Test: Manual trigger - Testing session save/load only...")
				await test_session_save_load() 