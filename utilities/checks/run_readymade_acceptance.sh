#!/usr/bin/env bash
# Headless ReadyMade acceptance: workplan save/load (+ legacy migration) and
# ADR 0024 instrument mapping. Non-zero exit on failure.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLIENT="$ROOT/synesyn_client"
SCENE="res://readymade/test_acceptance_workplan_instruments.tscn"

GODOT_BIN="${GODOT_BIN:-}"
if [[ -z "$GODOT_BIN" ]]; then
  if command -v godot >/dev/null 2>&1; then
    GODOT_BIN="$(command -v godot)"
  elif [[ -x "$HOME/bin/godot" ]]; then
    GODOT_BIN="$HOME/bin/godot"
  else
    echo "Godot executable not found. Set GODOT_BIN or install godot on PATH." >&2
    exit 127
  fi
fi

if [[ ! -f "$CLIENT/addons/limboai/bin/limboai.gdextension" ]]; then
  echo "LimboAI binaries missing under synesyn_client/addons/limboai/bin/." >&2
  echo "See docs/developer-guide/local-dev.md" >&2
  exit 127
fi

echo "Using Godot: $GODOT_BIN"
echo "Running: $SCENE"
exec "$GODOT_BIN" --headless --path "$CLIENT" "$SCENE"
