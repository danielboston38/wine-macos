#!/bin/bash
# Opened in Terminal when Wine.app is double-clicked.
app="$(cd "$(dirname "$0")/../.." && pwd -P)"
export WINE_ROOT="$app/Contents/Resources/wine"
export DYLD_FALLBACK_LIBRARY_PATH="$WINE_ROOT/lib:/usr/lib"
# Contents/MacOS comes first so "wine" goes through the launcher, which sets
# DYLD_FALLBACK_LIBRARY_PATH again (macOS drops DYLD_* vars when it starts
# the system shell).
export PATH="$app/Contents/MacOS:$WINE_ROOT/bin:$PATH"
echo "Wine @VERSION@ ready: try 'wine winecfg'"
exec "$SHELL" -l
