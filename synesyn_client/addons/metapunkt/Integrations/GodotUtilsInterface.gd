extends ToolInterfaceBase
class_name GodotUtilsInterface

# Adapter for core Godot features exposed as tools.

func _init():
	pass

func get_tool_name() -> String:
	return "GodotUtils"

func get_description() -> String:
	return "Small Godot utility actions (debug/inspection helpers)."

func get_operations() -> Array[String]:
	return ["print_message"]

func get_input_schema() -> Dictionary:
	return {
		"schema_version": 1,
		"type": "object",
		"properties": {
			"action": {"type": "string", "description": "Action name (e.g. print_message)."},
			"message": {"type": "string", "description": "Message for print_message."},
		},
		"required": ["action"],
	}

# --- Tool Execution Logic ---
func execute_tool(args: Dictionary) -> Dictionary:
	var action = args.get("action")
	
	match action:
		"print_message":
			var message = args.get("message", "Default message from GodotUtils tool!")
			print(">> [GodotUtils Tool] Message: ", message)
			# Return a success indicator and the message that was printed
			return {"status": "success", "message_printed": message}
			
		# --- Add other Godot utility actions here ---
		# "get_node_position":
		#     var node_path = args.get("node_path")
		#     # ... (logic to get node and position) ...
		#     return {"status": "success", "position": pos}
			
		_:
			printerr("GodotUtilsInterface: Unknown action requested: %s" % action)
			return {"error": "Unknown GodotUtils action: %s" % action, "status": "failure"} 