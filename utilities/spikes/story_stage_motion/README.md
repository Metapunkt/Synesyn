# Story Stage motion spike

A test of rung 4 on the motion ladder in ADR 0030: can a character portrait be turned
into a talking clip for each spoken line, quickly enough and in a form Story Stage can
use? The spike sends one portrait and one line of speech through the hub to a ComfyUI
running [SoulX-FlashHead](https://github.com/Soul-AILab/SoulX-FlashHead), times the
round trip, and leaves the files needed to judge the result by eye.

Nothing here ships. The hub changes it relies on do ship, and are covered by
`services/synesyn_hub/tests/test_render_comfy_media.py`:

- A `render.comfyui` request may name `input_uploads`. Each one is an artifact the
  hub uploads to ComfyUI before it submits the workflow. The hub then points the node
  input at the uploaded name, so a ComfyUI on another machine gets the files it needs.
- `output_routing.videos` (and `.audio`) opt a request into collecting video and audio
  outputs. They are stored as `video.generated` / `audio.generated` artifacts, or
  under the type the request names, and listed as `media_artifact_ids` on the job and
  on `render.completed`. Requests that do not opt in behave exactly as before.
- `timeout_sec` on the request replaces the 180-second poll limit (1 to 1800).

## Setting up the ComfyUI machine

The spike expects ComfyUI to run elsewhere, as it does for Synpunkt. On that machine:

1. Clone [ComfyUI_RH_FlashHead](https://github.com/HM-RunningHub/ComfyUI_RH_FlashHead)
   into `ComfyUI/custom_nodes/` and install its `requirements.txt` into ComfyUI's
   Python (it needs `optimum-quanto`, `librosa`, `av`, `imageio` and `loguru`).
2. Put the weights where the loader looks for them:
   - `ComfyUI/models/Soul-AILab/SoulX-FlashHead-1_3B` from
     `huggingface-cli download Soul-AILab/SoulX-FlashHead-1_3B`
   - `ComfyUI/models/wav2vec/facebook/wav2vec2-base-960h` from
     `huggingface-cli download facebook/wav2vec2-base-960h`
3. `ffmpeg` must be on that machine's PATH; the node uses it to add the audio track.
4. Restart ComfyUI. The Lite model needs about 8 GB of VRAM.

The hub, not this machine, submits the job, so the address has to be one the hub can
reach (the Tailscale address Synpunkt already uses, for example).

## Running it

From the repository root:

```bash
python utilities/spikes/story_stage_motion/flashhead_spike.py --check
python utilities/spikes/story_stage_motion/flashhead_spike.py --runs 3
python utilities/spikes/story_stage_motion/flashhead_spike.py --model pro --audio line.mp3 --crop 300,40,520,520
```

`--check` reports the hub, the ComfyUI address and where it came from, the GPU, and
whether both FlashHead nodes are installed. The address is taken from `--comfy-url`,
then `render.comfy_url` in `Documents/Synesyn/synesyn/config/synesyn_client.json`,
then the first entry of `render.comfy_url_history`, then the most recent render request
the hub stored.

By default a run uses Didi's first idle sprite from Ireti Okan and the newest TTS line
in `Documents/Synesyn/Workspaces/*/artifacts/audio/tts/`. The sprite is cropped to a
square from the top of its silhouette and flattened onto grey, because FlashHead takes
an RGB image. For these busts the face then fills less than half the frame. Use
`--crop x,y,w,h` (sprite pixels) to frame the head more tightly and compare.

The first run includes loading the model; ComfyUI keeps it loaded, so later runs are
warm. Each run's results go to `results/<timestamp>/` beside the script:

| File | What it is for |
| --- | --- |
| `results.json` | timings, clip size and frame rate, real-time factor per run, a verdict hint |
| `clip_N.mp4` | the clip as ComfyUI produced it |
| `clip_N.ogv` | the last clip in Theora/Vorbis, the only video format Godot plays natively |
| `contact_sheet.png` | eight frames across the clip |
| `contact_sheet_masked.png` | the same frames cut out with the portrait's own alpha mask |
| `portrait_input.png`, `portrait_mask.png`, `line.wav` | exactly what was sent |

## Judging the result

The real-time factor is generation time divided by the length of the line. It decides
where the rung can be used:

| Warm real-time factor | Use |
| --- | --- |
| 1.0 or less | A clip per line, generated as the line is synthesised, with a short lead-in |
| 1.0 to 3.0 | Generate the next line while the current one plays; the first line waits |
| above 3.0 | Offline only: portrait sheets for a scenario, or re-rendering a saved session for replay |

Look at the clips for the rest:

- **Identity.** Does Didi still look like Didi throughout, cracked panels and all?
  Generative models tend to smooth damage and seams into skin.
- **Lip-sync.** Do the mouth shapes follow the speech? Try a line with plosives.
- **Artefacts.** Warping at the panel edges, eyes that drift, a chin that melts.
- **Silhouette.** The clip has no alpha. In `contact_sheet_masked.png`, if the head
  stays inside the portrait's mask, a fixed mask is enough to composite it on the
  stage. If it moves outside, the stage needs a matte (a keyed background colour, or a
  segmentation pass) before the clip can sit on a backdrop.
- **Coverage.** FlashHead drops the tail of the audio that does not fill a whole chunk;
  `audio_covered` in `results.json` shows how much of the line the clip spans.
- **VRAM.** Watch the ComfyUI machine during a run; note whether Pro fits.

Record what you see next to `results.json`; the ADR's rung-4 decision waits on it.
