from __future__ import annotations

import asyncio
import json
import logging
from dataclasses import dataclass
from typing import Any, Dict, Optional, Tuple

from .events import EventBus
from .utils import make_event_envelope


log = logging.getLogger("synesyn_hub.udp")


@dataclass
class UdpIngestConfig:
	port: int


class UdpIngestProtocol(asyncio.DatagramProtocol):
	def __init__(self, bus: EventBus, persist_queue: asyncio.Queue):
		self._bus = bus
		self._persist_queue = persist_queue
		self._seq_by_source: Dict[str, int] = {}

	def datagram_received(self, data: bytes, addr: Tuple[str, int]) -> None:
		try:
			text = data.decode("utf-8", errors="ignore").strip()
			if not text:
				return
			obj = json.loads(text)
			if not isinstance(obj, dict):
				return

			source_id = str(obj.get("source_id", "unknown"))
			seq_in = obj.get("seq", None)
			if seq_in is None:
				seq = self._seq_by_source.get(source_id, 0) + 1
				seq_provided = False
			else:
				seq = int(seq_in)
				seq_provided = True

			self._seq_by_source[source_id] = seq
			warn = self._bus.note_source(source_id, seq, seq_provided=seq_provided)

			typ = str(obj.get("type", "packet"))
			event_type = f"sensor.{typ}"
			payload = obj.get("payload", {})
			if not isinstance(payload, dict):
				payload = {"value": payload}

			t_device = obj.get("t_device", None)
			try:
				t_device_val: Optional[float] = float(t_device) if t_device is not None else None
			except Exception:
				t_device_val = None

			env = make_event_envelope(
				event_type=event_type,
				source_id=source_id,
				seq=seq,
				payload=payload,
				t_device=t_device_val,
				provenance={"session_id": obj.get("session_id")},
			)

			# Fire-and-forget publish + persistence queueing (do not block UDP thread)
			asyncio.create_task(self._bus.publish(env))
			self._persist_queue.put_nowait(("event", env))

			# v1: best-effort seq-gap/dupe detection warnings (also persisted as events).
			if warn:
				wenv = make_event_envelope(
					event_type="sensor.warning",
					source_id=source_id,
					seq=seq,
					payload={"warning": warn, "type": "seq"},
					t_device=t_device_val,
					provenance={"session_id": obj.get("session_id")},
				)
				asyncio.create_task(self._bus.publish(wenv))
				self._persist_queue.put_nowait(("event", wenv))
		except Exception:
			log.exception("UDP ingest failed from %s", addr)


async def start_udp_ingest(bus: EventBus, persist_queue: asyncio.Queue, cfg: UdpIngestConfig):
	loop = asyncio.get_running_loop()
	transport, protocol = await loop.create_datagram_endpoint(
		lambda: UdpIngestProtocol(bus, persist_queue),
		local_addr=("0.0.0.0", cfg.port),
	)
	log.info("UDP ingest listening on port %d", cfg.port)
	return transport, protocol


