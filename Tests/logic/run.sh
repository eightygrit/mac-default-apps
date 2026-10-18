#!/usr/bin/env bash
# Compile Tests/logic/main.swift together with the shared sources and run it.
#
# usage: Tests/logic/run.sh            print failures and a summary; exit status 1 if anything failed
#        VERBOSE=1 Tests/logic/run.sh   also print every passing check
#
# The shared sources (Sources/Common Sources) are what both the app and the CLI compile, so this checks the
# real code, not a copy. It uses swiftc directly: a test target would mean hand-editing two project files.
# The checks only read Launch Services state; the ones that would write use applications that do not exist.
set -eu
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

swiftc -swift-version 5 -module-name SwdaLogicTests -o "$work/logic" \
	"$here/main.swift" "$repo/Sources/Common Sources/"*.swift 2>"$work/compile.log" \
	|| { grep -E 'error' "$work/compile.log" >&2 || cat "$work/compile.log" >&2; exit 1; }
"$work/logic"
