#!/bin/bash
set -uo pipefail
TESTS_DIR="$(cd "$(dirname "$0")" && pwd -P)"
# shellcheck source=tests/assert.sh
. "$TESTS_DIR/assert.sh"
# shellcheck source=scripts/make-bundle.sh
. "$TESTS_DIR/../scripts/make-bundle.sh" || { echo "FAIL - cannot source make-bundle.sh"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
echo 'int f(void) { return 1; }' > "$TMP/f.c"

# find_foreign_paths flags a Homebrew rpath
BAD="$TMP/Bad App.app"
mkdir -p "$BAD/Contents/Resources/wine/lib"
clang -arch x86_64 -dynamiclib -Wl,-rpath,/opt/homebrew/lib -install_name @rpath/libbad.dylib \
    -o "$BAD/Contents/Resources/wine/lib/libbad.dylib" "$TMP/f.c"
out=$(find_foreign_paths "$BAD"); rc=$?
assert_eq 1 "$rc" "find_foreign_paths fails on a Homebrew rpath"
assert_contains "$out" "libbad.dylib" "offending file named"

# ...and passes a clean one
GOOD="$TMP/Good App.app"
mkdir -p "$GOOD/Contents/Resources/wine/lib"
clang -arch x86_64 -dynamiclib -install_name @rpath/libgood.dylib \
    -o "$GOOD/Contents/Resources/wine/lib/libgood.dylib" "$TMP/f.c"
find_foreign_paths "$GOOD" >/dev/null; rc=$?
assert_eq 0 "$rc" "find_foreign_paths passes a clean app"

# strip_pe_debug removes debug info from both PE architectures
PE="$TMP/pe-root"
mkdir -p "$PE/lib/wine/x86_64-windows" "$PE/lib/wine/i386-windows"
x86_64-w64-mingw32-gcc -g -shared -o "$PE/lib/wine/x86_64-windows/f.dll" "$TMP/f.c"
i686-w64-mingw32-gcc -g -shared -o "$PE/lib/wine/i386-windows/f.dll" "$TMP/f.c"
assert_contains "$(x86_64-w64-mingw32-objdump -h "$PE/lib/wine/x86_64-windows/f.dll")" ".debug_info" "test DLL starts with debug info"
strip_pe_debug "$PE"
for a in x86_64 i386; do
    out=$(x86_64-w64-mingw32-objdump -h "$PE/lib/wine/$a-windows/f.dll" 2>&1)
    assert_eq 0 "$(echo "$out" | grep -c '\.debug_')" "$a DLL has no debug sections"
done

# launcher resolves its own location at run time (moved, renamed, spaces)
FAKE="$TMP/My Apps/Wine Devel.app"
mkdir -p "$FAKE/Contents/MacOS" "$FAKE/Contents/Resources/wine/bin"
cp "$TESTS_DIR/../scripts/launcher/wine" "$FAKE/Contents/MacOS/wine"
# shellcheck disable=SC2016  # expanded by the fake wine, not here
printf '#!/bin/bash\necho "root=$WINE_ROOT args=$*"\n' > "$FAKE/Contents/Resources/wine/bin/wine"
chmod +x "$FAKE/Contents/MacOS/wine" "$FAKE/Contents/Resources/wine/bin/wine"
out=$(env -i HOME="$HOME" PATH=/usr/bin:/bin "$FAKE/Contents/MacOS/wine" --version "a b")
assert_eq "root=$(cd "$FAKE" && pwd -P)/Contents/Resources/wine args=--version a b" "$out" \
    "launcher finds its own bundle and passes args through"

# launcher still finds its bundle when started through a symlink (e.g. /usr/local/bin/wine)
mkdir -p "$TMP/bin"
ln -s "$FAKE/Contents/MacOS/wine" "$TMP/bin/wine"
out=$(env -i HOME="$HOME" PATH=/usr/bin:/bin "$TMP/bin/wine" --version)
assert_eq "root=$(cd "$FAKE" && pwd -P)/Contents/Resources/wine args=--version" "$out" \
    "launcher works through a symlink"

# integration: real bundle from Task 4's stage
if [ "${BUNDLE_IT:-}" = 1 ]; then
    if ! app=$("$TESTS_DIR/../scripts/make-bundle.sh" wine-11.22 "$WORK_DIR/stage/wine-11.22" 2>"$TMP/bundle.log" | tail -1); then
        tail -40 "$TMP/bundle.log"; echo "FAIL - make-bundle.sh"; exit 1
    fi
    assert_eq "$DIST_DIR/Wine-11.22.app" "$app" "app path printed last"
    find_foreign_paths "$app"; rc=$?
    assert_eq 0 "$rc" "no foreign paths in the app"
    codesign --verify --deep --strict "$app"; rc=$?
    assert_eq 0 "$rc" "codesign verifies"
    assert_eq 0 "$(x86_64-w64-mingw32-objdump -h "$app/Contents/Resources/wine/lib/wine/x86_64-windows/kernel32.dll" | grep -c '\.debug_')" \
        "bundled kernel32.dll has no debug sections"
    assert_eq 11.22 "$(plutil -extract CFBundleShortVersionString raw "$app/Contents/Info.plist")" "version in Info.plist"
    MOVED="$TMP/My Apps/Wine Devel.app"
    rm -rf "$MOVED"
    cp -R "$app" "$MOVED"
    out=$(env -i HOME="$HOME" PATH=/usr/bin:/bin "$MOVED/Contents/MacOS/wine" --version 2>&1)
    assert_eq wine-11.22 "$out" "moved and renamed app runs wine --version"
fi

finish_tests
