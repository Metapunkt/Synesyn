from __future__ import annotations

import json
import sqlite3
from pathlib import Path
from typing import Any, Dict


def rebuild_sqlite_mirror(
	db_path: Path,
	sources: list[Dict[str, Any]],
	chunks: list[Dict[str, Any]],
	memories: list[Dict[str, Any]],
	closures: list[Dict[str, Any]],
) -> Dict[str, Any]:
	db_path.parent.mkdir(parents=True, exist_ok=True)
	if db_path.exists():
		db_path.unlink()
	conn = sqlite3.connect(str(db_path))
	try:
		conn.executescript(
			"""
			CREATE TABLE sources (
				source_id TEXT PRIMARY KEY,
				title TEXT,
				content_hash TEXT,
				record_json TEXT NOT NULL
			);
			CREATE TABLE chunks (
				chunk_id TEXT PRIMARY KEY,
				source_id TEXT,
				heading TEXT,
				primary_seed TEXT,
				content_hash TEXT,
				record_json TEXT NOT NULL
			);
			CREATE TABLE memories (
				memory_id TEXT PRIMARY KEY,
				title TEXT,
				primary_seed TEXT,
				content_hash TEXT,
				record_json TEXT NOT NULL
			);
			CREATE TABLE closures (
				closure_id TEXT PRIMARY KEY,
				title TEXT,
				primary_seed TEXT,
				content_hash TEXT,
				record_json TEXT NOT NULL
			);
			CREATE TABLE symbols (
				record_id TEXT,
				record_type TEXT,
				symbol_type TEXT,
				value TEXT
			);
			CREATE TABLE relations (
				from_id TEXT,
				to_id TEXT,
				relation_type TEXT,
				rationale TEXT
			);
			"""
		)
		for source in sources:
			conn.execute(
				"INSERT INTO sources VALUES (?, ?, ?, ?)",
				(
					str(source.get("source_id", "")),
					str(source.get("title", "")),
					str(source.get("content_hash", "")),
					json.dumps(source, ensure_ascii=False),
				),
			)
		for chunk in chunks:
			symbolic = chunk.get("symbolic", {}) if isinstance(chunk.get("symbolic", {}), dict) else {}
			heading = " > ".join(str(part) for part in chunk.get("heading_path", []) if str(part).strip())
			chunk_id = str(chunk.get("chunk_id", ""))
			seed = str(symbolic.get("primary_seed", ""))
			conn.execute(
				"INSERT INTO chunks VALUES (?, ?, ?, ?, ?, ?)",
				(chunk_id, str(chunk.get("source_id", "")), heading, seed, str(chunk.get("content_hash", "")), json.dumps(chunk, ensure_ascii=False)),
			)
			_insert_symbol_rows(conn, chunk_id, "chunk", symbolic)
			_insert_relation_rows(conn, chunk_id, chunk.get("relations", []))
		for memory in memories:
			address = memory.get("symbolic_address", {}) if isinstance(memory.get("symbolic_address", {}), dict) else {}
			memory_id = str(memory.get("memory_id", ""))
			seed = str(address.get("primary_seed", ""))
			conn.execute(
				"INSERT INTO memories VALUES (?, ?, ?, ?, ?)",
				(memory_id, str(memory.get("title", "")), seed, str(memory.get("content_hash", "")), json.dumps(memory, ensure_ascii=False)),
			)
			_insert_symbol_rows(conn, memory_id, "memory", address)
			_insert_relation_rows(conn, memory_id, memory.get("relations", []))
		for closure in closures:
			constraints = closure.get("symbolic_constraints", {}) if isinstance(closure.get("symbolic_constraints", {}), dict) else {}
			closure_id = str(closure.get("closure_id", ""))
			seed = str(constraints.get("primary_seed", ""))
			conn.execute(
				"INSERT INTO closures VALUES (?, ?, ?, ?, ?)",
				(closure_id, str(closure.get("title", "")), seed, str(closure.get("content_hash", "")), json.dumps(closure, ensure_ascii=False)),
			)
			_insert_symbol_rows(conn, closure_id, "closure", constraints)
			_insert_relation_rows(conn, closure_id, closure.get("relations", []))
		conn.commit()
	finally:
		conn.close()
	return {
		"enabled": True,
		"path": str(db_path),
		"tables": ["sources", "chunks", "memories", "closures", "symbols", "relations"],
		"counts": {
			"sources": len(sources),
			"chunks": len(chunks),
			"memories": len(memories),
			"closures": len(closures),
		},
	}


def _insert_symbol_rows(conn: sqlite3.Connection, record_id: str, record_type: str, symbolic: Dict[str, Any]) -> None:
	seed = str(symbolic.get("primary_seed", "")).strip()
	if seed:
		conn.execute("INSERT INTO symbols VALUES (?, ?, ?, ?)", (record_id, record_type, "primary_seed", seed))
	tensions = symbolic.get("tensions", [])
	if isinstance(tensions, list):
		for tension in tensions:
			value = str(tension).strip()
			if value:
				conn.execute("INSERT INTO symbols VALUES (?, ?, ?, ?)", (record_id, record_type, "tension", value))


def _insert_relation_rows(conn: sqlite3.Connection, from_id: str, relations_any: Any) -> None:
	relations = relations_any if isinstance(relations_any, list) else []
	for relation_any in relations:
		if not isinstance(relation_any, dict):
			continue
		to_id = str(relation_any.get("target", "")).strip()
		if not to_id:
			continue
		conn.execute(
			"INSERT INTO relations VALUES (?, ?, ?, ?)",
			(
				from_id,
				to_id,
				str(relation_any.get("type", "related")).strip() or "related",
				str(relation_any.get("rationale", "")).strip(),
			),
		)
