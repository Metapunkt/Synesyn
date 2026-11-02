from __future__ import annotations

from typing import Any, Dict

from .schemas import INDEX_SCHEMA


def build_symbolic_index(
	sources: list[Dict[str, Any]],
	chunks: list[Dict[str, Any]],
	memories: list[Dict[str, Any]] | None = None,
	closures: list[Dict[str, Any]] | None = None,
) -> Dict[str, Any]:
	by_seed: dict[str, list[str]] = {}
	by_tension: dict[str, list[str]] = {}
	by_source: dict[str, list[str]] = {}
	by_memory_seed: dict[str, list[str]] = {}
	by_memory_tension: dict[str, list[str]] = {}
	by_closure_seed: dict[str, list[str]] = {}
	memory_related: dict[str, Dict[str, Any]] = {}
	closure_selected: dict[str, Dict[str, Any]] = {}

	for chunk in chunks:
		chunk_id = str(chunk.get("chunk_id", "")).strip()
		source_id = str(chunk.get("source_id", "")).strip()
		symbolic = chunk.get("symbolic", {}) if isinstance(chunk.get("symbolic", {}), dict) else {}
		seed = str(symbolic.get("primary_seed", "")).strip().lower()
		if seed and chunk_id:
			by_seed.setdefault(seed, []).append(chunk_id)
		if source_id and chunk_id:
			by_source.setdefault(source_id, []).append(chunk_id)
		for tension in symbolic.get("tensions", []) if isinstance(symbolic.get("tensions", []), list) else []:
			t = str(tension).strip().lower()
			if t and chunk_id:
				by_tension.setdefault(t, []).append(chunk_id)

	for memory in memories or []:
		memory_id = str(memory.get("memory_id", "")).strip()
		if not memory_id:
			continue
		symbolic_address = memory.get("symbolic_address", {}) if isinstance(memory.get("symbolic_address", {}), dict) else {}
		seed = str(symbolic_address.get("primary_seed", "")).strip().lower()
		if seed:
			by_memory_seed.setdefault(seed, []).append(memory_id)
		for tension in symbolic_address.get("tensions", []) if isinstance(symbolic_address.get("tensions", []), list) else []:
			t = str(tension).strip().lower()
			if t:
				by_memory_tension.setdefault(t, []).append(memory_id)
		related = memory.get("related", {}) if isinstance(memory.get("related", {}), dict) else {}
		memory_related[memory_id] = {
			"source_ids": [str(item).strip() for item in related.get("source_ids", []) if str(item).strip()] if isinstance(related.get("source_ids", []), list) else [],
			"chunk_ids": [str(item).strip() for item in related.get("chunk_ids", []) if str(item).strip()] if isinstance(related.get("chunk_ids", []), list) else [],
			"closure_ids": [str(item).strip() for item in related.get("closure_ids", []) if str(item).strip()] if isinstance(related.get("closure_ids", []), list) else [],
		}

	for closure in closures or []:
		closure_id = str(closure.get("closure_id", "")).strip()
		if not closure_id:
			continue
		symbolic_constraints = closure.get("symbolic_constraints", {}) if isinstance(closure.get("symbolic_constraints", {}), dict) else {}
		seed = str(symbolic_constraints.get("primary_seed", "")).strip().lower()
		if seed:
			by_closure_seed.setdefault(seed, []).append(closure_id)
		selected = closure.get("selected", {}) if isinstance(closure.get("selected", {}), dict) else {}
		closure_selected[closure_id] = {
			"source_ids": [str(item).strip() for item in selected.get("source_ids", []) if str(item).strip()] if isinstance(selected.get("source_ids", []), list) else [],
			"chunk_ids": [str(item).strip() for item in selected.get("chunk_ids", []) if str(item).strip()] if isinstance(selected.get("chunk_ids", []), list) else [],
			"memory_ids": [str(item).strip() for item in selected.get("memory_ids", []) if str(item).strip()] if isinstance(selected.get("memory_ids", []), list) else [],
			"artifact_ids": [str(item).strip() for item in selected.get("artifact_ids", []) if str(item).strip()] if isinstance(selected.get("artifact_ids", []), list) else [],
		}

	return {
		"schema": INDEX_SCHEMA,
		"index_type": "symbolic",
		"authority": "generated",
		"sources": [str(source.get("source_id", "")) for source in sources],
		"memories": [str(memory.get("memory_id", "")) for memory in memories or []],
		"closures": [str(closure.get("closure_id", "")) for closure in closures or []],
		"by_seed": by_seed,
		"by_tension": by_tension,
		"by_source": by_source,
		"by_memory_seed": by_memory_seed,
		"by_memory_tension": by_memory_tension,
		"memory_related": memory_related,
		"by_closure_seed": by_closure_seed,
		"closure_selected": closure_selected,
	}
