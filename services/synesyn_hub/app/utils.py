from __future__ import annotations

import time
from typing import Any, Dict, Optional

import ulid


def new_id(prefix: str) -> str:
	"""
	Generate a globally unique, time-sortable id with a prefix, e.g. `evt_...`.
	"""
	return f"{prefix}_{ulid.new()}"


def now_utc_iso() -> str:
	return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def make_event_envelope(
	*,
	event_type: str,
	source_id: str,
	seq: int,
	payload: Dict[str, Any],
	t_device: Optional[float] = None,
	provenance: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
	return {
		"schema_version": "1",
		"event_id": new_id("evt"),
		"event_type": event_type,
		"source_id": source_id,
		"seq": int(seq),
		"t_device": t_device,
		"t_hub_received": time.time(),
		"payload": payload,
		"provenance": provenance or {},
	}


