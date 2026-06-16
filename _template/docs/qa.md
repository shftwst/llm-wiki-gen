# QA: keeping the wiki trustworthy

How to know the wiki is right enough to act on, what defends each way it can be wrong, and
the human loop that calibrates trust without re-reading everything.

---

## 1. Why QA here is unusual

Normal QA checks software against a spec you can run. Here the artifact is a knowledge base
an LLM wrote from documents, and verifying its accuracy means re-reading those documents,
which is the exact work the system exists to automate. You cannot re-verify everything
without defeating the purpose. So the whole job is: **spend scarce verification effort
where it matters most, and make the rest cheap to spot-check.**

Two design choices already make that possible:

- **Provenance.** Every page ends with `## Sources` linking the real files. "Is the wiki
  right?" (unanswerable) becomes "is this claim supported by this document?" (one click).
- **Honesty.** Pages mark each source `read in full` or `not read`, and the agent flags its
  own doubts with `> [!review]`. The wiki tells you where to be skeptical.

---

## 2. Failure modes and what guards them

| Failure | Guarded by | Residual risk |
|---|---|---|
| Hallucination / misread a document | read/not-read tags, `[!review]`, the verify pass | the main one, needs verification |
| Inference stated as fact (from folder names) | "never assert from structure", not-read tags, `lint` | medium |
| Stale data (source changed, wiki did not) | freshness: `scan --refresh`, the `stale` frontier | low |
| Omission / coverage gaps | the coverage frontier, `stats` | medium, but visible |
| Privacy leak (identifiers, credentials) | the hard rule, `privilege` tiers, `lint` heuristics | low |
| Internal contradiction | the Lint workflow | medium |
| Broken provenance | the `## Sources` convention, `lint` | low |
| AI-writing tells | `STYLE.md`, `lint` | low |

The big residual is **factual accuracy**: did the agent read the document correctly. Only
re-reading the source catches that, which is what the verify pass does.

---

## 3. Defense in depth

Cheapest first; each layer catches a class the one below cannot.

1. **`scripts/lint`**: mechanical, no LLM, run every time. Frontmatter validity, missing
   `## Sources`, all-`not read` pages, dangling links, orphans, stale derived pages, style
   tells, privacy heuristics. Catches structural and surface defects for free.
2. **Consistency**: an LLM read of the wiki *only* (no source re-read), looking for
   cross-page contradictions and derived pages out of step with their sources. Folded into
   the Lint workflow. Cheaper than verification because it reads no PDFs.
3. **`ingest --verify`**: the accuracy layer. A separate, adversarial auditor re-reads the
   cited sources and confirms or refutes claims. Sampled and risk-weighted, so it is
   affordable. This is the only layer that catches hallucination.
4. **Human + `notes.md`**: you spot-check what the verifier flagged or what matters most;
   the provenance links make this near-free. Corrections go into `notes.md` and stick.

A principle runs through 2 to 4: **independent, adversarial verification beats self-review.**
The agent that wrote a page is the worst judge of it. The verify pass is a different role
with a "try to refute this claim" prompt, defaulting to unsupported when it cannot confirm.

---

## 4. Risk-weighting: where to spend

Not all pages deserve equal scrutiny. Verify where the expected loss is highest:

```
priority ≈ value × (1 − confidence) × stakes
```

The system already carries every term:

- **value**: the source's value tier in `coverage.tsv` (importance).
- **confidence**: read vs not-read, and any open `[!review]`.
- **stakes**: the page's `privilege` tier (personal-sensitive and business-sensitive cost
  more if wrong).

So a high-value, inferred, personal-sensitive page you make decisions on is audited first;
a low-value read receipt is trusted. The verify pass samples in that order.

---

## 5. The two ledgers in QA

QA reads from two agent-owned ledgers, each answering a different question:

- **`.ingest/coverage.tsv`**: *how deeply has each source been read, and is it current?*
  (`unread | partial | read | stale`). This is the **confidence** signal.
- **`.ingest/qa.tsv`**: *has each wiki page been audited against its sources?*
  (`verified | flagged | unverified`, with claims checked vs supported). This is the
  **verification** signal, keyed by wiki page.

Keeping verification state in a ledger (not in page frontmatter) means `stats` reports
`% verified` from one file instead of parsing every page. A `verified: <date>` line on the
page is an optional courtesy for a reader; the ledger is authoritative.

---

## 6. Operator's QA playbook

You decide how much to trust the wiki and how much to spend confirming it.

### The loop

1. **`./scripts/lint`**: free. Fix or note anything it flags before trusting a pass. Re-run
   until errors are zero; read the warnings.
2. **`./scripts/stats`**: see coverage and, once you have verified, `% verified`. Decide
   what is under-verified relative to its stakes.
3. **`./scripts/ingest --verify --sample N --watch`**: audit the highest-risk pages.
   Watch the stream; the auditor re-reads sources and flags unsupported claims.
4. **Review the flags.** Each `flagged` page now carries a `> [!review]` naming what failed.
   Open the cited source via its `## Sources` link and judge. A real error goes into
   `notes.md` as a correction (cited "per owner"); a re-ingest then fixes the page.
5. **Repeat** on the next risk tier, or after a deepen/refresh adds material.

### Guardrails

- **Cost is dialed**: `--sample N` and `--budget $N` per pass; `stats` shows verify spend
  as its own `mode=verify` line in the cost ledger.
- **QA never mutates sources or coverage**: the verify pass does not sweep, ingest, or
  advance the manifest. The worst it does is add a `[!review]` and a `qa.tsv` row.
- **Everything is git**: every pass is a commit; revert any you dislike.
- **Honesty is enforced**: the auditor defaults to unsupported, so silence reads as doubt,
  not approval.

---

## 7. Calibrated confidence, not 100%

You can never reach fully-verified without re-reading the whole corpus, which is the cost
the system exists to avoid. The realistic target is a **known confidence per tier**:
"every personal-sensitive page verified; high-value claims sampled at N with 92% supported;
low-value pages trusted." `stats` plus `qa.tsv` give you that number, so you know exactly
how much to trust each part of the wiki before you act on it.
