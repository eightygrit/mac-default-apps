#!/usr/bin/env bash
# Compile Tests/logic/main.swift together with the shared sources and run it.
#
# usage: Tests/logic/run.sh            print failures and a summary; exit status 1 if anything failed
#        VERBOSE=1 Tests/logic/run.sh   also print every passing check
#
# The shared sources (Sources/Common Sources) are what both the app and the CLI compile, so this checks the
# real code, not a copy. It uses swiftc directly: a test target would mean hand-editing two project files.
# The checks only read Launch Services state; the setter checks name things that do not exist, so the code under
# test has to refuse them (see the comment above them in main.swift).
set -eu
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Nothing here may change a default handler or register an application for real. Every check that calls a setter gives it a
# stand-in (the two lines marked "real call, guarded" are the exceptions, and SWDA_READ_ONLY refuses both), and the program runs with SWDA_READ_ONLY=1 as well, so that a call that slipped through is refused by the code itself.
export SWDA_READ_ONLY=1
if grep -nE 'setDefaultHandler\(|ensureRegistered\(' "$here/main.swift" | grep -vE 'setter:|register:|real call, guarded'; then
	echo "Tests/logic/main.swift: a call above has no stand-in; it could write a default handler for real if the code under test were wrong." >&2
	exit 1
fi
repo="$(cd "$here/../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

swiftc -swift-version 5 -module-name SwdaLogicTests -o "$work/logic" \
	"$here/main.swift" "$repo/Sources/Common Sources/"*.swift 2>"$work/compile.log" \
	|| { grep -E 'error' "$work/compile.log" >&2 || cat "$work/compile.log" >&2; exit 1; }
"$work/logic"
