from __future__ import annotations

from typing import Any, Dict

from .provenance import provenance_record, query_input
from .records import make_context_pack_id, make_trace_id, utc_now
from .schemas import CONTEXT_PACK_SCHEMA, RETRIEVAL_TRACE_SCHEMA, validate_context_pack, validate_trace_record


def citation_label(chunk: Dict[str, Any]) -> str:
	heading = " > ".join(str(x) for x in chunk.get("heading_path", []) if str(x).strip())
	source_id = str(chunk.get("source_id", ""))
	return f"{source_id} > {heading}" if heading else source_id


def build_context_pack(trace_id: str, query: str, selected: list[Dict[str, Any]], chunks_by_id: Dict[str, Dict[str, Any]]) -> Dict[str, Any]:
	context_pack_id = make_context_pack_id(trace_id)
	context_chunks = []
	for item in selected:
		chunk = chunks_by_id[str(item["chunk_id"])]
		context_chunks.append({
			"chunk_id": chunk["chunk_id"],
			"source_id": chunk["source_id"],
			"heading_path": chunk.get("heading_path", []),
			"citation": citation_label(chunk),
			"text": chunk.get("text", ""),
			"scores": item["scores"],
		})
	pack = {
		"schema": CONTEXT_PACK_SCHEMA,
		"context_pack_id": context_pack_id,
		"trace_id": trace_id,
		"created_at": utc_now(),
		"chunks": context_chunks,
		"provenance": provenance_record(
			"stfx_store.retrieve@v0",
			inputs=[query_input(query)],
		),
	}
	validate_context_pack(pack)
	return pack


def build_retrieval_trace(
	query: str,
	active_source_ids: list[str],
	seed_family: str,
	top_k: int,
	expansion_depth: int,
	query_terms: list[str],
	core_summary: Dict[str, Any],
	candidates: list[Dict[str, Any]],
	selected: list[Dict[str, Any]],
	rejected: list[Dict[str, Any]],
	context_pack_id: str,
) -> Dict[str, Any]:
	trace_id = context_pack_id.replace("ctx_", "ret_", 1) if context_pack_id.startswith("ctx_") else make_trace_id(query)
	trace = {
		"schema": RETRIEVAL_TRACE_SCHEMA,
		"trace_id": trace_id,
		"query": query,
		"created_at": utc_now(),
		"scope": {
			"active_source_ids": sorted(active_source_ids),
			"seed_family": seed_family,
			"top_k": max(1, int(top_k)),
		},
		"retrieval_plan": {
			"symbolic_seed": seed_family,
			"lexical_terms": query_terms,
			"expansion_depth": int(expansion_depth),
			"stfx_core": core_summary,
			"vector_assist_enabled": False,
			"accelerators": ["symbolic", "lexical", "relation"],
		},
		"candidates": candidates,
		"selected": [item["chunk_id"] for item in selected],
		"rejected": rejected,
		"produced_context_artifact": context_pack_id,
	}
	validate_trace_record(trace)
	return trace
