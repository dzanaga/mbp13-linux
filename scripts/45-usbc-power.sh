#!/usr/bin/env bash
set -Eeuo pipefail

MBP13_ROOT="${MBP13_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=scripts/00-lib.sh
source "$MBP13_ROOT/scripts/00-lib.sh"
load_config
require_root "$@"
setup_logging
ensure_ubuntu

HELPER="/usr/local/sbin/mbp13-usbc-power"
SERVICE="/etc/systemd/system/mbp13-usbc-power.service"
SLEEP_HOOK="/lib/systemd/system-sleep/mbp13-usbc-power"

main() {
  local helper service sleep_hook

  log "Installing USB-C controller power workaround"

  helper="#!/usr/bin/env bash
set -u

DISABLE_D3COLD=\"$USBC_POWER_DISABLE_D3COLD\"
KEEP_NHI=\"$USBC_POWER_KEEP_NHI\"

is_enabled_value() {
  case \"\${1:-0}\" in
    1|yes|true|on|Y|y|TRUE|YES|ON) return 0 ;;
    *) return 1 ;;
  esac
}

should_manage_device() {
  local devpath=\"\$1\" vendor device

  vendor=\"\$(cat \"\$devpath/vendor\" 2>/dev/null || true)\"
  device=\"\$(cat \"\$devpath/device\" 2>/dev/null || true)\"

  [ \"\$vendor\" = \"0x8086\" ] || return 1
  case \"\$device\" in
    0x15d4) return 0 ;;
    0x15d2)
      is_enabled_value \"\$KEEP_NHI\"
      return \$?
      ;;
    *) return 1 ;;
  esac
}

apply_device() {
  local devpath=\"\$1\" pciid

  pciid=\"\$(basename \"\$devpath\")\"
  [ -w \"\$devpath/power/control\" ] && printf on >\"\$devpath/power/control\"
  if is_enabled_value \"\$DISABLE_D3COLD\" && [ -w \"\$devpath/d3cold_allowed\" ]; then
    printf 0 >\"\$devpath/d3cold_allowed\"
  fi
  printf '%s control=%s runtime=%s d3cold=%s\n' \
    \"\$pciid\" \
    \"\$(cat \"\$devpath/power/control\" 2>/dev/null || printf unknown)\" \
    \"\$(cat \"\$devpath/power/runtime_status\" 2>/dev/null || printf unknown)\" \
    \"\$(cat \"\$devpath/d3cold_allowed\" 2>/dev/null || printf n/a)\"
}

apply_all() {
  local devpath found=0

  for devpath in /sys/bus/pci/devices/*; do
    if should_manage_device \"\$devpath\"; then
      found=1
      apply_device \"\$devpath\"
    fi
  done

  if [ \"\$found\" -eq 0 ]; then
    printf 'No matching Alpine Ridge USB-C controllers found\n' >&2
    return 1
  fi
}

case \"\${1:-apply}\" in
  apply|--resume|--status) apply_all ;;
  *) printf 'usage: %s [apply|--resume|--status]\n' \"\$0\" >&2; exit 2 ;;
esac
"
  write_file_if_changed "$HELPER" 0755 "$helper"

  service="[Unit]
Description=Keep MacBookPro13 USB-C controllers awake
After=sysinit.target

[Service]
Type=oneshot
ExecStart=$HELPER apply
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
"
  write_file_if_changed "$SERVICE" 0644 "$service"

  sleep_hook="#!/usr/bin/env bash
set -u

HELPER=\"$HELPER\"

case \"\${1:-}:\${2:-}\" in
  pre:suspend|pre:hybrid-sleep|pre:suspend-then-hibernate|post:suspend|post:hybrid-sleep|post:suspend-then-hibernate)
    [ -x \"\$HELPER\" ] && \"\$HELPER\" --resume >/dev/null 2>&1 || true
    ;;
esac
"
  write_file_if_changed "$SLEEP_HOOK" 0755 "$sleep_hook"

  run systemctl daemon-reload
  run systemctl enable --now mbp13-usbc-power.service
  run "$HELPER" --status
}

main "$@"
