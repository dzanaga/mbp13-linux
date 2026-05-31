#!/usr/bin/env bash
set -Eeuo pipefail

MBP13_ROOT="${MBP13_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=scripts/00-lib.sh
source "$MBP13_ROOT/scripts/00-lib.sh"
load_config
require_root "$@"
setup_logging
ensure_ubuntu

SLEEP_CONF="/etc/systemd/sleep.conf.d/10-mbp13-suspend.conf"
SUSPEND_HOOK="/lib/systemd/system-sleep/mbp13-suspend"
SERVICE_HELPER="/usr/local/sbin/enable-apple-ibridge-touchbar"

validate_memory_sleep_mode() {
  case "$SUSPEND_MEMORY_SLEEP" in
    s2idle|deep) ;;
    *) die "SUSPEND_MEMORY_SLEEP must be s2idle or deep, got: $SUSPEND_MEMORY_SLEEP" ;;
  esac
}

set_memory_sleep_now() {
  if [ ! -r /sys/power/mem_sleep ]; then
    warn "/sys/power/mem_sleep is not readable; cannot select $SUSPEND_MEMORY_SLEEP"
    return 0
  fi
  if ! grep -qw "$SUSPEND_MEMORY_SLEEP" /sys/power/mem_sleep; then
    warn "Memory sleep mode $SUSPEND_MEMORY_SLEEP is not supported: $(cat /sys/power/mem_sleep)"
    return 0
  fi
  run sh -c 'printf "%s" "$1" >/sys/power/mem_sleep' sh "$SUSPEND_MEMORY_SLEEP"
  log "Selected memory sleep mode: $SUSPEND_MEMORY_SLEEP"
}

main() {
  local sleep_conf hook

  validate_memory_sleep_mode

  log "Installing suspend/resume support (mem_sleep=$SUSPEND_MEMORY_SLEEP)"

  sleep_conf="# Managed by mbp13-linux-setup.
[Sleep]
SuspendState=mem
MemorySleepMode=$SUSPEND_MEMORY_SLEEP
"
  write_file_if_changed "$SLEEP_CONF" 0644 "$sleep_conf"

  hook="#!/usr/bin/env bash
set -u

MEMORY_SLEEP_MODE=\"$SUSPEND_MEMORY_SLEEP\"
SERVICE_HELPER=\"$SERVICE_HELPER\"

set_memory_sleep_mode() {
  if [ -r /sys/power/mem_sleep ] && grep -qw \"\$MEMORY_SLEEP_MODE\" /sys/power/mem_sleep; then
    printf '%s' \"\$MEMORY_SLEEP_MODE\" >/sys/power/mem_sleep 2>/dev/null || true
  fi
}

case \"\${1:-}:\${2:-}\" in
  pre:suspend|pre:hybrid-sleep|pre:suspend-then-hibernate)
    set_memory_sleep_mode
    find /sys/devices -name d3cold_allowed -exec sh -c 'for f do printf 0 >\"\$f\" 2>/dev/null || true; done' sh {} +
    ;;
  post:suspend|post:hybrid-sleep|post:suspend-then-hibernate)
    if [ -x \"\$SERVICE_HELPER\" ]; then
      \"\$SERVICE_HELPER\" || true
    fi
    ;;
esac
"
  write_file_if_changed "$SUSPEND_HOOK" 0755 "$hook"

  set_memory_sleep_now
}

main "$@"
