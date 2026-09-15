#!/usr/bin/env bash
# upgrade.test.sh — scaffolds a KB from a throwaway copy of the kit, changes the kit, and checks
# that scripts/upgrade moves the change in without touching anything the KB owns.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_SRC="$(cd "$HERE/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1" >&2; exit 1; }

KIT="$TMP/kit"
mkdir -p "$KIT"
cp -R "$KIT_SRC/_template" "$KIT/_template"
cp -R "$KIT_SRC/scripts" "$KIT/scripts"

KBS="$TMP/bases"; mkdir -p "$KBS"
KB_KIT_SOURCE="$KIT" "$KIT/scripts/new-kb" base "Base" "$KBS" >/dev/null 2>&1 || fail "new-kb failed"
KB="$KBS/base"
up() { (cd "$KB" && ./scripts/upgrade --from "$KIT" "$@"); }
tracked() { awk -F'\t' -v p="$2" '$1=="file" && $2==p {print $4}' "$1/.kit"; }

[ -f "$KB/.kit" ]         || fail "new-kb wrote no .kit"
[ -f "$KB/CHARTER.md" ]   || fail "charter not seeded"
grep -q "^# Base: Charter" "$KB/CHARTER.md" || fail "charter title not substituted"

# --- nothing to do on a fresh base ------------------------------------------
out="$(up --check)"
printf '%s\n' "$out" | grep -q "up to date" || fail "fresh base should be up to date: $out"

# --- a kit change reaches the base ------------------------------------------
printf '\n# kit change marker\n' >> "$KIT/_template/scripts/sweep"
printf 'newpattern\n' >> "$KIT/_template/.ingestignore"
out="$(up --check)"
printf '%s\n' "$out" | grep -q "to update" || fail "--check did not see the change: $out"
grep -q "kit change marker" "$KB/scripts/sweep" && fail "--check modified the base"

out="$(up)"
grep -q "kit change marker" "$KB/scripts/sweep" || fail "kit change did not reach the base"
grep -q "newpattern" "$KB/.ingestignore" || fail "ignore change did not reach the base"
[ -x "$KB/scripts/sweep" ] || fail "refreshed script lost its exec bit"
up --check | grep -q "up to date" || fail "not up to date after applying"

# --- the base's own files are never touched ----------------------------------
printf 'MINE\n' >> "$KB/CHARTER.md"; printf 'MINE\n' >> "$KB/STYLE.local.md"
printf 'MINE\n' >> "$KB/.ingestignore.local"; printf 'mine\tlocal\n' >> "$KB/.schema/page-types.tsv"
printf '\n# another kit change\n' >> "$KIT/_template/scripts/lint"
up >/dev/null
for f in CHARTER.md STYLE.local.md .ingestignore.local .schema/page-types.tsv; do
  grep -q "MINE\|mine" "$KB/$f" || fail "$f was overwritten"
done

# --- a file edited in the base stops the upgrade -----------------------------
printf '\n# edited by the owner\n' >> "$KB/scripts/lint"
printf '\n# yet another kit change\n' >> "$KIT/_template/scripts/lint"
set +e; out="$(up 2>&1)"; rc=$?; set -e
[ "$rc" -ne 0 ] || fail "upgrade should stop when a kit-owned file was edited"
printf '%s\n' "$out" | grep -q "EDITED HERE" || fail "edited file not reported: $out"
printf '%s\n' "$out" | grep -q "scripts/lint" || fail "edited file not named: $out"
grep -q "edited by the owner" "$KB/scripts/lint" || fail "the edit was clobbered anyway"

# --- pin keeps yours, and says so ever after ---------------------------------
(cd "$KB" && ./scripts/upgrade --pin scripts/lint >/dev/null)
[ "$(tracked "$KB" scripts/lint)" = pinned ] || fail "pin not recorded"
out="$(up)"
printf '%s\n' "$out" | grep -q "pinned, skipped" || fail "pinned file not reported: $out"
grep -q "edited by the owner" "$KB/scripts/lint" || fail "pinned file was overwritten"
grep -q "yet another kit change" "$KB/scripts/lint" && fail "pinned file took the kit's version"

# --- force takes the kit's, keeping a backup ---------------------------------
printf '\n# owner edit to classify\n' >> "$KB/scripts/classify"
printf '\n# kit edit to classify\n' >> "$KIT/_template/scripts/classify"
up --force >/dev/null
grep -q "kit edit to classify" "$KB/scripts/classify" || fail "--force did not take the kit's version"
grep -q "owner edit to classify" "$KB/scripts/classify.local-backup" || fail "--force kept no backup"

# --- a file the kit newly owns is added --------------------------------------
printf 'hello\n' > "$KIT/_template/NEWFILE.md"
printf 'NEWFILE.md\n' >> "$KIT/_template/.kit-owned"
up >/dev/null
[ -f "$KB/NEWFILE.md" ] || fail "newly owned file not added"
grep -q "^file	NEWFILE.md	" "$KB/.kit" || fail "newly owned file not tracked"

# --- upgrading the upgrader itself -------------------------------------------
printf '\n# upgrade self-change\n' >> "$KIT/_template/scripts/upgrade"
up >/dev/null || fail "upgrade failed while replacing itself"
grep -q "upgrade self-change" "$KB/scripts/upgrade" || fail "upgrade did not replace itself"

# --- charter migration for a base that predates CHARTER.md -------------------
OLD="$KBS/old"; mkdir -p "$OLD/scripts"
cp "$KIT/_template/scripts/upgrade" "$OLD/scripts/upgrade"
printf '# Old KB\n\n## Charter (what this KB covers)\n\nCovers the old thing.\n\n## Relevance triage and quarantine\n\nblah\n' \
  > "$OLD/AGENTS.md"
out="$(cd "$OLD" && ./scripts/upgrade --from "$KIT" 2>&1)" || true
[ -f "$OLD/CHARTER.md" ] || fail "charter not lifted out of AGENTS.md"
grep -q "Covers the old thing" "$OLD/CHARTER.md" || fail "lifted charter lost its content"
printf '%s\n' "$out" | grep -q "lifted out of AGENTS.md" || fail "migration not reported: $out"

# --- a KB with no .kit must not adopt files it cannot vouch for ---------------
# This is the bootstrap case, and the checksum guard cannot help: with no baseline, a file that
# differs could equally be behind the kit or edited here. Guessing wrong destroys real config.
BARE="$KBS/bare"; mkdir -p "$BARE/scripts"
cp "$KIT/_template/scripts/upgrade" "$BARE/scripts/upgrade"
cp "$KIT/_template/.gitignore" "$BARE/.gitignore"
printf 'raw/local-mount\n' >> "$BARE/.gitignore"        # the kind of line that must survive
cp "$KIT/_template/STYLE.md" "$BARE/STYLE.md"
bare_up() { (cd "$BARE" && ./scripts/upgrade --from "$KIT" "$@"); }

set +e; out="$(bare_up 2>&1)"; rc=$?; set -e
[ "$rc" -ne 0 ] || fail "first upgrade should stop on files with no baseline"
printf '%s\n' "$out" | grep -q "UNKNOWN (no baseline)" || fail "unknown files not reported: $out"
printf '%s\n' "$out" | grep -q ".gitignore" || fail "edited .gitignore not listed: $out"
grep -q "raw/local-mount" "$BARE/.gitignore" || fail "first run clobbered .gitignore"

# pin it, and the rest can be adopted
(cd "$BARE" && ./scripts/upgrade --pin .gitignore >/dev/null)
bare_up --adopt >/dev/null || fail "--adopt failed after pinning"
grep -q "raw/local-mount" "$BARE/.gitignore" || fail "pinned .gitignore was overwritten"
[ -f "$BARE/scripts/sweep" ] || fail "--adopt did not install the rest of the kit"
bare_up --check | grep -q "up to date" || fail "not settled after adopt"

echo "PASS"
