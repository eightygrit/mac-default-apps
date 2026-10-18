#!/usr/bin/env bash
# GUARDED. This script CHANGES real default handlers on the Mac it runs on, and then puts them back.
# Run it only while you are sitting at the machine: macOS may ask for consent in a dialog, and one case
# needs you to decline it.
#
# usage: Tests/write-roundtrip.sh [--i-understand] <path-to-swda> [case ...]
#
#   without --i-understand   dry run: choose the subjects, print the plan, change nothing
#   with --i-understand      run the cases (after a final "yes")
#
# cases (default: all, in this order):
#   scheme             a URL scheme that has two or more handlers
#   uti                a UTI, role-less ("All Roles"), whose Viewer and Editor defaults are the same application
#   uti-role           the same, with --role Viewer: Editor and Shell must not move
#   decline            like uti, but YOU decline the system prompt: the default must stay, swda must say canceled
#   extension          --extension with a known extension: the default of its UTI must change
#   unknown-extension  --extension with an invented one: does a real file with that extension follow?
#   none               Do Nothing ("None") as the handler of a UTI (ThisAppDoesNothing.app must sit next to swda)
#
# Every case remembers the original handler, changes it, reads it back (up to 20 s), reads it again after 5 s
# (the change must stay: see upstream issue 72), restores the original and reads that back. A trap restores
# whatever is still changed when the script is interrupted. http, https, ftp, file, mailto and public.html
# are never used: changing one of them can change others, and the original of a role-less change is not
# always recoverable exactly.
#
# Overrides: SWDA_TEST_SCHEME, SWDA_TEST_UTI (space-separated candidates), SWDA_TEST_APP (path of the new handler).
set -u

dry=1
if [ "${1:-}" = "--i-understand" ]; then dry=0; shift; fi
SWDA="${1:-}"
if [ -z "$SWDA" ] || [ ! -x "$SWDA" ]; then sed -n '2,25p' "${BASH_SOURCE[0]}"; exit 2; fi
shift
CASES="${*:-scheme uti uti-role decline extension unknown-extension none}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PASS=0; FAIL=0
say()  { printf '%s\n' "$*"; }
ok()   { PASS=$((PASS+1)); say "    PASS  $*"; }
bad()  { FAIL=$((FAIL+1)); say "    FAIL  $*"; }
note() { say "    note  $*"; }

# ------------------------------------------------------------------ restoring
RESTORE=()
restore_all() {
	local i n=${#RESTORE[@]}
	[ "$n" -gt 0 ] || return 0
	for ((i = n - 1; i >= 0; i--)); do
		say "    restoring: ${RESTORE[$i]}"
		eval "${RESTORE[$i]}" >/dev/null 2>&1 || say "    !! the restore command failed: ${RESTORE[$i]}"
	done
	RESTORE=()
}
trap restore_all EXIT
trap 'say; say "interrupted"; exit 130' INT TERM

# -------------------------------------------------------------- read-only helpers
handler()  { "$SWDA" getHandler "$@" 2>/dev/null | head -1; }          # the current default, or nothing
handlers() { "$SWDA" getHandler "$@" --all 2>/dev/null | sort -u; }    # every candidate
snapshot() {                                                           # the three per-role defaults of a UTI
	printf 'viewer=%s editor=%s shell=%s' "$(handler --UTI "$1" --role Viewer)" "$(handler --UTI "$1" --role Editor)" "$(handler --UTI "$1" --role Shell)"
}
pick_other() {   # pick_other <original> <getHandler args...>: another candidate, preferring Apple's own applications
	local orig="$1" list; shift
	list="$(handlers "$@" | grep -vxF -- "$orig")"
	[ -n "$list" ] || return 1
	printf '%s\n' "$list" | grep '^/System/' | head -1 | grep . || printf '%s\n' "$list" | head -1
}
wait_for() {     # wait_for <pattern> <seconds> <getHandler args...>: true once the default matches
	local want="$1" limit="$2" got t=0; shift 2
	while :; do
		got="$(handler "$@")"
		# shellcheck disable=SC2053
		[[ "$got" == $want ]] && return 0
		[ "$t" -ge "$limit" ] && return 1
		sleep 1; t=$((t + 1))
	done
}

# ------------------------------------------------------------------ subjects
UTI_CANDIDATES="${SWDA_TEST_UTI:-public.json public.xml public.yaml public.comma-separated-values-text net.daringfireball.markdown public.log public.c-source}"
SKIP_SCHEMES=" http https ftp file mailto tel sms facetime facetime-audio imessage webcal feed ssh x-apple.systempreferences "

pick_uti() {     # sets UTI ORIG TARGET: Viewer and Editor defaults are one application and another candidate exists
	local u v e
	for u in $UTI_CANDIDATES; do
		v="$(handler --UTI "$u" --role Viewer)"; e="$(handler --UTI "$u" --role Editor)"
		{ [ -n "$v" ] && [ "$v" = "$e" ]; } || continue
		TARGET="${SWDA_TEST_APP:-$(pick_other "$v" --UTI "$u")}"; [ -n "$TARGET" ] || continue
		UTI="$u"; ORIG="$v"; return 0
	done
	return 1
}
pick_scheme() {  # sets SCHEME ORIG TARGET
	local s candidates
	if [ -n "${SWDA_TEST_SCHEME:-}" ]; then candidates="$SWDA_TEST_SCHEME"
	else candidates="$("$SWDA" getSchemes 2>/dev/null | awk -F'\t' 'NF >= 2 && $1 != "" {print $1}')"; fi
	for s in $candidates; do
		case "$SKIP_SCHEMES" in *" $s "*) continue ;; esac
		ORIG="$(handler --URL "$s")"; [ -n "$ORIG" ] || continue
		TARGET="${SWDA_TEST_APP:-$(pick_other "$ORIG" --URL "$s")}"; [ -n "$TARGET" ] || continue
		SCHEME="$s"; return 0
	done
	return 1
}

# ------------------------------------------------------------------ the round trip
# Inputs (globals): LABEL READ_ARGS SET_ARGS ORIG TARGET; optional SET_APP EXPECT DURING SNAPSHOT_UTI SNAPSHOT_STRICT
begin() {        # print the plan line; false in a dry run
	say "  - $LABEL: $ORIG  ->  ${EXPECT:-$TARGET}"
	[ "$dry" = 0 ]
}
exercise() {
	local out rc started elapsed want="${EXPECT:-$TARGET}" before="" during="" after=""
	[ -n "${SNAPSHOT_UTI:-}" ] && before="$(snapshot "$SNAPSHOT_UTI")"
	RESTORE+=("$(printf '%q ' "$SWDA" setHandler "${SET_ARGS[@]}" --app "$ORIG")")
	started=$(date +%s)
	out="$("$SWDA" setHandler "${SET_ARGS[@]}" --app "${SET_APP:-$TARGET}" 2>&1)"; rc=$?
	elapsed=$(( $(date +%s) - started ))
	say "    swda (exit $rc, ${elapsed} s): $out"
	if wait_for "$want" 20 "${READ_ARGS[@]}"; then ok "$LABEL: read-back shows the new handler"
	else bad "$LABEL: the handler is still $(handler "${READ_ARGS[@]}") 20 s after the change"; fi
	sleep 5
	# shellcheck disable=SC2053
	if [[ "$(handler "${READ_ARGS[@]}")" == $want ]]; then ok "$LABEL: still in place after 5 s"
	else bad "$LABEL: did not stay; it is now $(handler "${READ_ARGS[@]}")"; fi
	[ -n "${SNAPSHOT_UTI:-}" ] && { during="$(snapshot "$SNAPSHOT_UTI")"; note "roles during the change: $during"; }
	[ -n "${DURING:-}" ] && "$DURING"
	restore_all
	if wait_for "$ORIG" 20 "${READ_ARGS[@]}"; then ok "$LABEL: restored"
	else bad "$LABEL: NOT restored; it is $(handler "${READ_ARGS[@]}"). By hand: swda setHandler ${SET_ARGS[*]} --app \"$ORIG\""; fi
	if [ -n "${SNAPSHOT_UTI:-}" ]; then
		after="$(snapshot "$SNAPSHOT_UTI")"
		if [ "$after" = "$before" ]; then ok "$LABEL: all three roles are back as they were"
		elif [ "${SNAPSHOT_STRICT:-0}" = 1 ]; then bad "$LABEL: roles differ from before: [$before] now [$after]"
		else note "roles differ from before (a role-less change cannot restore each role separately): [$before] now [$after]"; fi
	fi
}
reset_case() { LABEL=""; READ_ARGS=(); SET_ARGS=(); ORIG=""; TARGET=""; SET_APP=""; EXPECT=""; DURING=""; SNAPSHOT_UTI=""; SNAPSHOT_STRICT=0; }

# ------------------------------------------------------------------ cases
case_scheme() {
	pick_scheme || { note "no scheme with a second handler found; try SWDA_TEST_SCHEME"; return; }
	LABEL="scheme $SCHEME"; READ_ARGS=(--URL "$SCHEME"); SET_ARGS=(--URL "$SCHEME")
	begin && exercise
}
case_uti() {
	pick_uti || { note "no UTI with one Viewer/Editor default and a second handler; try SWDA_TEST_UTI"; return; }
	LABEL="uti $UTI"; READ_ARGS=(--UTI "$UTI"); SET_ARGS=(--UTI "$UTI"); SNAPSHOT_UTI="$UTI"
	begin && exercise
}
check_other_roles() {
	local now_editor now_shell
	now_editor="$(handler --UTI "$UTI" --role Editor)"; now_shell="$(handler --UTI "$UTI" --role Shell)"
	if [ "$now_editor" = "$BEFORE_EDITOR" ]; then ok "uti-role: Editor did not move"; else bad "uti-role: Editor moved to $now_editor"; fi
	if [ "$now_shell" = "$BEFORE_SHELL" ]; then ok "uti-role: Shell did not move"; else bad "uti-role: Shell moved to $now_shell"; fi
}
case_uti_role() {
	pick_uti || { note "no suitable UTI; try SWDA_TEST_UTI"; return; }
	BEFORE_EDITOR="$(handler --UTI "$UTI" --role Editor)"; BEFORE_SHELL="$(handler --UTI "$UTI" --role Shell)"
	LABEL="uti-role $UTI (Viewer)"; READ_ARGS=(--UTI "$UTI" --role Viewer); SET_ARGS=(--UTI "$UTI" --role Viewer)
	SNAPSHOT_UTI="$UTI"; SNAPSHOT_STRICT=1; DURING=check_other_roles
	begin && exercise
}
case_decline() {
	local out rc now
	pick_uti || { note "no suitable UTI; try SWDA_TEST_UTI"; return; }
	LABEL="decline $UTI"
	begin || return
	say "    >>> If macOS asks for permission now, click Cancel / \"Don't Allow\"."
	RESTORE+=("$(printf '%q ' "$SWDA" setHandler --UTI "$UTI" --app "$ORIG")")
	out="$("$SWDA" setHandler --UTI "$UTI" --app "$TARGET" 2>&1)"; rc=$?
	say "    swda (exit $rc): $out"
	sleep 3
	now="$(handler --UTI "$UTI")"
	if [ "$now" = "$ORIG" ]; then ok "decline: the handler did not change"; RESTORE=()
	else bad "decline: the handler is now $now (no prompt appeared, or it was accepted); restoring"; restore_all; fi
	if printf '%s' "$out" | grep -qi 'cancel'; then ok "decline: swda reported the cancellation"
	else note "decline: swda did not say 'canceled' (only a build with asynchronous setters can tell; older ones report success regardless)"; fi
}
case_extension() {
	local pair ext u v e found=0
	for pair in json:public.json xml:public.xml md:net.daringfireball.markdown csv:public.comma-separated-values-text; do
		ext="${pair%%:*}"; u="${pair#*:}"
		v="$(handler --UTI "$u" --role Viewer)"; e="$(handler --UTI "$u" --role Editor)"
		{ [ -n "$v" ] && [ "$v" = "$e" ] && [ "$v" = "$(handler --extension "$ext")" ]; } || continue
		TARGET="${SWDA_TEST_APP:-$(pick_other "$v" --extension "$ext")}"; [ -n "$TARGET" ] || continue
		found=1; break
	done
	[ "$found" = 1 ] || { note "no known extension with a second handler found"; return; }
	ORIG="$v"; UTI="$u"
	LABEL="extension .$ext ($u)"; READ_ARGS=(--UTI "$u"); SET_ARGS=(--extension "$ext"); SNAPSHOT_UTI="$u"
	begin && exercise
}
case_unknown_extension() {
	local ext=swdatestext tmp file before after target
	tmp="$(mktemp -d)"; file="$tmp/sample.$ext"; : > "$file"
	before="$("$here/probe/run.sh" openswith "$file")"
	target="${SWDA_TEST_APP:-/System/Applications/TextEdit.app}"
	case "$before" in *"opensWith=$target") target=/System/Applications/Preview.app ;; esac
	say "  - unknown extension .$ext: a real file would open with [${before##*opensWith=}], set $target"
	say "    before: $before"
	if [ "$dry" = 0 ]; then
		local out rc
		out="$("$SWDA" setHandler --extension "$ext" --app "$target" 2>&1)"; rc=$?
		say "    swda (exit $rc): $out"
		sleep 3
		after="$("$here/probe/run.sh" openswith "$file")"
		say "    after:  $after"
		if [ "$after" != "$before" ]; then ok "unknown-extension: the handler reaches a real .$ext file"
		else bad "unknown-extension: a real .$ext file is not affected (the extension resolved to a dynamic type that real files do not use)"; fi
		note "this script cannot remove that handler again; it applies only to files named *.$ext"
	fi
	rm -rf "$tmp"
}
case_none() {
	pick_uti || { note "no suitable UTI; try SWDA_TEST_UTI"; return; }
	if [ ! -d "$(dirname "$SWDA")/ThisAppDoesNothing.app" ] && [ ! -d /Applications/ThisAppDoesNothing.app ]; then
		note "ThisAppDoesNothing.app is neither next to swda nor in /Applications; the case may fail for that reason"
	fi
	LABEL="none $UTI"; READ_ARGS=(--UTI "$UTI"); SET_ARGS=(--UTI "$UTI"); SET_APP="None"; EXPECT="*/ThisAppDoesNothing.app"
	begin && exercise
}

# ------------------------------------------------------------------ main
if [ "$dry" = 0 ]; then
	cat <<BANNER
This changes real default handlers on this Mac, then restores them.
Cases: $CASES
Have the machine in front of you: macOS may ask permission, and 'decline' needs you to say no.
BANNER
	printf 'Type yes to continue: '
	read -r answer </dev/tty
	[ "$answer" = yes ] || { say "not confirmed; nothing was changed"; exit 3; }
fi

for c in $CASES; do
	say; say "case: $c"
	reset_case
	case "$c" in
		scheme)            case_scheme ;;
		uti)               case_uti ;;
		uti-role)          case_uti_role ;;
		decline)           case_decline ;;
		extension)         case_extension ;;
		unknown-extension) case_unknown_extension ;;
		none)              case_none ;;
		*) say "  unknown case: $c" ;;
	esac
done

say; say "$PASS passed, $FAIL failed"
[ "$dry" = 1 ] && say "(dry run: nothing was changed; add --i-understand to run the cases)"
[ "$FAIL" = 0 ]
