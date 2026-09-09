#!/usr/bin/env bash
# The README makes checkable claims. In plainwin one of its download links was four versions out of date for
# months because nothing ever looked at it. So the claims are checked the same way the program's are.
set -uo pipefail
cd "$(dirname "$0")/.."
fail=0
check() { if [ "$2" = "1" ]; then echo "ok    $1"; else echo "FAIL  $1${3:+ - $3}"; fail=1; fi; }

version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist 2>/dev/null)
check "Info.plist has a version" "$([ -n "$version" ] && echo 1 || echo 0)"

stale=$(grep -oE 'Plain-for-Mac-[0-9]+\.[0-9]+\.[0-9]+\.dmg' README.md | grep -v "Plain-for-Mac-$version.dmg" | sort -u)
check "every download link in the README names $version" "$([ -z "$stale" ] && echo 1 || echo 0)" "$(echo $stale)"

for doc in PRIVACY.md CONTRIBUTING.md docs/Help.html docs/Help.es.html LICENSE; do
  check "$doc exists" "$([ -f "$doc" ] && echo 1 || echo 0)"
done

# Every command the program answers to should be findable in the README.
missing=""
for verb in info text cells slides set hidden preserved roundtrip do selftest version help; do
  grep -q "plainmac $verb" README.md || missing="$missing $verb"
done
check "every command is in the README" "$([ -z "$missing" ] && echo 1 || echo 0)" "missing:$missing"

# The engine is a copy; if it has drifted the two programs no longer agree, which is the whole point of it.
if [ -x tests/engine-sync.sh ]; then
  tests/engine-sync.sh >/dev/null 2>&1
  check "the engine has not drifted from plainwin" "$([ $? -eq 0 ] && echo 1 || echo 0)"
fi

[ $fail -eq 0 ] && echo "docs: all passed" || echo "docs: FAILURES"
exit $fail
