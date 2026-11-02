# Docs site

Builds a browsable site from [`../../docs/`](../../docs/README.md) with MkDocs and
the Material theme. There is no separate source: the same markdown is read on
GitHub and served here, which is why there is no wiki (ADR 0007 gives the
governance reason).

## Preview locally

From the repository root:

```bash
pip install -r utilities/docs/requirements.txt
mkdocs serve
```

That serves <http://127.0.0.1:8000> and reloads as you edit. To produce the static
site in `site/` instead, run `mkdocs build`. `site/` is ignored by git.

## What the build checks

`mkdocs build --strict`, which CI runs on any change to `docs/`, fails on

- a cross-reference to a document that does not exist,
- a link to a heading anchor that does not exist,
- a document in `docs/` that no navigation entry points at.

The last one is the reason the navigation in `mkdocs.yml` is written out in full
rather than generated: adding a document without placing it is then a build
failure instead of a file nobody finds.

CI also runs
[`check_doc_paths.py`](../checks/README.md#documented-path-check), which catches
what mkdocs cannot see: repository paths written as prose in backticks rather than
as links.

## Audience separation

The top level of the navigation is two audience tabs — **Using Synesyn** and
**Developing** — plus a shared **Reference** section for concepts, requirements,
contracts and decisions. The separation lives in the navigation rather than in the
filesystem on purpose: moving the folders would invalidate several hundred path
references, eleven of them inside append-only ADRs, for no reader benefit that the
tabs do not already provide. ADR 0025 records the related split between `docs/`
and `implementation_tracking/`.

Note that links pointing outside `docs/` cannot work in the site, since the site
contains only `docs/`. Where documentation needs to reach code or an addon README,
it uses an absolute `github.com` URL, which resolves in both places.

## Publishing

Deliberately not enabled yet. GitHub Pages cannot serve a private repository on
the free organisation plan, and on paid plans the published site is public by
default, which would defeat keeping the repository private. The deploy job in
[`../../.github/workflows/docs.yml`](../../.github/workflows/docs.yml) is
therefore gated rather than absent, so it can be reviewed now and switched on
later.

Once the repository is public:

1. **Settings → Pages → Source:** GitHub Actions.
2. **Settings → Secrets and variables → Actions → Variables:** add
   `PUBLISH_DOCS` = `true`.

The site then publishes at <https://metapunkt.github.io/Synesyn/> on every push to
`main` that touches the documentation. Nothing else needs changing, and there is no
hosting cost for a public repository.
