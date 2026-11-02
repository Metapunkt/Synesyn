from __future__ import annotations

from typing import Any, Dict, List


_PHASE_BY_SEED = {
	"primary": "setup",
	"transitional": "incident",
	"rhythmic": "rising",
	"alternating": "climax",
}


def _dedupe_strs(values: List[str]) -> List[str]:
	seen = set()
	out: List[str] = []
	for value in values:
		text = str(value or "").strip()
		if not text or text in seen:
			continue
		seen.add(text)
		out.append(text)
	return out


def _continuity_anchors(ctx: Dict[str, Any]) -> List[str]:
	target_summary = str(((ctx.get("target", {}) or {}).get("summary")) or "")
	lineage = [str(entry.get("summary", "")) for entry in (ctx.get("lineage", []) or [])]
	fragments = list(((ctx.get("carry_forward", {}) or {}).get("summary_fragments")) or [])
	return _dedupe_strs([target_summary, *lineage, *fragments])[:6]


def _latent_tensions(ctx: Dict[str, Any]) -> List[Dict[str, Any]]:
	out: List[Dict[str, Any]] = []
	for sibling in (ctx.get("sibling_context", []) or []):
		out.append({
			"path": sibling.get("path", ""),
			"summary": sibling.get("summary", ""),
			"seed_family": sibling.get("seed_family", ""),
			"tension_role": "alternative_branch",
		})
	return out[:4]


def _recommended_phase(ctx: Dict[str, Any]) -> str:
	seed_family = str(((ctx.get("target", {}) or {}).get("seed_family")) or "").strip().lower()
	return _PHASE_BY_SEED.get(seed_family, "setup")


def build_scenario_continuity_state(continuity_context: Dict[str, Any]) -> Dict[str, Any]:
	ctx = continuity_context or {}
	target = ctx.get("target", {}) or {}
	document = ctx.get("document", {}) or {}
	carry_forward = ctx.get("carry_forward", {}) or {}
	symbolic_context = ctx.get("symbolic_context", {}) or {}
	recommended_phase = _recommended_phase(ctx)
	anchors = _continuity_anchors(ctx)
	tensions = _latent_tensions(ctx)
	focus_terms = _dedupe_strs(list(carry_forward.get("focus_terms", []) or []))[:8]
	seed_emphasis = _dedupe_strs(list(carry_forward.get("seed_emphasis", []) or []))[:4]

	phase_instruction = {
		"setup": "Use this branch as setup material: introduce setting, roles, and stakes without resolving the tension.",
		"incident": "Use this branch to surface the inciting tension and force a response from the participants.",
		"rising": "Use this branch to escalate complications, trade-offs, and conflicting interpretations.",
		"climax": "Use this branch to drive toward a decisive confrontation, turning point, or choice.",
	}.get(recommended_phase, "Use this branch as continuity material for the next scenario beat.")

	unresolved_challenges = _dedupe_strs(
		[str(t.get("summary", "")) for t in tensions] + [str(target.get("selection_rationale", ""))]
	)[:4]

	return {
		"ok": True,
		"contract_type": "scensyn.scenario_continuity_state",
		"contract_version": 1,
		"source_contract": {
			"contract_type": ctx.get("contract_type", ""),
			"contract_version": ctx.get("contract_version", 0),
		},
		"scenario_focus": {
			"document_id": target.get("document_id", document.get("document_id", "")),
			"chunk_path": target.get("chunk_path", ""),
			"summary": target.get("summary", ""),
			"source_ref": target.get("source_ref", {}),
		},
		"continuity": {
			"anchors": anchors,
			"latent_tensions": tensions,
			"focus_terms": focus_terms,
			"seed_emphasis": seed_emphasis,
			"recommended_narrative_phase": recommended_phase,
			"phase_instruction": phase_instruction,
		},
		"symbolic_signals": {
			"root_seed_family": symbolic_context.get("root_seed_family", ""),
			"active_seed_family": symbolic_context.get("target_seed_family", target.get("seed_family", "")),
			"expansion_depth": symbolic_context.get("expansion_depth", 0),
			"matrix_shape": symbolic_context.get("matrix_shape", []),
			"complementarity_verified": symbolic_context.get("complementarity_verified", False),
		},
		"state_patch": {
			"current_narrative_phase_hint": recommended_phase,
			"unresolved_challenges": unresolved_challenges,
			"memory_context": {
				"continuity_anchor": (anchors[0] if anchors else ""),
				"summary_fragments": anchors,
				"focus_terms": focus_terms,
				"seed_emphasis": seed_emphasis,
			},
		},
		"prompt_cues": {
			"scenario_brief": " | ".join(anchors[:3]),
			"continuity_prompt": "; ".join(_dedupe_strs([phase_instruction, *anchors[:2], *focus_terms[:4]])),
		},
		"provenance": ctx.get("provenance", {}),
	}


def build_scenario_continuity_state_from_context_pack(context_pack: Dict[str, Any]) -> Dict[str, Any]:
	pack = context_pack or {}
	chunks = pack.get("chunks", []) if isinstance(pack.get("chunks", []), list) else []
	anchors: List[str] = []
	focus_terms: List[str] = []
	source_ids: List[str] = []
	seed_emphasis: List[str] = []

	for chunk in chunks:
		if not isinstance(chunk, dict):
			continue
		text = str(chunk.get("text", "") or "").strip()
		citation = str(chunk.get("citation", "") or "").strip()
		source_id = str(chunk.get("source_id", "") or "").strip()
		if citation:
			anchors.append(citation)
		elif source_id:
			anchors.append(source_id)
		if source_id:
			source_ids.append(source_id)
		for term in text.replace("\n", " ").split(" "):
			clean = "".join(ch.lower() for ch in term if ch.isalnum() or ch in "-_").strip("-_")
			if len(clean) >= 5:
				focus_terms.append(clean)
		scores = chunk.get("scores", {}) if isinstance(chunk.get("scores", {}), dict) else {}
		if float(scores.get("symbolic", 0.0) or 0.0) > 0:
			seed_emphasis.append("symbolic")

	anchors = _dedupe_strs(anchors)[:6]
	focus_terms = _dedupe_strs(focus_terms)[:8]
	source_ids = _dedupe_strs(source_ids)
	seed_emphasis = _dedupe_strs(seed_emphasis)[:4]
	trace_id = str(pack.get("trace_id", "") or "").strip()
	context_pack_id = str(pack.get("context_pack_id", "") or "").strip()

	summary = " | ".join(anchors[:3])
	phase_instruction = "Use this retrieved STFX Store context as scenario continuity material while preserving current session agency."

	return {
		"ok": True,
		"contract_type": "scensyn.scenario_continuity_state",
		"contract_version": 1,
		"source_contract": {
			"contract_type": "stfx.context_pack",
			"contract_version": 1,
		},
		"scenario_focus": {
			"document_id": "",
			"chunk_path": "",
			"summary": summary,
			"source_ref": {
				"kind": "stfx_store.context_pack",
				"context_pack_id": context_pack_id,
				"trace_id": trace_id,
			},
		},
		"continuity": {
			"anchors": anchors,
			"latent_tensions": [],
			"focus_terms": focus_terms,
			"seed_emphasis": seed_emphasis,
			"recommended_narrative_phase": "rising" if len(chunks) > 1 else "setup",
			"phase_instruction": phase_instruction,
		},
		"symbolic_signals": {
			"root_seed_family": "",
			"active_seed_family": "",
			"expansion_depth": 0,
			"matrix_shape": [],
			"complementarity_verified": False,
		},
		"state_patch": {
			"current_narrative_phase_hint": "rising" if len(chunks) > 1 else "setup",
			"unresolved_challenges": anchors[:4],
			"memory_context": {
				"continuity_anchor": anchors[0] if anchors else "",
				"summary_fragments": anchors,
				"focus_terms": focus_terms,
				"seed_emphasis": seed_emphasis,
				"source_ids": source_ids,
				"trace_id": trace_id,
				"context_pack_id": context_pack_id,
			},
		},
		"prompt_cues": {
			"scenario_brief": summary,
			"continuity_prompt": "; ".join(_dedupe_strs([phase_instruction, *anchors[:2], *focus_terms[:4]])),
		},
		"provenance": {
			"produced_by": "scensyn.continuity_from_stfx_store_context_pack",
			"inputs": [
				{"type": "stfx_store.context_pack", "context_pack_id": context_pack_id},
				{"type": "stfx_store.retrieval_trace", "trace_id": trace_id},
			],
		},
	}


def build_store_context_continuity_artifact_payload(
	continuity_state: Dict[str, Any],
	context_pack_id: str = "",
	session_id: str = "",
) -> Dict[str, Any]:
	state = continuity_state or {}
	prov = state.get("provenance", {}) if isinstance(state.get("provenance", {}), dict) else {}
	inputs = prov.get("inputs", []) if isinstance(prov.get("inputs", []), list) else []
	trace_id = ""
	for item in inputs:
		if not isinstance(item, dict):
			continue
		if str(item.get("type", "")) == "stfx_store.retrieval_trace":
			trace_id = str(item.get("trace_id", "")).strip()
		if not context_pack_id and str(item.get("type", "")) == "stfx_store.context_pack":
			context_pack_id = str(item.get("context_pack_id", "")).strip()
	return {
		"schema_version": 1,
		"artifact_type": "json.scensyn_continuity_context",
		"session_id": str(session_id or "").strip(),
		"context_pack_id": str(context_pack_id or "").strip(),
		"trace_id": trace_id,
		"continuity_state": state,
	}
