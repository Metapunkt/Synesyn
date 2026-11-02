## Purpose: utils/code_block.gd
@tool
extends VBoxContainer

signal copy_requested(code: String)

@onready var code_edit: CodeEdit = %CodeEdit
@onready var copy_button: Button = %CopyButton
@onready var collapse_button: Button = %CollapseButton

const _CODE_BG_COLOR := Color(0.988, 0.985, 1, 1)
const _CODE_BORDER_COLOR := Color(0.67, 0.59, 0.93, 0.42)
const _CODE_TEXT_COLOR := Color(0.16, 0.14, 0.22, 1)
const _CODE_LINE_NUMBER_COLOR := Color(0.42, 0.39, 0.56, 0.72)
const _CODE_SELECTION_COLOR := Color(0.79, 0.73, 0.97, 0.65)

var is_collapsed: bool = false
var highlighter = null
var _pending_code: String = ""

func _ready():
	if not code_edit:
		push_error("CodeEdit node not found in CodeBlock scene")
		return
	if not copy_button:
		push_error("CopyButton not found in CodeBlock scene")
		return
	if not collapse_button:
		push_error("CollapseButton not found in CodeBlock scene")
		return
	copy_button.pressed.connect(_on_copy_button_pressed)
	collapse_button.pressed.connect(_on_collapse_button_pressed)
	# Ensure CodeEdit is properly configured

	# NOTE: `code_block.tscn` already assigns a SyntaxHighlighter resource.
	# Avoid dynamic `load(...).new()` here to keep editor/tool loading robust.
	highlighter = code_edit.syntax_highlighter
	if is_instance_valid(highlighter) and highlighter.has_method("update_cache"):
		highlighter.update_cache()
	code_edit.editable = false
	code_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	code_edit.size_flags_vertical = SIZE_EXPAND_FILL
	code_edit.size_flags_horizontal = SIZE_EXPAND_FILL
	_apply_light_code_theme()

	if not _pending_code.is_empty():
		set_code(_pending_code)
		_pending_code = ""

func _apply_light_code_theme() -> void:
	if not is_instance_valid(code_edit):
		return
	var code_style := StyleBoxFlat.new()
	code_style.bg_color = _CODE_BG_COLOR
	code_style.border_width_left = 1
	code_style.border_width_top = 1
	code_style.border_width_right = 1
	code_style.border_width_bottom = 1
	code_style.border_color = _CODE_BORDER_COLOR
	code_style.corner_radius_top_left = 8
	code_style.corner_radius_top_right = 8
	code_style.corner_radius_bottom_right = 8
	code_style.corner_radius_bottom_left = 8
	code_style.content_margin_left = 8.0
	code_style.content_margin_top = 8.0
	code_style.content_margin_right = 8.0
	code_style.content_margin_bottom = 8.0
	code_edit.add_theme_stylebox_override("normal", code_style)
	code_edit.add_theme_stylebox_override("read_only", code_style)
	code_edit.add_theme_stylebox_override("focus", code_style)
	code_edit.add_theme_color_override("background_color", _CODE_BG_COLOR)
	code_edit.add_theme_color_override("font_color", _CODE_TEXT_COLOR)
	code_edit.add_theme_color_override("font_readonly_color", _CODE_TEXT_COLOR)
	code_edit.add_theme_color_override("font_placeholder_color", _CODE_LINE_NUMBER_COLOR)
	code_edit.add_theme_color_override("line_number_color", _CODE_LINE_NUMBER_COLOR)
	code_edit.add_theme_color_override("caret_color", _CODE_TEXT_COLOR)
	code_edit.add_theme_color_override("selection_color", _CODE_SELECTION_COLOR)

func set_code(code: String):
	#print("Setting code in CodeBlock. Length: ", code.length())
	#print("Code content: ", code)
	if not code_edit:
		_pending_code = code
		return
	if code_edit:
		code_edit.text = code
		if is_instance_valid(code_edit.syntax_highlighter) and code_edit.syntax_highlighter.has_method("update_cache"):
			code_edit.syntax_highlighter.update_cache()
		#print("Code set in CodeEdit. Text length: ", code_edit.text.length())
	
		# Ensure the CodeEdit is visible and has the correct size
		code_edit.visible = true	
		# Force the CodeEdit to update. might not be necessary, but just in case, to ensure the code edit is updating visually
		code_edit.queue_redraw() 
		
		# Adjust size to fit content
		var line_height = code_edit.get_line_height()
		var num_lines = code_edit.get_line_count()
		code_edit.custom_minimum_size.y = line_height * num_lines + 20  # Add some padding
	else:
		push_error("Cannot set code: CodeEdit node is null")

func _on_copy_button_pressed():
	if code_edit:
		var code_to_copy = code_edit.text
		DisplayServer.clipboard_set(code_to_copy)
		emit_signal("copy_requested", code_edit.text)
	else:
		push_error("Cannot copy code: CodeEdit node is null")
	
	emit_signal("copy_requested", code_edit.text)

func _on_collapse_button_pressed():
	is_collapsed = !is_collapsed
	code_edit.visible = !is_collapsed
	collapse_button.text = "▼" if is_collapsed else "▲"
