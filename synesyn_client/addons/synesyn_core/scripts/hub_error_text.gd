extends RefCounted
class_name HubErrorText

## Purpose: render a Hub error value as one readable line, whatever its type.
##
## `hub_substrate_transport.gd` does not return a single error shape. A transport
## failure yields a plain String; any non-2xx response yields
## `{"status": int, "body": Variant, "body_raw": String}`; and a Hub that answers
## 200 with its own JSON has that JSON returned verbatim, so `error` may hold
## anything at all — including a number.
##
## Callers used to force this through `String(...)`, which in Godot 4 converts only
## from String, StringName, and NodePath. A Dictionary or a number therefore raised
## "Invalid call 'String' constructor" *inside the failure handler itself*, which
## aborted the handler, left the caller's in-flight flag set, and hung the UI with
## no diagnostic — the exact opposite of what an error path is for. Every Hub error
## must survive being described, so this is deliberately total: it has no failure
## mode of its own and no branch that can raise.

## Long enough for a FastAPI validation payload to name the offending field,
## short enough not to fill a status label with a wall of JSON.
const MAX_DETAIL_LENGTH: int = 400


static func describe(error_any: Variant, fallback_text: String = "Hub unavailable") -> String:
	match typeof(error_any):
		TYPE_NIL:
			return fallback_text
		TYPE_STRING, TYPE_STRING_NAME:
			var error_text: String = str(error_any).strip_edges()
			return error_text if not error_text.is_empty() else fallback_text
		TYPE_DICTIONARY:
			return _describe_dictionary(error_any, fallback_text)
		TYPE_ARRAY:
			return _shorten(JSON.stringify(error_any))
	return _shorten(str(error_any))


static func _describe_dictionary(error_data: Dictionary, fallback_text: String) -> String:
	var status_code: int = int(error_data.get("status", 0))
	var detail_text: String = _body_detail(error_data)
	if status_code > 0 and not detail_text.is_empty():
		return "HTTP %d — %s" % [status_code, detail_text]
	if status_code > 0:
		return "HTTP %d" % status_code
	if not detail_text.is_empty():
		return detail_text
	var rendered: String = JSON.stringify(error_data)
	if rendered.is_empty() or rendered == "{}":
		return fallback_text
	return _shorten(rendered)


## Prefers the message a human can act on. FastAPI reports rejections under
## "detail", which is where the Hub's own validation errors surface, so a schema
## complaint reads as the field it objected to rather than as "HTTP 422".
static func _body_detail(error_data: Dictionary) -> String:
	var body_any: Variant = error_data.get("body", null)
	if typeof(body_any) == TYPE_DICTIONARY:
		var body: Dictionary = body_any
		if body.has("detail"):
			return _shorten(_render_value(body["detail"]))
		if body.has("error"):
			return _shorten(_render_value(body["error"]))
		return _shorten(JSON.stringify(body))
	if typeof(body_any) == TYPE_ARRAY:
		return _shorten(JSON.stringify(body_any))
	var body_text: String = _render_value(body_any).strip_edges()
	if body_text.is_empty():
		body_text = str(error_data.get("body_raw", "")).strip_edges()
	return _shorten(body_text)


static func _render_value(value_any: Variant) -> String:
	if value_any == null:
		return ""
	if typeof(value_any) == TYPE_DICTIONARY or typeof(value_any) == TYPE_ARRAY:
		return JSON.stringify(value_any)
	return str(value_any)


static func _shorten(text: String) -> String:
	var collapsed: String = text.replace("\n", " ").replace("\t", " ").strip_edges()
	if collapsed.length() <= MAX_DETAIL_LENGTH:
		return collapsed
	return collapsed.left(MAX_DETAIL_LENGTH) + "…"
