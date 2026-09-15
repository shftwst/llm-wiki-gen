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

## `.kit` and the update command

A `.kit` file at the base's root records where the kit came from, which version produced the
current files, and a checksum per kit-owned file (see below). `new-kb` writes it.

`scripts/update-kit` fetches the kit at a version, refreshes only the kit-owned column, and
prints what changed. It never touches the seeded column.

It also performs a one-time migration, so bases created before this design convert themselves:
when a base has no `CHARTER.md` and its `AGENTS.md` still carries a `## Charter` section, the
section is lifted into `CHARTER.md` first, and only then is `AGENTS.md` refreshed. A base that
has already converted is left alone.

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
  future updates skip it and say so. An accidental divergence becomes a declared one.
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

## Bootstrap

Existing bases have no `update-kit` to run, so the first update arrives by hand: copy that one
script in, or run it from a kit checkout against the base's path. It bites once per base that
predates this, and never again.

## Not covered

Publishing the kit anywhere it can be fetched from without a checkout, and any notion of
downgrading. Updates move forward; rolling back is a git operation in the base.
