#!/usr/bin/env bash
# What the CLI does when the system no longer has the three per-role functions, simulated with SWDA_NO_LEGACY_ROLES=1.
#
# usage: Tests/legacy-roles-off.sh <path-to-swda>
#
# Naming a role (--role Viewer|Editor|Shell) must be refused with one message and exit status 1, and everything that
# asks for no role in particular must answer exactly as it does with the functions present.
#
# Nothing is written. The refused setHandler calls are stopped by the CLI before they reach Launch Services, and
# with the switch set the role-setting function cannot be found, so it could not write even if the CLI let one through.
# The script reads the viewer default of public.html before and after, as proof.
set -u
SWDA="${1:?path to swda}"
checks=0; failures=0
err="$(mktemp)"; trap 'rm -f "$err"' EXIT
MESSAGE="SwiftDefaultApps ERROR: Per-role defaults are not available on this version of macOS."

ok()   { checks=$((checks+1)); echo "ok    $1"; }
fail() { checks=$((checks+1)); failures=$((failures+1)); echo "FAIL  $1"; [ $# -lt 2 ] || printf '        %s\n' "${@:2}"; }

# refused <args...>: with the switch set the command prints nothing, says MESSAGE on stderr and exits 1.
refused() {
	local out rc
	out="$(SWDA_NO_LEGACY_ROLES=1 "$SWDA" "$@" 2>"$err")"; rc=$?
	if [ "$rc" = 1 ] && [ -z "$out" ] && [ "$(cat "$err")" = "$MESSAGE" ]; then ok "refused: swda $*"
	else fail "refused: swda $*" "exit=$rc stdout=[$out] stderr=[$(cat "$err")]"; fi
}

# unchanged <args...>: the switch changes neither the output nor the exit status. Lists are sorted first.
unchanged() {
	local with without
	with="$({ SWDA_NO_LEGACY_ROLES=1 "$SWDA" "$@" 2>&1; echo "exit=$?"; } | sort)"
	without="$({ "$SWDA" "$@" 2>&1; echo "exit=$?"; } | sort)"
	if [ "$with" = "$without" ]; then ok "unchanged: swda $*"
	else fail "unchanged: swda $*" "$(diff <(echo "$without") <(echo "$with") | head -6)"; fi
}

viewer_before="$("$SWDA" getHandler --UTI public.html --role Viewer 2>&1)"

refused getHandler --UTI public.html --role Viewer
refused getHandler --UTI public.html --role Editor --all
refused getHandler --UTI public.html --role Shell
refused getHandler --extension html --role Viewer
refused getHandler --UTI public.html --role nonsense           # falls back to Viewer+Editor, which names a role
refused setHandler --UTI public.html --app TextEdit --role Viewer
refused setHandler --extension html --app TextEdit --role Shell

unchanged getHandler --UTI public.html
unchanged getHandler --UTI public.html --role All
unchanged getHandler --UTI public.html --all
unchanged getHandler --UTI com.adobe.pdf --role All --all
unchanged getHandler --extension html
unchanged getHandler --URL http --role Viewer                  # a role means nothing for a scheme
unchanged getHandler --browser
unchanged getUTIs
unchanged getSchemes

viewer_after="$("$SWDA" getHandler --UTI public.html --role Viewer 2>&1)"
if [ "$viewer_before" = "$viewer_after" ]; then ok "the viewer default of public.html is untouched"
else fail "the viewer default of public.html changed" "before: $viewer_before" "after:  $viewer_after"; fi

echo "$((checks-failures)) of $checks checks passed"
[ "$failures" = 0 ]
