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
        || die "unknown Wine tag: $tag (try: git -C \"$WINE_GIT\" tag -l 'wine-[0-9]*.*' --sort=v:refname | tail)"
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
    # The app bundles MoltenVK, not a Vulkan loader, and the launcher hides
    # /usr/local/lib, so any other Vulkan library fails to load at run time.
    grep -q '^#define SONAME_LIBVULKAN "libMoltenVK.dylib"' "$config" \
        || die "Wine configured with a Vulkan library other than the bundled MoltenVK (rebuild with --clean)"
}

# configure_wine <src> <build> <stage>: run configure in build, unless an
# earlier run left config.status there and deps/manifest.sh has not changed
# since. configure records each bundled library's file name (e.g.
# libgnutls.30.dylib), so a dependency bump must reconfigure. make reruns
# configure itself when Wine's own configure changes; --clean forces it.
configure_wine() {
    local src=$1 build=$2 stage=$3 deps_sum
    deps_sum=$(shasum -a 256 < "$REPO_ROOT/deps/manifest.sh")
    if [ -e "$build/config.status" ] && [ "$(cat "$build/deps-manifest.sha256" 2>/dev/null)" = "$deps_sum" ]; then
        log "already configured, skipping configure (use --clean to redo)"
    else
        log "configuring $(basename "$build")"
        # Explicit triplets: under Rosetta, uname still reports arm64 to
        # configure's child processes, so it cannot detect x86_64 by itself.
        # ac_cv_lib_soname_vulkan= marks the Vulkan loader as not found, so
        # configure uses the bundled MoltenVK even when a Vulkan SDK in
        # /usr/local/lib (on the linker's default path) provides libvulkan.
        (cd "$build" && run_x86 "$src/configure" --build=x86_64-apple-darwin \
            --host=x86_64-apple-darwin --prefix="$stage" --enable-archs=i386,x86_64 \
            --without-x --disable-tests ac_cv_lib_soname_vulkan= >&2)
        echo "$deps_sum" > "$build/deps-manifest.sha256"
    fi
    check_wine_config "$build/include/config.h"
}

# apply_patches <src> <patch_dir>: apply <patch_dir>/*.patch to the Wine
# checkout <src>, in name order, once. A stamp in the checkout's git dir
# records what was applied, so reruns are no-ops; if the patches change, stop
# rather than guess, since the checkout would need resetting first.
apply_patches() {
    local src=$1 dir=$2 stamp sum patch
    local patches=("$dir"/*.patch)
    [ -e "${patches[0]}" ] || return 0
    stamp=$(git -C "$src" rev-parse --path-format=absolute --git-path wine-macos-patches) || die "not a git checkout: $src"
    sum=$(cat "${patches[@]}" | shasum -a 256)
    if [ -e "$stamp" ]; then
        [ "$(cat "$stamp")" = "$sum" ] && return 0
        die "patches in $dir changed since they were applied to $src; reset it first: git -C \"$src\" checkout -- . && rm \"$stamp\""
    fi
    for patch in "${patches[@]}"; do
        log "applying $(basename "$patch")"
        git -C "$src" apply "$patch" >&2 || die "patch does not apply: $(basename "$patch")"
    done
    echo "$sum" > "$stamp"
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
    apply_patches "$src" "$REPO_ROOT/patches"

    x86_env
    if command -v ccache >/dev/null; then
        export CC="ccache clang -arch x86_64"
    fi

    mkdir -p "$build"
    cd "$build"
    configure_wine "$src" "$build" "$stage"

    log "building $tag"
    run_x86 make -j"$(sysctl -n hw.ncpu)" >&2
    # install-lib: only what running programs needs (no headers, import libs
    # or winegcc). Start from an empty stage so nothing stale is left over.
    rm -rf "$stage"
    run_x86 make install-lib >&2

    echo "$stage"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    set -euo pipefail
    [ $# -eq 1 ] || die "usage: $0 <tag>"
    main "$1"
fi
