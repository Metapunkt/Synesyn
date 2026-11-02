extends RefCounted
class_name WorkshopComparePathsMount

const ComparePathsControllerScript = preload(
	"res://ScenSyn/session_types/workshop_catalyst/workshop_compare_paths_controller.gd"
)


static func mount(
	workspace_controller: RefCounted,
	hub_client: Object,
	record_store: RefCounted,
	session_id: String,
	scenario_id: String,
	saved_state: Dictionary,
	state_changed_callback: Callable
) -> RefCounted:
	if not workspace_controller:
		return null
	var panel_node: Control = workspace_controller.get_control("WorkshopComparePaths")
	if not panel_node:
		push_error("WorkshopCatalystController: Compare Paths panel is unavailable.")
		return null
	var closure_bus: Object = null
	if Global:
		closure_bus = Global.get_closure_bus() as Object
	var controller: RefCounted = ComparePathsControllerScript.new()
	controller.state_changed.connect(state_changed_callback)
	if not controller.mount(
		panel_node,
		hub_client,
		closure_bus,
		record_store,
		session_id,
		scenario_id,
		saved_state
	):
		push_error("WorkshopCatalystController: Compare Paths failed to mount.")
		return null
	return controller
