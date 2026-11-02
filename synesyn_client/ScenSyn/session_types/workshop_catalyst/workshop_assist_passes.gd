extends RefCounted
class_name WorkshopAssistPasses

## The two on-demand model passes a Workshop Catalyst facilitator can ask for: orientation
## suggestions for untagged claims (REQ-CA-004) and drafted answers to the Closure Audit's steps
## (REQ-CA-021).
##
## Both live here rather than in the map controller for the same reason: a controller with model
## access of its own could be made to run a pass from anywhere, and neither of these should ever
## happen as a side effect of ordinary facilitation. Routing them through the session controller
## means a pass exists only because somebody pressed for one.
##
## They live here rather than *in* the session controller because that file is held to 900 lines
## by its own test, and two async handlers with their own preloads is exactly the kind of weight
## that limit exists to keep out of it.
##
## Neither pass writes anything. Each hands its result back to the map controller, which holds
## it as a proposal until a human acts on it.

const OrientationSuggesterScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_orientation_suggester.gd"
)
const AuditSuggesterScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_closure_audit_suggester.gd"
)


## The map controller is re-checked after the await: a pass outlives a panel that is torn down
## mid-request, and applying a result to a freed controller is a crash rather than a stale read.
static func run_orientation_pass(map_controller: RefCounted, claims: Array) -> void:
	var conversation: Variant = Global.get_conversation_manager() if Global else null
	var suggester: RefCounted = OrientationSuggesterScript.new()
	var result: Dictionary = await suggester.request(conversation, claims)
	if map_controller:
		map_controller.apply_orientation_suggestions(result)


static func run_audit_pass(map_controller: RefCounted, request: Dictionary) -> void:
	var conversation: Variant = Global.get_conversation_manager() if Global else null
	var suggester: RefCounted = AuditSuggesterScript.new()
	var result: Dictionary = await suggester.request(
		conversation,
		request.get("claims", []),
		request.get("findings", {}),
		request.get("thin_quadrants", []),
		String(request.get("decision", ""))
	)
	if map_controller:
		map_controller.apply_audit_suggestions(result)
