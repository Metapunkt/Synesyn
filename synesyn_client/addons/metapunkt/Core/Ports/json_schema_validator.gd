extends Object
class_name MetapunktJsonSchemaValidator

## Minimal JSON Schema validator (subset) for Metapunkt Synterfaces v1.
##
## Supported keywords:
## - type
## - required
## - properties
## - enum
## - minLength
## - minItems
## - items
## - additionalProperties (true/false)
##
## This is intentionally conservative and small to avoid pulling in heavy deps.
## It returns actionable error strings for UI and spawn failures.

static func validate(value: Variant, schema: Dictionary, path: String = "$") -> Dictionary:
	if schema.has("enum"):
		var allowed: Array = schema.get("enum", [])
		if not allowed.has(value):
			return _fail("%s: value %s not in enum %s" % [path, str(value), str(allowed)])

	var t: String = str(schema.get("type", "")).strip_edges()
	if not t.is_empty():
		var type_ok := _matches_type(value, t)
		if not type_ok:
			return _fail("%s: expected type %s, got %s" % [path, t, _type_name(value)])

	# Strings
	if t == "string":
		var s := str(value)
		var min_len: int = int(schema.get("minLength", 0))
		if min_len > 0 and s.length() < min_len:
			return _fail("%s: string shorter than minLength=%d" % [path, min_len])

	# Arrays
	if t == "array":
		var arr: Array = value
		var min_items: int = int(schema.get("minItems", 0))
		if min_items > 0 and arr.size() < min_items:
			return _fail("%s: array shorter than minItems=%d" % [path, min_items])
		if schema.has("items"):
			var item_schema: Dictionary = schema.get("items", {})
			for i in range(arr.size()):
				var r = validate(arr[i], item_schema, "%s[%d]" % [path, i])
				if not r.ok:
					return r

	# Objects
	if t == "object":
		var obj: Dictionary = value

		# required fields
		var req: Array = schema.get("required", [])
		for k in req:
			var key := str(k)
			if not obj.has(key):
				return _fail("%s: missing required property '%s'" % [path, key])

		# properties validation
		var props: Dictionary = schema.get("properties", {})
		for key in props.keys():
			if obj.has(key):
				var prop_schema: Dictionary = props.get(key, {})
				var r2 = validate(obj.get(key), prop_schema, "%s.%s" % [path, str(key)])
				if not r2.ok:
					return r2

		# additionalProperties strictness (default: true)
		var additional := schema.get("additionalProperties", true)
		if additional == false:
			for k2 in obj.keys():
				if not props.has(k2):
					return _fail("%s: unexpected property '%s' (additionalProperties=false)" % [path, str(k2)])

	return {"ok": true}

static func _matches_type(value: Variant, t: String) -> bool:
	match t:
		"object":
			return typeof(value) == TYPE_DICTIONARY
		"array":
			return typeof(value) == TYPE_ARRAY
		"string":
			return typeof(value) == TYPE_STRING
		"number":
			return typeof(value) in [TYPE_INT, TYPE_FLOAT]
		"integer":
			return typeof(value) == TYPE_INT
		"boolean":
			return typeof(value) == TYPE_BOOL
		_:
			# Unknown 'type' keyword: treat as pass-through to avoid false negatives.
			return true

static func _type_name(value: Variant) -> String:
	match typeof(value):
		TYPE_NIL: return "null"
		TYPE_BOOL: return "boolean"
		TYPE_INT: return "integer"
		TYPE_FLOAT: return "number"
		TYPE_STRING: return "string"
		TYPE_ARRAY: return "array"
		TYPE_DICTIONARY: return "object"
		_: return "variant(%d)" % typeof(value)

static func _fail(msg: String) -> Dictionary:
	return {"ok": false, "error": msg}


