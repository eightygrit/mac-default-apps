#!/usr/bin/env bash
# Reproduces why LSPrivate.swift and LSLegacyRoles.swift resolve their symbols with dlsym.
# READ-ONLY (builds and runs two throwaway programs in a temporary directory).
#
# usage: Tests/probe/fixups.sh
#
# At a deployment target of macOS 12 or later the linker emits "chained fixups": every symbol a program
# links against is bound when the program LAUNCHES, not when it first calls the function. If a later macOS
# removes one of those functions, a program that merely links against it is killed by dyld before main()
# runs ("Symbol not found", SIGABRT), even when the missing function is never called.
#
# The script stands in for that situation with a tiny dylib that exists in two versions: v1 has two functions,
# v2 has only the first. Two programs are linked against v1:
#   linked   calls both functions directly              (what the code did before: it binds both symbols)
#   dynamic  calls the first directly, the second via dlsym   (what the code does now)
# Then v2 replaces v1, as if an OS update had removed the function.
#
# Expected:  with v1 both programs run.  With v2: linked is aborted at launch (exit 134, 128 + SIGABRT) and
# prints nothing; dynamic runs and reports the function as unavailable.
set -eu
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cd "$work"

cat > v1.c <<'C'
int swda_present(void) { return 1; }
int swda_extra(void)   { return 2; }
C
cat > v2.c <<'C'
int swda_present(void) { return 1; }
C
cat > linked.swift <<'S'
import Foundation
@_silgen_name("swda_present") func present() -> Int32
@_silgen_name("swda_extra") func extra() -> Int32
setvbuf(stdout, nil, _IOLBF, 0)
print("linked: started")
print("linked: present() =", present())
if CommandLine.arguments.contains("--call") { print("linked: extra() =", extra()) }
S
cat > dynamic.swift <<'S'
import Foundation
@_silgen_name("swda_present") func present() -> Int32
typealias Extra = @convention(c) () -> Int32
setvbuf(stdout, nil, _IOLBF, 0)
print("dynamic: started")
print("dynamic: present() =", present())
if let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "swda_extra") {   // RTLD_DEFAULT
    print("dynamic: extra() =", unsafeBitCast(symbol, to: Extra.self)())
} else {
    print("dynamic: swda_extra is not available (handled)")
}
S

build_dylib() { clang -dynamiclib -mmacosx-version-min=12.0 -install_name "@executable_path/libswda.dylib" -o libswda.dylib "$1"; }
build_dylib v1.c
swiftc -O -target "$(uname -m)-apple-macos12.0" -L . -lswda -o linked linked.swift 2>/dev/null
swiftc -O -target "$(uname -m)-apple-macos12.0" -L . -lswda -o dynamic dynamic.swift 2>/dev/null

if otool -l linked | grep -q LC_DYLD_CHAINED_FIXUPS; then
	echo "linked uses chained fixups (LC_DYLD_CHAINED_FIXUPS present)"
else
	echo "NOTE: no chained fixups in this build; the abort below will not reproduce"
fi

status=0
run() {   # run <label> <program> [args]
	local label="$1"; shift
	set +e; out="$("$@" 2>&1)"; rc=$?; set -e
	printf '%-34s exit %-3s %s\n' "$label" "$rc" "$(printf '%s' "$out" | head -3 | tr '\n' '|' | cut -c1-150)"
}

echo "--- with libswda v1 (both functions present)"
run "linked"            ./linked
run "linked --call"     ./linked --call
run "dynamic"           ./dynamic

echo "--- after the update: libswda v2 (swda_extra removed)"
build_dylib v2.c
run "linked (never calls extra)" ./linked
run "dynamic"                    ./dynamic

exit_status() { set +e; local out; out="$("$@" 2>&1)"; local rc=$?; set -e; echo "$rc"; }   # the substitution keeps the shell's "Abort trap" notice out of our output
linked_rc="$(exit_status ./linked)"; dynamic_rc="$(exit_status ./dynamic)"
if [ "$linked_rc" = 134 ] && [ "$dynamic_rc" = 0 ]; then
	echo "RESULT: reproduced: linked aborted at launch (134), dynamic survived (0)"
else
	echo "RESULT: NOT as expected: linked=$linked_rc dynamic=$dynamic_rc"; status=1
fi
exit $status
