# Third-party notices

Synesyn's own source code is MIT licensed (see `LICENSE`). Text, documentation, and other website material are CC BY-SA 4.0. The code depends on and,
in packaged builds, redistributes third-party components that carry their own
licences. Those licences govern those components.

Licences below are as contained in installed package metadata. 

Versions refer to `services/synesyn_hub/requirements.txt` and
`environment.yml`.

## Components with obligations beyond attribution

These three need action when a packaged build is redistributed, so they are listed first.

### edge-tts (LGPL-3.0)

- Version 7.2.7 · https://github.com/rany2/edge-tts
- Used by the Hub for text-to-speech. Imported as a Python library.

The LGPL permits use from a work under a different licence, so it does not
affect Synesyn's MIT licensing. Obligations attach when edge-tts is
redistributed as part of a packaged build, where it becomes an embedded copy:
convey its licence, offer its source, and do not prevent a user substituting
their own version. **Any packaged release must ship this notice and an offer of
source for edge-tts.**

### FFmpeg (GPL or LGPL, depending on build)

- Resolved through conda-forge by `environment.yml`.
- Invoked as a separate executable for audio handling.

Invoking a separate process is aggregation rather than derivation, so this does
not affect Synesyn's licensing. Bundling the binary in an installer does carry
a source-offer obligation for FFmpeg itself. conda-forge commonly ships
GPL-enabled builds.


### PyInstaller (GPLv2-or-later, with bundling exception)

- Build-time only; not redistributed.

PyInstaller's licence carries an explicit exception permitting the building and
distribution of non-free programs, including commercial ones. Packaging
Synesyn with it therefore imposes no obligation on Synesyn's own code. 

## Weak copyleft (file-level)

Both are MPL-2.0. They combine freely with MIT code; obligations attach only to
modifications of those projects' own files, and only to those files. Neither is
modified here.

| Component | Licence |
| --- | --- |
| `certifi` | MPL-2.0 |
| `pyttsx3` 2.99 | MPL-2.0 |

## Permissive components

No obligation beyond preserving copyright and licence notices.

### Hub (Python)

| Component | Licence |
| --- | --- |
| FastAPI, Starlette | MIT / BSD-3-Clause |
| Uvicorn | BSD-3-Clause |
| Pydantic, pydantic-core | MIT |
| PyYAML | MIT |
| websockets | BSD-3-Clause |
| aiofiles, aiosignal, frozenlist, multidict, propcache, yarl | Apache-2.0 |
| aiohttp | Apache-2.0 AND MIT |
| aiosqlite | MIT |
| ulid-py | Apache-2.0 |
| soundfile | BSD-3-Clause |
| pydub | MIT |
| NumPy | BSD-3-Clause |
| PyTorch (CPU build) | BSD-3-Clause |
| openai-whisper 20231117 | MIT |
| Whisper model weights (`base.pt`) | MIT |
| httpx, httpcore, idna, click, python-dotenv, pycparser, pywin32-ctypes | BSD-3-Clause |
| anyio, attrs, h11, httptools, comtypes, cffi, watchfiles, tabulate | MIT |
| typing-extensions, pywin32, aiohappyeyeballs | PSF-2.0 |

### Godot client

| Component | Licence | Notes |
| --- | --- | --- |
| Godot Engine | MIT | Runtime; not vendored in this repository |
| LimboAI v1.8.0 | MIT | Copyright (c) 2023-2025 Serhii Snitsaruk and the LimboAI contributors. A GDExtension: its precompiled libraries under `addons/limboai/bin/` are **not** redistributed here (see `.gitignore`), so no binary redistribution obligation arises. `LICENSE.md`, `LOGO_LICENSE.md` and the pinned `version.txt` are retained. Install the matching release before opening the project. |
| `AniceM/vn_tutorial` | MIT | Copyright (c) Anice Menhour ([`AniceM/vn_tutorial`](https://github.com/AniceM/vn_tutorial)). Anice Menhour's *Adventure Visual Novel in Godot Tutorial* YouTube series and accompanying repository served as an initial inspiration from which Story Stage (`addons/story_stage/`) evolved. |

### Fonts

All fonts shipped in the client are under the SIL Open Font License 1.1. The
licence text travels with each font, as OFL requires, and the OFL's Reserved
Font Name terms apply to any modified version.

| Font | Location | Licence |
| --- | --- | --- |
| Noto Sans | `tools/fonts/Noto_Sans/static/`, `addons/synesyn_core/fonts/Noto_Sans/`, `ScenSyn/themes/fonts/noto/` | OFL-1.1 (`OFL.txt` in each) |
| Inter | `tools/fonts/Inter/static/`, `addons/synesyn_core/fonts/Inter/` | OFL-1.1 (`OFL.txt` in each) |
| Roboto Mono | `tools/fonts/Roboto_Mono/static/` | OFL-1.1 (`OFL.txt`) |

Only the weights actually referenced by themes and code are included; the
unused weights of each family were removed rather than shipped.

Inter Bold supplies the `LabelHeader`, `LabelSection` and `LabelSubsection`
roles in the two light themes. It replaced a font named "Claris Sans", which was
removed because its licence could not be established: the designer's own
distribution contains only the TTF and SIL's generic `OFL-FAQ.txt`, with no
licence grant, no copyright line, and no copyright, designer, vendor or URL
recorded in the font's name table. The OFL requires a copyright notice and the
licence text to accompany the font, so the upstream release was not
redistributable as it stood.

## Assets

Generated character portraits and scenario artwork are produced at runtime or
during authoring and are not covered by the MIT licence of this code. Where
such assets are distributed as a content pack, their terms derive from the
service that generated them.

The Story Stage sprite library is distributed this way rather than committed: see
[`docs/user-guide/story-stage-sprites.md`](docs/user-guide/story-stage-sprites.md)
for the packs and `utilities/assets/` for the tooling that builds them. A pack
carries no separate licence file, so treat its contents as governed by this
paragraph rather than by the MIT licence covering the code.

The LimboAI sample game formerly vendored at `synesyn_client/demo/`, which
carried its own `LICENSE_ASSETS.md`, has been removed. It was unreferenced by
the project, so no redistribution question arises from it.

## Corrections

If a licence is recorded incorrectly here, please open an issue. Notices are
maintained per release; this list is to be regenerated when dependency versions change.
