extends RefCounted
class_name SessionTypeRuntimeProfile

## Generic turn-presentation profile. Product-specific generation remains owned
## by the selected Session Type module.

const VISIBLE_ENSEMBLE := "visible_ensemble"
const HIDDEN_SYNTHESIS := "hidden_synthesis"

const _PROFILES: Dictionary = {
	"story_catalyst": VISIBLE_ENSEMBLE,
	"workshop_catalyst": HIDDEN_SYNTHESIS,
}


static func for_session_type(session_type_id: String) -> String:
	return String(_PROFILES.get(session_type_id.strip_edges(), VISIBLE_ENSEMBLE))


static func is_supported(profile_id: String) -> bool:
	return profile_id == VISIBLE_ENSEMBLE or profile_id == HIDDEN_SYNTHESIS
