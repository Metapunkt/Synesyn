extends SceneTree

const ContextActivationPolicyScript = preload(
	"res://addons/syntree/scripts/core/context_activation_policy.gd"
)
const ContextCompilerScript = preload(
	"res://addons/syntree/scripts/core/context_compiler.gd"
)

var _failures: Array[String] = []


func _init() -> void:
	_test_precedence()
	_test_conditions()
	_test_compiler_filtering()
	if _failures.is_empty():
		print("Context activation policy tests: all passed")
		quit(0)
		return
	for failure_message in _failures:
		push_error(failure_message)
	quit(1)


func _test_precedence() -> void:
	var policy: RefCounted = ContextActivationPolicyScript.new()
	var excluded: Dictionary = {
		"id": "excluded",
		"activation": {"mode": "excluded"},
	}
	_expect(
		not bool(policy.call(
			"evaluate",
			excluded,
			{},
			true,
			true,
			false
		).get("include", true)),
		"excluded mode did not omit a reachable entry"
	)
	_expect(
		bool(policy.call(
			"evaluate",
			excluded,
			{},
			false,
			false,
			true
		).get("include", false)),
		"explicit pin did not override excluded mode"
	)
	var rejected: Dictionary = excluded.duplicate(true)
	rejected["status"] = "rejected"
	_expect(
		not bool(policy.call(
			"evaluate",
			rejected,
			{},
			false,
			false,
			true
		).get("include", true)),
		"pin incorrectly overrode rejected review state"
	)


func _test_conditions() -> void:
	var policy: RefCounted = ContextActivationPolicyScript.new()
	var conditional: Dictionary = {
		"activation": {
			"mode": "conditional",
			"conditions": {
				"app_scope": "syntree",
				"tags": ["research"],
				"slots": {"phase": "review"},
			},
		},
	}
	var evaluation_context: Dictionary = {
		"app_scope": "syntree",
		"tags": ["research", "active"],
		"slots": {"phase": "review"},
	}
	_expect(
		bool(policy.call(
			"evaluate",
			conditional,
			evaluation_context,
			false,
			true,
			false
		).get("include", false)),
		"matching explicit activation conditions were rejected"
	)
	evaluation_context["app_scope"] = "scensyn"
	_expect(
		not bool(policy.call(
			"evaluate",
			conditional,
			evaluation_context,
			false,
			true,
			false
		).get("include", true)),
		"mismatched activation scope was included"
	)


func _test_compiler_filtering() -> void:
	var compiler: RefCounted = ContextCompilerScript.new()
	var document: Dictionary = {
		"nodes": [
			{
				"id": "entry",
				"label": "Entry",
				"annotations": {"content": "entry text"},
			},
			{
				"id": "always",
				"label": "Always",
				"annotations": {"content": "always text"},
				"activation": {"mode": "always"},
			},
			{
				"id": "hidden",
				"label": "Hidden",
				"annotations": {"content": "hidden text"},
				"activation": {"mode": "excluded"},
			},
		],
		"edges": [{
			"id": "entry-hidden",
			"from": "entry",
			"to": "hidden",
			"relation": "contains",
		}],
	}
	var context_set: Dictionary = {
		"id": "test-set",
		"entry_node_ids": ["entry"],
		"traversal_depth": 1,
		"allowed_relationship_types": [],
	}
	var result: Dictionary = compiler.call(
		"compile",
		document,
		context_set,
		{"preset": "balanced", "max_tokens": 100}
	)
	var included_ids: Array[String] = []
	for item_any in result.get("included_nodes", []):
		included_ids.append(str((item_any as Dictionary).get("node_id", "")))
	var omitted_ids: Array[String] = []
	for item_any in result.get("omitted_nodes", []):
		omitted_ids.append(str((item_any as Dictionary).get("node_id", "")))
	_expect(
		included_ids == ["entry", "always"],
		"compiler did not deterministically add always nodes"
	)
	_expect(
		omitted_ids == ["hidden"],
		"compiler did not explain activation omission"
	)


func _expect(condition: bool, failure_message: String) -> void:
	if not condition:
		_failures.append(failure_message)
