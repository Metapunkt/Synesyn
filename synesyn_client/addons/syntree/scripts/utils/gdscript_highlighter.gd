## Purpose: utils/gdscript_highlighter.gd
@tool
extends SyntaxHighlighter

var keywords = ["and", "as", "assert", "break", "breakpoint", "class", "class_name", "const", "continue", "elif", "else", "enum", "export", "extends", "for", "func", "if", "in", "is", "match", "not", "or", "pass", "return", "self", "signal", "static", "super", "trait", "var", "while", "yield"]
var built_ins = ["bool", "int", "float", "String", "Vector2", "Vector3", "Color", "Array", "Dictionary", "PackedScene", "Node", "SceneTree", "Resource", "null", "true", "false"]
var special_functions = ["_init", "_ready", "_process", "_physics_process", "_input", "_unhandled_input"]

var colors = {
	"text": Color(0.16, 0.14, 0.22, 1),
	"keyword": Color("#8f2fd7"),
	"control_flow": Color("#8f2fd7"),
	"base_type": Color("#178a66"),
	"type": Color("#178a66"),
	"comment": Color("#6c6781"),
	"string": Color("#b05a16"),
	"number": Color("#2368b5"),
	"symbol": Color("#8f2fd7"),
	"function": Color("#215f9b"),
	"member": Color("#215f9b"),
}

func _get_line_syntax_highlighting(line: int) -> Dictionary:
	var result = {}
	var text = get_text_edit().get_line(line)

	var tokens = _tokenize(text)
	
	for token in tokens:
		var start = token.start
		var end = token.end
		var type = token.type
		
		match type:
			"comment":
				result[start] = {"color": colors.comment}
			"string":
				result[start] = {"color": colors.string}
			"number":
				result[start] = {"color": colors.number}
			"symbol":
				result[start] = {"color": colors.symbol}
			"keyword":
				result[start] = {"color": colors.keyword}
			"control_flow":
				result[start] = {"color": colors.control_flow}
			"base_type", "type":
				result[start] = {"color": colors.base_type}
			"function":
				result[start] = {"color": colors.function}
			"member":
				result[start] = {"color": colors.member}
			_:
				result[start] = {"color": colors.text}
		
		result[end] = {"color": colors.text}
	
	return result

func _tokenize(text: String) -> Array:
	var tokens = []
	var i = 0
	while i < text.length():
		if text[i] == "#":
			tokens.append({"type": "comment", "start": i, "end": text.length()})
			break
		elif text[i] == "\"" or text[i] == "'":
			var end = text.find(text[i], i + 1)
			if end == -1:
				end = text.length()
			tokens.append({"type": "string", "start": i, "end": end + 1})
			i = end + 1
		elif text[i].is_valid_int() or (text[i] == "." and i + 1 < text.length() and text[i + 1].is_valid_int()):
			var end = i + 1
			while end < text.length() and (text[end].is_valid_int() or text[end] == "."):
				end += 1
			tokens.append({"type": "number", "start": i, "end": end})
			i = end
		elif text[i] in ["+", "-", "*", "/", "=", "<", ">", "!", ":", "(", ")", "[", "]", "{", "}", ".", ",", "$"]:
			tokens.append({"type": "symbol", "start": i, "end": i + 1})
			i += 1
		elif text[i].is_valid_identifier():
			var end = i + 1
			while end < text.length() and (text[end].is_valid_identifier() or text[end] == "_"):
				end += 1
			var word = text.substr(i, end - i)
			var type = "identifier"
			if word in keywords:
				type = "keyword"
			elif word in ["if", "elif", "else", "for", "while", "match", "break", "continue", "return", "pass"]:
				type = "control_flow"
			elif word in built_ins:
				type = "base_type"
			elif word in special_functions:
				type = "function"
			elif end < text.length() and text[end] == "(":
				type = "function"
			elif i > 0 and text[i - 1] == ".":
				type = "member"
			tokens.append({"type": type, "start": i, "end": end})
			i = end
		else:
			i += 1
	return tokens

func _update_cache():
	pass
