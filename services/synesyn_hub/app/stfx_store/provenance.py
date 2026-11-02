from __future__ import annotations

from typing import Any, Dict

from .records import content_hash, utc_now


def provenance_record(produced_by: str, inputs: list[Dict[str, Any]] | None = None, parameters: Dict[str, Any] | None = None) -> Dict[str, Any]:
	return {
		"produced_by": str(produced_by or "stfx_store"),
		"inputs": inputs or [],
		"parameters": parameters or {},
		"timestamp": utc_now(),
	}


def query_input(query: str) -> Dict[str, Any]:
	return {
		"kind": "query",
		"hash": content_hash(query),
	}


def source_input(source_path: str) -> Dict[str, Any]:
	return {
		"kind": "file",
		"path": str(source_path),
	}
