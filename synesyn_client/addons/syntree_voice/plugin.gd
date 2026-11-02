## SynTree Voice — Voice synthesis and transcription bridge for SynTree.
## Copyright © 2026 Ayodele Arigbabu | metapunkt.org | NTNU. All rights reserved.
## Licensed under [licence pending].
## Version: 0.0.3
## Enquiries: metapunkt@metapunkt.org
@tool
extends EditorPlugin

const VoiceServiceManager = preload("res://addons/syntree_voice/scripts/services/voice_service_manager.gd")
const VOICE_SERVICE_PATH := "res://addons/syntree_voice/scripts/services/voice_service_manager.gd"

## Registering an autoload rebuilds every autoload node. Re-registering one the
## host already declares would tear them down after sibling plugins scheduled
## deferred work against them. See ADR 0017 rule 7.
var _autoload_added: bool = false

func _enter_tree():
	# Register VoiceService as autoload so other systems can access it
	if not ProjectSettings.has_setting("autoload/VoiceService"):
		add_autoload_singleton("VoiceService", VOICE_SERVICE_PATH)
		_autoload_added = true
	print("SynTree Voice addon enabled")

func _exit_tree():
	# Only remove what this plugin added, so disabling it never strips a host
	# project's own entry.
	if _autoload_added:
		remove_autoload_singleton("VoiceService")
		_autoload_added = false
	print("SynTree Voice addon disabled")
