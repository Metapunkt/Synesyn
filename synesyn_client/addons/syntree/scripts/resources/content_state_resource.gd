## Purpose: ContentStateResource (script)
@tool
extends Resource
class_name ContentStateResource

# Load the script reference directly
const _ContentSourceResourceScript = preload("res://addons/syntree/scripts/resources/content_source_resource.gd")
const _ContentHierarchyOpsScript = preload("res://addons/syntree/scripts/resources/internal/content_hierarchy_ops.gd")
const _ContentStackOpsScript = preload("res://addons/syntree/scripts/resources/internal/content_stack_ops.gd")
const _ContentEdgePersistenceScript = preload("res://addons/syntree/scripts/resources/internal/content_edge_persistence.gd")
const _ContentStackOrderOpsScript = preload("res://addons/syntree/scripts/resources/internal/content_stack_order_ops.gd")
const _ContentRefreshOpsScript = preload("res://addons/syntree/scripts/resources/internal/content_refresh_ops.gd")
const _ContentNodePersistenceOpsScript = preload("res://addons/syntree/scripts/resources/internal/content_node_persistence_ops.gd")
const _ContextGraphEdgeStoreScript = preload("res://addons/syntree/scripts/resources/internal/context_graph_edge_store.gd")

# Compositional reference to content source - use Resource as base type
@export var content_source: Resource:
	set(value):
		content_source = value
		_wire_content_source_signals()

signal source_added(source_id: String)
signal source_deleted(source_id: String)
signal source_updated(source_id: String)
signal metaprompt_state_changed(source_id: String, is_metaprompt: bool)
signal active_state_changed(source_id: String, is_active: bool)
signal node_selected(node_id: String)
signal source_selected(source_id: String, selected: bool)

var _initialized: bool = false
var _content_source_signals_wired: bool = false
var _hierarchy_ops: Variant = null
var _stack_ops: Variant = null
var _edge_persistence: Variant = null
var _stack_order_ops: Variant = null
var _refresh_ops: Variant = null
var _node_persist_ops: Variant = null
var _context_graph_edge_store: Variant = null

func _wire_content_source_signals() -> void:
	if _content_source_signals_wired:
		return
	if not is_instance_valid(content_source):
		return
	# Only wire if the underlying resource exposes the expected signals.
	if content_source.has_signal("source_added") and not content_source.source_added.is_connected(_on_cs_source_added):
		content_source.source_added.connect(_on_cs_source_added)
	if content_source.has_signal("source_deleted") and not content_source.source_deleted.is_connected(_on_cs_source_deleted):
		content_source.source_deleted.connect(_on_cs_source_deleted)
	if content_source.has_signal("source_updated") and not content_source.source_updated.is_connected(_on_cs_source_updated):
		content_source.source_updated.connect(_on_cs_source_updated)
	if content_source.has_signal("metaprompt_state_changed") and not content_source.metaprompt_state_changed.is_connected(_on_cs_metaprompt_state_changed):
		content_source.metaprompt_state_changed.connect(_on_cs_metaprompt_state_changed)
	if content_source.has_signal("active_state_changed") and not content_source.active_state_changed.is_connected(_on_cs_active_state_changed):
		content_source.active_state_changed.connect(_on_cs_active_state_changed)
	_content_source_signals_wired = true

func _on_cs_source_added(source_id: String) -> void:
	source_added.emit(source_id)

func _on_cs_source_deleted(source_id: String) -> void:
	source_deleted.emit(source_id)

func _on_cs_source_updated(source_id: String) -> void:
	source_updated.emit(source_id)

func _on_cs_metaprompt_state_changed(source_id: String, is_metaprompt: bool) -> void:
	metaprompt_state_changed.emit(source_id, is_metaprompt)

func _on_cs_active_state_changed(source_id: String, is_active: bool) -> void:
	active_state_changed.emit(source_id, is_active)

# Stack composition constants (keep these stable; persisted keys depend on them)
const STACK_EDGES_KEY := "stack_edges"
const STACK_LAYOUT_KEY := "stack_layout"
const STACK_LAYOUT_POSITIONS_KEY := "node_positions"
const STACK_INCLUDE_UNWIRED_KEY := "include_unwired_nodes"
const COMPOSED_NODE_SEP := "__" # safe for Node.name and easy to split
const CONTEXT_GRAPH_EDGES_KEY := "context_graph_edges"
const STACK_CONTEXT_GRAPH_EDGES_KEY := "stack_context_graph_edges"

## --- Typed edge kinds (Graph + Hierarchy share one truth) ---
## "child": hierarchy containment + sibling order (stored in relationships.children + relationships.parents)
## "depends": ordering/flow constraint (stored in relationships.dependencies)
## "assoc": orthogonal association (stored in relationships.associations) (directed for now)
const EDGE_CHILD := "child"
const EDGE_DEPENDS := "depends"
const EDGE_ASSOC := "assoc"

const REL_PARENTS := "parents"
const REL_CHILDREN := "children"
const REL_DEPENDENCIES := "dependencies"
const REL_ASSOCIATIONS := "associations"

## --- Hierarchy reordering (used by SourceMenu Move Up/Down) ---
func move_hierarchy_node(node_id: String, delta: int, stack_context_id: String = "") -> Dictionary:
	# Returns {success: bool, error: String}
	# stack_context_id: if the display is a stack, pass its id here so we can reorder stack members
	var nid := String(node_id).strip_edges()
	if nid.is_empty():
		return {"success": false, "error": "Empty node id"}
	if delta == 0:
		return {"success": true, "error": ""}

	var parsed := parse_composed_node_id(nid)
	var src_id := ""
	var raw_id := nid
	if bool(parsed.get("is_composed", false)):
		src_id = String(parsed.get("source_id", "")).strip_edges()
		raw_id = String(parsed.get("node_id", "")).strip_edges()
	else:
		src_id = String(get_source_for_node(nid)).strip_edges()
		raw_id = String(nid).strip_edges()

	if src_id.is_empty():
		return {"success": false, "error": "Could not resolve owning source for node: %s" % nid}
	
	# Check if we're in a stack context and the node is a root of a member source
	var stack_id := String(stack_context_id).strip_edges()
	if not stack_id.is_empty() and is_stack_source(stack_id):
		var member_ids := get_stack_member_source_ids(stack_id)
		if member_ids.has(src_id):
			# Check if the raw_id is the root node of src_id
			var src_data := get_source_data(src_id)
			var nodes_any: Variant = src_data.get("content", {}).get("nodes", [])
			var is_root_node := false
			if nodes_any is Array:
				for n_any in (nodes_any as Array):
					if n_any is Dictionary:
						var n: Dictionary = n_any
						if String(n.get("node_id", "")).strip_edges() == raw_id:
							# Check if it's a root (no valid parents or is_root flag)
							var rel_v: Variant = n.get("relationships", {})
							var parents: Array = []
							if rel_v is Dictionary:
								var pv: Variant = (rel_v as Dictionary).get(REL_PARENTS, [])
								if pv is Array:
									parents = pv
							is_root_node = bool(n.get("is_root", false)) or parents.is_empty()
							break
			if is_root_node:
				# Reorder the stack's member sources instead
				return _move_stack_member_source(stack_id, src_id, delta)
	var d: Dictionary = get_source_data(src_id)
	if d.is_empty() or not (d.get("content", {}) is Dictionary) or not d.content.has("nodes") or not (d.content.nodes is Array):
		return {"success": false, "error": "Source has no nodes: %s" % src_id}

	# Normalize first so parents are consistent.
	var changed := false
	d = _normalize_graph_in_data(d, changed)
	var nodes: Array = d.content.nodes

	# Reorder via internal helper (no saving/signals).
	if _hierarchy_ops == null:
		_hierarchy_ops = _ContentHierarchyOpsScript.new()
	var res: Dictionary = (_hierarchy_ops as Object).call("move_node", nodes, raw_id, delta, REL_PARENTS, REL_CHILDREN)
	if not bool(res.get("success", false)):
		return {"success": false, "error": str(res.get("error", "Unknown error"))}
	if not bool(res.get("changed", false)):
		return {"success": true, "error": ""} # no-op at bounds
	d.content["nodes"] = res.get("nodes", nodes)

	# Persist and re-normalize for consistency
	var ok := update_source(src_id, d)
	if not ok:
		return {"success": false, "error": "update_source failed for: %s" % src_id}
	save_source(src_id)
	normalize_source_graph(src_id)
	return {"success": true, "error": ""}

func normalize_source_graph(source_id: String) -> bool:
	# Normalize graph structure for a source:
	# - Ensure relationships dict exists + arrays exist
	# - Remove stale refs
	# - Rebuild parents from children
	if source_id.is_empty():
		return false
	var sid := String(source_id).strip_edges()
	var d: Dictionary = get_source_data(sid)
	if d.is_empty():
		return false
	var changed := false
	var normalized := _normalize_graph_in_data(d, changed)
	if not changed:
		return true
	var ok := update_source(sid, normalized)
	if ok:
		save_source(sid)
	return ok

func _normalize_graph_in_data(d: Dictionary, changed_out: bool) -> Dictionary:
	var changed := changed_out
	if not d.has("content") or not (d.get("content") is Dictionary):
		return d
	var content: Dictionary = d.get("content")
	var nodes_any: Variant = content.get("nodes", [])
	if not (nodes_any is Array):
		content["nodes"] = []
		d["content"] = content
		changed = true
		return d
	var nodes: Array = nodes_any

	# Build id -> index map
	var id_to_index := {}
	for i in range(nodes.size()):
		var n_any: Variant = nodes[i]
		if not (n_any is Dictionary):
			continue
		var nid := str((n_any as Dictionary).get("node_id", "")).strip_edges()
		if nid.is_empty():
			continue
		id_to_index[nid] = i

	# Ensure relationships structure and remove stale refs
	for i in range(nodes.size()):
		var n_any: Variant = nodes[i]
		if not (n_any is Dictionary):
			continue
		var n: Dictionary = n_any
		if not n.has("relationships") or not (n.get("relationships") is Dictionary):
			n["relationships"] = {REL_PARENTS: [], REL_CHILDREN: [], REL_DEPENDENCIES: [], REL_ASSOCIATIONS: []}
			changed = true
		var rel: Dictionary = n.get("relationships") as Dictionary

		# Ensure arrays exist
		for k in [REL_PARENTS, REL_CHILDREN, REL_DEPENDENCIES, REL_ASSOCIATIONS]:
			var arr_any: Variant = rel.get(k, [])
			if not (arr_any is Array):
				rel[k] = []
				changed = true

		# Filter refs to valid ids and unique preserving order
		for k2 in [REL_PARENTS, REL_CHILDREN, REL_DEPENDENCIES, REL_ASSOCIATIONS]:
			var arr: Array = rel.get(k2, [])
			var seen := {}
			var out: Array = []
			for x_any in arr:
				var x := str(x_any).strip_edges()
				if x.is_empty():
					changed = true
					continue
				if not id_to_index.has(x):
					changed = true
					continue
				if seen.has(x):
					changed = true
					continue
				seen[x] = true
				out.append(x)
			rel[k2] = out

		n["relationships"] = rel
		nodes[i] = n

	# Rebuild parents from children (authoritative)
	var new_parents := {}
	for nid in id_to_index.keys():
		new_parents[nid] = []
	for i in range(nodes.size()):
		var n_any2: Variant = nodes[i]
		if not (n_any2 is Dictionary):
			continue
		var n2: Dictionary = n_any2
		var nid2 := str(n2.get("node_id", "")).strip_edges()
		if nid2.is_empty() or not id_to_index.has(nid2):
			continue
		var rel2: Dictionary = n2.get("relationships") as Dictionary
		var children: Array = rel2.get(REL_CHILDREN, [])
		for c_any in children:
			var cid := str(c_any).strip_edges()
			if cid.is_empty() or not new_parents.has(cid):
				continue
			var parr: Array = new_parents[cid]
			if not parr.has(nid2):
				parr.append(nid2)
				new_parents[cid] = parr

	for nid3 in new_parents.keys():
		var idx3 := int(id_to_index[nid3])
		var n_any3: Variant = nodes[idx3]
		if not (n_any3 is Dictionary):
			continue
		var n3: Dictionary = n_any3
		var rel3: Dictionary = n3.get("relationships") as Dictionary
		var old_parents: Array = rel3.get(REL_PARENTS, [])
		var rebuilt: Array = new_parents[nid3]
		if old_parents != rebuilt:
			rel3[REL_PARENTS] = rebuilt
			n3["relationships"] = rel3
			nodes[idx3] = n3
			changed = true

	content["nodes"] = nodes
	d["content"] = content
	changed_out = changed
	return d

func add_edge(kind: String, from_id: String, to_id: String) -> bool:
	_ensure_edge_persistence()
	return (_edge_persistence as Object).call(
		"mutate", self, kind, from_id, to_id, true, EDGE_CHILD,
		[REL_PARENTS, REL_CHILDREN, REL_DEPENDENCIES, REL_ASSOCIATIONS]
	)

func remove_edge(kind: String, from_id: String, to_id: String) -> bool:
	_ensure_edge_persistence()
	return (_edge_persistence as Object).call(
		"mutate", self, kind, from_id, to_id, false, EDGE_CHILD,
		[REL_PARENTS, REL_CHILDREN, REL_DEPENDENCIES, REL_ASSOCIATIONS]
	)

func _ensure_edge_persistence() -> void:
	if _edge_persistence == null:
		_edge_persistence = _ContentEdgePersistenceScript.new()

func _init() -> void:
	# Create content source resource if not provided
	if not content_source:
		content_source = _ContentSourceResourceScript.new()
	
	# Connect to content source signals
	_wire_content_source_signals()
	
	_initialized = true

func _connect_signals() -> void:
	# Back-compat shim: older code calls this. Keep it idempotent.
	_wire_content_source_signals()

## --- Stack composition API ---
func is_stack_source(source_id: String) -> bool:
	var d := get_source_data(source_id)
	return d.get("meta", {}).get("ai_context", {}).get("is_stack", false) == true

func get_stack_member_source_ids(stack_id: String) -> Array[String]:
	var d := get_source_data(stack_id)
	var arr = d.get("meta", {}).get("ai_context", {}).get("stack_sources", [])
	if arr is Array:
		var out: Array[String] = []
		for x in arr:
			if x == null:
				continue
			if x is Dictionary:
				# Current stack schema stores objects: {id,name,path}
				var sid := str(x.get("id", x.get("source_id", ""))).strip_edges()
				if not sid.is_empty():
					out.append(sid)
				continue
			var s := str(x).strip_edges()
			if not s.is_empty():
				out.append(s)
		return out
	return []

func _move_stack_member_source(stack_id: String, member_source_id: String, delta: int) -> Dictionary:
	# Reorder a member source within a stack's stack_sources array
	var d := get_source_data(stack_id)
	if d.is_empty():
		return {"success": false, "error": "Stack not found: %s" % stack_id}
	if _stack_ops == null:
		_stack_ops = _ContentStackOpsScript.new()
	var res: Dictionary = (_stack_ops as Object).call("reorder_stack_member_source", d, member_source_id, delta)
	if not bool(res.get("success", false)):
		return {"success": false, "error": str(res.get("error", "Unknown error"))}
	if not bool(res.get("changed", false)):
		return {"success": true, "error": ""} # no-op at bounds
	var nd: Dictionary = res.get("data", d)
	var ok := update_source(stack_id, nd)
	if not ok:
		return {"success": false, "error": "Failed to update stack: %s" % stack_id}
	save_source(stack_id)
	return {"success": true, "error": ""}

func make_composed_node_id(source_id: String, node_id: String) -> String:
	return "%s%s%s" % [source_id, COMPOSED_NODE_SEP, node_id]

func parse_composed_node_id(composed_id: String) -> Dictionary:
	var idx: int = composed_id.find(COMPOSED_NODE_SEP)
	if idx == -1:
		return {"is_composed": false, "source_id": "", "node_id": composed_id}
	return {
		"is_composed": true,
		"source_id": composed_id.substr(0, idx),
		"node_id": composed_id.substr(idx + COMPOSED_NODE_SEP.length())
	}

func get_stack_edges(stack_id: String) -> Array:
	var d: Dictionary = get_source_data(stack_id)
	var ai = d.get("meta", {}).get("ai_context", {})
	var edges = (ai as Dictionary).get(STACK_EDGES_KEY, []) if ai is Dictionary else []
	return edges if edges is Array else []

func get_stack_structural_edges(stack_id: String) -> Array:
	var structural_edges: Array = []
	for edge_any in get_stack_context_graph_edges(stack_id):
		if typeof(edge_any) != TYPE_DICTIONARY:
			continue
		var edge_data: Dictionary = edge_any
		if str(edge_data.get("relation", "")) == "contains":
			structural_edges.append({
				"from": edge_data.get("from", ""),
				"to": edge_data.get("to", ""),
			})
	return structural_edges

func set_stack_edges(stack_id: String, edges: Array) -> bool:
	var d: Dictionary = get_source_data(stack_id)
	if d.is_empty():
		return false
	if _stack_ops == null:
		_stack_ops = _ContentStackOpsScript.new()
	var res: Dictionary = (_stack_ops as Object).call("set_stack_edges_data", d, STACK_EDGES_KEY, edges)
	if not bool(res.get("success", false)):
		return false
	var nd: Dictionary = res.get("data", d)
	var ok: bool = update_source(stack_id, nd)
	if ok:
		save_source(stack_id)
	return ok

func add_stack_edge(stack_id: String, from_id: String, to_id: String) -> bool:
	var stack_data: Dictionary = get_source_data(stack_id)
	if stack_data.is_empty():
		return false
	if _stack_ops == null:
		_stack_ops = _ContentStackOpsScript.new()
	var result: Dictionary = (_stack_ops as Object).call(
		"add_stack_edge_data",
		stack_data,
		STACK_EDGES_KEY,
		from_id,
		to_id
	)
	if not bool(result.get("success", false)):
		return false
	if not bool(result.get("changed", false)):
		return true
	var updated_data: Dictionary = result.get("data", stack_data)
	var is_updated: bool = update_source(stack_id, updated_data)
	if is_updated:
		save_source(stack_id)
	return is_updated

func remove_stack_edge(stack_id: String, from_id: String, to_id: String) -> bool:
	var stack_data: Dictionary = get_source_data(stack_id)
	if stack_data.is_empty():
		return false
	if _stack_ops == null:
		_stack_ops = _ContentStackOpsScript.new()
	var result: Dictionary = (_stack_ops as Object).call(
		"remove_stack_edge_data",
		stack_data,
		STACK_EDGES_KEY,
		from_id,
		to_id
	)
	if not bool(result.get("success", false)):
		return false
	# Preserve the previous disconnect path: a valid request writes the resulting
	# edge array even when the requested edge was already absent.
	var updated_data: Dictionary = result.get("data", stack_data)
	var is_updated: bool = update_source(stack_id, updated_data)
	if is_updated:
		save_source(stack_id)
	return is_updated

func get_stack_layout_positions(stack_id: String) -> Dictionary:
	var d: Dictionary = get_source_data(stack_id)
	var ai = d.get("meta", {}).get("ai_context", {})
	var layout = (ai as Dictionary).get(STACK_LAYOUT_KEY, {}) if ai is Dictionary else {}
	if not (layout is Dictionary):
		return {}
	var pos = (layout as Dictionary).get(STACK_LAYOUT_POSITIONS_KEY, {})
	return pos if pos is Dictionary else {}

func set_stack_layout_position(stack_id: String, composed_node_id: String, position: Vector2) -> bool:
	var d: Dictionary = get_source_data(stack_id)
	if d.is_empty():
		return false
	if _stack_ops == null:
		_stack_ops = _ContentStackOpsScript.new()
	var res: Dictionary = (_stack_ops as Object).call("set_stack_layout_position_data", d, STACK_LAYOUT_KEY, STACK_LAYOUT_POSITIONS_KEY, composed_node_id, position)
	if not bool(res.get("success", false)):
		return false
	var nd: Dictionary = res.get("data", d)
	var ok: bool = update_source(stack_id, nd)
	if ok:
		save_source(stack_id)
	return ok

func get_stack_include_unwired_nodes(stack_id: String) -> bool:
	var d: Dictionary = get_source_data(stack_id)
	var ai = d.get("meta", {}).get("ai_context", {})
	if ai is Dictionary and (ai as Dictionary).has(STACK_INCLUDE_UNWIRED_KEY):
		return bool((ai as Dictionary).get(STACK_INCLUDE_UNWIRED_KEY, true))
	return true

func set_stack_include_unwired_nodes(stack_id: String, enabled: bool) -> bool:
	var d: Dictionary = get_source_data(stack_id)
	if d.is_empty():
		return false
	if _stack_ops == null:
		_stack_ops = _ContentStackOpsScript.new()
	var res: Dictionary = (_stack_ops as Object).call("set_stack_include_unwired_nodes_data", d, STACK_INCLUDE_UNWIRED_KEY, enabled)
	if not bool(res.get("success", false)):
		return false
	var nd: Dictionary = res.get("data", d)
	var ok: bool = update_source(stack_id, nd)
	if ok:
		save_source(stack_id)
	return ok

func get_stack_unwired_member_source_ids(stack_id: String) -> Array[String]:
	# A member source is “wired” if it appears in any cross-source stack edge (in or out).
	var members: Array[String] = get_stack_member_source_ids(stack_id)
	if members.is_empty():
		return []
	var edges: Array = get_stack_structural_edges(stack_id)
	if _stack_order_ops == null:
		_stack_order_ops = _ContentStackOrderOpsScript.new()
	return (_stack_order_ops as Object).call("compute_unwired_members", members, edges, COMPOSED_NODE_SEP)

func get_stack_unwired_member_count(stack_id: String) -> int:
	return get_stack_unwired_member_source_ids(stack_id).size()

func get_stack_ordered_member_source_ids(stack_id: String) -> Array[String]:
	# Deterministic ordering:
	# - if include_unwired_nodes=true: return a stable topological order of member-sources induced by stack edges,
	#   with unwired nodes appended in declared member order.
	# - if include_unwired_nodes=false: return only “wired” members (those in any cross-source edge), in topo order.
	var members: Array[String] = get_stack_member_source_ids(stack_id)
	if members.is_empty():
		return []
	var include_unwired := get_stack_include_unwired_nodes(stack_id)
	var edges: Array = get_stack_structural_edges(stack_id)
	if _stack_order_ops == null:
		_stack_order_ops = _ContentStackOrderOpsScript.new()
	return (_stack_order_ops as Object).call("compute_ordered_members", members, edges, include_unwired, COMPOSED_NODE_SEP)

# Resource API
func is_initialized() -> bool:
	return _initialized and content_source

# Forward properties from content source
var sources: Dictionary:
	get: return content_source.sources if content_source else {}

# Delegate methods to ContentSourceResource
func get_source_data(any_id: String) -> Dictionary:
	return content_source.get_source_data(any_id) if content_source else {}

func load_source_from_file(path: String) -> String:
	return content_source.load_source_from_file(path) if content_source else ""

func save_source(source_id: String) -> bool:
	return content_source.save_source(source_id) if content_source else false

func update_source(source_id: String, data: Dictionary) -> bool:
	return content_source.update_source(source_id, data) if content_source else false

func delete_source(source_id: String) -> bool:
	return content_source.delete_source(source_id) if content_source else false

# --- NEW: Wrapper for direct data add/update --- 
func add_or_update_source_data(source_data: Dictionary) -> String:
	return content_source.add_or_update_source_data(source_data) if content_source else ""
# --- END NEW WRAPPER --- 

func set_metaprompt_state(source_id: String, is_metaprompt: bool) -> bool:
	if not content_source:
		return false
	var sid := get_normalized_id(source_id)
	if sid.is_empty():
		sid = source_id
	var before: bool = get_metaprompt_state(sid)
	var ok: bool = bool(content_source.set_metaprompt_state(sid, is_metaprompt))
	if ok and before != is_metaprompt:
		metaprompt_state_changed.emit(sid, is_metaprompt)
	return ok

func get_metaprompt_state(source_id: String) -> bool:
	return content_source.get_metaprompt_state(source_id) if content_source else false

func get_normalized_id(any_id: String) -> String:
	return content_source.get_normalized_id(any_id) if content_source else ""

func get_source_for_node(node_id: String) -> String:
	if node_id.is_empty():
		return ""
		
	# First check the node_to_source_map if available
	if content_source and content_source.node_to_source_map.has(node_id):
		return content_source.node_to_source_map[node_id]

	# Support composed ids (stack graphs): "source__node"
	if node_id.contains(COMPOSED_NODE_SEP):
		var parsed: Dictionary = parse_composed_node_id(node_id)
		if parsed.get("is_composed", false) == true:
			var src := str(parsed.get("source_id", "")).strip_edges()
			if not src.is_empty() and has_source(src):
				return src
		
	# Fallback: Iterate through sources to find the node
	for source_id in sources:
		var source = sources[source_id]
		# Check if content exists AND is a Dictionary before accessing nodes
		if source.has("content") and source.content is Dictionary and source.content.has("nodes"):
			for node in source.content.nodes:
				if node is Dictionary and node.has("node_id") and node.node_id == node_id:
					return source_id
			
	return ""

func register_node_source_relationship(node_id: String, source_id: String) -> void:
	if content_source:
		content_source.register_node_source_relationship(node_id, source_id)

func has_source(source_id: String) -> bool:
	return content_source.has_source(source_id) if content_source else false

func initialize_content_sources(content_dir: String = "") -> Dictionary:
	return content_source.initialize_content_sources(content_dir) if content_source else {"success": false, "error": "Content source not initialized"}

func get_source_ids() -> Array:
	return content_source.get_source_ids() if content_source else []

func import_from_content_model(content_model: Node) -> void:
	if content_source:
		content_source.import_from_content_model(content_model)

func select_node(node_id: String) -> void:
	if node_id.is_empty():
		push_error("ContentStateResource: Cannot select node - empty node ID provided")
		return
		
	print("[SELECT] ContentStateResource.select_node called with: '%s'" % node_id)
	
	# Get the source ID for this node
	var source_id = get_source_for_node(node_id)
	print("[SELECT] get_source_for_node returned: '%s'" % source_id)
	if source_id.is_empty():
		push_error("ContentStateResource: Cannot select node - no source found for node: " + node_id)
		return
		
	# Emit signals for selection
	print("[SELECT] Emitting node_selected('%s')" % node_id)
	node_selected.emit(node_id)
	source_selected.emit(source_id, true)

func deselect_node(node_id: String) -> void:
	if node_id.is_empty():
		push_error("ContentStateResource: Cannot deselect node - empty node ID provided")
		return
		
	print("ContentStateResource: Deselecting node: " + node_id)
	
	# Get the source ID for this node
	var source_id = get_source_for_node(node_id)
	if source_id.is_empty():
		push_error("ContentStateResource: Cannot deselect node - no source found for node: " + node_id)
		return
		
	# Emit signal for deselection
	source_selected.emit(source_id, false)

# Add active source methods
func set_source_active_state(source_id: String, is_active: bool) -> bool:
	if not content_source:
		return false
	var sid := get_normalized_id(source_id)
	if sid.is_empty():
		sid = source_id
	var before: bool = get_source_active_state(sid)
	var ok: bool = bool(content_source.set_source_active_state(sid, is_active))
	if ok and before != is_active:
		active_state_changed.emit(sid, is_active)
	return ok

func get_source_active_state(source_id: String) -> bool:
	return content_source.get_source_active_state(source_id) if content_source else false

func get_active_sources() -> Array[String]:
	return content_source.get_active_sources() if content_source else [] 

func refresh_active_sources() -> Dictionary:
	if _refresh_ops == null:
		_refresh_ops = _ContentRefreshOpsScript.new()
	var active_sources: Array[String] = get_active_sources()
	# Provide an optional remote refresh callable if ContentBus exists in this runtime.
	var remote_cb := Callable()
	if Engine.has_singleton("ContentBus"):
		var bus = Engine.get_singleton("ContentBus")
		if bus and (bus as Object).has_method("trigger_remote_source_refresh"):
			remote_cb = Callable(bus, "trigger_remote_source_refresh")
	# Delegate loop to helper.
	return (_refresh_ops as Object).call("refresh_active_sources", active_sources, Callable(self, "get_source_data"), Callable(self, "update_source_content"), remote_cb)

func update_source_content(source_id: String, new_content: String) -> bool:
	"""
	Updates the content of a source while preserving its metadata and other properties.
	Returns true if successful, false otherwise.
	"""
	if not content_source:
		push_error("ContentStateResource: Cannot update source content - content source not initialized")
		return false
		
	var source_data = get_source_data(source_id)
	if source_data.is_empty():
		push_error("ContentStateResource: Cannot update source content - source not found: " + source_id)
		return false
		
	if _refresh_ops == null:
		_refresh_ops = _ContentRefreshOpsScript.new()
	var parsed: Dictionary = (_refresh_ops as Object).call("parse_updated_content", source_data, new_content)
	if not bool(parsed.get("success", false)):
		push_error("ContentStateResource: " + str(parsed.get("error", "Cannot update content")))
		return false
	var updated_content: Variant = parsed.get("updated_content")
	
	# Update the content while preserving metadata
	if source_data.has("content"):
		source_data["content"] = updated_content
	else:
		# If no content field exists, create it
		source_data["content"] = updated_content
	
	# Update the source
	if content_source.update_source(source_id, source_data):
		source_updated.emit(source_id)
		return true
	
	return false

## --- Graph persistence helpers (non-stack / member-editing path) ---
func remove_node_from_source(source_id: String, node_id: String) -> bool:
	var source_id_clean: String = source_id.strip_edges()
	var node_id_clean: String = node_id.strip_edges()
	if source_id_clean.is_empty() or node_id_clean.is_empty():
		return false
	var source_data: Dictionary = get_source_data(source_id_clean)
	if source_data.is_empty():
		return false
	var content_any: Variant = source_data.get("content", null)
	if typeof(content_any) != TYPE_DICTIONARY:
		return false
	var nodes_any: Variant = (content_any as Dictionary).get("nodes", null)
	if typeof(nodes_any) != TYPE_ARRAY:
		return false
	if _node_persist_ops == null:
		_node_persist_ops = _ContentNodePersistenceOpsScript.new()
	var relationship_keys: Array[String] = [REL_CHILDREN, REL_PARENTS]
	var result: Dictionary = (_node_persist_ops as Object).call(
		"remove_node_and_unlink",
		nodes_any,
		node_id_clean,
		relationship_keys
	)
	if not bool(result.get("success", false)):
		return false
	(content_any as Dictionary)["nodes"] = result.get("nodes", nodes_any)
	_ensure_context_graph_edge_store()
	var rich_edges_any: Variant = (content_any as Dictionary).get(
		CONTEXT_GRAPH_EDGES_KEY,
		[]
	)
	if typeof(rich_edges_any) == TYPE_ARRAY:
		(content_any as Dictionary)[CONTEXT_GRAPH_EDGES_KEY] = (
			(_context_graph_edge_store as Object).call(
				"remove_incident",
				rich_edges_any,
				node_id_clean
			)
		)
	source_data["content"] = content_any
	var is_updated: bool = update_source(source_id_clean, source_data)
	if not is_updated:
		return false
	save_source(source_id_clean)
	return normalize_source_graph(source_id_clean)

func update_node_position(node_id: String, position: Vector2) -> bool:
	if node_id.is_empty():
		return false
	# Support composed ids too (we only write into the owning source here).
	var parsed: Dictionary = parse_composed_node_id(node_id)
	var src: String = ""
	var nid: String = str(parsed.get("node_id", ""))
	if parsed.get("is_composed", false) == true:
		src = str(parsed.get("source_id", ""))
	else:
		src = get_source_for_node(node_id)
	if src.is_empty():
		return false
	var d: Dictionary = get_source_data(src)
	if d.is_empty():
		return false
	if not (d.get("content", {}) is Dictionary) or not d.content.has("nodes"):
		return false
	if _node_persist_ops == null:
		_node_persist_ops = _ContentNodePersistenceOpsScript.new()
	var nodes: Array = d.content.nodes
	var res: Dictionary = (_node_persist_ops as Object).call("set_node_position", nodes, nid, position)
	if not bool(res.get("success", false)):
		return false
	d.content["nodes"] = res.get("nodes", nodes)
	var ok: bool = update_source(src, d)
	if ok:
		save_source(src)
	return ok

func add_relationship(from_id: String, to_id: String) -> bool:
	# Back-compat: treat legacy relationship as a typed child edge.
	return add_edge(EDGE_CHILD, from_id, to_id)

func remove_relationship(from_id: String, to_id: String) -> bool:
	return remove_edge(EDGE_CHILD, from_id, to_id)


func get_context_graph_edges(
	source_id: String,
	include_legacy_projection: bool = true
) -> Array:
	_ensure_context_graph_edge_store()
	return (_context_graph_edge_store as Object).call(
		"get_source_edges",
		self,
		source_id,
		CONTEXT_GRAPH_EDGES_KEY,
		include_legacy_projection
	)


func upsert_context_graph_edge(source_id: String, edge_data: Dictionary) -> Dictionary:
	_ensure_context_graph_edge_store()
	return (_context_graph_edge_store as Object).call(
		"upsert_source_edge",
		self,
		source_id,
		CONTEXT_GRAPH_EDGES_KEY,
		edge_data
	)


func remove_context_graph_edge(source_id: String, edge_id: String) -> Dictionary:
	_ensure_context_graph_edge_store()
	return (_context_graph_edge_store as Object).call(
		"remove_source_edge",
		self,
		source_id,
		CONTEXT_GRAPH_EDGES_KEY,
		edge_id
	)


func get_stack_context_graph_edges(stack_id: String) -> Array:
	_ensure_context_graph_edge_store()
	return (_context_graph_edge_store as Object).call(
		"get_stack_source_edges",
		self,
		stack_id,
		STACK_CONTEXT_GRAPH_EDGES_KEY,
		STACK_EDGES_KEY
	)


func upsert_stack_context_graph_edge(
	stack_id: String,
	edge_data: Dictionary,
	node_ids: Array[String]
) -> Dictionary:
	_ensure_context_graph_edge_store()
	return (_context_graph_edge_store as Object).call(
		"upsert_stack_source_edge",
		self,
		stack_id,
		STACK_CONTEXT_GRAPH_EDGES_KEY,
		edge_data,
		node_ids
	)


func remove_stack_context_graph_edge(
	stack_id: String,
	edge_id: String
) -> Dictionary:
	_ensure_context_graph_edge_store()
	return (_context_graph_edge_store as Object).call(
		"remove_stack_source_edge",
		self,
		stack_id,
		STACK_CONTEXT_GRAPH_EDGES_KEY,
		edge_id
	)


func _ensure_context_graph_edge_store() -> void:
	if _context_graph_edge_store == null:
		_context_graph_edge_store = _ContextGraphEdgeStoreScript.new()
