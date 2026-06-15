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
├── raw/               # sources (files, directories, symlinks to living docs)
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
  last_ingested: YYYY-MM-DD
  fingerprint: <mtime or short hash>   # cheap drift signal; optional
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
  here. Lives in `wiki/analysis/`.
- **overview** — `wiki/overview.md`, the evolving synthesis. **index** — `wiki/index.md`.

Create subdirectories under `wiki/` (`sources/`, `entities/`, `concepts/`, `analysis/`)
as content arrives. Don't pre-create empty ones — **let structure emerge from the
sources.** Do not impose a taxonomy up front.

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

1. Read the source in `raw/` (follow symlinks; for a directory, walk it).
2. Discuss key takeaways with the human.
3. Write a source page in `wiki/sources/` with provenance frontmatter.
4. Create or update the entity and concept pages the source touches — a single source
   may touch 10–15 pages.
5. Add new pages to `wiki/index.md`; refresh `wiki/overview.md` if the synthesis shifts.
6. Append an `ingest` entry to `log.md`.

### Re-ingest (a source changed)

1. Re-read the source. Compare against its existing source page.
2. Update only the affected wiki pages. Where new data contradicts old claims, flag it
   and revise — note explicitly what was superseded.
3. Bump `last_ingested` and `fingerprint` on the source page; bump `updated` on every
   page you touch.
4. Append a `reingest` entry to `log.md` noting what changed.

### Query

1. Read `wiki/index.md`, then drill into the relevant pages.
2. Answer with citations to wiki pages (and through them, to raw sources).
3. If the answer is durable (a comparison, an analysis, a discovered connection), offer
   to file it back as a page in `wiki/analysis/` so the exploration compounds.

### Lint (health check)

Scan for: contradictions between pages; stale claims newer sources superseded; orphan
pages (no inbound links); concepts mentioned but lacking a page; missing cross-references;
**living sources (`source_kind: symlink-living`) whose target changed since
`last_ingested`, or that are overdue — surface as re-ingest candidates**; data gaps a web
search could fill. Report findings and suggested next questions; fix with the human's
go-ahead. Append a `lint` entry.

## Principles

- You own `wiki/`; the human owns `raw/` and the questions.
- Structure emerges from content — don't impose a taxonomy up front.
- Keep pages small and single-purpose; split when one grows too broad.
- Bookkeeping is your job: cross-references, freshness, consistency. Do it thoroughly.
