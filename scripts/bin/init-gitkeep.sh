#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

cd "$REPO_ROOT"

count=0

while IFS= read -r -d '' dir; do
    touch "$dir/.gitkeep"
    echo "Creato: ${dir#./}/.gitkeep"
    ((count += 1))
done < <(
    find . \
        -type d \
        -empty \
        -not -path "./.git/*" \
        -print0
)

if (( count == 0 )); then
    echo "Nessuna directory vuota trovata."
else
    echo "Creati $count file .gitkeep."
fi
