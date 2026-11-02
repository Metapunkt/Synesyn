extends Resource
class_name PhaseIntentNarration

# Dictionary: intent_id -> context_key -> Array of lines (with placeholders)
var lines := {
	"SET_SCENE_TRANSITION": {
		"introduction": [
			"As the sun rises, the group prepares for a new beginning.",
			"Morning light fills the room as the introduction phase draws to a close."
		],
		"crisis": [
			"The tension in the air thickens as the crisis phase begins.",
			"With the city in turmoil, the group braces for the challenges ahead."
		],
		"default": [
			"The meeting shifts as new priorities come into focus.",
			"A sense of anticipation fills the room as the story moves forward."
		]
	},
	"ESCALATE_TENSION": {
		"day": [
			"Under the harsh daylight, every setback feels magnified.",
			"The group squints at the bright screens, tension mounting with each minute."
		],
		"night": [
			"Shadows lengthen as night falls, amplifying the group's anxiety.",
			"The darkness outside mirrors the uncertainty within the room."
		],
		"storm": [
			"Thunder rattles the windows, echoing the crisis inside.",
			"A storm rages outside, but the real turmoil is within these walls."
		],
		"default": [
			"Tension mounts as the crisis intensifies.",
			"A sense of urgency sweeps through the group."
		]
	},
	"ADVANCE_STORY": {
		"default": [
			"The story moves forward as the group weighs their options.",
			"A new idea sparks discussion among the team.",
			"The group considers their next move carefully.",
			"After {last_choice}, the group wonders what will come next.",
			"{player_name} suggests {last_action}, shifting the conversation."
		]
	},
	"GROUP_MORALE_HIGH": [
		"The group radiates confidence, their teamwork stronger than ever.",
		"Laughter and optimism fill the room, fueling creative solutions.",
		"A sense of unity empowers the team to tackle any challenge.",
		"Encouragement and praise are freely given, boosting spirits.",
		"The group celebrates small victories, building momentum.",
		"Collaboration comes easily as trust and goodwill abound.",
		"A positive atmosphere sparks new ideas and bold plans.",
		"The team's determination is matched by their camaraderie.",
		"Confidence is contagious, inspiring everyone to contribute.",
		"The group's high morale turns obstacles into opportunities."
	],
	"GROUP_MORALE_LOW": [
		"A heavy mood hangs over the group, making progress difficult.",
		"Doubt and frustration creep in, slowing the team's momentum.",
		"The group struggles to find common ground as morale dips.",
		"Fatigue and discouragement are evident in every conversation.",
		"A sense of defeat lingers, sapping energy and focus.",
		"Tension rises as hope gives way to resignation.",
		"The team's usual spark is missing, replaced by uncertainty.",
		"Attempts at encouragement fall flat, leaving silence in their wake.",
		"The group's low spirits make even simple tasks seem daunting.",
		"A lack of enthusiasm threatens to stall the group's efforts."
	]
}

func get_random_line(intent_id: String, context_key: String, placeholders := {}):
	if lines.has(intent_id):
		var ctxs = lines[intent_id]
		var arr = []
		if ctxs.has(context_key):
			arr = ctxs[context_key]
		elif ctxs.has("default"):
			arr = ctxs["default"]
		if arr.size() > 0:
			var line = arr[randi() % arr.size()]
			for k in placeholders.keys():
				line = line.replace("{" + k + "}", str(placeholders[k]))
			return line
	return "" 