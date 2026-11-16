#!/bin/bash
set -uo pipefail
TESTS_DIR="$(cd "$(dirname "$0")" && pwd -P)"
# shellcheck source=tests/assert.sh
. "$TESTS_DIR/assert.sh"
# shellcheck source=scripts/lib.sh
. "$TESTS_DIR/../scripts/lib.sh" || { echo "FAIL - cannot source lib.sh"; exit 1; }

# check_prereqs reports every missing item at once
err=$( (PATH=/usr/bin:/bin check_prereqs) 2>&1 >/dev/null ); rc=$?
assert_eq 1 "$rc" "check_prereqs fails with a bare PATH"
assert_contains "$err" "mingw-w64" "missing mingw-w64 reported"
assert_contains "$err" "meson" "missing meson reported in the same message"

( check_prereqs ) >/dev/null 2>&1; rc=$?
assert_eq 0 "$rc" "check_prereqs succeeds with the real PATH"

# die
err=$( (die "boom") 2>&1 ); rc=$?
assert_eq 1 "$rc" "die exits 1"
assert_eq "error: boom" "$err" "die prints 'error: msg' to stderr"

# x86_env
(
    export PKG_CONFIG_PATH=/opt/homebrew/lib/pkgconfig
    x86_env
    assert_eq "$DEPS_PREFIX/lib/pkgconfig" "$PKG_CONFIG_LIBDIR" "x86_env sets PKG_CONFIG_LIBDIR"
    assert_eq "unset" "${PKG_CONFIG_PATH-unset}" "x86_env unsets PKG_CONFIG_PATH"
    finish_tests
) || TEST_FAILURES=$((TEST_FAILURES + 1))

finish_tests
