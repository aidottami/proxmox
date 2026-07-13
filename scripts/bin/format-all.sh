#!/usr/bin/env bash
##############################################################################
#
# Script: format-all.sh
#
# Description:
#   Format all Bash scripts in the repository using shfmt.
#
##############################################################################

set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly SCRIPT_DIR

REPO_ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd)
readonly REPO_ROOT

if ! command -v shfmt >/dev/null 2>&1; then
    echo "ERROR: shfmt is not installed."
    echo
    echo "Install it with:"
    echo "  brew install shfmt"
    echo
    exit 1
fi

echo "============================================================"
echo "Formatting Bash scripts"
echo "============================================================"
echo

while IFS= read -r -d '' file; do
    echo "Formatting: ${file#"$REPO_ROOT"/}"
    shfmt -w -i 4 -ci "$file"
done < <(
    find "$REPO_ROOT" \
        -type f \
        -name "*.sh" \
        -not -path "*/.git/*" \
        -not -path "*/vendor/*" \
        -not -path "*/.venv/*" \
        -print0
)

echo
echo "Done."
