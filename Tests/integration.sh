#!/usr/bin/env bash
# End to end through the command line, on copies so a demo file is never written over.
#
#   tests/integration.sh [path/to/Plain]
set -uo pipefail
cd "$(dirname "$0")/.."

BIN="${1:-.build/release/Plain}"
[ -x "$BIN" ] || BIN="build/Plain for Mac.app/Contents/MacOS/Plain"
[ -x "$BIN" ] || { echo "no build: run ./build-app.sh"; exit 2; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cp docs/demo/quarter.xlsx "$work/book.xlsx"
cp docs/demo/review.docx  "$work/doc.docx"
cp docs/demo/woodland.pptx "$work/deck.pptx"

fail=0
check() {
  local what="$1"; shift
  if "$@" >/dev/null 2>&1; then echo "ok    $what"; else echo "FAIL  $what"; fail=1; fi
}
says() {
  local what="$1" want="$2"; shift 2
  local got; got="$("$@" 2>&1)"
  if printf '%s' "$got" | grep -q -- "$want"; then echo "ok    $what"
  else echo "FAIL  $what (wanted \"$want\", got \"$(printf '%s' "$got" | head -1)\")"; fail=1; fi
}

says "it says which version it is"            "Plain for Mac"  "$BIN" version
says "and which engine is inside it"          "engine"         "$BIN" version

says "a workbook is a workbook"               "spreadsheet"    "$BIN" info "$work/book.xlsx"
says "a document is a document"               "document"       "$BIN" info "$work/doc.docx"
says "a presentation is a presentation"       "presentation"   "$BIN" info "$work/deck.pptx"

says "the promise holds on a workbook"        "identical"      "$BIN" roundtrip "$work/book.xlsx"
says "and on a document"                      "identical"      "$BIN" roundtrip "$work/doc.docx"
says "and on a presentation"                  "identical"      "$BIN" roundtrip "$work/deck.pptx"

says "cells come out with their references"   "A1"             "$BIN" cells "$work/book.xlsx"
says "the text of a document comes out"       "Woodland"       "$BIN" text "$work/doc.docx"
says "and the speaker notes with the slides"  "twenty minutes" "$BIN" slides "$work/deck.pptx"

"$BIN" set "$work/book.xlsx" B5 25000 --sheet Summary >/dev/null 2>&1
says "a cell can be changed"                  "25,000"         "$BIN" cells "$work/book.xlsx" --sheet Summary
# The Windows app once wrote a switch's value into the cell. It must never happen here.
if "$BIN" cells "$work/book.xlsx" --sheet Summary 2>/dev/null | grep -q "25000 Summary\|25,000 Summary"; then
  echo "FAIL  a switch's value must not end up in the cell"; fail=1
else
  echo "ok    a switch's value does not end up in the cell"
fi
says "and the file still opens afterwards"    "spreadsheet"    "$BIN" info "$work/book.xlsx"

says "what a file carries can be listed"      ""               "$BIN" preserved "$work/deck.pptx"
says "a file that is not there says so"       "not there"      "$BIN" info "$work/nothing.docx"
says "asking a document for cells is refused" "spreadsheet"    "$BIN" cells "$work/doc.docx"

# Every operation the app can do, run one after another on the same files. The point is not each one on its own;
# it is that after all of them the files still open and still come back byte for byte.
op() { "$BIN" do "$@" >/dev/null 2>&1; }

op sort   --path "$work/book.xlsx" --sheet Detail  --left 1 --top 2 --right 5 --bottom 8 --by 4
op freeze --path "$work/book.xlsx" --sheet Summary --rows 4 --columns 1
op colour --path "$work/book.xlsx" --sheet Summary --left 1 --top 4 --right 5 --bottom 4 --fill FFF3C4
op border --path "$work/book.xlsx" --sheet Summary --left 1 --top 4 --right 5 --bottom 4 --style medium
op align  --path "$work/book.xlsx" --sheet Summary --left 1 --top 4 --right 5 --bottom 4 --horizontal center
op format --path "$work/book.xlsx" --sheet Summary --left 2 --top 5 --right 3 --bottom 10 --code "#,##0"
op weight --path "$work/book.xlsx" --sheet Summary --left 1 --top 4 --right 5 --bottom 4 --bold true
op width  --path "$work/book.xlsx" --sheet Summary --column 1 --fit true
op height --path "$work/book.xlsx" --sheet Summary --row 4 --points 26
op sheet  --path "$work/book.xlsx" --how add --name Extra
op grid   --path "$work/book.xlsx" --sheet Summary --how insertrow --at 3

op band     --path "$work/doc.docx" --header true --text "Pine Street Holdings, in confidence"
op tablerow --path "$work/doc.docx" --how add --table 0 --row 1
op link     --path "$work/doc.docx" --block 2 --address https://example.invalid/terms
op replace  --path "$work/doc.docx" --find Woodland --with Oakfield

op slide    --path "$work/deck.pptx" --how add --at 2
op setnotes --path "$work/deck.pptx" --slide 1 --text "Keep it short."

says "a workbook survives every operation"     "spreadsheet"  "$BIN" info "$work/book.xlsx"
says "so does a document"                      "document"     "$BIN" info "$work/doc.docx"
says "so does a presentation"                  "presentation" "$BIN" info "$work/deck.pptx"

says "and the promise still holds on all three" "identical"   "$BIN" roundtrip "$work/book.xlsx"
says "the document too"                         "identical"   "$BIN" roundtrip "$work/doc.docx"
says "and the deck"                             "identical"   "$BIN" roundtrip "$work/deck.pptx"

# The refusals are the product. Sorting rows a formula reads has to be turned down, with a reason.
# On a fresh copy, because the operations above have moved things about and this has to be about the refusal.
# A refusal exits 2, and with pipefail a pipeline takes that as its own status, so the output is captured
# first rather than piped: otherwise the check fails precisely because the refusal worked.
cp docs/demo/quarter.xlsx "$work/fresh.xlsx"
refusal="$("$BIN" do sort --path "$work/fresh.xlsx" --sheet Summary --left 1 --top 4 --right 5 --bottom 11 --by 1 2>&1 || true)"
if printf '%s' "$refusal" | grep -qi "formula"; then
  echo "ok    sorting rows a formula reads is refused, with a reason"
else
  echo "FAIL  sorting rows a formula reads should have been refused"; fail=1
fi

# An operation that fails must leave the file exactly as it was.
cp "$work/fresh.xlsx" "$work/before.xlsx"
"$BIN" do sort --path "$work/fresh.xlsx" --sheet Summary --left 1 --top 4 --right 5 --bottom 11 --by 1 >/dev/null 2>&1
if cmp -s "$work/before.xlsx" "$work/fresh.xlsx"; then
  echo "ok    a refused operation leaves the file untouched"
else
  echo "FAIL  a refused operation changed the file"; fail=1
fi

# LibreOffice is the independent reader: if it opens them, the files are real.
if command -v soffice >/dev/null 2>&1; then
  rm -rf "$work/lo"; mkdir -p "$work/lo"
  soffice --headless --convert-to pdf --outdir "$work/lo" \
          "$work/book.xlsx" "$work/doc.docx" "$work/deck.pptx" >/dev/null 2>&1
  n=$(ls "$work/lo" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$n" = "3" ]; then echo "ok    LibreOffice opens all three afterwards"
  else echo "FAIL  LibreOffice opened $n of 3 afterwards"; fail=1; fi
fi

"$BIN" selftest >/dev/null 2>&1 && echo "ok    the checks pass" || { echo "FAIL  the checks pass"; fail=1; }

[ $fail -eq 0 ] && echo "integration: all passed" || echo "integration: FAILURES"
exit $fail
