extends Node

# Test script for ScenSyn Voice Integration
# Demonstrates how the voice bridge integrates with game messages

const ScenSynVoiceBridge = preload("res://addons/syntree_voice/scripts/integration/scensyn_voice_bridge.gd")

var voice_bridge: ScenSynVoiceBridge
var test_messages: Array = [
	{"sender": "Narrator", "message": "The energy crisis meeting begins in the old conference room. The air is thick with tension as the three key stakeholders gather around the worn wooden table."},
	{"sender": "Ingrid Tog", "message": "We need to act quickly. The renewable energy proposal can't wait any longer. Every day we delay costs us more resources."},
	{"sender": "Nathan Coleman", "message": "I understand the urgency, but we must consider the economic implications carefully. A rushed decision could destabilize our entire infrastructure."},
	{"sender": "Astrid Olavson", "message": "Both perspectives have merit, but we're missing the bigger picture. This isn't just about energy - it's about our future as a community."},
	{"sender": "Narrator", "message": "The room falls silent as each person contemplates the weight of their decisions. Outside, the wind picks up, rattling the old windows."}
]

var current_message_index: int = 0

func _ready():
	print("🎮 Starting ScenSyn Voice Integration Test...")
	
	# Create voice bridge
	voice_bridge = ScenSynVoiceBridge.new()
	voice_bridge.name = "VoiceBridge" 
	add_child(voice_bridge)
	
	# Wait for voice bridge to initialize
	await voice_bridge.voice_integration_ready
	
	print("✅ Voice bridge ready!")
	
	# Start test sequence
	await get_tree().create_timer(2.0).timeout
	_start_message_sequence()

func _start_message_sequence():
	"""Start the test message sequence"""
	print("🎭 Starting message sequence...")
	_display_next_message()

func _display_next_message():
	"""Display the next test message"""
	if current_message_index >= test_messages.size():
		print("🎉 Message sequence complete!")
		await get_tree().create_timer(3.0).timeout
		_show_integration_status()
		return
	
	var msg = test_messages[current_message_index]
	current_message_index += 1
	
	print("📝 Displaying message from: ", msg.sender)
	print("   Content: ", msg.message.substr(0, 50), "...")
	
	# Simulate the GameSession display_message call
	_simulate_display_message(msg.sender, msg.message)
	
	# Wait for speech to complete or timeout
	var avatar = voice_bridge.get_character_avatar(msg.sender)
	if avatar:
		# Wait for speech to start
		await get_tree().create_timer(1.0).timeout
		
		# Wait for speech to complete (with timeout)
		var timeout = 60.0  # Max 60 seconds per message
		var elapsed = 0.0
		while avatar.is_currently_speaking() and elapsed < timeout:
			await get_tree().create_timer(0.5).timeout
			elapsed += 0.5
		
		if elapsed >= timeout:
			print("⚠️ Speech timeout for: ", msg.sender)
			avatar.stop_speaking()
	
	# Wait a bit before next message
	await get_tree().create_timer(2.0).timeout
	_display_next_message()

func _simulate_display_message(sender: String, message: String):
	"""Simulate the GameSession display_message function"""
	
	# This simulates what GameSession.display_message() does
	print("🎯 Simulating GameSession.display_message()")
	print("   Sender: ", sender)
	print("   Message length: ", message.length(), " characters")
	
	# Extract character name (removing BBCode formatting)
	var character_name = voice_bridge.extract_character_name_from_sender(sender)
	print("   Extracted character: ", character_name)
	
	# Check if voice should be requested
	if voice_bridge.should_request_voice_for_message(sender, message):
		print("   ✅ Voice synthesis requested")
		
		# Clean message for voice
		var clean_message = _clean_message_for_voice(message)
		print("   Cleaned message: ", clean_message.substr(0, 50), "...")
		
		# Request speech
		var success = voice_bridge.request_character_speech(character_name, clean_message)
		if success:
			print("   🎤 Speech request sent successfully")
		else:
			print("   ❌ Speech request failed")
	else:
		print("   ⏭️ Voice synthesis skipped")

func _clean_message_for_voice(message: String) -> String:
	"""Clean message text for voice synthesis (same as patch)"""
	var clean_text = message
	
	# Remove BBCode formatting
	var regex = RegEx.new()
	regex.compile("\\[/?[^\\]]*\\]")
	clean_text = regex.sub(clean_text, "", true)
	
	# Remove extra whitespace and newlines
	clean_text = clean_text.strip_edges()
	while "  " in clean_text:
		clean_text = clean_text.replace("  ", " ")
	
	# Replace multiple newlines with single spaces
	clean_text = clean_text.replace("\n", " ")
	while "  " in clean_text:
		clean_text = clean_text.replace("  ", " ")
	
	return clean_text

func _show_integration_status():
	"""Show final integration status"""
	print("📊 Integration Status:")
	var status = voice_bridge.get_voice_status()
	
	for key in status:
		print("   ", key, ": ", status[key])
	
	print("🎯 Integration test complete!")

func _input(event):
	"""Handle input for manual control"""
	if event.is_action_pressed("ui_accept"):  # Space or Enter
		print("🎤 Manual trigger - next message")
		if current_message_index < test_messages.size():
			_display_next_message()
	
	if event.is_action_pressed("ui_cancel"):  # Escape
		print("⏹️ Stopping all speech")
		voice_bridge.stop_all_speech() 
