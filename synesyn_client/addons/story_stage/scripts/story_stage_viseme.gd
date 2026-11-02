class_name StoryStageViseme
extends RefCounted

## Shared viseme names for 2D mouth sheets and a later 3D presenter.


static func canonical(name: String) -> String:
	match name:
		"open", "mouth_a":
			return "open"
		"wide", "mouth_e":
			return "wide"
		"round", "mouth_o", "mouth_u":
			return "round"
		"lips_closed", "mouth_m", "mouth_b", "mouth_p":
			return "lips_closed"
		"teeth", "mouth_s", "mouth_f":
			return "teeth"
		_:
			return "rest"


static func from_intensity(intensity: float) -> String:
	if intensity > 0.66:
		return "wide"
	if intensity > 0.22:
		return "open"
	return "rest"
