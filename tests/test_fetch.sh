#!/bin/bash
set -uo pipefail
TESTS_DIR="$(cd "$(dirname "$0")" && pwd -P)"
# shellcheck source=tests/assert.sh
. "$TESTS_DIR/assert.sh"
# shellcheck source=scripts/fetch.sh
. "$TESTS_DIR/../scripts/fetch.sh" || { echo "FAIL - cannot source fetch.sh"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
DIR="$TMP/with space"
mkdir -p "$DIR"
printf 'hello wine\n' > "$DIR/src file.txt"
GOOD=$(shasum -a 256 "$DIR/src file.txt" | cut -d' ' -f1)
URL="file://${DIR// /%20}/src%20file.txt"

# correct checksum
( fetch_source "$URL" "$GOOD" "$DIR/dest.txt" ) 2>/dev/null; rc=$?
assert_eq 0 "$rc" "fetch with correct sha succeeds"
assert_file "$DIR/dest.txt"
assert_eq "no" "$([ -e "$DIR/dest.txt.part" ] && echo yes || echo no)" "no .part left after success"

# wrong checksum
BAD=0000000000000000000000000000000000000000000000000000000000000000
err=$( (fetch_source "$URL" "$BAD" "$DIR/bad.txt") 2>&1 ); rc=$?
assert_eq 1 "$rc" "fetch with wrong sha fails"
assert_contains "$err" "checksum mismatch" "mismatch reported"
assert_eq "no" "$([ -e "$DIR/bad.txt" ] && echo yes || echo no)" "no dest after mismatch"
assert_eq "no" "$([ -e "$DIR/bad.txt.part" ] && echo yes || echo no)" "no .part after mismatch"

# cache hit: good file exists, URL unreachable
( fetch_source "file://$DIR/does-not-exist" "$GOOD" "$DIR/dest.txt" ) 2>/dev/null; rc=$?
assert_eq 0 "$rc" "existing good file is reused without download"

# manifest completeness
# shellcheck source=deps/manifest.sh
. "$TESTS_DIR/../deps/manifest.sh"
for name in $DEPS_ORDER; do
    v=$(dep_var "$name" VERSION); u=$(dep_var "$name" URL); s=$(dep_var "$name" SHA256)
    assert_eq 1 "$([ -n "$v" ] && [ -n "$u" ] && echo 1)" "$name has VERSION and URL"
    assert_eq 1 "$(echo "$s" | grep -cE '^[0-9a-f]{64}$')" "$name has a 64-hex SHA256"
done

finish_tests
