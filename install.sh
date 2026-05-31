#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export MBP13_ROOT="$ROOT_DIR"

# shellcheck source=scripts/00-lib.sh
source "$ROOT_DIR/scripts/00-lib.sh"
load_config
require_root "$@"
setup_logging

run_selected_module() {
  local flag="$1"
  local label="$2"
  local script="$3"

  if is_enabled "$flag"; then
    log "Running $label"
    if bash "$ROOT_DIR/$script"; then
      record_status "$label" "ok"
    else
      local status=$?
      record_status "$label" "failed ($status)"
      warn "$label failed; stopping before later modules"
      return "$status"
    fi
  else
    log "Skipping $label ($flag=0)"
    record_status "$label" "skipped"
  fi
}

main() {
  local status=0

  init_report
  log "Starting MacBookPro13 Linux setup"
  log "Config: $CONFIG_FILE"

  run_selected_module RUN_WIFI "wifi" scripts/20-wifi.sh || status=$?
  if [ "$status" -eq 0 ]; then run_selected_module RUN_MISC "misc" scripts/10-misc.sh || status=$?; fi
  if [ "$status" -eq 0 ]; then run_selected_module RUN_SOUND "sound" scripts/30-sound.sh || status=$?; fi
  if [ "$status" -eq 0 ]; then run_selected_module RUN_TOUCHBAR_CAMERA "touchbar-camera" scripts/40-touchbar-camera.sh || status=$?; fi
  if [ "$status" -eq 0 ]; then run_selected_module RUN_SUSPEND "suspend" scripts/50-suspend.sh || status=$?; fi

  bash "$ROOT_DIR/scripts/90-report.sh" || true

  if [ "$status" -eq 0 ]; then
    log "Setup completed"
  else
    warn "Setup stopped with status $status"
  fi

  exit "$status"
}

main "$@"
