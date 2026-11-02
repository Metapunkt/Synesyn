from __future__ import annotations

from typing import Any, Dict

from .schemas import INDEX_SCHEMA


def build_relation_index(
	chunks: list[Dict[str, Any]],
	memories: list[Dict[str, Any]] | None = None,
	closures: list[Dict[str, Any]] | None = None,
) -> Dict[str, Any]:
	edges: list[Dict[str, Any]] = []
	by_type: dict[str, list[Dict[str, Any]]] = {}
	reverse: dict[str, list[str]] = {}

	for record, record_id_field, record_kind in (
		*[(chunk, "chunk_id", "chunk") for chunk in chunks],
		*[(memory, "memory_id", "memory") for memory in (memories or [])],
		*[(closure, "closure_id", "closure") for closure in (closures or [])],
	):
		record_id = str(record.get(record_id_field, "")).strip()
		relations = record.get("relations", []) if isinstance(record.get("relations", []), list) else []
		for rel in relations:
			if not isinstance(rel, dict):
				continue
			rel_type = str(rel.get("type", "")).strip().lower()
			target = str(rel.get("target", "")).strip()
			if not rel_type or not target or not record_id:
				continue
			edge = {
				"from": record_id,
				"to": target,
				"type": rel_type,
				"from_kind": record_kind,
				"rationale": str(rel.get("rationale", "")),
			}
			edges.append(edge)
			by_type.setdefault(rel_type, []).append(edge)
			reverse.setdefault(target, []).append(record_id)

	return {
		"schema": INDEX_SCHEMA,
		"index_type": "relation",
		"authority": "generated",
		"edges": edges,
		"by_type": by_type,
		"reverse": reverse,
	}
