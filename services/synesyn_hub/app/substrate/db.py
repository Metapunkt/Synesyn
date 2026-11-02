from __future__ import annotations

import logging
from pathlib import Path
from typing import Optional

import aiosqlite


log = logging.getLogger("synesyn_hub.substrate")


SCHEMA_SQL = """
PRAGMA journal_mode=WAL;
PRAGMA synchronous=NORMAL;

CREATE TABLE IF NOT EXISTS schema_version (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

INSERT OR IGNORE INTO schema_version(key, value) VALUES('version', '0');

CREATE TABLE IF NOT EXISTS sessions (
  id TEXT PRIMARY KEY,
  created_at REAL NOT NULL,
  app_id TEXT,
  scenario_id TEXT,
  scenario_version TEXT,
  participants_json TEXT,
  metadata_json TEXT
);

CREATE TABLE IF NOT EXISTS events (
  id TEXT PRIMARY KEY,
  session_id TEXT,
  event_type TEXT NOT NULL,
  source_id TEXT NOT NULL,
  seq INTEGER NOT NULL,
  t_device REAL,
  t_received REAL NOT NULL,
  payload_json TEXT NOT NULL,
  provenance_json TEXT
);

CREATE INDEX IF NOT EXISTS idx_events_session_time ON events(session_id, t_received);
CREATE INDEX IF NOT EXISTS idx_events_type_time ON events(event_type, t_received);

CREATE TABLE IF NOT EXISTS artifacts (
  id TEXT PRIMARY KEY,
  artifact_type TEXT NOT NULL,
  uri TEXT NOT NULL,
  hash TEXT NOT NULL,
  created_at REAL NOT NULL,
  metadata_json TEXT
);

CREATE INDEX IF NOT EXISTS idx_artifacts_type ON artifacts(artifact_type);
CREATE INDEX IF NOT EXISTS idx_artifacts_hash ON artifacts(hash);

CREATE TABLE IF NOT EXISTS entities (
  id TEXT PRIMARY KEY,
  entity_type TEXT NOT NULL,
  name TEXT,
  summary TEXT,
  tags_json TEXT,
  created_at REAL NOT NULL,
  metadata_json TEXT
);

CREATE INDEX IF NOT EXISTS idx_entities_type ON entities(entity_type);
CREATE INDEX IF NOT EXISTS idx_entities_name ON entities(name);

CREATE TABLE IF NOT EXISTS relations (
  id TEXT PRIMARY KEY,
  relation_type TEXT NOT NULL,
  from_entity_id TEXT NOT NULL,
  to_entity_id TEXT NOT NULL,
  weight REAL,
  created_at REAL NOT NULL,
  metadata_json TEXT
);

CREATE INDEX IF NOT EXISTS idx_relations_type ON relations(relation_type);
CREATE INDEX IF NOT EXISTS idx_relations_from ON relations(from_entity_id);
CREATE INDEX IF NOT EXISTS idx_relations_to ON relations(to_entity_id);

-- Jobs (v0): background compute requests (e.g., SynAxes project/cluster)
CREATE TABLE IF NOT EXISTS jobs (
  id TEXT PRIMARY KEY,
  job_type TEXT NOT NULL,
  status TEXT NOT NULL, -- queued|started|completed|failed
  created_at REAL NOT NULL,
  started_at REAL,
  completed_at REAL,
  input_json TEXT,
  output_json TEXT,
  artifacts_json TEXT,
  error TEXT,
  metadata_json TEXT
);

CREATE INDEX IF NOT EXISTS idx_jobs_status_time ON jobs(status, created_at);
CREATE INDEX IF NOT EXISTS idx_jobs_type_time ON jobs(job_type, created_at);
"""


class Substrate:
	def __init__(self, db_path: Path):
		self.db_path = db_path
		self._conn: Optional[aiosqlite.Connection] = None

	async def open(self) -> None:
		self.db_path.parent.mkdir(parents=True, exist_ok=True)
		self._conn = await aiosqlite.connect(self.db_path)
		await self._conn.executescript(SCHEMA_SQL)
		await self._conn.commit()
		log.info("Substrate opened at %s", self.db_path)

	async def close(self) -> None:
		if self._conn:
			await self._conn.close()
			self._conn = None

	@property
	def conn(self) -> aiosqlite.Connection:
		if not self._conn:
			raise RuntimeError("Substrate not opened")
		return self._conn


