from __future__ import annotations

import asyncio
import json
import logging
import os
import subprocess
import sys
from dataclasses import dataclass
from typing import Any, Dict, Optional
from urllib.request import Request, urlopen


log = logging.getLogger("synesyn_hub.voice.sidecar")


def _post_json_sync(url: str, payload: Dict[str, Any], timeout_sec: float = 8.0) -> Dict[str, Any]:
	"""
	Minimal JSON POST without adding new deps (httpx/aiohttp).
	Runs in a worker thread via asyncio.to_thread.
	"""
	body = json.dumps(payload).encode("utf-8")
	req = Request(url=url, data=body, headers={"Content-Type": "application/json"}, method="POST")
	with urlopen(req, timeout=timeout_sec) as resp:
		raw = resp.read().decode("utf-8") if resp else ""
		obj = json.loads(raw) if raw else {}
		return obj if isinstance(obj, dict) else {"ok": False, "error": "invalid_json", "raw": raw}


def _get_json_sync(url: str, timeout_sec: float = 4.0) -> Dict[str, Any]:
	req = Request(url=url, headers={"Accept": "application/json"}, method="GET")
	with urlopen(req, timeout=timeout_sec) as resp:
		raw = resp.read().decode("utf-8") if resp else ""
		obj = json.loads(raw) if raw else {}
		return obj if isinstance(obj, dict) else {"ok": False, "error": "invalid_json", "raw": raw}


@dataclass(frozen=True)
class VoiceSidecarConfig:
	enabled: bool
	base_url: str
	cmd: str
	args: list[str]
	cwd: str


class VoiceSidecarManager:
	"""
	Hub-managed sidecar for voice engines.
	The hub remains the system-of-record (artifacts/provenance); the sidecar only computes bytes/text.
	This module exists to support packaging topology "Option 2" (hub-managed sidecar) from the SynTree Voice checklist:
	- Users still interact with ONE endpoint (the hub).
	- Godot starts/stops the hub; the hub optionally starts/stops the sidecar.
	- Voice artifacts/provenance are still persisted by the hub (not by the sidecar).
	Expected legacy sidecar API:
	  - GET  /health -> {"status":"ok"} (or {"ok":true})
	  - POST /synthesize -> {"success":true, "audio":"<base64>", "lipsync":[...], "duration":float}
	  - POST /transcribe -> {"success":true, "text":"..."}
	"""

	def __init__(self, cfg: VoiceSidecarConfig, logs_path: Optional[str] = None):
		self.cfg = cfg
		self._proc: Optional[asyncio.subprocess.Process] = None
		self._logs_path = logs_path

	def is_enabled(self) -> bool:
		return bool(self.cfg.enabled)

	def base_url(self) -> str:
		return (self.cfg.base_url or "").strip().rstrip("/")

	async def start(self) -> None:
		if not self.is_enabled():
			return
		if self._proc and self._proc.returncode is None:
			return
		# cmd/args are optional: if cmd is empty, hub will assume the sidecar is managed externally
		# and will only use it if it responds to /health.
		cmd = (self.cfg.cmd or "").strip()
		if not cmd:
			# Sidecar may be managed externally; we can still proxy if it's reachable.
			return
		args = list(self.cfg.args or [])

		cwd = (self.cfg.cwd or "").strip() or None
		log.info("Starting voice sidecar: %s %s (cwd=%s)", cmd, " ".join(args), cwd or "")

		stdout = None
		stderr = None
		if self._logs_path:
			try:
				os.makedirs(os.path.dirname(self._logs_path), exist_ok=True)
				f = open(self._logs_path, "a", encoding="utf-8")
				stdout = f
				stderr = subprocess.STDOUT
			except Exception:
				stdout = None
				stderr = None

		# Use subprocess.create_subprocess_exec so startup doesn't block the event loop.
		self._proc = await asyncio.create_subprocess_exec(
			cmd,
			*args,
			cwd=cwd,
			stdout=stdout,
			stderr=stderr,
		)

	async def stop(self) -> None:
		if not self._proc:
			return
		if self._proc.returncode is not None:
			return
		try:
			self._proc.terminate()
		except ProcessLookupError:
			return
		try:
			await asyncio.wait_for(self._proc.wait(), timeout=3.0)
		except asyncio.TimeoutError:
			try:
				self._proc.kill()
			except Exception:
				pass

	async def check_health(self) -> bool:
		if not self.is_enabled():
			return False
		url = self.base_url()
		if not url:
			return False
		try:
			obj = await asyncio.to_thread(_get_json_sync, url + "/health", 3.0)
			if obj.get("ok") is True:
				return True
			if str(obj.get("status", "")).lower() == "ok":
				return True
		except Exception:
			return False
		return False

	async def synthesize(self, text: str, character: str, voice_name: str) -> Dict[str, Any]:
		url = self.base_url()
		return await asyncio.to_thread(
			_post_json_sync,
			url + "/synthesize",
			{"text": text, "character": character, "voice": (voice_name or "")},
			12.0,
		)

	async def transcribe(self, audio_base64: str, audio_format: str = "wav", language: str = "en") -> Dict[str, Any]:
		url = self.base_url()
		return await asyncio.to_thread(
			_post_json_sync,
			url + "/transcribe",
			{"audio_base64": audio_base64, "audio_format": audio_format, "language": language},
			18.0,
		)


