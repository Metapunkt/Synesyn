from __future__ import annotations

import importlib
import logging
from typing import Any, Dict, List

from fastapi import FastAPI

from .base import PluginLoadResult


log = logging.getLogger("synesyn_hub.plugins")


def load_plugins(app: FastAPI, plugin_names: List[str]) -> Dict[str, Any]:
	"""
	Minimal hub plugin system (v1):
	- plugin module: `app.plugins.<name>`
	- optional entrypoint: `register(app) -> dict` returning capability flags

	Plugins are *best-effort*: load errors are recorded and do not prevent hub startup.
	"""
	results: List[PluginLoadResult] = []
	combined_caps: Dict[str, Any] = {}

	for name in plugin_names or []:
		n = str(name).strip()
		if not n:
			continue
		mod_name = f"app.plugins.{n}"
		try:
			mod = importlib.import_module(mod_name)
			plugin_caps: Dict[str, Any] = {}
			if hasattr(mod, "register"):
				caps = mod.register(app)  # type: ignore[attr-defined]
				if isinstance(caps, dict):
					plugin_caps = {str(k): v for k, v in caps.items()}
					combined_caps.update({f"plugin.{n}.{k}": v for k, v in plugin_caps.items()})
			results.append(PluginLoadResult(name=n, ok=True, capabilities=plugin_caps))
			log.info("Loaded plugin: %s", n)
		except Exception as e:
			results.append(PluginLoadResult(name=n, ok=False, error=str(e)))
			log.exception("Failed to load plugin %s", n)

	return {
		"plugins": [r.__dict__ for r in results],
		"ok": all(r.ok for r in results) if results else True,
		"capabilities": combined_caps,
	}


