extends Control

const PLAYER_COLOR = Color(0.7, 0.7, 0.7, 1)  # Light grey
const AI_COLOR = Color(0.5, 0.5, 0.5, 1)  # Medium grey
const NARRATOR_COLOR = Color(0.4, 0.4, 0.4, 1)  # Dark grey

@onready var scroll_container = $ScrollContainer
@onready var message_container = $ScrollContainer/VBoxContainer
@onready var line_edit = $HBoxContainer/LineEdit
@onready var send_button = $HBoxContainer/Button
@onready var timer = $Timer
@onready var Network = %Network

func _ready():
	send_button.connect("pressed", _on_send_pressed)
	timer.connect("timeout", _on_timer_timeout)
	timer.start(2.0)  # Start timer for test messages
	custom_minimum_size = Vector2(600, 0)

func add_message(text: String, sender: String):
	print("Debug: StoryLogSystem add_message called. Text:", text, " Sender:", sender)
	var label = RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.selection_enabled = true
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var style_box = StyleBoxFlat.new()
	label.push_color(Color.BLACK)
	# Determine the color based on the sender
	if sender == "":
		style_box.bg_color = NARRATOR_COLOR
#		label.push_color(Color.WHITE)
	elif sender == Network.get_peer_name(multiplayer.get_unique_id()):
		style_box.bg_color = PLAYER_COLOR	
#		label.push_color(Color.BLACK)	
	else:
		style_box.bg_color = AI_COLOR
#		label.push_color(Color.WHITE)
	
	label.add_theme_stylebox_override("normal", style_box)
	
#	if sender != "":
#		label.append_text("[b]" + sender + ":[/b] ")
	label.append_text(text)
	
	message_container.add_child(label)
	print("Debug: New label added to ScrollContainer")
	
	await get_tree().process_frame
	
	scroll_container.scroll_vertical = scroll_container.get_v_scroll_bar().max_value
	print("Debug: Scrolled to bottom of ScrollContainer")
	
func _on_send_pressed():
	pass
	#var text = line_edit.text.strip_edges()
	#if text != "":
		#var player_name = Network.get_peer_name(multiplayer.get_unique_id())
		#add_message(text, player_name)
		#line_edit.clear()

func _on_timer_timeout():
#	add_message("This is a test message from the system.")
	pass

func set_full_log(full_log: String):
	for child in message_container.get_children():
		child.queue_free()
	message_container.clear()
	
	var messages = full_log.strip_edges().split("\n\n", true)
	
	for msg in messages:
		if msg != "":
			var sender_and_msg = msg.split(": ", false, 1)
			if sender_and_msg.size() == 2:
				var sender = sender_and_msg[0].strip_edges()
				var message = sender_and_msg[1]
				add_message(message, sender)
			else:
				add_message(msg, "")
	
	await get_tree().process_frame
	
	scroll_container.scroll_vertical = scroll_container.get_v_scroll_bar().max_value
	print("Debug: Story Log synced and scrolled to bottom.")
