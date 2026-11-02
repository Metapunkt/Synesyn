# Contributing

Synesyn is research software from a funded pilot, not a product with a support
team. Contributions are welcome, and it is worth knowing what that means here:
the project has one principal author, the design is opinionated and recorded in
[ADRs](docs/architectural-decisions/README.md), and a change that cuts against a
recorded decision needs a new decision rather than a patch.

If you are unsure whether something is wanted, open an issue before writing code.

## Setting up

[`docs/developer-guide/local-dev.md`](docs/developer-guide/local-dev.md) is the
canonical setup guide, including the one manual step (installing the LimboAI
binaries, which are not redistributed here). Read
[`docs/SYSTEM_MAP.md`](docs/SYSTEM_MAP.md) next: it records which document owns
which kind of statement, and saves you writing in the wrong place.

## Before you open a pull request

Run whatever your change touches. All commands from the repository root unless
stated.

| If you changed | Run |
| --- | --- |
| Hub Python | `python -m pytest tests/` from `services/synesyn_hub/` |
| GDScript or hub Python | `python utilities/checks/check_line_limits.py --check-baseline` |
| Addon code | `python utilities/checks/check_addon_autoloads.py` |
| ScenSyn runtime, scenarios, themes | a harness spec, see below |
| Documentation | `mkdocs build --strict` and `python utilities/checks/check_doc_paths.py` |

Behaviour is verified by executable specs rather than prose (ADR 0006), so a
claim that something works should come with a spec run:

```bash
python utilities/harness/test_harness.py \
  --spec docs/technical-review/run_specs/scensyn_workshop_catalyst_smoke.json
```

## House rules worth knowing

These are the ones that most often cause a change to be sent back.

- **Script size.** 900 lines is a soft warning, 1200 a hard limit, and the ratchet
  in `utilities/checks/` refuses regressions against a baseline. Splitting by
  responsibility is expected rather than exceptional (ADR 0004).
- **GDScript conventions.** [`AGENTS.md`](AGENTS.md) lists the naming, typing and
  scene-construction rules that keep the Godot parser and the engine's autoloads
  out of your way. They look fussy; each one is there because of a real bug.
- **The addon boundary.** Shared client code lives in `addons/synesyn_core/`, and
  addons must not reach into application autoloads (ADR 0017). The autoload check
  enforces it.
- **Humans commit, systems propose.** Anything generated must be accepted by a
  person before it becomes part of the record (ADR 0019). A change that
  auto-commits model output will be rejected on principle, not on style.
- **Where writing goes.** Contracts in `docs/implementation_docs/`, rationale in
  an ADR, intent in a PRD, checklists in `implementation_tracking/active/` — never
  a plan in `docs/` (ADR 0025).

## Decisions

If your change involves a real choice between alternatives with lasting
consequences, add an ADR. Copy the shape of a recent one, keep the options you
rejected, and append rather than editing history: several ADRs here record
directions that were later withdrawn, and that record is the point.

## Licence and names

Contributions of code are accepted under the MIT licence in [`LICENSE`](LICENSE). Contributions of documentation are accepted under CC BY-SA 4.0.

The names are not covered by either licence. See [`TRADEMARK.md`](TRADEMARK.md).
