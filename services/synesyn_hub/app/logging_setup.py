from __future__ import annotations

import json
import logging
from logging.handlers import RotatingFileHandler
from pathlib import Path
from typing import Optional
import sys

from .config import HubConfig


class JsonFormatter(logging.Formatter):
	def format(self, record: logging.LogRecord) -> str:
		payload = {
			"level": record.levelname,
			"logger": record.name,
			"message": record.getMessage(),
			"time": self.formatTime(record, datefmt="%Y-%m-%dT%H:%M:%S"),
		}
		if record.exc_info:
			payload["exc_info"] = self.formatException(record.exc_info)
		return json.dumps(payload, ensure_ascii=False)


def setup_logging(cfg: HubConfig) -> None:
	root = logging.getLogger()
	root.setLevel(logging.INFO)

	# Avoid duplicate handlers in reload scenarios
	for h in list(root.handlers):
		root.removeHandler(h)

	console = logging.StreamHandler()
	console.setFormatter(logging.Formatter("[%(levelname)s] %(name)s: %(message)s"))
	root.addHandler(console)

	def _maybe_add_file_handler(log_dir: Optional[Path], filename: str) -> None:
		if not log_dir:
			return
		try:
			log_dir.mkdir(parents=True, exist_ok=True)
			log_path = log_dir / filename
			file_handler = RotatingFileHandler(log_path, maxBytes=5_000_000, backupCount=3, encoding="utf-8")
			file_handler.setFormatter(JsonFormatter())
			root.addHandler(file_handler)
		except Exception:
			# Logging must never prevent the hub from starting.
			return

	log_dir: Optional[Path] = cfg.workspace.logs_dir if cfg.workspace else None
	_maybe_add_file_handler(log_dir, "synesyn_hub.log.jsonl")

	# v0 "no-CLI" packaging: a packaged build also logs into the install tree at
	# <install>/services/hub/logs/, where a user expects to find logs next to the
	# service. Only a packaged build: running from source, the same lookup lands in
	# the repository working tree, which is not a deployment location (ADR 0018) and
	# leaves operational logs among the source. The workspace handler above already
	# covers development.
	if getattr(sys, "frozen", False):
		try:
			exe = Path(sys.executable).resolve()
			services_dir: Optional[Path] = None
			for parent in exe.parents:
				if parent.name == "services":
					services_dir = parent
					break
			if services_dir is None and exe.parent.name == "synesyn_hub":
				services_dir = exe.parent.parent
			if services_dir:
				_maybe_add_file_handler(services_dir / "hub" / "logs", "synesyn_hub.log.jsonl")
		except Exception:
			pass


