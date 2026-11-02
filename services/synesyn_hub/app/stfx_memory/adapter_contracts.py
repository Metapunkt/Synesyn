from __future__ import annotations

from typing import Any, Dict, List, Optional

from ..stfx_core import expand_seed_matrix, matrix_to_payload
from .retrieve import document_summary, get_chunk_by_path


_STOPWORDS = {
	"a",
	"an",
	"and",
	"are",
	"as",
	"at",
	"be",
	"but",
	"by",
	"for",
	"from",
	"has",
	"have",
	"in",
	"into",
	"is",
	"it",
	"its",
	"of",
	"on",
	"or",
	"that",
	"the",
	"their",
	"this",
	"to",
	"was",
	"with",
}


def _chunk_seed_family(chunk: Dict[str, Any]) -> str:
	return str(chunk.get("recommended_sub_seed_family") or "primary").strip().lower()


def _chunk_brief(chunk: Dict[str, Any]) -> Dict[str, Any]:
	return {
		"path": chunk.get("path", ""),
		"summary": chunk.get("summary", ""),
		"seed_family": _chunk_seed_family(chunk),
		"selection_rationale": chunk.get("selection_rationale", ""),
		"start_offset": int(chunk.get("start_offset", 0)),
		"end_offset": int(chunk.get("end_offset", 0)),
	}


def _lineage_chunks(doc: Dict[str, Any], chunk_path: str) -> List[Dict[str, Any]]:
	if not chunk_path:
		return []
	parts = [p for p in str(chunk_path).split(".") if p]
	current_children = doc.get("chunks", {})
	lineage: List[Dict[str, Any]] = []
	for part in parts:
		chunk = current_children.get(part)
		if chunk is None:
			break
		lineage.append(chunk)
		current_children = chunk.get("sub_chunks", {}) if isinstance(chunk.get("sub_chunks", {}), dict) else {}
	return lineage


def _sibling_context(doc: Dict[str, Any], chunk_path: str, sibling_window: int) -> List[Dict[str, Any]]:
	if not chunk_path:
		return []
	parts = [p for p in str(chunk_path).split(".") if p]
	if not parts:
		return []
	parent_path = ".".join(parts[:-1])
	target_id = parts[-1]
	parent_children = doc.get("chunks", {})
	if parent_path:
		parent_chunk = get_chunk_by_path(doc.get("chunks", {}), parent_path)
		if parent_chunk is None:
			return []
		parent_children = parent_chunk.get("sub_chunks", {}) if isinstance(parent_chunk.get("sub_chunks", {}), dict) else {}
	keys = list(parent_children.keys())
	if target_id not in keys:
		return []
	idx = keys.index(target_id)
	start = max(0, idx - max(0, int(sibling_window)))
	end = min(len(keys), idx + max(0, int(sibling_window)) + 1)
	out: List[Dict[str, Any]] = []
	for key in keys[start:end]:
		if key == target_id:
			continue
		chunk = parent_children[key]
		out.append(_chunk_brief(chunk))
	return out


def _extract_focus_terms(*parts: str, max_terms: int = 8) -> List[str]:
	seen = set()
	out: List[str] = []
	for part in parts:
		for token in str(part or "").replace("-", " ").replace("_", " ").split():
			clean = "".join(ch.lower() for ch in token if ch.isalnum())
			if len(clean) < 4 or clean in _STOPWORDS or clean in seen:
				continue
			seen.add(clean)
			out.append(clean)
			if len(out) >= max_terms:
				return out
	return out


def build_continuity_context(
	doc: Dict[str, Any],
	document_id: str,
	chunk_path: str = "",
	depth: int = 2,
	sibling_window: int = 2,
) -> Dict[str, Any]:
	target: Optional[Dict[str, Any]]
	if chunk_path:
		target = get_chunk_by_path(doc.get("chunks", {}), chunk_path)
		if target is None:
			raise KeyError(f"chunk path not found: {chunk_path}")
		seed_matrix = target["sub_seed_matrix"]
		seed_family = _chunk_seed_family(target)
		summary_text = str(target.get("summary", ""))
		rationale = str(target.get("selection_rationale", ""))
	else:
		target = None
		seed_matrix = doc["root_seed_matrix"]
		seed_family = str(doc.get("root_seed_family") or "primary").strip().lower()
		summary_text = str(doc.get("title", ""))
		rationale = str(doc.get("ingest_rationale", ""))

	matrix_payload = matrix_to_payload(expand_seed_matrix(seed_matrix, int(depth)))
	lineage = [_chunk_brief(chunk) for chunk in _lineage_chunks(doc, chunk_path)]
	siblings = _sibling_context(doc, chunk_path, sibling_window)
	focus_terms = _extract_focus_terms(
		doc.get("title", ""),
		summary_text,
		rationale,
		*(entry.get("summary", "") for entry in lineage),
	)
	carry_forward = [summary_text] if summary_text else []
	carry_forward.extend(entry.get("summary", "") for entry in lineage[:-1] if entry.get("summary"))
	carry_forward.extend(entry.get("summary", "") for entry in siblings[:2] if entry.get("summary"))

	return {
		"ok": True,
		"contract_type": "stfx_memory.continuity_context",
		"contract_version": 1,
		"document": document_summary(doc),
		"target": {
			"document_id": document_id,
			"chunk_path": chunk_path or "",
			"summary": summary_text,
			"seed_family": seed_family,
			"selection_rationale": rationale,
			"source_ref": doc.get("source_ref", {}),
		},
		"lineage": lineage,
		"sibling_context": siblings,
		"symbolic_context": {
			"root_seed_family": doc.get("root_seed_family", ""),
			"target_seed_family": seed_family,
			"expansion_depth": int(depth),
			"matrix_shape": matrix_payload.get("matrix_shape", []),
			"complementarity_verified": matrix_payload.get("meta", {}).get("complementarity_verified", False),
		},
		"carry_forward": {
			"focus_terms": focus_terms,
			"summary_fragments": [frag for frag in carry_forward if frag][:6],
			"seed_emphasis": [seed_family, str(doc.get("root_seed_family", "")).strip().lower()],
		},
		"provenance": {
			"source_ref": doc.get("source_ref", {}),
			"origin": "stfx_memory.adapter_contract",
		},
	}
