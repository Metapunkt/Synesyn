## Pack tool proxy: wraps a pack-provided tool capability as a ToolInterfaceBase.
##
## When executed, behavior depends on execution_mode (v0: "echo" only).
extends ToolInterfaceBase
class_name PackToolProxy

var _tool_name_val: String
var _pack_id: String
var _pack_version: String
var _capability_id: String
var _description_text: String
var _args_schema_dict: Dictionary
var _result_schema_dict: Dictionary
var _execution_mode: String  # "echo" (default v0)


func _init(
	tool_name_val: String = "",
	pack_id_val: String = "",
	pack_version_val: String = "",
	capability_id_val: String = "",
	desc: String = "",
	args_schema_val: Dictionary = {},
	result_schema_val: Dictionary = {},
	exec_mode: String = "echo"
):
	_tool_name_val = tool_name_val
	_pack_id = pack_id_val
	_pack_version = pack_version_val
	_capability_id = capability_id_val
	_description_text = desc
	_args_schema_dict = args_schema_val
	_result_schema_dict = result_schema_val
	_execution_mode = exec_mode


func get_tool_name() -> String:
	return _tool_name_val


func get_description() -> String:
	return _description_text


func get_input_schema() -> Dictionary:
	if _args_schema_dict.is_empty():
		return super.get_input_schema()
	return _args_schema_dict


func get_output_schema() -> Dictionary:
	if _result_schema_dict.is_empty():
		return super.get_output_schema()
	return _result_schema_dict


func get_operations() -> Array[String]:
	return ["execute"]


func execute_tool(args: Dictionary) -> Dictionary:
	match _execution_mode:
		"echo":
			return {
				"ok": true,
				"result": args,
				"pack_id": _pack_id,
				"pack_version": _pack_version,
				"capability_id": _capability_id,
			}
		_:
			return {"error": "Unsupported execution_mode: %s" % _execution_mode}
