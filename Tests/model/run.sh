#!/usr/bin/env bash
# Compile Tests/model/main.swift together with the app's model (AppModel, Catalog) and the shared sources, and run it.
#
# usage: Tests/model/run.sh            print failures and a summary; exit status 1 if anything failed
#        VERBOSE=1 Tests/model/run.sh   also print every passing check
#
# The views are not compiled: the rules worth testing live in the model (what a change is allowed to do, what is shown while it
# waits, how a list is grouped and collapsed), and the model asks the system for nothing it is not given. Every change goes through
# a stand-in (`Catalog.HandlerAccess`), and the program runs with SWDA_READ_ONLY=1 as well, so that nothing here can write a default.
set -eu
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
export SWDA_READ_ONLY=1
if grep -nE 'AppModel\(' "$here/main.swift" | grep -v 'access:'; then
	echo "Tests/model/main.swift: a model above has no stand-in for the system." >&2
	exit 1
fi
if grep -nE 'Catalog\.setDefault\(|Catalog\.settledDefault\(' "$here/main.swift" | grep -v 'real call, guarded'; then
	echo "Tests/model/main.swift: a call above reaches the system and is not marked as guarded." >&2
	exit 1
fi
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

swiftc -swift-version 5 -module-name SwdaModelTests -o "$work/model" \
	"$here/main.swift" "$here/../support/checks.swift" "$repo/Sources/App Sources/Model/"*.swift "$repo/Sources/Common Sources/"*.swift 2>"$work/compile.log" \
	|| { grep -E 'error' "$work/compile.log" >&2 || cat "$work/compile.log" >&2; exit 1; }
"$work/model"
