# VoiceService - Autoload singleton for voice services
# Manages voice synthesis, playback, and other voice-related features

signal voice_synthesis_requested(text: String, character_name: String)
signal voice_synthesis_completed(character_name: String, audio_data: PackedByteArray, lipsync_data: Array, duration: float)
signal voice_service_error(message: String)

signal tts_playback_started(character_name: String)
signal tts_playback_finished(character_name: String)
signal tts_playback_paused(character_name: String)
signal tts_playback_resumed(character_name: String)

var voice_client: Node
var is_available: bool = false
