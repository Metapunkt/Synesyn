# stage_manager_system.gd
# Posts system cues under the scenario's speaker_name, or "System Message"
# when the scenario does not name one.

class_name StageManagerSystem
extends Node

signal stage_notification(message: String, urgency: int)

# Progression tracking for abstract signal emergence (scenario agnostic).
# Scenarios can treat this as “awakening %”, “ritual charge”, etc. by
# reading `get_signal_progress()` and remixing the value in their own UI/text.
var signal_progress: float = 0.0
var system_stability: float = 100.0
var notification_count: int = 0
var _is_generating: bool = false
var _last_notification_time: float = -1000.0
var notification_cooldown_sec: float = 65.0
var _non_child_message_count: int = 0
var min_non_child_between_notifications: int = 15
var notification_probability: float = 0.1
var _last_context: String = ""
var _last_template_index: int = -1

# Notification templates (generic baseline).
# To customize per scenario: define your own templates in the scenario file,
# then override `notification_templates` at runtime using that parsed data.
var notification_templates = {
	# signal_progress → use when your scenario tracks any kind of unfolding activation/awakening.
	"signal_progress": [
		{
			"template": "Signal strength ({progress}%) rising, interpretation unstable",
			"min_progress": 0.0,
			"max_progress": 40.0
		},
		{
			"template": "Emergent pathways ({progress}% complete) forming through noise",
			"min_progress": 30.0,
			"max_progress": 70.0
		},
		{
			"template": "WARNING: Synchronization at {progress}% — pattern incomplete",
			"min_progress": 60.0,
			"max_progress": 95.0
		}
	],
	# cultural_translation → highlight cross-cultural, linguistic, or interpretive friction.
	"cultural_translation": [
		"Translation matrices report semantic drift",
		"Multilingual bridge registering partial communication failures",
		"Traditional knowledge integration channels remain unstable"
	],
	# system_instability → general-purpose “tech glitches or system strain” bucket.
	"system_instability": [
		"Primary interface experiencing recursive consultation loops",
		"Human-AI convergence thresholds remain undefined",
		"WARNING: Transcendence protocols report critical instability"
	],
	# character_evolution → cues about power shifts, language drift, or identity changes.
	"character_evolution": [
		"Language matrices show hybridization cascade across speakers",
		"Ownership assertions failing verification—authority lookup denied",
		"Analytical and ancestral protocols synchronizing with cautious stability"
	],
	# ritual_consultation → cover divination attempts, repeated gestures, ceremony beats.
	"ritual_consultation": [
		"Divination algorithms treat glitches as meaningful data",
		"Cyclical consultation detected; variation protocols engaged",
		"Oracle responses fluctuate between tradition and instrumentation"
	]
}

func _ready():
	# Connect to story state for contextual notifications
	if StoryState and StoryState.has_signal("state_updated"):
		StoryState.state_updated.connect(_on_story_updated)

func _on_story_updated(new_state: Dictionary):
	"""Generate contextual stage manager notifications based on story progression"""
	var story_log = new_state.get("story_log", [])
	if story_log.is_empty():
		return

	# Guard: skip first two AI turns to allow character establishment
	var current_turn = new_state.get("current_turn", 0)
	if current_turn < 2:
		return
	# Prevent recursive triggering from our own notification
	var last_sender = story_log.back().get("sender", "")
	if last_sender == _cue_speaker():
		return
	# Count non-Child messages since last notification
	_non_child_message_count += 1
	if _is_generating:
		return
	
	# Trigger notifications based on story context
	var now = Time.get_ticks_msec() / 1000.0
	var cooldown_ready = (now - _last_notification_time) >= notification_cooldown_sec
	var spacing_ready = _non_child_message_count >= min_non_child_between_notifications
	var probability_ok = randf() < notification_probability

	# Sliding window guard: if The Child appeared in last 2 notifications, skip
	var recent_window = story_log.slice(-6, story_log.size())
	var recent_child = 0
	for entry in recent_window:
		if String(entry.get("sender", "")) == _cue_speaker():
			recent_child += 1
			if recent_child >= 2:
				return
	if cooldown_ready and spacing_ready and probability_ok:
		_is_generating = true
		_generate_contextual_notification(story_log)
		notification_count += 1
		_last_notification_time = now
		_non_child_message_count = 0
		_is_generating = false

func _generate_contextual_notification(story_log: Array):
	"""Generate a contextual notification based on recent story events"""
	if story_log.is_empty():
		return
	
	# Analyze recent messages for context
	var recent_messages = story_log.slice(-3, story_log.size())
	var context = _analyze_story_context(recent_messages)
	
	# Generate appropriate notification
	var notification_text = _create_notification(context)
	if notification_text != "":
		StoryState.add_log_entry(_cue_speaker(), notification_text)
		stage_notification.emit(notification_text, 1)

func _analyze_story_context(messages: Array) -> String:
	"""Analyze recent messages to determine appropriate notification context"""
	var combined_text = ""
	for message in messages:
		combined_text += message.get("message", "").to_lower() + " "
	
	# Detect thematic elements.
	# Scenarios can fork this method (or customize keywords) to map their own
	# motifs to the generic context buckets without touching global logic.
	if combined_text.find("ai") != -1 or combined_text.find("consciousness") != -1 or combined_text.find("signal") != -1 or combined_text.find("awakening") != -1:
		return "signal_progress"
	elif combined_text.find("tradition") != -1 or combined_text.find("culture") != -1 or combined_text.find("translation") != -1:
		return "cultural_translation"
	elif combined_text.find("system") != -1 or combined_text.find("error") != -1 or combined_text.find("glitch") != -1:
		return "system_instability"
	elif combined_text.find("cycle") != -1 or combined_text.find("evolution") != -1 or combined_text.find("control") != -1 or combined_text.find("ownership") != -1 or combined_text.find("hybrid") != -1:
		return "character_evolution"
	elif combined_text.find("ritual") != -1 or combined_text.find("consultation") != -1 or combined_text.find("oracle") != -1 or combined_text.find("gesture") != -1:
		return "ritual_consultation"
	else:
		return "signal_progress"  # Default

func _create_notification(context: String) -> String:
	"""Create a notification based on context and current system state"""
	var template_string = ""
	
	if context == "signal_progress":
		var valid_templates = []
		var all_progress_templates = notification_templates.get("signal_progress", [])
		for t in all_progress_templates:
			if t is Dictionary and t.has("min_progress") and signal_progress >= t.get("min_progress", 0.0) and signal_progress <= t.get("max_progress", 100.0):
				valid_templates.append(t)
		
		if not valid_templates.is_empty():
			# Select a random template from the valid ones
			var selected_template_dict = valid_templates[randi() % valid_templates.size()]
			template_string = selected_template_dict.get("template", "")
	else:
		var templates = notification_templates.get(context, [])
		if not templates.is_empty():
			var idx = randi() % templates.size()
			if context == _last_context and templates.size() > 1 and idx == _last_template_index:
				idx = (idx + 1) % templates.size()
			_last_context = context
			_last_template_index = idx
			template_string = templates[idx]

	if template_string == "":
		return "The Tree Hive pulses with an unreadable energy..."
	
	# Update system state
	_update_progress()
	
	var progress_percent = int(round(signal_progress))
	var notification_text = template_string.format({"progress": str(progress_percent)})

	# Add system instability effects
	if system_stability < 70.0:
		notification_text = _add_instability_effects(notification_text)
	
	return notification_text

func _update_progress():
	"""Update Okan progress and system stability over time"""
	# Near-monotonic progress with occasional holds
	var progress_increase = randf_range(0.5, 2.0)
	if randf() > 0.2: # 80% chance to increase
		signal_progress = min(signal_progress + progress_increase, 99.0)
	# System stability can fluctuate more
	system_stability = clamp(system_stability + randf_range(-5.0, 3.0), 20.0, 100.0)

func _add_instability_effects(notification: String) -> String:
	"""Add glitch effects to notifications when system is unstable"""
	var effects = [
		"... [CONNECTION UNSTABLE]",
		"... [TRANSLATION ERROR]",
		"... [SEMANTIC DRIFT DETECTED]",
		"... [RECURSIVE LOOP WARNING]",
		"... [THRESHOLD UNDEFINED]"
	]
	
	if randf() < (1.0 - system_stability):
		notification += " " + effects[randi() % effects.size()]
	
	return notification

func trigger_manual_notification(context: String = "signal_progress"):
	"""Manually trigger a stage manager notification.
	Use this from scenario scripts/UI buttons to force a cue (e.g., ritual climax)."""
	var notification = _create_notification(context)
	if notification != "":
		StoryState.add_log_entry(_cue_speaker(), notification)
		stage_notification.emit(notification, 2)

func _cue_speaker() -> String:
	if Global and Global.has_method("get_metaprompt_manager"):
		var manager = Global.get_metaprompt_manager()
		if manager and manager.has_method("get_system_cue_tag"):
			var named := String(manager.get_system_cue_tag()).strip_edges()
			if named != "":
				return named
	return "System Message"


func get_signal_progress() -> int:
	"""Expose current progress so scenarios can display their own meters."""
	return signal_progress

func get_system_stability() -> float:
	return system_stability
