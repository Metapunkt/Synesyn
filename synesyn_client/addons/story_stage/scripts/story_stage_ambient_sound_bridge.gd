class_name StoryStageAmbientSoundBridge
extends Node

## OSC cues to SuperCollider. Off unless the scenario enables the section.

var active := false

var _stage: Node
var _peer: PacketPeerUDP
var _host := "127.0.0.1"
var _port := 57120
var _base := 0.4


func setup(stage: Node) -> void:
	_stage = stage
	active = stage.scenario_section_enabled("ambient_sound", false)
	if not active:
		return
	var section: Dictionary = stage.scenario_section("ambient_sound")
	_host = str(section.get("host", "127.0.0.1"))
	_port = int(float(str(section.get("port", "57120"))))
	_base = float(str(section.get("base_intensity", "0.4")))
	_peer = PacketPeerUDP.new()
	if _peer.connect_to_host(_host, _port) != OK:
		_peer = null
	if stage.host.has_signal("phase_changed"):
		stage.host.phase_changed.connect(_on_phase)


func is_active() -> bool:
	return active


func send_turn(turn_id: int) -> void:
	_send("/scensyn/turn", "i", [turn_id])


func send_lull(tier: int, elapsed_s: float) -> void:
	_send("/scensyn/lull", "if", [tier, elapsed_s])


func note_speaker(speaker: String) -> void:
	_send("/scensyn/speaker", "s", [speaker])
	_send("/scensyn/duck", "f", [0.15])


func note_speech_ended() -> void:
	_send("/scensyn/duck", "f", [1.0])


func stop() -> void:
	_send("/scensyn/stop", "", [])


func _on_phase(phase: String) -> void:
	var section: Dictionary = _stage.scenario_section("ambient_sound")
	var mood := str(section.get("mood_" + phase.to_lower(), section.get("mood_" + phase, phase)))
	_send("/scensyn/phase", "s", [phase])
	_send("/scensyn/mood", "sf", [mood, _base])


func _send(address: String, type_tags: String, args: Array) -> void:
	if not active and address != "/scensyn/lull":
		return
	if address == "/scensyn/lull" and _peer == null and active:
		return
	if _peer == null:
		if address == "/scensyn/lull":
			_ensure_peer()
		if _peer == null:
			return
	_peer.put_packet(StoryStageOsc.message(address, type_tags, args))


func _ensure_peer() -> void:
	_peer = PacketPeerUDP.new()
	if _peer.connect_to_host(_host, _port) != OK:
		_peer = null
