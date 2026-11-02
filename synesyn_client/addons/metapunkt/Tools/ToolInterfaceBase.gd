extends Object
class_name ToolInterfaceBase

# Base class/interface for tool interaction logic.

func _init():
	pass

# Example interface functions (to be defined by subclasses)
func get_tool_name() -> String:
	return "BaseTool"

func get_description() -> String:
	return ""

# Optional: list supported operations/actions for this tool (for /tools introspection).
func get_operations() -> Array[String]:
	return []

# JSON-schema-ish dictionaries intended for introspection (SLOP /tools) and UI validation.
# Keep them small and stable; they are not a strict validator inside GDScript.
func get_input_schema() -> Dictionary:
	return {
		"schema_version": 1,
		"type": "object",
		"properties": {},
		"required": [],
	}

func get_output_schema() -> Dictionary:
	return {
		"schema_version": 1,
		"type": "object",
		"properties": {
			"ok": {"type": "boolean"},
			"result": {},
			"error_obj": {},
		},
		"required": ["ok"],
	}

func execute_tool(args: Dictionary) -> Dictionary:
	push_warning("Base execute_tool called!")
	return {"error": "Not implemented"} 