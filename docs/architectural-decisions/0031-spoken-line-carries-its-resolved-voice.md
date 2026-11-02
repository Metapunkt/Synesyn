# 0031 — A spoken line carries the voice it was resolved with

- **Status:** Accepted
- **Date:** 2026-10-31
- **Area:** scensyn

## Context

`POST /voice/speak` treats a blank `voice.name` as `en-US-AriaNeural`. That is the voice heard when a line leaves with no id.

Story Stage reads a scenario `[VOICES]` block into a shared `VoiceService` mapping, then builds the hub body from that mapping. The human's first typed line still went out with no id. Every later line from the same person used the scenario voice. Other cast members were already correct on first appearance: their log sender is the name in `[VOICES]`, and they speak after the mapping has been filled.

Two gaps produced the empty id.

The typed line was credited to the network name (`Player_1`, `Unknown Character`, an old peer name). That string is not a `[VOICES]` key, so lookup missed. Later lines matched the cast name.

The shared mapping can still be empty, or hold a hash-pool string, when the first request is built. A hash of a cast name is one of the pool voices. Hearing `en-US-AriaNeural` for a speaker who has a `[VOICES]` entry means the name was omitted.

A third cause sat in the hub's disk cache (`artifacts/_cache/tts_cache.json`). During the earlier `edge-tts` outage, `/voice/speak` fell back to Windows SAPI (`sapi_default`) and wrote that WAV into `tts_cache.json` under the requested neural voice's cache key. Common opening lines (`hello`, `Hello`, `Hello!`) for `en-NG-AbeoNeural` were stored as `sapi_default`. Even after the client sent `{ "name": "en-NG-AbeoNeural" }` on the first turn, the hub matched that key in `tts_cache.json` and returned the cached SAPI WAV. Later turns used different text, missed the poisoned cache entries, and spoke in the neural voice.

The hash pool stays for a scenario that has no `[VOICES]` block. An empty block must return before the pool, or it overwrites voices the session already installed. A dictionary config already stored for a speaker must stay. Replacing it with the pool was an earlier form of the same first-line failure.

## Options considered

1. **Hold the first human line until the mapping is warm.** The line still misses when the log sender is not a `[VOICES]` key, and the hold adds latency.
2. **Hard-code the played character's voice id.** Fixes one scenario and breaks the rest.
3. **Resolve the config when the line is sent, and put that config on the request.** The hub body is written from the request. A mapping filled later cannot change this utterance, and an empty mapping cannot win once resolution has succeeded.

## Decision

Option 3, for every scenario.

- `get_local_speaker_name` returns the character the participant is playing when the network name has no `[VOICES]` entry and the played character does.
- `voice_config_for` clears a stale voice cache and tries again, then reads the live scenario, the loader, and the scenario file. A local speaker named `Participant`, `Unknown Character`, `Unknown Player`, or `Unknown Peer` uses the played character's config.
- The dictionary travels on the voice-bridge queue and into `VoiceService.request_character_speech` as `voice_override`. A non-empty `voice` is written with `set_character_voice_config` before the mapping is read for the HTTP body.
- Speakers absent from a non-empty `[VOICES]` block keep an existing dictionary config. The hash pool runs only when none is stored. An empty `voices_mapping` returns before the pool.
- The host installs voices itself. `apply_character_voice_mappings` takes a `Node` and must not be given the host.
- `/voice/speak` does not write a SAPI fallback into `tts_cache.json` under a neural voice key, and drops any cached `sapi` entry when a neural voice is requested. `VoiceClient` also evicts the cached file and retries once if a cached response reports `sapi` or a voice id other than the one requested.

On the first human line the log should show both `StoryStage: <name> speaks as <id>` and `VoiceClient: Sending synthesis request ... voice: <id>`, with the same id.

## Consequences

- The first human line uses the scenario voice, including rate, volume, and pitch. A later write to the shared mapping cannot retarget a request already queued.
- The hash pool remains the voice source for a scenario with no `[VOICES]` block.
- Removing the config from the request, crediting the raw network name, hashing over a stored dictionary config, or running the pool against an empty `[VOICES]` block puts the hub default back on a speaker's first line.
- The hub default in `routes.py` stays. Sending the id is the client's job.
