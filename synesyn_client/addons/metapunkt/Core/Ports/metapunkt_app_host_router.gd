@tool
extends MetapunktAppHostBase
class_name MetapunktAppHostRouter

## MetapunktAppHostRouter (autoload contract at /root/MetapunktAppHost)
##
## Design goals:
## - There is exactly one deterministic autoload name: /root/MetapunktAppHost
## - Router should NOT be edited when new apps are added
## - Apps "install" themselves by providing a script with:
##   - `class_name <Something>`
##   - `extends MetapunktAppHostBase`
##   - `get_synterface_catalog()` returning NAMESPACED synterface IDs (e.g. `myapp.*`)
##   - `bind_synterfaces(...)`
## - Router auto-discovers all such global classes at runtime and routes binding per synterface id.

const _SynterfaceCatalog := preload("res://addons/metapunkt/Core/Ports/synterface_catalog.gd")
const _JsonSchemaValidator := preload("res://addons/metapunkt/Core/Ports/json_schema_validator.gd")

var _providers: Array[MetapunktAppHostBase] = []
var _impls_by_synterface: Dictionary = {} # synterface_id -> Array[Dictionary] (impl records)
var _synterface_status: Dictionary = {} # synterface_id -> {status, reason, schema_sig, catalog_entry, impl_ids}
var _merged_catalog: Dictionary = {} # synterface_id -> canonical catalog entry (for AgentRegistry existence checks)

var _overrides: Dictionary = {} # synterface_id -> impl_id
var _overrides_dirty: bool = false
var _overrides_path_abs: String = ""

var _user_synterfaces_path_abs: String = ""
var _user_synterfaces: Dictionary = {} # synterface_id -> entry dict {version,description,schema,binding}
var _user_synterfaces_dirty: bool = false
var _user_synterfaces_issues: Array = [] # [{synterface_id, error}]

var _slots_by_id: Dictionary = {} # slot_id -> Array[Dictionary] (provider slot records)
var _slot_catalog: Dictionary = {} # slot_id -> merged slot record (or conflict marker)
var _slot_conflicts: Array = [] # [{slot_id, providers:[...]}]
var _slot_assignments_path_abs: String = ""
var _slot_assignments: Dictionary = {} # slot_id -> agent_id

func _ready() -> void:
	_overrides_path_abs = _compute_overrides_path_abs()
	_user_synterfaces_path_abs = _compute_user_synterfaces_path_abs()
	_slot_assignments_path_abs = _compute_slot_assignments_path_abs()
	_overrides = _load_overrides(_overrides_path_abs)
	_user_synterfaces = _load_user_synterfaces(_user_synterfaces_path_abs)
	_slot_assignments = _load_slot_assignments(_slot_assignments_path_abs)
	_refresh_providers()

func get_app_id() -> String:
	# Router is project-level; apps identify themselves in their provider.
	return "synesyn"

func get_synterface_catalog() -> Dictionary:
	# Router returns merged app catalogs (core is handled by AgentRegistry separately).
	if _merged_catalog.is_empty():
		_refresh_providers()
	return _merged_catalog

func get_synterface_issues() -> Array:
	# Returns list of issues for UI:
	# - status: "conflict" (schemas differ), "multi" (multiple compatible impls)
	# - impls: [{impl_id, provider_id, provider_class, provider_path, schema_sig}]
	var out: Array = []
	for sid in _synterface_status.keys():
		var st_any: Variant = _synterface_status.get(sid)
		if typeof(st_any) != TYPE_DICTIONARY:
			continue
		var st: Dictionary = st_any
		var status := str(st.get("status", "")).strip_edges()
		if status != "conflict" and status != "multi":
			continue
		var item := {
			"synterface_id": str(sid),
			"status": status,
			"reason": str(st.get("reason", "")),
			"override": str(_overrides.get(str(sid), "")),
			"impls": []
		}
		var impls_any: Variant = _impls_by_synterface.get(str(sid))
		if typeof(impls_any) == TYPE_ARRAY:
			for impl_any in (impls_any as Array):
				if typeof(impl_any) != TYPE_DICTIONARY:
					continue
				var impl: Dictionary = impl_any
				(item["impls"] as Array).append({
					"impl_id": str(impl.get("impl_id", "")),
					"provider_id": str(impl.get("provider_id", "")),
					"provider_class": str(impl.get("provider_class", "")),
					"provider_path": str(impl.get("provider_path", "")),
					"schema_sig": str(impl.get("schema_sig", ""))
				})
		out.append(item)
	out.sort_custom(func(a, b): return str(a.get("synterface_id", "")) < str(b.get("synterface_id", "")))
	return out

func set_override(synterface_id: String, impl_id: String) -> Dictionary:
	var sid := synterface_id.strip_edges()
	var iid := impl_id.strip_edges()
	if sid.is_empty() or iid.is_empty():
		return {"ok": false, "error": "Missing synterface_id or impl_id"}
	var impls_any: Variant = _impls_by_synterface.get(sid)
	if typeof(impls_any) != TYPE_ARRAY:
		return {"ok": false, "error": "Unknown synterface id: %s" % sid}
	var ok := false
	for impl_any in (impls_any as Array):
		if typeof(impl_any) != TYPE_DICTIONARY:
			continue
		var impl: Dictionary = impl_any
		if str(impl.get("impl_id", "")).strip_edges() == iid:
			ok = true
			break
	if not ok:
		return {"ok": false, "error": "impl_id not valid for synterface '%s': %s" % [sid, iid]}
	_overrides[sid] = iid
	_overrides_dirty = true
	_save_overrides_now()
	return {"ok": true}

func clear_override(synterface_id: String) -> Dictionary:
	var sid := synterface_id.strip_edges()
	if sid.is_empty():
		return {"ok": false, "error": "Missing synterface_id"}
	_overrides.erase(sid)
	_overrides_dirty = true
	_save_overrides_now()
	return {"ok": true}

func get_overrides_path_abs() -> String:
	return _overrides_path_abs

func get_user_synterfaces_path_abs() -> String:
	return _user_synterfaces_path_abs

func get_user_synterfaces_catalog() -> Dictionary:
	# UX helper for non-dev customization:
	# {
	#   "synterfaces": {sid: {description, schema_sig}},
	#   "issues": [{synterface_id, error}]
	# }
	if _merged_catalog.is_empty() or _impls_by_synterface.is_empty():
		_refresh_providers()
	var out: Dictionary = {}
	for sid_any in _user_synterfaces.keys():
		var sid := str(sid_any).strip_edges()
		if sid.is_empty():
			continue
		var entry_any: Variant = _user_synterfaces.get(sid_any)
		if typeof(entry_any) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_any
		var schema_any: Variant = entry.get("schema")
		var schema: Dictionary = schema_any if typeof(schema_any) == TYPE_DICTIONARY else {}
		out[sid] = {
			"description": str(entry.get("description", "")).strip_edges(),
			"schema_sig": _stable_json(schema),
		}
	return {"synterfaces": out, "issues": _user_synterfaces_issues.duplicate(true)}

func get_user_synterfaces_issues() -> Array:
	if _merged_catalog.is_empty() or _impls_by_synterface.is_empty():
		_refresh_providers()
	return _user_synterfaces_issues.duplicate(true)

func get_slot_assignments_path_abs() -> String:
	return _slot_assignments_path_abs

func get_agent_slots_catalog() -> Dictionary:
	# Returns:
	# {
	#   "slots": { slot_id: <slot_record_or_conflict_marker> },
	#   "conflicts": [ {slot_id, providers:[{provider_id, provider_class, provider_path}]} ]
	# }
	if _slot_catalog.is_empty() and _slot_conflicts.is_empty():
		_refresh_providers()
	return {"slots": _slot_catalog, "conflicts": _slot_conflicts}

func get_slot_assignments() -> Dictionary:
	return _slot_assignments

func get_slot_assignment_issues() -> Dictionary:
	# Structural validation only (router-level):
	# - unknown slot ids present in saved assignments (e.g. provider removed/renamed)
	if _slot_catalog.is_empty() and _slot_conflicts.is_empty():
		_refresh_providers()
	var unknown: Array = []
	for k in _slot_assignments.keys():
		var sid := str(k).strip_edges()
		if sid.is_empty():
			continue
		if not _slot_catalog.has(sid):
			unknown.append(sid)
	unknown.sort()
	return {"unknown_slots": unknown}

func set_slot_assignment(slot_id: String, agent_id: String) -> Dictionary:
	var sid := slot_id.strip_edges()
	if sid.is_empty():
		return {"ok": false, "error": "Missing slot_id"}
	if _slot_catalog.is_empty() and _slot_conflicts.is_empty():
		_refresh_providers()
	# Must be a known, non-conflicted slot.
	if not _slot_catalog.has(sid):
		return {"ok": false, "error": "Unknown slot_id: %s" % sid}
	var rec_any: Variant = _slot_catalog.get(sid)
	if typeof(rec_any) != TYPE_DICTIONARY:
		return {"ok": false, "error": "Invalid slot catalog entry"}
	if bool((rec_any as Dictionary).get("conflict", false)):
		return {"ok": false, "error": "Slot id conflict: %s (resolve provider collision first)" % sid}
	var aid := agent_id.strip_edges()
	_slot_assignments[sid] = aid
	_save_slot_assignments_now()
	return {"ok": true}

func clear_slot_assignment(slot_id: String) -> Dictionary:
	var sid := slot_id.strip_edges()
	if sid.is_empty():
		return {"ok": false, "error": "Missing slot_id"}
	_slot_assignments.erase(sid)
	_save_slot_assignments_now()
	return {"ok": true}

func bind_synterfaces(required_synterfaces: Array, hints: Dictionary) -> Dictionary:
	if _merged_catalog.is_empty() or _impls_by_synterface.is_empty():
		_refresh_providers()

	var bound: Dictionary = {}
	var missing: Array = []

	# Group requested synterfaces by selected provider.
	var by_owner: Dictionary = {} # ObjectID (int) -> Array[String]
	var selected_impl_by_sid: Dictionary = {} # sid -> impl record
	var core_ids: Array = []

	var active_app_id := _infer_active_app_id(hints)

	for s in required_synterfaces:
		var sid := str(s).strip_edges()
		if sid.is_empty():
			continue

		# Core synterfaces (no owner) handled directly by router.
		if _SynterfaceCatalog.get_core_synterface_catalog_v1().has(sid):
			core_ids.append(sid)
			continue

		var pick := _select_impl_for_synterface(sid, active_app_id)
		if not bool(pick.get("ok", false)):
			missing.append(sid)
			continue
		var impl: Dictionary = pick.get("impl", {})
		selected_impl_by_sid[sid] = impl

		# Router-local, data-driven synterface binding (no provider call).
		if bool(impl.get("local", false)):
			var schema: Dictionary = impl.get("schema", {})
			var binding: Variant = impl.get("binding")
			if typeof(binding) != TYPE_DICTIONARY:
				missing.append(sid)
				continue
			if typeof(schema) == TYPE_DICTIONARY and not schema.is_empty():
				var vr = _JsonSchemaValidator.validate(binding, schema, "$.%s" % sid)
				if not bool(vr.get("ok", false)):
					push_warning("MetapunktAppHostRouter: local synterface '%s' binding invalid: %s" % [sid, str(vr.get("error", ""))])
					missing.append(sid)
					continue
			bound[sid] = binding
			continue

		var owner: MetapunktAppHostBase = impl.get("provider")
		if owner == null:
			missing.append(sid)
			continue
		var oid := owner.get_instance_id()
		if not by_owner.has(oid):
			by_owner[oid] = []
		(by_owner[oid] as Array).append(sid)

	# Bind core ids
	for cid in core_ids:
		var r := _bind_core_synterface(str(cid), hints)
		if not bool(r.get("ok", false)):
			missing.append(str(cid))
		else:
			bound[str(cid)] = r.get("binding", {})

	# Bind provider-owned ids (one call per provider)
	for oid_key in by_owner.keys():
		var owner: MetapunktAppHostBase = null
		for p in _providers:
			if p.get_instance_id() == int(oid_key):
				owner = p
				break
		if owner == null:
			continue
		var ids: Array = by_owner[oid_key]
		var res_any: Variant = owner.bind_synterfaces(ids, hints)
		if typeof(res_any) != TYPE_DICTIONARY:
			for sid2 in ids:
				missing.append(str(sid2))
			continue
		var res: Dictionary = res_any
		if not bool(res.get("ok", false)):
			# Provider returns missing list (optional); otherwise treat all as missing.
			var miss_any: Variant = res.get("missing")
			if typeof(miss_any) == TYPE_ARRAY:
				for m in miss_any:
					missing.append(str(m))
			else:
				for sid3 in ids:
					missing.append(str(sid3))
			continue
		var syn_any: Variant = res.get("synterfaces")
		if typeof(syn_any) != TYPE_DICTIONARY:
			for sid4 in ids:
				missing.append(str(sid4))
			continue
		var syn: Dictionary = syn_any
		for sid5 in ids:
			var key := str(sid5)
			if syn.has(key):
				# Validate against selected impl schema when available.
				var impl: Dictionary = selected_impl_by_sid.get(key, {})
				var schema: Dictionary = impl.get("schema", {})
				if typeof(schema) == TYPE_DICTIONARY and not schema.is_empty():
					var binding = syn[key]
					if typeof(binding) != TYPE_DICTIONARY:
						missing.append(key)
						continue
					var vr = _JsonSchemaValidator.validate(binding, schema, "$.%s" % key)
					if not bool(vr.get("ok", false)):
						push_warning("MetapunktAppHostRouter: binding invalid for '%s': %s" % [key, str(vr.get("error", ""))])
						missing.append(key)
						continue
				bound[key] = syn[key]
			else:
				missing.append(key)

	if not missing.is_empty():
		# Surface actionable hint if selection required.
		return {
			"ok": false,
			"missing": missing,
			"error": "Router could not bind required synterfaces: %s. If this is a conflict/multiple-implementation synterface, resolve it in Metapunkt UI (AgentDefs → Synterface Selection) and/or set an override at: %s" % [str(missing), _overrides_path_abs]
		}

	return {"ok": true, "synterfaces": bound}

func _bind_core_synterface(sid: String, hints: Dictionary) -> Dictionary:
	match sid:
		"conversation_io":
			return {
				"ok": true,
				"binding": {"kind": "service", "service": "metapunkt.conversation_io", "operations": ["chat", "tool_call"]}
			}
		"thread_scope":
			var scope := str(hints.get("thread_scope", "")).strip_edges()
			# Router cannot guess app default safely; require hint or explicit selection.
			if scope.is_empty():
				return {"ok": false}
			return {"ok": true, "binding": {"scope": scope}}
		"scene_root":
			# Conservative: bind to /root unless caller provides a more specific hint.
			var path := str(hints.get("scene_root_path", "/root")).strip_edges()
			if path.is_empty():
				path = "/root"
			return {"ok": true, "binding": {"kind": "path", "path": path, "label": "scene_root"}}
		"ui_hooks":
			# Router provides a generic envelope; apps can override by providing their own namespaced synterface.
			return {
				"ok": true,
				"binding": {"kind": "service", "service": "synesyn.ui_hooks", "operations": ["toast", "status"], "channels": ["toast", "status"]}
			}
		"workplan":
			# Workplan is app-specific; router can't assume.
			return {"ok": false}
		_:
			return {"ok": false}

func _refresh_providers() -> void:
	_providers.clear()
	_impls_by_synterface.clear()
	_synterface_status.clear()
	_merged_catalog.clear()
	_slots_by_id.clear()
	_slot_catalog.clear()
	_slot_conflicts.clear()

	# Discover all global classes that extend MetapunktAppHostBase.
	var list_any: Variant = ProjectSettings.get_global_class_list()
	if typeof(list_any) != TYPE_ARRAY:
		return
	var list: Array = list_any

	for e_any in list:
		if typeof(e_any) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = e_any
		var base := str(e.get("base", "")).strip_edges()
		if base != "MetapunktAppHostBase":
			continue
		var cls := str(e.get("class", "")).strip_edges()
		var path := str(e.get("path", "")).strip_edges()
		if cls.is_empty() or path.is_empty():
			continue
		# Avoid instantiating the router itself even if someone sets class_name on it.
		if cls == "MetapunktAppHostRouter":
			continue

		var scr := load(path)
		if scr == null:
			continue
		var inst = (scr as Script).new()
		if inst == null:
			continue
		if not (inst is MetapunktAppHostBase):
			continue

		var provider: MetapunktAppHostBase = inst
		add_child(provider)
		_providers.append(provider)

		# Slot declarations (optional)
		if provider.has_method("get_agent_slots"):
			var slots_any: Variant = provider.call("get_agent_slots")
			if typeof(slots_any) == TYPE_ARRAY:
				for s_any in (slots_any as Array):
					if typeof(s_any) != TYPE_DICTIONARY:
						continue
					var s: Dictionary = s_any
					var slot_id := str(s.get("slot_id", "")).strip_edges()
					if slot_id.is_empty():
						continue
					if slot_id.find(".") == -1:
						push_warning("MetapunktAppHostRouter: slot_id must be namespaced (ignored): %s" % slot_id)
						continue
					# Store as provider record (do not mutate provider's dict in place).
					var rec := s.duplicate(true)
					rec["provider_id"] = str(provider.get_app_id()).strip_edges()
					rec["provider_class"] = cls
					rec["provider_path"] = path
					if not _slots_by_id.has(slot_id):
						_slots_by_id[slot_id] = []
					(_slots_by_id[slot_id] as Array).append(rec)

		# Collect provider catalog entries (candidate implementations).
		var cat_any: Variant = provider.get_synterface_catalog()
		if typeof(cat_any) != TYPE_DICTIONARY:
			continue
		var cat: Dictionary = cat_any
		for sid_any in cat.keys():
			var sid := str(sid_any).strip_edges()
			if sid.is_empty():
				continue
			# Enforce namespacing: avoid providers claiming core synterfaces.
			if sid.find(".") == -1:
				push_warning("MetapunktAppHostRouter: provider '%s' published non-namespaced synterface '%s' (ignored)" % [provider.get_app_id(), sid])
				continue
			if _SynterfaceCatalog.get_core_synterface_catalog_v1().has(sid):
				push_warning("MetapunktAppHostRouter: provider '%s' attempted to override core synterface '%s' (ignored)" % [provider.get_app_id(), sid])
				continue

			var entry_any: Variant = cat[sid_any]
			var entry: Dictionary = entry_any if typeof(entry_any) == TYPE_DICTIONARY else {}
			var schema_any: Variant = entry.get("schema")
			var schema: Dictionary = schema_any if typeof(schema_any) == TYPE_DICTIONARY else {}
			var schema_sig := _stable_json(schema)

			var impl_id := "%s::%s::%s" % [str(provider.get_app_id()).strip_edges(), cls, sid]
			var impl := {
				"impl_id": impl_id,
				"provider": provider,
				"provider_id": str(provider.get_app_id()).strip_edges(),
				"provider_class": cls,
				"provider_path": path,
				"synterface_id": sid,
				"entry": entry,
				"schema": schema,
				"schema_sig": schema_sig
			}

			if not _impls_by_synterface.has(sid):
				_impls_by_synterface[sid] = []
			(_impls_by_synterface[sid] as Array).append(impl)

	# Load user-defined (data-driven) synterfaces from local storage.
	_user_synterfaces = _load_user_synterfaces(_user_synterfaces_path_abs)
	_user_synterfaces_issues = _validate_user_synterfaces(_user_synterfaces)
	for sid3 in _user_synterfaces.keys():
		var sid_u := str(sid3).strip_edges()
		if sid_u.is_empty():
			continue
		# Keep user synterfaces namespaced; forbid overriding core.
		if sid_u.find(".") == -1:
			push_warning("MetapunktAppHostRouter: user synterface must be namespaced (ignored): %s" % sid_u)
			continue
		if _SynterfaceCatalog.get_core_synterface_catalog_v1().has(sid_u):
			push_warning("MetapunktAppHostRouter: user synterface cannot override core (ignored): %s" % sid_u)
			continue
		var entry_any: Variant = _user_synterfaces.get(sid3)
		if typeof(entry_any) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_any
		var schema_any: Variant = entry.get("schema")
		var schema: Dictionary = schema_any if typeof(schema_any) == TYPE_DICTIONARY else {}
		var schema_sig := _stable_json(schema)
		var binding_any: Variant = entry.get("binding")
		var binding: Dictionary = binding_any if typeof(binding_any) == TYPE_DICTIONARY else {}
		var impl_id_u := "local::user_synterfaces::%s" % sid_u
		var impl_u := {
			"impl_id": impl_id_u,
			"provider": null,
			"provider_id": "local",
			"provider_class": "user_synterfaces",
			"provider_path": _user_synterfaces_path_abs,
			"synterface_id": sid_u,
			"entry": entry,
			"schema": schema,
			"schema_sig": schema_sig,
			"local": true,
			"binding": binding
		}
		if not _impls_by_synterface.has(sid_u):
			_impls_by_synterface[sid_u] = []
		(_impls_by_synterface[sid_u] as Array).append(impl_u)

func _validate_user_synterfaces(synterfaces: Dictionary) -> Array:
	# Returns an issues list: [{synterface_id, error}]
	var issues: Array = []
	for sid_any in synterfaces.keys():
		var sid := str(sid_any).strip_edges()
		if sid.is_empty():
			continue
		var entry_any: Variant = synterfaces.get(sid_any)
		if typeof(entry_any) != TYPE_DICTIONARY:
			issues.append({"synterface_id": sid, "error": "Entry must be a Dictionary"})
			continue
		var entry: Dictionary = entry_any
		if sid.find(".") == -1:
			issues.append({"synterface_id": sid, "error": "Synterface id must be namespaced (contain a '.')"})
			continue
		if _SynterfaceCatalog.get_core_synterface_catalog_v1().has(sid):
			issues.append({"synterface_id": sid, "error": "Cannot override core synterface id"})
			continue
		var schema_any: Variant = entry.get("schema")
		if schema_any != null and typeof(schema_any) != TYPE_DICTIONARY:
			issues.append({"synterface_id": sid, "error": "schema must be a Dictionary"})
			continue
		var binding_any: Variant = entry.get("binding")
		if typeof(binding_any) != TYPE_DICTIONARY:
			issues.append({"synterface_id": sid, "error": "binding must be a Dictionary"})
			continue
		var schema: Dictionary = schema_any if typeof(schema_any) == TYPE_DICTIONARY else {}
		if not schema.is_empty():
			var vr := _JsonSchemaValidator.validate(binding_any, schema, "$.%s" % sid)
			if not bool(vr.get("ok", false)):
				issues.append({"synterface_id": sid, "error": "Binding does not match schema: %s" % str(vr.get("error", ""))})
	return issues

	# After collecting candidates, compute canonical status + merged catalog entries.
	for sid2 in _impls_by_synterface.keys():
		var impls: Array = _impls_by_synterface[sid2]
		if impls.size() == 1:
			var one: Dictionary = impls[0]
			var entry: Dictionary = one.get("entry", {})
			_merged_catalog[sid2] = entry
			_synterface_status[sid2] = {
				"status": "ok",
				"reason": "",
				"schema_sig": str(one.get("schema_sig", "")),
				"impl_ids": [str(one.get("impl_id", ""))]
			}
			continue

		# Multiple implementations: compatible if schema_sig matches.
		var sigs: Dictionary = {} # schema_sig -> true
		for impl_any2 in impls:
			var impl2: Dictionary = impl_any2
			sigs[str(impl2.get("schema_sig", ""))] = true
		if sigs.keys().size() <= 1:
			# Compatible multi-impl: choose catalog entry from first (schema is shared).
			var first: Dictionary = impls[0]
			var entry3: Dictionary = first.get("entry", {})
			# annotate for UI/debug
			entry3 = entry3.duplicate(true)
			entry3["multi_impl"] = true
			entry3["implementations"] = impls.map(func(x): return str((x as Dictionary).get("impl_id", "")))
			_merged_catalog[sid2] = entry3
			_synterface_status[sid2] = {
				"status": "multi",
				"reason": "multiple compatible implementations",
				"schema_sig": str(first.get("schema_sig", "")),
				"impl_ids": entry3.get("implementations", [])
			}
		else:
			# Conflict: keep catalog entry present for existence checks, but clear schema so AgentRegistry won't validate.
			var base_entry: Dictionary = (impls[0] as Dictionary).get("entry", {})
			base_entry = base_entry.duplicate(true)
			base_entry["conflict"] = true
			base_entry["schema"] = {}
			base_entry["implementations"] = impls.map(func(x): return str((x as Dictionary).get("impl_id", "")))
			_merged_catalog[sid2] = base_entry
			_synterface_status[sid2] = {
				"status": "conflict",
				"reason": "multiple incompatible schemas",
				"schema_sig": "",
				"impl_ids": base_entry.get("implementations", [])
			}

	# Build slot catalog + conflict list.
	for slot_id_any in _slots_by_id.keys():
		var slot_id := str(slot_id_any).strip_edges()
		var recs: Array = _slots_by_id[slot_id_any]
		if recs.size() == 1:
			var rec: Dictionary = (recs[0] as Dictionary).duplicate(true)
			# annotate current assignment
			rec["assigned_agent_id"] = str(_slot_assignments.get(slot_id, "")).strip_edges()
			_slot_catalog[slot_id] = rec
		else:
			var providers: Array = []
			for r_any in recs:
				if typeof(r_any) != TYPE_DICTIONARY:
					continue
				var r: Dictionary = r_any
				providers.append({
					"provider_id": str(r.get("provider_id", "")),
					"provider_class": str(r.get("provider_class", "")),
					"provider_path": str(r.get("provider_path", ""))
				})
			_slot_conflicts.append({"slot_id": slot_id, "providers": providers})
			_slot_catalog[slot_id] = {"conflict": true, "slot_id": slot_id, "assigned_agent_id": str(_slot_assignments.get(slot_id, "")).strip_edges()}

func _select_impl_for_synterface(sid: String, active_app_id: String) -> Dictionary:
	var impls_any: Variant = _impls_by_synterface.get(sid)
	if typeof(impls_any) != TYPE_ARRAY:
		return {"ok": false}
	var impls: Array = impls_any
	if impls.is_empty():
		return {"ok": false}
	if impls.size() == 1:
		return {"ok": true, "impl": impls[0]}

	# Overrides win.
	var override_id := str(_overrides.get(sid, "")).strip_edges()
	if not override_id.is_empty():
		for impl_any in impls:
			var impl: Dictionary = impl_any
			if str(impl.get("impl_id", "")).strip_edges() == override_id:
				return {"ok": true, "impl": impl}

	# If compatible multi-impl, prefer active app provider; otherwise require selection.
	var st_any: Variant = _synterface_status.get(sid)
	var st: Dictionary = st_any if typeof(st_any) == TYPE_DICTIONARY else {}
	var status := str(st.get("status", "")).strip_edges()
	if status == "multi" and not active_app_id.is_empty():
		for impl_any2 in impls:
			var impl2: Dictionary = impl_any2
			if str(impl2.get("provider_id", "")).strip_edges() == active_app_id:
				return {"ok": true, "impl": impl2}

	# If we get here (multi but no active app match, or conflict), require explicit selection.
	return {"ok": false}

func _infer_active_app_id(hints: Dictionary) -> String:
	# 1) Explicit hint
	var any: Variant = hints.get("active_app_id")
	if typeof(any) == TYPE_STRING:
		var s := str(any).strip_edges()
		if not s.is_empty():
			return s
	# 2) ModeManager hook (if present)
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		var mm := tree.root.get_node_or_null("ModeManager")
		if mm and (mm as Object).has_method("get_active_app_id"):
			var r := str((mm as Object).call("get_active_app_id")).strip_edges()
			if not r.is_empty():
				return r
	# 3) Heuristic by current scene path (last resort; may still be ambiguous)
	if tree and tree.current_scene:
		var p := str(tree.current_scene.scene_file_path).to_lower()
		if p.find("/scensyn/") != -1:
			return "scensyn"
		if p.find("/readymade/") != -1:
			return "readymade"
	return ""

func _stable_json(v: Variant) -> String:
	match typeof(v):
		TYPE_DICTIONARY:
			var d: Dictionary = v
			var keys := d.keys()
			keys.sort()
			var parts: Array = []
			for k in keys:
				parts.append(_stable_json(k) + ":" + _stable_json(d[k]))
			return "{" + ",".join(parts) + "}"
		TYPE_ARRAY:
			var a: Array = v
			var parts2: Array = []
			for x in a:
				parts2.append(_stable_json(x))
			return "[" + ",".join(parts2) + "]"
		TYPE_STRING:
			return JSON.stringify(str(v))
		TYPE_BOOL:
			return "true" if bool(v) else "false"
		TYPE_INT, TYPE_FLOAT:
			return str(v)
		TYPE_NIL:
			return "null"
		_:
			# For schemas, we expect JSON-native types; stringify fallback.
			return JSON.stringify(str(v))

func _compute_overrides_path_abs() -> String:
	# Local-first, user-visible storage: Documents/Synesyn/synesyn/config/metapunkt/...
	var base := _compute_metapunkt_config_dir_abs()
	var dest: String = base.path_join("synterface_overrides.json")
	RuntimeConfig.migrate_file_if_needed(
		dest, ["user://metapunkt/synterface_overrides.json"]
	)
	return dest

func _compute_user_synterfaces_path_abs() -> String:
	var base := _compute_metapunkt_config_dir_abs()
	var dest: String = base.path_join("user_synterfaces.json")
	RuntimeConfig.migrate_file_if_needed(
		dest, ["user://metapunkt/user_synterfaces.json"]
	)
	return dest

func _compute_slot_assignments_path_abs() -> String:
	var base := _compute_metapunkt_config_dir_abs()
	var dest: String = base.path_join("slot_assignments.json")
	RuntimeConfig.migrate_file_if_needed(
		dest, ["user://metapunkt/slot_assignments.json"]
	)
	return dest

func _compute_metapunkt_config_dir_abs() -> String:
	var base: String = RuntimeConfig.get_metapunkt_data_dir()
	DirAccess.make_dir_recursive_absolute(base)
	return base

func _load_overrides(path_abs: String) -> Dictionary:
	if path_abs.is_empty():
		return {}
	if not FileAccess.file_exists(path_abs):
		return {}
	var f := FileAccess.open(path_abs, FileAccess.READ)
	if not f:
		return {}
	var txt := f.get_as_text()
	f.close()
	var parsed := JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var d: Dictionary = parsed
	var ov_any: Variant = d.get("overrides")
	return ov_any if typeof(ov_any) == TYPE_DICTIONARY else {}

func _save_overrides_now() -> void:
	if not _overrides_dirty:
		return
	_overrides_dirty = false
	var path_abs := _overrides_path_abs
	if path_abs.is_empty():
		return
	var base_dir := path_abs.get_base_dir()
	if not base_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(base_dir)
	var f := FileAccess.open(path_abs, FileAccess.WRITE)
	if not f:
		push_warning("MetapunktAppHostRouter: failed to write overrides: %s" % path_abs)
		return
	var payload := {"schema_version": "metapunkt.synterface_overrides.v1", "overrides": _overrides}
	f.store_string(JSON.stringify(payload, "\t"))
	f.close()

func _load_user_synterfaces(path_abs: String) -> Dictionary:
	if path_abs.is_empty():
		return {}
	if not FileAccess.file_exists(path_abs):
		# Create an empty starter file so non-dev users can discover/edit it.
		_save_user_synterfaces_now(path_abs, {})
		return {}
	var f := FileAccess.open(path_abs, FileAccess.READ)
	if not f:
		return {}
	var txt := f.get_as_text()
	f.close()
	var parsed := JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var d: Dictionary = parsed
	var syn_any: Variant = d.get("synterfaces")
	return syn_any if typeof(syn_any) == TYPE_DICTIONARY else {}

func _save_user_synterfaces_now(path_abs: String, synterfaces: Dictionary) -> void:
	if path_abs.is_empty():
		return
	var base_dir := path_abs.get_base_dir()
	if not base_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(base_dir)
	var f := FileAccess.open(path_abs, FileAccess.WRITE)
	if not f:
		push_warning("MetapunktAppHostRouter: failed to write user_synterfaces: %s" % path_abs)
		return
	var payload := {"schema_version": "metapunkt.user_synterfaces.v1", "synterfaces": synterfaces}
	f.store_string(JSON.stringify(payload, "\t"))
	f.close()

func _load_slot_assignments(path_abs: String) -> Dictionary:
	if path_abs.is_empty():
		return {}
	if not FileAccess.file_exists(path_abs):
		_save_slot_assignments_now()
		return {}
	var f := FileAccess.open(path_abs, FileAccess.READ)
	if not f:
		return {}
	var txt := f.get_as_text()
	f.close()
	var parsed := JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var d: Dictionary = parsed
	var m_any: Variant = d.get("assignments")
	return m_any if typeof(m_any) == TYPE_DICTIONARY else {}

func _save_slot_assignments_now() -> void:
	var path_abs := _slot_assignments_path_abs
	if path_abs.is_empty():
		return
	var base_dir := path_abs.get_base_dir()
	if not base_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(base_dir)
	var f := FileAccess.open(path_abs, FileAccess.WRITE)
	if not f:
		push_warning("MetapunktAppHostRouter: failed to write slot assignments: %s" % path_abs)
		return
	var payload := {"schema_version": "metapunkt.slot_assignments.v1", "assignments": _slot_assignments}
	f.store_string(JSON.stringify(payload, "\t"))
	f.close()


