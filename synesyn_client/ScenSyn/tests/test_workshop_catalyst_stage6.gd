extends SceneTree

const TranscriptControllerScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_transcript_controller.gd"
)
const WorkspaceScene = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_catalyst_workspace_shell.tscn"
)

var _failures: Array[String] = []


class FakeGameSession:
	extends Node
	var input_field: LineEdit
	var _session_id: String = "sess_stage6"
	var _save_recordings_enabled: bool = false
	var sent_texts: Array[String] = []

	func _init() -> void:
		input_field = LineEdit.new()
		add_child(input_field)

	func _on_send_pressed() -> void:
		var submitted_text: String = input_field.text.strip_edges()
		if submitted_text.is_empty():
			return
		sent_texts.append(submitted_text)
		input_field.text = ""


class FakeHub:
	extends Node
	var artifacts: Array[Dictionary] = []
	var should_succeed: bool = true

	func create_artifact_inline_json(
		artifact_type: String,
		payload: Dictionary,
		metadata: Dictionary = {}
	) -> Dictionary:
		if not should_succeed:
			return {"ok": false, "error": "hub_offline"}
		artifacts.append({
			"artifact_type": artifact_type,
			"payload": payload.duplicate(true),
			"metadata": metadata.duplicate(true),
		})
		return {"ok": true, "id": "art_%d" % artifacts.size()}


class FakeWorkspaceController:
	extends RefCounted
	var shell_node: Control

	func _init(workshop_shell_node: Control) -> void:
		shell_node = workshop_shell_node

	func set_conversation_overlay(
		overlay_id: String,
		is_visible: bool
	) -> bool:
		var control_id: String = (
			"TranscriptPreviewPanel"
			if overlay_id == "transcript_preview"
			else "TranscriptCorrectionPanel"
		)
		var overlay_node: Control = shell_node.find_child(
			control_id, true, false
		) as Control
		if not overlay_node:
			return false
		overlay_node.visible = is_visible
		return true


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_preview_send_cancel_and_typed_nonregression()
	await _test_immutable_correction_and_degraded_hub()
	_test_single_spoken_voice_policy()
	_finish()


func _test_preview_send_cancel_and_typed_nonregression() -> void:
	var fixture: Dictionary = _build_fixture()
	var transcript_controller: Node = fixture["controller"]
	var game_session_node: FakeGameSession = fixture["game_session"]
	var hub_node: FakeHub = fixture["hub"]
	_expect(
		transcript_controller.handle_transcription_completed("Draft wording", ""),
		"Workshop transcription was not consumed by preview"
	)
	var preview_editor_node: TextEdit = fixture["shell"].find_child(
		"TranscriptPreviewEditor", true, false
	) as TextEdit
	preview_editor_node.text = "Reviewed wording"
	_expect(transcript_controller.send_preview(), "Reviewed transcript did not send")
	_expect(
		game_session_node.sent_texts == ["Reviewed wording"],
		"Preview edit was not the text submitted"
	)
	await process_frame
	await process_frame
	_expect(hub_node.artifacts.size() == 1, "Original transcript was not persisted")
	var persisted_original: Dictionary = hub_node.artifacts[0].get("payload", {})
	_expect(
		persisted_original.get("original_text") == "Draft wording"
		and persisted_original.get("submitted_text") == "Reviewed wording",
		"Pre-send edit overwrote the provider's original STT text"
	)
	transcript_controller.handle_transcription_completed("Discard me", "")
	transcript_controller.cancel_preview()
	_expect(
		game_session_node.sent_texts.size() == 1,
		"Cancel/re-record unexpectedly submitted a turn"
	)
	game_session_node.input_field.text = "Typed input remains direct"
	game_session_node._on_send_pressed()
	_expect(
		game_session_node.sent_texts.back() == "Typed input remains direct",
		"Typed input behavior regressed"
	)
	await _free_fixture(fixture)


func _test_immutable_correction_and_degraded_hub() -> void:
	var fixture: Dictionary = _build_fixture()
	var transcript_controller: Node = fixture["controller"]
	var game_session_node: FakeGameSession = fixture["game_session"]
	var hub_node: FakeHub = fixture["hub"]
	transcript_controller.handle_transcription_completed("The original statement", "")
	_expect(transcript_controller.send_preview(), "Original STT did not send")
	await process_frame
	var segment_id: String = transcript_controller.get_active_segment_id()
	var correction_editor_node: TextEdit = fixture["shell"].find_child(
		"TranscriptCorrectionEditor", true, false
	) as TextEdit
	var reason_node: LineEdit = fixture["shell"].find_child(
		"TranscriptCorrectionReason", true, false
	) as LineEdit
	correction_editor_node.text = "The corrected statement"
	reason_node.text = "Speaker clarification"
	var turns_before: int = game_session_node.sent_texts.size()
	_expect(transcript_controller.save_correction(), "Correction did not save")
	_expect(
		game_session_node.sent_texts.size() == turns_before,
		"Correction silently caused a second model turn"
	)
	await process_frame
	await process_frame
	var segment_state: Dictionary = transcript_controller.get_segment(segment_id)
	var original_payload: Dictionary = segment_state.get("original", {})
	var corrected_payload: Dictionary = segment_state.get("latest", {})
	_expect(
		original_payload.get("original_text") == "The original statement",
		"Original STT text was mutated"
	)
	_expect(
		corrected_payload.get("original_text") == "The original statement"
		and corrected_payload.get("corrected_text") == "The corrected statement",
		"Correction did not preserve original and corrected text"
	)
	_expect(
		corrected_payload.get("previous_version_id") == original_payload.get("version_id"),
		"Correction lineage does not reference the original version"
	)
	_expect(hub_node.artifacts.size() == 2, "Original/correction artifact round-trip incomplete")
	hub_node.should_succeed = false
	correction_editor_node.text = "A second corrected statement"
	reason_node.text = "Further clarification"
	_expect(transcript_controller.save_correction(), "Local correction failed while Hub was down")
	await process_frame
	var degraded_label_node: Label = fixture["shell"].find_child(
		"UncommittedWarningLabel", true, false
	) as Label
	_expect(
		degraded_label_node.text.contains("retained locally"),
		"Hub failure was not shown as truthful degraded state"
	)
	await _free_fixture(fixture)


func _test_single_spoken_voice_policy() -> void:
	var transcript_controller: Node = TranscriptControllerScript.new()
	_expect(
		transcript_controller.should_speak_sender("Session Record"),
		"Session Record was not selected as Workshop's spoken voice"
	)
	for silent_sender: String in [
		"Risk & Feasibility Analyst",
		"Options & Innovation Analyst",
		"Facilitator",
		"Narrator",
	]:
		_expect(
			not transcript_controller.should_speak_sender(silent_sender),
			"Hidden/non-record sender was allowed to speak: " + silent_sender
		)
	var flow_source: String = FileAccess.get_file_as_string(
		"res://ScenSyn/scripts/core/game_session_ai_flow_utils.gd"
	)
	_expect(
		flow_source.contains("should_speak_workshop_message"),
		"Story-log TTS does not enforce the Workshop voice policy"
	)
	transcript_controller.free()


func _build_fixture() -> Dictionary:
	var shell_node: Control = WorkspaceScene.instantiate() as Control
	var game_session_node := FakeGameSession.new()
	var hub_node := FakeHub.new()
	var transcript_controller: Node = TranscriptControllerScript.new()
	var workspace_controller: RefCounted = FakeWorkspaceController.new(
		shell_node
	)
	root.add_child(shell_node)
	root.add_child(game_session_node)
	root.add_child(hub_node)
	root.add_child(transcript_controller)
	_expect(
		transcript_controller.mount(
			shell_node,
			game_session_node,
			hub_node,
			workspace_controller
		),
		"Transcript controller failed to mount scene-authored controls"
	)
	return {
		"shell": shell_node,
		"game_session": game_session_node,
		"hub": hub_node,
		"controller": transcript_controller,
	}


func _free_fixture(fixture: Dictionary) -> void:
	for key: String in ["controller", "hub", "game_session", "shell"]:
		var node_value: Node = fixture[key] as Node
		node_value.queue_free()
	await process_frame


func _expect(condition: bool, failure_message: String) -> void:
	if not condition:
		_failures.append(failure_message)


func _finish() -> void:
	if _failures.is_empty():
		print("Workshop Catalyst Stage 6 tests: all passed")
		quit(0)
		return
	for failure_message: String in _failures:
		push_error(failure_message)
	quit(1)
