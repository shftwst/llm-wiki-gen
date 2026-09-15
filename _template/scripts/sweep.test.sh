#!/usr/bin/env bash
# sweep.test.sh — builds a fixture KB plus a sibling capture/ queue in a temp dir and checks
# both sweep inputs: the shared inbox/ staging directory, and promoted items in capture/.
# Promotion is a field in capture/.meta/<id>.json, so sweep (not the server) does the move.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1" >&2; exit 1; }

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not installed"; exit 0; }

KB="$TMP/ops"
mkdir -p "$KB/scripts" "$KB/inbox" "$KB/raw" "$TMP/capture/.meta"
cp "$HERE/kblib.sh" "$KB/scripts/kblib.sh"
cp "$HERE/sweep" "$KB/scripts/sweep"
printf '.DS_Store\n*.tmp\n' > "$KB/.ingestignore"

# meta <id> <json>: write a capture payload and its provenance sidecar.
meta() { printf 'payload-%s' "$1" > "$TMP/capture/$1"; printf '%s' "$2" > "$TMP/capture/.meta/$1.json"; }

# --- fixtures ---------------------------------------------------------------
printf 'real source\n' > "$KB/inbox/report.pdf"                    # inbox: moves to raw/
printf '' > "$KB/inbox/pending.docx"                               # inbox: zero-byte, held

meta 20260915T100000-ab-invoice.pdf \
  '{"origin":"phone","kind":"http-upload","received":"2026-09-15T10:00:00Z","size":9,
    "promoted":{"kb":"ops","at":"2026-09-15T11:00:00Z","by":"studio"}}'
meta 20260915T100001-cd-notes.md \
  '{"origin":"phone","kind":"mcp-submit","received":"2026-09-15T10:00:01Z","size":9}'
meta 20260915T100002-ef-other.pdf \
  '{"origin":"phone","kind":"http-upload","received":"2026-09-15T10:00:02Z","size":9,
    "promoted":{"kb":"client-x","at":"2026-09-15T11:00:00Z","by":"studio"}}'
meta 20260915T100003-gh-cruft.tmp \
  '{"origin":"phone","kind":"http-upload","received":"2026-09-15T10:00:03Z","size":9,
    "promoted":{"kb":"ops","at":"2026-09-15T11:00:00Z","by":"studio"}}'

# --- dry run changes nothing ------------------------------------------------
out="$("$KB/scripts/sweep" --dry-run)"
printf '%s\n' "$out" | grep -q "capture/20260915T100000-ab-invoice.pdf" \
  || fail "dry-run did not report the promoted capture: $out"
[ -e "$TMP/capture/20260915T100000-ab-invoice.pdf" ] || fail "dry-run moved a promoted capture"
[ -e "$KB/inbox/report.pdf" ] || fail "dry-run moved an inbox item"

# --- real run ---------------------------------------------------------------
out="$("$KB/scripts/sweep")"

# inbox behaviour is unchanged
[ -f "$KB/raw/report.pdf" ]     || fail "inbox item did not reach raw/"
[ -f "$KB/inbox/pending.docx" ] || fail "zero-byte inbox item should be held in place"

# a capture promoted to this KB is moved in, and its sidecar is retired to .done/
[ -f "$KB/raw/20260915T100000-ab-invoice.pdf" ] || fail "promoted capture did not reach raw/"
[ -e "$TMP/capture/20260915T100000-ab-invoice.pdf" ] && fail "promoted capture left in the queue"
[ -f "$TMP/capture/.done/20260915T100000-ab-invoice.pdf.json" ] || fail "sidecar not retired to .done/"
[ -e "$TMP/capture/.meta/20260915T100000-ab-invoice.pdf.json" ] && fail "sidecar left in .meta/"
grep -q "payload-20260915T100000-ab-invoice.pdf" "$KB/raw/20260915T100000-ab-invoice.pdf" \
  || fail "raw/ copy has the wrong content"

# an unpromoted capture is untouched: no promotion decision, no move
[ -f "$TMP/capture/20260915T100001-cd-notes.md" ] || fail "unpromoted capture was moved"
[ -e "$KB/raw/20260915T100001-cd-notes.md" ] && fail "unpromoted capture reached raw/"

# a capture promoted to a different KB is untouched by this KB's sweep
[ -f "$TMP/capture/20260915T100002-ef-other.pdf" ] || fail "another KB's capture was moved"
[ -e "$KB/raw/20260915T100002-ef-other.pdf" ] && fail "another KB's capture reached raw/"

# .ingestignore routing applies to captures too
[ -f "$KB/junk/20260915T100003-gh-cruft.tmp" ] || fail "junk-named capture did not reach junk/"
[ -e "$KB/raw/20260915T100003-gh-cruft.tmp" ] && fail "junk-named capture reached raw/"

printf '%s\n' "$out" | grep -q "2 moved into raw/" || fail "summary count wrong: $out"

# --- a sidecar naming a traversal-shaped KB or id never escapes --------------
meta 20260915T100004-ij-evil.pdf \
  '{"origin":"phone","kind":"http-upload","received":"2026-09-15T10:00:04Z","size":9,
    "promoted":{"kb":"../ops","at":"2026-09-15T11:00:00Z","by":"studio"}}'
printf 'x' > "$TMP/capture/.meta/..%2Fescape.json"
"$KB/scripts/sweep" >/dev/null
[ -f "$TMP/capture/20260915T100004-ij-evil.pdf" ] || fail "a non-matching kb value was acted on"

# --- a second run is a no-op ------------------------------------------------
out="$("$KB/scripts/sweep")"
printf '%s\n' "$out" | grep -qE "nothing to sweep|0 moved" || fail "re-run was not idempotent: $out"

echo "PASS"
