extends Node

# Test script for Character Avatar System
# Tests avatar creation, voice synthesis, and lip sync animation

var test_avatar: CharacterAvatar

func _ready():
	print("🎭 Starting Avatar System Test...")
	
	# Wait a frame for everything to initialize
	await get_tree().process_frame
	
	# Create test avatar
	_create_test_avatar()
	
	# Wait a bit then test speech
	await get_tree().create_timer(2.0).timeout
	_test_avatar_speech()

func _create_test_avatar():
	"""Create a test avatar instance"""
	print("🎨 Creating test avatar...")
	
	# Load the avatar scene
	var avatar_scene = preload("res://addons/syntree_voice/scenes/character_avatar.tscn")
	test_avatar = avatar_scene.instantiate()
	
	# Configure the avatar
	test_avatar.character_name = "Narrator"
	test_avatar.position = Vector3(0, 0, -2)  # Position in front of camera
	
	# Connect signals for feedback
	test_avatar.speech_started.connect(_on_avatar_speech_started)
	test_avatar.speech_finished.connect(_on_avatar_speech_finished)
	test_avatar.lip_sync_frame.connect(_on_avatar_lip_sync_frame)
	
	# Add to scene
	add_child(test_avatar)
	
	print("✅ Test avatar created: ", test_avatar.character_name)

func _test_avatar_speech():
	"""Test avatar speech synthesis and animation"""
	if not test_avatar:
		print("❌ No test avatar available")
		return
	
	print("🎤 Testing avatar speech...")
	
	var test_text = "Hello! I am the narrator of SynTree. This is a test of the avatar voice system with lip sync animation."
	var success = test_avatar.speak(test_text, "happy")
	
	if success:
		print("📤 Avatar speech request sent successfully")
	else:
		print("❌ Avatar speech request failed")

func _on_avatar_speech_started(character_name: String):
	"""Handle avatar speech start"""
	print("🎭 Avatar started speaking: ", character_name)

func _on_avatar_speech_finished(character_name: String):
	"""Handle avatar speech completion"""
	print("🎭 Avatar finished speaking: ", character_name)
	
	# Test another character after a delay
	await get_tree().create_timer(3.0).timeout
	_test_different_character()

func _on_avatar_lip_sync_frame(mouth_shape: String, intensity: float):
	"""Handle lip sync animation frame"""
	# Only log every few frames to avoid spam
	if randf() < 0.1:  # 10% chance to log
		print("👄 Lip sync: ", mouth_shape, " (", "%.2f" % intensity, ")")

func _test_different_character():
	"""Test with a different character voice"""
	if not test_avatar:
		return
	
	print("🎭 Testing different character voice...")
	
	# Change character name to get different voice
	test_avatar.character_name = "Ingrid Tog"
	
	var test_text = "Greetings from Ingrid Tog! I'm concerned about the current situation in our story."
	test_avatar.speak(test_text, "concerned")

func _input(event):
	"""Handle input for manual testing"""
	if event.is_action_pressed("ui_accept"):  # Space or Enter
		if test_avatar and not test_avatar.is_currently_speaking():
			print("🎤 Manual speech test triggered")
			test_avatar.speak("This is a manual test of the voice system.", "neutral")
	
	if event.is_action_pressed("ui_cancel"):  # Escape
		if test_avatar and test_avatar.is_currently_speaking():
			print("⏹️ Stopping current speech")
			test_avatar.stop_speaking() 