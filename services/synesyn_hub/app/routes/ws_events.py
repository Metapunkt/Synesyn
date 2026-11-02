from __future__ import annotations

import asyncio
import json
import logging
import time
from fastapi import APIRouter, WebSocket, WebSocketDisconnect


router = APIRouter()
log = logging.getLogger("synesyn_hub.ws")


@router.websocket("/ws/events")
async def ws_events(websocket: WebSocket):
	await websocket.accept()
	bus = websocket.app.state.event_bus
	q = bus.register_client()
	subscribed_event_types: set[str] = set()  # empty => all

	try:
		# On connect, send a small hello.
		await websocket.send_text(json.dumps({"type": "hello", "ok": True, "protocol": {"ws_events": 1}}))

		while True:
			# Multiplex:
			# - accept client->server commands (subscribe/replay)
			# - drain outgoing event queue (filtered)
			try:
				msg = await asyncio.wait_for(websocket.receive_text(), timeout=0.05)
				if msg:
					try:
						obj = json.loads(msg)
						typ = obj.get("type")

						# v1: subscribe {type:"subscribe", event_types:[...]} where empty/omitted means "all".
						if typ == "subscribe":
							types_in = obj.get("event_types", None)
							if isinstance(types_in, list):
								subscribed_event_types = {str(x).strip() for x in types_in if str(x).strip()}
							else:
								subscribed_event_types = set()
							await websocket.send_text(
								json.dumps({"type": "subscribed", "ok": True, "event_types": sorted(list(subscribed_event_types))})
							)

						# v1: replay window semantics
						# {type:"replay", max_events:int, window_sec:float?, since_ts:float?, until_ts:float?, event_types:[...]?}
						elif typ == "replay":
							max_events = int(obj.get("max_events", 200))
							window_sec = obj.get("window_sec", None)
							since_ts = obj.get("since_ts", None)
							until_ts = obj.get("until_ts", None)
							if window_sec is not None:
								try:
									window = float(window_sec)
									since_ts = time.time() - max(0.0, window)
								except Exception:
									pass
							try:
								since_ts_f = float(since_ts) if since_ts is not None else None
							except Exception:
								since_ts_f = None
							try:
								until_ts_f = float(until_ts) if until_ts is not None else None
							except Exception:
								until_ts_f = None

							types_in = obj.get("event_types", None)
							if isinstance(types_in, list):
								replay_types = {str(x).strip() for x in types_in if str(x).strip()}
							else:
								replay_types = set(subscribed_event_types)

							for evt in bus.replay_filtered(
								max_events=max_events,
								event_types=replay_types if replay_types else None,
								since_ts=since_ts_f,
								until_ts=until_ts_f,
							):
								await websocket.send_text(json.dumps({"type": "event", "data": evt}))
					except Exception:
						pass
			except asyncio.TimeoutError:
				pass

			# Drain one event (don’t block)
			try:
				evt = q.get_nowait()
				if subscribed_event_types:
					et = str(evt.get("event_type", "")).strip()
					if et not in subscribed_event_types:
						continue
				await websocket.send_text(json.dumps({"type": "event", "data": evt}))
			except asyncio.QueueEmpty:
				continue
	except WebSocketDisconnect:
		pass
	except Exception as e:
		log.exception("WS error: %s", e)
	finally:
		bus.unregister_client(q)


