# agentlib.sh — the KB_AGENT driver: run one headless prompt against whichever agent maintains
# this KB, and record what it cost. Sourced by ingest and query; the caller sets KB_DIR (and
# optionally AUTO=1, WATCH=1) first. The prompts themselves stay in the calling script; this file
# only knows how to hand a prompt to an agent and read the reply back.
#
#   KB_AGENT       claude (default) | hermes | cmd
#   KB_AGENT_BIN   binary override (CLAUDE_BIN is still honoured for claude)
#   KB_MODEL       model override   (CLAUDE_MODEL is still honoured for claude)
#   KB_AGENT_CMD   for KB_AGENT=cmd: a shell command run in KB_DIR with the prompt on stdin
#
# Drivers:
#   claude   claude -p --permission-mode <acceptEdits|bypassPermissions> [--model M] <prompt>
#            Uses --output-format stream-json when jq is present, which gives --watch its live
#            steps and fills the cost fields below. The raw/ guard hook in .claude/settings.json
#            applies.
#   hermes   hermes -z [-m M] <prompt>: one-shot, prints only the final reply, loads the KB's
#            AGENTS.md from the cwd, approvals already bypassed (so --auto changes nothing).
#            With --watch: hermes chat --oneshot --yolo -q <prompt>, which shows tool previews.
#            No cost figure is reported.
#   cmd      sh -c "$KB_AGENT_CMD" with the prompt on stdin, for any other headless agent
#            (e.g. KB_AGENT_CMD='codex exec --full-auto -'). No cost figure is reported.
#
# Only the claude driver has a hook that physically blocks writes under raw/; the other drivers
# rely on the AGENTS.md rule plus whatever sandbox the agent itself provides. kb_agent_init says
# so once per run.
#
# After kb_agent_run: AGENT_COST, AGENT_TURNS, AGENT_DUR, AGENT_MODEL_USED are set (empty when
# the driver cannot report them). kb_cost_record appends a cost.tsv row only when AGENT_COST is
# non-empty. No bash 4 features.

_KB_COST_TSV="$KB_DIR/.ingest/cost.tsv"
_KB_COST_HEADER=$'# cost.tsv — per-run ingest cost ledger (appended by scripts/ingest).\n# Columns: date\tcost_usd\tturns\tduration_ms\tsources\tmode\tmodel'
_KB_TAG="${_KB_TAG:-$(basename "${BASH_SOURCE[1]:-agent}")}"   # message prefix: the calling script's name

# --watch renderer for Claude's stream-json (one readable line per event).
_KB_JQ_FILTER='
def short(s): (s // "" | tostring) as $t | (env.WATCH_MAXLEN // "0" | tonumber) as $m
  | if $m > 0 and ($t|length) > $m then $t[0:$m] + "…" else $t end;
if .type=="system" and .subtype=="init" then "▶ start (model \(.model // "?"))"
elif .type=="assistant" then
  ( .message.content[]? |
    if .type=="tool_use" then "  ⚙ \(.name) \(short(.input.file_path // .input.path // .input.command // .input.pattern // ""))"
    elif .type=="text" and (.text|length>0) then "» \(short(.text))"
    else empty end )
elif .type=="result" then "✓ \(.subtype // "done")\(if .total_cost_usd then "  ($\(.total_cost_usd))" else "" end)"
else empty end
'

# kb_agent_init: resolve AGENT / AGENT_BIN / MODEL / HAVE_JQ from the environment. Exits 1 on an
# unknown KB_AGENT or a cmd driver with no command. Reads AUTO and WATCH (default 0).
kb_agent_init() {
  AGENT="${KB_AGENT:-claude}"
  AUTO="${AUTO:-0}"; WATCH="${WATCH:-0}"
  HAVE_JQ=0; command -v jq >/dev/null 2>&1 && HAVE_JQ=1
  AGENT_COST=""; AGENT_TURNS=""; AGENT_DUR=""; AGENT_MODEL_USED=""
  case "$AGENT" in
    claude)
      AGENT_BIN="${KB_AGENT_BIN:-${CLAUDE_BIN:-claude}}"
      MODEL="${KB_MODEL:-${CLAUDE_MODEL:-claude-opus-4-8}}"
      if [ "$AUTO" -eq 1 ]; then PERM=(--permission-mode bypassPermissions); else PERM=(--permission-mode acceptEdits); fi
      ;;
    hermes)
      AGENT_BIN="${KB_AGENT_BIN:-hermes}"
      MODEL="${KB_MODEL:-}"
      ;;
    cmd)
      AGENT_BIN="sh"
      MODEL="${KB_MODEL:-}"
      [ -n "${KB_AGENT_CMD:-}" ] || { echo "$_KB_TAG: KB_AGENT=cmd needs KB_AGENT_CMD (a shell command that reads the prompt on stdin)." >&2; exit 1; }
      ;;
    *)
      echo "$_KB_TAG: unknown KB_AGENT '$AGENT' (expected claude, hermes, or cmd)." >&2; exit 1;;
  esac
  if [ "$AGENT" != "claude" ]; then
    echo "$_KB_TAG: KB_AGENT=$AGENT; the raw/ write guard is a Claude Code hook, so raw/ is protected by AGENTS.md and the agent's own sandbox only." >&2
  fi
}

# kb_agent_describe: one line showing the command a run would execute (for --dry-run).
kb_agent_describe() {
  case "$AGENT" in
    claude)
      if [ "$HAVE_JQ" -eq 1 ]; then
        printf '%s -p %s --model %s --output-format stream-json --verbose "<%s>"\n' "$AGENT_BIN" "${PERM[*]}" "$MODEL" "$1"
      else
        printf '%s -p %s --model %s "<%s>"   (jq absent: plain text, no cost ledger)\n' "$AGENT_BIN" "${PERM[*]}" "$MODEL" "$1"
      fi
      ;;
    hermes)
      if [ "$WATCH" -eq 1 ]; then printf '%s chat --oneshot --yolo%s -q "<%s>"\n' "$AGENT_BIN" "${MODEL:+ -m $MODEL}" "$1"
      else printf '%s -z%s "<%s>"   (no cost ledger)\n' "$AGENT_BIN" "${MODEL:+ -m $MODEL}" "$1"; fi
      ;;
    cmd)
      printf 'sh -c %s  <<< "<%s>"   (no cost ledger)\n' "'$KB_AGENT_CMD'" "$1";;
  esac
}

# kb_agent_check: exit 127 with a hint when the agent binary is not on PATH.
kb_agent_check() {
  command -v "$AGENT_BIN" >/dev/null 2>&1 \
    || { echo "$_KB_TAG: '$AGENT_BIN' not found. Set KB_AGENT_BIN=/path/to/$AGENT (or choose another KB_AGENT)." >&2; exit 127; }
  [ "$AGENT" = "claude" ] && [ "$HAVE_JQ" -eq 0 ] \
    && echo "$_KB_TAG: jq not found; no live steps or cost ledger (install jq to enable)." >&2
  return 0
}

# kb_agent_run <prompt>: run the prompt in KB_DIR, stream the reply to stdout, return the agent's
# exit code, and set the AGENT_COST / AGENT_TURNS / AGENT_DUR / AGENT_MODEL_USED fields.
kb_agent_run() {
  local prompt="$1" rc=0 stream
  AGENT_COST=""; AGENT_TURNS=""; AGENT_DUR=""; AGENT_MODEL_USED="$MODEL"
  case "$AGENT" in
    claude)
      if [ "$HAVE_JQ" -eq 0 ]; then
        ( cd "$KB_DIR" && "$AGENT_BIN" -p "${PERM[@]}" --model "$MODEL" "$prompt" ); return $?
      fi
      stream="$(mktemp)"
      set +e
      if [ "$WATCH" -eq 1 ]; then
        ( cd "$KB_DIR" && "$AGENT_BIN" -p "${PERM[@]}" --model "$MODEL" --output-format stream-json --verbose "$prompt" ) \
          | tee "$stream" | jq -r "$_KB_JQ_FILTER"
        rc="${PIPESTATUS[0]}"
      else
        ( cd "$KB_DIR" && "$AGENT_BIN" -p "${PERM[@]}" --model "$MODEL" --output-format stream-json --verbose "$prompt" ) > "$stream"
        rc=$?
        jq -r 'select(.type=="result") | .result // empty' "$stream" 2>/dev/null || true
      fi
      set -e
      AGENT_COST="$(jq -r 'select(.type=="result") | .total_cost_usd // empty' "$stream" 2>/dev/null | tail -1 || true)"
      AGENT_TURNS="$(jq -r 'select(.type=="result") | .num_turns // empty'      "$stream" 2>/dev/null | tail -1 || true)"
      AGENT_DUR="$(jq -r 'select(.type=="result") | .duration_ms // empty'      "$stream" 2>/dev/null | tail -1 || true)"
      local used
      used="$(jq -r 'select(.type=="system" and .subtype=="init") | .model // empty' "$stream" 2>/dev/null | head -1 || true)"
      [ -n "$used" ] && AGENT_MODEL_USED="$used"
      rm -f "$stream"
      ;;
    hermes)
      # bash 3.2: expanding an empty array under set -u is an error, hence the ${a[@]+...} form
      local margs=()
      [ -n "$MODEL" ] && margs=(-m "$MODEL")
      set +e
      if [ "$WATCH" -eq 1 ]; then
        ( cd "$KB_DIR" && "$AGENT_BIN" chat --oneshot --yolo ${margs[@]+"${margs[@]}"} -q "$prompt" )
      else
        ( cd "$KB_DIR" && "$AGENT_BIN" -z ${margs[@]+"${margs[@]}"} "$prompt" )
      fi
      rc=$?
      set -e
      ;;
    cmd)
      set +e
      ( cd "$KB_DIR" && printf '%s' "$prompt" | sh -c "$KB_AGENT_CMD" )
      rc=$?
      set -e
      ;;
  esac
  return "$rc"
}

# kb_cost_record <sources> <mode>: append a cost.tsv row from the last run (when the driver
# reported a cost) and print a one-line summary. Silent no-op otherwise.
kb_cost_record() {
  if [ -z "$AGENT_COST" ]; then
    [ "$AGENT" = "claude" ] && [ "$HAVE_JQ" -eq 1 ] && echo "$_KB_TAG: no cost field in result; cost ledger not updated." >&2
    return 0
  fi
  [ -f "$_KB_COST_TSV" ] || printf '%s\n' "$_KB_COST_HEADER" > "$_KB_COST_TSV"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(date +%F)" "$AGENT_COST" "$AGENT_TURNS" "$AGENT_DUR" "$1" "$2" "$AGENT_MODEL_USED" >> "$_KB_COST_TSV"
  local total
  total="$(awk -F'\t' '$1 !~ /^#/ {s+=$2} END{printf "%.4f", s+0}' "$_KB_COST_TSV")"
  printf '%s: cost $%s (%s turns, %s pass, %s); cumulative $%s\n' "$_KB_TAG" "$AGENT_COST" "${AGENT_TURNS:-?}" "$2" "$AGENT_MODEL_USED" "$total"
}
