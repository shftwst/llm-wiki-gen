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

echo "PASS"
