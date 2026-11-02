from __future__ import annotations

import hashlib
import re
import time
import uuid
from typing import Iterable


def utc_now() -> str:
	return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def safe_slug(text: str, fallback: str = "record") -> str:
	slug = re.sub(r"[^a-z0-9]+", "_", str(text or "").strip().lower()).strip("_")
	return slug[:80] or fallback


def short_hash(text: str | bytes, length: int = 12) -> str:
	data = text if isinstance(text, bytes) else str(text).encode("utf-8")
	return hashlib.sha256(data).hexdigest()[:length]


def content_hash(text: str | bytes) -> str:
	data = text if isinstance(text, bytes) else str(text).encode("utf-8")
	return "sha256:" + hashlib.sha256(data).hexdigest()


def make_source_id(title: str, text: str) -> str:
	return f"src_{safe_slug(title, 'source')}_{short_hash(text, 10)}"


def make_trace_id(query: str) -> str:
	return f"ret_{int(time.time())}_{short_hash(query + uuid.uuid4().hex, 8)}"


def make_context_pack_id(trace_id: str) -> str:
	return f"ctx_{trace_id.removeprefix('ret_')}"


def tokenize(text: str) -> list[str]:
	terms = re.findall(r"[a-z0-9][a-z0-9_\-]{1,}", str(text or "").lower())
	stop = {
		"the", "and", "for", "with", "that", "this", "from", "into", "are",
		"was", "were", "have", "has", "not", "but", "you", "your", "its",
		"our", "can", "will", "all", "one", "two", "how", "what", "why",
	}
	return [term for term in terms if term not in stop]


def unique_preserve_order(items: Iterable[str]) -> list[str]:
	out: list[str] = []
	seen: set[str] = set()
	for item in items:
		text = str(item or "").strip()
		if text and text not in seen:
			out.append(text)
			seen.add(text)
	return out
