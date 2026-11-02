# Privacy and data

Synesyn is local-first: your work is stored on your own machine, in ordinary
folders you can open, copy or delete. But it is not offline. Several features send
text to third-party services, and if you are running a workshop with participants
you should know which, because you may need to tell them.

This page describes what the software does. It is not a legal privacy notice, and
it does not cover the terms of the providers you choose.

## What stays on your machine

- **Everything you produce.** Session transcripts, workshop summaries, Thinking
  Maps, closures, scenarios and images are written to `Documents/Synesyn/`.
- **The hub.** It binds to `127.0.0.1:17777`, which is reachable only from your
  own machine unless you deliberately host for a group.
- **Speech recognition.** Transcription runs locally through Whisper. Recorded
  audio is not uploaded.
- **Image generation**, when you use ComfyUI, which you run yourself.
- **No telemetry.** There is no analytics, usage reporting or crash reporting of
  any kind. Nothing phones home, and there is nothing to opt out of.

## What is sent away, and to whom

**To your chosen language-model provider** (such as Anthropic, OpenAI, Google,
xAI, or DeepSeek, depending on your configuration):

- Participant contributions, as typed or transcribed. In a workshop this means
  **what people say in the room**, once it enters the session.
- The scenario text and the session's assembled prompt.
- Enough prior conversation for the model to follow the session.

Your provider's terms govern what happens to that text, including whether it is
retained or used for training. If that matters for your participants, check the
provider's policy and consider a local model instead.

**To your provider's embeddings endpoint**, when SynAxes **Model themes** are
explicitly enabled under Advanced: the text being analysed is sent to compute
embeddings. By default, SynAxes stays on local discovery (TF-IDF) and sends
nothing.

**To Microsoft**, when spoken output is enabled: the text to be spoken is sent to
the Edge text-to-speech service. On Windows there is an offline fallback (SAPI),
which sounds noticeably worse but sends nothing. If nothing may leave the machine,
prefer the fallback or leave speech off.

## Running with nothing leaving the machine

It is possible, with reduced quality:

- Use [Ollama](https://ollama.com/) locally instead of a hosted provider.
- Leave text-to-speech off, or force the offline fallback.
- Keep speech recognition on — it is already local.
- Run ComfyUI locally for images.

## If you are facilitating

Two practical suggestions, neither of which the software can do for you:

- **Say so at the start.** Participants generally assume a workshop tool is a
  local notepad. Tell them contributions are processed by whichever provider you
  have configured, and name it.
- **Decide about attribution before you begin.** Contributions can be captured
  with an owner against decisions and risks. If the group would rather be
  unattributed, agree on that first, because the Session Record is a durable
  document and is often circulated afterwards.

## Group sessions

When one machine hosts the hub for others, participants' contributions travel over
your local network to that machine, and are stored in the host's
`Documents/Synesyn/`. Set a bearer token under **Settings → Host/Join** if the
network is not one you control. The host holds everyone's material.
