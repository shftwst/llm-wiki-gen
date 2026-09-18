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
_KB_IGNORE_LOCAL="$KB_DIR/.ingestignore.local"
_KB_SENSITIVITY="$KB_DIR/.ingest/sensitivity.tsv"

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
kb_tier_rank()    { _kb_tiers_raw | awk -F'\t' -v t="$1" '$1==t{print $2; exit}'; }         # numeric rank, "" if unknown

# Junk filter (.ingestignore) ------------------------------------------------
# Patterns are loaded once into a variable so per-file checks need no re-read or subprocess.
# Two files: .ingestignore tracks the kit, so additions to its cruft list arrive on upgrade,
# and .ingestignore.local is this KB's own and is never overwritten. Both are read.
_KB_IGNORE_PATS=""
for _f in "$_KB_IGNORE" "$_KB_IGNORE_LOCAL"; do
  [ -f "$_f" ] || continue
  _p="$(grep -vE '^[[:space:]]*(#|$)' "$_f" 2>/dev/null || true)"
  [ -n "$_p" ] || continue
  _KB_IGNORE_PATS="${_KB_IGNORE_PATS:+$_KB_IGNORE_PATS
}$_p"
done

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

# Source sensitivity (.ingest/sensitivity.tsv) -------------------------------
# scripts/classify tags each coverage item with a tier. These readers carry that tag through
# to the pages written from those sources, so a page cannot sit below the sensitivity of what
# it was written from. Shared by lint (which flags) and reclassify (which raises).

# kb_page_sources <page-file>: raw/-relative paths cited in the page's "## Sources" section.
kb_page_sources() {
  sed -n '/^## Sources/,$p' "$1" 2>/dev/null \
    | grep -oE 'raw/[^ )]+' \
    | sed -E 's#^raw/##; s#/+$##' \
    | grep -v '^$' \
    | sort -u || true
}

# kb_source_tier <raw-relative-path>: tiers of every sensitivity row covering this path. A row
# covers a path when the path equals the row's item or sits underneath it, so a page citing one
# file inside a classified group inherits the group's tier. The item's trailing "(note)" is not
# part of the path.
kb_source_tier() {
  [ -f "$_KB_SENSITIVITY" ] || return 0
  awk -F'\t' -v p="$1" '
    /^#/ || /^[[:space:]]*$/ { next }
    { item = $1; sub(/ +\(.*$/, "", item)
      if (p == item || index(p, item "/") == 1) print $2 }' "$_KB_SENSITIVITY"
}

# kb_page_source_tier <page-file>: the highest tier among the page's cited sources, or nothing
# if no cited source is classified. Unclassified sources are silent: absence of a tag is not
# evidence of low sensitivity, and guessing here would produce false errors.
kb_page_source_tier() {
  _best=""; _bestrank=-1
  # read, not word-split: a cited source path may contain spaces.
  while IFS= read -r _p; do
    [ -n "$_p" ] || continue
    for _t in $(kb_source_tier "$_p"); do
      kb_tier_valid "$_t" || continue
      _r="$(kb_tier_rank "$_t")"; [ -n "$_r" ] || continue
      if [ "$_r" -gt "$_bestrank" ]; then _bestrank="$_r"; _best="$_t"; fi
    done
  done < <(kb_page_sources "$1")
  [ -n "$_best" ] && printf '%s' "$_best"
  return 0
}

# kb_page_derived_tier <page-file> <wiki-dir>: the highest tier among the pages listed in this
# page's derived_from. Same rule lint's "privilege inheritance" section checks; lint keeps its
# own loop there so it can name the specific input in the error, this returns just the maximum.
kb_page_derived_tier() {
  _best=""; _bestrank=-1
  for _d in $(grep -E '^derived_from:' "$1" 2>/dev/null | grep -oE '\[\[[^]]+\]\]' | sed -E 's/\[\[([^]|#]+).*/\1/'); do
    _df="$(find "$2" -name "${_d}.md" 2>/dev/null | head -1)"; [ -n "$_df" ] || continue
    _t="$(awk -F': ' '/^privilege:/{sub(/^[^:]*: */,"");print;exit}' "$_df")"
    kb_tier_valid "$_t" || continue
    _r="$(kb_tier_rank "$_t")"; [ -n "$_r" ] || continue
    if [ "$_r" -gt "$_bestrank" ]; then _bestrank="$_r"; _best="$_t"; fi
  done
  [ -n "$_best" ] && printf '%s' "$_best"
  return 0
}

# Living sources (unresolved symlinks) --------------------------------------
# kb_unresolved_sources <raw-dir>: print every symlink under raw/ that does not resolve here,
# at any depth, as a raw/-relative path. A living source points into a mount, so on a machine
# without that mount, or inside a container where it points outside the bind, it dangles.
# `find -L` then walks nothing and the corpus reads as empty rather than unreachable, which is
# the difference between "nothing to do" and "everything is invisible".
#
# At any depth on purpose: sources are usually grouped, so the link sits at raw/<group>/<name>
# rather than directly under raw/, and a top-level-only scan missed exactly those. find without
# -L does not descend through a symlink, so a link that DOES resolve is never walked into and
# the target's own tree is not searched.
kb_unresolved_sources() {
  [ -d "$1" ] || return 0
  find "$1" -type l 2>/dev/null | sort | while IFS= read -r _e; do
    [ -e "$_e" ] && continue
    printf '%s\n' "${_e#"$1"/}"
  done
}

# Change-aimed verification (.ingest/coverage.tsv) ---------------------------
# A synthesised page is a copy of what its sources said on the day they were read. When a source
# moves, the copy may be wrong and nothing about the page knows it. These readers name the pages
# whose sources have moved, so verification can be pointed at what actually changed rather than
# at what merely looks risky. Deterministic: no model decides what is affected.

# kb_source_coverage <raw-relative-path> <field>: the coverage row covering this path, field 3
# (status) or 5 (last_read). A row covers a path when the path equals it or sits underneath it,
# so a page citing one file inside a covered group picks up that group's state.
kb_source_coverage() {
  [ -f "$KB_DIR/.ingest/coverage.tsv" ] || return 0
  awk -F'\t' -v p="$1" -v f="$2" '
    /^#/ || /^[[:space:]]*$/ { next }
    { item = $1; sub(/ +\(.*$/, "", item)
      if (p == item || index(p, item "/") == 1) { print $f; exit } }' "$KB_DIR/.ingest/coverage.tsv"
}

# kb_page_moved_sources <page-file>: for each cited source whose state means this page may now be
# wrong, print "<reason><TAB><source>". Two reasons, and they are different failures:
#   stale     the source changed and has not been re-read, so the page reflects an old version
#   reread    the source was re-read AFTER this page was last verified, so the verification is
#             out of date even though the page may have been updated
# URL-encoded citation links are decoded first, since a wikilink to a real path escapes spaces.
kb_page_moved_sources() {
  _verified="$(awk -F': ' '/^verified:/{sub(/^[^:]*: */,"");print;exit}' "$1" 2>/dev/null)"
  while IFS= read -r _src; do
    [ -n "$_src" ] || continue
    _dec="$(printf '%b' "${_src//%/\\x}")"
    _st="$(kb_source_coverage "$_dec" 3)"
    if [ "$_st" = stale ]; then printf 'stale\t%s\n' "$_dec"; continue; fi
    case "$_verified" in ''|-|false) continue;; esac
    _lr="$(kb_source_coverage "$_dec" 5)"
    case "$_lr" in ''|-) continue;; esac
    [ "$_lr" \> "$_verified" ] && printf 'reread\t%s\n' "$_dec"
  done < <(kb_page_sources "$1")
  return 0
}

# Portable hashing, stat, and source fingerprinting ---------------------------
# Shared by scan (coverage change detection) and citations (dependency change detection) so a
# "fingerprint" means the same thing to both. Moved here from scan; do not redefine per-script.
if command -v shasum >/dev/null 2>&1; then
  kb_hash() { shasum -a 256 | cut -d' ' -f1; }
elif command -v sha256sum >/dev/null 2>&1; then
  kb_hash() { sha256sum | cut -d' ' -f1; }
else
  kb_hash() { echo "kblib: need shasum or sha256sum on PATH" >&2; return 1; }
fi

if stat -f '%z' . >/dev/null 2>&1; then
  kb_statline() { stat -f '%z %m' "$1"; }   # BSD / macOS: <size> <mtime>
else
  kb_statline() { stat -c '%s %Y' "$1"; }   # GNU / Linux
fi

# kb_fingerprint <path>: hash of (path size mtime) for every non-junk file at or under <path>,
# sorted for stability. Follows symlinks so a living-source target is covered. A single file
# fingerprints just itself; a directory fingerprints its whole non-junk subtree. Empty output
# (path resolves to nothing) hashes to a stable constant, so an unreachable source is detectable
# as "no fingerprint" rather than mistaken for unchanged.
kb_fingerprint() {
  find -L "$1" -type f 2>/dev/null | LC_ALL=C sort | while IFS= read -r _f; do
    kb_ignored "${_f##*/}" && continue
    printf '%s %s\n' "$_f" "$(kb_statline "$_f")"
  done | kb_hash
}
