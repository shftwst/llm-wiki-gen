# Relevance and noise tolerance (design)

**Status: design only, nothing built yet. Opt-in.** This captures the architecture so the
decisions are recorded before any code. The goal is to make ingestion tolerant of irrelevant
input (junk files, accidental drops, misfiled documents, off-topic material) without ever
silently discarding something real.

Every KB accumulates noise. `inbox/` is a shared drop point, so people will drop the wrong
thing: a duplicate, a system file, or a document that belongs to a different KB. The system
must tolerate that. Noise should not waste deep-read budget and should not pollute the wiki or
the pages derived from it. But the cure has to be gentler than the disease.

---

## 1. The asymmetry that drives the design

Two failure modes, very unequal in cost:

- **False-keep**: a junk file gets ingested. Cost: some wasted tokens and a thin or odd page.
  Cheap, visible, reversible.
- **False-drop**: a real document gets discarded as noise. Cost: lost knowledge, lost
  silently, with nothing in the wiki to indicate the gap.

False-drop is the expensive error, so the policy is **quarantine and flag, never delete**, and
every uncertain call resolves toward keeping. This mirrors the fail-safe stance of the
sensitivity classifier (default to sensitive when unsure): here, default to "keep but park"
when relevance is unclear.

A hard constraint reinforces it. `raw/` is read-only to the agent, so it cannot delete a raw
source even if it wanted to. The agent can park, down-rank, and flag a raw item; only the
owner removes it at its origin. The agent owns `wiki/` and can delete pages there, but even
then a reversible quarantine beats a hard delete.

---

## 2. Relevance needs a reference: the charter

"Irrelevant" is undefined unless the KB states what it is about. Today nothing does. The
prerequisite for every judgment below is a short **charter**: two or three sentences naming the
KB's scope and its explicit non-scope.

Example for the ops KB:

> This KB covers the operations of acme-consulting-inc: its finances, clients and
> engagements, corporate records, tax, banking, insurance, and the vendors and people involved.
> Out of scope: personal life unrelated to the company, unrelated side projects, and material
> belonging to other entities.

The charter lives in `AGENTS.md` (it is schema) and is the yardstick the map pass and the
relevance audit measure against. Without it, relevance triage is guessing. A charter that names
the non-scope explicitly is more useful than one that names only the scope.

---

## 3. Kinds of irrelevance, and the right response to each

Not all noise is the same, and the handling differs:

- **Junk / cruft** (system files, zero-byte files, temp files, exact duplicates).
  High-confidence, detectable mechanically. Skip for free: no LLM, no page.
- **Off-charter but real** (a genuine document that does not fit the KB's scope). Needs judgment
  against the charter. Park and flag; never auto-delete.
- **Misfiled** (a real document that belongs to a *different* KB). The fix is relocation, not
  deletion: flag it with a suggested destination; the owner moves the raw file at its origin and
  re-ingests it there.
- **Superseded version** (v1 when v2 exists). Freshness and dedup territory: supersede, do not
  silently keep both.
- **Low-value but on-charter** (incidental receipts, minor notes). Not irrelevant. The existing
  value tier already handles these; they are read last, not parked.

Conflating these produces bad behavior (deleting an off-charter document, or treating a
duplicate as junk). The design keeps them distinct.

---

## 4. Relevance as a tracked dimension

Relevance becomes a first-class signal beside value and sensitivity, recorded per source. The
natural home is `coverage.tsv` (a new `relevance` column) or a sidecar like `sensitivity.tsv`
if a column would collide with `scan --refresh`.

Values:

- `relevant` (default for on-charter material)
- `off-charter` (real but outside scope, parked)
- `junk` (mechanical garbage, parked)
- `misfiled:<target>` (belongs elsewhere, parked with a destination hint)
- `unsure` (needs human confirmation)

Parked items are never promoted to a deep read and never publish. They stay in the ledger so
the decision is auditable and reversible, and so a downstream consumer (a RAG pipeline, an
agent) can filter on it.

---

## 5. Pre-ingestion guards (cheapest first)

Concentrate the guard at the boundary between `--map` (cheap) and `--deepen` (expensive); that
is where the token savings live. Layer the checks so each is fail-safe toward keeping.

1. **Mechanical ignore list (free).** A `.ingestignore` (gitignore-style globs) honored by
   `scan` and `sweep`: system cruft, zero-byte files, files with no extractable text. `sweep`
   is the enforcement point, since it is already the intake gate from `inbox/` to `raw/`.
2. **Dedup at scan.** `scan` already fingerprints every source in the manifest. Extend it to
   flag content-identical duplicates so the same document is not read twice or turned into two
   pages.
3. **Triage in `--map`.** The map pass already enumerates the corpus into `coverage.tsv` with a
   value tier. Add a relevance verdict against the charter from cheap signals (path, filename,
   skeleton), writing `off-charter` / `junk` / `unsure` and parking them. This is light work on
   metadata, not a full read.
4. **Human gate via `pending.md`.** Items marked `unsure` (and optionally `off-charter`) land in
   a review section of `pending.md` rather than being read or dropped silently. The owner
   confirms (stays parked) or rescues (re-tag `relevant`).

---

## 6. Post-ingestion cleanup (the real safety net)

A filename can lie; the content cannot. The most reliable relevance signal arrives only after a
document is read, so post-ingestion is the net that catches what pre-ingestion guessed wrong.

1. **Post-read verdict.** When a doc is read and proves to be noise, set its `relevance`
   accordingly. Deepen, verify, and publish then all skip it.
2. **Quarantine pages, do not vaporise them.** A page built from a doc that turned out
   irrelevant is tagged `relevance: off-topic` in frontmatter (excluded from `index`,
   `overview`, and `publish`) or moved to `wiki/_quarantine/`, with a `log.md` entry recording
   what and why. Reversible, and git keeps the history regardless.
3. **Lint surfaces noise.** Extend `lint` to flag thin pages (very short, no real facts, no
   inbound links, sourced only to a parked doc) as removal candidates for human review, not
   auto-deletion.
4. **Relevance audit.** A cheap pass modelled on `--verify`: sample pages, ask "on-charter and
   substantive, or noise?" against the charter, flag the off-charter ones.
5. **Owner override via `notes.md`.** The owner writes "X is irrelevant" or "X belongs in
   KB-Y", and the agent honours it: down-rank, quarantine, or remove the page, and for misfiled
   material, flag the relocation for the owner to perform at the origin.

---

## 7. How it maps onto the current system

Most of the scaffolding exists:

- **`inbox/` + `sweep`**: the intake gate, the place to enforce `.ingestignore` and first-pass
  junk rejection.
- **`scan` + `manifest.tsv`**: fingerprints, so dedup is a small extension.
- **`coverage.tsv` value tiers**: where a `relevance` column joins `value` and read status.
- **`--map` pass**: the cheap triage point.
- **`pending.md`**: the human review surface.
- **`notes.md`**: the owner's correction and override channel.
- **`lint` (orphans)**: extends naturally to thin-page detection.
- **`--verify` + `qa.tsv`**: the model for a relevance audit.
- **`AGENTS.md`**: the home for the charter.

What is missing: the charter, the `.ingestignore`, the `relevance` signal and the map-pass
triage that writes it, the quarantine convention, and the audit.

---

## 8. Patterns it builds on

- **Defense in depth.** No single filter is trusted: cheap mechanical rejection, cheap metadata
  triage, a human gate, a post-read verdict, and a periodic audit each catch what the others
  miss. The same layering as the QA strategy (`docs/qa.md`).
- **Focused crawling.** A topic-budgeted web crawler scores links for on-topic-ness before
  fetching, to spend bandwidth where it pays. The map-pass triage is the same idea: score before
  the expensive read.
- **Triage and fail-safe classification.** As with the sensitivity classifier
  (`docs/routing.md`), a cheap stage gates expensive work and defaults to the safe side when
  unsure. Here "safe" means keep-and-park, not drop.

---

## 9. Phased plan

- **Phase 1 (cheap, deterministic).** The charter in `AGENTS.md`, `.ingestignore` honoured by
  `sweep`/`scan`, and dedup at scan. No LLM. Removes the obvious junk and gives relevance a
  reference.
- **Phase 2 (cheap LLM).** The `relevance` signal in the ledger, map-pass triage that parks
  off-charter/junk and routes `unsure` to `pending.md`, and the quarantine convention
  (frontmatter flag plus publish/index exclusion) with the lint thin-page check.
- **Phase 3 (audit).** The relevance audit pass and the `notes.md` override semantics.

All opt-in and fail-safe: with none of it, ingestion behaves as it does today.

---

## 10. Open decisions

- **Signal location.** A `relevance` column in `coverage.tsv` versus a sidecar like
  `sensitivity.tsv`. A column is simpler to read; a sidecar avoids collisions with
  `scan --refresh` (sensitivity chose the sidecar for that reason).
- **Quarantine mechanism.** A frontmatter flag (page stays in place, excluded by filters) versus
  a `wiki/_quarantine/` move (clear separation, but breaks inbound links). The flag is less
  disruptive; a move is more visible.
- **Auto-park threshold.** How confident the map pass must be to park without asking. Junk can
  auto-park; off-charter probably always routes to `pending.md` first.
- **Charter drift.** The charter will evolve. A re-classification needs to re-evaluate parked
  items against the new charter, the way `scan --refresh` re-opens read items.
- **Misfiled routing.** Whether the kit should know about sibling KBs to suggest a concrete
  destination, or just flag "belongs elsewhere" and leave the target to the owner.
