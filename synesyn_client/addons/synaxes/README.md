# SynAxes — pattern synthesis + closure formation

Walk your material as a space and leave with a few closures you can stand behind.

SynAxes is the **Synthesize** layer of the Synesyn stack: import material, discover patterns, review candidates, and **explicitly commit** versioned `ui.closure` artifacts. Other modules (SynPunkt, SynTree, ScenSyn) consume those closures; they should not re-implement SynAxes discovery.

**Status:** V1 complete (import → embed → discover → curate → commit). V2 is **Closure Map orientation + Proxistance** (ADR 0015) — not a physics spacetime canvas. Orientation tags and Coverage exist; fuller Proxistance navigation UX remains later work.

---

## For Synesyn Tools users

Open **Tools → SynAxes**. Default spine:

**Import → Explore → Choose → Name → Commit**

1. Import a Hub context graph (latest CTA when available), ScenSyn session data, or a labeled demo.
2. Discover with Advanced closed (local themes by default).
3. Review **Pattern Overview** (default after discover); use 3D Pattern Space when useful.
4. **Work on this** in Dream Inbox → name / intent / optional Orientation → **Commit** to Hub.
5. Coverage updates for Saved Closures; optional next step into SynPunkt Closures.

**Hub dependency:** Commit and published-graph import require Synesyn Hub. Demo + local discover work offline for rehearsal.

**Human commit:** Machine proposals are editable; only explicit commit creates a canonical artifact (no silent overwrite). Model embeddings (when offered) require a disclosed, remembered opt-in — item text is not sent to a third-party provider silently.

Facilitator one-pager: `synesyn/docs/user-guide/synaxes.md`. Pipeline context: `synesyn/docs/user-guide/facilitator-workflow.md`.

Power controls (discovery method, dim-reduction, Hub jobs, embedding tier, cache stats) live under **Advanced**.

---

## For Godot developers (this addon)

### Drop-in (ADR 0017)

SynAxes is a product addon. It is **not** a single orphan folder: shared config, Hub client, and theme services live in `synesyn_core`.

```
addons/synesyn_core/   ← required (enable first)
addons/synaxes/        ← this addon
```

Verified expectation: `synesyn_core` + SynAxes parses and enables in a clean Godot 4 project (headless script load). See `addons/synesyn_core/README.md` and `synesyn/docs/architectural-decisions/0017-synesyn-core-shared-library-addon.md`.

Optional host theme `.tres` packs (typically under ScenSyn) may skin scenes when present; absence must not prevent the addon from loading.

### Editor plugin expectations (honest)

| What you get | What you should not expect |
| --- | --- |
| Pattern dock / main-screen UI, local discovery, demo sources | An NPC brain or autonomous agent |
| Full substrate loop (import graphs, Hub jobs, commit `ui.closure`) **when Hub + workspace are configured** | Commit / publish without Hub |
| Integration hooks via Metapunkt / host Tools shell (navigation signal; no reach-up into host trees) | Silent overwrite of closures or silent model-embedding egress |

Enable under Project → Project Settings → Plugins (`synesyn_core` before SynAxes). For the full Synesyn facilitator journey, run inside the Synesyn client with Hub available.

### Architecture boundary

| Layer | Responsibility |
| --- | --- |
| **Godot (this addon)** | Dataset selection, Pattern Space / Overview, Dream Inbox / Closure Editor, explicit commits |
| **Synesyn Hub** | Jobs (`synaxes.embed_*`, `project`, `cluster`, …), artifact persistence, provenance, analysis-run records |
| **synesyn_core** | RuntimeConfig, HubSubstrateClient, ThemeManager, shared helpers |

### Code map

| Concern | Script |
| --- | --- |
| UI binder (Tools + editor) | `scripts/runtime/synaxes_ui_binder.gd` |
| UI coordinator | `scripts/runtime/synaxes_runtime_controller.gd` |
| Analysis / discovery orchestration | `scripts/runtime/synaxes_analysis_controller.gd` |
| Hub jobs + artifact persistence | `scripts/runtime/synaxes_hub_pipeline.gd` |
| Dream Inbox + commit | `scripts/runtime/synaxes_closure_controller.gd` |
| Import / source picker | `scripts/runtime/synaxes_import_controller.gd` |
| Local discovery | `scripts/integration/discovery_engine.gd` |
| 3D viewer | `scripts/visualization/pattern_viewer.gd` |
| Main scene | `scenes/synaxes_main.tscn` |
| Editor plugin entry | `scripts/plugin.gd` |

### Pattern Space controls

| Input | Action |
| --- | --- |
| Left click | Select pattern |
| Left drag | Orbit |
| Middle drag / Shift+left drag | Pan |
| Right click | Deselect |
| Scroll | Zoom |
| Space | Reset camera |
| Esc | Clear selection |
| F | Focus selected pattern |

### Further reading (repo-relative)

- `synesyn/docs/user-guide/synaxes.md`
- `synesyn/docs/concepts/closure-map.md`
- `synesyn/docs/architectural-decisions/0015-synaxes-v2-closure-map-orientation.md`
- `synesyn/docs/architectural-decisions/0017-synesyn-core-shared-library-addon.md`
- `synesyn/docs/product-requirements/PRD-SYNAXES-NAVIGABLE-DEFAULT-PATH.md`
- `synesyn/docs/implementation_docs/SynAxes_Embeddings_Pipeline.md`
- `synesyn/implementation_tracking/active/05_SynAxes.md`

---

## License

Source code is MIT; text and documentation are CC BY-SA 4.0. See the `LICENSE`
file at the repository root. Third-party components are listed in
`THIRD-PARTY-NOTICES.md`. The project's names and marks are not licensed
(`TRADEMARK.md`).
