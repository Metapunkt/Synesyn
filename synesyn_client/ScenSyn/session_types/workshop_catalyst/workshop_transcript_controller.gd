extends Node
class_name WorkshopTranscriptController

## Owns Workshop Catalyst's STT proposal, immutable correction lineage, and
## best-effort Hub persistence. Typed input remains owned by GameSession.

const ARTIFACT_TYPE := "json.workshop_transcript_segment"
const FEATURE_FLAG_KEY := "workshop_transcript_trust_enabled"

var _game_session_node: Node
var _hub_client: Object
var _shell_root_node: Control
var _workspace_controller: RefCounted
var _preview_editor_node: TextEdit
var _preview_panel_node: Control
var _preview_status_node: Label
var _send_preview_button_node: Button
var _cancel_preview_button_node: Button
var _correction_panel_node: Control
var _original_text_node: Label
var _correction_editor_node: TextEdit
var _correction_reason_node: LineEdit
var _correction_status_node: Label
var _save_correction_button_node: Button
var _resend_correction_button_node: Button
var _segments: Dictionary = {}
var _active_segment_id: String = ""
var _segment_counter: int = 0
var _pending_original_text: String = ""


static func is_feature_enabled() -> bool:
	var cfg: Dictionary = RuntimeConfig.load_config()
	var apps_any: Variant = cfg.get("apps", {})
	var apps: Dictionary = apps_any if typeof(apps_any) == TYPE_DICTIONARY else {}
	var scensyn_any: Variant = apps.get("scensyn", {})
	var scensyn_cfg: Dictionary = (
		scensyn_any if typeof(scensyn_any) == TYPE_DICTIONARY else {}
	)
	return scensyn_cfg.get(FEATURE_FLAG_KEY, true) == true


func mount(
	shell_root_node: Control,
	game_session_node: Node,
	hub_client: Object,
	workspace_controller: RefCounted
) -> bool:
	_shell_root_node = shell_root_node
	_game_session_node = game_session_node
	_hub_client = hub_client
	_workspace_controller = workspace_controller
	_preview_panel_node = shell_root_node.find_child("TranscriptPreviewPanel", true, false) as Control
	_preview_editor_node = shell_root_node.find_child("TranscriptPreviewEditor", true, false) as TextEdit
	_preview_status_node = shell_root_node.find_child("TranscriptPreviewStatus", true, false) as Label
	_send_preview_button_node = shell_root_node.find_child("SendTranscriptButton", true, false) as Button
	_cancel_preview_button_node = shell_root_node.find_child("CancelTranscriptButton", true, false) as Button
	_correction_panel_node = shell_root_node.find_child("TranscriptCorrectionPanel", true, false) as Control
	_original_text_node = shell_root_node.find_child("TranscriptOriginalText", true, false) as Label
	_correction_editor_node = shell_root_node.find_child("TranscriptCorrectionEditor", true, false) as TextEdit
	_correction_reason_node = shell_root_node.find_child("TranscriptCorrectionReason", true, false) as LineEdit
	_correction_status_node = shell_root_node.find_child("TranscriptCorrectionStatus", true, false) as Label
	_save_correction_button_node = shell_root_node.find_child("SaveTranscriptCorrectionButton", true, false) as Button
	_resend_correction_button_node = shell_root_node.find_child("ResendTranscriptCorrectionButton", true, false) as Button
	if (
		not _all_controls_available()
		or not _workspace_controller
		or not _workspace_controller.has_method("set_conversation_overlay")
	):
		return false
	_send_preview_button_node.pressed.connect(_on_send_preview_pressed)
	_cancel_preview_button_node.pressed.connect(cancel_preview)
	_save_correction_button_node.pressed.connect(_on_save_correction_pressed)
	_resend_correction_button_node.pressed.connect(_on_resend_correction_pressed)
	_send_preview_button_node.visible = true
	_cancel_preview_button_node.visible = true
	_save_correction_button_node.visible = true
	_resend_correction_button_node.visible = true
	cancel_preview()
	_workspace_controller.set_conversation_overlay(
		"transcript_correction",
		false
	)
	return true


func handle_transcription_completed(transcribed_text: String, error_text: String) -> bool:
	if not _preview_editor_node:
		return false
	if not error_text.strip_edges().is_empty():
		_workspace_controller.set_conversation_overlay(
			"transcript_preview",
			true
		)
		_preview_editor_node.text = ""
		_preview_status_node.text = "Transcription failed: " + error_text.strip_edges()
		_send_preview_button_node.disabled = true
		return true
	var cleaned_text: String = transcribed_text.strip_edges()
	if cleaned_text.is_empty():
		_workspace_controller.set_conversation_overlay(
			"transcript_preview",
			true
		)
		_preview_editor_node.text = ""
		_preview_status_node.text = "No speech detected. Cancel and record again."
		_send_preview_button_node.disabled = true
		return true
	_workspace_controller.set_conversation_overlay(
		"transcript_preview",
		true
	)
	_pending_original_text = cleaned_text
	_preview_editor_node.text = cleaned_text
	_preview_editor_node.grab_focus()
	_preview_status_node.text = "Review and edit before explicit Send."
	_send_preview_button_node.disabled = false
	return true


func cancel_preview() -> void:
	if not _preview_panel_node:
		return
	_preview_editor_node.text = ""
	_pending_original_text = ""
	_workspace_controller.set_conversation_overlay(
		"transcript_preview",
		false
	)
	_preview_status_node.text = "No transcript awaiting review."
	_send_preview_button_node.disabled = true


func send_preview() -> bool:
	var reviewed_text: String = _preview_editor_node.text.strip_edges()
	if reviewed_text.is_empty() or not _game_session_node:
		return false
	var original_stt_text: String = _pending_original_text.strip_edges()
	if original_stt_text.is_empty():
		original_stt_text = reviewed_text
	_segment_counter += 1
	var segment_id: String = "seg_%s_%04d" % [
		str(int(Time.get_unix_time_from_system())),
		_segment_counter,
	]
	var version_id: String = segment_id + "_v1"
	var timestamp_text: String = Time.get_datetime_string_from_system(true)
	var payload: Dictionary = {
		"schema_version": 1,
		"version_id": version_id,
		"session_id": _session_id(),
		"segment_id": segment_id,
		"origin": "user",
		"capture_started_at": timestamp_text,
		"capture_completed_at": timestamp_text,
		"created_at": timestamp_text,
		"original_text": original_stt_text,
		"submitted_text": reviewed_text,
		"provider": _provider_metadata(),
		"consent": _consent_classification(),
		"retention": _retention_classification(),
		"previous_version_id": "",
		"corrected_text": "",
		"correction_reason": "",
		"source_audio_artifact_id": "",
	}
	_segments[segment_id] = {
		"original": payload.duplicate(true),
		"latest": payload.duplicate(true),
		"original_artifact_id": "",
		"latest_artifact_id": "",
	}
	_active_segment_id = segment_id
	_show_correction(payload, "Original transcript sent; Hub save pending.")
	_submit_text_as_turn(reviewed_text)
	cancel_preview()
	call_deferred("_persist_version", segment_id, payload, false)
	return true


func save_correction() -> bool:
	if _active_segment_id.is_empty() or not _segments.has(_active_segment_id):
		return false
	var corrected_text: String = _correction_editor_node.text.strip_edges()
	var reason_text: String = _correction_reason_node.text.strip_edges()
	var segment_state: Dictionary = _segments[_active_segment_id]
	var previous_payload: Dictionary = segment_state.get("latest", {})
	var effective_text: String = String(previous_payload.get("corrected_text", "")).strip_edges()
	if effective_text.is_empty():
		effective_text = String(
			previous_payload.get("submitted_text", previous_payload.get("original_text", ""))
		).strip_edges()
	if corrected_text.is_empty() or corrected_text == effective_text or reason_text.is_empty():
		_correction_status_node.text = "Correction needs changed text and a reason."
		return false
	var previous_version_id: String = String(previous_payload.get("version_id", "")).strip_edges()
	var version_number: int = _version_number(previous_version_id) + 1
	var corrected_payload: Dictionary = previous_payload.duplicate(true)
	corrected_payload["version_id"] = "%s_v%d" % [_active_segment_id, version_number]
	corrected_payload["created_at"] = Time.get_datetime_string_from_system(true)
	corrected_payload["corrected_at"] = corrected_payload["created_at"]
	corrected_payload["corrected_text"] = corrected_text
	corrected_payload["correction_reason"] = reason_text
	corrected_payload["previous_version_id"] = previous_version_id
	segment_state["latest"] = corrected_payload.duplicate(true)
	_segments[_active_segment_id] = segment_state
	_correction_status_node.text = "Correction saved to record only; no AI turn was triggered."
	_resend_correction_button_node.disabled = false
	call_deferred("_persist_version", _active_segment_id, corrected_payload, true)
	return true


func resend_correction() -> bool:
	if _active_segment_id.is_empty() or not _segments.has(_active_segment_id):
		return false
	var segment_state: Dictionary = _segments[_active_segment_id]
	var latest_payload: Dictionary = segment_state.get("latest", {})
	var corrected_text: String = String(latest_payload.get("corrected_text", "")).strip_edges()
	if corrected_text.is_empty():
		return false
	_submit_text_as_turn(corrected_text)
	_correction_status_node.text = "Corrected text explicitly resent as a new AI turn."
	return true


func get_segment(segment_id: String) -> Dictionary:
	var segment_any: Variant = _segments.get(segment_id, {})
	return segment_any.duplicate(true) if typeof(segment_any) == TYPE_DICTIONARY else {}


func get_active_segment_id() -> String:
	return _active_segment_id


func should_speak_sender(sender_id: String) -> bool:
	return sender_id == "Session Record"


func _on_send_preview_pressed() -> void:
	send_preview()


func _on_save_correction_pressed() -> void:
	save_correction()


func _on_resend_correction_pressed() -> void:
	resend_correction()


func _submit_text_as_turn(text_value: String) -> void:
	var input_field_node: LineEdit = _game_session_node.get("input_field") as LineEdit
	if not input_field_node:
		return
	input_field_node.text = text_value
	_game_session_node.call("_on_send_pressed")


func _show_correction(payload: Dictionary, status_text: String) -> void:
	_workspace_controller.set_conversation_overlay(
		"transcript_correction",
		true
	)
	var original_text: String = String(payload.get("original_text", ""))
	var submitted_text: String = String(payload.get("submitted_text", original_text))
	_original_text_node.text = "Original STT: %s\nConfirmed text: %s" % [
		original_text,
		submitted_text,
	]
	_correction_editor_node.text = submitted_text
	_correction_reason_node.text = ""
	_correction_status_node.text = status_text
	_resend_correction_button_node.disabled = true


func _persist_version(segment_id: String, payload: Dictionary, is_correction: bool) -> void:
	if not is_instance_valid(_hub_client) or not _hub_client.has_method("create_artifact_inline_json"):
		_set_persistence_status("Hub unavailable — retained locally for this session.", true)
		return
	var metadata: Dictionary = {
		"session_id": payload.get("session_id", ""),
		"segment_id": segment_id,
		"version_id": payload.get("version_id", ""),
		"previous_version_id": payload.get("previous_version_id", ""),
		"provenance": {
			"produced_by": "scensyn.workshop_transcript@1",
			"inputs": [],
			"timestamp": payload.get("created_at", ""),
		},
	}
	var result: Dictionary = await _hub_client.call(
		"create_artifact_inline_json",
		ARTIFACT_TYPE,
		payload,
		metadata
	)
	if not bool(result.get("ok", false)):
		_set_persistence_status("Hub save failed — local conversation continued.", true)
		return
	var artifact_id: String = String(result.get("id", result.get("artifact_id", "")))
	var segment_state: Dictionary = _segments.get(segment_id, {})
	if is_correction:
		segment_state["latest_artifact_id"] = artifact_id
	else:
		segment_state["original_artifact_id"] = artifact_id
		segment_state["latest_artifact_id"] = artifact_id
	_segments[segment_id] = segment_state
	_set_persistence_status(
		"Correction saved as new Hub version." if is_correction else "Original transcript saved to Hub.",
		false
	)


func _set_persistence_status(status_text: String, is_degraded: bool) -> void:
	if _correction_status_node:
		_correction_status_node.text = status_text
	if not _shell_root_node:
		return
	var connection_label_node: Label = _shell_root_node.find_child(
		"ConnectionErrorLabel", true, false
	) as Label
	var uncommitted_label_node: Label = _shell_root_node.find_child(
		"UncommittedWarningLabel", true, false
	) as Label
	if connection_label_node:
		if is_degraded:
			connection_label_node.text = "Hub persistence degraded"
			connection_label_node.visible = true
		elif not status_text.strip_edges().is_empty():
			connection_label_node.text = "Transcript saved"
			connection_label_node.visible = true
		else:
			connection_label_node.visible = false
	if uncommitted_label_node:
		if is_degraded:
			uncommitted_label_node.text = "Uncommitted changes: transcript retained locally"
			uncommitted_label_node.visible = true
		else:
			uncommitted_label_node.visible = false


func _session_id() -> String:
	if _game_session_node:
		return String(_game_session_node.get("_session_id")).strip_edges()
	return ""


func _provider_metadata() -> Dictionary:
	var cfg: Dictionary = RuntimeConfig.load_config()
	var voice_any: Variant = cfg.get("voice", {})
	var voice_cfg: Dictionary = voice_any if typeof(voice_any) == TYPE_DICTIONARY else {}
	return {
		"provider_id": String(voice_cfg.get("provider_mode", "unknown")),
		"model_id": String(voice_cfg.get("stt_model", "provider-reported")),
		"transcript_artifact_id": "",
	}


func _consent_classification() -> Dictionary:
	return {
		"voice_transcription": true,
		"save_recordings": _save_recordings_enabled(),
	}


func _retention_classification() -> Dictionary:
	return {
		"classification": "session_transcript",
		"transcript_retained": true,
		"raw_audio_retained": _save_recordings_enabled(),
	}


func _save_recordings_enabled() -> bool:
	return _game_session_node != null and _game_session_node.get("_save_recordings_enabled") == true


func _version_number(version_id: String) -> int:
	var marker_index: int = version_id.rfind("_v")
	if marker_index < 0:
		return 1
	return maxi(1, int(version_id.substr(marker_index + 2)))


func _all_controls_available() -> bool:
	return (
		_preview_panel_node != null
		and _preview_editor_node != null
		and _preview_status_node != null
		and _send_preview_button_node != null
		and _cancel_preview_button_node != null
		and _correction_panel_node != null
		and _original_text_node != null
		and _correction_editor_node != null
		and _correction_reason_node != null
		and _correction_status_node != null
		and _save_correction_button_node != null
		and _resend_correction_button_node != null
	)
