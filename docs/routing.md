# Sensitivity-aware model routing (design)

**Status: Phase 1 (deterministic classification) is built; routing is not. Opt-in.** This
captures the architecture so the decisions are recorded and the build is staged. As of now
`scripts/classify` tags coverage items and `stats` reports the breakdown; nothing routes on
the tag yet.

Most KBs will run every pass through one model and never touch this. It exists for KBs whose
sources contain regulated or private material that cannot leave the machine.

---

## 1. Motivation: data residency

Today every ingest and verify pass sends the raw source documents to the Claude API through
`claude -p`. For a tax return or a bank statement, the document's contents, including any
SIN or account number, are transmitted to a third party. Some clients (regulated, or simply
privacy-strict) cannot accept that.

This is a different control from the privacy hard rule, and the two are complementary:

- The **hard rule governs the output**: a SIN never lands in the wiki, whatever model ran.
- **Routing governs the input**: whether the raw sensitive document ever leaves the device.

Routing sensitive documents to a local model keeps the sensitive inputs on the machine while
still letting non-sensitive, hard reasoning use a frontier model for quality.

---

## 2. Two axes, and the rule that combines them

The decision has two inputs that are not symmetric:

- **Sensitivity is a hard boundary.** It picks the *allowed model pool*: local-only for
  sensitive material, anywhere for the rest. A violation is a data leak.
- **Difficulty (and value) is soft optimization.** Within the allowed pool, pick the
  cheapest model that is capable enough.

So the rule is **constrain, then optimize**: sensitivity selects the pool, difficulty selects
the model inside it.

The failure mode this framing exposes: a **false negative in classification** (a sensitive
document tagged "general" and sent to a frontier API) is the costly error, not a false
positive. So the classifier must **fail safe**: default to sensitive when unsure, and rely on
defense in depth rather than one guess.

---

## 3. Patterns it builds on

This is a combination of two established ideas, not a new one:

- **LLM routing and cascades** (the difficulty axis). FrugalGPT (Chen et al.) cascades from a
  cheap model to an expensive one and stops when the cheap one is confident. RouteLLM (Ong et
  al.) trains a router to send hard queries to the strong model and easy ones to the cheap
  model.
- **Data classification and policy-based routing** (the sensitivity axis), known in the
  governance world as DLP and data residency or data-boundary control. Classify the data,
  then a policy constrains where it may be processed.

The classification pass itself is a **cascade triage stage**: a cheap classifier gates the
expensive work. The escape hatch in section 6 is **PII redaction before an external call**,
also a standard pattern.

---

## 4. How it maps onto the current system

Much of the scaffolding is already here:

- **`privilege` tiers** (`default | business-sensitive | personal-sensitive`) are the
  sensitivity classification, but applied to *output pages*, not input documents.
- **`coverage.tsv`** is the per-document ledger where an input sensitivity tag can live.
- **`value` tier** is the difficulty and importance proxy.
- **`CLAUDE_BIN` and `CLAUDE_MODEL`** already make the model and binary swappable per run.

One distinction to keep straight: **page `privilege` is per output page; source sensitivity is
per input document.** They are related (a page's privilege is the most sensitive of the
documents it draws on), but they are keyed differently. Source sensitivity belongs in
`coverage.tsv` (one row per source document); page privilege stays in page frontmatter. The
first feeds the second.

What is missing: a pass that assigns input sensitivity early and cheaply, and routing logic
that reads it.

---

## 5. The classification pass

A cheap, fast pass that tags each `coverage.tsv` item with a sensitivity tier. It does not
ingest, and ideally does not read full documents.

- **Cheap signals first.** Path, filename, file type, size, and a deterministic PII or
  keyword scan (the same heuristics `lint` already uses: SIN-shaped numbers, `T4`, `payroll`,
  `passport`, `company key`). These are free and deterministic.
- **Cascade.** Run the deterministic heuristics first; call a small local model only for the
  ambiguous remainder. This keeps cost near zero and avoids a model call for the obvious
  cases.
- **Fail safe.** Default to sensitive when uncertain.
- **Output.** A `sensitivity` tier per row, written to `coverage.tsv`, reusing the privilege
  vocabulary (`default | business-sensitive | personal-sensitive`).

This stands on its own even before any routing exists: it pre-warns which documents are
sensitive, sharpens the QA risk-weighting, and is the prerequisite for routing. It also has
no local-model dependency, since the deterministic stage carries most of the load and the
optional model call is a single rating, not an agentic loop.

Built as `scripts/classify`: deterministic keyword matching over the coverage path and notes,
fail-safe floor (`CLASSIFY_FLOOR`, default `business-sensitive`), writing the sidecar ledger
`.ingest/sensitivity.tsv`. The small-model stage for ambiguous cases is a later refinement.

---

## 6. Routing (the second phase)

A KB-level config (a routing policy) maps:

- `sensitivity -> allowed pool` (for example, `personal-sensitive -> local-only`).
- `value or difficulty -> model` within that pool.

`ingest` and `verify` read each item's sensitivity and value, then pick `CLAUDE_BIN` and
`CLAUDE_MODEL` accordingly.

The hard case is **sensitive and hard**: constrained to local, but a local model may be too
weak. The escape hatch is **redact, then send**: strip the identifiers from the document and
send only the redacted version to the frontier model. Redaction reliability becomes a safety
control of its own, since a missed identifier is a leak, so it needs its own verification.

---

## 7. The real cost: the agentic runtime

Routing the *classification* call to a small local model is easy: it is a single rating
prompt. Routing the *ingest or verify* pass to a local model is much harder, because that
pass is an **agentic loop**: it reads files, writes wiki pages, and updates ledgers. That
loop currently assumes Claude Code's tool-use harness. A local model needs a comparable
agentic runtime (for example Ollama or llama.cpp with a tool-use harness), and small local
models are weaker at driving it.

So the split is clean:

- **Classification** has no local-runtime dependency. It can ship first.
- **Routing the agentic passes to local** is a real integration project, gated on a local
  runtime you trust for tool use.

---

## 8. Phased plan

- **Phase 0 (free, deterministic, already present).** `lint`'s PII and keyword scan already
  gives a fail-safe sensitivity signal with no model at all.
- **Phase 1 (cheap, no local dependency). Built.** `scripts/classify` tags each coverage
  item into the `.ingest/sensitivity.tsv` sidecar; `stats` reports the breakdown. Useful
  standalone; unblocks routing. The optional small-model stage for ambiguous items is still
  to come.
- **Phase 2 (needs a local runtime).** The routing config, model selection in
  `ingest`/`verify`, and the redaction escape hatch for sensitive-and-hard.

All of it opt-in through a KB config, off by default.

Recommendation: build Phase 1 first. It is independently useful and carries no local-model
dependency.

---

## 9. Open decisions

- **Tag location. Resolved (for now): a sidecar.** Phase 1 writes `.ingest/sensitivity.tsv`
  keyed per coverage item, rather than a `coverage.tsv` column, so it never collides with
  `scan --refresh` or the agent's row writes. A column could replace it later if a join
  proves awkward.
- **Classification granularity.** Per document, or per tight group as `coverage.tsv` already
  groups them.
- **Local model and harness** for Phase 2, and how much agentic capability it needs.
- **Redaction reliability and its verification**, since a missed identifier defeats the point.
- **Config format** for the routing policy.
