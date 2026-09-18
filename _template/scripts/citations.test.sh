#!/usr/bin/env bash
# citations.test.sh — a fixture KB with real source files under raw/ and pages that cite them.
# Checks the dependency graph, the baseline, and that a changed source names the citing pages.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1" >&2; exit 1; }

KB="$TMP/kb"; mkdir -p "$KB/scripts" "$KB/.ingest" "$KB/wiki/analysis" "$KB/raw/Finance/Tax"
cp "$HERE/kblib.sh" "$KB/scripts/kblib.sh"; cp "$HERE/citations" "$KB/scripts/citations"
printf '.DS_Store\n' > "$KB/.ingestignore"

printf 'the 2023 rate was 150\n' > "$KB/raw/Finance/Tax/return.pdf"
printf 'banking notes\n'          > "$KB/raw/Finance/banking.csv"

# two pages; one cites both sources, one cites only banking. Spaces and a %20 link included.
page() { printf -- '---\ntype: analysis\n---\n\n# %s\n\nprose\n\n## Sources\n\n%s\n' "$2" "$3" > "$KB/wiki/$1"; }
page analysis/rates.md   Rates   '- [tax](../../raw/Finance/Tax/return.pdf) (read in full)
- [bank](../../raw/Finance/banking.csv) (read in full)'
page analysis/cash.md    Cash    '- [bank](../../raw/Finance/banking.csv) (read in full)'

cd "$KB"

# --- graph -------------------------------------------------------------------
g="$(./scripts/citations --graph)"
[ "$(printf '%s\n' "$g" | grep -c .)" = 3 ] || fail "expected 3 edges, got: $g"
printf '%s\n' "$g" | grep -qF "analysis/rates.md	Finance/Tax/return.pdf" || fail "edge missing: $g"

# --- accept then a clean check ----------------------------------------------
./scripts/citations --accept 2>/dev/null
[ -f .ingest/citations.tsv ] || fail "baseline not written"
out="$(./scripts/citations --check 2>/dev/null)"
[ -z "$out" ] || fail "a freshly-baselined wiki should report no affected pages, got: $out"

# --- change one source: only its citing pages are affected -------------------
sleep 1; printf 'the 2023 rate was 175 (corrected)\n' > "$KB/raw/Finance/Tax/return.pdf"
out="$(./scripts/citations --check 2>/dev/null)"
printf '%s\n' "$out" | grep -qx "analysis/rates.md" || fail "rates.md (cites the changed tax file) not flagged: $out"
printf '%s\n' "$out" | grep -qx "analysis/cash.md" && fail "cash.md (does not cite the tax file) should not be flagged: $out"

# the human summary names the changed source and the page
err="$(./scripts/citations --check 2>&1 >/dev/null)"
printf '%s\n' "$err" | grep -q "CHANGED Finance/Tax/return.pdf" || fail "changed source not named: $err"

# --- re-accept clears it -----------------------------------------------------
./scripts/citations --accept 2>/dev/null
[ -z "$(./scripts/citations --check 2>/dev/null)" ] || fail "re-accept did not clear the change"

# --- a new (unbaselined) cited source is flagged as NEW ----------------------
printf 'a new source\n' > "$KB/raw/Finance/new.pdf"
page analysis/extra.md Extra '- [new](../../raw/Finance/new.pdf) (read in full)'
out="$(./scripts/citations --check 2>/dev/null)"
printf '%s\n' "$out" | grep -qx "analysis/extra.md" || fail "page citing a never-baselined source not flagged: $out"

# --- a dropped baseline entry is reported, not fatal -------------------------
./scripts/citations --accept 2>/dev/null
rm "$KB/wiki/analysis/extra.md"                       # stop citing new.pdf
err="$(./scripts/citations --check 2>&1 >/dev/null)"
printf '%s\n' "$err" | grep -q "DROPPED Finance/new.pdf" || fail "dropped baseline entry not reported: $err"

echo "PASS"
