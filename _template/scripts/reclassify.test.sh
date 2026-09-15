#!/usr/bin/env bash
# reclassify.test.sh — a fixture KB where pages sit below the tier their sources require.
# Checks the lint rule that reports it and the reclassify command that raises it, including
# the cascade: raising a page must then raise anything derived from it.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1" >&2; exit 1; }
tier() { awk -F': ' '/^privilege:/{sub(/^[^:]*: */,"");print;exit}' "$1"; }

mkdir -p "$TMP/.schema" "$TMP/.ingest" "$TMP/scripts" "$TMP/wiki/concepts" "$TMP/wiki/analysis"
for s in kblib.sh lint reclassify; do cp "$HERE/$s" "$TMP/scripts/$s"; done
printf 'concept\tcontent\tconcepts\t-\nanalysis\tcontent\tanalysis\t-\n' > "$TMP/.schema/page-types.tsv"
printf 'default\t0\t-\t-\nbusiness-sensitive\t1\tbusiness\t-\npersonal-sensitive\t2\tpersonal\t-\n' \
  > "$TMP/.schema/privilege-tiers.tsv"

# classify's ledger: one plain file, one group covering a directory.
{ printf '# sensitivity.tsv\n'
  printf 'minute-book/other-resolutions (director changes)\tpersonal-sensitive\tkeyword\t2026-09-15\n'
  printf 'banking/statements\tbusiness-sensitive\tkeyword\t2026-09-15\n'
} > "$TMP/.ingest/sensitivity.tsv"

page() { # <path> <privilege> <extra-frontmatter> <sources-block>
  printf -- '---\ntype: %s\nprivilege: %s\ncreated: 2026-09-01\nupdated: 2026-09-01\n%s---\n\n# %s\n\nProse.\n\n## Sources\n\n%s\n' \
    "$5" "$2" "$3" "$(basename "$1" .md)" "$4" > "$TMP/wiki/$1"
}

# Under-tiered against a group row: cites one file inside a classified directory.
page "concepts/directors.md" "business-sensitive" "" "- raw/minute-book/other-resolutions/2023-change.pdf (read in full)" concept
# Correctly tiered already.
page "concepts/banking.md" "business-sensitive" "" "- raw/banking/statements/2025.pdf (read in full)" concept
# Cites an unclassified source: must be left alone, not guessed at.
page "concepts/misc.md" "default" "" "- raw/uncatalogued/notes.txt (read in full)" concept
# Derived from directors: must cascade up once directors is raised.
page "analysis/board-trends.md" "default" 'origin: query
derived_from: ["[[directors]]"]
as_of: 2026-09-02
' "- raw/minute-book/other-resolutions/2023-change.pdf (read in full)" analysis

# --- lint reports it ---------------------------------------------------------
out="$("$TMP/scripts/lint" --quiet 2>&1)" && fail "lint exited 0 with an under-tiered page"
printf '%s\n' "$out" | grep -q "below its sources" || fail "expected source-sensitivity ERROR, got: $out"
printf '%s\n' "$out" | grep -q "concepts/directors" || fail "error did not name the offending page"
printf '%s\n' "$out" | grep -q "personal-sensitive" || fail "error did not name the required tier"
printf '%s\n' "$out" | grep -q "concepts/misc" && fail "unclassified source must not be flagged"
printf '%s\n' "$out" | grep -q "concepts/banking" && fail "correctly tiered page must not be flagged"

# --- dry run changes nothing -------------------------------------------------
out="$("$TMP/scripts/reclassify" --dry-run)"
printf '%s\n' "$out" | grep -q "concepts/directors.md: business-sensitive → personal-sensitive" \
  || fail "dry-run did not report the raise: $out"
[ "$(tier "$TMP/wiki/concepts/directors.md")" = business-sensitive ] || fail "dry-run modified a page"

# --- real run raises, and cascades to the derived page -----------------------
out="$("$TMP/scripts/reclassify")"
[ "$(tier "$TMP/wiki/concepts/directors.md")" = personal-sensitive ] || fail "directors not raised"
[ "$(tier "$TMP/wiki/analysis/board-trends.md")" = personal-sensitive ] \
  || fail "derived page did not cascade (got $(tier "$TMP/wiki/analysis/board-trends.md"))"
[ "$(tier "$TMP/wiki/concepts/misc.md")" = default ] || fail "unclassified-source page was raised"
[ "$(tier "$TMP/wiki/concepts/banking.md")" = business-sensitive ] || fail "correct page was changed"

# Frontmatter is otherwise intact and the body is untouched.
grep -q '^type: concept$' "$TMP/wiki/concepts/directors.md" || fail "frontmatter damaged"
grep -q '^# directors$' "$TMP/wiki/concepts/directors.md" || fail "body damaged"
[ "$(grep -c '^privilege:' "$TMP/wiki/concepts/directors.md")" = 1 ] || fail "duplicate privilege line"

# --- a second run is a no-op, and lint is now clean --------------------------
out="$("$TMP/scripts/reclassify")"
printf '%s\n' "$out" | grep -q "at or above" || fail "re-run was not idempotent: $out"
out="$("$TMP/scripts/lint" --quiet 2>&1)" || fail "lint still errors after reclassify: $out"

# --- it never lowers a tier --------------------------------------------------
sed -i.bak 's/^privilege: business-sensitive/privilege: personal-sensitive/' "$TMP/wiki/concepts/banking.md"
rm -f "$TMP/wiki/concepts/banking.md.bak"
"$TMP/scripts/reclassify" >/dev/null
[ "$(tier "$TMP/wiki/concepts/banking.md")" = personal-sensitive ] || fail "reclassify lowered a tier"

echo "PASS"
