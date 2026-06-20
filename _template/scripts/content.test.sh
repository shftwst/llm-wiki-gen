#!/usr/bin/env bash
# content.test.sh — builds a tiny fixture KB in a temp dir and checks scripts/content output.
# jq 1.6-safe: extract with `jq -r`, assert in shell (avoids jq -e exit-code semantics).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1" >&2; exit 1; }

mkdir -p "$TMP/.schema" "$TMP/scripts" "$TMP/wiki/concepts"
cp "$HERE/kblib.sh" "$TMP/scripts/kblib.sh"
cp "$HERE/content" "$TMP/scripts/content"
printf 'source\tsource\tsources\t-\nconcept\tcontent\tconcepts\t-\noverview\tnav\t.\t-\n' > "$TMP/.schema/page-types.tsv"
printf 'default\t0\t-\t-\nbusiness-sensitive\t1\tbusiness\t-\n' > "$TMP/.schema/privilege-tiers.tsv"
printf -- '---\ntype: concept\nprivilege: business-sensitive\nupdated: 2026-06-19\n---\n\n# Banking\n\nAccounts text.\n' > "$TMP/wiki/concepts/banking.md"
printf -- '---\ntype: concept\nupdated: 2026-06-01\n---\n\n# Expenses\n\nExpenses text.\n' > "$TMP/wiki/concepts/expenses.md"
printf -- '---\ntype: overview\n---\n\n# Home\n\nNav page.\n' > "$TMP/wiki/overview.md"

man="$("$TMP/scripts/content" --manifest)"
[ -n "$(printf '%s\n' "$man" | jq -r 'select(.id=="concepts/banking") | .hash')" ] || fail "manifest missing banking hash"
printf '%s\n' "$man" | grep -q '"overview"' && fail "manifest included nav page"
[ "$(printf '%s\n' "$man" | grep -c '"id"')" = "2" ] || fail "manifest should list exactly 2 content pages"

rec="$(printf 'concepts/banking\nconcepts/expenses\n' | "$TMP/scripts/content" --get)"
[ "$(printf '%s\n' "$rec" | jq -r 'select(.id=="concepts/banking") | .frontmatter.privilege')" = "business-sensitive" ] || fail "banking privilege wrong"
[ "$(printf '%s\n' "$rec" | jq -r 'select(.id=="concepts/banking") | .title')" = "Banking" ] || fail "banking title wrong"
printf '%s\n' "$rec" | jq -r 'select(.id=="concepts/banking") | .body' | grep -q "Accounts text" || fail "banking body wrong"
[ "$(printf '%s\n' "$rec" | jq -r 'select(.id=="concepts/expenses") | .frontmatter.privilege')" = "default" ] || fail "missing-privilege page should default to lowest tier"

echo "PASS"
