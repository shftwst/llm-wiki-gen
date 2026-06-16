#!/usr/bin/env bash
# ingest-new.sh — detect new/changed sources and ingest them via headless Claude Code.
#
#   ./scripts/ingest-new.sh            supervised: scan, then ingest pending (final summary)
#   ./scripts/ingest-new.sh --watch    supervised + live play-by-play of each step
#   ./scripts/ingest-new.sh --dry-run  detect only; print what would run (no LLM, no cost)
#   ./scripts/ingest-new.sh --auto     unattended permissions (for cron / launchd)
#
# Flags combine (e.g. --watch --auto). Set CLAUDE_BIN=/path/to/claude if not on PATH.
#
# Cost: when `jq` is available, each run's cost is appended to .ingest/cost.tsv
# (date, cost_usd, turns, duration_ms, sources, mode) and a cumulative total is printed.
#
# Model: defaults to claude-opus-4-8; override with CLAUDE_MODEL=<id> (e.g. claude-sonnet-4-6).

set -euo pipefail

KB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCAN="$KB_DIR/scripts/scan.sh"
PENDING="$KB_DIR/.ingest/pending.md"
COST_TSV="$KB_DIR/.ingest/cost.tsv"
COST_HEADER=$'# cost.tsv — per-run ingest cost ledger (appended by scripts/ingest-new.sh).\n# Columns: date\tcost_usd\tturns\tduration_ms\tsources\tmode'

DRY_RUN=0; AUTO=0; WATCH=0
for a in "${@:-}"; do
  case "$a" in
    "") ;;
    --dry-run) DRY_RUN=1;;
    --auto)    AUTO=1;;
    --watch)   WATCH=1;;
    *) echo "ingest-new: unknown arg: $a" >&2; exit 1;;
  esac
done

CLAUDE_BIN="${CLAUDE_BIN:-claude}"
MODEL="${CLAUDE_MODEL:-claude-opus-4-8}"   # ingest model; override: CLAUDE_MODEL=claude-sonnet-4-6
if [ "$AUTO" -eq 1 ]; then
  PERM=(--permission-mode bypassPermissions)   # unattended: no prompts
else
  PERM=(--permission-mode acceptEdits)         # supervised: auto-accept edits
fi

HAVE_JQ=0; command -v jq >/dev/null 2>&1 && HAVE_JQ=1

# readable render of the JSON event stream (used for --watch)
JQ_FILTER='
def short(s): (s // "" | tostring | if length>80 then .[0:80]+"…" else . end);
if .type=="system" and .subtype=="init" then "▶ start (model \(.model // "?"))"
elif .type=="assistant" then
  ( .message.content[]? |
    if .type=="tool_use" then "  ⚙ \(.name) \(short(.input.file_path // .input.path // .input.command // .input.pattern // ""))"
    elif .type=="text" and (.text|length>0) then "» \(short(.text))"
    else empty end )
elif .type=="result" then "✓ \(.subtype // "done")\(if .total_cost_usd then "  ($\(.total_cost_usd))" else "" end)"
else empty end
'

PROMPT='Mechanical ingest run. Read .ingest/pending.md and follow this KB'"'"'s CLAUDE.md.
For every source under New and Changed, run the Ingest or Re-ingest workflow; for Removed,
reconcile the affected wiki pages. This is an UNATTENDED ingest: skip the discussion step,
mark anything uncertain or contradictory with a "> [!review]" callout on the page, and
summarize what you did plus every [!review] you raised in the log.md entry. Do NOT edit
.ingest/manifest.tsv and do NOT git commit — the wrapper advances the manifest and commits.'

# --- detect ------------------------------------------------------------------
set +e; bash "$SCAN"; code=$?; set -e
case "$code" in
  0)  echo "ingest-new: nothing pending — done."; exit 0;;
  10) ;;  # pending work exists
  *)  echo "ingest-new: scan failed (exit $code)" >&2; exit "$code";;
esac

if [ "$DRY_RUN" -eq 1 ]; then
  echo "ingest-new: [dry-run] changes pending. Would run, in $KB_DIR:"
  if [ "$HAVE_JQ" -eq 1 ]; then
    echo "  $CLAUDE_BIN -p ${PERM[*]} --model $MODEL --output-format stream-json --verbose \"<ingest prompt>\""
    echo "  → ${WATCH:+live steps, }final summary, and append cost to .ingest/cost.tsv"
  else
    echo "  $CLAUDE_BIN -p ${PERM[*]} --model $MODEL \"<ingest prompt>\"   (jq absent: plain text, no cost ledger)"
  fi
  echo "  then: scripts/scan.sh --accept && git add -A && git commit"
  echo "ingest-new: [dry-run] no changes made."
  exit 0
fi

command -v "$CLAUDE_BIN" >/dev/null 2>&1 \
  || { echo "ingest-new: '$CLAUDE_BIN' not found. Set CLAUDE_BIN=/path/to/claude." >&2; exit 127; }
if [ "$HAVE_JQ" -eq 0 ]; then
  echo "ingest-new: jq not found — no live steps or cost ledger (install jq to enable)." >&2
fi

SOURCES_N="$(grep -cE '^- ' "$PENDING" 2>/dev/null || true)"
echo "ingest-new: ingesting $SOURCES_N pending source(s) via $CLAUDE_BIN ..."

rc=0
if [ "$HAVE_JQ" -eq 1 ]; then
  STREAM_TMP="$(mktemp)"; trap 'rm -f "$STREAM_TMP"' EXIT
  set +e
  if [ "$WATCH" -eq 1 ]; then
    ( cd "$KB_DIR" && "$CLAUDE_BIN" -p "${PERM[@]}" --model "$MODEL" --output-format stream-json --verbose "$PROMPT" ) \
      | tee "$STREAM_TMP" | jq -r "$JQ_FILTER"
    rc="${PIPESTATUS[0]}"
  else
    ( cd "$KB_DIR" && "$CLAUDE_BIN" -p "${PERM[@]}" --model "$MODEL" --output-format stream-json --verbose "$PROMPT" ) > "$STREAM_TMP"
    rc=$?
    jq -r 'select(.type=="result") | .result // empty' "$STREAM_TMP" 2>/dev/null || true
  fi
  set -e

  # --- record cost (the run incurs cost whether or not it fully succeeded) ----
  COST="$(jq -r 'select(.type=="result") | .total_cost_usd // empty' "$STREAM_TMP" 2>/dev/null | tail -1 || true)"
  TURNS="$(jq -r 'select(.type=="result") | .num_turns // empty'      "$STREAM_TMP" 2>/dev/null | tail -1 || true)"
  DUR="$(jq -r 'select(.type=="result") | .duration_ms // empty'      "$STREAM_TMP" 2>/dev/null | tail -1 || true)"
  if [ -n "$COST" ]; then
    [ -f "$COST_TSV" ] || printf '%s\n' "$COST_HEADER" > "$COST_TSV"
    mode="supervised"; [ "$AUTO" -eq 1 ] && mode="auto"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$(date +%F)" "$COST" "${TURNS:-}" "${DUR:-}" "$SOURCES_N" "$mode" >> "$COST_TSV"
    TOTAL="$(awk -F'\t' '$1 !~ /^#/ {s+=$2} END{printf "%.4f", s+0}' "$COST_TSV")"
    printf 'ingest-new: cost $%s (%s turns, %s source(s)) — cumulative $%s\n' "$COST" "${TURNS:-?}" "$SOURCES_N" "$TOTAL"
  else
    echo "ingest-new: no cost field in result — cost ledger not updated." >&2
  fi
else
  ( cd "$KB_DIR" && "$CLAUDE_BIN" -p "${PERM[@]}" --model "$MODEL" "$PROMPT" )
  rc=$?
fi

if [ "$rc" -ne 0 ]; then
  echo "ingest-new: ingest run failed (exit $rc) — manifest NOT advanced, no commit." >&2
  exit "$rc"
fi

# Guard against silent no-ops: a clean exit (incl. a *cancelled* run — Claude Code exits 0
# on cancel) with no changes to wiki/ or log.md means nothing was actually ingested. Don't
# advance the baseline on a lie — leave the source(s) pending so the next run retries.
CHANGED="$(git -C "$KB_DIR" status --porcelain -- wiki log.md 2>/dev/null || true)"
if [ -z "$CHANGED" ]; then
  echo "ingest-new: the run produced NO changes to wiki/ or log.md — nothing was ingested." >&2
  echo "ingest-new: baseline NOT advanced; source(s) stay pending. (Run cancelled, or raw/ content unreadable?)" >&2
  exit 3
fi

echo "ingest-new: advancing manifest baseline + committing ..."
"$SCAN" --accept >/dev/null
( cd "$KB_DIR" && git add -A && git commit -q -m "Mechanical ingest ($(date +%F))" ) \
  || echo "ingest-new: nothing to commit."
echo "ingest-new: done."
