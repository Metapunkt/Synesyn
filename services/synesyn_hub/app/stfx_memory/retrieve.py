from __future__ import annotations

from typing import Any, Dict, Optional


def get_chunk_by_path(chunks: Dict[str, Dict[str, Any]], chunk_path: str) -> Optional[Dict[str, Any]]:
	parts = [p for p in str(chunk_path or "").split(".") if p]
	if not parts:
		return None
	current: Optional[Dict[str, Any]] = None
	current_children = chunks
	for part in parts:
		current = current_children.get(part)
		if current is None:
			return None
		current_children = current.get("sub_chunks", {}) if isinstance(current.get("sub_chunks", {}), dict) else {}
	return current


def document_summary(doc: Dict[str, Any]) -> Dict[str, Any]:
	return {
		"document_id": doc.get("document_id"),
		"title": doc.get("title"),
		"ingested_at": doc.get("ingested_at"),
		"ingest_strategy": doc.get("ingest_strategy"),
		"root_seed_family": doc.get("root_seed_family"),
		"source_ref": doc.get("source_ref", {}),
		"chunk_count": len(doc.get("chunks", {})),
	}
