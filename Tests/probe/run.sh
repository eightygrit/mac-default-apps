#!/usr/bin/env bash
# Compile and run one read-only probe.
#
# usage: Tests/probe/run.sh <name> [arguments...]      e.g. Tests/probe/run.sh roles
#        Tests/probe/run.sh --list
#
# A probe is Tests/probe/<name>.swift. It never changes a default handler. Compiler output (mostly
# deprecation warnings, because the probes call the legacy functions on purpose) is shown only when
# compiling fails.
set -eu
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "${1:-}" = "--list" ] || [ $# -eq 0 ]; then
	echo "probes:"
	for f in "$here"/*.swift; do basename "$f" .swift; done | sed 's/^/  /'
	echo "  fixups   (run Tests/probe/fixups.sh instead)"
	[ $# -eq 0 ] && exit 2 || exit 0
fi

name="$1"; shift
src="$here/$name.swift"
[ -f "$src" ] || { echo "no such probe: $name (try --list)" >&2; exit 2; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
swiftc -O -swift-version 5 -o "$work/$name" "$src" 2>"$work/compile.log" || { cat "$work/compile.log" >&2; exit 1; }
"$work/$name" ${1+"$@"}
