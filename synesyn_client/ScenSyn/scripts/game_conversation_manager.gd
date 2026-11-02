@tool
extends ConversationManager
class_name GameConversationManager

const MAX_SCENARIOS = 3
const MAX_SESSIONS_PER_SCENARIO = 3
const MAX_CHARACTERS_PER_SESSION = 200000
const WARNING_THRESHOLDS = [0.8, 0.9]  # 80% and 90%

signal approaching_limit(percentage)
signal limit_reached

func add_game_message(role: String, content: String, thread_name: String = "") -> void:
	if thread_name.is_empty():
		thread_name = get_current_thread()
	
	var thread = _get_or_create_thread(thread_name)
	if not thread:
		push_error("GameConversationManager: Failed to get or create thread: " + thread_name)
		return
	
	if not thread.has("messages"):
		thread["messages"] = []
	
	var message = {
		"role": role,
		"content": content,
		"timestamp": Time.get_datetime_string_from_system()
	}
	thread.messages.append(message)
	
	var current_count = get_character_count(thread_name)
	var percentage = float(current_count) / MAX_CHARACTERS_PER_SESSION
	
	for threshold in WARNING_THRESHOLDS:
		if percentage >= threshold:
			emit_signal("approaching_limit", percentage * 100)
			break
	
	if current_count >= MAX_CHARACTERS_PER_SESSION:
		emit_signal("limit_reached")
	
	_save_thread(thread_name)

func get_character_count(thread_name: String) -> int:
	var count = 0
	var messages = get_thread_messages(thread_name)
	for message in messages:
		if message.has("content"):
			count += message.content.length()
	return count

func create_game_thread(scenario_name: String, session_number: int) -> void:
	var thread_name = scenario_name + "_session_" + str(session_number)
	var result = set_current_thread(thread_name)
	if not result.success:
		push_error("GameConversationManager: Failed to create game thread: " + thread_name)

func load_game_thread(scenario_name: String, session_number: int) -> void:
	var thread_name = scenario_name + "_session_" + str(session_number)
	var result = set_current_thread(thread_name)
	if not result.success:
		push_error("GameConversationManager: Failed to load game thread: " + thread_name)

func get_game_threads() -> Dictionary:
	var all_threads = get_thread_list()
	var game_threads = {}
	for thread in all_threads:
		var parts = thread.split("_session_")
		if parts.size() == 2:
			var scenario_name = parts[0]
			var session_number = int(parts[1])
			if not game_threads.has(scenario_name):
				game_threads[scenario_name] = []
			game_threads[scenario_name].append(session_number)
	return game_threads

func can_create_new_scenario() -> bool:
	var game_threads = get_game_threads()
	return game_threads.size() < MAX_SCENARIOS

func can_create_new_session(scenario_name: String) -> bool:
	var game_threads = get_game_threads()
	if game_threads.has(scenario_name):
		return game_threads[scenario_name].size() < MAX_SESSIONS_PER_SCENARIO
	return true

func delete_scenario(scenario_name: String) -> void:
	var game_threads = get_game_threads()
	if game_threads.has(scenario_name):
		for session_number in game_threads[scenario_name]:
			var thread_name = scenario_name + "_session_" + str(session_number)
			delete_thread(thread_name)

func delete_session(scenario_name: String, session_number: int) -> void:
	var thread_name = scenario_name + "_session_" + str(session_number)
	delete_thread(thread_name)

func delete_thread(thread_name: String) -> void:
	if _threads.has(thread_name):
		_threads.erase(thread_name)
		var thread_path = _get_threads_dir().path_join(thread_name + ".json")
		if FileAccess.file_exists(thread_path):
			DirAccess.remove_absolute(thread_path)
