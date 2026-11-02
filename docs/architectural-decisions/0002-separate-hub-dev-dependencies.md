# 0002 — Separate hub dev/test dependencies into requirements-dev.txt

- **Status:** Accepted (amended 2026-11-01)
- **Date:** 2026-07-09
- **Area:** hub / tooling

> Amendment note (2026-11-01, ADR 0032): `artrhythmetic_store` and
> `test_artrhythmetic_store.py` were renamed to `stfx_store` and
> `test_stfx_store.py`. The historical context below retains the original names.

## Context
The `run-hub-tests` and `synesyn-reviewer` skills promise "run the tests before reporting," but a dry run showed the hub `.venv` had neither `pytest` nor `httpx`. `test_artrhythmetic_store.py` uses FastAPI's `TestClient`, which hard-requires `httpx`, so the store suite could not even be collected by pytest *or* the unittest fallback. Neither dep was declared in `requirements.txt`.

## Options considered
1. **Add `pytest` + `httpx` to `requirements.txt`** — simplest, but pollutes the runtime/packaged build with test-only deps.
2. **New `requirements-dev.txt`** that pulls in runtime via `-r requirements.txt` and adds the test-only deps — keeps the packaged build lean while making test deps explicit.

## Decision
Option 2. Created `synesyn/services/synesyn_hub/requirements-dev.txt` pinning `pytest==8.3.4` and `httpx==0.28.1`, installed into the hub `.venv`. The `run-hub-tests` skill documents the install fallback.

## Consequences
- Positive: lean runtime image; reproducible, explicit test environment.
- Negative / trade-offs: contributors must install dev deps as a separate step (documented in the skill and the file header).
- Verification: `python -m pytest tests/ -q` → **26 passed**.
