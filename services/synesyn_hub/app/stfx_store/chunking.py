from __future__ import annotations

from typing import Any, Dict

from .records import content_hash
from .schemas import CHUNK_SCHEMA


def _line_char_offsets(lines: list[str]) -> list[int]:
	offsets: list[int] = []
	pos = 0
	for line in lines:
		offsets.append(pos)
		pos += len(line) + 1
	return offsets


def _chunk_text(lines: list[str], start_line: int, end_line: int) -> str:
	if end_line < start_line:
		return ""
	return "\n".join(lines[start_line - 1:end_line]).strip()


def chunk_markdown_text(source_id: str, text: str, default_seed: str = "primary") -> list[Dict[str, Any]]:
	lines = text.splitlines()
	offsets = _line_char_offsets(lines)
	heading_stack: list[str] = []
	open_chunks: list[Dict[str, Any]] = []

	for idx, line in enumerate(lines, start=1):
		stripped = line.strip()
		if not stripped.startswith("#"):
			continue
		level = len(stripped) - len(stripped.lstrip("#"))
		if level <= 0:
			continue
		title = stripped.lstrip("#").strip() or f"Section {len(open_chunks) + 1}"
		while len(heading_stack) >= level:
			heading_stack.pop()
		heading_stack.append(title)
		open_chunks.append({
			"title": title,
			"heading_path": list(heading_stack),
			"line_start": idx,
			"level": level,
		})

	if not open_chunks:
		open_chunks.append({
			"title": "Document",
			"heading_path": ["Document"],
			"line_start": 1 if lines else 0,
			"level": 1,
		})

	chunks: list[Dict[str, Any]] = []
	for i, raw in enumerate(open_chunks):
		next_start = open_chunks[i + 1]["line_start"] if i + 1 < len(open_chunks) else len(lines) + 1
		line_start = int(raw["line_start"])
		line_end = max(line_start, next_start - 1)
		char_start = offsets[line_start - 1] if line_start > 0 and line_start - 1 < len(offsets) else 0
		if line_end - 1 < len(offsets):
			char_end = offsets[line_end - 1] + len(lines[line_end - 1])
		else:
			char_end = len(text)
		body = _chunk_text(lines, line_start, line_end)
		chunk_id = f"{source_id}__ch_{i + 1:04d}"
		heading_path = [str(x) for x in raw["heading_path"]]
		chunks.append({
			"schema": CHUNK_SCHEMA,
			"chunk_id": chunk_id,
			"source_id": source_id,
			"span": {
				"line_start": line_start,
				"line_end": line_end,
				"char_start": char_start,
				"char_end": char_end,
			},
			"heading_path": heading_path,
			"text": body,
			"summary": heading_path[-1] if heading_path else raw["title"],
			"symbolic": {
				"primary_seed": default_seed,
				"secondary_seed": "",
				"tensions": [],
				"rationale": "Deterministic heading-based ingest; default symbolic seed assigned for human review.",
			},
			"relations": [],
			"ingest": {
				"method": "headings",
				"reviewed_by_human": False,
			},
			"content_hash": content_hash(body),
		})
	return chunks
