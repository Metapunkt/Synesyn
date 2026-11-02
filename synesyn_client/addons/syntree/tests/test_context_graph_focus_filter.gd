extends SceneTree

const FocusFilterScript = preload(
	"res://addons/syntree/scripts/core/context_graph_focus_filter.gd"
)


func _init() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var filter_engine: RefCounted = FocusFilterScript.new()
	var document: Dictionary = {
		"nodes": [
			_node("root", "Root", true, "user_authored"),
			_node("child", "Child evidence", true, "imported_quotation"),
			_node("grandchild", "Grandchild", false, "ai_inference"),
			_node("unrelated", "Other", true, "user_authored"),
		],
		"edges": [
			_edge("root-child", "root", "child", "contains"),
			_edge("child-grand", "child", "grandchild", "supports"),
		],
	}
	var focused: Dictionary = filter_engine.call("evaluate", document, {
		"search_text": "",
		"focus_node_id": "root",
		"focus_depth": 1,
		"show_inactive": true,
		"show_rejected": false,
		"show_low_confidence": true,
		"show_unrelated": false,
	})
	var collapsed: Dictionary = filter_engine.call("evaluate", document, {
		"collapsed_node_ids": ["root"],
		"show_inactive": true,
		"show_rejected": false,
		"show_low_confidence": true,
		"show_unrelated": true,
	})
	var filtered: Dictionary = filter_engine.call("evaluate", document, {
		"search_text": "evidence",
		"authorship_kinds": ["imported_quotation"],
		"show_inactive": true,
		"show_rejected": false,
		"show_low_confidence": true,
		"show_unrelated": true,
	})
	var did_pass: bool = (
		focused.get("visible_node_ids", []) == ["child", "root"]
		and collapsed.get("visible_node_ids", []) == [
			"grandchild",
			"root",
			"unrelated",
		]
		and filtered.get("visible_node_ids", []) == ["child"]
	)
	if did_pass:
		print("Context graph focus filter tests: all passed")
		quit(0)
		return
	push_error(
		"Context Graph focus/filter result was not deterministic: %s"
		% JSON.stringify({
			"focused": focused,
			"collapsed": collapsed,
			"filtered": filtered,
		})
	)
	quit(1)


func _node(
	node_id: String,
	label_text: String,
	is_active: bool,
	authorship_kind: String
) -> Dictionary:
	return {
		"id": node_id,
		"label": label_text,
		"status": "committed",
		"annotations": {"is_active": is_active, "tags": []},
		"activation": {"mode": "when_relevant"},
		"provenance": {"authorship_kind": authorship_kind},
	}


func _edge(
	edge_id: String,
	from_id: String,
	to_id: String,
	relation_id: String
) -> Dictionary:
	return {
		"id": edge_id,
		"from": from_id,
		"to": to_id,
		"relation": relation_id,
		"confidence": 1.0,
	}
