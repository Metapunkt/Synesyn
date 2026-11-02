class_name StoryStageVoice
extends Node

## Silent base. An application adapter talks to a speech engine.

signal speech_started(speaker: String)
signal speech_finished(speaker: String)
signal speech_paused(speaker: String)
signal speech_resumed(speaker: String)
signal ready_to_speak
signal synthesis_completed(speaker: String, duration: float)
signal playback_finished(speaker: String)
signal transcription_completed(text: String, error: String)

var _stage: Node
var _skip_welcome := false
var _speaker := ""


func attach(stage: Node) -> void:
	_stage = stage


func is_present() -> bool:
	return false


func get_skip_welcome() -> bool:
	return _skip_welcome


func set_skip_welcome(skip: bool) -> void:
	_skip_welcome = skip


func refresh_roster(_scenario: Dictionary) -> void:
	pass


func enable_character(_speaker: String) -> void:
	pass


func should_speak(_voice_name: String, _text: String) -> bool:
	return true


func speak(_voice_name: String, _text: String, _emotion: String = "neutral") -> bool:
	return false


func speaking_character() -> String:
	return _speaker


func is_busy() -> bool:
	return false


func pause() -> void:
	pass


func resume() -> void:
	pass


func stop_all() -> void:
	_speaker = ""


func cancel_synthesis() -> void:
	pass


func clear_synthesis() -> void:
	pass


func clear_activity() -> void:
	_speaker = ""


func stop_welcome_narration() -> void:
	pass


func recover_stuck_speaker() -> String:
	var who := _speaker
	_speaker = ""
	return who


func get_lipsync_frames(_voice_name: String, _speaker: String) -> Array:
	return []


func health_lines() -> Array[String]:
	var lines: Array[String] = []
	return lines


func set_save_recordings(_enabled: bool) -> void:
	pass


func create_recorder() -> Node:
	return null


func transcribe(_audio_path: String) -> bool:
	return false


func playback_position() -> float:
	return -1.0
