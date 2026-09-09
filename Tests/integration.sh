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

"$BIN" selftest >/dev/null 2>&1 && echo "ok    the checks pass" || { echo "FAIL  the checks pass"; fail=1; }

[ $fail -eq 0 ] && echo "integration: all passed" || echo "integration: FAILURES"
exit $fail
