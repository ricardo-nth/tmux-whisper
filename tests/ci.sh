#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

bash_files=()
while IFS= read -r f; do
  bash_files+=("$f")
done < <(printf '%s\n' install.sh bootstrap.sh && rg --files -g '*.sh' bin integrations tools tests)

for f in "${bash_files[@]}"; do
  bash -n "$f"
done

echo "Syntax checks passed."

./tests/test_lib.sh
./tests/test_install.sh
./tests/test_bootstrap.sh

echo "All CI checks passed."
