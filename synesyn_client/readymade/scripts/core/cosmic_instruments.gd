# cosmic_instruments.gd
class_name CosmicInstruments
extends RefCounted
## Canonical Found Concepts cosmic-instrument vocabulary (ADR 0024).
## Accepts codes (RP/HF/IR/AH), hyphen/space variants, short names, and long names.

const CODE_RP := "RP"
const CODE_HF := "HF"
const CODE_IR := "IR"
const CODE_AH := "AH"

const NAME_RP := "Role Play (Dimensional Shifter)"
const NAME_HF := "Hypothetical Framings (Reality Benders)"
const NAME_IR := "Iterative Refinement (Gravitational Drift)"
const NAME_AH := "Abductive Hypothesis Generation (Quantum Reasoning)"

## Ordered instrument definitions used for matching and display.
static func definitions() -> Array[Dictionary]:
	return [
		{
			"code": CODE_RP,
			"name": NAME_RP,
			"aliases": [
				"rp",
				"role play",
				"role-play",
				"roleplaying",
				"role-playing",
				"role playing",
				"dimensional shifter",
				"dimensional-shifter",
			],
		},
		{
			"code": CODE_HF,
			"name": NAME_HF,
			"aliases": [
				"hf",
				"hypothetical",
				"hypothetical framings",
				"hypothetical-framings",
				"reality benders",
				"reality-benders",
			],
		},
		{
			"code": CODE_IR,
			"name": NAME_IR,
			"aliases": [
				"ir",
				"iterative",
				"iterative refinement",
				"iterative-refinement",
				"gravitational drift",
				"gravitational-drift",
			],
		},
		{
			"code": CODE_AH,
			"name": NAME_AH,
			"aliases": [
				"ah",
				"abductive",
				"abductive hypothesis",
				"abductive hypothesis generation",
				"quantum reasoning",
				"quantum-reasoning",
				"expert analysis",
			],
		},
	]


static func canonicalize(raw: String) -> String:
	"""Return ADR 0024 code (RP/HF/IR/AH) or empty string if unrecognized."""
	var normalized: String = _normalize(raw)
	if normalized.is_empty():
		return ""

	for definition in definitions():
		var code: String = String(definition.get("code", ""))
		if normalized == _normalize(code):
			return code
		if normalized == _normalize(String(definition.get("name", ""))):
			return code
		var aliases: Array = definition.get("aliases", [])
		for alias_any in aliases:
			var alias: String = _normalize(String(alias_any))
			if alias.is_empty():
				continue
			if normalized == alias or alias in normalized or normalized in alias:
				return code
	return ""


static func display_name(raw: String) -> String:
	"""Return the canonical long name for a code/alias, or the original trimmed text."""
	var code: String = canonicalize(raw)
	if code.is_empty():
		return raw.strip_edges()
	for definition in definitions():
		if String(definition.get("code", "")) == code:
			return String(definition.get("name", raw))
	return raw.strip_edges()


static func labeled_display(raw: String) -> String:
	"""Return 'CODE — Canonical Name' for pickers and summaries."""
	var code: String = canonicalize(raw)
	if code.is_empty():
		return raw.strip_edges()
	return "%s — %s" % [code, display_name(code)]


static func matches(raw: String, expected_code: String) -> bool:
	"""True when raw resolves to the expected ADR 0024 code."""
	return canonicalize(raw) == expected_code.to_upper().strip_edges()


static func _normalize(text: String) -> String:
	var value: String = text.strip_edges().to_lower()
	if value.is_empty():
		return ""
	# Collapse punctuation/hyphens to spaces, then squeeze whitespace.
	var cleaned: String = ""
	for i in range(value.length()):
		var ch: String = value[i]
		var codepoint: int = value.unicode_at(i)
		var is_alnum: bool = (
			(codepoint >= 97 and codepoint <= 122)
			or (codepoint >= 48 and codepoint <= 57)
		)
		if is_alnum:
			cleaned += ch
		else:
			cleaned += " "
	var parts: PackedStringArray = cleaned.split(" ", false)
	return " ".join(parts)
