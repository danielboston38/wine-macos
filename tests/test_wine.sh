#!/bin/bash
set -uo pipefail
TESTS_DIR="$(cd "$(dirname "$0")" && pwd -P)"
# shellcheck source=tests/assert.sh
. "$TESTS_DIR/assert.sh"
# shellcheck source=scripts/build-wine.sh
. "$TESTS_DIR/../scripts/build-wine.sh" || { echo "FAIL - cannot source build-wine.sh"; exit 1; }

# validate_tag fails fast on an unknown tag
start=$(date +%s)
err=$( (validate_tag wine-11.99) 2>&1 ); rc=$?
assert_eq 1 "$rc" "validate_tag rejects wine-11.99"
assert_contains "$err" "unknown Wine tag" "unknown tag message"
assert_eq 1 "$([ $(( $(date +%s) - start )) -lt 5 ] && echo 1)" "rejection takes under 5 s"
( validate_tag wine-11.22 ) 2>/dev/null; rc=$?
assert_eq 0 "$rc" "validate_tag accepts wine-11.22"

# check_wine_config
( check_wine_config "$TESTS_DIR/fixtures/config_ok.h" ) 2>/dev/null; rc=$?
assert_eq 0 "$rc" "complete config.h passes"
err=$( (check_wine_config "$TESTS_DIR/fixtures/config_missing_gnutls.h") 2>&1 ); rc=$?
assert_eq 1 "$rc" "config.h without GnuTLS fails"
assert_contains "$err" "GnuTLS" "missing GnuTLS named"

# configure_wine runs configure only when the build dir has no config.status
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
run_x86() { echo "configure-ran" >> "$TMP/calls"; }
check_wine_config() { :; }
mkdir -p "$TMP/build"
( configure_wine "$TMP/src" "$TMP/build" "$TMP/stage" ) 2>/dev/null
assert_eq 1 "$(grep -c configure-ran "$TMP/calls" 2>/dev/null)" "configure runs in a fresh build dir"
touch "$TMP/build/config.status"
( configure_wine "$TMP/src" "$TMP/build" "$TMP/stage" ) 2>/dev/null
assert_eq 1 "$(grep -c configure-ran "$TMP/calls")" "configure is skipped when config.status exists"
echo stale > "$TMP/build/deps-manifest.sha256"
( configure_wine "$TMP/src" "$TMP/build" "$TMP/stage" ) 2>/dev/null
assert_eq 2 "$(grep -c configure-ran "$TMP/calls")" "configure reruns when deps/manifest.sh changed"
unset -f run_x86 check_wine_config
# shellcheck source=scripts/build-wine.sh
. "$TESTS_DIR/../scripts/build-wine.sh"

# integration: real Wine build (slow)
if [ "${WINE_IT:-}" = 1 ]; then
    LOG="$WORK_DIR/build-wine-test.log"
    if ! stage=$("$TESTS_DIR/../scripts/build-wine.sh" wine-11.22 2>"$LOG" | tail -1); then
        tail -40 "$LOG"; echo "FAIL - build-wine.sh"; exit 1
    fi
    assert_eq "$WORK_DIR/stage/wine-11.22" "$stage" "stage path printed last"
    assert_eq x86_64 "$(lipo -archs "$stage/bin/wine")" "bin/wine is x86_64"
    assert_file "$stage/lib/wine/i386-windows/kernel32.dll"
    assert_file "$stage/lib/wine/x86_64-windows/kernel32.dll"
    assert_eq 0 "$(find "$stage" -name '*.a' | wc -l | tr -d ' ')" "no import libraries installed"
    assert_eq 1 "$([ ! -e "$stage/include" ] && echo 1)" "no headers installed"
    assert_eq wine-11.22 "$(DYLD_FALLBACK_LIBRARY_PATH="$DEPS_PREFIX/lib" "$stage/bin/wine" --version)" "wine --version"
fi

finish_tests
