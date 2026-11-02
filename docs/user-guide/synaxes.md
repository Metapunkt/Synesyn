# SynAxes — default path

Walk your material as a space and leave with a few closures you can stand behind.

SynAxes is where you turn imported material (context graphs, session turns, or a demo dataset) into **named Closures**: human-confirmed groupings you can reuse in SynPunkt and later sessions. Machine suggestions stay editable until you explicitly commit them.

**Hub:** Committing Closures and importing published context graphs require the Synesyn Hub. When working offline, you can still import the **demo** source, discover patterns locally (using the default local TF-IDF tier), and rehearse the workflow; committing waits until the Hub is running.

Spine: **Import → Explore → Choose → Name → Commit**

---

## Default path (no Advanced)

1. **Open** Tools → SynAxes (from the Synesyn Tools shell or from inside an application).
2. **Import**
   - Prefer **Import latest Hub context graph** when one or more published graphs exist.
   - Or choose **Import** and select a Hub context graph, a ScenSyn session, or the labelled demo.
3. **Discover** — leave Advanced closed and run **Discover** with the theme-count control on the main panel.
4. **Explore** — after discovery, **Pattern Overview** opens by default (the 3D Pattern Space remains available as an optional view).
5. **Choose** — select a candidate theme from Pattern Overview or the Dream Inbox and click **Work on this**.
6. **Name** — give the Closure a name and intent, and optionally choose an **Orientation** (the A–D [Closure Map](../concepts/closure-map.md) quadrants, shown with plain-language subtitles).
7. **Commit** — commit explicitly to the Hub. The orientation coverage strip updates once saved Closures exist, with an optional hand-off to SynPunkt Closures.

You can complete the full loop from demo import through discovery to commit (or defer) without opening Advanced.

**From Workshop Catalyst:** In the Session Record tab, clicking **Propose themes** opens Tools → SynAxes with that session's Hub turns preloaded, queues Discover, and focuses the Closures (Dream Inbox) tab. Follow the same Choose → Name → Commit steps above while leaving Advanced closed.

---

## What you leave with

- Named `ui.closure` artifacts stored on the Hub with full provenance
- Optional Orientation tags and a Coverage strip across your Saved Closures
- Committed Closures you can load in SynPunkt to generate SynDocs and presentations

Closures are human checkpoints: the machine proposes, and you decide what is held.

---

## Appendix: Advanced

Open **Advanced** only when you need to tune how discovery runs. Synesyn remembers whether you left the panel open or closed.

Controls under Advanced:

| Control | When you need it |
| --- | --- |
| Discovery method and dimensionality reduction | Switching between clustering and bridges/hubs, or between PCA, t-SNE, and UMAP |
| Hub jobs | Running reproducible projection and clustering jobs on the Hub |
| Embedding tier | Choosing between **Local themes** (default TF-IDF) and **Model themes** |
| Cache and job stats | Inspecting embedding caches and Hub job runs |

**Model themes:** When an embedding-capable SynTree model is active, SynAxes offers a disclosed opt-in that names the provider. Enabling it sends item text to that provider and consumes API credit. Consent is remembered per provider; SynAxes never enables model themes silently. Without consent, discovery stays on local themes.

When STFX Store admissibility filters are enabled, excluded items are withheld from import and reported in the status bar and Advanced panel (ADR 0016).

---

## Related

- Facilitator pipeline: [`facilitator-workflow.md`](./facilitator-workflow.md)
- Addon and developer notes: [`addons/synaxes/README.md`](https://github.com/Metapunkt/Synesyn/blob/main/synesyn_client/addons/synaxes/README.md)
- Closure Map concept: [`../concepts/closure-map.md`](../concepts/closure-map.md)
