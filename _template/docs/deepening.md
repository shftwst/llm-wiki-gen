# Deepening a knowledge base — ledgers, algorithm, and operator playbook

How a KB gets filled in *progressively* — shallow first, then deeper in bounded passes —
what bookkeeping makes that safe, and how you (the human driver) run it without surprises.

---

## 1. Two ledgers, two owners

Two small files under `.ingest/` track state. They are deliberately separate: they answer
different questions and have different owners.

### `manifest.tsv` — *has the source changed?* (script-owned)

- Columns: `source_path · kind · fingerprint · last_ingested`.
- Owned by **`scripts/scan.sh`**. The agent never touches it.
- `scan.sh` fingerprints each source (following living symlinks) and diffs against this
  baseline to classify **new / changed / removed**. `ingest` advances it
  (`scan.sh --accept`) only after a successful pass.
- It is about **change detection** — mechanical, content-hash based. A script can compute
  it; no judgment required.

### `coverage.tsv` — *how deeply have we read it?* (agent-owned)

- Columns: `item · value · status · pass · last_read`.
- Owned by **the agent (LLM)**. The wrapper never edits it.
- One row per document or tight group: a value tier (`high|med|low`) and a read status
  (`unread|partial|read`). It is the **frontier** the deepening loop consumes.
- It is about **read depth** — semantic. Only the agent that read a document knows whether
  it read it *in full*, so only the agent can maintain it.

### Why they're split

The system's rule everywhere: **one fact, one owner.**

- "Did the bytes change?" is mechanical → a script → `manifest.tsv`.
- "Did we actually understand it?" is semantic → the agent → `coverage.tsv`.

Keeping read-state in its own file (not scattered across wiki pages) means the frontier is
one greppable file, not something you reconstruct by parsing every page. The wiki's
`## Sources` sections still cite documents for the reader — that's a *finding-aid*, not the
source of truth.

| | `manifest.tsv` | `coverage.tsv` |
|---|---|---|
| Question | has the source changed? | how deeply have we read it? |
| Owner | `scan.sh` (script) | the agent |
| Basis | content fingerprint | semantic judgment |
| Drives | re-ingest detection | progressive deepening |

---

## 2. The deepening model (the algorithm)

Reading a large corpus in one pass is expensive and all-or-nothing. Instead the KB is
filled the way search algorithms explore a big tree: **shallow first, then progressively
deeper, stopping whenever you like.** The named ideas it borrows:

- **Iterative deepening** — a shallow pass, then deeper passes; a usable result early,
  refined over time. The `--map` → read → `--deepen` passes are exactly this. Unlike
  textbook iterative deepening (which *restarts* each pass), read-state is **memoized** in
  `coverage.tsv`, so no document is read twice — you *resume*, not restart.
- **Anytime algorithm** — always holds a valid answer that only improves, interruptible at
  any point. After Pass 0 the wiki is usable; every pass improves it; stop when it's good
  enough or the budget's spent.
- **Value of Information (VoI)** — spend the next dollar where it buys the most. The
  frontier is value-ordered (`notes.md` priorities first, then a document-type heuristic),
  so deepening always reads the most valuable unread item next.
- **Cascade / coarse-to-fine** — a cheap stage triages; the expensive stage runs only where
  it's worth it. `--map` is the cheap triage that decides what earns a full read.

### The three passes

- **Pass 0 — `--map`** (cheap): walk the corpus, build the skeleton, and enumerate every
  document into `coverage.tsv` with a value tier. Nothing read in full; everything
  `unread`. This is the triage.
- **Pass 1 — read** (default): read the **high-value** unread documents in full, extract
  facts, upgrade pages from inferred to cited, derive `analysis/` pages. Mark them `read`.
- **Passes 2…n — `--deepen`** (repeatable): read the next highest-value `unread` items,
  upgrade, mark `read`. Repeat until the frontier is empty or you stop.

Each pass commits, records cost in `.ingest/cost.tsv`, and leaves the wiki consistent.

---

## 3. Operator's playbook — deepening within guardrails

You are the driver. The agent does the reading and writing; you steer *what* gets deepened,
cap *how much* you spend, and you *catch errors*.

### Before you start

- **Run where `raw/` resolves** — your real machine, not a container. Sanity check:
  `find -L raw/<source> -type f | wc -l` should be greater than `0`.
- **Seed `notes.md`** with priorities and known facts/corrections — e.g. "go deep on
  finances and contracts; skip recordings", "payroll tax does not apply". The agent reads it first,
  treats it as authoritative ("per owner"), and it drives the value ordering.

### The loop

1. **Map first** — `./scripts/ingest --map --watch`. Cheap. Then **read
   `.ingest/coverage.tsv`**: are the value tiers sane? Re-tier anything mis-ranked (it's a
   plain TSV) or add priorities to `notes.md` and re-map.
2. **Read pass** — `./scripts/ingest --watch`. Reads the high-value docs. Watch the
   stream; **Ctrl-C if it goes wrong** — a cancelled run won't advance the baseline.
3. **Review** — open the wiki. Check the new `analysis/` pages and the `[!review]` flags.
   Wrong fact? Add a correction to `notes.md`. Spot-check a few *un-flagged* confident
   claims against the cited originals (each page's `## Sources` links them).
4. **Deepen in bounded passes** — `./scripts/ingest --deepen --budget 5 --watch`.
   Repeat. Each pass reads the next-most-valuable unread items. **Check `.ingest/cost.tsv`**
   between passes; stop when the marginal pages aren't worth the marginal dollars.

### Guardrails (what protects you)

- **Cost is dialed, not gambled** — `--budget $N` per pass, and you choose how many passes.
  `cost.tsv` keeps a running total. Depth is incremental, never all-or-nothing.
- **`--watch` + cancel** — see every step live; Ctrl-C aborts. Cancelled or no-op runs do
  **not** advance the baseline (the guard checks that `wiki/`, `log.md`, or `coverage.tsv`
  actually changed).
- **`--dry-run`** — preview exactly what a pass would run, with no spend.
- **`notes.md` is your override** — correct a wrong fact once; it sticks across re-ingests
  and is cited "per owner".
- **`raw/` is read-only** — the agent can never alter or delete your sources; the worst a
  bad pass does is write a wiki page you can fix.
- **Everything is git** — every pass is a commit. A pass you dislike is one `git revert`
  away.
- **Honesty is enforced** — pages cite their sources and mark `read` vs `not read`;
  `coverage.tsv` shows exactly what's been read. You can always see what the wiki *knows*
  vs. what it's *inferring*.

### When to stop

The wiki is an **anytime** artifact — useful after Pass 0, better after each pass. Stop
when the remaining `unread` items are all low-value, the last deepen pass added little, or
the cost-per-new-insight stops being worth it. You can resume later; the frontier persists.
