from __future__ import annotations

import json
import time
from typing import Any, Dict, Optional

from .db import Substrate
from ..utils import new_id
from .provenance import validate_artifact_metadata


class SubstrateRepo:
	def __init__(self, substrate: Substrate, enforce_provenance: bool = False):
		self._s = substrate
		self._enforce_provenance = enforce_provenance

	async def create_session(self, data: Dict[str, Any]) -> str:
		sess_id = new_id("sess")
		await self._s.conn.execute(
			"""
			INSERT INTO sessions(id, created_at, app_id, scenario_id, scenario_version, participants_json, metadata_json)
			VALUES(?, ?, ?, ?, ?, ?, ?)
			""",
			[
				sess_id,
				time.time(),
				data.get("app_id"),
				data.get("scenario_id"),
				data.get("scenario_version"),
				json.dumps(data.get("participants", {}), ensure_ascii=False),
				json.dumps(data.get("metadata", {}), ensure_ascii=False),
			],
		)
		await self._s.conn.commit()
		return sess_id

	async def get_session(self, session_id: str) -> Optional[Dict[str, Any]]:
		"""
		Fetch a session record by id, decoding JSON fields (participants_json, metadata_json).
		Used by policy gates such as voice recording consent checks.
		"""
		sid = (session_id or "").strip()
		if not sid:
			return None
		cur = await self._s.conn.execute("SELECT * FROM sessions WHERE id=?", [sid])
		row = await cur.fetchone()
		cols = [d[0] for d in cur.description]
		await cur.close()
		if not row:
			return None
		out: Dict[str, Any] = {}
		for i, c in enumerate(cols):
			out[c] = row[i]
		# Decode JSON fields
		for key in ("participants_json", "metadata_json"):
			try:
				out[key] = json.loads(out[key]) if out.get(key) else {}
			except Exception:
				out[key] = {}
		# Convenience aliases
		out["participants"] = out.get("participants_json") or {}
		out["metadata"] = out.get("metadata_json") or {}
		return out

	async def set_session_consent_save_recordings(self, session_id: str, enabled: bool) -> bool:
		"""
		Set `metadata.consent.save_recordings` on a session. This is the canonical consent gate
		for persisting input recordings (audio.input) via /voice/transcribe?save_recordings=true.
		"""
		sid = (session_id or "").strip()
		if not sid:
			return False
		sess = await self.get_session(sid)
		if not sess:
			# v0 ergonomics: allow clients to treat session_id as app-issued (e.g. SynesynSession.get_or_create_session_id)
			# and still use session metadata for consent without having to pre-create a substrate session via POST /sessions.
			meta = {"consent": {"save_recordings": bool(enabled)}}
			await self._s.conn.execute(
				"""
				INSERT OR IGNORE INTO sessions(id, created_at, app_id, scenario_id, scenario_version, participants_json, metadata_json)
				VALUES(?, ?, ?, ?, ?, ?, ?)
				""",
				[
					sid,
					time.time(),
					None,
					None,
					None,
					json.dumps({}, ensure_ascii=False),
					json.dumps(meta, ensure_ascii=False),
				],
			)
			# If another writer created the session concurrently, apply the update below too.
			await self._s.conn.execute(
				"UPDATE sessions SET metadata_json=? WHERE id=?",
				[json.dumps(meta, ensure_ascii=False), sid],
			)
			return True
		meta = sess.get("metadata") or {}
		if not isinstance(meta, dict):
			meta = {}
		consent = meta.get("consent") or {}
		if not isinstance(consent, dict):
			consent = {}
		consent["save_recordings"] = bool(enabled)
		meta["consent"] = consent

		await self._s.conn.execute(
			"UPDATE sessions SET metadata_json=? WHERE id=?",
			[json.dumps(meta, ensure_ascii=False), sid],
		)
		return True

	async def insert_event(self, e: Dict[str, Any]) -> str:
		evt_id = e.get("id") or e.get("event_id") or new_id("evt")
		await self._s.conn.execute(
			"""
			INSERT INTO events(id, session_id, event_type, source_id, seq, t_device, t_received, payload_json, provenance_json)
			VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)
			""",
			[
				evt_id,
				e.get("session_id") or (e.get("provenance") or {}).get("session_id"),
				e.get("event_type"),
				e.get("source_id"),
				int(e.get("seq", 0)),
				e.get("t_device"),
				float(e.get("t_received") or e.get("t_hub_received") or time.time()),
				json.dumps(e.get("payload", {}), ensure_ascii=False),
				json.dumps(e.get("provenance", {}), ensure_ascii=False),
			],
		)
		return evt_id

	async def insert_artifact(self, a: Dict[str, Any]) -> str:
		if self._enforce_provenance:
			validate_artifact_metadata(a["artifact_type"], a.get("metadata", {}) or {})
		art_id = a.get("id") or new_id("art")
		await self._s.conn.execute(
			"""
			INSERT INTO artifacts(id, artifact_type, uri, hash, created_at, metadata_json)
			VALUES(?, ?, ?, ?, ?, ?)
			""",
			[
				art_id,
				a["artifact_type"],
				a["uri"],
				a["hash"],
				time.time(),
				json.dumps(a.get("metadata", {}), ensure_ascii=False),
			],
		)
		return art_id

	async def get_artifact_record(self, artifact_id: str) -> Optional[Dict[str, Any]]:
		aid = (artifact_id or "").strip()
		if not aid:
			return None
		cur = await self._s.conn.execute("SELECT * FROM artifacts WHERE id=?", [aid])
		row = await cur.fetchone()
		cols = [d[0] for d in cur.description]
		await cur.close()
		if not row:
			return None
		out: Dict[str, Any] = {}
		for i, c in enumerate(cols):
			out[c] = row[i]
		# Decode JSON fields
		try:
			out["metadata_json"] = json.loads(out["metadata_json"]) if out.get("metadata_json") else {}
		except Exception:
			out["metadata_json"] = {}
		out["metadata"] = out.get("metadata_json") or {}
		return out

	async def delete_artifact(self, artifact_id: str) -> bool:
		aid = (artifact_id or "").strip()
		if not aid:
			return False
		cur = await self._s.conn.execute("DELETE FROM artifacts WHERE id=?", [aid])
		# sqlite rowcount is not always reliable; confirm via follow-up select
		deleted = (cur.rowcount or 0) > 0
		await cur.close()
		if deleted:
			return True
		cur2 = await self._s.conn.execute("SELECT 1 FROM artifacts WHERE id=?", [aid])
		row = await cur2.fetchone()
		await cur2.close()
		return row is None

	def _deep_merge_dicts(self, base: Dict[str, Any], patch: Dict[str, Any]) -> Dict[str, Any]:
		out: Dict[str, Any] = dict(base)
		for k, v in patch.items():
			if isinstance(v, dict) and isinstance(out.get(k), dict):
				out[k] = self._deep_merge_dicts(out.get(k) or {}, v)
			else:
				out[k] = v
		return out

	async def update_artifact_metadata(self, artifact_id: str, metadata_patch: Dict[str, Any], merge: bool = True) -> Optional[Dict[str, Any]]:
		aid = (artifact_id or "").strip()
		if not aid:
			return None
		rec = await self.get_artifact_record(aid)
		if not rec:
			return None
		current_meta = rec.get("metadata") or {}
		if not isinstance(current_meta, dict):
			current_meta = {}
		patch = metadata_patch or {}
		if not isinstance(patch, dict):
			patch = {}
		new_meta = self._deep_merge_dicts(current_meta, patch) if merge else patch
		if self._enforce_provenance:
			validate_artifact_metadata(str(rec.get("artifact_type") or ""), new_meta)
		await self._s.conn.execute(
			"UPDATE artifacts SET metadata_json=? WHERE id=?",
			[json.dumps(new_meta, ensure_ascii=False), aid],
		)
		rec["metadata"] = new_meta
		rec["metadata_json"] = new_meta
		return rec

	async def insert_entity(self, e: Dict[str, Any]) -> str:
		ent_id = e.get("id") or new_id("ent")
		await self._s.conn.execute(
			"""
			INSERT INTO entities(id, entity_type, name, summary, tags_json, created_at, metadata_json)
			VALUES(?, ?, ?, ?, ?, ?, ?)
			""",
			[
				ent_id,
				e["entity_type"],
				e.get("name"),
				e.get("summary"),
				json.dumps(e.get("tags", []), ensure_ascii=False),
				time.time(),
				json.dumps(e.get("metadata", {}), ensure_ascii=False),
			],
		)
		return ent_id

	async def insert_relation(self, r: Dict[str, Any]) -> str:
		rel_id = r.get("id") or new_id("rel")
		await self._s.conn.execute(
			"""
			INSERT INTO relations(id, relation_type, from_entity_id, to_entity_id, weight, created_at, metadata_json)
			VALUES(?, ?, ?, ?, ?, ?, ?)
			""",
			[
				rel_id,
				r["relation_type"],
				r["from_entity_id"],
				r["to_entity_id"],
				r.get("weight"),
				time.time(),
				json.dumps(r.get("metadata", {}), ensure_ascii=False),
			],
		)
		return rel_id

	async def create_job(self, j: Dict[str, Any]) -> str:
		"""
		Create a job record. Fields:
		- job_type (required)
		- status (required)
		- input_json/output_json/artifacts_json/metadata_json/error (optional)
		"""
		job_id = j.get("id") or new_id("job")
		await self._s.conn.execute(
			"""
			INSERT INTO jobs(id, job_type, status, created_at, started_at, completed_at, input_json, output_json, artifacts_json, error, metadata_json)
			VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
			""",
			[
				job_id,
				j["job_type"],
				j["status"],
				time.time(),
				j.get("started_at"),
				j.get("completed_at"),
				json.dumps(j.get("input", {}), ensure_ascii=False) if j.get("input") is not None else None,
				json.dumps(j.get("output", {}), ensure_ascii=False) if j.get("output") is not None else None,
				json.dumps(j.get("artifacts", []), ensure_ascii=False) if j.get("artifacts") is not None else None,
				j.get("error"),
				json.dumps(j.get("metadata", {}), ensure_ascii=False) if j.get("metadata") is not None else None,
			],
		)
		return job_id

	async def update_job_status(
		self,
		job_id: str,
		*,
		status: str,
		started_at: Optional[float] = None,
		completed_at: Optional[float] = None,
		error: Optional[str] = None,
		output: Optional[Dict[str, Any]] = None,
		artifacts: Optional[list[Dict[str, Any]]] = None,
	) -> None:
		await self._s.conn.execute(
			"""
			UPDATE jobs
			SET status=?,
			    started_at=COALESCE(?, started_at),
			    completed_at=COALESCE(?, completed_at),
			    error=COALESCE(?, error),
			    output_json=COALESCE(?, output_json),
			    artifacts_json=COALESCE(?, artifacts_json)
			WHERE id=?
			""",
			[
				status,
				started_at,
				completed_at,
				error,
				json.dumps(output, ensure_ascii=False) if output is not None else None,
				json.dumps(artifacts, ensure_ascii=False) if artifacts is not None else None,
				job_id,
			],
		)

	async def get_job(self, job_id: str) -> Optional[Dict[str, Any]]:
		cur = await self._s.conn.execute("SELECT * FROM jobs WHERE id=?", [job_id])
		row = await cur.fetchone()
		cols = [d[0] for d in cur.description]
		await cur.close()
		if not row:
			return None
		out: Dict[str, Any] = {}
		for i, c in enumerate(cols):
			out[c] = row[i]
		# Decode JSON fields
		for key in ("input_json", "output_json", "artifacts_json", "metadata_json"):
			try:
				out[key] = json.loads(out[key]) if out.get(key) else None
			except Exception:
				out[key] = None
		return out

	async def query(self, q: Dict[str, Any]) -> Dict[str, Any]:
		"""
		v1: query helper. Supports:
		- table: "events" | "artifacts" | "entities" | "relations"
		- limit (default 100, max 1000) + offset
		- where: dict of exact-match filters (small allowlist per table)
		- order_by + order_dir
		- time_range: {field, start?, end?}
		"""
		table = q.get("table")
		limit = int(q.get("limit") or 100)
		limit = max(1, min(limit, 1000))
		offset = int(q.get("offset") or 0)
		offset = max(0, min(offset, 1_000_000))
		where = q.get("where") or {}
		order_by = str(q.get("order_by") or "").strip()
		order_dir = str(q.get("order_dir") or "desc").strip().lower()
		time_range = q.get("time_range") or {}
		if table not in {"events", "artifacts", "entities", "relations", "jobs"}:
			raise ValueError("Invalid table")
		if not isinstance(where, dict):
			raise ValueError("where must be an object")
		if order_dir not in {"asc", "desc"}:
			raise ValueError("order_dir must be 'asc' or 'desc'")
		if time_range and not isinstance(time_range, dict):
			raise ValueError("time_range must be an object")

		allow = {
			# Allow exact id queries for UI clients (Godot) and internal helpers.
			"events": {"id", "session_id", "event_type", "source_id"},
			"artifacts": {"id", "artifact_type", "hash"},
			"entities": {"id", "entity_type", "name"},
			"relations": {"id", "relation_type", "from_entity_id", "to_entity_id"},
			"jobs": {"id", "job_type", "status"},
		}[table]

		# Allowed ordering/time fields per table (keep strict to avoid SQL injection).
		allow_order = {
			"events": {"t_received", "t_device", "seq"},
			"artifacts": {"created_at", "artifact_type"},
			"entities": {"created_at", "entity_type", "name"},
			"relations": {"created_at", "relation_type"},
			"jobs": {"created_at", "started_at", "completed_at", "job_type", "status"},
		}[table]

		clauses = []
		args = []
		for k, v in where.items():
			if k in allow and v is not None:
				clauses.append(f"{k}=?")
				args.append(v)

		# Optional time range
		if time_range:
			field = str(time_range.get("field") or "").strip()
			start = time_range.get("start", None)
			end = time_range.get("end", None)
			if field:
				if field not in allow_order:
					raise ValueError("Invalid time_range.field")
				try:
					if start is not None:
						clauses.append(f"{field}>=?")
						args.append(float(start))
					if end is not None:
						clauses.append(f"{field}<=?")
						args.append(float(end))
				except Exception:
					raise ValueError("time_range start/end must be numbers")

		sql = f"SELECT * FROM {table}"
		if clauses:
			sql += " WHERE " + " AND ".join(clauses)
		# Ordering
		default_order = "created_at" if table in {"artifacts", "entities", "relations", "jobs"} else "t_received"
		ob = order_by if order_by else default_order
		if ob not in allow_order:
			raise ValueError("Invalid order_by")
		sql += f" ORDER BY {ob} {order_dir.upper()}"
		sql += " LIMIT ?"
		args.append(limit)
		if offset:
			sql += " OFFSET ?"
			args.append(offset)

		cur = await self._s.conn.execute(sql, args)
		rows = await cur.fetchall()
		cols = [d[0] for d in cur.description]
		await cur.close()
		return {"table": table, "columns": cols, "rows": rows}

	async def commit(self) -> None:
		await self._s.conn.commit()


