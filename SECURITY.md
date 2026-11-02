# Security

## Reporting

Email **metapunkt@metapunkt.org** with "security" in the subject. Please do not
open a public issue for anything that could be exploited before it is fixed.

Be realistic about what happens next: Synesyn is research software with one
principal author and no support rota. You should get an acknowledgement within a
week. A fix for something serious will be prioritised over feature work; something
minor may sit. If you need a guaranteed response time, say so and we can agree one
rather than leaving you guessing.

There is no bounty programme. Credit in the release notes and in
[`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md) is offered gladly.

## What the threat model actually is

Synesyn is local-first. There is no hosted service, no account system and no
central database, so the interesting surface is not a server someone else operates
— it is what runs on a participant's machine during a session.

**In scope, and genuinely worth reporting:**

- **The hub bound beyond loopback.** It listens on `127.0.0.1` by default with
  authentication off. Setting `bind_host` to a LAN address without enabling
  `auth_enabled` exposes the artifact substrate to the network; if you find a way
  to reach it that bypasses that setting, that is a bug.
- **Path traversal through artifact payloads.** The substrate writes files derived
  from request data. A payload that escapes the workspace directory is a serious
  bug.
- **Archive extraction.** The content-pack installer in `utilities/assets/` unpacks
  downloaded archives. It validates checksums and rejects entries outside the
  declared directory; a way past either check is in scope.
- **Credential handling.** Model provider keys live in local configuration. Leaking
  one into a log, an export, an artifact or a story log is in scope.
- **Exports and session records.** These are meant to be shareable. Anything that
  puts a key, a token or an absolute home-directory path into one is in scope.

**Out of scope, though still worth telling us about as ordinary issues:**

- What a language model says, including output that is wrong, biased or unpleasant.
  Model behaviour is not a vulnerability class here.
- Vulnerabilities in third-party services the project can call (model providers,
  ComfyUI, Ollama). Report those upstream; tell us if our integration makes them
  worse.
- The deliberate absence of sandboxing around locally installed tools you have
  chosen to point the project at.
- Anything requiring an attacker who already has write access to your machine or
  your `Documents/Synesyn/` workspace.

## What participants should know

This matters more than most vulnerabilities in practice: by default, session text
goes to a hosted model provider and spoken output goes to Microsoft's Edge voices,
so **participants' words leave the machine**.
[`docs/user-guide/privacy-and-data.md`](docs/user-guide/privacy-and-data.md) sets
out exactly what is sent where, and how to run a session fully offline. Tell the
room before you start.

## Supported versions

There are no releases yet, so `main` is the only supported version. Once releases
begin, security fixes will go to the current release and to `main`, and this
section will say so specifically.
