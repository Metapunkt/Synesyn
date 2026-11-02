## Purpose: Normalize auditable Context Graph provenance without inference.
extends RefCounted

const AUTHORSHIP_KINDS: Array[String] = [
	"imported_quotation",
	"user_authored",
	"deterministic_summary",
	"ai_summary",
	"ai_inference",
	"unknown",
]
const REVIEW_STATUSES: Array[String] = [
	"unreviewed",
	"reviewed",
	"needs_review",
	"unknown",
]
const EVIDENCE_STATUSES: Array[String] = [
	"unsupported",
	"supported",
	"conflicting",
	"unknown",
]


func normalize(
	provenance: Dictionary,
	fallback_origin_ref: String = "unknown"
) -> Dictionary:
	var source_location: Dictionary = {}
	var location_any: Variant = provenance.get("source_location", {})
	if typeof(location_any) == TYPE_DICTIONARY:
		source_location = (location_any as Dictionary).duplicate(true)
	var normalized: Dictionary = {
		"authorship_kind": _enum_value(
			provenance.get("authorship_kind", "unknown"),
			AUTHORSHIP_KINDS,
			"unknown"
		),
		"origin_ref": str(provenance.get(
			"origin_ref",
			fallback_origin_ref
		)).strip_edges(),
		"source_location": source_location,
		"source_artifact_id": str(
			provenance.get("source_artifact_id", "")
		).strip_edges(),
		"source_version_id": str(
			provenance.get("source_version_id", "")
		).strip_edges(),
		"author_id": str(
			provenance.get("author_id", "")
		).strip_edges(),
		"produced_by": str(
			provenance.get("produced_by", "")
		).strip_edges(),
		"model_id": str(provenance.get("model_id", "")).strip_edges(),
		"created_at": str(
			provenance.get("created_at", "")
		).strip_edges(),
		"derivation_refs": _unique_strings(
			provenance.get("derivation_refs", [])
		),
		"review_status": _enum_value(
			provenance.get("review_status", "unknown"),
			REVIEW_STATUSES,
			"unknown"
		),
		"evidence_status": _enum_value(
			provenance.get("evidence_status", "unknown"),
			EVIDENCE_STATUSES,
			"unknown"
		),
	}
	if str(normalized.get("origin_ref", "")).is_empty():
		normalized["origin_ref"] = "unknown"
	return normalized


func refs(provenance: Dictionary) -> Array[String]:
	var normalized: Dictionary = normalize(provenance)
	var result: Array[String] = []
	var origin_ref: String = str(normalized.get("origin_ref", ""))
	if origin_ref != "unknown":
		result.append(origin_ref)
	for derivation_ref in normalized.get("derivation_refs", []):
		var ref_text: String = str(derivation_ref)
		if not result.has(ref_text):
			result.append(ref_text)
	return result


func _enum_value(
	value: Variant,
	allowed_values: Array[String],
	fallback: String
) -> String:
	var value_id: String = str(value).strip_edges().to_lower()
	return value_id if allowed_values.has(value_id) else fallback


func _unique_strings(values: Variant) -> Array[String]:
	var result: Array[String] = []
	if typeof(values) != TYPE_ARRAY:
		return result
	for value_any in values:
		var value_text: String = str(value_any).strip_edges()
		if not value_text.is_empty() and not result.has(value_text):
			result.append(value_text)
	return result
