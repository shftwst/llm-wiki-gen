# Learning from use, Phase 1: file-back (build spec)

**Status: Spec, ready to build.** Implements `learning.md` sections 2 to 5: a durable query
answer becomes a cited, deduped, flagged page automatically. Out of scope: prominence ranking,
query-driven depth, and embedding dedup (`learning.md` sections 6, 7, and Phase 3).

Auto-file is always on. There is no toggle. Owner steering ("stop filing about X", "that answer
is wrong") stays in `notes.md`, and weak pages are removed by the retirement path (thin-page
`lint` + `relevance: off-topic` quarantine), so a global switch is not needed.

---

## 1. Behaviour in one paragraph

A query is answered with citations as today. If the answer is durable (a synthesis across pages
or a discovered connection, not a lookup), the agent dedups against existing `analysis/` pages
and either merges into the matching one or creates a new page, marked `origin: query` and
`verified: false` with a `> [!review]` note. The page is usable at once; the nightly verify pass
confirms it or flags specific claims. The synthesis is paid for once and reused.

## 2. New: `scripts/query`

A thin headless wrapper, the deterministic twin of `scripts/ingest`. It holds no file-back
logic; that lives in `AGENTS.md` so interactive sessions behave the same.

- Usage: `scripts/query "<question>"`. Flags: `--watch`, `--auto`, `--dry-run`.
- Reuses `kblib.sh`, `CLAUDE_BIN`, `CLAUDE_MODEL`, the `cost.tsv` parser, and the `log.md` writer
  from `ingest`.
- Builds a prompt that hands the question to the agent and points it at the Query workflow, runs
  headless Claude Code, prints the answer.
- Appends a `query` entry to `log.md` (per the existing `## [date] query | <title>` format) and a
  `cost.tsv` row tagged mode `query`.
- `--dry-run` prints the planned invocation and writes nothing (the no-LLM self-check path).

## 3. Changed: the Query workflow in `AGENTS.md`

Replace the three-step consent version with:

1. Read `wiki/index.md`, drill into the relevant pages, answer with citations to wiki pages (and
   through them to raw sources).
2. If the answer is **durable**, file it back without asking:
   - **Dedup first.** Search `wiki/analysis/` for a page answering the same question (overlapping
     `derived_from` plus a matching title or subject). Found: update it (new `as_of`, append the
     new angle). Not found: create a new page. Unsure whether two questions are the same: prefer
     updating over creating.
   - **Write it flagged.** `maintained_by: agent`, `origin: query`, `verified: false`, a
     `> [!review]` note ("machine-synthesised from a query, not yet verified"), `derived_from`
     (the pages it draws on), and `as_of` (today).
   - **Trust boundary.** `derived_from` names existing wiki pages only. The question never
     introduces a new fact; a page may only synthesise what the sources already support.
3. If the answer is a **lookup** (ephemeral), file nothing.
4. If the wiki cannot answer, say so plainly and surface the gap. Do not read an unread source to
   close it (that is Phase 2); do not guess.
5. Append a `query` entry to `log.md`.

Durability test: a multi-page synthesis or a discovered connection is durable ("how the
cash-for-equity arrangement nets out across the contracts"); a single-fact recall is ephemeral
("the registered office address").

## 4. Page schema additions

- `origin: ingest | query` (new, optional; absent means `ingest` for back-compat). Query-filed
  analysis pages set `origin: query`.
- `verified: false` on creation. The existing `verified: <date>` form means confirmed; the verify
  pass sets it.
- The `> [!review]` callout carries the unconfirmed-synthesis note until verify clears it.

No new page type: these are ordinary `analysis` pages (class `content`), so every existing rule
(`## Sources`, prose hygiene, freshness) already applies.

## 5. Changed: `scripts/ingest --verify`

Page selection prioritises pages with `origin: query` and no `verified:` date, ahead of the
existing highest-risk selection. On a pass, set `verified: <date>` and drop the `> [!review]`
synthesis note. On a fail, keep the page but replace the note with the specific unsupported
claim; a thin or wholly unsupported page becomes a retirement candidate (section 7). Writes the
usual `qa.tsv` row. Rides the nightly `ingest --auto` cron unchanged.

## 6. Changed: `lint`

- Validate the `origin` enum (`ingest | query`); warn on any other value.
- A `origin: query` page must carry `derived_from` (it is a synthesis); error if missing.
- The thin-page check **applies** to query pages (they are `maintained_by: agent`), so a weak
  auto page surfaces as a removal candidate. No new exemption.

## 7. Changed: `stats`

Add a line: count of `origin: query` pages, split verified versus unverified, beside the existing
wiki-page and `% verified` reporting.

## 8. Reused, no new code: retirement

Thin-page `lint` and the `relevance: off-topic` quarantine flag already exist. Query pages flow
through both. Creation without consent is matched by retirement without consent, reversibly, with
git keeping the history.

## 9. Data flow

```
scripts/query "..."  (or an interactive session)
   -> agent answers with citations
   -> durable?  no  -> done
                yes -> dedup vs wiki/analysis/
                       -> match    -> update page (new as_of)
                       -> no match -> create page
                          (origin: query, verified: false, [!review],
                           derived_from existing pages, as_of today)
   -> log.md query entry + cost.tsv row

nightly  ingest --auto -> --verify
   -> pick origin:query + unverified pages first
   -> pass -> verified: <date>, drop the note
   -> fail -> specific [!review]; thin -> retirement candidate
```

## 10. Edge cases and invariants

- **Ephemeral query:** no page.
- **Already covered:** merge, never a second page on the same question.
- **Dedup uncertainty:** prefer merge (skip-when-unsure on create), since a duplicate page is the
  cheap-but-visible error here.
- **Unanswerable from the wiki:** state the gap; no page; no source read (Phase 2 owns that).
- **Hostile or garbage query:** cannot create a page, because a page may only assert what
  `derived_from` pages already support. The question is data, not instruction.
- **Owner override:** a `notes.md` line ("do not file pages about X", "page Y is wrong") is
  honoured on the next run, the same as any other owner correction.

## 11. Out of scope (guards against sprawl)

No `queries.tsv`, no prominence reranking in `index` or `overview`, no on-demand reading of an
unread source, no embedding dedup. Those are `learning.md` Phase 2 and Phase 3.

## 12. Acceptance: one smoke run against a real KB

Run against `1-knowledge-layer/shftwst-ops-kb` (a populated wiki), watched by a human:

1. A durable question files a new `analysis` page: `origin: query`, `verified: false`,
   `> [!review]` present, `derived_from` set to the pages it used.
2. The same question again updates that page; no duplicate is created.
3. An ephemeral question files nothing.
4. `scripts/ingest --verify` flips the page to `verified: <date>` or raises a specific
   `> [!review]`.
5. `scripts/lint` passes (or flags as designed); `scripts/stats` shows the `origin: query` count.

The deterministic pieces (`scripts/query --dry-run`, the `lint` and `stats` changes) are checked
without an LLM; the agent behaviour is exercised by this run, since unit-testing a paid,
non-deterministic model call is not sensible and the kit ships no test framework.
