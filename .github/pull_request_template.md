## What this changes, and why

<!-- The problem first, then the approach. If it fixes an issue, link it. -->

## What you ran

Tick what you actually ran, not what you believe would pass. Guidance and the full
table are in [`CONTRIBUTING.md`](../CONTRIBUTING.md).

- [ ] `python -m pytest tests/` from `services/synesyn_hub/` — hub Python changed
- [ ] `python utilities/checks/check_line_limits.py --check-baseline` — GDScript or hub Python changed
- [ ] `python utilities/checks/check_addon_autoloads.py` — addon code changed
- [ ] `mkdocs build --strict` and `python utilities/checks/check_doc_paths.py` — documentation changed
- [ ] A harness spec from `docs/technical-review/run_specs/` — ScenSyn runtime, scenarios or themes changed
- [ ] Nothing, because this change cannot affect any of the above

## Decisions

- [ ] This follows the recorded decisions in `docs/architectural-decisions/`
- [ ] This cuts against one, so it adds a new ADR rather than quietly diverging
- [ ] This involves a real choice with lasting consequences, so it adds an ADR

## Anything a reviewer should know

<!-- Things you are unsure about, alternatives you rejected, or a boundary you had
to push against. If the platform forced you to work around it, say so — that is a
defect worth recording rather than something to hide in a diff. -->
