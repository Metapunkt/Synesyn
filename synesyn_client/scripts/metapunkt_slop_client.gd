extends Node
class_name MetapunktSLOPClient

@export var base_url: String = "http://127.0.0.1:8080"
@export var app_id: String = "scensyn"

var _http: HTTPRequest

func _ready() -> void:
	_http = HTTPRequest.new()
	add_child(_http)

func _headers(user_id: String = "", scopes: Array[String] = []) -> PackedStringArray:
	var sid := SynesynSession.get_or_create_session_id(app_id)
	var tid := SynesynSession.get_current_turn_id(app_id)
	var hs: PackedStringArray = [
		"Content-Type: application/json",
		"X-App-Id: %s" % app_id,
		"X-Session-Id: %s" % sid,
	]
	if not tid.strip_edges().is_empty():
		hs.append("X-Turn-Id: %s" % tid.strip_edges())
	if not user_id.strip_edges().is_empty():
		hs.append("X-User-Id: %s" % user_id.strip_edges())
	if not scopes.is_empty():
		hs.append("X-Slop-Scope: %s" % ",".join(scopes))
	return hs

func request_json(method: int, path: String, payload: Variant = null, user_id: String = "", scopes: Array[String] = []) -> Dictionary:
	var url := base_url.rstrip("/") + "/" + path.lstrip("/")
	var body := "" if payload == null else JSON.stringify(payload)
	var err := _http.request(url, _headers(user_id, scopes), method, body)
	if err != OK:
		return {"ok": false, "error": "request_failed", "details": str(err)}
	var res = await _http.request_completed
	var code: int = int(res[1])
	var buf: PackedByteArray = res[3]
	var text := buf.get_string_from_utf8()
	var parsed_any: Variant = JSON.parse_string(text)
	return {"ok": code >= 200 and code < 300, "status": code, "data": parsed_any, "raw": text}


