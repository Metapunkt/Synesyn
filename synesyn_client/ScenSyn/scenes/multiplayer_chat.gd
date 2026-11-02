extends VBoxContainer

@onready var chat_display = $ChatDisplay
@onready var player_chat_input = %PlayerChat_InputField
@onready var player_chat_send_button = %SendPlayerChatButton
#@onready var Network = %Network


func _ready():	
	player_chat_input.connect("text_submitted", _on_send_pressed)
	Network.peer_connected.connect(_on_peer_connected)
	Network.peer_disconnected.connect(_on_peer_disconnected)

func _exit_tree():
	Network.peer_connected.disconnect(_on_peer_connected)
	Network.peer_disconnected.disconnect(_on_peer_disconnected)
	# ... other disconnections ...
	
func _on_send_pressed(new_text: String = ""):
	if new_text.is_empty():
		new_text = player_chat_input.text
	if not new_text.is_empty():
		rpc("receive_message", multiplayer.get_unique_id(), new_text)
		player_chat_input.clear()

@rpc("any_peer", "call_local")
func receive_message(sender_id: int, message: String):
	var sender_name = Network.player_info.get(sender_id, {}).get("name", "Unknown")
	var formatted_message = "[b]%s:[/b] %s" % [sender_name, message]
	chat_display.append_text(formatted_message + "\n")

func _on_peer_connected(id: int):
	pass
#	var player_name = Network.peer_info.get(id, {}).get("name", "Unknown")
#	chat_display.append_text("[color=green]%s has joined the game.[/color]\n" % player_name)

func _on_peer_disconnected(id: int):
	pass
#	var player_name = Network.player_info.get(id, {}).get("name", "Unknown")
#	chat_display.append_text("[color=red]%s has left the game.[/color]\n" % player_name)
