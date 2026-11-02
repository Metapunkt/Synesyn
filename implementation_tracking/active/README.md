# Synesyn Implementation To‑Do Lists (Component-by-component)

These checklists translate the architecture + specs into implementation tasks per component.

Read [`../../SYSTEM_MAP.md`](../../SYSTEM_MAP.md) for documentation
ownership and [`../README.md`](../README.md) for the technical-contract index.

As the project matures toward deployment, the completed checklists will be consolidated into:
- user docs (how-to guides, workflows)
- developer docs (architecture, integration contracts, operational runbooks)
- release notes / implementation history (what changed and why)

## Normative references (read first)
- `../Synesyn_Platform_Technical_Architecture.md`
- `../Synesyn_Hub_API_Spec.md`
- `../LatentSubstrate_Data_Model.md`
- `../Local_Deployment_Runbook.md`
- `../Human_Agency_UX_Contract.md`
- `../Artrhythmetic_Memory_Capability_Spec.md`
- `../ScenSyn_Workshop_Catalyst_Runtime_Robustness_Plan.md`

## Component checklists
- `01_Synesyn_Hub.md`
- `02_Metapunkt.md`
- `03_SynTree.md`
- `04_SynTree_Voice.md`
- `05_SynAxes.md`
- `06_SynPunkt.md`
- `07_Artrhythmetic_Memory.md`
- `08_UI_Refresh.md` (historical UI research; spatial UI effort withdrawn — see ADR 0010)
- `09_Artrhythmetic_Store.md`
- `10_Session_Types_and_Society_of_Minds.md`
- `11_Workshop_Catalyst_Build_Staging.md`

## Suggested implementation sequence (to minimize breakage)
1. `01_Synesyn_Hub.md`
2. Godot **Services panel + process manager** (implemented in the Synesyn platform shell; not a standalone checklist yet)
3. `04_SynTree_Voice.md` (route through hub for one-endpoint + no-CLI)
4. `02_Metapunkt.md` (wire audit/events/provenance to the substrate via hub)
5. `05_SynAxes.md` (Latent Reality engine: closures + 4D navigation; jobs + substrate-backed analysis)
6. `06_SynPunkt.md` (presentation + generation surface: SynDeck v2 + Story Stage mode + render orchestration)
7. `07_Artrhythmetic_Memory.md` (symbolic deterministic memory capability; app-agnostic; file-backed canonical store)
8. `03_SynTree.md` (prompt-chain editor + provider consolidation + deeper substrate integration)
9. `09_Artrhythmetic_Store.md` (canonical memory substrate + generated indexes + swappable accelerators)
10. `10_Session_Types_and_Society_of_Minds.md` (ScenSyn-specific: theme → SessionType elevation, Workshop Catalyst hidden multi-agent synthesis)
11. `11_Workshop_Catalyst_Build_Staging.md` (sequenced delivery plan over docs 10 + gap-closure: 11 logical stages, contract seams, verification gates, rollback posture)

> The former `12_Spatial_UI_System.md` (cross-product spatial interaction) was
> withdrawn after a cost-benefit review; only the semantic visual-profile system
> was salvaged into `addons/synesyn_visual_profiles/`. See ADR 0010. The tracker
> is archived under `_archive/spatial_ui/docs/`.

Notes:
- SynAxes is intentionally earlier now because it owns human-reviewed closure formation; SynPunkt consumes and performs closures rather than re-implementing closure logic. Artrhythmetic Store now defines the canonical memory form for closures that carry symbolic memory/provenance.
- Artrhythmetic Memory follows the hub and SynAxes layers because it is a general capability hosted by Synesyn, but must remain conceptually distinct from embeddings/LatentSubstrate-first analysis.
- SynTree work remains later because it risks breaking the editor assistant UX if done too early.
- Artrhythmetic Store formalizes the newer direction: Artrhythmetic Memory remains the capability/core logic, while the Store becomes the human-readable canonical substrate with generated, disposable indexes and optional accelerators.

## How to use
- Treat each file as a living implementation plan.
- Check items as they are completed.
- When a task changes architecture/spec expectations, update the relevant normative doc first.
- Do not duplicate PRD requirements or normative contracts in these checklists;
  link the owning document and track only implementation work.


