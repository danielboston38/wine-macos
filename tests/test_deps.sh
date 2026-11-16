#!/bin/bash
# The FAKE_* vars and build_dep_fake are read indirectly by build-deps.sh.
# shellcheck disable=SC2034,SC2329
set -uo pipefail
TESTS_DIR="$(cd "$(dirname "$0")" && pwd -P)"
# shellcheck source=tests/assert.sh
. "$TESTS_DIR/assert.sh"
# shellcheck source=deps/build-deps.sh
. "$TESTS_DIR/../deps/build-deps.sh" || { echo "FAIL - cannot source build-deps.sh"; exit 1; }

# --- unit: stamps are written only after a successful build ---------------
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/fixture/fake-1.0"
echo hi > "$TMP/fixture/fake-1.0/README"
tar czf "$TMP/fake-1.0.tar.gz" -C "$TMP/fixture" fake-1.0
FAKE_VERSION=1.0
FAKE_URL="file://$TMP/fake-1.0.tar.gz"
FAKE_SHA256=$(shasum -a 256 "$TMP/fake-1.0.tar.gz" | cut -d' ' -f1)
DEPS_WORK="$TMP/deps"

build_dep_fake() { echo "compiling..."; false; echo "should not get here"; }
( main fake ) >/dev/null 2>&1; rc=$?
assert_eq 1 "$([ "$rc" -ne 0 ] && echo 1)" "failing dependency build fails"
assert_eq 0 "$(find "$DEPS_WORK/stamps" -name 'fake-*' 2>/dev/null | wc -l | tr -d ' ')" "no stamp after failed build"

build_dep_fake() { test -f README; }
( main fake ) >/dev/null 2>&1; rc=$?
assert_eq 0 "$rc" "successful dependency build succeeds"
assert_file "$DEPS_WORK/stamps/fake-1.0"
out=$( (main fake) 2>&1 )
assert_contains "$out" "fake 1.0 up to date" "second run skips the built dependency"

# --- unit: pkg-config files for the SDK's zlib and bzip2 -----------------
write_sdk_pkgconfig "$TMP/pc"
assert_eq "-lz" "$(PKG_CONFIG_LIBDIR="$TMP/pc" pkg-config --libs zlib | tr -d ' ')" "zlib.pc gives -lz"
assert_eq "-lbz2" "$(PKG_CONFIG_LIBDIR="$TMP/pc" pkg-config --libs bzip2 | tr -d ' ')" "bzip2.pc gives -lbz2"

# --- integration: real dependencies (slow) --------------------------------
if [ "${DEPS_IT:-}" = 1 ]; then
    DEPS_WORK="$WORK_DIR/deps"
    if ! "$TESTS_DIR/../deps/build-deps.sh" > "$TMP/build.log" 2>&1; then
        tail -40 "$TMP/build.log"
        echo "FAIL - deps/build-deps.sh"
        exit 1
    fi
    while IFS= read -r lib; do
        assert_eq x86_64 "$(lipo -archs "$lib")" "arch of $(basename "$lib")"
        minos=$(vtool -show-build "$lib" | awk '/minos/ {print $2}')
        assert_eq 1 "$(echo "$minos" | awk '{ split($1, v, "."); print ((v[1] < 12 || (v[1] == 12 && v[2] == 0)) ? 1 : 0) }')" \
            "minos $minos <= 12.0 for $(basename "$lib")"
        foreign=$(otool -L "$lib" | grep -E '/opt/homebrew|/usr/local' || true)
        assert_eq "" "$foreign" "no Homebrew paths in $(basename "$lib")"
    done < <(find "$DEPS_PREFIX/lib" -name '*.dylib' -type f)
    ( x86_env; pkg-config --exists gnutls freetype2 sdl2 ); rc=$?
    assert_eq 0 "$rc" "pkg-config finds gnutls freetype2 sdl2 in the prefix"
    start=$(date +%s)
    out=$("$TESTS_DIR/../deps/build-deps.sh" 2>&1)
    assert_eq 1 "$([ $(( $(date +%s) - start )) -lt 10 ] && echo 1)" "cached rerun takes under 10 s"
    assert_eq 8 "$(echo "$out" | grep -c 'up to date')" "all 8 dependencies up to date on rerun"
fi

finish_tests
