extends Node
class_name StochasticDreamsPendulumBridge
## Receives OSC from the pendulum Pi on /pendulum/result, parses the
## {coins, track} JSON payload, runs UWP traversal analysis and Odu
## selection, then forwards the assembled ScenSyn packet through
## the ExternalInputListener pipeline.
##
## Instantiated by CulturalNarrativeMetapromptManager when the active
## scenario is Stochastic Dreams.

var _udp := PacketPeerUDP.new()
var _assembler: SDTurnPacketAssembler
var _turn_count: int = 0
var _is_listening: bool = false

var _uwp_x_min: float = 0.0
var _uwp_y_min: float = 0.0
var _uwp_x_max: float = 1280.0
var _uwp_y_max: float = 720.0


func _ready() -> void:
	print("PendulumBridge: _ready — node instantiated, beginning setup")
	var config: Dictionary = _load_config()
	_apply_config(config)
	_assembler = SDTurnPacketAssembler.new(config)
	var listen_port: int = int(config.get("osc_listen_port", 9002))
	print("PendulumBridge: attempting to bind UDP port %d on 192.168.1.102" % listen_port)
	var err: int = _udp.bind(listen_port, "192.168.1.102")
	if err != OK:
		push_error("PendulumBridge: FAILED to bind UDP port %d (Godot error code %d). OSC will not be received." % [listen_port, err])
		return
	_is_listening = true
	print("PendulumBridge: ✓ bound and listening on UDP port %d for OSC /pendulum/result" % listen_port)
	print("PendulumBridge: config loaded — uwp_bounds=%s  assembler=%s" % [
		config.get("uwp_wheel_bounds_px", "default"),
		("OK" if _assembler != null else "NULL"),
	])


var _process_log_timer: float = 0.0
const _PROCESS_LOG_INTERVAL: float = 10.0  # print "still listening" heartbeat every 10 s

func _process(delta: float) -> void:
	if not _is_listening:
		return
	_process_log_timer += delta
	if _process_log_timer >= _PROCESS_LOG_INTERVAL:
		_process_log_timer = 0.0
		print("PendulumBridge: heartbeat — still listening on port 9002, turns so far: %d" % _turn_count)
	var pkt_count: int = _udp.get_available_packet_count()
	if pkt_count > 0:
		print("PendulumBridge: %d UDP packet(s) available" % pkt_count)
	while _udp.get_available_packet_count() > 0:
		var raw: PackedByteArray = _udp.get_packet()
		print("PendulumBridge: raw packet received — %d bytes" % raw.size())
		_handle_osc_packet(raw)


func _exit_tree() -> void:
	if _is_listening:
		_udp.close()
		_is_listening = false
		print("PendulumBridge: stopped after %d turns" % _turn_count)


# ── Config ────────────────────────────────────────────────────────────────────

func _load_config() -> Dictionary:
	var path := "res://ScenSyn/session_types/story_catalyst/cultural_narratives/stochastic_dreams/bridge_config.json"
	if not FileAccess.file_exists(path):
		push_warning("PendulumBridge: config not found at %s; using defaults" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_warning("PendulumBridge: failed to parse config; using defaults")
		return {}
	return json.data if typeof(json.data) == TYPE_DICTIONARY else {}


func _apply_config(config: Dictionary) -> void:
	var bounds: Array = config.get("uwp_wheel_bounds_px", [0, 0, 1280, 720])
	_uwp_x_min = float(bounds[0])
	_uwp_y_min = float(bounds[1])
	_uwp_x_max = float(bounds[2])
	_uwp_y_max = float(bounds[3])


# ── OSC parsing ───────────────────────────────────────────────────────────────
# The Pi sends a standard OSC message: address /pendulum/result, type tag ,s,
# with the JSON payload as a single string argument.

func _handle_osc_packet(packet: PackedByteArray) -> void:
	if packet.size() < 8:
		push_warning("PendulumBridge: packet too small (%d bytes) — not a valid OSC message, discarding" % packet.size())
		return
	var parsed: Dictionary = _parse_osc_message(packet)
	if parsed.is_empty():
		push_warning("PendulumBridge: OSC parse returned empty — packet may be malformed (first 16 bytes: %s)" % packet.slice(0, mini(16, packet.size())).hex_encode())
		return
	var address: String = parsed.get("address", "")
	print("PendulumBridge: OSC address='%s'  arg_preview='%s'" % [address, parsed.get("arg", "").substr(0, 80)])
	if address != "/pendulum/result":
		push_warning("PendulumBridge: unexpected OSC address '%s' (expected /pendulum/result) — ignoring" % address)
		return
	var json_str: String = parsed.get("arg", "")
	if json_str.is_empty():
		push_warning("PendulumBridge: /pendulum/result received but OSC string argument is empty")
		return
	_process_result_payload(json_str)


func _parse_osc_message(packet: PackedByteArray) -> Dictionary:
	var packet_size: int = packet.size()
	# Address: null-terminated, padded to 4-byte boundary
	var addr_end: int = _find_null(packet, 0)
	if addr_end < 0:
		return {}
	var address: String = packet.slice(0, addr_end).get_string_from_ascii()
	var pos: int = _align4(addr_end + 1)
	# Type tags: starts with ',' (ASCII 44), null-terminated, padded
	if pos >= packet_size or packet[pos] != 44:
		return {}
	var tag_end: int = _find_null(packet, pos)
	if tag_end < 0:
		return {}
	var tags: String = packet.slice(pos, tag_end).get_string_from_ascii()
	pos = _align4(tag_end + 1)
	# Read first string argument if present
	var arg_str: String = ""
	if tags.length() >= 2 and tags[1] == "s":
		if pos < packet_size:
			var str_end: int = _find_null(packet, pos)
			if str_end >= 0:
				arg_str = packet.slice(pos, str_end).get_string_from_utf8()
	return {"address": address, "arg": arg_str}


func _find_null(data: PackedByteArray, from: int) -> int:
	for idx in range(from, data.size()):
		if data[idx] == 0:
			return idx
	return -1


func _align4(val: int) -> int:
	return (val + 3) & ~3


# ── Payload processing ────────────────────────────────────────────────────────

func _process_result_payload(json_str: String) -> void:
	var json := JSON.new()
	if json.parse(json_str) != OK:
		push_warning("PendulumBridge: failed to parse result JSON: %s" % json.get_error_message())
		return
	var payload: Variant = json.data
	if typeof(payload) != TYPE_DICTIONARY:
		return
	var coins: Array = payload.get("coins", [])
	var track: Array = payload.get("track", [])
	if coins.is_empty():
		push_warning("PendulumBridge: payload has no coins; skipping")
		return

	var board_detections: Dictionary = _parse_coins(coins)
	var tracking_samples: Array = _normalize_track(track)

	_turn_count += 1
	print("PendulumBridge: turn #%d — %d coins, %d track samples" % [
		_turn_count, board_detections.size(), tracking_samples.size()])

	var packet: Dictionary = _assembler.assemble(board_detections, tracking_samples)
	if packet.is_empty():
		push_warning("PendulumBridge: assembler returned empty packet for turn #%d" % _turn_count)
		return

	print("PendulumBridge: turn #%d assembled — odu=%s @ %s  resonance=%.3f" % [
		_turn_count,
		str(packet.get("odu", "?")),
		str(packet.get("turn_packet", {}).get("shared", {}).get("province_or_site", "?")),
		float(packet.get("resonance", 0.0)),
	])

	_forward_to_scensyn(packet)


func _parse_coins(coins: Array) -> Dictionary:
	var detections: Dictionary = {}
	for coin in coins:
		var coin_name: String = str(coin.get("name", "")).to_lower().strip_edges()
		if coin_name.is_empty():
			continue
		detections[coin_name] = [int(float(coin.get("x", 0))), int(float(coin.get("y", 0)))]
	return detections


func _normalize_track(track: Array) -> Array:
	var w: float = maxf(1.0, _uwp_x_max - _uwp_x_min)
	var h: float = maxf(1.0, _uwp_y_max - _uwp_y_min)
	var samples: Array = []
	for idx in range(track.size()):
		var point: Dictionary = track[idx]
		var x_raw: Variant = point.get("x")
		var y_raw: Variant = point.get("y")
		if x_raw == null or y_raw == null:
			samples.append({"x": null, "y": null, "t_s": float(idx)})
			continue
		var x_norm: float = clampf((float(x_raw) - _uwp_x_min) / w, 0.0, 1.0)
		var y_norm: float = clampf((float(y_raw) - _uwp_y_min) / h, 0.0, 1.0)
		samples.append({"x": x_norm, "y": y_norm, "t_s": float(idx)})
	return samples


func _forward_to_scensyn(packet: Dictionary) -> void:
	if Global.external_input_listener:
		print("PendulumBridge: forwarding turn #%d to ExternalInputListener" % _turn_count)
		Global.external_input_listener._forward_data(packet, "pendulum_bridge")
	else:
		push_error("PendulumBridge: Global.external_input_listener is null — packet for turn #%d dropped. Check that ExternalInputListener is instantiated in Global." % _turn_count)
