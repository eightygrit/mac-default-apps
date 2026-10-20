#!/usr/bin/env bash
# Golden-output recorder for the `swda` CLI. READ-ONLY: it cannot change a default handler.
#
# usage: Tests/golden.sh <path-to-swda> <output-dir>
#
# Runs only
#   - every getX command, and
#   - setHandler invocations that fail BEFORE the Launch Services call
#     (unresolvable application, missing option group, malformed scheme or extension).
# Each case writes one file holding the command line, stdout, stderr and the exit status.
# List output is sorted where the order is not part of the contract.
#
# Compare two runs (record them back-to-back: Launch Services state drifts, for example
# when an app is installed between runs):
#   diff -ru <dirA> <dirB>
#
# The recordings are machine-specific, so they are never committed.
set -u
SWDA="${1:?path to swda}"; OUT="${2:?output dir}"
mkdir -p "$OUT"
n=0
run() {                       # run <args...>  -> $OUT/NNN__<slug>.out (stdout, stderr, exit)
  n=$((n+1))
  local slug; slug="$(printf '%s_' "$@" | tr -c 'A-Za-z0-9._-\n' '_' | cut -c1-110)"
  local f; f="$OUT/$(printf '%03d' "$n")__${slug}.out"
  { "$SWDA" "$@" >"$f.so" 2>"$f.se"; echo "exit=$?" >"$f.rc"; } || true
  { echo "\$ swda $*"; echo "--- stdout"; cat "$f.so"; echo "--- stderr"; cat "$f.se"; echo "--- $(cat "$f.rc")"; } >"$f"
  rm -f "$f.so" "$f.se" "$f.rc"
}
sorted() {                    # same as run, but stdout is sorted (list order is not part of the contract)
  n=$((n+1))
  local slug; slug="$(printf '%s_' "$@" | tr -c 'A-Za-z0-9._-\n' '_' | cut -c1-110)"
  local f; f="$OUT/$(printf '%03d' "$n")__sorted_${slug}.out"
  { "$SWDA" "$@" 2>"$f.se" | LC_ALL=C sort >"$f.so"; echo "exit=${PIPESTATUS[0]}" >"$f.rc"; } || true
  { echo "\$ swda $* | sort"; echo "--- stdout"; cat "$f.so"; echo "--- stderr"; cat "$f.se"; echo "--- $(cat "$f.rc")"; } >"$f"
  rm -f "$f.so" "$f.se" "$f.rc"
}

run version
run help
run getHandler --help
run setHandler --help
run bogusCommand

# whole-database listings (order-insensitive)
sorted getApps
sorted getSchemes
sorted getUTIs

UTIS=(public.html public.plain-text public.json public.xml com.adobe.pdf public.jpeg com.compuserve.gif public.png
      public.mpeg-4 public.mp3 public.zip-archive com.apple.property-list public.unix-executable public.shell-script
      public.folder com.apple.application-bundle public.item no.such.uti)
ROLES=("" Viewer Editor Shell All viewer bogus)
for u in "${UTIS[@]}"; do
  for r in "${ROLES[@]}"; do
    roleargs=(); [ -n "$r" ] && roleargs=(--role "$r")
    run getHandler --UTI "$u" ${roleargs[@]+"${roleargs[@]}"}
    sorted getHandler --UTI "$u" ${roleargs[@]+"${roleargs[@]}"} --all
  done
done

SCHEMES=(http https mailto ftp rss news file tel facetime sms imessage x-apple.systempreferences zoommtg nosuchscheme HTTP)
for s in "${SCHEMES[@]}"; do
  run getHandler --URL "$s"
  sorted getHandler --URL "$s" --all
done

for flag in --internet --browser --web --mail --email --e-mail --ftp --rss --news; do
  run getHandler "$flag"
  run getHandler "$flag" --all
done

# option-parser contract
run getHandler
run getHandler --UTI public.html --URL http
run getHandler --UTI
run getHandler --role Viewer

# setHandler: ONLY paths that fail before any write
run setHandler
run setHandler --UTI public.html
run setHandler --app Safari
run setHandler --UTI public.html --app /nonexistent/Foo.app
run setHandler --URL http --app NoSuchAppAnywhere
run setHandler --UTI public.html --app /etc/hosts
run setHandler --URL "bad scheme" --app Safari
run setHandler --URL "1bad" --app Safari
# --extension / --ext (PR #94): known, bundle-type, unknown and malformed extensions
EXTS=(pdf md html txt swift app action appex foobar zzzzqq PDF .pdf tar.gz)
for e in "${EXTS[@]}"; do
  run getHandler --extension "$e"
  sorted getHandler --extension "$e" --all
  run getHandler --ext "$e" --role Viewer
done
run getHandler --extension ""
run getHandler --extension
run getHandler --extension pdf --UTI public.html
run setHandler --extension pdf
run setHandler --extension pdf --app NoSuchAppAnywhere
run setHandler --extension "" --app NoSuchAppAnywhere
# An option longer than 40 characters used to trap in SwiftCLI; an unknown role is refused before anything else
run getHandler "--URL=$(printf 'x%.0s' {1..45})"
run setHandler --UTI public.html --app NoSuchAppAnywhere --role Vieewer
run setHandler --UTI public.html --app NoSuchAppAnywhere --role viewer
echo "wrote $n cases to $OUT"
