from __future__ import annotations

from typing import Any, Dict

from .seed_registry import validate_seed_matrix


SCHEMA_VERSION = 1


def _require_nonempty_str(value: Any, field: str) -> str:
	s = str(value or "").strip()
	if not s:
		raise ValueError(f"{field} is required")
	return s


def validate_chunk_record(chunk: Dict[str, Any]) -> None:
	if not isinstance(chunk, dict):
		raise ValueError("chunk must be an object")
	_require_nonempty_str(chunk.get("chunk_id"), "chunk_id")
	_require_nonempty_str(chunk.get("path"), "path")
	if "start_offset" not in chunk or "end_offset" not in chunk:
		raise ValueError("chunk start_offset/end_offset are required")
	if int(chunk["start_offset"]) > int(chunk["end_offset"]):
		raise ValueError("chunk start_offset must be <= end_offset")
	_require_nonempty_str(chunk.get("recommended_sub_seed_family"), "recommended_sub_seed_family")
	validate_seed_matrix(chunk.get("sub_seed_matrix"))
	if not isinstance(chunk.get("sub_chunks", {}), dict):
		raise ValueError("chunk sub_chunks must be an object")


def validate_document_record(doc: Dict[str, Any]) -> None:
	if not isinstance(doc, dict):
		raise ValueError("document record must be an object")
	if int(doc.get("schema_version", 0)) != SCHEMA_VERSION:
		raise ValueError(f"document schema_version must be {SCHEMA_VERSION}")
	_require_nonempty_str(doc.get("document_id"), "document_id")
	_require_nonempty_str(doc.get("title"), "title")
	if not isinstance(doc.get("source_ref", {}), dict):
		raise ValueError("source_ref must be an object")
	_require_nonempty_str(doc.get("ingest_strategy"), "ingest_strategy")
	_require_nonempty_str(doc.get("root_seed_family"), "root_seed_family")
	validate_seed_matrix(doc.get("root_seed_matrix"))
	if not isinstance(doc.get("chunks", {}), dict):
		raise ValueError("chunks must be an object")
	for chunk in doc.get("chunks", {}).values():
		validate_chunk_record(chunk)


def validate_memory_index(index: Dict[str, Any]) -> None:
	if not isinstance(index, dict):
		raise ValueError("memory index must be an object")
	if int(index.get("schema_version", 0)) != SCHEMA_VERSION:
		raise ValueError(f"memory index schema_version must be {SCHEMA_VERSION}")
	if not isinstance(index.get("documents", {}), dict):
		raise ValueError("memory index documents must be an object")
