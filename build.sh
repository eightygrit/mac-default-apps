#!/usr/bin/env bash
#
# Build, sign and install SwiftDefaultApps into ~/Applications.
#
#   ./build.sh                 build, sign, install
#   ./build.sh --no-install    build and sign only
#   ./build.sh --cli           also build the "swda" command line tool
#
# Environment overrides:
#   SIGN_ID="..."              signing identity ("-" for ad-hoc); an identity that is not in the keychain is an error
#   REQUIRE_SIGNING=1          fail instead of falling back to an ad-hoc signature
#   ARCH="arm64"               narrow the build (default: universal)
#   DEPLOY_TARGET="13.0"       minimum macOS version

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$REPO/build/Release"
BACKUP_DIR="$REPO/backups"
INSTALL_DIR="$HOME/Applications"
APP="SwiftDefaultApps.app"
LOG="$REPO/build/build.log"

SWIFTCLI_DIR="$REPO/Packages/SwiftCLI-2.0.3"

ARCH="${ARCH:-arm64 x86_64}"
DEPLOY_TARGET="${DEPLOY_TARGET:-13.0}"

DO_INSTALL=1
DO_CLI=0
for arg in "$@"; do
	case "$arg" in
		--no-install) DO_INSTALL=0 ;;
		--cli)        DO_CLI=1 ;;
		-h|--help)    sed -n '2,14p' "${BASH_SOURCE[0]}"; exit 0 ;;
		*) echo "Unknown option: $arg" >&2; exit 2 ;;
	esac
done

step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }

# --------------------------------------------------------------- dependencies
# The app builds `swda`, which links SwiftCLI, so every build needs its sources: the submodule Packages/SwiftCLI-2.0.3, at the
# commit this repository records. (Its tag 2.0.3 is Swift 3 code that no longer compiles; the recorded commit is 2.0.3+swift5.)
step "Checking SwiftCLI"
if [ ! -f "$SWIFTCLI_DIR/Sources/CLI.swift" ]; then
	[ -e "$REPO/.git" ] || { echo "Packages/SwiftCLI-2.0.3 is empty and this is not a git checkout; clone with: git clone --recurse-submodules" >&2; exit 1; }
	echo "missing - fetching the submodule"
	git -C "$REPO" submodule update --init -- Packages/SwiftCLI-2.0.3
fi
if [ -e "$REPO/.git" ]; then
	case "$(git -C "$REPO" submodule status -- Packages/SwiftCLI-2.0.3 | cut -c1)" in
		"+") echo "Packages/SwiftCLI-2.0.3 is not at the commit this repository records; run: git submodule update" >&2; exit 1 ;;
		"U") echo "Packages/SwiftCLI-2.0.3 has a merge conflict" >&2; exit 1 ;;
		"-") echo "Packages/SwiftCLI-2.0.3 is not initialized; run: git submodule update --init" >&2; exit 1 ;;
	esac
fi
[ -f "$SWIFTCLI_DIR/Sources/CLI.swift" ] || { echo "$SWIFTCLI_DIR has no sources; run: git -C Packages/SwiftCLI-2.0.3 checkout -- ." >&2; exit 1; }
echo "present: $SWIFTCLI_DIR"

# ------------------------------------------------------------------- identity
step "Signing identity"
IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"
if [ -z "${SIGN_ID:-}" ]; then
	SIGN_ID="$(printf '%s\n' "$IDENTITIES" | sed -n 's/.*"\(Developer ID Application: .*\)"$/\1/p' | head -1)"
	if [ -z "$SIGN_ID" ]; then
		[ "${REQUIRE_SIGNING:-0}" != 1 ] || { echo "REQUIRE_SIGNING=1 and no Developer ID Application identity is in the keychain" >&2; exit 1; }
		echo "no Developer ID Application identity found - using ad-hoc"
		echo "(fine for local use, not for distribution)"
		SIGN_ID="-"
	fi
elif [ "$SIGN_ID" != "-" ] && ! grep -qF -- "$SIGN_ID" <<<"$IDENTITIES"; then
	echo "SIGN_ID names an identity that is not in the keychain" >&2
	exit 1
fi
[ "$SIGN_ID" != "-" ] || [ "${REQUIRE_SIGNING:-0}" != 1 ] || { echo "REQUIRE_SIGNING=1 does not allow an ad-hoc signature" >&2; exit 1; }
# Deliberately not echoing the identity itself: it carries a real name and
# Team ID, and build logs get pasted into issues.
if [ "$SIGN_ID" = "-" ]; then
	echo "using: ad-hoc signature"
else
	echo "using: Developer ID Application from keychain"
fi

# Ad-hoc signatures cannot be timestamped.
TS_FLAG=(--timestamp)
[ "$SIGN_ID" = "-" ] && TS_FLAG=(--timestamp=none)

# ---------------------------------------------------------------------- build
# The whole output of xcodebuild goes to a log, and the build stops when it fails; only the warnings and errors are shown.
mkdir -p "$REPO/build"
: > "$LOG"
build() { # build <project> <target>
	local seen
	seen="$(wc -l <"$LOG")"
	if ! xcodebuild -project "$REPO/$1" -target "$2" -configuration Release \
		ARCHS="$ARCH" ONLY_ACTIVE_ARCH=NO MACOSX_DEPLOYMENT_TARGET="$DEPLOY_TARGET" \
		CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO DEVELOPMENT_TEAM="" >>"$LOG" 2>&1; then
		tail -n +$((seen + 1)) "$LOG" | grep -E 'error:' | sort -u | head -20 >&2 || true
		echo "build failed; the whole log is $LOG" >&2
		exit 1
	fi
	tail -n +$((seen + 1)) "$LOG" | grep -E 'warning:' | sort -u | head -20 || true
}

step "Building app ($ARCH, deployment target $DEPLOY_TARGET)"
build SwiftDefaultApps.xcodeproj SwiftDefaultApps
[ -d "$BUILD_DIR/$APP" ] || { echo "build product missing: $BUILD_DIR/$APP" >&2; exit 1; }

if [ "$DO_CLI" = 1 ]; then
	step "Building CLI"
	build "SwiftDefaultApps CLI.xcodeproj" SwiftDefaultApps
	[ -f "$BUILD_DIR/swda" ] || { echo "build product missing: $BUILD_DIR/swda" >&2; exit 1; }
	echo "CLI built at: $BUILD_DIR/swda"
fi

# ----------------------------------------------------------------------- sign
# Nested bundles must be signed before the enclosing one.
step "Signing"
codesign --force --options runtime "${TS_FLAG[@]}" --sign "$SIGN_ID" \
	"$BUILD_DIR/$APP/Contents/Resources/ThisAppDoesNothing.app"
codesign --force --options runtime "${TS_FLAG[@]}" --sign "$SIGN_ID" \
	"$BUILD_DIR/$APP"
if [ "$DO_CLI" = 1 ]; then
	codesign --force --options runtime "${TS_FLAG[@]}" --sign "$SIGN_ID" "$BUILD_DIR/swda"
	codesign --verify --strict "$BUILD_DIR/swda"
	echo "swda signature verified"
fi

# `codesign --verify ... && echo` would not stop the script on a bad signature (a command in an && list is exempt from set -e).
codesign --verify --deep --strict "$BUILD_DIR/$APP"
echo "signature verified"
codesign -dv "$BUILD_DIR/$APP" 2>&1 | grep -E '^(Identifier|Format)='
lipo -info "$BUILD_DIR/$APP/Contents/MacOS/SwiftDefaultApps"

if [ "$DO_INSTALL" = 0 ]; then
	step "Done (not installed)"
	echo "$BUILD_DIR/$APP"
	exit 0
fi

# -------------------------------------------------------------------- install
step "Quitting SwiftDefaultApps"
if pgrep -x SwiftDefaultApps >/dev/null; then
	osascript -e 'quit app id "cl.fail.lordkamina.SwiftDefaultApps"'
	sleep 2
fi

step "Installing into $INSTALL_DIR"
mkdir -p "$INSTALL_DIR" "$BACKUP_DIR"
if [ -e "$INSTALL_DIR/$APP" ]; then
	BAK="$BACKUP_DIR/$APP.backup-$(date +%Y%m%d-%H%M%S)"
	mv "$INSTALL_DIR/$APP" "$BAK"
	echo "previous version kept at: $BAK"
fi
cp -R "$BUILD_DIR/$APP" "$INSTALL_DIR/$APP"

step "Verifying"
lipo -info "$INSTALL_DIR/$APP/Contents/MacOS/SwiftDefaultApps"
codesign --verify --deep --strict "$INSTALL_DIR/$APP"
echo "signature ok"
echo
echo "Installed. Open with:  open \"$INSTALL_DIR/$APP\""
