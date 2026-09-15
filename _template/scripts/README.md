# scripts/: mechanical ingest

These ship inside the KB so it stays self-contained and splittable. Detection is a pure
script (no LLM, no cost); the actual ingest invokes Claude Code headlessly.

> **Run these where `raw/` actually resolves, your real machine, not a container or
> remote sandbox.** Sources are often symlinks to local mounts (shared drives, OneDrive,
> etc.). Inside a container those symlinks are broken, so a scan there fingerprints
> *emptiness* and an ingest captures nothing. Sanity check: if
> `find -L raw/<source> -type f | wc -l` is `0` for a source you know has files, the mount
> isn't present, you're in the wrong place.

## Schema config (`.schema/`)

Two TSVs define this KB's vocabularies; edit them to fit your domain (the scripts read them
through `scripts/kblib.sh`):

- **`.schema/page-types.tsv`** — the `type:` values (`type · class · dir · note`). `class` is
  `content` (needs `## Sources`, prose is subject-only, carries a privilege tier), `source`
  (provenance is the page's subject), or `nav` (catalog/home pages, skipped when publishing).
  `lint` validates every page's `type` against this list.
- **`.schema/privilege-tiers.tsv`** — the `privilege:` ladder (`tier · rank · classify · note`),
  ordered least to most sensitive. `lint` validates `privilege`; `classify` maps its keyword
  buckets to the tiers marked `business` / `personal`; `.publish/roles.tsv` grants each role a
  subset of these tiers.

## `guard-raw`: protect `raw/` from edits (PreToolUse hook)

`raw/` is read-only to the agent. `AGENTS.md` says so; `scripts/guard-raw` makes it a lock.
Registered as a Claude Code **PreToolUse hook** in `.claude/settings.json`, it blocks any tool
action that would edit, delete, move, create, or change permissions under `raw/`, including
writes that resolve through a `raw/` symlink into the living source, and `Bash` commands such as
`rm` / `mv` / `chmod` or redirects into `raw/`. Reads pass (including a read that hydrates a cloud
placeholder). The hook exits `2` to block, so it holds even under `--permission-mode acceptEdits`
and `bypassPermissions` (that is, `ingest --auto`). It needs `python3` and fails closed if absent.
Being session-scoped it also covers **subagents** (the agent's Task-tool children), and it locates the
KB by marker (`raw/` beside `AGENTS.md`), so it holds even when a subagent runs in another directory.

Verify it on your machine (should print a BLOCK message and exit 2):

```sh
echo '{"tool_name":"Write","tool_input":{"file_path":"raw/x"},"cwd":"'"$PWD"'"}' \
  | CLAUDE_PROJECT_DIR="$PWD" ./scripts/guard-raw; echo "exit $?"
```

The hook is the in-tool guard. For a hard OS-level guarantee, mount the living source read-only,
or run ingest as a user without write access to `raw/` and its symlink targets.

## `sweep`: move staged intake into the protected store

`raw/` is the protected source store you never share. `sweep` **moves** items into it from
two staging areas and commits the move, so once curated a source leaves the staging area and
contributors can't alter or delete it.

- **`inbox/`** — the shareable drop folder. Every item is swept.
- **`capture/`** — the access layer's ingress queue (phone uploads, agent submits), shared
  across KBs and living beside them rather than inside one. Only items whose sidecar
  `capture/.meta/<id>.json` records `"promoted": {"kb": "<this KB>"}` are swept. Anything
  unpromoted, or promoted to another KB, is left alone.

```sh
./scripts/sweep            # move inbox/* and promoted capture items → raw/, then commit
./scripts/sweep --dry-run  # show what would move; move nothing
```

Promotion is a recorded decision rather than a move because the server that receives captures
is deliberately given no write access to any KB. Sweep, which already holds write access to
`raw/`, is what acts on the decision. A missing or unreadable sidecar reads as "not promoted",
so the failure direction is always "stays in the queue". After a move the sidecar is retired
to `capture/.done/`, which keeps the provenance next to the decision and stops a re-run
reconsidering it. Reading promotions needs `jq`; without it sweep does `inbox/` and says so.

It runs automatically as the first step of `ingest` (disable with `--no-sweep`).
Name collisions never overwrite a `raw/` source, the incoming item is timestamp-suffixed.
Non-empty `.ingestignore` matches move to `junk/`. A zero-byte file, or a directory containing one, is left in place and flagged instead of moved, since it may be a real download still in flight that a move would lose.

`PINKY_CAPTURE_DIR` overrides the queue location (default: `capture/` beside the KB).

## `lint`: mechanical QA

Structural, style, and privacy checks over `wiki/`. No LLM, no cost.

```sh
./scripts/lint          # full report; exit 0 if no errors, 1 otherwise
./scripts/lint --quiet  # errors + summary only
```

Checks: frontmatter completeness and valid enums (errors); missing `## Sources` and
all-`not read` pages; dangling `[[links]]` and orphan pages; stale derived pages
(`derived_from` page newer than `as_of`); style tells (banned vocabulary, curly quotes,
em-dash overuse); privacy heuristics (SIN-shaped numbers, credential keywords); and **docs
style** (the same tells across `AGENTS.md`, `CLAUDE.md`, `README`, and `docs/`, since `STYLE.md` governs
docs too). It is the cheap pre-check; the LLM Lint workflow and the verify pass go deeper.

## `stats`: ingestion summary

A read-only dashboard over the state ledgers and `wiki/`. No LLM, no cost.

```sh
./scripts/stats          # sources, coverage (read/partial/unread/stale), wiki pages, cost
./scripts/stats --check  # also resolve each coverage path on disk (flags missing/unreadable)
```

Reports: documents by read status and value tier, the remaining frontier, read-vs-not-read
counts with not-read reasons (timed-out = unreadable this pass), wiki pages by type and
privilege tier, open `[!review]` flags, sensitivity counts, and total cost broken down by
pass mode and model.

It also reports **MOST QUERIED** pages, aggregated from `.ingest/queries.tsv` (an append-only
page-hit log the agent writes on every answered query, slugs and dates only), so you can see what
the wiki is actually used for. See `../docs/learning.md` §6.

It also reports **DEMANDED** sources from `.ingest/demand.tsv` (documents a query needed but had
not read yet, shown with their current coverage status), so you can see what to ingest next; the
read/deepen passes read demanded-but-unread sources first. See `../docs/learning.md` §7.

## `classify`: estimate sensitivity

Tags each coverage item with a sensitivity tier (`default | business-sensitive |
personal-sensitive`) from path and keyword heuristics. No LLM, no cost, never reads document
contents. Tiers come from `.schema/privilege-tiers.tsv` (the keyword buckets map to whichever tiers
are marked `business` / `personal`). Fail-safe: an unmatched item falls to a conservative floor
(`CLASSIFY_FLOOR`, default = the `business`-bucket tier). Writes `.ingest/sensitivity.tsv`.

```sh
./scripts/classify            # classify all coverage items
./scripts/classify --dry-run  # print the classification; write nothing
CLASSIFY_FLOOR=default ./scripts/classify   # change the fail-safe floor
```

This is Phase 1 of the sensitivity-aware routing design ([`docs/routing.md`] in the kit). Run
it after `--map` populates the frontier. Model routing still does not read the tag, but page
privilege now does: `lint` and `reclassify` below hold each page at or above the sensitivity
of the sources it cites.

## `reclassify`: raise pages to the tier their sources require

A page written from a `personal-sensitive` source must not sit at `default`, or `publish`
stages it into a role that was never cleared for the underlying document and an MCP credential
reads it that should not. Two rules, both reported by `lint` as errors:

- **source sensitivity** — a page carries at least the highest tier among the raw sources its
  `## Sources` section cites, per `.ingest/sensitivity.tsv`. A row covers a path when the path
  equals it or sits underneath it, so citing one file inside a classified folder inherits the
  folder's tier. A source with no row is skipped, never guessed at.
- **derived_from** — a derived page carries at least the highest tier of its input pages.

```sh
./scripts/reclassify            # raise under-tiered pages, then commit
./scripts/reclassify --dry-run  # show what would change; change nothing
```

It only ever **raises**. Lowering a tier exposes content, so that stays a human decision.
Raising one page can put a page derived from it below its inputs, so it repeats until nothing
changes. Run `classify` first if the sensitivity ledger is stale.

## `convert`: extract text from binary sources

No language model reads a `.docx`. It is a zip of XML, and a model handed the bytes sees
nothing, whether it is a frontier model or a local one. `convert` does the extraction up front,
deterministically, so what the agent can read stops depending on which agent is configured.

```sh
./scripts/convert              # convert anything new or changed under raw/
./scripts/convert --dry-run    # say what would be converted; write nothing
./scripts/convert <raw-path>   # one source
```

`raw/` is never touched. Output lands in `.ingest/text/` with an `index.tsv` recording each
source, the tool used, and whether it produced anything. That directory is derived and
gitignored: delete it and re-run to rebuild. A source is reconverted only when its size or
mtime changes.

| Extension | Tool | Debian package |
|---|---|---|
| `.docx` `.odt` `.rtf` `.html` `.epub` | `pandoc -t plain` | `pandoc` |
| `.xlsx` | `xlsx2csv` | `xlsx2csv` |
| `.doc` / `.xls` / `.ppt` | `catdoc` / `xls2csv` / `catppt` | `catdoc` |
| `.pdf` | `pdftotext -layout` | `poppler-utils` |

Text files and images are skipped: the agent reads those directly. A missing tool is a warning
and a skip, never a failure, so a machine with only poppler still converts its PDFs.

A PDF that yields almost no text has no text layer, which means it is a scan. It is recorded as
`status=scanned` rather than silently empty, so those can be sent for OCR (`tesseract`) or
rasterised with `pdftoppm` and read by a vision model. `CONVERT_SCAN_FLOOR` tunes the
threshold.

Everything for a full-coverage install, about 330 MB on Debian:

```sh
apt-get install -y pandoc poppler-utils xlsx2csv catdoc
```

Run it where `raw/` actually resolves, the same rule as `ingest`: inside a container a
symlinked living source is a dangling link and converts nothing.

## `publish`: role-filtered views for the web

Build a read-only, shareable view of the wiki for a role, including only the pages that role
is cleared to see. Roles and their allowed privilege tiers live in `.publish/roles.tsv`; add
a row to make a view for any role.

```sh
./scripts/publish team             # filter team-cleared pages and build the site with Quartz
./scripts/publish team --serve     # build + live preview at http://localhost:8080
./scripts/publish client --dry-run # report what each role would include/exclude
./scripts/publish --all            # build every role's site into .publish/sites/<role>/
./scripts/publish --all --dry-run  # report include/exclude for every role; write nothing
```

Pages above the role's clearance are excluded; links to excluded pages and all `../raw/`
citation links are de-linked, so the site has no broken links and no paths into private
sources. `index.md` and `overview.md` are skipped (they catalog the whole graph); a minimal
role-view `index.md` is generated so the site root resolves, and Quartz builds its own nav. That
landing page leads with a **Most asked about** list, the most-queried pages (`.ingest/queries.tsv`)
this role is cleared to see, so usage prominence reaches the published site too.

One Quartz instance serves one role at a time, so `--all` writes each role to its own static
output dir (`.publish/sites/<role>/`) you can open or host; preview one live with
`publish <role> --serve`.

The site title (Quartz's header and the landing page) is the KB's own title, read from the
`wiki/overview.md` `title:`/H1 the ingest infers from the sources, falling back to the
`AGENTS.md` H1 then the folder name. Override per build with `KB_TITLE="My KB" ./scripts/publish team`.

[Quartz](https://quartz.jzhao.xyz/) is an Obsidian-aware static site generator: it understands
`[[wikilinks]]` and callouts, unlike plain GitHub. If it is not present, `publish` installs it
once automatically (git clone + `npm i`) into `QUARTZ_DIR` (default `.publish/quartz`, which is
gitignored and disposable — delete it to force a fresh clone). Without git or npm, the filtered
content is staged under `.publish/<role>/content/` with build instructions.

## `scan`: detect changes

Walks `raw/`, fingerprints each source (following symlinks into living drives), and diffs
against `.ingest/manifest.tsv`. Writes the queue to `.ingest/pending.md`. Names in `.ingestignore` are skipped as junk and zero-byte files flagged for review. It only stats files (never reading contents), so it will not hydrate cloud placeholders; same-size sources are flagged as possible duplicates, confirmed by content only with `--dedup`.

```sh
./scripts/scan          # detect; exit 0 = clean, 10 = changes pending
./scripts/scan --accept # advance the baseline to current state (used after ingest)
./scripts/scan --refresh # freshness check: flag read coverage items whose doc changed = stale
```

`scan` (no flag) is also the drift check the Lint workflow calls; `--refresh` is the
per-document freshness check that drives re-reading (see Progressive deepening).

## `ingest`: detect + ingest

```sh
./scripts/ingest            # Pass 1 "read": read HIGH-value docs in full
./scripts/ingest --map      # Pass 0 "map": cheap skeleton + build coverage frontier
./scripts/ingest --deepen   # Pass 2+: read the next highest-value unread OR stale docs
./scripts/ingest --verify   # QA: adversarial auditor re-reads sources, writes .ingest/qa.tsv
./scripts/ingest --sample 8 # verify: audit at most N pages this run
./scripts/ingest --fresh    # prioritise re-reading stale (changed) docs over new coverage
./scripts/ingest --budget 5 # soft per-pass spend target (USD)
./scripts/ingest --watch    # live play-by-play of each step
./scripts/ingest --dry-run  # show what would run; no LLM, no changes
./scripts/ingest --auto     # unattended permissions, for cron / launchd
```

### Progressive deepening

Ingestion is an **anytime, iterative-deepening** loop. Run `--map` once for a cheap
skeleton that enumerates the corpus into `.ingest/coverage.tsv` (the read frontier, ordered
by value: `notes.md` priorities, then a document-type heuristic). Then a default **read**
pass reads the high-value docs; repeat `--deepen` to read progressively more, value-first.
Stop after any pass, the wiki is usable throughout and the next run resumes the frontier.
`--budget $N` caps a pass; watch actual spend in `.ingest/cost.tsv`.

**Freshness.** A deepen pass auto-detects documents that changed since they were read
(`scan --refresh` flips them to `stale`) and re-reads them by value, the frontier is
`unread ∪ stale`. Default order is value-first (stale beats unread *within* a tier);
`--fresh` reconciles all stale before expanding. It's the web-crawler coverage-vs-freshness
trade-off, weighted by importance.

**Verification (`--verify`).** A separate, adversarial QA pass: it re-reads the cited
sources for the highest-risk pages, confirms each claim or flags it (`> [!review]`), and
writes a row per page to `.ingest/qa.tsv` (`status · claims_checked · claims_supported ·
confidence`). `--sample N` caps pages; `--budget $N` caps spend. `stats` reports
`% verified`. It does not sweep, ingest, or touch the manifest, QA only.

Full reference, the two ledgers, the algorithm, and a guardrailed operator playbook:
[`../docs/deepening.md`](../docs/deepening.md).

Flags combine (e.g. `--watch --auto`). Without `--watch` you get the agent's final summary
when it finishes; **`log.md` is the durable record either way** (what was ingested + every
`[!review]` flag). `--watch` streams each step live (read/write/etc.), it uses
`--output-format stream-json` rendered readable through `jq`; install `jq` for clean output,
or you'll see raw JSON. `--auto` stays quiet and logs to `.ingest/auto.log`.

If `claude` isn't on your PATH: `CLAUDE_BIN=/full/path/to/claude ./scripts/ingest`.

### Cost & model

When `jq` is installed, each run appends a row to `.ingest/cost.tsv`:
`date · cost_usd · turns · duration_ms · sources · mode · model` (the model actually used,
read from the run's init event), and prints the run cost plus a running cumulative total.
The ledger is committed, so cost history travels with the KB:

```sh
awk -F'\t' '$1!~/^#/{s+=$2} END{printf "total $%.4f\n", s}' .ingest/cost.tsv
```

The ingest model defaults to **`claude-opus-4-8`**. Override per run with `CLAUDE_MODEL`:

```sh
CLAUDE_MODEL=claude-sonnet-4-6 ./scripts/ingest   # cheaper/faster for small batches
```

On success it advances `.ingest/manifest.tsv` and commits. The manifest only advances when
the ingest run actually changed something (a content signature, computed without git, guards
against a cancelled run silently advancing the baseline), so an interrupted run leaves the queue
intact for next time.

**Git is optional.** Every git call is gated on git being present and the KB being a repo; without
git the manifest still advances and changes are saved to files, just not committed. When git *is*
present, any pending human edits to `wiki/` or `notes.md` are committed on their own *before* the
agent runs, so a hand edit is never silently overwritten or folded into the ingest commit.

**Human-maintained pages.** A wiki page whose frontmatter says `maintained_by: human` is
owner-authored: the agent reads and cites it but never rewrites or deletes it (the per-page
equivalent of `notes.md`), and `lint` exempts it from the agent-discipline checks (citations,
prose hygiene, thin-page). `stats` counts them.

## `query`: ask the wiki, and learn from the asking

`scripts/query "<question>"` answers from the wiki via headless Claude Code and, when the answer
is durable (a synthesis across pages, not a one-fact lookup), files it back as a cited
`analysis` page so the work compounds. It is the read-side twin of `ingest`; the file-back logic
lives in the Query workflow in `AGENTS.md`, so an interactive session behaves the same.

```sh
./scripts/query "how does the cash-for-equity arrangement net out?"
./scripts/query --watch "..."     # live play-by-play
./scripts/query --auto  "..."     # unattended permissions (cron)
./scripts/query --dry-run "..."   # show what would run; no LLM, no cost
```

Auto-filed pages carry `origin: query` and `verified: false` with a `> [!review]` note; they are
usable at once and the nightly `ingest --verify` pass confirms them or flags specific claims.
A lookup or an unanswerable question files nothing. Cost is appended to `.ingest/cost.tsv` under
mode `query`. See `../docs/learning.md` for the design.

## Opt-in auto-ingest

Enable this once you trust the supervised flow. Both options run `ingest --auto` on
a cadence; runs where `raw/` hasn't changed do nothing (detection is free). Replace
`KBPATH` with this KB's absolute path.

> Auto mode runs Claude Code with `--permission-mode bypassPermissions` so it can write
> unattended. Only enable it when you're comfortable with what supervised runs produce.

### macOS (launchd)

Save as `~/Library/LaunchAgents/dev.example.{{KB_NAME}}-ingest.plist`, then load it. Runs
daily at 07:00:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key>            <string>dev.example.{{KB_NAME}}-ingest</string>
  <key>ProgramArguments</key> <array>
    <string>/bin/bash</string>
    <string>KBPATH/scripts/ingest</string>
    <string>--auto</string>
  </array>
  <key>StartCalendarInterval</key> <dict>
    <key>Hour</key><integer>7</integer><key>Minute</key><integer>0</integer>
  </dict>
  <key>StandardOutPath</key>   <string>KBPATH/.ingest/auto.log</string>
  <key>StandardErrorPath</key> <string>KBPATH/.ingest/auto.log</string>
  <key>EnvironmentVariables</key><dict>
    <key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
  </dict>
</dict></plist>
```

```sh
launchctl load   ~/Library/LaunchAgents/dev.example.{{KB_NAME}}-ingest.plist
launchctl unload ~/Library/LaunchAgents/dev.example.{{KB_NAME}}-ingest.plist
```

### Linux (cron)

```cron
# daily at 07:00: ingest anything new in this KB
0 7 * * * cd KBPATH && /bin/bash scripts/ingest --auto >> .ingest/auto.log 2>&1
```
