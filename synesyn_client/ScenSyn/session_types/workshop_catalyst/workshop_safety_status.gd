extends RefCounted
class_name WorkshopSafetyStatus

## Presentation helper for the Workshop footer safety strip. Idle/healthy
## statuses stay hidden so the bar collapses to End & Save by default.


static func set_attention_label(
	label_node: Label,
	status_text: String,
	should_show: bool
) -> void:
	if not label_node:
		return
	if should_show and not status_text.strip_edges().is_empty():
		label_node.text = status_text.strip_edges()
		label_node.visible = true
	else:
		label_node.visible = false


static func refresh_idle_state(
	find_control: Callable,
	record_button_node: Button,
	voice_service_node: Node
) -> void:
	var cfg: Dictionary = RuntimeConfig.load_config()
	var voice_any: Variant = cfg.get("voice", {})
	var voice_cfg: Dictionary = voice_any if typeof(voice_any) == TYPE_DICTIONARY else {}
	var saves_recordings: bool = voice_cfg.get("save_recordings", false) == true
	var mic_available: bool = record_button_node != null and not record_button_node.disabled
	set_attention_label(
		find_control.call("MicrophoneStatusLabel") as Label,
		"Mic unavailable",
		not mic_available
	)
	set_attention_label(
		find_control.call("ConsentStatusLabel") as Label,
		"Saving audio",
		saves_recordings
	)
	var voice_ready: bool = (
		voice_service_node != null
		and voice_service_node.get("is_service_running") == true
	)
	set_attention_label(
		find_control.call("ConnectionErrorLabel") as Label,
		"Voice unavailable, check Settings",
		voice_service_node != null and not voice_ready
	)
	set_attention_label(find_control.call("ListeningStatusLabel") as Label, "", false)
	set_attention_label(find_control.call("TranscriptionErrorLabel") as Label, "", false)
	set_attention_label(find_control.call("UncommittedWarningLabel") as Label, "", false)


static func set_end_save_status(
	find_control: Callable,
	status_text: String,
	has_uncommitted_changes: bool
) -> void:
	var trimmed_status: String = status_text.strip_edges()
	set_attention_label(
		find_control.call("ConnectionErrorLabel") as Label,
		trimmed_status,
		not trimmed_status.is_empty()
	)
	set_attention_label(
		find_control.call("UncommittedWarningLabel") as Label,
		"Uncommitted changes" if has_uncommitted_changes else "",
		has_uncommitted_changes
	)


## Keeps the footer chrome available for pulse + alerts even when the
## facilitator presence row is toggled off by a workspace preset.
static func ensure_footer_visible(find_control: Callable) -> void:
	var safety_bar_node: Control = find_control.call("SafetyBar") as Control
	if safety_bar_node:
		safety_bar_node.visible = true
	var pulse_label_node: Control = find_control.call("SessionRecordPulseLabel") as Control
	if pulse_label_node:
		pulse_label_node.visible = true


static func set_session_record_pulse(
	shell_root_node: Control,
	find_control: Callable,
	pulse_text: String
) -> void:
	var trimmed: String = pulse_text.strip_edges()
	if trimmed.is_empty():
		return
	var label_node: Label = null
	if shell_root_node:
		label_node = shell_root_node.get_node_or_null("%SessionRecordPulseLabel") as Label
	if not label_node:
		label_node = find_control.call("SessionRecordPulseLabel") as Label
	if not label_node:
		push_warning("WorkshopSafetyStatus: SessionRecordPulseLabel is missing.")
		return
	label_node.visible = true
	label_node.text = trimmed
	ensure_footer_visible(find_control)
