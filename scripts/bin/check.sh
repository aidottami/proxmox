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

shellcheck -x \
    $(find scripts -type f -name "*.sh")

echo "✔ shellcheck"

echo
echo "All checks passed."
