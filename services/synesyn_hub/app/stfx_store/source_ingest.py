from __future__ import annotations

from pathlib import Path
from typing import Any, Dict

from .chunking import chunk_markdown_text
from .records import content_hash, make_source_id, utc_now
from .schemas import SOURCE_SCHEMA


def ingest_text_file(path: Path, default_seed: str = "primary") -> tuple[Dict[str, Any], list[Dict[str, Any]], str]:
	source_path = Path(path).expanduser().resolve()
	if not source_path.exists():
		raise FileNotFoundError(f"source file not found: {source_path}")
	text = source_path.read_text(encoding="utf-8")
	title = source_path.stem
	source_id = make_source_id(title, text)
	now = utc_now()
	source = {
		"schema": SOURCE_SCHEMA,
		"source_id": source_id,
		"title": title,
		"source_type": "markdown" if source_path.suffix.lower() in {".md", ".markdown"} else "text",
		"original_ref": {
			"kind": "file",
			"path": str(source_path),
		},
		"store_ref": {
			"kind": "file",
			"path": "",
		},
		"content_hash": content_hash(text),
		"ingest": {
			"method": "headings",
			"default_seed": default_seed,
			"created_at": now,
		},
		"provenance": {
			"produced_by": "stfx_store.source_ingest@v0",
			"timestamp": now,
			"inputs": [{"kind": "file", "path": str(source_path)}],
		},
		"chunk_ids": [],
	}
	chunks = chunk_markdown_text(source_id, text, default_seed=default_seed)
	source["chunk_ids"] = [str(chunk["chunk_id"]) for chunk in chunks]
	return source, chunks, text
