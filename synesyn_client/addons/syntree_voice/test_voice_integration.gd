extends Node

# Test script for SynTree Voice Integration
# This can be used to test the voice system independently

func _ready():
	print("=== SynTree Voice Integration Test ===")
	
	# Give some time for autoloads to initialize
	await get_tree().create_timer(1.0).timeout
	
	test_voice_service()

func test_voice_service():
	"""Test the voice service functionality"""
	
	if not has_node("/root/VoiceService"):
		print("❌ VoiceService autoload not found!")
		return
	
	var voice_service = get_node("/root/VoiceService")
	print("✅ VoiceService autoload found")
	
	# Connect to voice service signals
	voice_service.voice_synthesis_completed.connect(_on_voice_completed)
	voice_service.voice_service_ready.connect(_on_service_ready)
	voice_service.voice_service_error.connect(_on_service_error)
	
	# Check service status
	print("🔍 Checking voice service status...")
	var is_available = voice_service.get_service_status()
	print("📊 Service available: ", is_available)
	
	# Get character voices
	var character_voices = voice_service.get_character_voices()
	print("🎭 Character voices: ", character_voices)
	
	# Wait a bit for connection to establish
	await get_tree().create_timer(2.0).timeout
	
	# Test synthesis request
	print("🎤 Testing synthesis request...")
	var success = voice_service.request_character_speech("Hello from SynTree! This is a test of the voice synthesis system.", "Narrator")
	print("📤 Synthesis request sent: ", success)

func _on_voice_completed(character: String, audio_data: PackedByteArray, lipsync_data: Array):
	"""Handle voice synthesis completion"""
	print("✅ Voice synthesis completed!")
	print("🎭 Character: ", character)
	print("🔊 Audio data size: ", audio_data.size(), " bytes")
	print("👄 Lip sync data points: ", lipsync_data.size())
	
	# Test audio playback (optional)
	test_audio_playback(audio_data)

func _on_service_ready():
	"""Handle service ready signal"""
	print("🟢 Voice service is ready!")

func _on_service_error(error: String):
	"""Handle service error"""
	print("🔴 Voice service error: ", error)

func test_audio_playback(audio_data: PackedByteArray):
	"""Test audio playback with the synthesized audio"""
	print("🔊 Testing audio playback...")
	
	# Create audio stream player
	var audio_player = AudioStreamPlayer.new()
	add_child(audio_player)
	
	# Create audio stream from WAV data
	var audio_stream = AudioStreamWAV.new()
	audio_stream.data = audio_data
	audio_stream.format = AudioStreamWAV.FORMAT_16_BITS
	audio_stream.mix_rate = 22050  # Adjust based on your TTS settings
	audio_stream.stereo = false
	
	# Play the audio
	audio_player.stream = audio_stream
	audio_player.play()
	
	print("🎵 Audio playback started!")
	
	# Clean up after playback
	await audio_player.finished
	audio_player.queue_free()
	print("🎵 Audio playback completed!") 
