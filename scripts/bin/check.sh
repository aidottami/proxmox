#!/usr/bin/env bash

set -Eeuo pipefail

echo "== Syntax check =="

find scripts -type f -name "*.sh" -print0 |
    while IFS= read -r -d '' file; do
        bash -n "$file"
    done

echo "✔ bash -n"

echo
echo "== ShellCheck =="

find scripts -type f -name "*.sh" -print0 |
while IFS= read -r -d '' file; do
    shellcheck -x "$file"

done
echo "✔ shellcheck"

echo
echo "All checks passed."
