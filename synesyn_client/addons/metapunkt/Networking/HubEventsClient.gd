@tool
extends Node
class_name HubEventsClient

# Minimal hub WS events client for Metapunkt.
# - Best-effort: hub may be down; this must not break runtime.
# - Emits `hub_event(evt)` for each received event envelope.

signal hub_connected()
signal hub_disconnected()
signal hub_error(message: String)
signal hub_event(evt: Dictionary)

@export var hub_base_url: String = "http://127.0.0.1:17777"
@export var auto_reconnect: bool = true
@export var reconnect_delay_sec: float = 1.0

var _ws: WebSocketPeer
var _want_connected: bool = false
var _subscribed_event_types: Array[String] = []
var _reconnect_timer: Timer


func _ready() -> void:
	_ws = WebSocketPeer.new()
	_reconnect_timer = Timer.new()
	_reconnect_timer.one_shot = true
	_reconnect_timer.timeout.connect(func(): _connect_ws())
	add_child(_reconnect_timer)


func is_hub_connected() -> bool:
	# Exposes WS state for UI panels without leaking internal `_ws`.
	if not _ws:
		return false
	return _ws.get_ready_state() == WebSocketPeer.STATE_OPEN


func connect_to_hub(base_url: String = "") -> void:
	if not base_url.strip_edges().is_empty():
		hub_base_url = base_url.strip_edges()
	_want_connected = true
	_connect_ws()


func disconnect_from_hub() -> void:
	_want_connected = false
	if _ws:
		_ws.close()
	if _reconnect_timer:
		_reconnect_timer.stop()


func subscribe(event_types: Array[String]) -> void:
	_subscribed_event_types = event_types.duplicate()
	_try_send_subscribe()


func replay(window_sec: float = 5.0, event_types: Array[String] = []) -> void:
	if not _ws:
		return
	if _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	var msg := {
		"type": "replay",
		"window_sec": float(window_sec),
		"event_types": (event_types if event_types.size() > 0 else _subscribed_event_types),
	}
	_ws.send_text(JSON.stringify(msg))


func _process(_delta: float) -> void:
	if not _ws:
		return
	_ws.poll()
	var st := _ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN:
		while _ws.get_available_packet_count() > 0:
			var txt := _ws.get_packet().get_string_from_utf8()
			_handle_text(txt)
	elif st == WebSocketPeer.STATE_CLOSED:
		if _want_connected and auto_reconnect and not _reconnect_timer.is_stopped():
			# timer already scheduled
			return
		if _want_connected and auto_reconnect:
			_reconnect_timer.start(reconnect_delay_sec)


func _connect_ws() -> void:
	if not _ws:
		return
	if not _want_connected:
		return

	var base := hub_base_url.strip_edges().rstrip("/")
	if base.is_empty():
		hub_error.emit("Hub base URL is empty")
		return

	# Convert http(s) -> ws(s)
	var ws_url := base
	if ws_url.begins_with("https://"):
		ws_url = "wss://" + ws_url.trim_prefix("https://")
	elif ws_url.begins_with("http://"):
		ws_url = "ws://" + ws_url.trim_prefix("http://")
	ws_url += "/ws/events"

	var err := _ws.connect_to_url(ws_url)
	if err != OK:
		hub_error.emit("WebSocket connect failed: %s" % error_string(err))
		return


func _try_send_subscribe() -> void:
	if not _ws:
		return
	if _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	var msg := {"type": "subscribe", "event_types": _subscribed_event_types}
	_ws.send_text(JSON.stringify(msg))


func _handle_text(txt: String) -> void:
	var obj := JSON.parse_string(txt)
	if typeof(obj) != TYPE_DICTIONARY:
		return
	var d: Dictionary = obj
	var typ := str(d.get("type", "")).strip_edges()
	if typ == "hello":
		hub_connected.emit()
		_try_send_subscribe()
	elif typ == "subscribed":
		# no-op
		pass
	elif typ == "event":
		var evt_any: Variant = d.get("data", null)
		if typeof(evt_any) == TYPE_DICTIONARY:
			hub_event.emit(evt_any)


