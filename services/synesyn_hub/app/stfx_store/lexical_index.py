from __future__ import annotations

from typing import Any, Dict

from .records import tokenize, unique_preserve_order
from .schemas import INDEX_SCHEMA


def build_lexical_index(sources: list[Dict[str, Any]], chunks: list[Dict[str, Any]]) -> Dict[str, Any]:
	terms: dict[str, list[str]] = {}
	aliases: dict[str, str] = {}

	for source in sources:
		source_id = str(source.get("source_id", "")).strip()
		for term in tokenize(" ".join([
			str(source.get("title", "")),
			str(source.get("original_ref", {}).get("path", "")) if isinstance(source.get("original_ref", {}), dict) else "",
		])):
			if source_id:
				aliases.setdefault(term, source_id)

	for chunk in chunks:
		chunk_id = str(chunk.get("chunk_id", "")).strip()
		heading_path = chunk.get("heading_path", []) if isinstance(chunk.get("heading_path", []), list) else []
		text = " ".join([
			str(chunk.get("summary", "")),
			" ".join(str(x) for x in heading_path),
			str(chunk.get("text", "")),
		])
		for term in tokenize(text):
			if chunk_id:
				terms.setdefault(term, []).append(chunk_id)

	return {
		"schema": INDEX_SCHEMA,
		"index_type": "lexical",
		"authority": "generated",
		"terms": {term: unique_preserve_order(ids) for term, ids in sorted(terms.items())},
		"source_aliases": aliases,
	}
