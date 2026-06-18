# Learning from use (design)

**Status: Not built. Design only, opt-in.** This records the architecture so the decisions are
on file. The goal is the "self-improving" and "usage-shaped" half of the second-brain framing:
the wiki should get better the more it is queried, without a human curating every step, and
without the auto-curation quietly degrading the wiki it is meant to improve.

The Query workflow in `AGENTS.md` already files durable answers back as pages: when an answer is
a real synthesis, the agent offers to save it under `wiki/analysis/` with `derived_from` and
`as_of`. Today that offer needs a human yes. This design is about removing that step safely, and
about two further things the file-back loop does not cover.

---

## 1. Three mechanisms, kept separate

"Learns from use" conflates three different things that share only a trigger (a query):

- **File-back.** A durable answer becomes a permanent, cited page, so the synthesis is paid for
  once and reused. This is the existing Query step, made automatic (sections 2 to 5).
- **Usage-shaped prominence.** What gets asked rises: frequently-hit pages climb the index and
  surface on the home page. A query log and a ranking step of their own (section 6).
- **Query-driven depth.** A question whose answer sits in a source not yet read pulls that source
  up the read frontier, on demand or in the next batch. Usage decides where the corpus gets read
  deeply, not just a static value heuristic (section 7).

Build and reason about them apart.

## 2. The asymmetry, and how it flips

Relevance triage (`relevance.md`) defaults to keep, because for ingestion the expensive error is
false-drop: losing a real document silently. Auto-filing inverts this. The expensive error is
**false-create**: a thin or duplicate page, and at query volume that is death by a thousand thin
pages, each one more graph to lint, dedup, and mistrust. So the fail-safe default flips: when
durability is unclear, do not create, queue it. Keep-when-unsure becomes skip-when-unsure.

## 3. What the consent step was doing

The human yes was quietly doing three jobs. Drop it and each must be replaced.

1. **Durability triage.** "Is this answer worth a page?" becomes a cheap classifier with three
   verdicts: `durable | ephemeral | already-covered`. Same shape as the map-pass relevance
   verdict, fail-safe toward not creating (section 2). A lookup ("what is the office address") is
   ephemeral; a multi-page synthesis ("how the cash-for-equity arrangement nets out") is durable.
2. **Dedup and merge, not create.** The same question asked five ways must not make five pages.
   Before writing, search the wiki for an existing analysis page on that question and update or
   merge instead of spawning a duplicate. This is semantic dedup over questions, not the
   size/content dedup `scan` does over raw files, and it is the one genuinely new build here
   (section 4).
3. **A correctness check.** Consent was also a sanity glance that the synthesis was right.
   Without it, an auto-filed page is an unchecked claim the system now asserts as fact, and the
   next answer will cite it: a wrong answer becomes self-reinforcing. An auto-page must run
   through the `--verify` adversarial pass (`../_template/docs/qa.md`) before it is trusted, or
   land at lower confidence (`verified: false`, a `> [!review]` flag) until a batched verify
   confirms it.

## 4. The new build: semantic dedup and merge

Everything else is composition of shipped parts; this is the piece that does not exist yet.
Before filing a durable answer, the system must answer "is this already a page?" The cheap path:
the answer already names its `derived_from` pages, so a candidate match is an existing
`analysis/` page built from an overlapping set of `derived_from` pages on the same question.
Candidates go to a merge decision: extend the existing page (new `as_of`, append the new angle)
or, only if genuinely distinct, create. When unsure whether two questions are the same question,
prefer merge over create, consistent with section 2's skip-when-unsure.

## 5. Invariants to keep

- **Trust boundary.** Queries are untrusted input, more so in a multi-user deployment. The
  current model is safe because analysis pages are `derived_from` existing wiki pages, so the
  question itself never injects a new raw fact. Keep that hard: auto-filing synthesises over
  pages, it never lets a query plant a fact. A garbage or hostile question must not be able to
  create a page asserting something the sources do not.
- **Symmetric retirement.** If the system creates pages without asking, it must be able to demote
  and retire them without asking, reversibly. Wire auto-pages into the existing thin-page `lint`
  check and the `relevance: off-topic` quarantine flag, so creation and cleanup are one loop, not
  a create-only ratchet.
- **Cost on the hot path.** Answering stays cheap. Do not run classify, dedup, and verify inline
  on every query. The hot path writes only a cheap durability tag to a log; the dedup-merge and
  verify run in a nightly batch on the same cron as `ingest --auto`. Compounding is allowed to be
  asynchronous.

## 6. Usage-shaped prominence

What gets asked should rise. This needs:

- **A query log.** `.ingest/queries.tsv`: the pages a query hit, a count, and a last-asked date,
  appended per query. Page identifiers only, no query text and no page contents, so it is cheap
  and carries no new sensitive data (see section 11).
- **A deterministic ranking step** that `index` and `overview` read: bump frequently-hit pages up
  the catalog and surface the top few on the home page. Counts only, no LLM, the kind of cheap
  determinism the project prefers.

Prominence is reversible and never deletes: a page that stops being asked about falls back down
the ranking on its own.

## 7. Query-driven depth (reading on demand)

Progressive deepening means much of the corpus is `unread` at any moment: the read frontier
(`coverage.tsv`) holds documents the value heuristic has not reached yet. So a query can need a
fact that exists in a source the system has not read. This is different from a fact that is not
in the corpus at all, and the two must not be confused.

The frontier already knows the difference. `coverage.tsv` lists every source with a read status
(`unread | partial | read | stale`) and a value tier. When the wiki cannot answer, the agent can
see whether a plausibly relevant source is merely unread (answerable by reading it) or absent (a
real gap). Three responses, in order of preference:

1. **Targeted read on demand.** Pull the one relevant unread source up the frontier and read it
   now, whatever its value tier, to answer this question. A bounded read of the single source,
   not a full `--deepen` pass, so the hot-path cost is one document and it is opt-in per query
   ("this is not in the wiki yet; it is likely in [source], read it now?").
2. **Promote, then batch.** Whether or not it reads inline, the miss is logged against that
   source so the nightly batch raises its value. This is the same demand signal as usage-shaped
   prominence (section 6), applied to the read frontier instead of the index: questions pull
   depth toward where they land, so the corpus is read deeply where it is used, not only where a
   static heuristic guessed.
3. **Say so.** If no source covers the question, or the user declines the inline read, the agent
   states the gap plainly rather than guessing, consistent with the cautious posture in
   `AGENTS.md` (prefer inaction and surface it). A `> [!review]` note or a `lint` data-gap finding
   records it; it never fabricates to fill an unread hole.

The failure to design out is a confident answer drawn from a half-read wiki. The frontier makes
the gap visible; the rule is to surface it, optionally close it on demand, and always promote it
so depth follows demand.

## 8. How it maps onto the current system

Most of the scaffolding exists:

- **The Query step (`AGENTS.md`)** already files durable answers; this removes the human gate.
- **`wiki/analysis/` + `derived_from` + `as_of`**: the page form and the freshness handles, so an
  auto-page is a normal page and `lint` flags it stale by date when a source updates.
- **The map-pass relevance verdict**: the model for the durability classifier, fail-safe flipped.
- **`coverage.tsv` read status + value tiers**: already distinguishes unread from absent, and is
  the frontier a query-miss reprioritises (section 7).
- **`--verify` + `qa.tsv`**: the correctness gate for un-consented pages.
- **Thin-page `lint` + `relevance: off-topic`**: the retirement path.
- **`notes.md`**: the owner override ("stop filing pages about X", "that answer is wrong").
- **The `ingest --auto` cron**: where the nightly dedup, verify, promote, and rank batch rides.

What is missing: the durability classifier, the semantic dedup-and-merge step, the query-miss
detection and promotion, the `.ingest/queries.tsv` log, and the prominence ranking in `index` and
`overview`.

## 9. Patterns it builds on

- **Triage and fail-safe classification.** As in `routing.md` and `relevance.md`, a cheap stage
  gates expensive work and defaults to the safe side. Here safe means skip-and-queue, not keep.
- **Defense in depth.** No single filter is trusted: a cheap durability tag, semantic dedup, a
  verify pass, and a thin-page audit each catch what the others miss, the same layering as the QA
  strategy (`../_template/docs/qa.md`).
- **Write-back caching.** A query is a cache miss that pays to compute an answer; filing it
  populates the cache so the next hit is cheap. Dedup-on-write and the retirement of cold entries
  are the cache's eviction policy.
- **Demand-driven crawling.** A focused crawler spends its budget where the topic pays. Section
  7's query-driven depth is the same idea turned around: read deeply where the questions already
  land, not by a fixed value order set before anyone asked anything.

## 10. Phased plan

- **Phase 1 (file-back, batched).** The durability classifier, structural dedup (overlapping
  `derived_from` plus title match), merge-or-create, and the verify gate, all run nightly. No
  hot-path cost beyond a logged tag. Auto-filed pages land `verified: false` until the batch
  confirms them.
- **Phase 2 (depth and prominence from use).** Query-miss detection against `coverage.tsv` with an
  opt-in targeted read to answer now and a promotion for the next batch; `.ingest/queries.tsv` and
  the deterministic prominence ranking in `index` and `overview`.
- **Phase 3 (smarter dedup).** Replace structural matching with an embedding index over page
  topics if Phase 1 shows structural matching misses too many same-question duplicates.

All opt-in and fail-safe: with none of it, the Query step behaves as it does today, consent and
all.

## 11. Open decisions

- **Consent default.** Whether auto-filing is on by default once trusted, or always opt-in per
  KB. Likely opt-in, matching `--auto` ingest: enable it once you trust the supervised flow.
- **Dedup mechanism.** Structural (`derived_from` overlap plus title) versus an embedding index.
  Start structural; measure the duplicate rate before adding embeddings.
- **Verify timing.** Whether an un-verified auto-page is visible (flagged low-confidence) or
  withheld until the nightly verify passes. Leaning visible-but-flagged, so the answer is usable
  at once and the flag is honest about its state.
- **Inline read versus batch-only.** Whether a query may trigger a paid read on the hot path
  (answer now, the user waits and pays) or only ever promotes the source for the next batch
  (answer available next run). Leaning opt-in inline for an explicit ask, always promote
  regardless.
- **Query-log privacy.** Whether `queries.tsv` may record query text (a better topic signal, but
  query text can itself be sensitive) or only page identifiers. Default to identifiers only.
- **Owner steering.** How `notes.md` expresses "never auto-file about X" or "keep Y prominent",
  and how a re-classification honours a change to it.
