#!/usr/bin/env bash
# lint.test.sh — builds a tiny fixture KB in a temp dir and checks the privilege-inheritance
# rule: a derived page tiered below any of its derived_from inputs is an ERROR (exit 1), and
# raising the page to the maximum input tier clears it.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1" >&2; exit 1; }

mkdir -p "$TMP/.schema" "$TMP/scripts" "$TMP/wiki/concepts" "$TMP/wiki/analysis"
cp "$HERE/kblib.sh" "$TMP/scripts/kblib.sh"
cp "$HERE/lint" "$TMP/scripts/lint"
printf 'concept\tcontent\tconcepts\t-\nanalysis\tcontent\tanalysis\t-\n' > "$TMP/.schema/page-types.tsv"
printf 'default\t0\t-\t-\nbusiness-sensitive\t1\tbusiness\t-\npersonal-sensitive\t2\tpersonal\t-\n' > "$TMP/.schema/privilege-tiers.tsv"

printf -- '---\ntype: concept\nprivilege: business-sensitive\ncreated: 2026-09-01\nupdated: 2026-09-01\n---\n\n# Banking\n\nAccount arrangements described at length, [[rates-analysis]] draws on this.\n\n## Sources\n\n- raw/banking.pdf (read in full)\n' > "$TMP/wiki/concepts/banking.md"
printf -- '---\ntype: analysis\nprivilege: default\norigin: query\nderived_from: ["[[banking]]"]\nas_of: 2026-09-02\ncreated: 2026-09-02\nupdated: 2026-09-02\n---\n\n# Rates analysis\n\nSynthesis of the account arrangements and their pricing over time.\n\n## Sources\n\n- raw/banking.pdf (read in full)\n' > "$TMP/wiki/analysis/rates-analysis.md"

# Under-tiered derived page: lint must fail with the inheritance ERROR
out="$("$TMP/scripts/lint" --quiet 2>&1)" && fail "lint exited 0 with an under-tiered derived page"
printf '%s\n' "$out" | grep -q "inherits the maximum tier" || fail "expected privilege-inheritance ERROR, got: $out"
printf '%s\n' "$out" | grep -q "rates-analysis" || fail "error did not name the offending page"

# Raise the derived page to the input's tier: the ERROR must clear and lint pass
sed -i.bak 's/^privilege: default/privilege: business-sensitive/' "$TMP/wiki/analysis/rates-analysis.md" && rm -f "$TMP/wiki/analysis/rates-analysis.md.bak"
out="$("$TMP/scripts/lint" --quiet 2>&1)" || fail "lint failed after tier was corrected: $out"
printf '%s\n' "$out" | grep -q "inherits the maximum tier" && fail "inheritance ERROR still present after correction"

# Equal-or-higher is fine: personal-sensitive page derived from business-sensitive input
sed -i.bak 's/^privilege: business-sensitive/privilege: personal-sensitive/' "$TMP/wiki/analysis/rates-analysis.md" && rm -f "$TMP/wiki/analysis/rates-analysis.md.bak"
"$TMP/scripts/lint" --quiet >/dev/null 2>&1 || fail "lint failed with derived page above its input tier"

# --- ledger keys must resolve under raw/ -----------------------------------------------------
# coverage.tsv is joined to the filesystem by its path column. A row keyed by an invented slug is
# never fingerprinted, so the source can change and nothing notices: a silent failure, hence an
# error. Skipped entirely where raw/ cannot be read, or every row would fail for the wrong reason.
K="$TMP/ledger"; mkdir -p "$K/scripts" "$K/.ingest" "$K/wiki" "$K/.schema" "$K/raw/Finance/Tax"
cp "$HERE/kblib.sh" "$K/scripts/kblib.sh"; cp "$HERE/lint" "$K/scripts/lint"
cp "$TMP/.schema/page-types.tsv" "$K/.schema/" 2>/dev/null || printf 'concept\tcontent\tconcepts\t-\n' > "$K/.schema/page-types.tsv"
printf 'default\t0\t-\t-\n' > "$K/.schema/privilege-tiers.tsv"
printf 'real-file\n' > "$K/raw/Finance/Tax/t5.pdf"

hdr='# Columns: path\tvalue\tstatus\tpass\tlast_read\tfingerprint\tnotes'

# a key that resolves, including one carrying a trailing "(note)" and one naming a directory
printf '%s\nFinance/Tax/t5.pdf\thigh\tread\t1\t2026-01-01\t-\t-\nFinance/Tax (the tax folder)\thigh\tread\t1\t2026-01-01\t-\t-\n' "$hdr" \
  > "$K/.ingest/coverage.tsv"
out="$("$K/scripts/lint" 2>&1)" || fail "a KB whose ledger keys resolve should pass: $out"
printf '%s\n' "$out" | grep -q "all 2 key(s) resolve" || fail "resolving keys not reported: $out"

# an invented slug, which is what a real KB drifted into
printf '%s\ntax/ye2023-t5-summary (2022 T5 summary)\thigh\tread\t1\t2026-01-01\t-\t-\n' "$hdr" \
  > "$K/.ingest/coverage.tsv"
out="$("$K/scripts/lint" --quiet 2>&1)" && fail "a non-resolving ledger key must be an ERROR"
printf '%s\n' "$out" | grep -q "do not resolve under raw/" || fail "bad key not reported: $out"
printf '%s\n' "$out" | grep -q "tax/ye2023-t5-summary" || fail "offending key not named: $out"
printf '%s\n' "$out" | grep -q "(2022 T5 summary)" && fail "the trailing note should be stripped from the path"

# sensitivity.tsv is keyed the same way and is checked too
printf 'Finance/Tax/t5.pdf\thigh\tread\t1\t2026-01-01\t-\t-\n' > "$K/.ingest/coverage.tsv"
printf '# Columns: item\ttier\tbasis\tdate\nnot/a/real/path\tdefault\tkeyword\t2026-01-01\n' > "$K/.ingest/sensitivity.tsv"
out="$("$K/scripts/lint" --quiet 2>&1)" && fail "a bad sensitivity key must be an ERROR too"
printf '%s\n' "$out" | grep -q "sensitivity.tsv" || fail "sensitivity not checked: $out"
rm -f "$K/.ingest/sensitivity.tsv"

# unreachable raw/ skips rather than failing every row for the wrong reason
printf '%s\ntax/whatever\thigh\tread\t1\t2026-01-01\t-\t-\n' "$hdr" > "$K/.ingest/coverage.tsv"
rm -rf "$K/raw"; mkdir -p "$K/raw"; ln -s /nonexistent/mount "$K/raw/living"
out="$("$K/scripts/lint" 2>&1)" || fail "unreachable raw/ should skip, not fail: $out"
printf '%s\n' "$out" | grep -q "resolves to nothing here, skipped" || fail "skip not reported: $out"

echo "PASS"
