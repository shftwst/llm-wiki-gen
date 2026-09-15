#!/usr/bin/env bash
# agentlib.test.sh — checks the KB_AGENT driver (scripts/agentlib.sh) against fake agent binaries,
# then runs scripts/query end to end through the hermes driver. jq 1.6-safe.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1" >&2; exit 1; }

# --- fixture KB + fake agents on PATH -----------------------------------------------------
mkdir -p "$TMP/kb/scripts" "$TMP/kb/.ingest" "$TMP/bin"
cp "$HERE/agentlib.sh" "$TMP/kb/scripts/agentlib.sh"
cp "$HERE/query" "$TMP/kb/scripts/query"

# fake hermes: records argv (one per line) and cwd, prints a reply.
# pwd -P on both sides of the comparison: on macOS mktemp -d returns a path under /var, which is
# a symlink to /private/var, so a logical pwd and the expected physical path never match.
cat > "$TMP/bin/hermes" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$FAKE_LOG"
pwd -P > "$FAKE_LOG.cwd"
echo "hermes reply"
EOF
# fake claude: records argv, emits a stream-json transcript with a cost
cat > "$TMP/bin/claude" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$FAKE_LOG"
echo '{"type":"system","subtype":"init","model":"fake-model-1"}'
usage='"usage":{"input_tokens":1200,"output_tokens":340,"cache_read_input_tokens":800,"cache_creation_input_tokens":90}'
if [ -n "${FAKE_NO_COST:-}" ]; then
  echo "{\"type\":\"result\",\"subtype\":\"success\",\"result\":\"claude reply\",\"num_turns\":3,\"duration_ms\":1200,$usage}"
else
  echo "{\"type\":\"result\",\"subtype\":\"success\",\"result\":\"claude reply\",\"total_cost_usd\":0.42,\"num_turns\":3,\"duration_ms\":1200,$usage}"
fi
EOF
chmod +x "$TMP/bin/hermes" "$TMP/bin/claude"
export PATH="$TMP/bin:$PATH"
export FAKE_LOG="$TMP/fake.log"

# run a snippet with agentlib sourced, in a subshell so env leaks nowhere
# stderr goes to LIB_ERR (default: discarded, so the non-claude guard notice stays out of the way)
lib() { ( cd "$TMP/kb" && KB_DIR="$TMP/kb" && . scripts/agentlib.sh && eval "$1" ) 2>"${LIB_ERR:-/dev/null}"; }

# --- hermes driver ------------------------------------------------------------------------
rm -f "$FAKE_LOG"
out="$(KB_AGENT=hermes lib 'kb_agent_init; kb_agent_run "read the docs"')"
[ "$out" = "hermes reply" ] || fail "hermes: stdout should be the agent reply, got: $out"
[ "$(sed -n 1p "$FAKE_LOG")" = "-z" ] || fail "hermes: first arg should be -z"
[ "$(sed -n 2p "$FAKE_LOG")" = "read the docs" ] || fail "hermes: prompt should follow -z"
[ "$(cat "$FAKE_LOG.cwd")" = "$(cd "$TMP/kb" && pwd -P)" ] || fail "hermes: must run in KB_DIR"

KB_AGENT=hermes KB_MODEL=nous/hermes-4 lib 'kb_agent_init; kb_agent_run "p" >/dev/null'
grep -qx -- '-m' "$FAKE_LOG" && grep -qx 'nous/hermes-4' "$FAKE_LOG" || fail "hermes: KB_MODEL should pass -m <model>"

KB_AGENT=hermes lib 'WATCH=1; kb_agent_init; kb_agent_run "p" >/dev/null'
[ "$(sed -n 1p "$FAKE_LOG")" = "chat" ] || fail "hermes --watch: should use 'hermes chat'"
grep -qx -- '--oneshot' "$FAKE_LOG" || fail "hermes --watch: needs --oneshot"
grep -qx -- '--yolo' "$FAKE_LOG" || fail "hermes --watch: needs --yolo"
grep -qx -- '-q' "$FAKE_LOG" || fail "hermes --watch: needs -q"

cost="$(KB_AGENT=hermes lib 'kb_agent_init; kb_agent_run "p" >/dev/null; printf "%s" "${AGENT_COST:-}"')"
[ -z "$cost" ] || fail "hermes: reports no cost (got '$cost')"

# --- claude driver (default) --------------------------------------------------------------
out="$(lib 'kb_agent_init; kb_agent_run "p"')"
[ "$out" = "claude reply" ] || fail "claude: should print the result text, got: $out"
grep -qx -- '-p' "$FAKE_LOG" || fail "claude: needs -p"
grep -qx -- 'acceptEdits' "$FAKE_LOG" || fail "claude: default permission mode is acceptEdits"
grep -qx -- 'stream-json' "$FAKE_LOG" || fail "claude: uses stream-json when jq is present"

lib 'AUTO=1; kb_agent_init; kb_agent_run "p" >/dev/null'
grep -qx -- 'bypassPermissions' "$FAKE_LOG" || fail "claude --auto: permission mode bypassPermissions"

CLAUDE_MODEL=legacy-model lib 'kb_agent_init; kb_agent_run "p" >/dev/null'
grep -qx -- 'legacy-model' "$FAKE_LOG" || fail "claude: CLAUDE_MODEL still selects the model"

vals="$(lib 'kb_agent_init; kb_agent_run "p" >/dev/null; printf "%s|%s|%s|%s" "$AGENT_COST" "$AGENT_TURNS" "$AGENT_DUR" "$AGENT_MODEL_USED"')"
[ "$vals" = "0.42|3|1200|fake-model-1" ] || fail "claude: cost fields wrong: $vals"

# --- cmd driver ---------------------------------------------------------------------------
KB_AGENT=cmd KB_AGENT_CMD="cat > \"$TMP/cmd.in\"; pwd -P > \"$TMP/cmd.cwd\"; echo cmd reply" \
  lib 'kb_agent_init; kb_agent_run "stdin prompt" > "$TMP/cmd.out"'
[ "$(cat "$TMP/cmd.in")" = "stdin prompt" ] || fail "cmd: prompt should arrive on stdin"
[ "$(cat "$TMP/cmd.out")" = "cmd reply" ] || fail "cmd: stdout should pass through"
[ "$(cat "$TMP/cmd.cwd")" = "$(cd "$TMP/kb" && pwd -P)" ] || fail "cmd: must run in KB_DIR"

set +e
KB_AGENT=cmd lib 'kb_agent_init'; rc=$?
set -e
[ "$rc" -ne 0 ] || fail "cmd: KB_AGENT_CMD unset must be an error"

# --- errors -------------------------------------------------------------------------------
set +e
KB_AGENT=nonesuch LIB_ERR="$TMP/err" lib 'kb_agent_init'; rc=$?
set -e
[ "$rc" -ne 0 ] || fail "unknown KB_AGENT must fail"
grep -q "nonesuch" "$TMP/err" || fail "unknown KB_AGENT error should name the value"

set +e
KB_AGENT=hermes KB_AGENT_BIN=/nonexistent/hermes lib 'kb_agent_init; kb_agent_check'; rc=$?
set -e
[ "$rc" -eq 127 ] || fail "missing binary should exit 127 (got $rc)"

# --- cost ledger --------------------------------------------------------------------------
lib 'kb_agent_init; kb_agent_run "p" >/dev/null; kb_cost_record 2 read >/dev/null'
row="$(grep -v '^#' "$TMP/kb/.ingest/cost.tsv" | tail -1)"
[ "$(printf '%s' "$row" | cut -f2)" = "0.42" ] || fail "cost.tsv: cost column"
[ "$(printf '%s' "$row" | cut -f5)" = "2" ] || fail "cost.tsv: sources column"
[ "$(printf '%s' "$row" | cut -f6)" = "read" ] || fail "cost.tsv: mode column"
[ "$(printf '%s' "$row" | cut -f7)" = "fake-model-1" ] || fail "cost.tsv: model column"
[ "$(printf '%s' "$row" | cut -f8)"  = "1200" ] || fail "cost.tsv: in_tokens column"
[ "$(printf '%s' "$row" | cut -f9)"  = "340" ]  || fail "cost.tsv: out_tokens column"
[ "$(printf '%s' "$row" | cut -f10)" = "800" ]  || fail "cost.tsv: cache_read column"
[ "$(printf '%s' "$row" | cut -f11)" = "90" ]   || fail "cost.tsv: cache_write column"
grep -q 'in_tokens' "$TMP/kb/.ingest/cost.tsv" || fail "cost.tsv: header not describing token columns"

# A model the CLI cannot price still lands a row: usage is what keeps the ledger meaningful
# on a gateway or a local model.
out="$(FAKE_NO_COST=1 lib 'kb_agent_init; kb_agent_run "p" >/dev/null; kb_cost_record 1 read')"
row="$(grep -v '^#' "$TMP/kb/.ingest/cost.tsv" | tail -1)"
[ -z "$(printf '%s' "$row" | cut -f2)" ] || fail "cost.tsv: priceless run should leave cost empty"
[ "$(printf '%s' "$row" | cut -f8)" = "1200" ] || fail "cost.tsv: priceless run lost its token counts"
printf '%s\n' "$out" | grep -q "no price reported" || fail "priceless run summary wrong: $out"
printf '%s\n' "$out" | grep -q "1200 in / 340 out" || fail "priceless run did not report usage: $out"

# An old seven-column ledger keeps its rows and gains the new header.
printf '# Columns: date\tcost_usd\tturns\tduration_ms\tsources\tmode\tmodel\n2026-01-01\t1.5\t2\t10\t1\tread\tm\n' \
  > "$TMP/kb/.ingest/cost.tsv"
lib 'kb_agent_init; kb_agent_run "p" >/dev/null; kb_cost_record 1 read >/dev/null'
grep -q 'in_tokens' "$TMP/kb/.ingest/cost.tsv" || fail "old ledger header not upgraded"
grep -q '^2026-01-01' "$TMP/kb/.ingest/cost.tsv" || fail "old ledger rows lost on upgrade"

n_before="$(grep -vc '^#' "$TMP/kb/.ingest/cost.tsv")"
KB_AGENT=hermes lib 'kb_agent_init; kb_agent_run "p" >/dev/null; kb_cost_record 0 query >/dev/null'
n_after="$(grep -vc '^#' "$TMP/kb/.ingest/cost.tsv")"
[ "$n_before" = "$n_after" ] || fail "cost.tsv: hermes (no cost, no usage) must not append a row"

# --- scripts/query end to end via hermes --------------------------------------------------
out="$(cd "$TMP/kb" && KB_AGENT=hermes ./scripts/query "what rate?" 2>/dev/null)"
printf '%s\n' "$out" | grep -q "hermes reply" || fail "query: should print the hermes reply"
printf '%s\n' "$out" | grep -q "via hermes" || fail "query: should name the agent it used"
[ "$(sed -n 1p "$FAKE_LOG")" = "-z" ] || fail "query: should call hermes -z"
grep -q "^Question: what rate?" "$FAKE_LOG" || fail "query: prompt should carry the question"

out="$(cd "$TMP/kb" && KB_AGENT=hermes ./scripts/query --dry-run "q" 2>/dev/null)"
printf '%s\n' "$out" | grep -q "hermes -z" || fail "query --dry-run: should show the hermes command"

# --- scripts/ingest end to end via hermes -------------------------------------------------
# A full template copy with one raw source; the fake hermes writes a wiki page so the run counts
# as real work (ingest refuses a no-op) and the manifest advances.
KB2="$TMP/kb2"; mkdir -p "$KB2"
cp -R "$HERE/../." "$KB2/"
printf 'hello\n' > "$KB2/raw/note.txt"
cat > "$TMP/bin/hermes" <<'EOF2'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$FAKE_LOG"
printf -- '---\ntype: source\nprivilege: default\n---\n\n# Note\n\nhello\n' > wiki/note.md
echo "ingested"
EOF2
chmod +x "$TMP/bin/hermes"
out="$(cd "$KB2" && KB_AGENT=hermes ./scripts/ingest --no-sweep --dry-run 2>/dev/null)"
printf '%s\n' "$out" | grep -q "hermes -z" || fail "ingest --dry-run: should show the hermes command"
out="$(cd "$KB2" && KB_AGENT=hermes ./scripts/ingest --no-sweep 2>/dev/null)"; rc=$?
[ "$rc" -eq 0 ] || fail "ingest via hermes: exit $rc"
printf '%s\n' "$out" | grep -q "via hermes" || fail "ingest: should name the agent it used"
[ "$(sed -n 1p "$FAKE_LOG")" = "-z" ] || fail "ingest: should call hermes -z"
grep -q "READ pass" "$FAKE_LOG" || fail "ingest: prompt should be the read-pass prompt"
[ -f "$KB2/wiki/note.md" ] || fail "ingest: agent's page missing"
( cd "$KB2" && bash scripts/scan >/dev/null 2>&1 ); [ $? -eq 0 ] || fail "ingest: manifest should be advanced (scan still pending)"

echo "PASS"
