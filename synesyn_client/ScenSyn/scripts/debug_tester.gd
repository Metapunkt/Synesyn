extends Node

var game_session_connected = false

func _process(delta):
	if not game_session_connected:
		var root = get_tree().get_root()
		var game_session = root.find_child("GameSession", true, false)
		if game_session != null:
#			game_session.connect("sync_full_story_log_received", self._on_sync_full_story_log_received)
#			game_session.connect("sync_story_log_received", self._on_sync_story_log_received)
			game_session_connected = true
			print("Debug Tester: Connected to GameSession.")
	else:
		# Already connected
		pass

func _on_story_log_updated(current_story_log):
	pass
#	print("Story Log Updated:\n", current_story_log)

func _on_sync_full_story_log_received(full_story_log):
	pass
#	print("Sync Full Story Log Received:\n", full_story_log)

func _on_sync_story_log_received(sender_id, message):
	pass
#	print("Sync Story Log Received from", sender_id, ":", message)
