#!/usr/bin/env bash
# Compares the part of swda's output that is the same on every Mac with the recordings kept in Tests/contract. READ-ONLY, and the
# one golden check that can pass or fail on its own: help and usage text, and the refusals that name nothing installed here.
#
# usage: Tests/contract.sh <path-to-swda>             exit status 1 if any output differs
#        Tests/contract.sh <path-to-swda> --record    replace the recordings; do it only for a change of output made on purpose,
#                                                     and say so in the commit message
#
# Everything else Tests/golden.sh records depends on what is installed, so it is compared build against build, not against a file.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
swda="${1:?path to swda}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

"$here/golden.sh" "$swda" "$work/now" --contract-only >/dev/null || exit 2
# Recorded as .txt: a global git ignore for *.out (a common one) would keep the recordings out of the repository.
for recording in "$work/now"/*.out; do mv "$recording" "${recording%.out}.txt"; done
if [ "${2:-}" = "--record" ]; then
	rm -rf "$here/contract"
	cp -R "$work/now" "$here/contract"
	echo "recorded $(ls "$here/contract" | wc -l | tr -d ' ') cases in Tests/contract"
	exit 0
fi
[ -d "$here/contract" ] || { echo "Tests/contract.sh: no recordings; run it with --record" >&2; exit 2; }
if diff -ru "$here/contract" "$work/now"; then
	echo "$(ls "$here/contract" | wc -l | tr -d ' ') of $(ls "$here/contract" | wc -l | tr -d ' ') contract cases match"
else
	echo "contract: the output differs from Tests/contract" >&2
	exit 1
fi
