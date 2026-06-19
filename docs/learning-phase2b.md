# Learning from use, Phase 2b: query-driven depth (build spec)

**Status: Spec, ready to build.** Implements `learning.md` section 7 responses 2 (promote) and 3
(say so): when the wiki cannot answer but the data sits in an unread source, flag that source so
the next ingest reads it first, and record the miss. Out of scope: response 1, the paid inline
"read it now" read (deferred to a later phase, with this spec's `demand.tsv` as its foundation);
no embeddings. Builds on Phases 1, 2a.

The flag is a cheap append to a sidecar log; no paid read happens on the query path. The reading
still happens only when `ingest` runs, exactly as today; the query just leaves a flag that
reorders the read frontier. The query path never writes `coverage.tsv`, preserving the Phase 1
guard.

---

## 1. Behaviour in one paragraph

When a query cannot be answered from the wiki, the agent reads `.ingest/coverage.tsv` (the read
frontier). If a plausibly relevant source is still `unread` or `partial`, it appends one row to
`.ingest/demand.tsv` (the source path plus a short topic note, no question text) and tells the
user the answer likely lives in that source, not yet read, flagged for the next pass. If nothing
covers the question, it says it is a genuine gap. The next `ingest` read/deepen pass reads any
still-unread demanded source first, ahead of the value order, so questions pull depth toward
where they land. `stats` shows the demanded-but-unread backlog.

## 2. New ledger: `.ingest/demand.tsv`

Append-only. Three TAB columns:

```
# demand.tsv — sources a query needed but had not read yet (appended by the agent on a miss).
# Columns: date	source	note   (source = coverage.tsv path; note = short topic only, no question text)
```

`source` is the `coverage.tsv` path the agent judged relevant; `note` is a short topic phrase
(what was needed), never the verbatim question. Counts are aggregated at read time. The template
ships an empty `demand.tsv` with these two header lines, like `queries.tsv`. It is committed, so
the backlog travels with the KB.

## 3. Changed: the Query workflow in `AGENTS.md`

Replace step 5 of the `### Query` section. Current:

```markdown
5. If the wiki cannot answer, say so plainly and surface the gap. Do not read an unread source
   to close it; do not guess.
```

New:

```markdown
5. If the wiki cannot answer, read `.ingest/coverage.tsv`. If a plausibly relevant source is
   `unread` or `partial`, append a `date<TAB>source<TAB>note` row to `.ingest/demand.tsv` (source =
   its coverage path; note = a short topic phrase of what was needed, never the question text), and
   tell the user the answer likely lives in that source, which is not read yet and is now flagged
   for the next read pass. If no source plausibly covers the question, say it is a genuine gap. Do
   not read the source now to answer (that is a later phase) and do not guess; log the need and
   move on. Do not edit `.ingest/coverage.tsv`.
```

(`demand.tsv` is a sidecar the query path may append to; `coverage.tsv` and `manifest.tsv` stay
read-only from the query path, unchanged from Phase 1.)

## 4. Changed: `scripts/ingest` reads demanded sources first

In `scripts/ingest`, the `POLICY` string (set in the `--fresh` if/else) drives the read/deepen
frontier order. After the if/else sets `POLICY`, append a demand clause:

```bash
POLICY="$POLICY Before that ordering, read .ingest/demand.tsv: any source listed there that is still unread or partial in coverage.tsv is read FIRST this pass, ahead of the value and freshness order, because a question needed it. Once read it leaves the demand backlog naturally (it is no longer unread)."
```

`POLICY` is interpolated only into the read and deepen prompts, so map and verify are unaffected.
No new flag; demand prioritisation is automatic on every read/deepen pass.

## 5. Changed `scripts/stats`: DEMANDED report

Add a read-only section after MOST QUERIED, before COST, mirroring the existing sidecar sections:

- Header: `DEMANDED (.ingest/demand.tsv)`.
- Empty case (no data rows): `(none yet — a query logs a source here when its data is unread)`.
- Otherwise: a totals line (`N demand(s) across M source(s)`), then the top sources by demand
  count, each as `count  source  [status]  (last asked DATE)`, where `status` is the source's
  current `coverage.tsv` status (`unread` / `partial` / `read`, or `?` if the path is not in
  coverage). Still-`unread`/`partial` sources are the live backlog the next ingest will read;
  `read` ones are satisfied.

No LLM. The status lookup reads `coverage.tsv` into a map, then aggregates `demand.tsv`.

## 6. Changed `scripts/query`: prompt reminder

After the existing `queries.tsv` clause in the `PROMPT` string, append: `If you cannot answer and
a relevant source is unread, log it to .ingest/demand.tsv per the Query workflow (source path and a
short topic note only).` No other `scripts/query` change.

## 7. Template ships the ledger

Add `_template/.ingest/demand.tsv` with the two header lines from section 2 and no data rows, so
every generated KB has it from creation.

## 8. Data flow

```
query cannot be answered (scripts/query or interactive)
   -> agent reads coverage.tsv
      -> relevant source unread/partial?  yes -> append date<TAB>source<TAB>note to demand.tsv,
                                                   tell user "flagged [source] for next read pass"
                                          no  -> "genuine gap, nothing covers this"

next ingest read/deepen pass
   -> POLICY reads demand.tsv; still-unread demanded sources read FIRST, then value order
   -> once read, the source is no longer unread, so it drops out of the backlog

anytime: scripts/stats DEMANDED -> still-unread demanded sources (count, last asked, status)
```

## 9. Edge cases and invariants

- **No paid read on the query path.** The query only appends to `demand.tsv`. All reading stays
  on the ingest path, same as today. This is the deferred-inline-read decision made explicit.
- **Query path never writes `coverage.tsv`.** It appends to the `demand.tsv` sidecar only,
  preserving the Phase 1 guard. The frontier reorder happens during ingest, where the agent owns
  `coverage.tsv`.
- **Unread vs absent.** The agent distinguishes via `coverage.tsv`: a relevant `unread`/`partial`
  row means flag-and-promote; no relevant row means a genuine gap (no demand row). This is the
  same unread-vs-absent split `learning.md` section 7 calls out.
- **Privacy.** `demand.tsv` stores a `coverage.tsv` path (already an internal ledger value, no new
  exposure) and a short topic note, never the verbatim question, consistent with `queries.tsv`.
- **Append-only, self-clearing backlog.** Demand never edits prior rows. A demanded source stops
  being prioritised once it is read (the POLICY clause intersects demand with still-`unread`), so
  no explicit cleanup is needed; the rows stay as an audit trail.
- **Trust boundary.** A query cannot force a raw read or write; `demand.tsv` is advisory to the
  ingest frontier, which still honours relevance and the read-only `raw/` guard.

## 10. Out of scope (guards against sprawl)

No inline "read it now" paid read on the query path (deferred; `demand.tsv` is its foundation). No
`coverage.tsv` writes from the query path. No demand-log rotation or size cap. No embeddings. No
change to how relevance or freshness already order the frontier beyond placing demanded sources
first.

## 11. Acceptance

Deterministic (no LLM), against a scratch KB:

1. With fixture `.ingest/demand.tsv` rows and a matching `.ingest/coverage.tsv`, `scripts/stats`
   prints the DEMANDED section with the correct totals, the top source, its demand count,
   last-asked date, and its coverage status (`unread`/`read`).
2. An empty `demand.tsv` (header only) prints the `(none yet ...)` line.
3. `scripts/ingest --deepen --dry-run` runs and the read/deepen `POLICY` carries the demand
   clause (grep the script).

Live (human-run, on `shftwst-ops-kb`): ask a question whose source is unread (e.g. the 2024 T5
slip, flagged `[!review]` as unread); confirm the agent appends a `demand.tsv` row and says it is
flagged; confirm `stats` DEMANDED lists it as `unread`; run `ingest --deepen` and confirm that
source is read first and then drops off the backlog.

The deterministic pieces (`demand.tsv` format, the `stats` aggregation, the `POLICY` clause) are
unit-checked; the agent behaviours (miss detection, demand logging, reading demanded first) are
governed by `AGENTS.md` and the ingest prompt and exercised by the live run.
