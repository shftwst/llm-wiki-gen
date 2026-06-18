# Learning from use, Phase 2a: usage-shaped prominence (build spec)

**Status: Spec, ready to build.** Implements `learning.md` section 6: what gets asked rises in
the catalog and surfaces on the home page, and the owner gets a live "most asked" view. Out of
scope: query-driven depth (`learning.md` section 7), time-decay on counts, log rotation,
embeddings. Builds on Phase 1 (`learning-phase1.md`), which added `scripts/query` and the
auto-file Query workflow.

The signal is deterministic (an append-only page-hit log, aggregated by counts). The application
to `wiki/index.md` and `wiki/overview.md` is the agent's, because scripts never write `wiki/` in
this kit; that invariant holds.

---

## 1. Behaviour in one paragraph

Every answered query appends one row per wiki page it drew on to `.ingest/queries.tsv` (page
slugs and a date, no question text). `scripts/stats` aggregates that log into a MOST QUERIED
report any time. When the agent regenerates `wiki/index.md` and `wiki/overview.md` during ingest,
it consults the log and orders the catalog so frequently-asked pages rise, surfacing the top few
on the home page. Prominence is slow-moving, so refreshing on ingest is enough; `stats` gives the
live view between ingests.

## 2. New ledger: `.ingest/queries.tsv`

Append-only, identifiers only. Two TAB columns:

```
# queries.tsv — per-query page-hit log (appended by the agent on every answered query).
# Columns: date	page   (page = the wiki slug the answer drew on; identifiers only, no query text)
```

One row per wiki page an answered query used. Counts are aggregated at read time, so there is no
read-modify-write. The template ships an empty `queries.tsv` carrying only the two header lines,
like `cost.tsv`. It is committed, so usage history travels with the KB.

## 3. Changed: the Query workflow in `AGENTS.md`

Append a step to the `### Query` section (after the existing steps):

```markdown
7. For **every** answered query (durable, lookup, or partial), append one `date<TAB>page` row to
   `.ingest/queries.tsv` for each wiki page the answer drew on, page slugs only, never the
   question text. This is the usage signal that shapes prominence, so it runs even when nothing
   is filed. An unanswerable question (no pages used) appends nothing.
```

This is distinct from step 6 (the `log.md` entry, which fires only when a page is filed or
updated): `queries.tsv` tracks what is asked about, `log.md` tracks what changed.

## 4. Changed: prominence in `AGENTS.md` Navigation files

In the `## Navigation files` section, extend the `wiki/index.md` paragraph so the catalog is
usage-ordered, and state the home-page surfacing:

```markdown
**`wiki/index.md`: content catalog.** Every wiki page listed with a `[[link]]` and a one-line
summary, grouped by category. Update it on every ingest/re-ingest. When answering a query, read
the index first to find relevant pages, then drill in. **Order pages within each category by how
often they are asked about** (the per-page hit count in `.ingest/queries.tsv`, most-asked first;
ties keep their existing order). On `wiki/overview.md`, keep a short **Most asked about** section
listing the top few pages by that count, so the home page leads with what people actually use.
Prominence is a soft signal layered on top of the catalog, not a reordering of the underlying
pages or their privilege.
```

The agent applies this when it regenerates `index.md`/`overview.md` during ingest (the Ingest
workflow already does "Add new pages to `wiki/index.md`; refresh `wiki/overview.md`"). No script
writes `wiki/`.

## 5. Changed `scripts/stats`: MOST QUERIED report

Add a read-only section that aggregates `queries.tsv`. Place it after the VERIFICATION (qa.tsv)
section, mirroring the existing SENSITIVITY / RELEVANCE blocks:

- Header: `MOST QUERIED (.ingest/queries.tsv)`.
- If the ledger has no data rows: `(none yet — answered queries log page hits here)`.
- Otherwise: a totals line (`N page-hits logged across M pages`) and the top 10 pages by hit
  count, each as `count  page  (last asked YYYY-MM-DD)`, highest count first.

No LLM. Aggregation is `awk` over the TSV, the same idiom as the cost/relevance sections.

## 6. Changed `scripts/query`: prompt reminder

Add one clause to the `PROMPT` string so an unattended headless run logs the hits even though the
behaviour is defined in `AGENTS.md`: after the existing file-back instruction, append `Also log
the wiki pages your answer used to .ingest/queries.tsv per the Query workflow (page slugs and a
date only).` No other `scripts/query` change.

## 7. Template ships the ledger

Add `_template/.ingest/queries.tsv` with the two header lines from section 2 and no data rows, so
every generated KB has it from creation.

## 8. Data flow

```
query answered (scripts/query or interactive)
   -> agent appends date<TAB>page rows to .ingest/queries.tsv  (one per page used)

anytime:  scripts/stats  ->  MOST QUERIED report (counts, last-asked)

on ingest: agent regenerates index.md / overview.md
   -> orders catalog by per-page hit count; top few -> overview "Most asked about"
```

## 9. Edge cases and invariants

- **Identifiers only.** `queries.tsv` never stores question text, so it adds no new sensitive
  data beyond page slugs the wiki already exposes.
- **Every answered query logs hits**, durable or lookup; an unanswerable question logs nothing.
  This is the opposite of the Phase 1 `log.md` rule (file-only), on purpose.
- **Append-only.** No read-modify-write; counts are derived at read time. A cancelled run that
  wrote nothing simply adds no rows.
- **Scripts never write `wiki/`.** Prominence reaches the nav pages only through the agent.
- **Stale slug tolerance.** A slug in `queries.tsv` whose page was later renamed or deleted still
  aggregates in `stats` as a count against that slug; it is harmless and just will not appear in
  a regenerated index. `stats` does not need to resolve slugs to files.
- **Plain counts, no decay.** A page asked less simply falls in the ranking; nothing is deleted.
  Time-decay is deferred.

## 10. Out of scope (guards against sprawl)

No query-driven depth (no query-miss detection, no on-demand source read, no `coverage.tsv`
promotion, which is `learning.md` section 7). No time-decay or half-life on counts. No
`queries.tsv` rotation or size cap. No embeddings. No script writing into `wiki/`.

## 11. Acceptance

Deterministic (no LLM), against a scratch KB:

1. With a fixture `.ingest/queries.tsv` holding known rows, `scripts/stats` prints the MOST
   QUERIED section with the correct totals, the right top page, its count, and its last-asked
   date.
2. An empty `queries.tsv` (header only) prints the `(none yet ...)` line.

Live (human-run, on `shftwst-ops-kb`): ask two or three questions with `scripts/query`; confirm
`queries.tsv` gains a row per page used; confirm `stats` shows MOST QUERIED; after an ingest,
confirm `index.md` ordering and the `overview.md` "Most asked about" section reflect the hits.

The deterministic pieces (`queries.tsv` format, the `stats` aggregation) are unit-checked; the
agent behaviours (logging hits, applying prominence) are governed by `AGENTS.md` and exercised by
the live run, since the kit ships no test framework and the behaviour is non-deterministic.
