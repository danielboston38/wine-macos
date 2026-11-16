#!/bin/bash
# Usage: ./build.sh <tag> [--clean]
# Builds dist/Wine-<version>.app from an upstream Wine tag, e.g. wine-11.22.
# --clean rebuilds Wine from scratch (the dependency cache is kept).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd -P)"
# shellcheck source=scripts/build-wine.sh
. "$ROOT/scripts/build-wine.sh"

usage() { echo "usage: $0 <tag> [--clean]   (example: $0 wine-11.22)" >&2; exit 2; }

tag="" clean=""
for arg in "$@"; do
    case $arg in
        --clean) clean=1 ;;
        -*) usage ;;
        *) [ -z "$tag" ] || usage; tag=$arg ;;
    esac
done
[ -n "$tag" ] || usage

check_prereqs
validate_tag "$tag"

if [ -n "$clean" ]; then
    log "removing previous Wine build for $tag"
    rm -rf "$WORK_DIR/wine-build/$tag" "$WORK_DIR/stage/$tag"
fi

"$ROOT/deps/build-deps.sh"
stage=$("$ROOT/scripts/build-wine.sh" "$tag" | tail -1)
app=$("$ROOT/scripts/make-bundle.sh" "$tag" "$stage" | tail -1)
echo "Built: $app"
