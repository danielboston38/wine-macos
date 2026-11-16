#!/bin/bash
# Shared helpers. Source this file; do not run it.

# These are used by the scripts that source this file.
# shellcheck disable=SC2034
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
WORK_DIR="$REPO_ROOT/work"
DEPS_PREFIX="$WORK_DIR/deps/prefix"
DIST_DIR="$REPO_ROOT/dist"
WINE_GIT="${WINE_GIT:-$HOME/build/wine}"
export MACOSX_DEPLOYMENT_TARGET=12.0

# macOS ships bison 2.3; Wine needs bison 3. Homebrew's bison is keg-only.
for _bison_dir in /opt/homebrew/opt/bison/bin /usr/local/opt/bison/bin; do
    if [ -x "$_bison_dir/bison" ]; then
        PATH="$_bison_dir:$PATH"
        break
    fi
done
unset _bison_dir

log() { echo "==> $*" >&2; }
die() { echo "error: $*" >&2; exit 1; }

check_prereqs() {
    local missing=() tool
    arch -x86_64 /usr/bin/true 2>/dev/null \
        || missing+=("Rosetta (softwareupdate --install-rosetta)")
    command -v xcrun >/dev/null || missing+=("Xcode Command Line Tools (xcode-select --install)")
    if ! command -v i686-w64-mingw32-gcc >/dev/null || ! command -v x86_64-w64-mingw32-gcc >/dev/null; then
        missing+=("mingw-w64 (brew install mingw-w64)")
    fi
    if ! command -v bison >/dev/null; then
        missing+=("bison (brew install bison)")
    elif [ "$(bison --version | head -1 | sed 's/.* \([0-9]*\)\..*/\1/')" -lt 3 ]; then
        missing+=("bison >= 3 (brew install bison)")
    fi
    for tool in flex meson ninja cmake pkg-config autoreconf git curl shasum; do
        command -v "$tool" >/dev/null || missing+=("$tool")
    done
    if [ "${#missing[@]}" -gt 0 ]; then
        local joined
        joined=$(printf '%s, ' "${missing[@]}")
        die "missing: ${joined%, }"
    fi
}

x86_env() {
    export CC="clang -arch x86_64"
    export CXX="clang++ -arch x86_64"
    export CFLAGS="-O2 -mmacosx-version-min=12.0"
    export CXXFLAGS="$CFLAGS"
    export CPPFLAGS="-I$DEPS_PREFIX/include"
    export LDFLAGS="-L$DEPS_PREFIX/lib -mmacosx-version-min=12.0"
    export PKG_CONFIG_LIBDIR="$DEPS_PREFIX/lib/pkgconfig"
    unset PKG_CONFIG_PATH
    export PATH="$DEPS_PREFIX/bin:$PATH"
}

run_x86() { arch -x86_64 "$@"; }
