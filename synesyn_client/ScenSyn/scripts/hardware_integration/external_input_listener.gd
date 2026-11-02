extends Node
class_name ExternalInputListener

## ExternalInputListener
##
## A generic listener for external data packets (e.g., from hardware sensors,
## Python scripts, or other applications). It receives JSON data via UDP
## and broadcasts it to the active MetapromptManager.
##
## Usage:
## Preferred path: sensor packets arrive via Synesyn Hub subscription.
## Fallback path: external applications may send JSON strings to localhost:DEFAULT_PORT.
## Example: {"event": "pendulum_update", "alpha": 0.85, "odu": "OYEKU MEJI"}

signal data_received(data: Dictionary)

const DEFAULT_PORT = 5001
var server := UDPServer.new()
var is_listening := false
var _hub = null
var _hub_connected := false
var _last_hub_connect_attempt_ms := 0
const HUB_RETRY_INTERVAL_MS := 2000

func _ready():
	start_listening(_resolve_port())
	_start_hub_subscription()

func start_listening(port: int = DEFAULT_PORT):
	# Port may already be in use (e.g. another instance, another tool, or stale process).
	# Failing to bind should not hard-error the whole app; just disable external input.
	if server.listen(port) != OK:
		push_warning("ExternalInputListener: Failed to listen on UDP port %d; external input disabled." % port)
		is_listening = false
		return
	
	print("ExternalInputListener: Listening for external data on UDP port %d" % port)
	is_listening = true

func stop_listening():
	server.stop()
	is_listening = false
	print("ExternalInputListener: Stopped listening")

func _process(_delta):
	_retry_hub_connection_if_needed()
	if not is_listening:
		return
		
	server.poll()
	if server.is_connection_available():
		var peer : PacketPeerUDP = server.take_connection()
		var packet = peer.get_packet()
		var packet_string = packet.get_string_from_utf8()
		
		if packet_string.is_empty():
			return
			
		_handle_packet(packet_string)

func _retry_hub_connection_if_needed() -> void:
	if _hub == null or _hub_connected:
		return
	var now_ms := Time.get_ticks_msec()
	if now_ms - _last_hub_connect_attempt_ms < HUB_RETRY_INTERVAL_MS:
		return
	_last_hub_connect_attempt_ms = now_ms
	_hub.ensure_ws_connected()

func _resolve_port() -> int:
	var env_port := OS.get_environment("SCENSYN_EXTERNAL_INPUT_PORT").strip_edges()
	if env_port.is_valid_int():
		return int(env_port)
	return DEFAULT_PORT

func _start_hub_subscription() -> void:
	var hub_script = load("res://addons/synesyn_core/scripts/hub_substrate_client.gd")
	if hub_script == null:
		push_warning("ExternalInputListener: HubSubstrateClient script not found; hub subscription disabled.")
		return
	_hub = hub_script.new()
	add_child(_hub)
	_hub.configure_from_runtime_config()
	_hub.hub_event_received.connect(_on_hub_event_received)
	_hub.ws_connected.connect(func() -> void:
		_hub_connected = true
		var event_types: Array[String] = ["sensor.stochastic_dreams_turn"]
		_hub.ws_subscribe(event_types)
		_hub.ws_replay(3.0, event_types)
	)
	_hub.ws_disconnected.connect(func() -> void:
		_hub_connected = false
	)
	_last_hub_connect_attempt_ms = Time.get_ticks_msec()
	_hub.ensure_ws_connected()

func _on_hub_event_received(event: Dictionary) -> void:
	var event_type := str(event.get("event_type", "")).strip_edges()
	if event_type != "sensor.stochastic_dreams_turn":
		return
	var payload_any: Variant = event.get("payload", {})
	if typeof(payload_any) != TYPE_DICTIONARY:
		return
	var payload: Dictionary = payload_any
	_forward_data(payload, "hub")

func _handle_packet(json_string: String):
	var json = JSON.new()
	var error = json.parse(json_string)
	
	if error == OK:
		var data = json.data
		if typeof(data) == TYPE_DICTIONARY:
			_forward_data(data, "udp")
		else:
			push_warning("ExternalInputListener: Received non-dictionary JSON")
	else:
		push_warning("ExternalInputListener: JSON Parse Error: %s at line %d" % [json.get_error_message(), json.get_error_line()])

func _forward_data(data: Dictionary, source: String) -> void:
	print("ExternalInputListener[%s]: Received data: %s" % [source, data])
	emit_signal("data_received", data)
	
	# Forward to UmenoEngine first (if available)
	var chaos_engine = get_tree().get_first_node_in_group("chaos_engine")
	if chaos_engine:
		if data.has("pendulum"):
			var p = data.pendulum
			chaos_engine.update_pendulum_state(p.get("bias", 0.0), p.get("stability", 0.5))
		if data.has("resonance"):
			chaos_engine.update_resonance(data.resonance)
	
	# Forward to Narrative (MetapromptManager)
	if Global.get_metaprompt_manager():
		Global.get_metaprompt_manager().handle_external_input(data)
