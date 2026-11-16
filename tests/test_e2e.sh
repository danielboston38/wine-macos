#!/bin/bash
set -uo pipefail
TESTS_DIR="$(cd "$(dirname "$0")" && pwd -P)"
ROOT="$TESTS_DIR/.."
# shellcheck source=tests/assert.sh
. "$TESTS_DIR/assert.sh"

# usage
out=$("$ROOT/build.sh" 2>&1); rc=$?
assert_eq 2 "$rc" "build.sh with no args exits 2"
assert_contains "$out" "usage:" "usage printed"

# unknown tag fails fast
start=$(date +%s)
out=$("$ROOT/build.sh" wine-11.99 2>&1); rc=$?
assert_eq 1 "$([ "$rc" -ne 0 ] && echo 1)" "unknown tag fails"
assert_contains "$out" "unknown Wine tag" "unknown tag message"
assert_eq 1 "$([ $(( $(date +%s) - start )) -lt 5 ] && echo 1)" "unknown tag fails within 5 s"

if [ "${E2E:-}" = 1 ]; then
    TMP=$(mktemp -d)
    trap 'rm -rf "$TMP"' EXIT
    out=$("$ROOT/build.sh" wine-11.22 2>"$TMP/build.log"); rc=$?
    if [ "$rc" -ne 0 ]; then tail -40 "$TMP/build.log"; echo "FAIL - build.sh"; exit 1; fi
    app=$(echo "$out" | sed -n 's/^Built: //p')
    assert_file "$app/Contents/MacOS/wine"

    # mscoree/mshtml disabled: otherwise wineboot stops at the "install Wine
    # Mono / Gecko?" dialog and never sets up the 32-bit side of the prefix.
    w() {
        env -i HOME="$HOME" PATH=/usr/bin:/bin WINEPREFIX="$TMP/prefix" WINEDEBUG=-all \
            WINEDLLOVERRIDES="mscoree,mshtml=" "$app/Contents/MacOS/wine" "$@"
    }
    wineserver() {
        env -i HOME="$HOME" PATH=/usr/bin:/bin WINEPREFIX="$TMP/prefix" \
            "$app/Contents/Resources/wine/bin/wineserver" "$@"
    }
    w wineboot -i >/dev/null 2>&1; rc=$?
    assert_eq 0 "$rc" "wineboot -i succeeds"
    wineserver -w
    assert_contains "$(w cmd /c echo hello64 2>&1)" "hello64" "64-bit cmd runs"
    assert_contains "$(w 'C:\windows\syswow64\cmd.exe' /c echo hello32 2>&1)" "hello32" "32-bit cmd runs via WoW64"
    wineserver -k
fi

finish_tests
