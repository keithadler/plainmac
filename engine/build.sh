#!/bin/bash
# Build the engine as a native library the app links.
#
# This is the same C# that Plain for Windows runs, compiled ahead of time, so the Mac app and the Windows app
# agree about what a .docx is by construction rather than by intention. Nothing of .NET ships in the app: the
# result is one dylib with no runtime to install.
#
#   engine/build.sh [arm64|x64|both]     default: this Mac's architecture
set -euo pipefail
cd "$(dirname "$0")"

# .NET 9 or newer. A Mac with an older SDK on the PATH is the common case, so a 9 beside it wins.
pick() {
  for c in "${DOTNET:-}" "$HOME/.dotnet9/dotnet" "$(command -v dotnet || true)"; do
    [ -n "$c" ] && [ -x "$c" ] || continue
    case "$("$c" --version 2>/dev/null)" in
      9.*|1[0-9].*) echo "$c"; return 0 ;;
    esac
  done
  return 1
}
DOTNET="$(pick)" || {
  echo "The engine needs .NET 9 or newer. Install it, or set DOTNET to one." >&2
  echo "Found: $(command -v dotnet >/dev/null && dotnet --version || echo none)" >&2
  exit 2
}

want="${1:-$( [ "$(uname -m)" = "arm64" ] && echo arm64 || echo x64 )}"
case "$want" in
  arm64) rids="osx-arm64" ;;
  x64)   rids="osx-x64" ;;
  both)  rids="osx-arm64 osx-x64" ;;
  *) echo "usage: engine/build.sh [arm64|x64|both]"; exit 64 ;;
esac

for rid in $rids; do
  "$DOTNET" publish src/Plain.Engine.csproj -c Release -r "$rid" --nologo -v q -o "out-$rid"
  # The linker looks for libNAME.dylib, and the app finds it beside itself at run time.
  mv "out-$rid/PlainEngine.dylib" "out-$rid/libPlainEngine.dylib"
  install_name_tool -id "@rpath/libPlainEngine.dylib" "out-$rid/libPlainEngine.dylib"
done

rm -rf out && mkdir -p out
if [ "$want" = "both" ]; then
  # One library that runs on both kinds of Mac, which is what the DMG ships.
  lipo -create -output out/libPlainEngine.dylib out-osx-arm64/libPlainEngine.dylib out-osx-x64/libPlainEngine.dylib
  lipo -info out/libPlainEngine.dylib
else
  cp "out-osx-$( [ "$want" = "arm64" ] && echo arm64 || echo x64 )/libPlainEngine.dylib" out/
fi

ls -lh out/libPlainEngine.dylib | awk '{print $5, $9}'
