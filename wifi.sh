#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export MBP13_ROOT="$ROOT_DIR"
exec bash "$ROOT_DIR/scripts/20-wifi.sh" "$@"

