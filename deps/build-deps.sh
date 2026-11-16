#!/bin/bash
# Usage: deps/build-deps.sh [name...]
# Builds the pinned x86_64 dependencies (default: all of DEPS_ORDER) into
# work/deps/prefix. A dependency whose stamp exists is skipped. The stamp is
# written only after a successful install.

# shellcheck source=scripts/fetch.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/../scripts/fetch.sh"
# shellcheck source=deps/manifest.sh
. "$REPO_ROOT/deps/manifest.sh"

DEPS_WORK="$WORK_DIR/deps"
NCPU="$(sysctl -n hw.ncpu)"

# --- build recipes. Each runs inside the unpacked source dir. --------------

autotools_build() {
    run_x86 ./configure --host=x86_64-apple-darwin --prefix="$DEPS_PREFIX" \
        --enable-shared --disable-static "$@"
    run_x86 make -j"$NCPU"
    run_x86 make install
}

build_dep_libpng() { autotools_build; }

# The explicit --host keeps gmp from tuning for the build machine's CPU.
build_dep_gmp() { autotools_build; }

build_dep_nettle() { autotools_build --disable-openssl --disable-documentation; }

build_dep_libtasn1() { autotools_build; }

build_dep_gnutls() {
    autotools_build --with-included-unistring --without-p11-kit --without-idn \
        --without-zstd --without-brotli --disable-doc --disable-tests \
        --disable-tools --disable-cxx
}

build_dep_freetype() {
    autotools_build --with-png=yes --with-zlib=yes --with-bzip2=yes \
        --with-harfbuzz=no --with-brotli=no
}

# cmake and ninja from Homebrew are arm64-only, so they cannot run under
# arch -x86_64. CMAKE_OSX_ARCHITECTURES sets the output architecture.
build_dep_sdl2() {
    cmake -S . -B build -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_OSX_ARCHITECTURES=x86_64 \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=12.0 \
        -DCMAKE_INSTALL_PREFIX="$DEPS_PREFIX" \
        -DSDL_STATIC=OFF -DSDL_TEST=OFF
    cmake --build build
    cmake --install build
}

# Prebuilt release: keep only the x86_64 slice. Wine ships its own Vulkan headers.
build_dep_moltenvk() {
    mkdir -p "$DEPS_PREFIX/lib"
    lipo -thin x86_64 MoltenVK/dynamic/dylib/macOS/libMoltenVK.dylib \
        -output "$DEPS_PREFIX/lib/libMoltenVK.dylib"
    install_name_tool -id "$DEPS_PREFIX/lib/libMoltenVK.dylib" "$DEPS_PREFIX/lib/libMoltenVK.dylib"
}

# zlib and bzip2 come from the macOS SDK, which has no .pc files on our
# isolated pkg-config path. libpng.pc requires zlib, so describe them here.
write_sdk_pkgconfig() {
    local dir=$1 name lib
    mkdir -p "$dir"
    for name in zlib:z bzip2:bz2; do
        lib=${name#*:}
        printf 'Name: %s\nDescription: %s from the macOS SDK\nVersion: 1.0\nLibs: -l%s\nCflags:\n' \
            "${name%%:*}" "${name%%:*}" "$lib" > "$dir/${name%%:*}.pc"
    done
}

# --- driver -------------------------------------------------------------

build_one() {
    local name=$1 version url sha tarball src stamp logfile rc errexit=
    version=$(dep_var "$name" VERSION)
    url=$(dep_var "$name" URL)
    sha=$(dep_var "$name" SHA256)
    [ -n "$version" ] || die "unknown dependency: $name"
    stamp="$DEPS_WORK/stamps/$name-$version"
    if [ -e "$stamp" ]; then
        log "$name $version up to date"
        return 0
    fi

    tarball="$DEPS_WORK/dl/$(basename "$url")"
    fetch_source "$url" "$sha" "$tarball"

    src="$DEPS_WORK/src/$name-$version"
    rm -rf "$src"
    mkdir -p "$src" "$DEPS_WORK/logs"
    tar xf "$tarball" -C "$src" --strip-components 1

    logfile="$DEPS_WORK/logs/$name-$version.log"
    log "building $name $version (log: $logfile)"
    case $- in *e*) errexit=1 ;; esac
    set +e
    ( set -e; cd "$src"; "build_dep_$name" ) > "$logfile" 2>&1
    rc=$?
    if [ -n "$errexit" ]; then set -e; fi
    if [ "$rc" -ne 0 ]; then
        tail -30 "$logfile" >&2
        die "$name $version build failed (log: $logfile)"
    fi

    mkdir -p "$DEPS_WORK/stamps"
    touch "$stamp"
}

main() {
    local name names
    names=${*:-$DEPS_ORDER}
    x86_env
    write_sdk_pkgconfig "$DEPS_PREFIX/lib/pkgconfig"
    for name in $names; do
        build_one "$name"
    done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    set -euo pipefail
    main "$@"
fi
