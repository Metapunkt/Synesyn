class_name StoryStageImagery
extends Node

## Null imagery port. The host generates images; the addon only shows them.

signal backdrop_ready(cue_id: String, texture: Texture2D)
signal portrait_frames_ready(character_id: String, frames: SpriteFrames)
signal line_clip_ready(line_index: int, path: String)

var _stage: Node


func attach(stage: Node) -> void:
	_stage = stage


func request_backdrop(_cue: Dictionary) -> void:
	pass


func request_portrait_frames(_character_id: String, _source_roots: Array[String]) -> void:
	pass


func request_line_clip(_line_index: int, _character_id: String, _portrait: Texture2D, _audio_path: String) -> void:
	pass
