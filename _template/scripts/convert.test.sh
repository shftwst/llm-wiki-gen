#!/usr/bin/env bash
# convert.test.sh — routing, caching and scan detection for scripts/convert, driven by fake
# converter binaries on PATH so the test needs none of pandoc, poppler, xlsx2csv or catdoc.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1" >&2; exit 1; }

KB="$TMP/kb"; BIN="$TMP/bin"
mkdir -p "$KB/scripts" "$KB/raw/sub" "$KB/.ingest" "$BIN"
cp "$HERE/kblib.sh" "$KB/scripts/kblib.sh"
cp "$HERE/convert" "$KB/scripts/convert"
printf '.DS_Store\n' > "$KB/.ingestignore"

# --- fake converters ---------------------------------------------------------
cat > "$BIN/pandoc" <<'EOF'
#!/usr/bin/env bash
out=""; src=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift 2;;
    -t) shift 2;;
    --*) shift;;
    *) src="$1"; shift;;
  esac
done
printf 'PANDOC TEXT FROM %s\n' "$(basename "$src")" > "$out"
EOF
cat > "$BIN/pdftotext" <<'EOF'
#!/usr/bin/env bash
src=""; dest=""
for a in "$@"; do
  case "$a" in -*) ;; *) if [ -z "$src" ]; then src="$a"; else dest="$a"; fi;; esac
done
# A source named like a scan has no text layer, which is what a real scanned PDF looks like.
case "$src" in
  # A real scan: pdftotext emits a form feed per page and no words.
  *scan*) printf '\f\f\f' > "$dest";;
  # A short but genuine text layer, the case a byte-count floor used to misread as a scan.
  *short*) printf 'Invoice 4200\n' > "$dest";;
  *) printf 'PDF TEXT FROM %s, with a full page of words behind it.\n' "$(basename "$src")" > "$dest";;
esac
EOF
cat > "$BIN/xlsx2csv" <<'EOF'
#!/usr/bin/env bash
echo "a,b,c"
EOF
chmod +x "$BIN"/*
export PATH="$BIN:$PATH"

# --- fixture sources ---------------------------------------------------------
printf 'zipbytes' > "$KB/raw/contract.docx"
printf 'pdfbytes' > "$KB/raw/report.pdf"
printf 'pdfbytes' > "$KB/raw/sub/board-scan.pdf"
printf 'pdfbytes' > "$KB/raw/short-invoice.pdf"       # a real text layer, just a short one
printf 'xlsxbytes' > "$KB/raw/cap-table.xlsx"
printf 'docbytes' > "$KB/raw/old-minutes.doc"        # catdoc is NOT faked: must skip, not fail
printf 'plain text already' > "$KB/raw/notes.md"     # no conversion needed
printf 'imagebytes' > "$KB/raw/photo.jpg"            # agent reads directly
printf '' > "$KB/raw/pending.docx"                   # zero-byte: mid-download, leave alone
printf 'junk' > "$KB/raw/.DS_Store"

run() { "$KB/scripts/convert" "$@"; }
idx() { grep -v '^#' "$KB/.ingest/text/index.tsv" 2>/dev/null || true; }
field() { awk -F'\t' -v p="$1" -v n="$2" '$1==p{print $n; exit}' "$KB/.ingest/text/index.tsv"; }

# --- dry run writes nothing --------------------------------------------------
out="$(run --dry-run)"
printf '%s\n' "$out" | grep -q "contract.docx → pandoc" || fail "dry-run routing wrong: $out"
[ -d "$KB/.ingest/text" ] && [ -z "$(idx)" ] || fail "dry-run wrote index rows"
[ -e "$KB/.ingest/text/contract.docx.txt" ] && fail "dry-run wrote output"

# --- real run ----------------------------------------------------------------
out="$(run 2>"$TMP/err")"
grep -q "catdoc not installed" "$TMP/err" || fail "missing tool not warned: $(cat "$TMP/err")"

[ "$(field contract.docx 4)" = pandoc ]      || fail "docx not routed to pandoc"
[ "$(field report.pdf 4)" = pdftotext ]      || fail "pdf not routed to pdftotext"
[ "$(field cap-table.xlsx 4)" = xlsx2csv ]   || fail "xlsx not routed to xlsx2csv"
[ "$(field contract.docx 5)" = ok ]          || fail "docx status not ok"
grep -q "PANDOC TEXT FROM contract.docx" "$KB/.ingest/text/$(field contract.docx 6)" \
  || fail "extracted text not cached"

# a PDF with no text layer is recorded as a scan rather than silently empty
[ "$(field sub/board-scan.pdf 5)" = scanned ] || fail "scanned PDF not flagged (got $(field sub/board-scan.pdf 5))"

# a short document is NOT a scan: an invoice or a cover page has few words and a real text layer
[ "$(field short-invoice.pdf 5)" = ok ] \
  || fail "a short text-layer PDF was called a scan (got $(field short-invoice.pdf 5))"
printf '%s\n' "$out" | grep -q "no text layer" || fail "summary did not mention scans: $out"

# things that need no conversion, or must not be touched, are absent from the index
for p in notes.md photo.jpg pending.docx .DS_Store old-minutes.doc; do
  idx | grep -q "^$p	" && fail "$p should not be in the index"
done

# raw/ is untouched
[ "$(cat "$KB/raw/contract.docx")" = "zipbytes" ] || fail "raw/ source was modified"
[ "$(find "$KB/raw" -type f | wc -l | tr -d ' ')" = 10 ] || fail "raw/ gained or lost files"

# --- re-run is a no-op, and does not duplicate index rows --------------------
before="$(idx | wc -l | tr -d ' ')"
out="$(run 2>/dev/null)"
printf '%s\n' "$out" | grep -q "0 converted" || fail "re-run reconverted: $out"
[ "$(idx | wc -l | tr -d ' ')" = "$before" ] || fail "re-run changed the index"

# --- a changed source reconverts, replacing its row --------------------------
printf 'zipbytes-v2-longer' > "$KB/raw/contract.docx"
run >/dev/null 2>&1
[ "$(idx | grep -c '^contract.docx	')" = 1 ] || fail "changed source duplicated its index row"
[ "$(idx | wc -l | tr -d ' ')" = "$before" ] || fail "index grew on reconversion"

# --- single-path invocation --------------------------------------------------
printf 'zipbytes' > "$KB/raw/sub/addendum.docx"
out="$(run sub/addendum.docx 2>/dev/null)"
printf '%s\n' "$out" | grep -q "sub/addendum.docx → " || fail "single-path convert failed: $out"
[ "$(field sub/addendum.docx 4)" = pandoc ] || fail "single-path row not written"

# --- an extraction that yields nothing is reported, not counted as converted -----------------
printf 'this is not a docx\n' > "$KB/raw/mislabelled.docx"
cat > "$BIN/pandoc" <<'EOF'
#!/usr/bin/env bash
out=""; while [ $# -gt 0 ]; do case "$1" in -o) out="$2"; shift 2;; -t) shift 2;; --*) shift;; *) src="$1"; shift;; esac; done
case "$src" in *mislabelled*) : > "$out";; *) printf 'PANDOC TEXT FROM %s\n' "$(basename "$src")" > "$out";; esac
EOF
chmod +x "$BIN/pandoc"
out="$(run 2>&1)"
printf '%s\n' "$out" | grep -q "yielded NO TEXT" || fail "empty extraction not surfaced: $out"
[ "$(field mislabelled.docx 5)" = empty ] || fail "empty status not recorded"

# --- a living source that does not resolve is called out, not silently skipped ---------------
# find -L walks nothing through a dangling symlink, so the corpus reads as empty rather than
# unreachable. A clean "0 converted" is the worst way to discover a mount is missing.
ln -s /nonexistent/living-mount "$KB/raw/living-mount"
out="$(run --dry-run 2>&1)"
printf '%s\n' "$out" | grep -q "raw/living-mount does not resolve here" || fail "unreachable source not reported: $out"
printf '%s\n' "$out" | grep -q "UNREACHABLE here" || fail "summary did not flag it: $out"
out="$(run 2>&1)"
printf '%s\n' "$out" | grep -q "UNREACHABLE here" || fail "real run did not flag it: $out"

# a symlink that DOES resolve is ordinary and says nothing
mkdir -p "$TMP/real-mount"; printf 'zipbytes' > "$TMP/real-mount/linked.docx"
ln -s "$TMP/real-mount" "$KB/raw/good-mount"
out="$(run 2>&1)"
printf '%s\n' "$out" | grep -q "raw/good-mount does not resolve" && fail "a resolving symlink was flagged"
[ "$(field good-mount/linked.docx 4)" = pandoc ] || fail "content behind a live symlink not converted"

echo "PASS"
