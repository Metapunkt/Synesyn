extends RefCounted
class_name MetapunktUiParseUtils

static func coerce_int(v: Variant, default_value: int) -> int:
	match typeof(v):
		TYPE_INT:
			return int(v)
		TYPE_FLOAT:
			return floori(v)
		TYPE_STRING:
			var s := str(v).strip_edges()
			return s.to_int() if not s.is_empty() else default_value
		_:
			return default_value


static func parse_json_object(text: String) -> Dictionary:
	var any := JSON.parse_string(text)
	return any if typeof(any) == TYPE_DICTIONARY else {}


static func stringify_json(d: Dictionary) -> String:
	return JSON.stringify(d, "\t")


static func parse_csv(text: String) -> Array:
	var arr: Array = []
	for p in text.split(","):
		var s := p.strip_edges()
		if not s.is_empty():
			arr.append(s)
	return arr
