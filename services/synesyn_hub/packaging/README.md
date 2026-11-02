## Synesyn Hub packaging (Windows, PyInstaller)

This folder is for **developers** building `synesyn_hub.exe`. End users should not need a CLI; the Godot app will launch the executable.

### Prereqs
- Conda env: `synesyn-hub` (Python 3.11)
- Install packaging deps:

```powershell
conda run -n synesyn-hub pip install pyinstaller==6.10.0
```

### Build

```powershell
./packaging/build_windows.ps1
```

Outputs:
- `dist/synesyn_hub/synesyn_hub.exe`

Canonical runtime layout:
- `dist/synesyn_hub/synesyn_hub.exe`
- `dist/synesyn_hub/_internal/...`

Guardrail (avoid mixed pipelines / stale binaries):
- Do not run or ship `synesyn_hub.exe` directly under `services/synesyn_hub/`.
- Do not keep `_internal` directly under `services/synesyn_hub/`.
- The build script now pre-cleans those root-level stale artifacts before building.

### Runtime notes
- Data **never** writes into the shipped folder. Workspace data lives under `~/Documents/Synesyn/<workspace_slug>/`.
- Godot should call `POST /workspace/select` on first-run to set the workspace, then poll `/health`.
- Hub lifecycle: if `hub.stop_on_exit == true`, the Godot client will best-effort stop the hub at app exit.
  - Primary path: `POST /admin/shutdown` (local-only endpoint).
  - Deterministic fallback: if the client spawned the hub process, it records the PID and will kill that PID on exit if needed.
  - This design intentionally avoids stopping hubs that were started externally (e.g. user double-clicked the exe).

### Critical packaging note: optional deps must not crash the hub

In packaged builds, the hub runs inside its bundled Python environment (PyInstaller). Even if a module is installed in your system Python, it may **not** exist inside the executable unless explicitly bundled.

Rules:

- The hub must **start and serve `/health`** even if optional features are unavailable (e.g. voice STT/TTS providers).
- Voice/STT/TTS dependencies should be treated as **optional** and fail at request-time with clear `503` errors rather than crashing at import-time.

Known “gotchas” we hit:

- `whisper` missing → hub crashed on import (STT must be optional)
- `pydub`/`audioop` missing → hub crashed on import (avoid brittle audio deps in the packaged path)

### Debugging “hub spawned but exited”

If Godot reports the hub process exited, run the exe directly to capture the traceback:

```cmd
services\synesyn_hub\synesyn_hub.exe
```

The top-most `ModuleNotFoundError` is usually the actionable root cause (a missing packaged dependency).


