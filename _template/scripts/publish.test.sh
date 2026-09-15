#!/usr/bin/env bash
# publish.test.sh — the KB title is free text and lands in two places that are structured: the
# role landing page's YAML frontmatter and Quartz's config. Checks it is escaped in both.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1" >&2; exit 1; }

# yaml_dq is the unit under test; source it out of publish without running the script.
sed -n '/^yaml_dq() {/,/^}/p' "$HERE/publish" > "$TMP/lib.sh"
. "$TMP/lib.sh"

[ "$(yaml_dq 'Acme Ltd: Operations')" = '"Acme Ltd: Operations"' ] || fail "colon title not quoted"
[ "$(yaml_dq 'Say "hi"')" = '"Say \"hi\""' ] || fail "quotes not escaped: $(yaml_dq 'Say "hi"')"
[ "$(yaml_dq 'back\slash')" = '"back\\slash"' ] || fail "backslash not escaped: $(yaml_dq 'back\slash')"
[ "$(yaml_dq '# not a comment')" = '"# not a comment"' ] || fail "hash title not quoted"
[ "$(yaml_dq 'plain')" = '"plain"' ] || fail "plain title not quoted"
[ "$(yaml_dq "$(printf 'two\nlines')")" = '"twolines"' ] || fail "newline not removed"

# The escaped form must survive a real YAML parser. Node has no YAML built in, so check the
# property that broke: the value must not itself contain an unescaped ": " outside quotes.
for t in 'Acme Ltd: Operations' 'Say "hi"' 'back\slash' '# not a comment'; do
  line="title: $(yaml_dq "$t")"
  printf '%s\n' "$line" | grep -qE '^title: "([^"\\]|\\.)*"$' \
    || fail "not a well-formed quoted scalar: $line"
done

# And the round trip: unescaping must give back exactly what went in.
for t in 'Acme Ltd: Operations' 'Say "hi"' 'back\slash'; do
  q="$(yaml_dq "$t")"; body="${q#\"}"; body="${body%\"}"
  back="$(printf '%s' "$body" | sed -e 's/\\"/"/g' -e 's/\\\\/\\/g')"
  [ "$back" = "$t" ] || fail "round trip lost data: '$t' -> '$back'"
done

echo "PASS"
