extends ToolInterfaceBase
class_name SynTreeInterface

# Adapter/client for SynTree capabilities.

var _syntree_plugin: Node = null
var _conversation_manager: Node = null
var _content_service: Node = null
var _content_bus: Node = null

func _init():
	_try_connect_syntree()

func get_tool_name() -> String:
	return "SynTree"

func get_description() -> String:
	return "SynTree adapter tool: chat, content analysis, and content-source operations."

func get_operations() -> Array[String]:
	return get_available_operations()

func get_input_schema() -> Dictionary:
	return {
		"schema_version": 1,
		"type": "object",
		"properties": {
			"operation": {"type": "string", "description": "Operation name (chat/analyze_content/get_sources/add_source/get_conversations/create_conversation)."},
			"message": {"type": "string", "description": "User message for chat."},
			"thread_name": {"type": "string", "description": "Thread id/name."},
			"type": {"type": "string", "description": "Analysis type for analyze_content."},
			"content": {"type": "string", "description": "Content for analyze_content."},
			"path": {"type": "string", "description": "File path for add_source."},
			"name": {"type": "string", "description": "Name for add_source/create_conversation."},
		},
		"required": ["operation"],
	}

func execute_tool(args: Dictionary) -> Dictionary:
	if not _syntree_plugin or not _conversation_manager:
		var init_result = _try_connect_syntree()
		if not init_result.success:
			return {"error": "SynTree not available: " + init_result.error}
	
	var operation = args.get("operation", "")
	
	match operation:
		"chat":
			return await _handle_chat(args)
		"analyze_content":
			return await _analyze_content(args)
		"get_sources":
			return _get_content_sources(args)
		"add_source":
			return _add_content_source(args)
		"get_conversations":
			return _get_conversations(args)
		"create_conversation":
			return _create_conversation(args)
		_:
			return {"error": "Unknown operation: " + operation}

func _try_connect_syntree() -> Dictionary:
	# Try to get PluginManager autoload
	var tree = Engine.get_main_loop() as SceneTree
	if not tree:
		return {"success": false, "error": "No scene tree available"}
	
	var plugin_manager = tree.root.get_node_or_null("PluginManager")
	if not plugin_manager:
		return {"success": false, "error": "PluginManager autoload not found"}
	
	# Get main services from PluginManager
	_conversation_manager = plugin_manager.get("conversation_manager")
	_content_service = plugin_manager.get("content_service") 
	_content_bus = plugin_manager.get("content_bus")
	
	if not _conversation_manager:
		return {"success": false, "error": "ConversationManager not available"}
	
	# Set _syntree_plugin to reference PluginManager for compatibility
	_syntree_plugin = plugin_manager
	
	return {"success": true}

func _handle_chat(args: Dictionary) -> Dictionary:
	var message = args.get("message", "")
	var thread_name = args.get("thread_name", "default")
	
	if message.is_empty():
		return {"error": "Message cannot be empty"}
	
	# Use the ConversationManager's chat method directly
	var response = await _conversation_manager.chat(message, thread_name)
	
	if response and response.has("success") and response.success:
		return {
			"success": true,
			"response": response.response,
			"thread_name": thread_name
		}
	else:
		var error_msg = "Failed to get response from SynTree"
		if response and response.has("error"):
			error_msg = response.error
		return {"error": error_msg}

func _analyze_content(args: Dictionary) -> Dictionary:
	var content = args.get("content", "")
	var analysis_type = args.get("type", "general")
	
	if content.is_empty():
		return {"error": "Content cannot be empty"}
	
	# Use ConversationManager to analyze content via chat
	var analysis_prompt = "Please analyze the following content (type: %s):\n\n%s" % [analysis_type, content]
	var response = await _conversation_manager.chat(analysis_prompt, "analysis_" + str(Time.get_unix_time_from_system()))
	
	if response and response.has("success") and response.success:
		return {
			"success": true,
			"analysis": response.response
		}
	else:
		var error_msg = "Failed to analyze content"
		if response and response.has("error"):
			error_msg = response.error
		return {"error": error_msg}

func _get_content_sources(args: Dictionary) -> Dictionary:
	# Get content sources from ContentBus
	var tree = Engine.get_main_loop() as SceneTree
	if not tree:
		return {"error": "No scene tree available"}
	
	var content_bus = tree.root.get_node_or_null("ContentBus")
	if not content_bus:
		return {"error": "ContentBus not found"}
	
	# Get content state resource
	var content_state = content_bus.get_content_state_resource()
	if not content_state:
		return {"error": "ContentState not available"}
	
	var source_ids = content_state.get_source_ids()
	var sources = []
	
	for source_id in source_ids:
		var source_data = content_state.get_source_data(source_id)
		if not source_data.is_empty():
			sources.append({
				"id": source_id,
				"name": source_data.get("meta", {}).get("name", source_id),
				"path": source_data.get("meta", {}).get("path", ""),
				"active": content_state.get_source_active_state(source_id)
			})
	
	return {
		"success": true,
		"sources": sources
	}

func _add_content_source(args: Dictionary) -> Dictionary:
	var path = args.get("path", "")
	var name = args.get("name", "")
	
	if path.is_empty():
		return {"error": "Path cannot be empty"}
	
	if name.is_empty():
		name = path.get_file().get_basename()
	
	if not _content_service:
		return {"error": "ContentService not available"}
	
	# Use ContentService.create_source_from_file method
	var result = _content_service.create_source_from_file(name, path)
	
	if result.has("success") and result.success:
		return {
			"success": true,
			"source": result.get("data", {})
		}
	else:
		var error_msg = "Failed to add content source"
		if result.has("error"):
			error_msg = result.error
		return {"error": error_msg}

func _get_conversations(args: Dictionary) -> Dictionary:
	var threads = _conversation_manager.get_thread_list()
	
	# Convert thread list to conversation format
	var conversations = []
	for thread_name in threads:
		conversations.append({
			"id": thread_name,
			"name": thread_name
		})
	
	return {
		"success": true,
		"conversations": conversations
	}

func _create_conversation(args: Dictionary) -> Dictionary:
	var name = args.get("name", "")
	
	if name.is_empty():
		name = "conversation_" + str(Time.get_unix_time_from_system())
	
	# Use set_current_thread to create/switch to a new thread
	var result = _conversation_manager.set_current_thread(name)
	
	if result.has("success") and result.success:
		return {
			"success": true,
			"conversation": {
				"id": name,
				"name": name
			}
		}
	else:
		var error_msg = "Failed to create conversation"
		if result.has("error"):
			error_msg = result.error
		return {"error": error_msg}

func get_available_operations() -> Array[String]:
	return [
		"chat",
		"analyze_content", 
		"get_sources",
		"add_source",
		"get_conversations",
		"create_conversation"
	] 
