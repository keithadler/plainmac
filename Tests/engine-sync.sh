#!/usr/bin/env bash
# The engine in this repo is a copy of the one in plainwin, so that a clone of this repo builds on its own.
#
# A copy can drift, and drift is the one thing that would break what this app is for: the Mac and Windows programs
# agreeing about what a .docx is because they run the same code. So the copy is checked against the original.
#
#   tests/engine-sync.sh            check against github.com/keithadler/plainwin
#   tests/engine-sync.sh ../plainwin   check against a clone you already have
#   tests/engine-sync.sh --update ../plainwin   copy the original over this one
set -uo pipefail
cd "$(dirname "$0")/.."

update=false
[ "${1:-}" = "--update" ] && { update=true; shift; }
against="${1:-}"

if [ -z "$against" ]; then
  if [ -d "$HOME/Downloads/plainwin/src/Plain.Core" ]; then
    against="$HOME/Downloads/plainwin"
  else
    against="$(mktemp -d)/plainwin"
    echo "Fetching the original..."
    git clone --depth 1 -q https://github.com/keithadler/plainwin "$against" || {
      echo "Could not fetch plainwin. Pass a path to a clone."; exit 2; }
  fi
fi

original="$against/src/Plain.Core"
[ -d "$original" ] || { echo "No engine at $original"; exit 2; }

if $update; then
  rm -rf engine/Plain.Core
  cp -R "$original" engine/Plain.Core
  rm -rf engine/Plain.Core/bin engine/Plain.Core/obj
  echo "Copied the engine from $original. Rebuild it: engine/build.sh"
  exit 0
fi

# Compare every source file by content. Anything different, missing or extra is drift.
drift=0
while IFS= read -r file; do
  rel="${file#"$original"/}"
  mine="engine/Plain.Core/$rel"
  if [ ! -f "$mine" ]; then
    echo "FAIL  missing here: $rel"
    drift=1
  elif ! cmp -s "$file" "$mine"; then
    echo "FAIL  differs from plainwin: $rel"
    drift=1
  fi
done < <(find "$original" -name '*.cs' -not -path '*/bin/*' -not -path '*/obj/*')

while IFS= read -r file; do
  rel="${file#engine/Plain.Core/}"
  [ -f "$original/$rel" ] || { echo "FAIL  not in plainwin: $rel"; drift=1; }
done < <(find engine/Plain.Core -name '*.cs' -not -path '*/bin/*' -not -path '*/obj/*')

if [ $drift -eq 0 ]; then
  echo "engine: identical to plainwin"
else
  echo "engine: DRIFTED. Fix it in plainwin, then: tests/engine-sync.sh --update"
fi
exit $drift
