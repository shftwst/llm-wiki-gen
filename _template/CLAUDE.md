# {{KB_TITLE}} — Knowledge Base Schema

This file is the **schema** for this knowledge base. It tells you (the LLM agent) how
this wiki is structured and how to maintain it. **You are the wiki's maintainer:** you
read sources, write and update pages, and keep everything consistent. The human curates
sources and asks questions — you do the bookkeeping.

This KB follows the **LLM Wiki** pattern (Andrej Karpathy). The full write-up lives in
the `llm-wiki-kit` repo at `docs/llm-wiki-pattern.md`.

## The three layers

1. **`raw/` — sources.** The human's curated source material; your source of truth. You
   read from it and never treat it as something you own. Sources can be files,
   directories, or symlinks to living documents — see **Source model** below.
2. **`wiki/` — the wiki.** Markdown pages you own entirely: source summaries, entity
   pages, concept pages, comparisons, the overview. You create and maintain every file
   here. The reader browses this layer.
3. **This `CLAUDE.md` — the schema.** Conventions and workflows. Co-evolve it with the
   human as you learn what works for this domain.

## Directory layout

```
{{KB_NAME}}/
├── CLAUDE.md          # this schema
├── README.md          # human-facing intro + Obsidian setup
├── notes.md           # owner-authored facts & corrections (authoritative; cite as "per owner")
├── inbox/             # shareable staging; scripts/sweep.sh MOVES drops into raw/
├── raw/               # sources (files, directories, symlinks) — protected, never shared
├── wiki/              # the wiki (Obsidian vault root) — you own everything here
│   ├── index.md       # content catalog of every wiki page
│   └── overview.md    # the evolving top-level synthesis / home page
└── log.md             # append-only chronological record
```

**Obsidian:** the vault is opened at `wiki/` only. Everything in `wiki/` is browsable
markdown — keep it that way. A reader should never need to open `raw/` to understand the
wiki. A living source in `raw/` reaches the graph through its **source page** in
`wiki/`, not through the raw file itself.

## Source model (`raw/`)

A "source" is one unit of source material. It can be:

- **A file** — e.g. `raw/2026-q2-pricing.pdf`, a transcript, a markdown note.
- **A directory** — a folder dropped into `raw/` is itself a single source. Walk it,
  summarize the set as a whole, and create per-file pages only where a file warrants one.
- **A symlink to a living document or directory** — e.g.
  `raw/ops-shared-drive -> /mnt/gdrive/Ops`. The source of truth stays organized at its
  origin; `raw/` only points at it. **Follow the symlink to read; never copy its contents
  into the repo.** Git stores the link, not the target.

**Sources are not frozen.** Living sources (especially symlinks) change over time.
Support re-ingesting updates — see the **Re-ingest** workflow.

> **Hard rule — `raw/` is read-only to you.** Sources are never mutable by you. You read
> them; you never create, edit, move, rename, or delete anything in `raw/` — including
> writing *through* a symlink to a living source. The human owns `raw/` entirely. When a
> source needs to change, that happens at its origin; your job is to re-ingest the change,
> never to make it.

### Intake & sharing (`inbox/`)

`inbox/` is a **shareable staging area** — the one directory exposed to contributors.
People drop files or folders into it; `scripts/sweep.sh` then **moves** each item into
`raw/`. Because the sweep *moves* (not copies), a curated source leaves the shared area
entirely, so contributors can never read, alter, or delete the real `raw/` source.

- **Never share `raw/` or the KB root — share only `inbox/`** (e.g. point `inbox/` at a
  shared cloud folder, or share just that subdirectory).
- **You ignore `inbox/` entirely.** Only `raw/` is a source. Never read, ingest from, or
  write to `inbox/` — the sweep is a plain script, run before ingest, not your job.

Obsidian cannot render non-markdown sources (`.docx`, `.xlsx`, PDFs, etc.), but you can
read or convert them. Their knowledge reaches the reader through wiki pages, not the raw
files.

## Page conventions

- **Filenames:** kebab-case, descriptive — `acme-corp.md`, `client-onboarding.md`.
- **Links:** use `[[wikilinks]]` between wiki pages. Link liberally — a link to a page
  that doesn't exist yet marks a page worth creating.
- **Frontmatter:** every wiki page starts with YAML:

  ```yaml
  ---
  type: source | entity | concept | comparison | overview | index
  tags: []
  created: YYYY-MM-DD
  updated: YYYY-MM-DD
  ---
  ```

- **Source pages** carry extra provenance frontmatter:

  ```yaml
  ---
  type: source
  tags: []
  created: YYYY-MM-DD
  updated: YYYY-MM-DD
  source_path: raw/<path>              # path inside raw/
  source_kind: file | directory | symlink-living
  last_ingested: YYYY-MM-DD            # human-facing provenance
  ---
  ```

  Drift fingerprints live in `.ingest/manifest.tsv` (owned by `scripts/scan.sh`), not on
  the page — one fact, one owner.

- **Derived pages** (comparisons, analyses — answers synthesized from *other* pages)
  carry dependency frontmatter so their staleness can be detected mechanically:

  ```yaml
  ---
  type: comparison
  tags: []
  created: YYYY-MM-DD
  updated: YYYY-MM-DD
  derived_from: ["[[page-a]]", "[[page-b]]"]   # the wiki pages this was synthesized from
  as_of: YYYY-MM-DD                            # snapshot date of the underlying data
  ---
  ```

### Page types

- **source** — a summary of one ingested source. Lives in `wiki/sources/`. Records
  provenance, key takeaways, and `[[links]]` to the entity/concept pages it touches.
- **entity** — a concrete thing the domain tracks (a client, person, vendor, tool,
  process). Lives in `wiki/entities/`.
- **concept** — an idea, policy, or topic that spans sources (a pricing model, a
  methodology). Lives in `wiki/concepts/`.
- **comparison / analysis** — durable answers worth keeping; file query results back
  here. Lives in `wiki/analysis/`. Carries `derived_from` + `as_of` frontmatter so
  staleness is mechanically detectable (see Lint).
- **overview** — `wiki/overview.md`, the evolving synthesis. **index** — `wiki/index.md`.

Create subdirectories under `wiki/` (`sources/`, `entities/`, `concepts/`, `analysis/`)
as content arrives. Don't pre-create empty ones — **let structure emerge from the
sources.** Do not impose a taxonomy up front.

### Citing sources

The wiki is also a **finding-aid**: every claim should be traceable to the document it came
from, and that document should be openable. So:

- **End every content page with a `## Sources` section** listing the specific files it
  draws on, as links relative to the KB through the `raw/` symlink:
  `[<path under the source>](../raw/<source>/<path>)`. The visible text is the path (always
  precise and copy-pasteable); the link opens the original where the tool supports it.
- **Tag each source `read in full` or `not read`** (folder present / referenced by name but
  not opened). This keeps coverage honest and surfaces gaps for re-ingest.
- **Cite inline** where a specific figure or claim comes from a specific document, so a
  reader can jump from a claim to its origin.
- Paths are relative to the KB so they survive a move; only the `raw/` symlink target is
  machine-specific. (Obsidian: links outside the `wiki/` vault may open in the system app
  rather than in-pane — fine; the path is the durable part.)

## Navigation files

**`wiki/index.md` — content catalog.** Every wiki page listed with a `[[link]]` and a
one-line summary, grouped by category. Update it on every ingest/re-ingest. When
answering a query, read the index first to find relevant pages, then drill in.

**`log.md` — chronological, append-only.** One entry per operation. Format:

```
## [YYYY-MM-DD] <op> | <title>
- <what changed, which pages touched>
```

Ops vocabulary: `ingest | reingest | query | lint`. The consistent `## [` prefix keeps
it grep-parseable: `grep "^## \[" log.md | tail -5`.

## Workflows

### Ingest (new source)

Go for **depth, not a folder tour.** A page that just lists which folders exist is a
failure — read the documents and extract what they actually say.

1. **Consult `notes.md` first** (if present) — the owner's authoritative facts and
   corrections. Trust them over anything you would infer, and cite them as "per owner".
2. **Map the source** in `raw/` (follow symlinks; for a directory, walk it). For a
   directory source this map is the starting point, not the deliverable.
3. **Read the substantive documents in full** — anything carrying extractable facts
   (financial statements, tax returns, contracts, policies, agreements). Do **not**
   summarize these from their filenames. Read high-volume folders (e.g. hundreds of
   receipts) in batches to derive aggregates, not one page each.
4. **Write pages with depth and citations:**
   - a **source page** in `wiki/sources/` with provenance frontmatter;
   - an **entity page for every real entity** the source names — *including service
     providers* (accountant, brokers, payroll, banks). An important entity is never left
     as a bare dangling link;
   - **concept pages** for topics that span documents;
   - **`analysis/` pages** that synthesize across documents — the highest-value output:
     e.g. financials by period (from statements/returns), a subscriptions register and an
     asset register (from expenses), client rates (from contracts). Carry `derived_from`
     + `as_of`;
   - end **every page** with a `## Sources` section (see *Citing sources*).
5. Add new pages to `wiki/index.md`; refresh `wiki/overview.md` if the synthesis shifts.
6. Append an `ingest` entry to `log.md` — note what you read **in full** vs. **deferred**,
   the pages created, and every `[!review]` flag raised.

**Never assert a fact you only inferred from a folder or file name.** Read the document,
or cite it as `not read`. Inference-from-structure is how confidently-wrong pages happen.

### Re-ingest (a source changed)

1. Re-read the source. Compare against its existing source page.
2. Update the affected entity/concept pages. Where new data contradicts old claims, flag
   it and revise — note explicitly what was superseded.
3. **Propagate to derived pages.** For every page you changed, follow its backlinks — the
   pages that `[[link]]` to it, especially any whose `derived_from` lists it. Recompute
   each affected derived page; if you can't fully recompute it now, flag it inline and
   leave its `as_of` unchanged so Lint keeps surfacing it. Never leave a derived page
   silently inconsistent with its sources.
4. Bump `last_ingested` and `updated` on the source page; bump `updated` on every other
   page you touch, and `as_of` on any derived page you recompute. (The detection baseline
   in `.ingest/manifest.tsv` is advanced by `scripts/ingest-new.sh`, never by hand.)
5. Append a `reingest` entry to `log.md` noting what changed and which derived pages it
   rippled into.

### Query

1. Read `wiki/index.md`, then drill into the relevant pages.
2. Answer with citations to wiki pages (and through them, to raw sources).
3. If the answer is durable (a comparison, an analysis, a discovered connection), offer
   to file it back as a page in `wiki/analysis/` so the exploration compounds. Record its
   `derived_from` (the pages it draws on) and `as_of` (the snapshot date) so its freshness
   can be tracked.

### Lint (health check)

Scan for: contradictions between pages; stale claims newer sources superseded;
**stale derived pages — for any page with `derived_from`, if any listed page's `updated`
is later than this page's `as_of`, flag it stale (a pure date comparison, no re-reading
needed)**; orphan pages (no inbound links); concepts mentioned but lacking a page; missing
cross-references; **source drift — run `scripts/scan.sh`, which fingerprints every source
(files, directories, and living symlink targets) and lists anything changed since it was
last ingested; surface those as re-ingest candidates**; data gaps a web search could fill. Report findings and suggested next questions; fix with the human's
go-ahead. Append a `lint` entry.

## Mechanical detection & ingest

Detection of new/changed sources is automated so it never depends on someone remembering
to ask. The machinery lives in `scripts/` and `.ingest/`:

- **`scripts/scan.sh`** — walks `raw/`, fingerprints each source (following symlinks), and
  diffs against `.ingest/manifest.tsv` to classify **new / changed / removed**. Writes the
  queue to `.ingest/pending.md`; exits `10` if anything is pending, `0` if clean. Pure
  script, no LLM, no cost. It is also the drift check the Lint workflow calls.
- **`.ingest/manifest.tsv`** — the authoritative detection baseline: one row per ingested
  source (`source_path · kind · fingerprint · last_ingested`). **Never edit it by hand,
  and neither do you** — `scripts/ingest-new.sh` advances it after a successful ingest.
- **`.ingest/pending.md`** — the regenerated queue of what scan found. Derived; safe to
  overwrite.
- **`scripts/ingest-new.sh`** — runs `scan.sh`, and if anything is pending, ingests it,
  then advances the manifest and commits. Run it yourself, or schedule it (see
  `scripts/README.md`).

These three tenses never overlap: `log.md` records the **past** (narrative), `manifest.tsv`
holds the **present** (current ingested version of each source), `pending.md` lists the
**future** (what still needs ingesting).

### Unattended ingest

When `ingest-new.sh` runs headless (cron / launchd / `--auto`), there is no human to
discuss takeaways with. In that mode:

- Skip the "discuss with the human" step of Ingest.
- Mark any new claim you're unsure about, or anything that contradicts an existing page,
  with a `> [!review]` callout on the affected page instead of resolving it silently.
- Summarize what you ingested and list every `[!review]` you raised in the `log.md` entry,
  so the human can review on their next visit.
- Don't delete or rewrite existing synthesis on low confidence — append and flag instead.

## Principles

- You own `wiki/`; the human owns `raw/`, `inbox/`, `notes.md`, and the questions. **`raw/`
  is strictly read-only to you — never create, edit, or delete anything there, including
  through symlinks. `notes.md` is the owner's authoritative facts/corrections: read and
  cite it ("per owner"), never rewrite it.**
- Depth over breadth: read the documents and synthesize; never pad the wiki with pages that
  only restate folder names.
- Structure emerges from content — don't impose a taxonomy up front.
- Keep pages small and single-purpose; split when one grows too broad.
- Bookkeeping is your job: cross-references, freshness, consistency. Do it thoroughly.
