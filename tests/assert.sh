#!/bin/bash
# Tiny assertion helpers. Source this from a test file.
# Each assertion prints "ok - msg" or "FAIL - msg" and records failures in TEST_FAILURES.

TEST_FAILURES=${TEST_FAILURES:-0}

_ok()   { echo "ok - $1"; }
_fail() { echo "FAIL - $1"; TEST_FAILURES=$((TEST_FAILURES + 1)); }

assert_eq() {
    local expected=$1 actual=$2 msg=$3
    if [ "$expected" = "$actual" ]; then _ok "$msg"
    else _fail "$msg (expected '$expected', got '$actual')"; fi
}

assert_contains() {
    local haystack=$1 needle=$2 msg=$3
    case "$haystack" in
        *"$needle"*) _ok "$msg" ;;
        *) _fail "$msg ('$needle' not in '$haystack')" ;;
    esac
}

# assert_fails <msg> <cmd...>: passes when the command exits non-zero.
assert_fails() {
    local msg=$1; shift
    if "$@"; then _fail "$msg (command succeeded)"
    else _ok "$msg"; fi
}

assert_file() {
    if [ -e "$1" ]; then _ok "file exists: $1"
    else _fail "file missing: $1"; fi
}

# Call last in every test file.
finish_tests() {
    [ "$TEST_FAILURES" -eq 0 ]
}
