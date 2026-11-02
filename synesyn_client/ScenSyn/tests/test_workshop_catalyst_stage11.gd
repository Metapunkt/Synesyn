extends SceneTree

## Stage 11: "My Sessions" resume-live feature.
## Covers the Session Record half of the reload path, the local
## *.provenance.json scanner, and the My Sessions button/dialog wiring in the
## Session Menu. The Thinking Map half of the reload path is covered
## separately in test_workshop_catalyst_stage11b.gd — it is kept out of this
## file because workshop_thinking_map_controller.gd's ThemeManager reference
## intermittently fails to compile under `--headless --script` (a known,
## pre-existing Godot CLI quirk, see 11_Workshop_Catalyst_Build_Staging.md),
## and mixing it into this file made the unrelated scanner/wiring assertions
## below unreliable too.

const RecordStoreScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_session_record_store.gd"
)
const RecordPanelControllerScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_session_record_panel_controller.gd"
)
const RecordPersistenceScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_summary_persistence_coordinator.gd"
)
const RecordPanelScene = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_session_record_panel.tscn"
)
const SessionScannerScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_session_scanner.gd"
)
const WorkspaceControllerScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_workspace_controller.gd"
)
const WorkspaceScene = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_catalyst_workspace_shell.tscn"
)

var _failures: Array[String] = []


class FakeHub:
	extends Node

	func create_artifact_inline_json(
		_artifact_type: String, _payload: Dictionary, _metadata: Dictionary = {}
	) -> Dictionary:
		return {"ok": true, "id": "art_stub"}


class FakeGameSession:
	extends Node
	var last_loaded_path: String = ""

	func _on_story_log_file_selected(path: String) -> void:
		last_loaded_path = path


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_reload_rehydrates_session_record()
	_test_session_scanner_filters_and_sorts()
	await _test_my_sessions_button_opens_dialog_not_unavailable()
	_finish()


func _test_reload_rehydrates_session_record() -> void:
	# Mirrors ControllerUtilsScript.reload_workshop_panels_from_state():
	# record_store.initialize() + panel.refresh(), never mount() again (that
	# would double-wire the panel's buttons).
	var hub_node := FakeHub.new()
	root.add_child(hub_node)
	var record_store: RefCounted = RecordStoreScript.new()
	record_store.initialize("sess_stage11")
	var record_panel_node: Control = RecordPanelScene.instantiate() as Control
	root.add_child(record_panel_node)
	var persistence_node := RecordPersistenceScript.new()
	persistence_node.configure(hub_node, record_store)
	root.add_child(persistence_node)
	var panel_controller: RefCounted = RecordPanelControllerScript.new()
	var mounted_ok: bool = panel_controller.mount(record_panel_node, record_store, persistence_node)
	_expect(mounted_ok, "Session Record panel did not mount for reload test")
	if mounted_ok:
		record_store.propose("decisions", "Initial decision before resume")
		var proposals_before: Array[Dictionary] = record_store.get_proposals()
		var decision_id: String = ""
		if not proposals_before.is_empty():
			decision_id = String(proposals_before[0].get("id", ""))
		if not decision_id.is_empty():
			record_store.accept(decision_id, "Facilitator")
		panel_controller.refresh()
		var decisions_items_node: VBoxContainer = record_panel_node.get_node_or_null(
			"%DecisionsItems"
		) as VBoxContainer
		var commit_button_node: Button = record_panel_node.get_node_or_null(
			"%CommitSummaryButton"
		) as Button
		_expect(
			decisions_items_node != null and decisions_items_node.get_child_count() == 1,
			"Session Record did not render the pre-resume decision"
		)
		_expect(
			commit_button_node != null and commit_button_node.pressed.get_connections().size() == 1,
			"Session Record commit button should have exactly one connection after mount"
		)

		# Simulate the resume: overwrite reviewed state with a distinct entry
		# so we can tell reload replaced it rather than appending to it.
		# Round-trip through JSON.stringify/parse so proposals/proposal_decisions
		# become untyped Array (as they do when loaded from .workshop.json) —
		# direct assignment of those into Array[Dictionary] is the live crash.
		var resumed_record_state: Dictionary = record_store.get_state()
		resumed_record_state["reviewed"] = {
			"decisions": [{
				"id": "wsi_resumed_decision",
				"text": "Resumed decision after reload",
				"provenance_refs": [],
				"provenance": {"authorship_kind": "user_authored", "review_status": "reviewed"},
				"reviewed_by": "Facilitator",
				"facilitator_edited": false,
			}],
			"risks": [], "open_questions": [],
		}
		var json_roundtrip_any: Variant = JSON.parse_string(JSON.stringify(resumed_record_state))
		_expect(
			typeof(json_roundtrip_any) == TYPE_DICTIONARY,
			"JSON round-trip of Session Record state failed"
		)
		if typeof(json_roundtrip_any) == TYPE_DICTIONARY:
			record_store.initialize("sess_stage11", json_roundtrip_any)
		panel_controller.refresh()
		_expect(
			decisions_items_node.get_child_count() == 1,
			"Session Record reload did not re-render exactly one reviewed decision"
		)
		_expect(
			commit_button_node.pressed.get_connections().size() == 1,
			"Session Record reload duplicated a button signal connection"
		)
		var proposals_after: Array[Dictionary] = record_store.get_proposals()
		_expect(
			proposals_after.size() >= 1,
			"Session Record reload dropped proposals after JSON-typed array coerce"
		)

	record_panel_node.queue_free()
	hub_node.queue_free()
	persistence_node.queue_free()
	await process_frame


func _test_session_scanner_filters_and_sorts() -> void:
	var scratch_dir: String = ProjectSettings.globalize_path(
		"user://wc_stage11_scanner_test/"
	)
	DirAccess.make_dir_recursive_absolute(scratch_dir)

	_write_scanner_fixture(
		scratch_dir, "sess_a", "workshop_catalyst", "2026-08-01 10:00:00", true, true
	)
	_write_scanner_fixture(
		scratch_dir, "sess_b", "", "2026-08-02 10:00:00", true, true
	)
	_write_scanner_fixture(
		scratch_dir, "sess_c", "story_catalyst", "2026-08-03 10:00:00", true, true
	)
	_write_scanner_fixture(
		scratch_dir, "sess_d", "workshop_catalyst", "2026-08-04 10:00:00", false, true
	)

	var results: Array[Dictionary] = SessionScannerScript.scan_workshop_catalyst_sessions(
		scratch_dir
	)
	_expect(
		results.size() == 2,
		"Session scanner should keep exactly the 2 valid Workshop Catalyst sessions, got %d" % results.size()
	)
	if results.size() == 2:
		_expect(
			String(results[0].get("file_stem", "")) == "sess_b",
			"Session scanner did not sort most-recent-first"
		)
		_expect(
			String(results[1].get("file_stem", "")) == "sess_a",
			"Session scanner did not include the legacy (no session_type) sidecar session"
		)
		_expect(
			int(results[1].get("decisions_count", 0)) == 1,
			"Session scanner did not summarize decisions from the .workshop.json sidecar"
		)

	_cleanup_dir(scratch_dir)


func _write_scanner_fixture(
	dir_path: String,
	file_stem: String,
	session_type: String,
	saved_at: String,
	include_json: bool,
	include_workshop_sidecar: bool
) -> void:
	var provenance: Dictionary = {
		"schema": "synesyn_provenance_v1",
		"session_id": file_stem,
		"file_stem": file_stem,
		"scenario": "Scenario for " + file_stem,
		"saved_at": saved_at,
		"entry_count": 2,
	}
	if not session_type.is_empty():
		provenance["session_type"] = session_type
	_write_json(dir_path + file_stem + ".provenance.json", provenance)
	if include_json:
		_write_json(dir_path + file_stem + ".json", [])
	if include_workshop_sidecar:
		_write_json(dir_path + file_stem + ".workshop.json", {
			"buckets": {"decisions": ["Decision for " + file_stem], "open_questions": []},
			"stage_history": [{"stage_name": "Kickoff"}],
		})


func _write_json(path: String, data: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))
		file.close()


func _cleanup_dir(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if not dir:
		return
	dir.list_dir_begin()
	var entry_name := dir.get_next()
	while entry_name != "":
		if not dir.current_is_dir():
			dir.remove(entry_name)
		entry_name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(dir_path)


func _test_my_sessions_button_opens_dialog_not_unavailable() -> void:
	var shell_node: Control = WorkspaceScene.instantiate() as Control
	var conversation_region_node := TabContainer.new()
	var session_record_region_node := VBoxContainer.new()
	var record_button_node := Button.new()
	var story_log_system_node := Control.new()
	story_log_system_node.name = "StoryLogSystem"
	root.add_child(shell_node)
	root.add_child(conversation_region_node)
	conversation_region_node.add_child(session_record_region_node)
	conversation_region_node.add_child(story_log_system_node)
	root.add_child(record_button_node)
	var workspace_controller: RefCounted = WorkspaceControllerScript.new()
	_expect(
		workspace_controller.mount(
			shell_node, conversation_region_node, session_record_region_node, record_button_node
		),
		"Workspace failed to mount for My Sessions test"
	)
	await process_frame

	var target_controller: RefCounted = workspace_controller.get_target_surfaces_controller()
	var my_sessions_button_node: Button = (
		workspace_controller.get_control("MySessionsButton") as Button
	)
	var my_sessions_dialog_node: Control = shell_node.find_child(
		"MySessionsDialog", true, false
	) as Control
	var nav_unavailable_dialog_node: AcceptDialog = shell_node.find_child(
		"NavigationUnavailableDialog", true, false
	) as AcceptDialog
	_expect(
		my_sessions_button_node != null and my_sessions_dialog_node != null,
		"My Sessions button or dialog missing from the shell scene"
	)
	if my_sessions_button_node and my_sessions_dialog_node:
		my_sessions_button_node.pressed.emit()
		await process_frame
		_expect(
			my_sessions_dialog_node.visible,
			"My Sessions button did not open the My Sessions dialog"
		)
		_expect(
			nav_unavailable_dialog_node == null or not nav_unavailable_dialog_node.visible,
			"My Sessions incorrectly still routes through the generic unavailable dialog"
		)
		var close_button_node: Button = shell_node.find_child(
			"MySessionsCloseButton", true, false
		) as Button
		if close_button_node:
			close_button_node.pressed.emit()
			await process_frame
			_expect(
				not my_sessions_dialog_node.visible,
				"My Sessions Close button did not hide the dialog"
			)

	if target_controller:
		var fake_game_session := FakeGameSession.new()
		fake_game_session.add_to_group("game_session")
		root.add_child(fake_game_session)
		target_controller.call(
			"_on_session_selected", {"json_path": "C:/fake/dir/fake_session.json"}
		)
		await process_frame
		_expect(
			fake_game_session.last_loaded_path == "C:/fake/dir/fake_session.json",
			"Selecting a My Sessions entry did not dispatch to the game_session node"
		)
		fake_game_session.queue_free()

	shell_node.queue_free()
	conversation_region_node.queue_free()
	record_button_node.queue_free()
	await process_frame


func _expect(condition: bool, failure_message: String) -> void:
	if condition:
		return
	_failures.append(failure_message)
	push_error(failure_message)


func _finish() -> void:
	if _failures.is_empty():
		print("Workshop Catalyst Stage 11 tests: all passed")
		quit(0)
	else:
		push_error("Workshop Catalyst Stage 11: %d failure(s)" % _failures.size())
		quit(1)
