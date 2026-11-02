extends RefCounted
class_name ScenSynPromptBudget

# Scope-keyed in-memory cache used by callers that want to avoid recomputing
# expensive prompt fragments — e.g. a rendered metaprompt prefix that only
# changes when (scenario, theme, phase) change.
#
# Callers compute a `scope_token` from whatever inputs make the cached value
# valid; we never auto-invalidate. This is intentional: invalidation lives with
# the code that knows when its inputs changed, so cache freshness is not a
# hidden behavior here.
#
# Per-call prompt-size visibility is handled directly in ConversationManager
# (one short `[budget] <role> <chars> (<model>)` line per chat call). There is
# no flag to enable, no config to remember, and no separate telemetry surface.

var _memo: Dictionary = {} # key -> {"value": Variant, "scope_token": String}

# Look up a memoized value. Returns null when missing OR when the scope_token
# differs from the value cached under this key (so a stale entry never wins).
func memo_get(key: String, scope_token: String) -> Variant:
	if not _memo.has(key):
		return null
	var entry_any: Variant = _memo.get(key)
	if typeof(entry_any) != TYPE_DICTIONARY:
		return null
	var entry: Dictionary = entry_any
	if str(entry.get("scope_token", "")) != scope_token:
		return null
	return entry.get("value")

func memo_set(key: String, scope_token: String, value: Variant) -> void:
	_memo[key] = {"value": value, "scope_token": scope_token}

# Drop every entry whose key starts with `prefix` — useful when the scenario or
# theme changes and you want to clear everything that depended on it.
func memo_invalidate_prefix(prefix: String) -> int:
	var removed: int = 0
	for k_any in _memo.keys():
		var k: String = String(k_any)
		if k.begins_with(prefix):
			_memo.erase(k)
			removed += 1
	return removed

func memo_clear() -> void:
	_memo.clear()

# Build a stable scope_token from a list of strings. Use as:
#   var token := ScenSynPromptBudget.build_scope_token([scenario_id, theme, phase])
static func build_scope_token(parts: Array) -> String:
	var pieces: Array[String] = []
	for p_any in parts:
		pieces.append(str(p_any).strip_edges())
	return "|".join(pieces)
