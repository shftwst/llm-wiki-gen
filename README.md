# llm-wiki-gen

Your business already has the answers. They're just buried in folders, inboxes, and someone's
head. This makes that pile answerable: ask a question in plain words, get an answer pulled from
your own documents, not from a guess. Where's the signed contract? What rate did we agree? Who
did we use for insurance last year?

Finding a fact stops being an afternoon of digging. And when the person who knew everything is
on holiday, or gone, the knowledge stays.

You don't tag, sort, or file anything. You drop documents in a folder; an AI reads them, writes
them into a tidy set of linked notes, and keeps it current as you add more. The filing is its
job, not yours. (Based on Andrej Karpathy's **LLM Wiki** pattern,
[`docs/llm-wiki-pattern.md`](docs/llm-wiki-pattern.md).)

```
   inbox/  ──sweep──▶   raw/   ──scan + ingest──▶   wiki/   ──publish──▶   website
  you drop here       locked, never edited        the linked notes       filtered per role
  (one shared box)    (your safe originals)       (what you ask)         (read-only, optional)
                      └────────── the AI does this middle part on its own ──────────┘
```

## Nothing new to learn

Most of these systems die because they ask everyone to tag and tidy, and people quietly stop.
Here there's one folder. Drop a file in, walk away, that's the whole job. Share it as a network
folder and it's the only thing anyone touches; the rest stays out of sight. Because there's
nothing to learn, it actually gets used, which is the only reason any of this is worth doing.

It doesn't fight how you already work, either. Keep your files in the cloud exactly as you do
now, point it at them, and it adds the connections a folder of files can never show you: who a
contract is with, which rate replaced which, where two documents disagree.

## Your files are safe

Nothing you put in ever gets changed. The system can read your documents but is physically
blocked from editing, moving, or deleting them. The AI can't either, even when it's running on
its own overnight. Point it at a shared drive someone else keeps tidy and it reads through to
the originals without touching them, picking up edits whenever they happen. No "the computer
reorganised my files" disaster waiting to go off.

## Answers you can actually trust

A knowledge base is worthless if you can't believe it. Every answer traces back to the real
document it came from, so you can check it yourself. When two documents disagree it says so,
instead of quietly picking one and hoping. It re-reads the sources to mark its own homework, and
flags anything it can't back up rather than inventing something to fill the gap.

It's careful with your money, too: it reads the important things first (you say what matters),
sets obvious junk aside for you to glance at rather than deleting it, and when it's unsure it
keeps a document, because losing something real is worse than holding onto something useless.

## It gets to know your business

The more you use it, the better it gets. It reads deeper over time, remembers your corrections,
and saves the answers to questions you've already asked so the next person gets them straight
away. After a while it knows your suppliers, your clients, and your quirks, and the answers come
faster and sharper.

## Quiet and cheap

It only does paid work when something actually changed; an ordinary day with nothing new costs
nothing. It looks for new files itself and gets on with it, no babysitting. Run it by hand or
leave it on a schedule.

## The right people see the right things

You decide who sees what. Sensitive material (anything with personal or financial detail) can
stay on a computer in your own office and never be sent anywhere. And you can hand someone a
plain read-only website of the knowledge, filtered to their level: a client sees only
client-safe pages, your staff see more, you see everything, with private bits and any path back
to the original files stripped out.

---

The rest is for whoever sets this up.

## Quickstart

```sh
# 1. create a knowledge base (its own folder, and its own git repo)
./scripts/new-kb acme-ops "Acme Operations"     # creates ../acme-ops/
cd ../acme-ops

# 2. feed it documents
cp ~/Documents/*.pdf inbox/                       # the normal way: drop files into inbox/
ln -s "/Volumes/Shared/Acme" raw/acme            # or link a living folder straight into raw/

# 3. read them (ingest sweeps inbox/ into raw/ first, then reads)
./scripts/ingest --map        # cheap first look: lists everything, ranks it by importance
./scripts/ingest              # read the important documents in full
./scripts/ingest --deepen     # keep going, as deep as you want; stop any time

# 4. read wiki/ directly, or publish a site (see below)
```

Each base is self-contained, so you can have one per client and move or hand off a whole folder
without it breaking. `new-kb <name> "<Title>" [parent-dir]` takes a kebab-case folder name, an
optional title, and an optional location.

## Customising

Sensible defaults ship in `_template/`; edit a generated base directly, or edit the template to
change every future one. The knobs, and why you'd turn them:

- **Charter (do this first).** In `AGENTS.md`, write two or three sentences on what this base
  covers and what it does not. It is the yardstick the AI measures every document against, so an
  off-topic file gets parked instead of polluting the wiki. Leave it blank and "off-topic" has
  no meaning, everything looks relevant.
- **Priorities and corrections.** `notes.md` is the owner's channel: list what matters most (it
  gets read first) and correct anything the AI got wrong (the correction sticks across re-runs).
- **Page types (`.schema/page-types.tsv`).** The kinds of page this domain has. Each has a
  `class`: `content` (a page about a subject, e.g. a client or a policy), `source` (a page
  describing one ingested document), or `nav` (index and home pages). Add types that fit your
  world; `lint` checks every page against this list.
- **Privacy levels (`.schema/privilege-tiers.tsv`).** The sensitivity ladder, least to most
  private (the default ships `default` < `business-sensitive` < `personal-sensitive`). This is
  what sensitivity tagging sorts documents into and what publish roles are granted. Rename or
  re-rank tiers and the scripts follow; nothing is hard-coded to the shipped names.
- **Who sees what (`.publish/roles.tsv`).** One row per audience: a role name and the privacy
  levels it may see. Add a row to create a new filtered view.
- **Junk filter (`.ingestignore`).** gitignore-style globs the scan skips outright (system
  files, temp files). Edit to match the cruft your sources collect.

Placeholders (`{{KB_NAME}}`, `{{KB_TITLE}}`, `{{DATE}}`, `{{YEAR}}`) are filled in when a base
is created, so template edits stay generic.

## Publishing a wiki site

`scripts/publish` turns the wiki into a read-only website, filtered to one role's clearance:

```sh
./scripts/publish team --serve     # build the team view and serve it at http://localhost:8080
./scripts/publish client           # build the client view as static files
./scripts/publish --all            # build a separate site for every role in roles.tsv
./scripts/publish team --dry-run   # show what a role would include and exclude; build nothing
```

Pages above the role's level are dropped, and links to them, plus any path back to the raw
files, are removed, so a shared site has no leaks and no dead links. The first run installs the
site builder itself (it needs `git` and `npm`); after that it is just `publish`. The site title
comes from the base's own title; override per build with `KB_TITLE="..." ./scripts/publish team`.

## What's in a knowledge base

Plain files, nothing exotic:

- `wiki/` the notes the AI writes and links (open and read directly)
- `raw/` your source documents (read-only; files or symlinks to living folders)
- `inbox/` the shared drop folder; `sweep` moves drops into `raw/`
- `.schema/` your page types and privacy levels
- `.publish/` publish roles, and a disposable site-builder checkout
- `.ingest/` bookkeeping: what's been read, what's covered, what each run cost
- `AGENTS.md` the AI's full instructions · `STYLE.md` the writing rules · `log.md` a running record

Every script and flag, in detail: [`_template/scripts/README.md`](_template/scripts/README.md).

## License

Apache 2.0, see [LICENSE](LICENSE).
