#!/bin/bash
# Usage: scripts/install-dxvk.sh <prefix>
# Installs DXVK-macOS (Direct3D 10/11 -> Vulkan -> MoltenVK) into an existing
# Wine prefix and sets the DLL overrides that make Wine use it.
# WINE names the launcher to use (default: wine on PATH).

# shellcheck source=scripts/fetch.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/fetch.sh"

# Gcenx's macOS fork: upstream DXVK needs Vulkan features MoltenVK lacks.
DXVK_VERSION=v1.10.3-20230507-repack
DXVK_URL="https://github.com/Gcenx/DXVK-macOS/releases/download/$DXVK_VERSION/dxvk-macOS-async-$DXVK_VERSION.tar.gz"
DXVK_SHA256=acd1520ad105d8ef124a09c8e11a259a5dc8bdc565ad18e0e52693f9807b2477
DXVK_DLLS="d3d10core d3d11"

# check_prefix <prefix>: die unless prefix is a booted 64-bit Wine prefix.
check_prefix() {
    local prefix=$1
    [ -d "$prefix/drive_c/windows/system32" ] && [ -d "$prefix/drive_c/windows/syswow64" ] \
        || die "not a Wine prefix: $prefix (create it first: WINEPREFIX=$prefix wine wineboot)"
}

# copy_dlls <tarball> <prefix>: unpack and copy 64-bit DLLs to system32 and
# 32-bit DLLs to syswow64.
copy_dlls() {
    local tarball=$1 prefix=$2 tmp dir dll
    tmp=$(mktemp -d)
    tar -xzf "$tarball" -C "$tmp" || { rm -rf "$tmp"; die "cannot unpack $tarball"; }
    dir=$(find "$tmp" -mindepth 1 -maxdepth 1 -type d | head -1)
    for dll in $DXVK_DLLS; do
        if ! cp "$dir/x64/$dll.dll" "$prefix/drive_c/windows/system32/" \
            || ! cp "$dir/x32/$dll.dll" "$prefix/drive_c/windows/syswow64/"; then
            rm -rf "$tmp"
            die "$dll.dll missing from $tarball"
        fi
    done
    rm -rf "$tmp"
}

run_wine() { WINEPREFIX=$1 "$WINE" "${@:2}"; }

# set_overrides <prefix>: tell Wine to load the DXVK DLLs instead of its own.
set_overrides() {
    local prefix=$1 dll
    for dll in $DXVK_DLLS; do
        run_wine "$prefix" reg add 'HKEY_CURRENT_USER\Software\Wine\DllOverrides' \
            /v "$dll" /t REG_SZ /d native /f >/dev/null \
            || die "cannot set DLL override for $dll"
    done
}

main() {
    [ $# -eq 1 ] || die "usage: scripts/install-dxvk.sh <prefix>"
    local prefix tarball
    prefix=$(cd "$1" 2>/dev/null && pwd -P) || die "no such directory: $1"
    check_prefix "$prefix"
    WINE=${WINE:-$(command -v wine)} \
        || die "wine not on PATH; set WINE=/Applications/Wine-11.22.app/Contents/MacOS/wine"
    tarball="$WORK_DIR/downloads/dxvk-macOS-$DXVK_VERSION.tar.gz"
    fetch_source "$DXVK_URL" "$DXVK_SHA256" "$tarball"
    copy_dlls "$tarball" "$prefix"
    set_overrides "$prefix"
    log "DXVK $DXVK_VERSION installed in $prefix"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    set -euo pipefail
    main "$@"
fi
