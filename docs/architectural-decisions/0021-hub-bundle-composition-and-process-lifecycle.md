# 0021 — Hub bundle composition and process lifecycle

- **Status:** Accepted
- **Date:** 2026-09-13
- **Area:** hub / client / tooling
- **Relates to:** ADR 0018 (hub deployment path contract)

## Context

An external reviewer reported that their machine froze whenever the hub was
running, that the freeze affected every other application and not just Synesyn,
and that the hub could not be restarted afterwards even after closing and
reopening the client. A reboot cleared it. We could not reproduce the freeze,
and had until then treated it as unverified.

Inspecting the shipped artefact rather than the reviewer's machine explained it.
The bundle was **4.68 GB, of which roughly 3.9 GB was CUDA**: `torch_cuda.dll`
at 1.2 GB, `magma.dll` at 804 MB, then cuBLAS, cuSPARSE, cuFFT and cuSOLVER.
Nothing in the hub uses a GPU — a search for `torch.cuda`, `.to(device)`,
`transformers`, `onnx` and similar returns nothing, `app/voice/stt.py` pins
`device="cpu"` with `fp16=False`, TTS is `edge_tts` or Windows SAPI, the vector
index is a hand-rolled 16-dimension function, and there is no LLM in the hub at
all (generation is client-side against remote APIs). `environment.yml` already
asked for CPU-only via the pytorch channel's `cpuonly` metapackage, but the
`pytorch` package resolved from **conda-forge** as `cuda128_mkl_py311`:
`cpuonly` does not constrain conda-forge builds, so the declared intent was
silently ignored.

Two further faults compounded it. `WorkspaceBootstrapper.register_hub_process()`
stored a **single** pid, but the Launcher and VoiceService both autostart a hub
and, on a cold start, neither sees the other's process in time; when both
spawned, the second registration overwrote the first and that hub could never be
stopped by the app again. The lifecycle log records this happening repeatedly,
with two registrations one second apart and only the later pid killed. And
`ScenSyn/.../services_panel.gd`'s Stop button called `stop_hub()`, which
early-returns unless it holds a pid, so the one visible control for clearing an
orphan did nothing against one.

Separately, Whisper weights were **not** bundled. Only ~1.7 MB of tokeniser and
mel assets shipped, so the first transcription downloaded 138.5 MB from OpenAI's
CDN inside a request the client was already awaiting, with `--noconsole`
suppressing any sign of it. This is invisible to any developer whose
`~/.cache/whisper` is already warm, which is why it never showed up for us.

## Options considered

1. **Treat it as the reviewer's hardware** — Pros: no work. Cons: the artefact
   evidence contradicts it; a 4.7 GB bundle whose bulk is dead GPU code is
   indefensible regardless of who reports it.
2. **Exclude CUDA at the PyInstaller layer** (`--exclude-module`) — Pros: no
   environment change. Cons: fights the hook system, and the environment still
   holds a CUDA torch so the next contributor rebuilds the same bundle.
3. **Fix the declaration, enforce it at build time, and repair the lifecycle** —
   Pros: the environment, the build and the runtime agree; failures are loud.
   Cons: touches the env, the build script, two client scripts and the hub entry
   point.

## Decision

Adopt option 3.

**CPU-only is a build invariant, not a preference.** `environment.yml` names
conda-forge's `pytorch-cpu` explicitly instead of relying on `cpuonly`, and pins
`numpy=2.1.3` because `openai-whisper` pulls in numba, which refuses NumPy newer
than 2.3 and fails at import — the first CPU swap regressed STT exactly that way.
`build_windows.ps1` now reads `torch.version.cuda` and **fails the build** if it
is not `None`, so the packaged artefact cannot silently reacquire the GPU payload.

**Whisper weights ship with the bundle.** The build stages `base.pt` (from the
local cache, downloading once if absent) and adds it as data; `stt.py` resolves
`download_root` to `sys._MEIPASS/models` when frozen and falls back to the user
cache otherwise. First voice use now needs no network.

**Every spawned hub is tracked.** `_hub_pids_started_by_client` is a list, and
`_shutdown_hub_best_effort()` kills all of them. A hub that lost the port race
still holds its memory, so leaving any behind is what strands the machine.

**Stop works without a pid.** `HubProcessManager` gains `is_reachable()` from
its existing health poll, plus `stop_hub_async()`, which kills a pid it owns and
otherwise asks the running hub to exit via the local-only `/admin/shutdown`.
`start_hub()` adopts a reachable hub instead of spawning a duplicate that cannot
bind, and reports `-1` so callers do not register a process they do not own.

**Bind failure is reported.** `uvicorn.run` is wrapped: an `OSError` is logged
with the remedy and exits `98`, rather than vanishing under `--noconsole`.

**The build cannot report false success.** `$LASTEXITCODE` is checked after
PyInstaller and the output exe must be newer than the build start. Both were
needed: a failed build leaves the previous exe in place, and the existence-only
checks passed, so the script printed `Done. Output:` and exited 0 while shipping
a stale binary. A running hub holds that exe open and is now detected up front
(`-StopRunningHub` to clear it) instead of failing minutes in.

## Consequences

- Positive: the bundle is **1.12 GB, down from 4.68 GB**, while now *including*
  the 138.5 MB of weights it previously downloaded. The packaged hub answers
  `/health` about two seconds after launch and transcribes with the user cache
  removed, proving the bundled weights are used.
- Positive: a verification run no longer leaks hubs. Runs previously stranded two
  processes at roughly 470 MB each; the lifecycle log now shows registration and
  a matching kill, with none left behind.
- Positive: the reviewer's account is explained without needing to reproduce the
  freeze, and the remaining orphan case (abnormal client exit, where no handler
  can run) is now recoverable from Settings rather than only by reboot.
- Negative / trade-offs: STT is CPU-bound by contract. If Whisper `base` proves
  too slow the answer is `faster-whisper` with int8, or `base.en`, not a GPU —
  requiring one would exclude the ordinary laptops a facilitator pilot runs on.
- Negative: the bundle carries weights for one model size only. Offering a choice
  of model would mean shipping more, or restoring the download for the rest.
- Follow-ups: an adopted hub is deliberately left unregistered and so survives
  client exit; this is correct for an externally started hub but means an orphan
  adopted after a crash must be stopped explicitly. The Launcher/VoiceService
  spawn race is mitigated (both hubs now die on exit) but not eliminated; a
  single spawn owner would remove it. `services_panel.gd` is at 1173 lines, in
  the soft band and worth splitting before it grows further.
