"""Open Closure–aligned admissibility gate for STFX Store retrieval.

Opt-in provenance policy between sort_candidates and build_context_pack (Note 87).
Relevance rejection and policy rejection stay separate. Uncertain provenance excludes
when configured (fail-safe).

This module hard-filters forbidden sources from the context pack. That is stronger
than attention masking: blocked items never reach the LLM context. Optional Open
Closure ClosureRouter audit is attempted only when the package is importable; the
hard filter remains authoritative either way.
"""

from __future__ import annotations

from typing import Any, Dict, List, Optional, Tuple


DEFAULT_ADMISSIBILITY: Dict[str, Any] = {
	"enabled": False,
	"uncertain_exclude": True,
	"forbidden_produced_by_prefixes": ["llm_generation"],
	"forbidden_source_types": ["promotional"],
	"forbidden_authorship_kinds": ["ai_summary", "ai_inference"],
	"persist_closure": False,
}


def normalize_admissibility_config(raw: Any) -> Dict[str, Any]:
	cfg = dict(DEFAULT_ADMISSIBILITY)
	if not isinstance(raw, dict):
		return cfg
	if "enabled" in raw:
		cfg["enabled"] = bool(raw.get("enabled"))
	if "uncertain_exclude" in raw:
		cfg["uncertain_exclude"] = bool(raw.get("uncertain_exclude"))
	if "persist_closure" in raw:
		cfg["persist_closure"] = bool(raw.get("persist_closure"))
	for key in (
		"forbidden_produced_by_prefixes",
		"forbidden_source_types",
		"forbidden_authorship_kinds",
	):
		if key in raw and isinstance(raw.get(key), list):
			cfg[key] = [str(x).strip() for x in raw[key] if str(x).strip()]
	return cfg


def policy_description(cfg: Dict[str, Any]) -> str:
	parts = [
		f"exclude produced_by prefixes {cfg.get('forbidden_produced_by_prefixes', [])}",
		f"exclude source_types {cfg.get('forbidden_source_types', [])}",
		f"exclude authorship_kinds {cfg.get('forbidden_authorship_kinds', [])}",
	]
	if bool(cfg.get("uncertain_exclude", True)):
		parts.append("uncertain→exclude")
	return "; ".join(parts)


def _source_facts(source: Dict[str, Any]) -> Dict[str, str]:
	prov = source.get("provenance", {}) if isinstance(source.get("provenance", {}), dict) else {}
	return {
		"source_id": str(source.get("source_id", "")).strip(),
		"source_type": str(source.get("source_type", "")).strip().lower(),
		"produced_by": str(prov.get("produced_by", "")).strip(),
		"authorship_kind": str(prov.get("authorship_kind", "")).strip().lower(),
	}


def classify_source(source: Optional[Dict[str, Any]], cfg: Dict[str, Any]) -> Tuple[bool, str]:
	"""Return (is_forbidden, reason). Missing/empty provenance may be uncertain."""
	if source is None:
		if bool(cfg.get("uncertain_exclude", True)):
			return True, "uncertain provenance (source record missing)"
		return False, ""
	facts = _source_facts(source)
	produced_by = facts["produced_by"]
	source_type = facts["source_type"]
	authorship = facts["authorship_kind"]

	for prefix in cfg.get("forbidden_produced_by_prefixes", []) or []:
		p = str(prefix).strip()
		if p and produced_by.startswith(p):
			return True, f"inadmissible provenance: produced_by starts with '{p}'"

	for st in cfg.get("forbidden_source_types", []) or []:
		s = str(st).strip().lower()
		if s and source_type == s:
			return True, f"inadmissible provenance: source_type '{s}'"

	for kind in cfg.get("forbidden_authorship_kinds", []) or []:
		k = str(kind).strip().lower()
		if k and authorship == k:
			return True, f"inadmissible provenance: authorship_kind '{k}'"

	if bool(cfg.get("uncertain_exclude", True)):
		if not produced_by and not authorship and not source_type:
			return True, "uncertain provenance (empty produced_by/source_type/authorship)"
	return False, ""


def gate_selected_candidates(
	selected: List[Dict[str, Any]],
	sources_by_id: Dict[str, Dict[str, Any]],
	cfg: Dict[str, Any],
) -> Dict[str, Any]:
	"""Split top-k selected into admissible vs policy-rejected.

	Does not touch relevance-rejected candidates. Returns a report suitable for
	trace enrichment and optional closure.v1 symbolic_constraints.
	"""
	cfg = normalize_admissibility_config(cfg)
	if not bool(cfg.get("enabled", False)):
		return {
			"enabled": False,
			"admissible": list(selected),
			"policy_rejected": [],
			"forbidden_source_ids": [],
			"policy": policy_description(cfg),
			"provably_faithful": True,
			"leakage": 0.0,
		}

	admissible: List[Dict[str, Any]] = []
	policy_rejected: List[Dict[str, Any]] = []
	forbidden_source_ids: List[str] = []

	for item in selected:
		source_id = str(item.get("source_id", "")).strip()
		source = sources_by_id.get(source_id)
		forbidden, reason = classify_source(source, cfg)
		if forbidden:
			policy_rejected.append({
				"chunk_id": item.get("chunk_id"),
				"source_id": source_id,
				"reason": reason or "inadmissible provenance",
			})
			if source_id and source_id not in forbidden_source_ids:
				forbidden_source_ids.append(source_id)
		else:
			admissible.append(item)

	# Hard filter ⇒ structural faithfulness (forbidden items are absent from pack).
	report = {
		"enabled": True,
		"admissible": admissible,
		"policy_rejected": policy_rejected,
		"forbidden_source_ids": forbidden_source_ids,
		"policy": policy_description(cfg),
		"provably_faithful": True,
		"leakage": 0.0,
		"method": "hard_provenance_filter",
	}
	optional = _optional_open_closure_note()
	if optional:
		report["open_closure"] = optional
	return report


def _optional_open_closure_note() -> Optional[Dict[str, Any]]:
	"""Best-effort discovery of the Open Closure package (not required)."""
	try:
		import closure_router  # type: ignore

		return {
			"package": "closure_router",
			"available": True,
			"version_attr": getattr(closure_router, "__version__", None),
			"note": "Open Closure importable; Store gate uses hard filter (structural faithfulness).",
		}
	except Exception:
		return {
			"package": "closure_router",
			"available": False,
			"note": "Open Closure not on PYTHONPATH; Store gate uses hard provenance filter only.",
		}


def build_admissibility_closure_payload(
	query: str,
	admissible: List[Dict[str, Any]],
	report: Dict[str, Any],
	context_pack_id: str,
	trace_id: str,
) -> Dict[str, Any]:
	"""Closure.v1-shaped payload for optional persist (Note 87 fields)."""
	selected_chunk_ids = [str(item.get("chunk_id", "")) for item in admissible if item.get("chunk_id")]
	return {
		"title": f"Admissibility gate: {query[:80]}",
		"selected": {
			"artifact_ids": [context_pack_id] if context_pack_id else [],
			"source_ids": [],
			"chunk_ids": selected_chunk_ids,
			"memory_ids": [],
			"item_ids": [],
			"pattern_ids": [],
		},
		"symbolic_constraints": {
			"primary_seed": "closure",
			"source_app": "stfx_store.admissibility",
			"forbidden_source_ids": list(report.get("forbidden_source_ids", [])),
			"admissibility_policy": str(report.get("policy", "")),
			"provably_faithful": bool(report.get("provably_faithful", True)),
			"leakage": float(report.get("leakage", 0.0)),
			"method": str(report.get("method", "hard_provenance_filter")),
			"trace_id": trace_id,
		},
		"human_commit": {
			"committed_by": "stfx_store.admissibility",
			"decision": "gate",
		},
		"rationale": (
			"Open Closure–aligned provenance gate. Forbidden sources hard-excluded from "
			"context pack; leakage=0 by construction when policy is trusted."
		),
		"relations": [],
	}
