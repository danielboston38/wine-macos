#!/bin/bash
# Usage: tests/run.sh [pattern]
# Runs every tests/test_*<pattern>*.sh, each in its own bash, and fails if any fail.
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd -P)"
pattern=${1:-}
failed=0

for t in "$TESTS_DIR"/test_*"$pattern"*.sh; do
    [ -e "$t" ] || { echo "no tests match '$pattern'" >&2; exit 1; }
    echo "# $(basename "$t")"
    if ! /bin/bash "$t"; then
        failed=1
    fi
done

exit "$failed"
