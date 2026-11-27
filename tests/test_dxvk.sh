#!/bin/bash
set -uo pipefail
TESTS_DIR="$(cd "$(dirname "$0")" && pwd -P)"
# shellcheck source=tests/assert.sh
. "$TESTS_DIR/assert.sh"
# shellcheck source=scripts/install-dxvk.sh
. "$TESTS_DIR/../scripts/install-dxvk.sh" || { echo "FAIL - cannot source install-dxvk.sh"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PREFIX="$TMP/my prefix"

# check_prefix rejects a directory that is not a booted prefix
mkdir -p "$PREFIX"
err=$( (check_prefix "$PREFIX") 2>&1 ); rc=$?
assert_eq 1 "$rc" "check_prefix rejects an empty directory"
assert_contains "$err" "wineboot" "rejection says how to create the prefix"
mkdir -p "$PREFIX/drive_c/windows/system32" "$PREFIX/drive_c/windows/syswow64"
( check_prefix "$PREFIX" ) 2>/dev/null; rc=$?
assert_eq 0 "$rc" "check_prefix accepts a booted prefix"

# copy_dlls puts 64-bit DLLs in system32 and 32-bit DLLs in syswow64
REL="$TMP/rel/dxvk-test"
mkdir -p "$REL/x64" "$REL/x32"
for dll in d3d10core d3d11; do
    echo "64 $dll" > "$REL/x64/$dll.dll"
    echo "32 $dll" > "$REL/x32/$dll.dll"
done
tar -czf "$TMP/dxvk.tar.gz" -C "$TMP/rel" dxvk-test
( copy_dlls "$TMP/dxvk.tar.gz" "$PREFIX" ) 2>/dev/null; rc=$?
assert_eq 0 "$rc" "copy_dlls succeeds"
assert_eq "64 d3d11" "$(cat "$PREFIX/drive_c/windows/system32/d3d11.dll")" "64-bit d3d11 in system32"
assert_eq "32 d3d11" "$(cat "$PREFIX/drive_c/windows/syswow64/d3d11.dll")" "32-bit d3d11 in syswow64"
assert_eq "32 d3d10core" "$(cat "$PREFIX/drive_c/windows/syswow64/d3d10core.dll")" "32-bit d3d10core in syswow64"

# copy_dlls fails when the release lacks a DLL
rm "$REL/x32/d3d10core.dll"
tar -czf "$TMP/broken.tar.gz" -C "$TMP/rel" dxvk-test
err=$( (copy_dlls "$TMP/broken.tar.gz" "$PREFIX") 2>&1 ); rc=$?
assert_eq 1 "$rc" "copy_dlls fails on an incomplete release"
assert_contains "$err" "d3d10core.dll missing" "missing DLL named"

# set_overrides sets each DLL to native in the given prefix
run_wine() { echo "$1|${*:2}" >> "$TMP/calls"; }
( set_overrides "$PREFIX" ) 2>/dev/null
assert_eq 2 "$(grep -c "^$PREFIX|reg add .*DllOverrides /v d3d1[01]\(core\)\{0,1\} /t REG_SZ /d native /f$" "$TMP/calls")" "overrides set for both DLLs"

finish_tests
