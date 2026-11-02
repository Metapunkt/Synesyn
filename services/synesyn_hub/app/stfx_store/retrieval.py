from __future__ import annotations

from typing import Any, Dict


def score_candidate(
	chunk: Dict[str, Any],
	chunk_id: str,
	source_id: str,
	seed_family: str,
	query_term_count: int,
	lexical_hit_count: int,
	relation_reasons: list[str] | None = None,
	core_alignment: float = 0.0,
) -> Dict[str, Any]:
	symbolic_data = chunk.get("symbolic", {}) if isinstance(chunk.get("symbolic", {}), dict) else {}
	chunk_seed = str(symbolic_data.get("primary_seed", "")).strip().lower()
	seed = str(seed_family or "").strip().lower()
	symbolic_score = max(float(core_alignment), 1.0 if seed and chunk_seed == seed else 0.25 if not seed else 0.0)
	lexical_score = min(1.0, lexical_hit_count / max(1, query_term_count))
	relation_score = 0.35 if relation_reasons else 0.0

	# STFX core alignment is the final symbolic prior; lexical and
	# relation hits remain candidate-discovery aids.
	final_score = (0.62 * symbolic_score) + (0.25 * lexical_score) + (0.13 * relation_score)
	why: list[str] = []
	if seed and chunk_seed == seed:
		why.append(f"matches symbolic seed '{seed}'")
	elif seed:
		why.append(f"does not match requested symbolic seed '{seed}'")
	elif relation_reasons:
		why.append("included through relation-neighborhood expansion")
	else:
		why.append("no symbolic seed requested; neutral symbolic prior applied")
	if lexical_hit_count:
		why.append(f"matches {lexical_hit_count} lexical query term(s)")
	for reason in relation_reasons or []:
		why.append(reason)
	if not lexical_hit_count and not seed:
		why.append("included as fallback candidate because no stronger index hits were found")

	return {
		"chunk_id": chunk_id,
		"source_id": source_id,
		"scores": {
			"symbolic": round(symbolic_score, 4),
			"core_alignment": round(float(core_alignment), 4),
			"lexical": round(lexical_score, 4),
			"relation": round(relation_score, 4),
			"vector": 0.0,
			"final": round(final_score, 4),
		},
		"why": why,
	}


def sort_candidates(candidates: list[Dict[str, Any]]) -> list[Dict[str, Any]]:
	return sorted(
		candidates,
		key=lambda item: (
			float(item.get("scores", {}).get("final", 0.0)),
			float(item.get("scores", {}).get("symbolic", 0.0)),
			float(item.get("scores", {}).get("lexical", 0.0)),
			str(item.get("chunk_id", "")),
		),
		reverse=True,
	)
