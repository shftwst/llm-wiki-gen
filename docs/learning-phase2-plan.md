# Learning from use, Phase 2a (usage-shaped prominence) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** What gets asked rises: an append-only `queries.tsv` page-hit log, a `stats` MOST QUERIED report, and agent-applied prominence in `index`/`overview`.

**Architecture:** Every answered query appends `date⇥page` rows to `.ingest/queries.tsv` (identifiers only). `stats` aggregates it to counts (deterministic, no LLM). The agent orders `index.md`/`overview.md` by those counts when it regenerates them during ingest — scripts never write `wiki/`.

**Tech Stack:** Bash (the `_template/scripts/` idiom), `awk` aggregation, headless Claude Code for the agent behaviours. No test framework; deterministic pieces checked with shell assertions against a scratch KB, agent behaviour by a human smoke run.

## Global Constraints

- `.ingest/queries.tsv` is **identifiers only** (`date⇥page`), append-only, aggregated at read time. No question text, ever.
- **Every answered query logs page-hits** (durable, lookup, or partial) — one row per wiki page the answer drew on. An unanswerable question logs nothing. This is the opposite of the Phase 1 `log.md` rule (file-only), on purpose.
- **Scripts never write `wiki/`.** Prominence reaches `index.md`/`overview.md` only through the agent, applied when it regenerates them during ingest.
- Prominence is a **soft** ordering layered on the catalog (most-asked first within a category; ties keep existing order); it never changes a page's privilege or deletes anything.
- `stats` edits keep the existing `set -eu` (no pipefail) idiom and the `have()`/`awk` patterns already in the file.
- All prose obeys `STYLE.md` (no banned vocab, straight quotes, em-dashes sparse, sentence-case headings). Exception: literal ledger-header and `stats` "(none yet — …)" strings keep the em-dash to match the kit's existing `cost.tsv`/`stats` conventions.
- Edits target `_template/`. The generated `1-knowledge-layer/shftwst-ops-kb` is synced only in Task 5.
- Spec: `docs/learning-phase2.md`. Rationale: `docs/learning.md` §6.

---

### Task 1: `scripts/stats` MOST QUERIED + ship the `queries.tsv` ledger

**Files:**
- Create: `_template/.ingest/queries.tsv`
- Modify: `_template/scripts/stats` (var decls ~12-21; new section before the `# --- cost` block at ~146)
- Test bed: a scratch KB at `../wiki-gen-smoke`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: a `MOST QUERIED (.ingest/queries.tsv)` section; the template ledger every KB ships. Later tasks (the agent logging in Task 2) write rows this reads.

- [ ] **Step 1: Write the failing test**

```bash
# from the kit root (parent of _template/)
setup_smoke() {
  [ -d ../wiki-gen-smoke ] || ./scripts/new-kb wiki-gen-smoke "Smoke" >/dev/null 2>&1
}
test_stats_queries() {
  setup_smoke
  cp _template/scripts/stats ../wiki-gen-smoke/scripts/stats
  # populated fixture (TAB-separated)
  printf '# queries.tsv\n# Columns: date\tpage\n2026-06-10\tclient-rates\n2026-06-12\tclient-rates\n2026-06-15\thumans-not-robots\n2026-06-15\tclient-rates\n' > ../wiki-gen-smoke/.ingest/queries.tsv
  out="$(../wiki-gen-smoke/scripts/stats 2>&1 || true)"
  echo "$out" | grep -qE 'logged +4 page-hit\(s\) across 2 page\(s\)' || { echo "FAIL: totals line wrong"; echo "$out" | grep -i logged; return 1; }
  echo "$out" | grep -qE '3 +client-rates +\(last asked 2026-06-15\)' || { echo "FAIL: top page wrong"; echo "$out" | grep -i client-rates; return 1; }
  # empty (header-only) fixture -> (none yet ...)
  printf '# queries.tsv\n# Columns: date\tpage\n' > ../wiki-gen-smoke/.ingest/queries.tsv
  out="$(../wiki-gen-smoke/scripts/stats 2>&1 || true)"
  echo "$out" | grep -q 'none yet' || { echo "FAIL: empty case missing"; return 1; }
  echo PASS
}
test_stats_queries
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash -c "$(declare -f setup_smoke test_stats_queries); test_stats_queries"`
Expected: `FAIL: totals line wrong` (no MOST QUERIED section yet).

- [ ] **Step 3: Create the template ledger**

Create `_template/.ingest/queries.tsv` with exactly two header lines (a real TAB between `date` and `page` on the Columns line, no data rows):

```
# queries.tsv — per-query page-hit log (appended by the agent on every answered query).
# Columns: date	page   (page = the wiki slug the answer drew on; identifiers only, no query text)
```

- [ ] **Step 4: Add the `QUERIES` var and the MOST QUERIED section to `stats`**

In `_template/scripts/stats`, after the `COST="$KB_DIR/.ingest/cost.tsv"` line, add:

```bash
QUERIES="$KB_DIR/.ingest/queries.tsv"
```

Then, immediately before the `# --- cost ----` comment block, insert:

```bash
# --- queries (prominence signal) --------------------------------------------
printf '\nMOST QUERIED (.ingest/queries.tsv)\n'; rule
if have "$QUERIES"; then
  awk -F'\t' '$1 ~ /^#/ || $1=="" {next}
    {n++; c[$2]++; if($1>last[$2]) last[$2]=$1}
    END{ np=0; for(p in c) np++
         printf "  logged         %d page-hit(s) across %d page(s)\n", n, np }' "$QUERIES"
  printf '  most queried:\n'
  awk -F'\t' '$1 ~ /^#/ || $1=="" {next}
    {c[$2]++; if($1>last[$2]) last[$2]=$1}
    END{ for(p in c) printf "%d\t%s\t%s\n", c[p], p, last[p] }' "$QUERIES" \
    | sort -rn | head -10 \
    | awk -F'\t' '{printf "    %4d  %-28s (last asked %s)\n", $1, $2, $3}'
else
  printf '  (none yet — answered queries log page hits here)\n'
fi

```

(ISO dates compare correctly as strings, so `$1>last[$2]` tracks the latest. The pipeline runs under `set -eu` without pipefail, so `head` closing `sort` early is harmless.)

- [ ] **Step 5: Run the test to verify it passes**

Run: `cp _template/scripts/stats ../wiki-gen-smoke/scripts/stats && bash -c "$(declare -f setup_smoke test_stats_queries); test_stats_queries"`
Expected: `PASS`. Also `bash -n _template/scripts/stats`.

- [ ] **Step 6: Commit**

```bash
git add _template/scripts/stats _template/.ingest/queries.tsv
git commit -m "feat(stats): MOST QUERIED report; ship the queries.tsv ledger"
```

---

### Task 2: `AGENTS.md` — log page-hits and apply prominence

**Files:**
- Modify: `_template/AGENTS.md` (Query section ~371-394; Navigation files ~275-277)

**Interfaces:**
- Consumes: the `queries.tsv` ledger and `stats` MOST QUERIED from Task 1.
- Produces: the agent behaviour that writes `queries.tsv` rows and orders `index`/`overview` by them.

- [ ] **Step 1: Add the page-hit logging step to the Query workflow**

In `_template/AGENTS.md`, the `### Query` section ends with step 6:

```markdown
6. When you filed or updated a page, append a `query` entry to `log.md` naming what was
   created or merged and any `> [!review]` raised. A lookup or an unanswered question writes no
   page and no log entry.
```

Insert step 7 immediately after it:

```markdown
7. For **every** answered query (durable, lookup, or partial), append one `date<TAB>page` row to
   `.ingest/queries.tsv` for each wiki page the answer drew on, page slugs only, never the
   question text. This is the usage signal that shapes prominence, so it runs even when nothing
   is filed. An unanswerable question (no pages used) appends nothing.
```

- [ ] **Step 2: Extend the index/overview navigation paragraph for prominence**

The `## Navigation files` section opens with:

```markdown
**`wiki/index.md`: content catalog.** Every wiki page listed with a `[[link]]` and a
one-line summary, grouped by category. Update it on every ingest/re-ingest. When
answering a query, read the index first to find relevant pages, then drill in.
```

Replace that paragraph with:

```markdown
**`wiki/index.md`: content catalog.** Every wiki page listed with a `[[link]]` and a
one-line summary, grouped by category. Update it on every ingest/re-ingest. When
answering a query, read the index first to find relevant pages, then drill in. Order pages
within each category by how often they are asked about (the per-page hit count in
`.ingest/queries.tsv`, most-asked first; ties keep their existing order). On `wiki/overview.md`,
keep a short **Most asked about** section listing the top few pages by that count, so the home
page leads with what people actually use. Prominence is a soft signal on top of the catalog, not
a reordering of the underlying pages or their privilege.
```

- [ ] **Step 3: Verify no style regressions and the edits landed**

Run from `_template/`:
```bash
./scripts/lint 2>&1 | grep -E 'AGENTS\.md' || echo "no AGENTS.md style warnings — good"
grep -q 'append one `date<TAB>page` row' AGENTS.md && grep -q 'Most asked about' AGENTS.md && echo "edits landed"
```
Expected: `no AGENTS.md style warnings — good` and `edits landed`.

- [ ] **Step 4: Commit**

```bash
git add _template/AGENTS.md
git commit -m "feat(query): log page-hits to queries.tsv; order index/overview by query frequency"
```

---

### Task 3: `scripts/query` — prompt reminder to log hits

**Files:**
- Modify: `_template/scripts/query` (the `PROMPT` string, ~line 53)

**Interfaces:**
- Consumes: the Query workflow from Task 2 (this only reinforces it for headless runs).
- Produces: no new behaviour; a one-clause prompt addition.

- [ ] **Step 1: Add the clause**

In `_template/scripts/query`, the `PROMPT` currently ends (before the blank line and `Question: $QUESTION`):

```
Do NOT edit raw/, .ingest/manifest.tsv, or .ingest/coverage.tsv; do NOT git commit — the wrapper commits.
```

Replace that sentence with:

```
Do NOT edit raw/, .ingest/manifest.tsv, or .ingest/coverage.tsv; do NOT git commit — the wrapper commits. Also log the wiki pages your answer used to .ingest/queries.tsv per the Query workflow (page slugs and a date only).
```

- [ ] **Step 2: Verify the edit landed and the script still parses**

Run from `_template/`:
```bash
grep -q 'log the wiki pages your answer used to .ingest/queries.tsv' scripts/query && echo "clause present"
bash -n scripts/query && echo "syntax ok"
./scripts/query --dry-run "smoke" | grep -q 'dry-run' && echo "dry-run ok"
```
Expected: `clause present`, `syntax ok`, `dry-run ok`.

- [ ] **Step 3: Commit**

```bash
git add _template/scripts/query
git commit -m "feat(query): remind the headless prompt to log page-hits to queries.tsv"
```

---

### Task 4: Documentation

**Files:**
- Modify: `_template/scripts/README.md` (the `stats` section)
- Modify: `docs/learning.md` (status of §6)

**Interfaces:**
- Consumes: the finished behaviour.
- Produces: operator docs; no code.

- [ ] **Step 1: Note MOST QUERIED + queries.tsv in the `stats` operator section**

In `_template/scripts/README.md`, the `## \`stats\`: ingestion summary` section lists what `stats` reports. Append one sentence to that section's prose:

```markdown
It also reports **MOST QUERIED** pages, aggregated from `.ingest/queries.tsv` (an append-only
page-hit log the agent writes on every answered query, slugs and dates only), so you can see what
the wiki is actually used for. See `../docs/learning.md` §6.
```

- [ ] **Step 2: Flip the §6 status in `docs/learning.md`**

In `docs/learning.md`, the Phase 2 line in the §9 phased plan reads:

```markdown
- **Phase 2 (depth and prominence from use).** Query-miss detection against `coverage.tsv` with an
  opt-in targeted read to answer now and a promotion for the next batch; `.ingest/queries.tsv` and
  the deterministic prominence ranking in `index` and `overview`.
```

Replace it with:

```markdown
- **Phase 2a (prominence from use). Built.** `.ingest/queries.tsv` (an append-only page-hit log),
  the `stats` MOST QUERIED report, and agent-applied prominence ordering in `index` and
  `overview`. See `learning-phase2.md`.
- **Phase 2b (query-driven depth).** Query-miss detection against `coverage.tsv` with an opt-in
  targeted read to answer now and a promotion for the next batch. Not built.
```

- [ ] **Step 3: Verify docs style**

Run from `_template/`: `./scripts/lint 2>&1 | grep -E 'scripts/README' || echo "no scripts/README style warnings"`
Expected: `no scripts/README style warnings`. Eyeball: no new em-dashes/banned words.

- [ ] **Step 4: Commit**

```bash
git add _template/scripts/README.md docs/learning.md
git commit -m "docs(query): document MOST QUERIED / queries.tsv; mark Phase 2a built"
```

---

### Task 5: Smoke-test prep on `shftwst-ops-kb` and hand off

**Files:**
- Modify (sync): `1-knowledge-layer/shftwst-ops-kb/scripts/{stats,query}` and `1-knowledge-layer/shftwst-ops-kb/.ingest/queries.tsv` (create if absent)
- Modify (targeted): `1-knowledge-layer/shftwst-ops-kb/AGENTS.md` (apply the Task 2 edits)

**Interfaces:**
- Consumes: every prior task.
- Produces: a live, human-watched acceptance run. The agent prepares; the human runs and judges.

- [ ] **Step 1: Sync into the generated KB**

Work from `/Users/shftwst/workspace/shftwst/pinky`:
```bash
cp llm-wiki-gen/_template/scripts/stats llm-wiki-gen/_template/scripts/query \
   1-knowledge-layer/shftwst-ops-kb/scripts/
[ -f 1-knowledge-layer/shftwst-ops-kb/.ingest/queries.tsv ] \
  || cp llm-wiki-gen/_template/.ingest/queries.tsv 1-knowledge-layer/shftwst-ops-kb/.ingest/queries.tsv
```

- [ ] **Step 2: Apply the Task 2 AGENTS.md edits to the ops KB**

Apply the same two edits from Task 2 (the Query step 7 and the Navigation prominence paragraph) to `1-knowledge-layer/shftwst-ops-kb/AGENTS.md`. The anchors match (it was generated from the same template, and its Phase 1 Query section is identical). Touch only those two spots; leave its charter alone. Verify:
```bash
grep -q 'Most asked about' 1-knowledge-layer/shftwst-ops-kb/AGENTS.md && echo "ops KB updated"
```

- [ ] **Step 3: Deterministic pre-check in the ops KB**

```bash
cd 1-knowledge-layer/shftwst-ops-kb
./scripts/stats | grep -A4 'MOST QUERIED'   # prints the section ((none yet ...) until queries run)
./scripts/query --dry-run "smoke"            # dry-run banner, no changes
cd -
```
Expected: a MOST QUERIED section (likely `(none yet ...)`); the dry-run banner.

- [ ] **Step 4: Hand off the live run to the human (acceptance)**

Run by the user (paid LLM calls):

```bash
cd 1-knowledge-layer/shftwst-ops-kb
# ask a few questions
./scripts/query "what is our day rate history with Humans Not Robots?"
./scripts/query "which clients are outside IR35?"
# expect: .ingest/queries.tsv gained a row per wiki page each answer used (slugs only)
cat .ingest/queries.tsv
# the live view
./scripts/stats | grep -A6 'MOST QUERIED'
# after a normal ingest, index/overview reflect prominence (most-asked first; "Most asked about" on home)
./scripts/ingest --deepen --watch   # or any ingest that regenerates index/overview
```

Acceptance: `queries.tsv` gains slug rows (no question text); `stats` MOST QUERIED ranks them; after an ingest, `index.md` ordering and `overview.md` "Most asked about" reflect the hits. If the agent logs question text, or a script wrote into `wiki/`, that is a defect — fix the wording in `AGENTS.md` (Task 2), no script change.

- [ ] **Step 5: Commit the ops-KB sync (after the human is satisfied)**

```bash
cd 1-knowledge-layer/shftwst-ops-kb
git add -A && git commit -m "chore: adopt Phase 2a query prominence (scripts + AGENTS.md + queries.tsv)"
cd -
```

---

## Cleanup

After acceptance, remove the scratch KB: `rm -rf ../wiki-gen-smoke`.

## Notes for the implementer

- The `queries.tsv` logging and the prominence ordering are LLM behaviours defined in `AGENTS.md`; their only real test is the Task 5 smoke run. The shell checks in Tasks 2-3 confirm the edits are present and the script parses.
- Keep the `stats` MOST QUERIED block read-only and `set -eu`-safe — match the existing SENSITIVITY/RELEVANCE/COST sections exactly in idiom.
