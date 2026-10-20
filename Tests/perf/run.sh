#!/usr/bin/env bash
# Times the loading of each list in the app's model. READ-ONLY.
#
# usage: Tests/perf/run.sh [rounds]      default 3; the first round is the coldest
set -eu
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
export SWDA_READ_ONLY=1
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
swiftc -O -swift-version 5 -module-name SwdaPerf -o "$work/perf" \
	"$here/main.swift" "$repo/Sources/App Sources/Model/"*.swift "$repo/Sources/Common Sources/"*.swift 2>"$work/compile.log" \
	|| { grep -E 'error' "$work/compile.log" >&2 || cat "$work/compile.log" >&2; exit 1; }
"$work/perf" "$@"
