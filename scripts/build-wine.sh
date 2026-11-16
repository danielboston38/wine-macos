#!/bin/bash
# Usage: scripts/build-wine.sh <tag>
# Builds an upstream Wine tag against work/deps/prefix and installs it to
# work/stage/<tag>. Prints the stage path as the last line on stdout.
# Build output goes to stderr.

# shellcheck source=scripts/lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

validate_tag() {
    local tag=$1
    git -C "$WINE_GIT" rev-parse -q --verify "refs/tags/$tag" >/dev/null \
        || die "unknown Wine tag: $tag (try: git -C \"$WINE_GIT\" tag -l 'wine-*')"
}

# check_wine_config <config.h>: die unless every required library was found.
check_wine_config() {
    local config=$1 entry missing=()
    for entry in FREETYPE:FreeType GNUTLS:GnuTLS VULKAN:Vulkan SDL2:SDL2; do
        grep -q "^#define SONAME_LIB${entry%%:*} " "$config" || missing+=("${entry#*:}")
    done
    if [ "${#missing[@]}" -gt 0 ]; then
        local joined
        joined=$(printf '%s, ' "${missing[@]}")
        die "Wine configured without: ${joined%, }"
    fi
}

main() {
    local tag=$1 src build stage
    validate_tag "$tag"
    src="$WORK_DIR/wine-src/$tag"
    build="$WORK_DIR/wine-build/$tag"
    stage="$WORK_DIR/stage/$tag"

    if [ ! -e "$src/configure" ]; then
        log "checking out $tag"
        git -C "$WINE_GIT" worktree add --detach "$src" "$tag" >&2
    fi

    x86_env
    if command -v ccache >/dev/null; then
        export CC="ccache clang -arch x86_64"
    fi

    mkdir -p "$build"
    cd "$build"
    log "configuring $tag"
    # Explicit triplets: under Rosetta, uname still reports arm64 to
    # configure's child processes, so it cannot detect x86_64 by itself.
    run_x86 "$src/configure" --build=x86_64-apple-darwin --host=x86_64-apple-darwin \
        --prefix="$stage" --enable-archs=i386,x86_64 \
        --without-x --disable-tests >&2
    check_wine_config "$build/include/config.h"

    log "building $tag"
    run_x86 make -j"$(sysctl -n hw.ncpu)" >&2
    run_x86 make install >&2

    echo "$stage"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    set -euo pipefail
    [ $# -eq 1 ] || die "usage: $0 <tag>"
    main "$1"
fi
