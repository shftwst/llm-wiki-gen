# Kit updates: letting fixes reach knowledge bases that already exist

Status: approved, not yet built.

## The problem

`new-kb` does `cp -R _template/. "$TARGET"/` once, and never again. A knowledge base is
templated at creation and frozen from that moment. Every bug fix and every addition made in the
kit afterwards reaches new bases only, so a base created last month runs last month's tooling
and nothing tells anyone.

The duplication itself is deliberate and stays. A base ships its own `scripts/` so it is
self-contained and splittable: it can be handed to a client, backed up, or operated with no kit
and no pinky anywhere near it. That property is worth keeping. What is not worth keeping is
having no way to move a fix into an existing base short of copying files by hand.

## Who edits what

Nothing can be refreshed safely until it is clear which files a base's owner may change. A file
an implementor edits cannot be overwritten, and a file that cannot be overwritten is frozen at
creation. Today `AGENTS.md` and `STYLE.md` are both editable and therefore both frozen, which
is why most conventions never move.

The fix is a base file that tracks the kit plus a small local file holding only this base's
deltas, with both read. The same shape pinky's deployment uses for its generated compose file
and the site's override.

| Kit-owned, refreshed on update | Seeded once, the base's thereafter |
|---|---|
| `scripts/` | `CHARTER.md` |
| `AGENTS.md` | `STYLE.local.md` |
| `STYLE.md` | `.ingestignore.local` |
| `.ingestignore` | `.schema/page-types.tsv` |
| `.claude/settings.json` | `.schema/privilege-tiers.tsv` |
| `.gitignore` | `.publish/roles.tsv` |
| `raw/`, `inbox/`, `junk/` READMEs | `notes.md`, `log.md`, `wiki/`, `raw/` |

The schema files and `roles.tsv` stay wholly the base's. A tier ladder and a role set are about
that business, and the kit has no better default to re-impose once a base is in use.

## Splitting the charter

`## Charter (what this KB covers)` currently sits at line 11 of `AGENTS.md`, in the middle of
roughly five hundred lines of kit conventions, and the rest of the file refers back to it, as
does the ingest prompt when it records a relevance verdict per source.

Moving it to `CHARTER.md`, seeded with a default the implementor edits, is what makes the rest
work. With it gone, `AGENTS.md` becomes kit-owned, and the trust boundary rule, the source
model, the page conventions and the workflows all start tracking the kit. That is where most
fixes live, so this one move accounts for most of the benefit.

`AGENTS.md` references `CHARTER.md` where it used to hold the section. The ingest and query
prompts read it alongside `notes.md`.

The alternative considered was folding the charter into `notes.md`, which already exists, is
already the owner's, and is already read first by every prompt. It was rejected because the
charter is enforced mechanically, with a verdict written per source, and a rule with teeth is
easier to erode inside free-form notes.

## Local override files

`STYLE.local.md` and `.ingestignore.local` are seeded empty with a comment saying what they are
for. Both are optional; a base with neither behaves exactly as it does now.

- `.ingestignore.local` is concatenated with `.ingestignore` by `kblib.sh`, which already loads
  the patterns once into `_KB_IGNORE_PATS`. Additions to the kit's cruft list then reach every
  base, and a base's own patterns survive an update.
- `STYLE.local.md` is read after `STYLE.md` wherever style is read. Its content is additions and
  exceptions for this base, not a replacement.

## `.kit` and the upgrade command

A `.kit` file at the base's root records where the kit came from, which version produced the
current files, and a checksum per kit-owned file (see below). `new-kb` writes it.

`scripts/upgrade` fetches the kit at a version, refreshes only the kit-owned column, and prints
what changed. It never touches the seeded column.

### Where the kit comes from

`.kit` records a source, and `upgrade` resolves it in this order:

1. A path given on the command line, `upgrade --from /path/to/llm-wiki-gen`. Wins over
   everything, and is how a consultant updates a base from a checkout they brought with them.
2. The `source` recorded in `.kit`, which `new-kb` writes. Normally the kit's git remote, since
   the kit is its own repository; a path or a tarball URL works the same way.
3. Nothing. `upgrade` says so and stops, rather than guessing.

A version argument pins the fetch; without one it takes the newest tag the source offers and
names it before changing anything.

This means a base never needs a checkout beside it, and never needs pinky. A deployment host
with network access to the kit's remote can update every base it holds.

### Sites with no route to the remote

A client site may have no outbound access, which rules out a fetch. Two routes cover it, and
both use the same `--from`:

- A checkout or an unpacked release on local disk or a mounted share.
- A tarball of the kit, which `upgrade` unpacks to a temporary directory and treats as a
  checkout.

So the offline story is not a separate mechanism, only a different source. Nothing about the
refresh, the checksum guard or the reporting changes.

### Several bases at once

A deployment holds more than one base, and running a command per base does not scale past a
handful.

- `scripts/upgrade --check` refreshes nothing and reports whether this base is behind, which is
  what the staleness notice in `ingest` and `lint` calls.
- Pinky wraps it for a whole deployment, disambiguated by object rather than by a second verb:
  `./pinky kb upgrade <kb>`, `./pinky kb upgrade --all` to walk every base under `KB_ROOT`, and
  `./pinky kb upgrade --check` to list which are behind. It runs each base's own
  `scripts/upgrade` inside the ops container, which already carries git, so the host needs no
  checkout.

One verb everywhere, and the object says what it acts on. `./pinky upgrade 0.4` is the
deployment; `./pinky kb upgrade` is the bases. The two cannot be told apart by argument shape,
since a version and a base name look alike, so the noun does the work. Earlier drafts used
`update-kit` and `update-kb`, which differ by a letter and mean nearly the same thing; the first
person to read that asked which was which.

The kit version is pinned per base in its own `.kit`, independently of `PINKY_VERSION`. Two
bases can sit on different kit versions on purpose, which is how you update one, watch an
ingest run through it, and only then do the rest.

### The kit is not baked into the pinky images

It would be convenient and it is the wrong call. It would tie the kit's release cadence to
pinky's, which undoes the reason the kit is a separate repository, and it would lock out a
client base that has no pinky. Pinky supplies a runner and a container with git in it. The kit
supplies itself.

It also performs a one-time migration, so bases created before this design convert themselves:
when a base has no `CHARTER.md` and its `AGENTS.md` still carries a `## Charter` section, the
section is lifted into `CHARTER.md` first, and only then is `AGENTS.md` refreshed. A base that
has already converted is left alone.

### Upgrading the upgrader

`scripts/upgrade` is itself kit-owned, so a refresh rewrites the script while it is running. Bash
reads a script incrementally rather than loading it whole, so overwriting it in place partway
through leaves the shell executing whatever now sits at that byte offset. The failure is a
one-off, looks like nothing else, and is very hard to diagnose after the fact.

It has to avoid editing the running file: either copy itself to a temporary location and re-exec
from there before touching anything, or write every replacement through a rename so the running
inode is never modified. Either is fine; doing neither is not.

## Never overwrite a file somebody edited

Until now, editing any file in a base was safe, because nothing ever overwrote one. `AGENTS.md`
and `STYLE.md` in particular were fair game. The moment they become kit-owned, a naive refresh
destroys that work, and `AGENTS.md` is the likeliest file to have been edited because it was
the only place to record anything about how this base should behave.

So `.kit` records a checksum per kit-owned file, taken of the file as installed rather than of
the template, since `new-kb` substitutes the title into `AGENTS.md` and the two would otherwise
never match. On update, a file whose checksum still matches is refreshed silently. A file whose
checksum differs has been edited locally, and the update stops rather than overwriting it.

The report names each edited file and offers two ways forward:

- **pin it.** The base keeps its version, `.kit` records the file as deliberately divergent, and
  future updates skip it and say so. An accidental divergence becomes a declared one. `--unpin`
  reverses it and `--pinned` lists what is pinned, so the decision is not one-way: unpinning
  drops the row rather than restoring `tracked`, because the recorded checksum is of the local
  version and leaving it would make the next update read the file as unmodified and overwrite
  it.
- **take the kit's.** The local file is saved beside it as `<name>.local-backup` first, so the
  edit is recoverable, and the kit version is written.

Neither happens without being asked. An update that silently reverted somebody's conventions
would be worse than never updating at all, and harder to notice.

This is also the safety net under the charter migration. A base whose `AGENTS.md` was edited in
ways beyond the charter has those edits preserved and reported, not lifted and lost.

## Notice, not silent self-update

`ingest` and `lint` print one line when a newer kit is known, and stop there. Updating is an
explicit command.

Compose files in a deployment are regenerated on every run because they are configuration with
no behaviour of their own. Scripts are behaviour. Rewriting behaviour partway through an ingest
is the kind of thing that fails at an awkward moment and is hard to explain afterwards, and the
audit trail of what ran becomes unreliable. A loud notice gets the same outcome with none of
that.

`scripts/` stays committed to the base's own git history rather than being derived and ignored,
because a base handed to a client should carry its tooling in its history.

## The first upgrade has no baseline

The checksum guard needs a `.kit` to compare against, and the first upgrade of an existing base
has none. Every kit-owned file is then unrecorded, so nothing looks edited and a naive
implementation adopts the kit's version of all of them. That is the most destructive moment in
the whole design, and it is the one the guard does not cover.

It is not guessable either. Without a baseline, a file that differs from the kit could equally
be behind it or carry local changes, and the two are indistinguishable.

So a file with no recorded checksum that differs from the kit is reported as unknown, and the
upgrade stops. You look at each one and either `--pin` it to keep yours or, once the remaining
ones are genuinely just behind, pass `--adopt` to take the kit's version of the rest. `--pin`
works before any `.kit` exists, seeding one.

This is not hypothetical. The first real base this was run against had `raw/onedrive-files` and
`kb.git/` in its `.gitignore`, keeping a mounted source tree and a nested bare repo out of git.
Silently adopting the kit's `.gitignore` would have removed both.

## Bootstrap

Existing bases have no `scripts/upgrade` to run, so the first one arrives by hand: copy that
single script in, or run it from a kit checkout against the base's path. That first run then
behaves as described above, refusing to adopt anything it cannot vouch for. It bites once per base that
predates this, and never again.

## Not covered

Publishing the kit anywhere it can be fetched from without a checkout, and any notion of
downgrading. Updates move forward; rolling back is a git operation in the base.
