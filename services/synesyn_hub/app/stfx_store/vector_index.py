from __future__ import annotations

import hashlib
from typing import Any, Dict

from .schemas import INDEX_SCHEMA


def _embedding_for_text(text: str, dimensions: int = 16) -> list[float]:
	digest = hashlib.sha256(text.encode("utf-8")).digest()
	values: list[float] = []
	for idx in range(dimensions):
		raw = digest[idx] / 255.0
		values.append(round((raw * 2.0) - 1.0, 6))
	return values


def build_vector_manifest(chunks: list[Dict[str, Any]], enabled: bool = False) -> Dict[str, Any]:
	vectors: Dict[str, Any] = {}
	for chunk in chunks:
		chunk_id = str(chunk.get("chunk_id", "")).strip()
		if not chunk_id:
			continue
		text = str(chunk.get("text", ""))
		vectors[chunk_id] = {
			"content_hash": str(chunk.get("content_hash", "")).strip(),
			"dimensions": 16,
			"embedding": _embedding_for_text(text),
		}
	return {
		"schema": INDEX_SCHEMA,
		"index_type": "vector",
		"authority": "generated",
		"enabled": bool(enabled),
		"provider": "deterministic_hash",
		"model": "hash16.v1",
		"vectors": vectors,
		"notes": "Deterministic local vectors are generated accelerators; canonical retrieval must work without this index.",
	}


def empty_vector_manifest() -> Dict[str, Any]:
	return build_vector_manifest([], enabled=False)


def external_vector_backend_manifest(enabled: bool = False, provider: str = "", model: str = "") -> Dict[str, Any]:
	return {
		"schema": INDEX_SCHEMA,
		"index_type": "external_vector_backend",
		"authority": "generated",
		"enabled": bool(enabled),
		"provider": str(provider or "").strip(),
		"model": str(model or "").strip(),
		"status": "configured" if enabled else "disabled",
		"notes": "External vector stores are mirrors only; rebuild from canonical Store records before use.",
	}
