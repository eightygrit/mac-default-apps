#!/usr/bin/env bash
# Looks at what the built programs bind to, not at what the sources say. READ-ONLY.
#
# usage: Tests/check-artifacts.sh <swda | Some.app>...
#
# For every program given (an application bundle is checked by its executable) it fails when
#   - the program is linked to a Launch Services function other than the ones listed in ALLOWED below. The deprecated functions
#     were replaced by NSWorkspace, and the three that still do the per-role work, and the private ones, are looked up with dlsym
#     (see LSLegacyRoles.swift and LSPrivate.swift) so that a macOS that removes one cannot stop the program before main;
#     a function that shows up here as an undefined symbol is linked, and that protection is gone;
#   - the program is linked to a networking framework or class. Nothing here talks to a network, and nothing should start to
#     without somebody deciding it should.
set -u

ALLOWED='^_LSRegisterURL$'
NETWORK='CFNetwork|Network\.framework|NetworkExtension|libnetwork|_OBJC_CLASS_\$_NSURLSession|_OBJC_CLASS_\$_NSURLConnection|_getaddrinfo$|_gethostbyname$|_CFHostCreate|_CFSocket|_nw_'

[ "$#" -gt 0 ] || { sed -n '2,12p' "${BASH_SOURCE[0]}"; exit 2; }

failures=0
for given in "$@"; do
	program="$given"
	if [ -d "$given" ]; then
		name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$given/Contents/Info.plist" 2>/dev/null)" \
			|| { echo "FAIL  $given: no CFBundleExecutable in its Info.plist"; failures=$((failures + 1)); continue; }
		program="$given/Contents/MacOS/$name"
	fi
	[ -f "$program" ] || { echo "FAIL  $given: no such program"; failures=$((failures + 1)); continue; }

	linked="$(nm -u "$program" 2>/dev/null | awk '{print $NF}')" \
		|| { echo "FAIL  $given: nm could not read it"; failures=$((failures + 1)); continue; }
	libraries="$(otool -L "$program" | tail -n +2 | awk '{print $1}')"

	problems=""
	launch="$(printf '%s\n' "$linked" | grep -E '^_{1,2}LS' | grep -Ev "$ALLOWED")"
	[ -z "$launch" ] || problems="$problems"$'\n'"    links Launch Services functions that are to be looked up at run time: $(echo $launch)"
	network="$( (printf '%s\n' "$linked"; printf '%s\n' "$libraries") | grep -E "$NETWORK")"
	[ -z "$network" ] || problems="$problems"$'\n'"    links networking: $(echo $network)"

	if [ -z "$problems" ]; then
		echo "ok    $given"
	else
		echo "FAIL  $given$problems"
		failures=$((failures + 1))
	fi
done
[ "$failures" -eq 0 ]
