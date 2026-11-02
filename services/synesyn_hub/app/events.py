from __future__ import annotations

import asyncio
import time
from collections import deque
from dataclasses import dataclass, field
from typing import Any, Deque, Dict, Optional, Set


@dataclass
class SourceStats:
	last_seen_time: float = 0.0
	seq: int = 0
	seq_gaps: int = 0
	seq_dupes: int = 0
	last_gap: int = 0
	last_dupe: bool = False


class EventBus:
	def __init__(self, ring_buffer_size: int):
		self._clients: Set[asyncio.Queue] = set()
		self._ring: Deque[Dict[str, Any]] = deque(maxlen=ring_buffer_size)
		self._source_stats: Dict[str, SourceStats] = {}

	def client_count(self) -> int:
		return len(self._clients)

	def ring_size(self) -> int:
		return len(self._ring)

	def get_source_stats(self) -> Dict[str, Dict[str, Any]]:
		now = time.time()
		out: Dict[str, Dict[str, Any]] = {}
		for source_id, stats in self._source_stats.items():
			out[source_id] = {
				"last_seen_ms": int(max(0.0, (now - stats.last_seen_time)) * 1000.0),
				"seq": stats.seq,
				"seq_gaps": stats.seq_gaps,
				"seq_dupes": stats.seq_dupes,
				"last_gap": stats.last_gap,
				"last_dupe": stats.last_dupe,
			}
		return out

	def note_source(self, source_id: str, seq: int, *, seq_provided: bool = True) -> Dict[str, Any]:
		"""
		Track per-source liveness + seq for /status, and optionally compute gap/dupe warnings.
		Returns a warning dict when a seq gap/dupe is detected; otherwise {}.
		"""
		stats = self._source_stats.get(source_id) or SourceStats()
		prev = int(stats.seq or 0)
		warn: Dict[str, Any] = {}
		stats.last_gap = 0
		stats.last_dupe = False

		if seq_provided and prev > 0:
			if int(seq) <= prev:
				stats.seq_dupes += 1
				stats.last_dupe = True
				warn = {"kind": "seq_dupe", "source_id": source_id, "expected_next": prev + 1, "got": int(seq)}
			elif int(seq) > (prev + 1):
				gap = int(seq) - (prev + 1)
				stats.seq_gaps += gap
				stats.last_gap = gap
				warn = {"kind": "seq_gap", "source_id": source_id, "expected_next": prev + 1, "got": int(seq), "gap": gap}

		stats.last_seen_time = time.time()
		# Always move forward to the highest observed sequence to keep status monotonic.
		stats.seq = max(prev, int(seq))
		self._source_stats[source_id] = stats
		return warn

	def register_client(self) -> asyncio.Queue:
		q: asyncio.Queue = asyncio.Queue(maxsize=256)
		self._clients.add(q)
		return q

	def unregister_client(self, q: asyncio.Queue) -> None:
		self._clients.discard(q)

	async def publish(self, event: Dict[str, Any]) -> None:
		"""
		Publish to ring buffer and all client queues.
		Drop events for slow clients (never block the bus).
		"""
		self._ring.append(event)
		for q in list(self._clients):
			try:
				q.put_nowait(event)
			except asyncio.QueueFull:
				# Drop for that client
				pass

	def replay(self, max_events: int = 500) -> list[Dict[str, Any]]:
		if max_events <= 0:
			return []
		return list(self._ring)[-max_events:]

	def replay_filtered(
		self,
		*,
		max_events: int = 500,
		event_types: Optional[Set[str]] = None,
		since_ts: Optional[float] = None,
		until_ts: Optional[float] = None,
	) -> list[Dict[str, Any]]:
		"""
		Replay events from the ring buffer, filtered by:
		- event_types: exact event_type allowlist (None/empty => no filter)
		- since_ts/until_ts: window over t_hub_received (inclusive bounds)
		"""
		if max_events <= 0:
			return []
		types = set(event_types) if event_types else set()
		out: list[Dict[str, Any]] = []
		for evt in self._ring:
			et = str(evt.get("event_type", "")).strip()
			if types and et not in types:
				continue
			t = evt.get("t_hub_received", None)
			try:
				ts = float(t) if t is not None else None
			except Exception:
				ts = None
			if since_ts is not None and ts is not None and ts < float(since_ts):
				continue
			if until_ts is not None and ts is not None and ts > float(until_ts):
				continue
			out.append(evt)
		return out[-max_events:]


