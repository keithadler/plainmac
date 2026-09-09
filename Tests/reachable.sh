#!/usr/bin/env bash
# Every operation the engine can do has to be reachable from the window.
#
# This exists because the same mistake happened four times: code that worked, wired to nothing. Replace-all said
# it had changed things and saved nothing. Inserting a link wrote it and then a stale model wrote over it. The
# update check found a newer version and told nobody. And twenty-one of the engine's operations had no way to
# them in the window at all, while the tests were green, because every test exercised the engine and none of them
# exercised the path from a person to the engine.
#
# A unit test cannot see this. What can see it is asking, of every operation the engine knows: is there anywhere
# in the window that names it? That is a crude question and it catches the exact thing that keeps happening.
set -uo pipefail
cd "$(dirname "$0")/.."

fail=0

# What the engine answers to, read from the engine rather than from a list somebody has to remember to update.
# Only the switch inside Run: the operations themselves. Other switches deeper in the file have cases of their
# own ("rename", "add") that are arguments to an operation, not operations.
ops=$(sed -n '/return op switch/,/^        };$/p' engine/src/Do.cs \
      | grep -oE '"[a-z]+" =>' | grep -oE '"[a-z]+"' | tr -d '"' | sort -u)
[ -n "$ops" ] || { echo "could not read the operations out of engine/src/Do.cs"; exit 2; }

# Reached another way on purpose, and said so here rather than left to be rediscovered:
#   setnotes  the deck view edits notes through the ordinary save, not as an operation
#   images    the pictures are listed under their descriptions, which is the same list
elsewhere="setnotes images"

for op in $ops; do
  case " $elsewhere " in *" $op "*) continue ;; esac
  if grep -rq "\"$op\"" Sources/Plain/*.swift 2>/dev/null; then
    :
  else
    echo "FAIL  nothing in the window can reach \"$op\""
    fail=1
  fi
done

# And the other direction: what the window offers has to be something the engine knows, or a menu item does
# nothing and says nothing.
for named in $(grep -ohE 'perform\("[a-z]+"' Sources/Plain/*.swift | grep -oE '"[a-z]+"' | tr -d '"' | sort -u); do
  printf '%s\n' "$ops" | grep -qx "$named" || { echo "FAIL  the window offers \"$named\" and the engine has no such operation"; fail=1; }
done

# The same for what it asks to read.
for named in $(grep -ohE 'Engine\.(ask|run|raw)\("[a-z]+"' Sources/Plain/*.swift | grep -oE '"[a-z]+"' | tr -d '"' | sort -u); do
  printf '%s\n' "$ops" | grep -qx "$named" || { echo "FAIL  the window asks for \"$named\" and the engine has no such operation"; fail=1; }
done

count=$(printf '%s\n' "$ops" | wc -l | tr -d ' ')
[ $fail -eq 0 ] && echo "reachable: all $count operations have a way to them" || echo "reachable: FAILURES"
exit $fail
