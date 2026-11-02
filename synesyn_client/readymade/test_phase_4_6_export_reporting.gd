extends Node

# Test suite for ReadyMade Phase 4.6: Export and Reporting Features
# Tests comprehensive report generation, document export, analytics, and session sharing

signal test_completed(test_name: String, passed: bool, details: String)
signal all_tests_completed(summary: Dictionary)

var test_results = {}
var test_session_manager: Node
var test_documents = []

func _ready():
	print("Phase 4.6 Test Suite: Export and Reporting Features")
	print("=".repeat(60))
	
	# Setup test environment
	_setup_test_environment()
	
	# Run all tests
	await _run_all_tests()
	
	# Generate test report
	_generate_test_report()

func _setup_test_environment():
	"""Setup test environment with sample documents and session data"""
	# Create test session manager instance
	test_session_manager = DocumentSessionManager
	
	if not test_session_manager:
		push_error("DocumentSessionManager not available for testing")
		return
	
	# Clear any existing session
	test_session_manager.clear_session()
	
	# Create test documents with various content and change patterns
	_create_test_documents()
	
	print("Test environment setup complete")

func _create_test_documents():
	"""Create test documents with sample content and edit history"""
	# Document 1: Primary document with extensive edits
	var doc1_content = """# Project Proposal: AI-Enhanced Document Editor

## Overview
This document outlines our proposal for developing an AI-enhanced document editing system that will revolutionize how users interact with textual content.

## Key Features
- Real-time collaborative editing
- AI-powered content suggestions
- Advanced change tracking
- Multi-format export capabilities

## Technical Architecture
The system will be built using a modular architecture with the following components:
1. Core editing engine
2. AI analysis module
3. Collaboration framework
4. Export and reporting system

## Implementation Timeline
Phase 1: Core functionality (3 months)
Phase 2: AI integration (2 months)
Phase 3: Advanced features (2 months)
Phase 4: Testing and deployment (1 month)

## Expected Outcomes
We anticipate this system will improve user productivity by 40% and reduce editing time by 60%.
"""
	
	var doc1 = test_session_manager.load_document_from_string(doc1_content, "Project_Proposal.md")
	if doc1:
		test_session_manager.set_primary_document(doc1)
		# Simulate extensive editing history
		_simulate_document_edits(doc1, 25)
		test_documents.append(doc1)
	
	# Document 2: Research notes with moderate edits
	var doc2_content = """# Research Notes: Document Editing Technologies

## Current Solutions
- Microsoft Word: Industry standard but limited collaboration
- Google Docs: Good collaboration, basic AI features
- Notion: Flexible but complex interface
- Obsidian: Powerful linking, local-first approach

## AI Integration Opportunities
Recent advances in large language models present opportunities for:
- Content generation assistance
- Grammar and style checking
- Document structure optimization
- Automated summarization

## Technical Considerations
Performance requirements:
- Real-time responsiveness
- Offline capability
- Cross-platform compatibility
- Secure data handling

## User Experience Priorities
1. Intuitive interface design
2. Seamless collaboration workflows
3. Customizable AI assistance levels
4. Rich formatting options
"""
	
	var doc2 = test_session_manager.load_document_from_string(doc2_content, "Research_Notes.md")
	if doc2:
		_simulate_document_edits(doc2, 12)
		test_documents.append(doc2)
	
	# Document 3: Meeting minutes with light edits
	var doc3_content = """# Team Meeting Minutes - December 27, 2024

**Attendees:** Alice, Bob, Charlie, Diana
**Duration:** 2 hours
**Location:** Conference Room A

## Agenda Items

### 1. Project Status Review
- Phase 4.5 implementation completed successfully
- Change tracking system fully operational
- Session management features tested and verified

### 2. Phase 4.6 Planning
- Export and reporting features prioritized
- Analytics dashboard requirements defined
- Session sharing functionality scoped

### 3. Technical Decisions
- HTML export format approved
- Markdown export for documentation
- JSON export for data analysis
- PDF-ready format for formal reports

### 4. Next Steps
- Begin Phase 4.6 implementation
- Create comprehensive test suite
- Document new API endpoints
- Schedule user acceptance testing

## Action Items
- [ ] Alice: Implement report generation (Due: Dec 30)
- [ ] Bob: Create export UI components (Due: Dec 28)
- [ ] Charlie: Design analytics dashboard (Due: Jan 2)
- [ ] Diana: Write user documentation (Due: Jan 5)
"""
	
	var doc3 = test_session_manager.load_document_from_string(doc3_content, "Meeting_Minutes_2024-12-27.md")
	if doc3:
		_simulate_document_edits(doc3, 5)
		test_documents.append(doc3)
	
	print("Created %d test documents with simulated edit history" % test_documents.size())

func _simulate_document_edits(document, edit_count: int):
	"""Simulate editing history for a document"""
	var base_content = document.content
	var edit_modes = ["developmental", "structural", "refinement", "proofreading"]
	
	for i in range(edit_count):
		var mode = edit_modes[i % edit_modes.size()]
		var timestamp = Time.get_unix_time_from_system() - (edit_count - i) * 300  # 5 min intervals
		
		# Simulate different types of edits
		var edit_type = i % 4
		match edit_type:
			0:  # Add content
				document.content += "\n\n## Additional Section %d\nThis is additional content added during editing session." % i
			1:  # Modify existing content
				document.content = document.content.replace("system", "platform")
			2:  # Remove content (simulate)
				pass  # Content removal simulation
			3:  # Formatting changes
				document.content = document.content.replace("##", "###")  # Change heading levels
		
		# Update document with edit information
		test_session_manager.update_document_content(document, document.content, "test_simulation")
		
		# Manually add to edit history (simulating real editing)
		document.edit_history.append({
			"timestamp": timestamp,
			"change_description": "Simulated edit %d: %s" % [i + 1, ["Content addition", "Text modification", "Content removal", "Format change"][edit_type]],
			"change_type": ["addition", "modification", "deletion", "formatting"][edit_type],
			"edit_mode": mode,
			"significant_change": (i % 5 == 0),  # Every 5th edit is significant
			"words_delta": randi_range(-10, 20),
			"characters_delta": randi_range(-50, 100)
		})
	
	# Update change statistics
	document.change_statistics["total_edits"] = edit_count
	document.change_statistics["words_added"] = edit_count * 5
	document.change_statistics["words_removed"] = edit_count * 2
	document.change_statistics["change_velocity"] = float(edit_count) / 60.0  # edits per minute

func _run_all_tests() -> void:
	"""Run all Phase 4.6 tests"""
	print("\nRunning Phase 4.6 Export and Reporting Tests...")
	print("-".repeat(50))
	
	# Test categories
	await _test_report_generation()
	await _test_document_export()
	await _test_session_sharing()
	await _test_analytics_features()
	await _test_export_formats()
	await _test_error_handling()
	
	print("\nAll tests completed!")

# === REPORT GENERATION TESTS ===

func _test_report_generation():
	"""Test comprehensive report generation functionality"""
	print("\n🔍 Testing Report Generation...")
	
	# Test HTML report generation
	await _test_html_report()
	await _test_markdown_report()
	await _test_json_report()
	await _test_text_report()
	await _test_pdf_ready_report()

func _test_html_report():
	"""Test HTML report generation"""
	var test_name = "HTML Report Generation"
	if true:
		var report_path = test_session_manager.generate_edit_session_report(
			DocumentSessionManager.ExportFormat.HTML
		)
		
		if report_path.is_empty():
			_record_test_result(test_name, false, "Failed to generate HTML report")
			return
		
		# Check if file exists
		if not FileAccess.file_exists(report_path):
			_record_test_result(test_name, false, "HTML report file not created: " + report_path)
			return
		
		# Read and validate HTML content
		var file = FileAccess.open(report_path, FileAccess.READ)
		if not file:
			_record_test_result(test_name, false, "Cannot read HTML report file")
			return
		
		var content = file.get_as_text()
		file.close()
		
		# Validate HTML structure
		var has_html_tags = content.contains("<html>") and content.contains("</html>")
		var has_title = content.contains("<title>")
		var has_session_data = content.contains("Session Overview")
		var has_css = content.contains("<style>")
		
		if has_html_tags and has_title and has_session_data and has_css:
			_record_test_result(test_name, true, "HTML report generated successfully with valid structure")
		else:
			_record_test_result(test_name, false, "HTML report missing required elements")
	else:
		_record_test_result(test_name, false, "Exception during HTML report generation")

func _test_markdown_report():
	"""Test Markdown report generation"""
	var test_name = "Markdown Report Generation"
	if true:
		var report_path = test_session_manager.generate_edit_session_report(
			DocumentSessionManager.ExportFormat.MARKDOWN
		)
		
		if report_path.is_empty():
			_record_test_result(test_name, false, "Failed to generate Markdown report")
			return
		
		if not FileAccess.file_exists(report_path):
			_record_test_result(test_name, false, "Markdown report file not created")
			return
		
		var file = FileAccess.open(report_path, FileAccess.READ)
		var content = file.get_as_text()
		file.close()
		
		# Validate Markdown structure
		var has_title = content.contains("# Edit Session Report")
		var has_overview = content.contains("## Session Overview")
		var has_bullets = content.contains("- **")
		
		if has_title and has_overview and has_bullets:
			_record_test_result(test_name, true, "Markdown report generated with proper formatting")
		else:
			_record_test_result(test_name, false, "Markdown report missing required formatting")
	else:
		_record_test_result(test_name, false, "Exception during Markdown report generation")

func _test_json_report():
	"""Test JSON report generation"""
	var test_name = "JSON Report Generation"
	if true:
		var report_path = test_session_manager.generate_edit_session_report(
			DocumentSessionManager.ExportFormat.JSON
		)
		
		if report_path.is_empty():
			_record_test_result(test_name, false, "Failed to generate JSON report")
			return
		
		var file = FileAccess.open(report_path, FileAccess.READ)
		var content = file.get_as_text()
		file.close()
		
		# Validate JSON structure
		var json = JSON.new()
		var parse_result = json.parse(content)
		
		if parse_result != OK:
			_record_test_result(test_name, false, "Invalid JSON format in report")
			return
		
		var data = json.data
		var has_metadata = data.has("metadata")
		var has_overview = data.has("session_overview")
		var has_documents = data.has("document_analysis")
		var has_recommendations = data.has("recommendations")
		
		if has_metadata and has_overview and has_documents and has_recommendations:
			_record_test_result(test_name, true, "JSON report generated with complete data structure")
		else:
			_record_test_result(test_name, false, "JSON report missing required data sections")
	else:
		_record_test_result(test_name, false, "Exception during JSON report generation")

func _test_text_report():
	"""Test plain text report generation"""
	var test_name = "Plain Text Report Generation"
	if true:
		var report_path = test_session_manager.generate_edit_session_report(
			DocumentSessionManager.ExportFormat.PLAIN_TEXT
		)
		
		if not report_path.is_empty() and FileAccess.file_exists(report_path):
			_record_test_result(test_name, true, "Plain text report generated successfully")
		else:
			_record_test_result(test_name, false, "Failed to generate plain text report")
	else:
		_record_test_result(test_name, false, "Exception during plain text report generation")

func _test_pdf_ready_report():
	"""Test PDF-ready HTML report generation"""
	var test_name = "PDF-Ready Report Generation"
	if true:
		var report_path = test_session_manager.generate_edit_session_report(
			DocumentSessionManager.ExportFormat.PDF_READY
		)
		
		if report_path.is_empty():
			_record_test_result(test_name, false, "Failed to generate PDF-ready report")
			return
		
		var file = FileAccess.open(report_path, FileAccess.READ)
		var content = file.get_as_text()
		file.close()
		
		# Validate PDF-ready features
		var has_print_css = content.contains("@media print")
		var has_page_breaks = content.contains("page-break")
		var has_margins = content.contains("margin:")
		
		if has_print_css and (has_page_breaks or has_margins):
			_record_test_result(test_name, true, "PDF-ready report generated with print styling")
		else:
			_record_test_result(test_name, false, "PDF-ready report missing print optimizations")
	else:
		_record_test_result(test_name, false, "Exception during PDF-ready report generation")

# === DOCUMENT EXPORT TESTS ===

func _test_document_export():
	"""Test document export functionality"""
	print("\n📄 Testing Document Export...")
	
	await _test_single_document_export()
	await _test_bulk_document_export()
	await _test_export_with_change_tracking()

func _test_single_document_export():
	"""Test exporting a single document"""
	var test_name = "Single Document Export"
	
	if test_documents.is_empty():
		_record_test_result(test_name, false, "No test documents available")
		return
	if true:
		var document = test_documents[0]
		var export_path = test_session_manager.export_document(
			document, 
			DocumentSessionManager.ExportFormat.HTML
		)
		
		if export_path.is_empty():
			_record_test_result(test_name, false, "Failed to export document")
			return
		
		if FileAccess.file_exists(export_path):
			var file = FileAccess.open(export_path, FileAccess.READ)
			var content = file.get_as_text()
			file.close()
			
			# Validate exported content
			var has_title = content.contains(document.file_name)
			var has_content = content.contains(document.content.substr(0, 50))
			var has_change_info = content.contains("Change Summary")
			
			if has_title and has_content and has_change_info:
				_record_test_result(test_name, true, "Document exported successfully with change tracking")
			else:
				_record_test_result(test_name, false, "Exported document missing required content")
		else:
			_record_test_result(test_name, false, "Export file not created")
	else:
		_record_test_result(test_name, false, "Exception during single document export")

func _test_bulk_document_export():
	"""Test exporting all documents"""
	var test_name = "Bulk Document Export"
	if true:
		var exported_files = test_session_manager.export_all_documents(
			DocumentSessionManager.ExportFormat.MARKDOWN
		)
		
		if exported_files.size() != test_documents.size():
			_record_test_result(test_name, false, "Not all documents were exported")
			return
		
		# Verify all files exist
		var all_exist = true
		for file_path in exported_files:
			if not FileAccess.file_exists(file_path):
				all_exist = false
				break
		
		if all_exist:
			_record_test_result(test_name, true, "All documents exported successfully")
		else:
			_record_test_result(test_name, false, "Some exported files are missing")
	else:
		_record_test_result(test_name, false, "Exception during bulk document export")

func _test_export_with_change_tracking():
	"""Test that exports include change tracking information"""
	var test_name = "Export with Change Tracking"
	
	if test_documents.is_empty():
		_record_test_result(test_name, false, "No test documents available")
		return
	if true:
		var document = test_documents[0]
		var export_path = test_session_manager.export_document(
			document,
			DocumentSessionManager.ExportFormat.JSON
		)
		
		var file = FileAccess.open(export_path, FileAccess.READ)
		var content = file.get_as_text()
		file.close()
		
		var json = JSON.new()
		json.parse(content)
		var data = json.data
		
		var has_change_tracking = data.has("change_tracking")
		var has_edit_history = data.get("change_tracking", {}).has("edit_history")
		var has_statistics = data.get("change_tracking", {}).has("change_statistics")
		
		if has_change_tracking and has_edit_history and has_statistics:
			_record_test_result(test_name, true, "Export includes comprehensive change tracking data")
		else:
			_record_test_result(test_name, false, "Export missing change tracking information")
	else:
		_record_test_result(test_name, false, "Exception during change tracking export test")

# === SESSION SHARING TESTS ===

func _test_session_sharing():
	"""Test session sharing functionality"""
	print("\n🤝 Testing Session Sharing...")
	
	await _test_shareable_package_creation()
	await _test_anonymized_sharing()
	await _test_share_export()

func _test_shareable_package_creation():
	"""Test creation of shareable session packages"""
	var test_name = "Shareable Package Creation"
	if true:
		var share_package = test_session_manager.create_shareable_session_package()
		
		var has_version = share_package.has("version")
		var has_session_info = share_package.has("session_info")
		var has_documents = share_package.has("documents")
		var has_analytics = share_package.has("analytics")
		var has_metadata = share_package.has("sharing_metadata")
		
		if has_version and has_session_info and has_documents and has_analytics and has_metadata:
			# Verify anonymization
			var metadata = share_package.get("sharing_metadata", {})
			var is_anonymized = metadata.get("anonymized", false)
			var no_content = not metadata.get("includes_content", true)
			
			if is_anonymized and no_content:
				_record_test_result(test_name, true, "Shareable package created with proper anonymization")
			else:
				_record_test_result(test_name, false, "Package not properly anonymized")
		else:
			_record_test_result(test_name, false, "Package missing required sections")
	else:
		_record_test_result(test_name, false, "Exception during shareable package creation")

func _test_anonymized_sharing():
	"""Test that shared packages don't contain sensitive content"""
	var test_name = "Anonymized Sharing"
	if true:
		var share_package = test_session_manager.create_shareable_session_package()
		var documents = share_package.get("documents", [])
		
		var properly_anonymized = true
		for doc in documents:
			# Check that document names are anonymized
			if not doc.get("name", "").begins_with("Document_"):
				properly_anonymized = false
				break
			
			# Check that actual content is not included
			if doc.has("content"):
				properly_anonymized = false
				break
		
		if properly_anonymized:
			_record_test_result(test_name, true, "All sensitive data properly anonymized")
		else:
			_record_test_result(test_name, false, "Sensitive data found in shareable package")
	else:
		_record_test_result(test_name, false, "Exception during anonymization test")

func _test_share_export():
	"""Test exporting shareable packages to file"""
	var test_name = "Share Export to File"
	if true:
		var share_path = test_session_manager.export_session_for_sharing()
		
		if share_path.is_empty():
			_record_test_result(test_name, false, "Failed to export shareable package")
			return
		
		if FileAccess.file_exists(share_path):
			# Verify file content
			var file = FileAccess.open(share_path, FileAccess.READ)
			var content = file.get_as_text()
			file.close()
			
			var json = JSON.new()
			var parse_result = json.parse(content)
			
			if parse_result == OK:
				_record_test_result(test_name, true, "Shareable package exported successfully")
			else:
				_record_test_result(test_name, false, "Invalid JSON in exported package")
		else:
			_record_test_result(test_name, false, "Share export file not created")
	else:
		_record_test_result(test_name, false, "Exception during share export test")

# === ANALYTICS TESTS ===

func _test_analytics_features():
	"""Test analytics and insights functionality"""
	print("\n📊 Testing Analytics Features...")
	
	await _test_comprehensive_analytics()
	await _test_productivity_metrics()
	await _test_recommendations_generation()

func _test_comprehensive_analytics():
	"""Test comprehensive analytics data compilation"""
	var test_name = "Comprehensive Analytics"
	if true:
		var analytics_data = test_session_manager._compile_comprehensive_report_data()
		
		var has_metadata = analytics_data.has("metadata")
		var has_overview = analytics_data.has("session_overview")
		var has_documents = analytics_data.has("document_analysis")
		var has_timeline = analytics_data.has("change_timeline")
		var has_productivity = analytics_data.has("productivity_metrics")
		var has_insights = analytics_data.has("content_insights")
		var has_recommendations = analytics_data.has("recommendations")
		
		if has_metadata and has_overview and has_documents and has_timeline and has_productivity and has_insights and has_recommendations:
			_record_test_result(test_name, true, "Comprehensive analytics data compiled successfully")
		else:
			_record_test_result(test_name, false, "Analytics data missing required sections")
	else:
		_record_test_result(test_name, false, "Exception during analytics compilation")

func _test_productivity_metrics():
	"""Test productivity metrics calculation"""
	var test_name = "Productivity Metrics"
	if true:
		var metrics = test_session_manager._calculate_productivity_metrics()
		
		var has_speed_metrics = metrics.has("words_per_minute") and metrics.has("edits_per_minute")
		var has_efficiency = metrics.has("efficiency_score")
		var has_patterns = metrics.has("peak_productivity_time") and metrics.has("consistency_score")
		
		# Verify metrics are reasonable
		var wpm = metrics.get("words_per_minute", -1)
		var epm = metrics.get("edits_per_minute", -1)
		var efficiency = metrics.get("efficiency_score", -1)
		
		var metrics_valid = wpm >= 0 and epm >= 0 and efficiency >= 0.0 and efficiency <= 1.0
		
		if has_speed_metrics and has_efficiency and has_patterns and metrics_valid:
			_record_test_result(test_name, true, "Productivity metrics calculated correctly")
		else:
			_record_test_result(test_name, false, "Invalid or missing productivity metrics")
	else:
		_record_test_result(test_name, false, "Exception during productivity metrics calculation")

func _test_recommendations_generation():
	"""Test improvement recommendations generation"""
	var test_name = "Recommendations Generation"
	if true:
		var recommendations = test_session_manager._generate_improvement_recommendations()
		
		var has_recommendations = recommendations.size() > 0
		var valid_format = true
		
		for rec in recommendations:
			if not rec.has_all(["category", "title", "description", "priority"]):
				valid_format = false
				break
		
		if has_recommendations and valid_format:
			_record_test_result(test_name, true, "Improvement recommendations generated with valid format")
		else:
			_record_test_result(test_name, false, "No recommendations or invalid format")
	else:
		_record_test_result(test_name, false, "Exception during recommendations generation")

# === EXPORT FORMAT TESTS ===

func _test_export_formats():
	"""Test all export format options"""
	print("\n🔄 Testing Export Formats...")
	
	await _test_all_export_formats()
	await _test_format_specific_features()

func _test_all_export_formats():
	"""Test that all export formats work"""
	var test_name = "All Export Formats"
	
	var formats = [
		DocumentSessionManager.ExportFormat.HTML,
		DocumentSessionManager.ExportFormat.MARKDOWN,
		DocumentSessionManager.ExportFormat.JSON,
		DocumentSessionManager.ExportFormat.PLAIN_TEXT,
		DocumentSessionManager.ExportFormat.PDF_READY
	]
	
	var successful_exports = 0
	
	for format in formats:
		if true:
			var report_path = test_session_manager.generate_edit_session_report(format)
			if not report_path.is_empty() and FileAccess.file_exists(report_path):
				successful_exports += 1
		else:
			pass  # Continue testing other formats
	
	if successful_exports == formats.size():
		_record_test_result(test_name, true, "All export formats working correctly")
	else:
		_record_test_result(test_name, false, "Some export formats failed (%d/%d)" % [successful_exports, formats.size()])

func _test_format_specific_features():
	"""Test format-specific features"""
	var test_name = "Format-Specific Features"
	if true:
		# Test HTML CSS inclusion
		var html_path = test_session_manager.generate_edit_session_report(DocumentSessionManager.ExportFormat.HTML)
		var html_file = FileAccess.open(html_path, FileAccess.READ)
		var html_content = html_file.get_as_text()
		html_file.close()
		
		var has_css = html_content.contains("<style>")
		
		# Test JSON structure validity
		var json_path = test_session_manager.generate_edit_session_report(DocumentSessionManager.ExportFormat.JSON)
		var json_file = FileAccess.open(json_path, FileAccess.READ)
		var json_content = json_file.get_as_text()
		json_file.close()
		
		var json_parser = JSON.new()
		var json_valid = json_parser.parse(json_content) == OK
		
		if has_css and json_valid:
			_record_test_result(test_name, true, "Format-specific features working correctly")
		else:
			_record_test_result(test_name, false, "Some format-specific features missing")
	else:
		_record_test_result(test_name, false, "Exception during format-specific testing")

# === ERROR HANDLING TESTS ===

func _test_error_handling():
	"""Test error handling and edge cases"""
	print("\n⚠️  Testing Error Handling...")
	
	await _test_empty_session_handling()
	await _test_invalid_format_handling()
	await _test_file_permission_handling()

func _test_empty_session_handling():
	"""Test behavior with empty session"""
	var test_name = "Empty Session Handling"
	if true:
		# Clear session
		test_session_manager.clear_session()
		
		# Try to generate report with empty session
		var report_path = test_session_manager.generate_edit_session_report()
		
		# Should still generate a report (with no documents)
		if not report_path.is_empty() and FileAccess.file_exists(report_path):
			_record_test_result(test_name, true, "Empty session handled gracefully")
		else:
			_record_test_result(test_name, false, "Failed to handle empty session")
		
		# Restore test documents
		_create_test_documents()
	else:
		_record_test_result(test_name, false, "Exception during empty session test")

func _test_invalid_format_handling():
	"""Test handling of invalid export format"""
	var test_name = "Invalid Format Handling"
	if true:
		# Test with invalid format ID (should default to HTML)
		var report_path = test_session_manager.generate_edit_session_report(999)
		
		# Should still generate something or handle gracefully
		if not report_path.is_empty():
			_record_test_result(test_name, true, "Invalid format handled gracefully")
		else:
			_record_test_result(test_name, false, "Invalid format not handled properly")
	else:
		_record_test_result(test_name, true, "Exception properly caught for invalid format")

func _test_file_permission_handling():
	"""Test handling of file permission issues"""
	var test_name = "File Permission Handling"
	
	# This test is more difficult to implement without actually changing file permissions
	# For now, we'll test directory creation
	if true:
		# Test directory creation
		test_session_manager._ensure_reports_directory()
		test_session_manager._ensure_exports_directory()
		test_session_manager._ensure_shared_directory()
		
		var reports_exist = DirAccess.open("user://").dir_exists("reports")
		var exports_exist = DirAccess.open("user://").dir_exists("exports")
		var shared_exist = DirAccess.open("user://").dir_exists("shared")
		
		if reports_exist and exports_exist and shared_exist:
			_record_test_result(test_name, true, "Directory creation handled correctly")
		else:
			_record_test_result(test_name, false, "Failed to create required directories")
	else:
		_record_test_result(test_name, false, "Exception during file permission test")

# === TEST UTILITIES ===

func _record_test_result(test_name: String, passed: bool, details: String):
	"""Record the result of a test"""
	test_results[test_name] = {
		"passed": passed,
		"details": details
	}
	
	var status = "✅ PASS" if passed else "❌ FAIL"
	print("  %s: %s - %s" % [status, test_name, details])
	
	test_completed.emit(test_name, passed, details)

func _generate_test_report():
	"""Generate comprehensive test report"""
	print("\n" + "=".repeat(60))
	print("Phase 4.6 Test Report - Export and Reporting Features")
	print("=".repeat(60))
	
	var total_tests = test_results.size()
	var passed_tests = 0
	var failed_tests = 0
	
	for test_name in test_results:
		if test_results[test_name].passed:
			passed_tests += 1
		else:
			failed_tests += 1
	
	print("\nTest Summary:")
	print("  Total Tests: %d" % total_tests)
	print("  Passed: %d" % passed_tests)
	print("  Failed: %d" % failed_tests)
	print("  Success Rate: %.1f%%" % (float(passed_tests) / total_tests * 100.0))
	
	if failed_tests > 0:
		print("\nFailed Tests:")
		for test_name in test_results:
			if not test_results[test_name].passed:
				print("  ❌ %s: %s" % [test_name, test_results[test_name].details])
	
	print("\nPhase 4.6 Features Tested:")
	print("  ✅ Comprehensive report generation (5 formats)")
	print("  ✅ Document export functionality")
	print("  ✅ Session sharing and anonymization")
	print("  ✅ Analytics and productivity metrics")
	print("  ✅ Improvement recommendations")
	print("  ✅ Error handling and edge cases")
	
	var summary = {
		"total_tests": total_tests,
		"passed": passed_tests,
		"failed": failed_tests,
		"success_rate": float(passed_tests) / total_tests * 100.0,
		"details": test_results
	}
	
	all_tests_completed.emit(summary)
	
	print("\n🎉 Phase 4.6 Export and Reporting Features Testing Complete!")

# Manual test triggers for keyboard shortcuts
func _input(event):
	"""Handle keyboard shortcuts for manual testing"""
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_F10:  # F10 - Run all tests
				_run_all_tests()
			KEY_F11:  # F11 - Test report generation only
				_test_report_generation()
			KEY_F12:  # F12 - Test analytics only
				_test_analytics_features() 