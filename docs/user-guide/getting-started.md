# Getting started

## Before you start

Synesyn is research software from a funded pilot. Expect rough edges.

- **If you downloaded a packaged Windows release:** unpack the archive, set up
  [model access](#model-access) below, and run `Synesyn.exe` (or the versioned
  executable in the root folder). The packaged build already includes the
  client, the LimboAI extension, and the bundled hub under
  `services/synesyn_hub/synesyn_hub.exe`.
- **If you are running from source:** budget half an hour for the first setup.
  You will need:
  - **Godot 4.7.x** (recommended **4.7.2-stable**), from
    [godotengine.org](https://godotengine.org/download). Synesyn does not ship
    Godot; install it yourself. The standard build is fine; you do not need the
    .NET version. See
    [Recommended builds](https://github.com/Metapunkt/Synesyn/blob/main/docs/developer-guide/local-dev.md#recommended-builds).
  - **The LimboAI addon binaries** (recommended **v1.8.0**, GDExtension for
    Godot 4.6), which are excluded from this repository for size reasons —
    Synesyn does not redistribute them. One download and one copy — see
    [installing LimboAI](https://github.com/Metapunkt/Synesyn/blob/main/docs/developer-guide/local-dev.md#installing-limboai-required-before-the-first-open).
    The project will not open cleanly without them.
  - **An API key for a language model**, or a local model. Nothing generative
    works without one; see [Model access](#model-access) below.
  - **Python 3.11**, only if you want to run the hub from source for voice,
    embeddings, or artifact storage. The client also runs without the hub, with
    those features absent.

Synesyn is developed and tested on **Windows**. Godot and the hub are
cross-platform in principle, though macOS and Linux have not been tested yet.

## First launch

When running from a packaged release, start `Synesyn.exe` after configuring model
access. When running from source:

1. Install the LimboAI binaries as linked above.
2. Open `synesyn_client/` in Godot and let it import. The first import takes a
   few minutes. On a fresh clone, transient `BTPlayer` / `BTTask` / font-load
   errors during that first import are expected; use
   **Project → Reload Current Project** (or run
   `godot --headless --import` first). Details:
   [First launch (fresh clone)](https://github.com/Metapunkt/Synesyn/blob/main/docs/developer-guide/local-dev.md#first-launch-fresh-clone).
3. Set up model access (next section), or the session will start and then fail to
   respond.
4. Press play.

Warnings about `Logging service not available`, `NotificationManager not found`,
or `ContentStateResource not injected yet` are benign init-order messages and
can be ignored.

The hub starts on its own if a Hub binary is present and not already running, and
adopts one that is already running rather than starting a second (ADR 0021). A
source checkout has no shipped binary under `dist/` — start the Hub yourself (or
set `hub.exec_path` / `hub.autostart_from_source`) when you want voice. For voice
plus Story Stage portraits from source, see
[Running ScenSyn from source with voice and avatars](../developer-guide/local-dev.md#running-scensyn-from-source-with-voice-and-avatars).

## Model access

Copy `synesyn_client/addons/syntree/config.example.cfg` to `config.cfg` in the
same directory and fill in one key (or configure your provider and key inside
SynTree / ScenSyn settings). `config.cfg` is git-ignored, so your key stays on
your machine.

| Provider | Where to get a key |
| --- | --- |
| Anthropic (Claude) — the default | <https://console.anthropic.com/settings/keys> |
| OpenAI | <https://platform.openai.com/api-keys> |
| Google (Gemini) | <https://aistudio.google.com/apikey> |
| xAI (Grok) | <https://console.x.ai/> |
| DeepSeek | <https://platform.deepseek.com/api_keys> |

Only the provider you use needs a key. For a session with **no external calls at
all**, run [Ollama](https://ollama.com/) locally and point the client at it
instead; quality depends heavily on the local model you choose.

Sessions consume API credit at roughly the rate of an active chat, and a workshop
turn costs more than a single message because four analytical lenses run behind
it. Watch your provider's usage page during your first workshop rather than
guessing.

## Your first session

Most people come here to facilitate a group session. That path is
**Workshop Catalyst**:

1. Read the [facilitator workflow](facilitator-workflow.md) for the shape of a
   session — roughly twenty minutes.
2. Follow the
   [Workshop Catalyst facilitator manual](workshop-catalyst-facilitator-manual.md)
   for running one, including scenario selection, the Thinking Map, and producing
   a Session Record.
3. Keep the [glossary](../concepts/glossary.md) to hand. *Closure*, *artifact* and
   *specialist* all mean something specific here.

If you came instead to author or present documents, the SynPunkt path is:
open **Artifacts → Closures**, load a closure, press **Generate** for an editable
SynDoc draft, lay it out, and save a version. Editing produces a new version;
closure history is never overwritten.

## Working as a group

- One machine runs the hub for the shared workspace.
- Other machines point at that hub's URL under **Settings → Host/Join**, with a
  bearer token if one is set.
- ComfyUI, if used for image generation, can live on a third machine. Only the hub
  needs to reach it.

## Where your work is kept

Everything user-visible lives under `Documents/Synesyn/` (ADR 0014), not in a
hidden application folder:

- `Documents/Synesyn/scensyn/story_logs/` — session transcripts, the workshop
  summary `.md`, and its `.workshop.json` sidecar.
- `Documents/Synesyn/Workspaces/<workspace>/artifacts/` — artifacts held by the
  hub, when you are running one.

Both are ordinary folders. Copy them, back them up, or open them in a text editor.

For what is sent where, and what stays local, see
[Privacy and data](privacy-and-data.md).
