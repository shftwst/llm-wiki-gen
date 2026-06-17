# kblib.sh — shared readers for this KB's schema config in .schema/ (page-types.tsv,
# privilege-tiers.tsv). Sourced by lint, classify, and publish. If a config file is missing,
# the shipped defaults below are used, so a KB scaffolded before these files existed still
# works. The caller must set KB_DIR before sourcing this file.
#
# No bash 4 features (associative arrays): everything is awk/cut over the TSVs, bash 3.2 safe.

_KB_TYPES_TSV="$KB_DIR/.schema/page-types.tsv"
_KB_TIERS_TSV="$KB_DIR/.schema/privilege-tiers.tsv"

# Shipped defaults (printf interprets \t and \n, so this file needs no literal tabs).
_kb_default_types() { printf 'source\tsource\nentity\tcontent\nconcept\tcontent\ncomparison\tcontent\nanalysis\tcontent\noverview\tnav\nindex\tnav\n'; }
_kb_default_tiers() { printf 'default\t0\t-\nbusiness-sensitive\t1\tbusiness\npersonal-sensitive\t2\tpersonal\n'; }

_kb_types_raw() { if [ -f "$_KB_TYPES_TSV" ]; then grep -v '^#' "$_KB_TYPES_TSV" | grep -vE '^[[:space:]]*$' || true; else _kb_default_types; fi; }
_kb_tiers_raw() { if [ -f "$_KB_TIERS_TSV" ]; then grep -v '^#' "$_KB_TIERS_TSV" | grep -vE '^[[:space:]]*$' || true; else _kb_default_tiers; fi; }

# Page types -----------------------------------------------------------------
kb_types()        { _kb_types_raw | cut -f1; }
kb_type_valid()   { _kb_types_raw | cut -f1 | grep -qxF "$1"; }        # exit 0 if $1 is a known type
kb_type_class()   { _kb_types_raw | awk -F'\t' -v t="$1" '$1==t{print $2; exit}'; }  # content|source|nav|""

# Privilege tiers ------------------------------------------------------------
kb_tiers()        { _kb_tiers_raw | awk -F'\t' '{print $2"\t"$1}' | sort -n | cut -f2; }  # names, rank order
kb_tier_valid()   { _kb_tiers_raw | cut -f1 | grep -qxF "$1"; }        # exit 0 if $1 is a known tier
kb_top_tier()     { _kb_tiers_raw | awk -F'\t' '{print $2"\t"$1}' | sort -n | tail -1 | cut -f2; }
# Tier carrying a given classify bucket (business|personal); falls back to the most sensitive.
kb_tier_for_bucket() { t="$(_kb_tiers_raw | awk -F'\t' -v b="$1" '$3==b{print $1; exit}')"; [ -n "$t" ] && printf '%s' "$t" || kb_top_tier; }
