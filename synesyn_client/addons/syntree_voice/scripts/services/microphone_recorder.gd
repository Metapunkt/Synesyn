# microphone_recorder.gd
extends Node

## Manages microphone recording and saving audio to a WAV file.

var _is_recording := false
var _audio_stream_player: AudioStreamPlayer
var _record_effect_idx := -1
var _recorded_sample: AudioStreamWAV = null

func _save_path() -> String:
	var dir_path: String = RuntimeConfig.get_voice_recordings_dir()
	DirAccess.make_dir_recursive_absolute(dir_path)
	return dir_path.path_join("voice_input.wav")

func _ready():
	# This node needs an AudioStreamPlayer to function.
	# We create it programmatically to keep this component self-contained.
	_audio_stream_player = AudioStreamPlayer.new()
	add_child(_audio_stream_player)
	
	# Set up the audio bus with a record effect.
	var bus_idx = AudioServer.get_bus_index("Record")
	if bus_idx == -1:
		# If the "Record" bus doesn't exist, create it.
		AudioServer.add_bus(AudioServer.bus_count)
		bus_idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus_idx, "Record")
		# Route the new bus to the Master output but mute it.
		# This ensures the bus is processed, allowing the record effect to work.
		AudioServer.set_bus_send(bus_idx, "Master")
		AudioServer.set_bus_volume_db(bus_idx, -100) # Effectively muted
	
	# Add the record effect to the bus if it's not already there.
	_record_effect_idx = -1
	for i in range(AudioServer.get_bus_effect_count(bus_idx)):
		var effect = AudioServer.get_bus_effect(bus_idx, i)
		if effect is AudioEffectRecord:
			_record_effect_idx = i
			break
			
	if _record_effect_idx == -1:
		var effect = AudioEffectRecord.new()
		AudioServer.add_bus_effect(bus_idx, effect)
		_record_effect_idx = AudioServer.get_bus_effect_count(bus_idx) - 1

	# Assign the microphone input to the player.
	_audio_stream_player.stream = AudioStreamMicrophone.new()
	_audio_stream_player.bus = "Record"


func start_recording():
	if _is_recording:
		print("MicrophoneRecorder: Already recording.")
		return
	
	print("MicrophoneRecorder: Starting recording...")
	var bus_idx = AudioServer.get_bus_index("Record")
	var effect: AudioEffectRecord = AudioServer.get_bus_effect(bus_idx, _record_effect_idx)
	
	if effect:
		effect.set_recording_active(true)
		_is_recording = true
		_audio_stream_player.play() # Start the microphone stream
	else:
		push_error("MicrophoneRecorder: Could not find the record effect.")


func stop_recording() -> String:
	if not _is_recording:
		print("MicrophoneRecorder: Not currently recording.")
		return ""
		
	print("MicrophoneRecorder: Stopping recording...")
	_audio_stream_player.stop() # Stop the microphone stream
	
	var bus_idx = AudioServer.get_bus_index("Record")
	var effect: AudioEffectRecord = AudioServer.get_bus_effect(bus_idx, _record_effect_idx)
	
	if effect:
		effect.set_recording_active(false)
		await get_tree().process_frame # Allow the recording to finalize
		_recorded_sample = effect.get_recording()
		_is_recording = false
		
		if _recorded_sample and _recorded_sample.get_length() > 0:
			# Diagnostic check for audio length
			print("MicrophoneRecorder: Recorded sample length: %.2f seconds." % _recorded_sample.get_length())
			if _recorded_sample.get_length() < 0.2:
				push_warning("MicrophoneRecorder: The recorded audio is very short. Is the microphone picking up sound?")
			
			var absolute_save_path: String = _save_path()
			var dir_path: String = absolute_save_path.get_base_dir()
			if not DirAccess.dir_exists_absolute(dir_path):
				var err = DirAccess.make_dir_recursive_absolute(dir_path)
				if err != OK:
					push_error("MicrophoneRecorder: Failed to create recordings directory at: %s. Error: %s" % [dir_path, err])
					return ""
			
			var save_err = _recorded_sample.save_to_wav(absolute_save_path)
			if save_err != OK:
				push_error("MicrophoneRecorder: Failed to save .wav file to %s. Error: %s" % [absolute_save_path, save_err])
				return ""
				
			print("MicrophoneRecorder: Recording saved to: ", absolute_save_path)
			return absolute_save_path
		else:
			push_error("MicrophoneRecorder: Failed to get a valid audio sample after recording.")
	else:
		push_error("MicrophoneRecorder: Could not find the record effect to stop recording.")
	return ""

func is_recording() -> bool:
	return _is_recording
