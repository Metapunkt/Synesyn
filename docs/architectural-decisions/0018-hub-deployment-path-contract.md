# 0018 — Hub deployment path contract (one location, one resolver)

- **Status:** Accepted
- **Date:** 2026-09-05
- **Area:** client / tooling / packaging
- **Relates to:** ADR 0017 (`synesyn_core` shared library addon)

> Amendment note (2026-09-18): the client directory named `synesyn_dec2025/`
> below is now `synesyn_client/` (ADR 0023). The paths are left as written
> because they record the misresolution this ADR diagnosed; the contract itself
> is unaffected, since it fixes the hub location relative to the repository root
> rather than to the client directory's name.

## Context

The editor logged `hub autostart skipped (hub exe not found). Expected path like
services/synesyn_hub/`. Investigating it exposed that "where does the hub live"
had three mutually inconsistent answers.

`Local_Deployment_Runbook.md` (normative for packaging) and
`validate_windows_layout.ps1` both said `services/synesyn_hub/synesyn_hub.exe`.
All five shipped releases matched that: the Godot exe sits beside
`services/synesyn_hub/` holding a flattened one-dir bundle (`synesyn_hub.exe` +
`_internal/`), with no `.venv`, `build/`, `dist/`, or `tests/`.

The client disagreed. Four independent copies of `_find_default_hub_exe()` —
`scripts/synesyn_launcher.gd`, `ScenSyn/scripts/services/services_panel.gd`,
`addons/syntree_voice/.../voice_service_manager.gd`, and
`addons/synpunkt/scripts/internal/startup_utils.gd` — probed up to eight
candidates each and disagreed with one another. Their comments labelled
`services/synesyn_hub/dist/synesyn_hub/` "canonical" and the actually-shipped
flat path a "legacy fallback", exactly inverting reality: `dist/` is PyInstaller
build output that packaging flattens away. In production the `dist/` candidate
always missed and the "legacy" one always hit, so autostart worked only by
accident of candidate ordering. SynPunkt's copy had no `dist/` candidates at all;
two copies hardcoded `.exe`, breaking non-Windows; they disagreed on whether to
return `""` or a non-existent path when nothing was found.

Three classes of candidate could never resolve in production: `dist/` paths
(build tree), grandparent-directory paths (no layout, runbook entry, or validator
rule uses them), and `res://services/...` (the Godot project contains no
`services/` directory — this was the actual warning).

The tooling that should have enforced the contract could not run.
`package_windows.ps1` resolved `$repoRoot` to `synesyn_dec2025` and required
`synesyn_dec2025/services`, which does not exist; the services tree is a
*sibling* of the Godot project. It also demanded `Synesyn.exe` plus `Synesyn.pck`
while the export preset emits a versioned name with `embed_pck=true`, and would
have recursively copied `.venv/`, `build/`, `dist/`, and `tests/` into the
release. It threw on its first path check, so every release was assembled by
hand — which is how the layout drifted (v0.0.4 shipped a stray `services/hub/logs`;
`sd_exhibition_build` shipped the raw `dist/` tree).

Two PyInstaller specs also disagreed: `services/synesyn_hub/synesyn_hub.spec` was
a **one-file** build with `console=True` producing a bare `dist/synesyn_hub.exe`
matching no candidate and no validator rule, while
`packaging/synesyn_hub.spec` was the **one-dir** build every release used.

## Options considered

1. **Broaden the candidate ladders** so every layout resolves everywhere — Pros:
   no packaging change. Cons: entrenches guessing; a wrong-but-present hub still
   wins silently; four copies still drift.
2. **One production path, one shared resolver, enforced by tooling** — Pros:
   a single answer to "where does it go" and "where do we look"; failures are
   explicit; packaging produces what the client probes. Cons: touches four call
   sites, two scripts, and drops a documented (unused) layout.
3. **Absolute `hub.exec_path` in config as the only mechanism** — Pros: trivial.
   Cons: pushes machine-specific setup onto every user; no zero-config release.

## Decision

Adopt option 2.

**Contract.** In a packaged build the hub lives at exactly one location:

```
<folder containing the Godot executable>/services/synesyn_hub/synesyn_hub[.exe]
```

holding the flattened contents of PyInstaller's `dist/synesyn_hub/` (executable
plus its `_internal/` sibling). "Layout B" (`godot/Synesyn.exe` with a sibling
`services/`) is withdrawn — no release used it.

**Single resolver.** `addons/synesyn_core/scripts/hub_locator.gd` (`HubLocator`)
is the only place that answers the question. It sits in `synesyn_core` because
both product addons and the host need it, and ADR 0017 rule 1 forbids addons
reaching into `res://scripts/**`. Search order:

1. `hub.exec_path` from runtime config, when set (explicit user override).
2. The production path above.
3. Editor-only dev paths, gated on `OS.has_feature("editor")`.

`find_hub_exe()` returns `""` when the hub is absent; callers must not pass a
guessed path to a process launcher. `get_suggested_path()` exists separately for
UI prefill, where a non-existent path is meaningful.

**Dev is a branch, not a candidate.** In the repo the Godot project
(`synesyn_dec2025/`) is a *sibling* of `services/`, so exe-relative resolution
cannot work in the editor. Rather than mixing repo paths into the production
ladder, `get_dev_paths()` returns the build-output and flattened locations and is
empty in exported builds.

**Tooling produces and verifies the contract.** `build_windows.ps1` is the sole
build entry point, asserts a one-dir bundle exists afterwards, and documents
`packaging/synesyn_hub.spec` as regenerated output rather than a source file. The
divergent one-file spec is retired. `package_windows.ps1` resolves the services
tree as a sibling of the project, flattens `dist/synesyn_hub/` into place, accepts
a versioned exe with embedded pck, and validates before zipping.
`validate_windows_layout.ps1` checks the single layout and fails on a shipped
`dist/`, `build/`, `.venv/`, or `tests/` inside the hub folder.

## Consequences

- Positive: one documented answer for where the built hub is deposited and where
  the client looks. A release is reproducible by two scripted steps instead of
  hand-assembly, and the validator catches the flatten mistake — the specific
  error that would otherwise ship a hub the client cannot find.
- Positive: the resolver is OS-correct in one place, so non-Windows targets no
  longer depend on which copy ran.
- Negative / trade-offs: a hub placed anywhere else now requires an explicit
  `hub.exec_path` rather than being found by tolerant probing. This is deliberate —
  silent discovery of an unexpected hub was itself a failure mode — but it means
  ad-hoc layouts must be configured, not guessed.
- Negative: dev and production resolve differently by construction. The dev
  branch is `OS.has_feature("editor")`-gated and therefore cannot affect a
  release, but it does mean "works in the editor" is not evidence the packaged
  path is correct. Run `validate_windows_layout.ps1` for that.
- Follow-ups: `check_line_limits.py` and `addon_compile_sweep.gd` do not detect
  path-contract drift. The guard against a fifth resolver appearing is convention
  plus this ADR; `.cursor/rules/` may warrant a scoped rule if it recurs.
