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

# --- baseUrl is patched per role, and its PATH is what Quartz stamps on the body -------------
# Quartz derives basePath from the baseUrl's pathname; empty means the client router resolves
# against the server root, which 404s under Caddy's /<kb>/<role>/ prefix.
QZ="$TMP/qz"; KB_DIR="$TMP/acme-kb"; mkdir -p "$QZ" "$KB_DIR"
sed -n '/^quartz_set_base_url() {/,/^}/p' "$HERE/publish" >> "$TMP/lib.sh"
. "$TMP/lib.sh"

printf 'configuration:\n  pageTitle: "x"\n  baseUrl: quartz.jzhao.xyz\n' > "$QZ/quartz.config.default.yaml"
quartz_set_base_url client 2>/dev/null
grep -q 'baseUrl: "localhost:8788/acme-kb/client"' "$QZ/quartz.config.default.yaml" \
  || fail "yaml baseUrl not set: $(grep baseUrl "$QZ/quartz.config.default.yaml")"
grep -q '^  baseUrl' "$QZ/quartz.config.default.yaml" || fail "yaml indentation lost"

# a second role must overwrite the first, since one Quartz builds them in turn
quartz_set_base_url owner 2>/dev/null
grep -q 'baseUrl: "localhost:8788/acme-kb/owner"' "$QZ/quartz.config.default.yaml" \
  || fail "second role did not replace the first"
[ "$(grep -c baseUrl "$QZ/quartz.config.default.yaml")" = 1 ] || fail "baseUrl duplicated"

# the path Quartz would compute, which is the whole point
path="$(printf '%s' "localhost:8788/acme-kb/owner" | sed 's#^[^/]*##')"
[ "$path" = "/acme-kb/owner" ] || fail "basePath would be '$path', not the serving prefix"

WIKI_HOST=wiki.corp.example quartz_set_base_url team 2>/dev/null
grep -q 'baseUrl: "wiki.corp.example/acme-kb/team"' "$QZ/quartz.config.default.yaml" \
  || fail "WIKI_HOST override ignored"

# Quartz v4 keeps a TypeScript config instead
rm -f "$QZ/quartz.config.default.yaml"
printf 'export default {\n  baseUrl: "quartz.jzhao.xyz",\n}\n' > "$QZ/quartz.config.ts"
quartz_set_base_url client 2>/dev/null
grep -q 'baseUrl: "localhost:8788/acme-kb/client"' "$QZ/quartz.config.ts" || fail "ts baseUrl not set"

echo "PASS"
