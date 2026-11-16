#!/bin/bash
# Usage: scripts/make-bundle.sh <tag> <stage_dir>
# Assembles dist/Wine-<version>.app from a Wine stage dir and the bundled
# dependencies, fixes up library paths, and signs it. Prints the app path last.

# shellcheck source=scripts/lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib.sh"

# list_macho <dir>: print every Mach-O file (not symlinks) under dir, one per line.
list_macho() {
    find "$1" -type f -exec file -0 {} + | tr '\0' '\t' \
        | awk -F'\t' '$2 ~ /Mach-O/ { print $1 }'
}

# find_foreign_paths <app>: print "file: path" for every load command or
# rpath pointing at Homebrew or the build tree. Exit 1 if any.
find_foreign_paths() {
    local app=$1 f hits found=0
    while IFS= read -r f; do
        hits=$( { otool -L "$f" | tail -n +2; otool -l "$f" | grep -A2 LC_RPATH | grep ' path '; } \
            | grep -E "/opt/homebrew|/usr/local|$WORK_DIR" | awk '{ print ($1 == "path") ? $2 : $1 }' || true)
        if [ -n "$hits" ]; then
            found=1
            printf '%s\n' "$hits" | while IFS= read -r line; do echo "$f: $line"; done
        fi
    done < <(list_macho "$app")
    return "$found"
}

# rpath_to_lib <wine_root> <file>: @loader_path-relative path from file's dir to wine_root/lib.
rpath_to_lib() {
    local root=$1 rel up=""
    rel=$(dirname "${2#"$root"/}")
    while [ "$rel" != "." ]; do
        up="../$up"
        rel=$(dirname "$rel")
    done
    echo "@loader_path/${up}lib"
}

# fix_macho <wine_root> <file>: point dependency-prefix references at @rpath and add an rpath.
fix_macho() {
    local root=$1 f=$2 dep rpath changed=0
    while IFS= read -r dep; do
        install_name_tool -change "$dep" "@rpath/$(basename "$dep")" "$f" 2>/dev/null
        changed=1
    done < <(otool -L "$f" | tail -n +2 | awk '{ print $1 }' | grep "^$DEPS_PREFIX/lib/" || true)
    if otool -L "$f" | grep -q '@rpath/'; then
        rpath=$(rpath_to_lib "$root" "$f")
        if ! otool -l "$f" | grep -A2 LC_RPATH | grep -q " path $rpath "; then
            install_name_tool -add_rpath "$rpath" "$f" 2>/dev/null
            changed=1
        fi
    fi
    if [ "$changed" = 1 ]; then
        codesign --force -s - "$f" 2>/dev/null
    fi
}

main() {
    local tag=$1 stage=$2 version app res root f launcher_dir
    [ -x "$stage/bin/wine" ] || die "not a Wine stage dir: $stage"
    version=${tag#wine-}
    app="$DIST_DIR/Wine-$version.app"
    res="$app/Contents/Resources"
    root="$res/wine"
    launcher_dir="$REPO_ROOT/scripts/launcher"

    log "assembling $app"
    rm -rf "$app"
    mkdir -p "$app/Contents/MacOS" "$root"
    sed "s/@VERSION@/$version/g" "$launcher_dir/Info.plist.in" > "$app/Contents/Info.plist"
    cp "$launcher_dir/wine" "$app/Contents/MacOS/wine"
    sed "s/@VERSION@/$version/g" "$launcher_dir/wine-shell.command" > "$res/wine-shell.command"
    chmod +x "$app/Contents/MacOS/wine" "$res/wine-shell.command"
    cp -a "$stage/." "$root/"
    mkdir -p "$root/lib"
    cp -a "$DEPS_PREFIX"/lib/*.dylib "$root/lib/"

    log "fixing up library paths"
    for f in "$DEPS_PREFIX"/lib/*.dylib; do
        [ -L "$f" ] && continue
        install_name_tool -id "@rpath/$(basename "$f")" "$root/lib/$(basename "$f")" 2>/dev/null
    done
    while IFS= read -r f; do
        fix_macho "$root" "$f"
    done < <(list_macho "$root")

    if ! find_foreign_paths "$app" >&2; then
        die "bundle still references Homebrew or build paths (listed above)"
    fi

    log "signing"
    codesign --force --deep -s "${SIGN_IDENTITY:--}" "$app"
    echo "$app"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    set -euo pipefail
    [ $# -eq 2 ] || die "usage: $0 <tag> <stage_dir>"
    main "$1" "$2"
fi
