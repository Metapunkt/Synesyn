#!/usr/bin/env bash
# Fresh-clone import + main-scene smoke.
# Simulates first open then a second launch (after Project > Reload): wipe .godot,
# import once, then run the main scene and fail on LimboAI/script parse errors
# that persist past the first import.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLIENT="$ROOT/synesyn_client"
LOG="${TMPDIR:-/tmp}/synesyn_fresh_import_smoke.log"

GODOT_BIN="${GODOT_BIN:-}"
if [[ -z "$GODOT_BIN" ]]; then
  if command -v godot >/dev/null 2>&1; then
    GODOT_BIN="$(command -v godot)"
  elif [[ -x "$HOME/bin/godot" ]]; then
    GODOT_BIN="$HOME/bin/godot"
  elif [[ -x "$HOME/bin/godot-4.7.2" ]]; then
    GODOT_BIN="$HOME/bin/godot-4.7.2"
  else
    echo "Godot executable not found. Set GODOT_BIN or install godot on PATH." >&2
    exit 127
  fi
fi

if [[ ! -f "$CLIENT/addons/limboai/bin/limboai.gdextension" ]]; then
  echo "LimboAI binaries missing under synesyn_client/addons/limboai/bin/." >&2
  echo "See docs/developer-guide/local-dev.md#recommended-builds" >&2
  exit 127
fi

echo "Using Godot: $GODOT_BIN"
echo "Fresh-clone smoke: wiping $CLIENT/.godot"
rm -rf "$CLIENT/.godot"
: >"$LOG"

echo "==> Pass 1: headless import (first open; transient errors OK)"
set +e
"$GODOT_BIN" --headless --path "$CLIENT" --import --quit-after 120 >>"$LOG" 2>&1
IMPORT_EXIT=$?
set -e
echo "Import exit: $IMPORT_EXIT" | tee -a "$LOG"

if [[ ! -f "$CLIENT/.godot/extension_list.cfg" ]]; then
  echo "FAIL: .godot/extension_list.cfg was not generated after import" | tee -a "$LOG" >&2
  exit 1
fi
if ! grep -q 'limboai.gdextension' "$CLIENT/.godot/extension_list.cfg"; then
  echo "FAIL: LimboAI not listed in extension_list.cfg after import" | tee -a "$LOG" >&2
  cat "$CLIENT/.godot/extension_list.cfg" >&2 || true
  exit 1
fi

echo "==> Pass 2: run main scene (post-reload equivalent)"
MAIN_LOG="${TMPDIR:-/tmp}/synesyn_fresh_import_main.log"
: >"$MAIN_LOG"
set +e
"$GODOT_BIN" --headless --path "$CLIENT" --quit-after 25 >>"$MAIN_LOG" 2>&1
MAIN_EXIT=$?
set -e
cat "$MAIN_LOG" >>"$LOG"
echo "Main-scene exit: $MAIN_EXIT" | tee -a "$LOG"

# Fail only on errors that persist after import (pass 2).
FAIL_PATTERNS=(
  'Parse Error:.*Could not find type "BT'
  'Parse Error:.*Could not find base class "BT'
  'Could not find type "BTPlayer"'
  'Failed to load script "res://readymade/agents/a1_agent.gd"'
  'Failed to load script "res://ScenSyn/scripts/agents/narrator_agent.gd"'
)

FAILED=0
for pat in "${FAIL_PATTERNS[@]}"; do
  if grep -E "$pat" "$MAIN_LOG" >/dev/null; then
    echo "FAIL: matched /$pat/ in post-import main-scene log" | tee -a "$LOG" >&2
    FAILED=1
  fi
done

if [[ "$FAILED" -ne 0 ]]; then
  echo "---- post-import main-scene errors (tail) ----" >&2
  grep -E 'Parse Error|Could not find type|Failed to load script|ERROR:' "$MAIN_LOG" | head -80 >&2 || true
  exit 1
fi

echo "Fresh-import smoke PASSED (LimboAI registered; no persistent BT*/a1_agent parse errors)"
exit 0
