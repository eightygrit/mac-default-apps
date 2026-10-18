#!/usr/bin/env bash
# Build one target into a scratch directory without touching the repository, ~/Applications or any installed copy.
#
# usage: Tests/build-scratch.sh <cli|app|dummy> <output-dir> [deployment-target]
#
#   cli     "SwiftDefaultApps CLI.xcodeproj", target SwiftDefaultApps    -> <output-dir>/products/Release/swda   (target 12.0)
#   app     "SwiftDefaultApps.xcodeproj",     target SwiftDefaultApps    -> .../SwiftDefaultApps.app            (target 13.0)
#   dummy   "AppDoesNothing.xcodeproj",       target ThisAppDoesNothing  -> .../ThisAppDoesNothing.app          (target 12.0)
#
# Prints the result and how many distinct compiler warnings and errors there were. They are also written, one
# per line as "file:line:col: message" with the repository prefix removed, to <output-dir>/diagnostics.txt;
# the full log is <output-dir>/build.log. ARCH overrides the architecture (default: this machine's).
# Compare two builds with: diff <old>/diagnostics.txt <new>/diagnostics.txt
#
# Launch Services registers freshly built applications, which changes what swda lists. When you compare
# golden output, record the reference build and the candidate back-to-back.
set -u
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
kind="${1:-}"; out="${2:-}"
case "$kind" in
	cli)   project="SwiftDefaultApps CLI.xcodeproj"; target=SwiftDefaultApps;   dt="${3:-12.0}" ;;
	app)   project="SwiftDefaultApps.xcodeproj";     target=SwiftDefaultApps;   dt="${3:-13.0}" ;;
	dummy) project="AppDoesNothing.xcodeproj";       target=ThisAppDoesNothing; dt="${3:-12.0}" ;;
	*) sed -n '2,6p' "${BASH_SOURCE[0]}"; exit 2 ;;
esac
[ -n "$out" ] || { sed -n '2,6p' "${BASH_SOURCE[0]}"; exit 2; }
mkdir -p "$out"; out="$(cd "$out" && pwd)"
rm -rf "$out/products" "$out/obj" "$out/build.log" "$out/diagnostics.txt"

cd "$repo" || exit 1
xcodebuild -project "$project" -target "$target" -configuration Release \
	ARCHS="${ARCH:-$(uname -m)}" ONLY_ACTIVE_ARCH=NO MACOSX_DEPLOYMENT_TARGET="$dt" \
	CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO DEVELOPMENT_TEAM="" \
	SYMROOT="$out/products" OBJROOT="$out/obj" >"$out/build.log" 2>&1
rc=$?
grep -E 'BUILD (SUCCEEDED|FAILED)' "$out/build.log" | tail -1
grep -E '^/.*: (warning|error):' "$out/build.log" | sed -E "s#^$repo/##" | sort -u >"$out/diagnostics.txt"
echo "exit=$rc  distinct warnings: $(grep -c ': warning:' "$out/diagnostics.txt")  errors: $(grep -c ': error:' "$out/diagnostics.txt")"
exit $rc
