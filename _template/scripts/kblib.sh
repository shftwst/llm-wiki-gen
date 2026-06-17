# kblib.sh — shared readers for this KB's config: the schema vocabularies in .schema/
# (page-types.tsv, privilege-tiers.tsv) and the .ingestignore junk filter. Sourced by lint,
# classify, publish (schema readers) and scan, sweep (ignore filter); the caller sets KB_DIR
# first. The schema files are required by the readers that use them (the kit scaffolds them); a
# missing one is a hard error at first use, not a silent default. Sourcing kblib has no side
# effect, so scan/sweep can use the ignore filter without needing the schema files.
#
# No bash 4 features (associative arrays): everything is awk/cut over the TSVs, bash 3.2 safe.

_KB_TYPES_TSV="$KB_DIR/.schema/page-types.tsv"
_KB_TIERS_TSV="$KB_DIR/.schema/privilege-tiers.tsv"
_KB_IGNORE="$KB_DIR/.ingestignore"

_kb_req()       { [ -f "$1" ] || { echo "kblib: missing $1" >&2; exit 1; }; }   # hard-error, lazy
_kb_types_raw() { _kb_req "$_KB_TYPES_TSV"; grep -v '^#' "$_KB_TYPES_TSV" | grep -vE '^[[:space:]]*$' || true; }
_kb_tiers_raw() { _kb_req "$_KB_TIERS_TSV"; grep -v '^#' "$_KB_TIERS_TSV" | grep -vE '^[[:space:]]*$' || true; }

# Page types -----------------------------------------------------------------
kb_types()        { _kb_types_raw | cut -f1; }
kb_type_valid()   { _kb_types_raw | cut -f1 | grep -qxF "$1"; }                      # exit 0 if $1 is a known type
kb_type_class()   { _kb_types_raw | awk -F'\t' -v t="$1" '$1==t{print $2; exit}'; }  # content|source|nav|""

# Privilege tiers ------------------------------------------------------------
kb_tiers()        { _kb_tiers_raw | awk -F'\t' '{print $2"\t"$1}' | sort -n | cut -f2; }  # names, rank order
kb_tier_valid()   { _kb_tiers_raw | cut -f1 | grep -qxF "$1"; }                            # exit 0 if $1 is a known tier
kb_top_tier()     { _kb_tiers_raw | awk -F'\t' '{print $2"\t"$1}' | sort -n | tail -1 | cut -f2; }
# Tier carrying a given classify bucket (business|personal); falls back to the most sensitive.
kb_tier_for_bucket() { t="$(_kb_tiers_raw | awk -F'\t' -v b="$1" '$3==b{print $1; exit}')"; [ -n "$t" ] && printf '%s' "$t" || kb_top_tier; }

# Junk filter (.ingestignore) ------------------------------------------------
# Patterns are loaded once into a variable so per-file checks need no re-read or subprocess.
_KB_IGNORE_PATS=""
[ -f "$_KB_IGNORE" ] && _KB_IGNORE_PATS="$(grep -vE '^[[:space:]]*(#|$)' "$_KB_IGNORE" 2>/dev/null || true)"

# kb_ignored <name>: exit 0 if <name> matches a .ingestignore glob (matched against the name,
# gitignore-style; a trailing slash is tolerated so dir-style entries match a bare name).
kb_ignored() {
  [ -n "$_KB_IGNORE_PATS" ] || return 1
  while IFS= read -r pat; do
    pat="${pat%/}"
    case "$1" in $pat) return 0;; esac
  done <<EOF
$_KB_IGNORE_PATS
EOF
  return 1
}

# kb_skip_reason <fullpath>: print why this path should not be promoted as a source, else nothing.
#   "review" — zero-byte regular file: ambiguous and possibly un-synced (a real download that has
#              not arrived). Callers MUST NOT move it; moving can break the pending download.
#              Leave it in place and flag it.
#   "junk"   — non-empty name matching .ingestignore (system cruft, temp/lock files): safe to move.
# Zero-byte wins over a junk-name match, so nothing zero-byte is ever moved. Symlinks are excluded
# from the zero-byte test (mv on a symlink just moves the link; the target stays at its origin).
kb_skip_reason() {
  if [ -f "$1" ] && [ ! -L "$1" ] && [ ! -s "$1" ]; then printf 'review'; return 0; fi
  kb_ignored "${1##*/}" && { printf 'junk'; return 0; }
  return 1
}

# kb_skip <fullpath>: exit 0 if the path should not be promoted as-is (review or junk).
kb_skip() { kb_skip_reason "$1" >/dev/null; }

# kb_dir_has_unsynced <dir>: 0 if the directory holds a non-junk zero-byte file (a likely
# un-synced or failed download). Used by sweep to avoid moving a directory mid-sync. NOTE: this
# only catches truly empty files; a macOS dataless placeholder reports its full size and cannot
# be detected here, so fully download a folder's contents before sweeping it.
kb_dir_has_unsynced() {
  [ -d "$1" ] || return 1
  while IFS= read -r f; do
    kb_ignored "${f##*/}" && continue
    return 0
  done < <(find -L "$1" -type f -size 0 2>/dev/null)
  return 1
}
