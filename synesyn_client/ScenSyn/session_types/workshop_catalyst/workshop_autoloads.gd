extends RefCounted
class_name WorkshopAutoloads

## Resolves autoloads through the scene tree instead of by their bare global names.
##
## `godot --headless --script` does not register project autoloads, so a file containing a
## bare `Network` or `StoryState` fails to *compile* under it. The failure is quiet and
## expensive: the preloaded script comes back empty, `new()` returns null, the test's `_run`
## abandons before reaching an assertion, and the harness still prints "all passed". Three
## Workshop Catalyst tests were reporting green that way while verifying nothing.
##
## Behaviour is identical once the autoloads exist — this only changes *when* the name is
## resolved, from compile time to call time. Callers keep their existing null guards, because
## a missing autoload still has to mean "no multiplayer session" rather than a crash.

static func get_node_by_name(autoload_name: String) -> Node:
	var main_loop: SceneTree = Engine.get_main_loop() as SceneTree
	if not main_loop or not main_loop.root:
		return null
	return main_loop.root.get_node_or_null(autoload_name)


static func network() -> Node:
	return get_node_by_name("Network")


static func story_state() -> Node:
	return get_node_by_name("StoryState")


## The workshop presence sync node, or null when there is no networked session. Every caller
## treats null as "act locally", so this collapses the repeated has_method dance.
static func workshop_presence() -> Node:
	var network_node: Node = network()
	if not network_node or not network_node.has_method("get_workshop_presence"):
		return null
	return network_node.call("get_workshop_presence")


## True only for a live ENet session. False when Network is absent, which is what a
## single-machine session and a headless test both look like.
static func is_enet_session() -> bool:
	var network_node: Node = network()
	if not network_node or not network_node.has_method("is_enet_session"):
		return false
	return bool(network_node.call("is_enet_session"))
