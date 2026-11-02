from __future__ import annotations

from typing import Any, Dict


SCHEMA_VERSION = 1
STORE_SCHEMA = "stfx.store.v1"
SOURCE_SCHEMA = "stfx.source.v1"
CHUNK_SCHEMA = "stfx.chunk.v1"
INDEX_SCHEMA = "stfx.index.v1"
RETRIEVAL_TRACE_SCHEMA = "stfx.retrieval_trace.v1"
CONTEXT_PACK_SCHEMA = "stfx.context_pack.v1"
ARTIFACT_SCHEMA = "stfx.artifact.v1"
MEMORY_SCHEMA = "stfx.memory.v1"
CLOSURE_SCHEMA = "stfx.closure.v1"
INGEST_REPORT_SCHEMA = "stfx.ingest_report.v1"
REPAIR_REPORT_SCHEMA = "stfx.repair_report.v1"


def require_nonempty_str(value: Any, field: str) -> str:
	text = str(value or "").strip()
	if not text:
		raise ValueError(f"{field} is required")
	return text


def require_dict(value: Any, field: str) -> Dict[str, Any]:
	if not isinstance(value, dict):
		raise ValueError(f"{field} must be an object")
	return value


def validate_manifest(manifest: Dict[str, Any]) -> None:
	require_dict(manifest, "manifest")
	if manifest.get("schema") != STORE_SCHEMA:
		raise ValueError(f"manifest schema must be {STORE_SCHEMA}")
	require_nonempty_str(manifest.get("store_id"), "store_id")
	indexes = require_dict(manifest.get("indexes", {}), "indexes")
	if indexes.get("authority") != "generated":
		raise ValueError("indexes.authority must be 'generated'")


def validate_source_record(source: Dict[str, Any]) -> None:
	require_dict(source, "source")
	if source.get("schema") != SOURCE_SCHEMA:
		raise ValueError(f"source schema must be {SOURCE_SCHEMA}")
	require_nonempty_str(source.get("source_id"), "source_id")
	require_nonempty_str(source.get("title"), "title")
	require_nonempty_str(source.get("content_hash"), "content_hash")
	require_dict(source.get("original_ref", {}), "original_ref")
	require_dict(source.get("provenance", {}), "provenance")


def validate_chunk_record(chunk: Dict[str, Any]) -> None:
	require_dict(chunk, "chunk")
	if chunk.get("schema") != CHUNK_SCHEMA:
		raise ValueError(f"chunk schema must be {CHUNK_SCHEMA}")
	require_nonempty_str(chunk.get("chunk_id"), "chunk_id")
	require_nonempty_str(chunk.get("source_id"), "source_id")
	require_nonempty_str(chunk.get("content_hash"), "content_hash")
	span = require_dict(chunk.get("span", {}), "span")
	if int(span.get("line_start", 0)) > int(span.get("line_end", 0)):
		raise ValueError("span.line_start must be <= span.line_end")
	if int(span.get("char_start", 0)) > int(span.get("char_end", 0)):
		raise ValueError("span.char_start must be <= span.char_end")
	symbolic = require_dict(chunk.get("symbolic", {}), "symbolic")
	require_nonempty_str(symbolic.get("primary_seed"), "symbolic.primary_seed")
	require_nonempty_str(symbolic.get("rationale"), "symbolic.rationale")


def validate_trace_record(trace: Dict[str, Any]) -> None:
	require_dict(trace, "trace")
	if trace.get("schema") != RETRIEVAL_TRACE_SCHEMA:
		raise ValueError(f"trace schema must be {RETRIEVAL_TRACE_SCHEMA}")
	require_nonempty_str(trace.get("trace_id"), "trace_id")
	require_dict(trace.get("scope", {}), "scope")
	if not isinstance(trace.get("candidates", []), list):
		raise ValueError("trace.candidates must be a list")
	if not isinstance(trace.get("selected", []), list):
		raise ValueError("trace.selected must be a list")


def validate_context_pack(pack: Dict[str, Any]) -> None:
	require_dict(pack, "context_pack")
	if pack.get("schema") != CONTEXT_PACK_SCHEMA:
		raise ValueError(f"context_pack schema must be {CONTEXT_PACK_SCHEMA}")
	require_nonempty_str(pack.get("context_pack_id"), "context_pack_id")
	require_nonempty_str(pack.get("trace_id"), "trace_id")
	if not isinstance(pack.get("chunks", []), list):
		raise ValueError("context_pack.chunks must be a list")


def validate_memory_record(memory: Dict[str, Any]) -> None:
	require_dict(memory, "memory")
	if memory.get("schema") != MEMORY_SCHEMA:
		raise ValueError(f"memory schema must be {MEMORY_SCHEMA}")
	require_nonempty_str(memory.get("memory_id"), "memory_id")
	require_nonempty_str(memory.get("title"), "title")
	require_nonempty_str(memory.get("rationale"), "rationale")
	require_nonempty_str(memory.get("content_hash"), "content_hash")
	require_dict(memory.get("symbolic_address", {}), "symbolic_address")
	require_dict(memory.get("related", {}), "related")
	require_dict(memory.get("provenance", {}), "provenance")
	if not isinstance(memory.get("repair_notes", []), list):
		raise ValueError("memory.repair_notes must be a list")


def validate_closure_record(closure: Dict[str, Any]) -> None:
	require_dict(closure, "closure")
	if closure.get("schema") != CLOSURE_SCHEMA:
		raise ValueError(f"closure schema must be {CLOSURE_SCHEMA}")
	require_nonempty_str(closure.get("closure_id"), "closure_id")
	require_nonempty_str(closure.get("title"), "title")
	require_nonempty_str(closure.get("rationale"), "rationale")
	require_nonempty_str(closure.get("content_hash"), "content_hash")
	require_dict(closure.get("selected", {}), "selected")
	require_dict(closure.get("symbolic_constraints", {}), "symbolic_constraints")
	require_dict(closure.get("human_commit", {}), "human_commit")
	require_dict(closure.get("provenance", {}), "provenance")


def validate_ingest_report(report: Dict[str, Any]) -> None:
	require_dict(report, "ingest_report")
	if report.get("schema") != INGEST_REPORT_SCHEMA:
		raise ValueError(f"ingest_report schema must be {INGEST_REPORT_SCHEMA}")
	require_nonempty_str(report.get("report_id"), "report_id")
	require_nonempty_str(report.get("source_id"), "source_id")
	if not isinstance(report.get("chunk_ids", []), list):
		raise ValueError("ingest_report.chunk_ids must be a list")


def validate_repair_report(report: Dict[str, Any]) -> None:
	require_dict(report, "repair_report")
	if report.get("schema") != REPAIR_REPORT_SCHEMA:
		raise ValueError(f"repair_report schema must be {REPAIR_REPORT_SCHEMA}")
	require_nonempty_str(report.get("report_id"), "report_id")
	if not isinstance(report.get("checks", []), list):
		raise ValueError("repair_report.checks must be a list")
