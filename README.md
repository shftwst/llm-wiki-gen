# llm-wiki-kit

A scaffolder for **LLM-maintained knowledge bases** — personal or team wikis that an LLM
agent reads into, writes, and keeps current. Based on Andrej Karpathy's **LLM Wiki**
pattern ([`docs/llm-wiki-pattern.md`](docs/llm-wiki-pattern.md)).

Point it anywhere and it stamps out a self-contained knowledge base: a source directory,
an LLM-owned wiki, a schema the agent follows, and an append-only log. Each generated KB
is its own git repo.

## Quickstart

```sh
./scripts/new-kb my-kb "My KB Title"
```

This creates `../my-kb/` (a sibling of the kit by default), substitutes the
name/title/date into the template, and runs `git init` with an initial commit. Then:

```sh
cd ../my-kb
# open in Claude Code; open wiki/ as an Obsidian vault
# drop sources into raw/ and ask the agent to ingest them
```

Pick a different location with a third argument:

```sh
./scripts/new-kb my-kb "My KB Title" /path/to/parent-dir
```

## What's in a generated KB

```
my-kb/
├── CLAUDE.md   # the schema the LLM follows (page conventions + workflows)
├── README.md   # human intro + Obsidian setup
├── inbox/      # shareable intake; sweep moves drops into raw/ (raw/ stays private)
├── raw/        # sources: files, directories, or symlinks to living docs
├── wiki/       # the LLM-owned wiki (Obsidian vault root)
│   ├── index.md
│   └── overview.md
├── scripts/    # sweep · scan · ingest · lint (QA) · stats (dashboard) · new-kb
├── .ingest/    # state: manifest · coverage (read frontier) · qa (verification) · cost · pending
└── log.md      # append-only ingest / re-ingest / query / lint / qa record
```

## Protected store + shared intake

`raw/` is the protected source of truth — you never share it. `inbox/` is a shareable
staging directory: contributors drop files there, and `scripts/sweep` **moves** each
into `raw/`. Because the sweep *moves* (not copies), a curated source leaves the shared
area entirely — contributors can't reach, alter, or delete the real `raw/` files. Share
only `inbox/` (e.g. a shared cloud folder); keep `raw/` and the KB root private.

## Mechanical ingest

Ingest never has to wait for you to remember it. `scripts/scan` fingerprints every
source — including the contents behind a living symlink — and diffs against a committed
baseline (`.ingest/manifest.tsv`) to find what's new, changed, or removed. It's a pure
script: no LLM, no cost. `scripts/ingest` runs the scan and, if anything changed,
ingests it via headless Claude Code, then advances the baseline and commits. Run it by
hand, or schedule it (`--auto`) with the cron/launchd snippets in `scripts/README.md`.

Ingestion is **progressive**: a cheap `--map` pass triages the corpus into a value-ranked
read frontier (`.ingest/coverage.tsv`), a default read pass reads the high-value documents
in full, and repeatable `--deepen` passes go further — an anytime, iterative-deepening loop
you stop whenever you like. Each KB ships an operator guide,
[`docs/deepening.md`](_template/docs/deepening.md), covering the deepening algorithm, the
coverage-vs-manifest ledger ownership, and a guardrailed human playbook.

## Trusting the wiki (QA)

A KB is only useful if you can act on it. QA is defense-in-depth: `scripts/lint` runs free
mechanical checks (citations, links, style, privacy); `scripts/ingest --verify` is an
adversarial pass that re-reads cited sources to confirm or flag claims, writing a
verification ledger (`.ingest/qa.tsv`); and `scripts/stats` reports coverage and
`% verified`. Effort is risk-weighted — value × uncertainty × stakes — so the target is
calibrated confidence per tier, not 100%. Full strategy and operator loop:
[`docs/qa.md`](_template/docs/qa.md).

## The pattern in one paragraph

Instead of RAG re-deriving knowledge on every query, the LLM **incrementally builds and
maintains a persistent wiki** between you and your raw sources. You curate sources and ask
questions; the LLM does the summarizing, cross-referencing, filing, and bookkeeping. The
wiki compounds — cross-references are already there, contradictions already flagged,
synthesis already current. Full write-up:
[`docs/llm-wiki-pattern.md`](docs/llm-wiki-pattern.md).

### Sources can be living

A KB's `raw/` accepts plain files, whole directories, and **symlinks to living documents**
(e.g. a shared-drive folder that stays organized at its source). Git stores the symlink,
not the target's contents, so the wiki references living sources without copying or owning
them — and the agent can **re-ingest** updates when they change.

## Customizing the template

Edit `_template/` to change what new KBs look like — especially
[`_template/CLAUDE.md`](_template/CLAUDE.md), which encodes the page conventions and the
ingest / re-ingest / query / lint workflows. Placeholders `{{KB_NAME}}`, `{{KB_TITLE}}`,
`{{DATE}}`, and `{{YEAR}}` are substituted at generation time.

## License

MIT — see [LICENSE](LICENSE).
