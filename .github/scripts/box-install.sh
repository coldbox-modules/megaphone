#!/usr/bin/env bash
set -euo pipefail

for attempt in 1 2 3; do
  if box install "$@"; then
    exit 0
  fi

  if [[ "$attempt" -lt 3 ]]; then
    echo "::warning::Dependency installation failed on attempt $attempt; retrying in 5 seconds."
    sleep 5
  fi
done

echo "::error::Dependency installation failed after 3 attempts."
exit 1
