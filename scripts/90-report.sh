#!/usr/bin/env bash
set -Eeuo pipefail

MBP13_ROOT="${MBP13_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=scripts/00-lib.sh
source "$MBP13_ROOT/scripts/00-lib.sh"
load_config
require_root "$@"
setup_logging

section() {
  printf '\n== %s ==\n' "$1"
}

count_enabled_d3cold() {
  local count=0 file
  while IFS= read -r file; do
    if [ "$(cat "$file" 2>/dev/null || true)" = "1" ]; then
      count=$((count + 1))
    fi
  done < <(find /sys/devices -name d3cold_allowed -print 2>/dev/null)
  printf '%s\n' "$count"
}

module_path() {
  local module="$1"
  modinfo -n "$module" 2>/dev/null || true
}

main() {
  local iface

  section "module status"
  if [ -f "$REPORT_FILE" ]; then
    cat "$REPORT_FILE"
  else
    printf 'No module status file found\n'
  fi

  section "system"
  printf 'model: %s\n' "$(model_name)"
  printf 'kernel: %s\n' "$(uname -r)"
  if [ -r /etc/os-release ]; then
    . /etc/os-release
    printf 'os: %s\n' "${PRETTY_NAME:-unknown}"
  fi

  section "wifi"
  for iface_path in /sys/class/net/*; do
    iface="$(basename "$iface_path")"
    [ "$iface" = "lo" ] && continue
    [ -d "$iface_path/wireless" ] || continue
    printf '%s mac=%s\n' "$iface" "$(read_sysfs "$iface_path/address")"
    [ -L "$iface_path/device/driver/module" ] && printf 'module=%s\n' "$(basename "$(readlink "$iface_path/device/driver/module")")"
  done
  ls -l /usr/lib/firmware/brcm/brcmfmac43602-pcie*.txt 2>/dev/null || true

  section "sound"
  printf 'snd_hda_codec_cs8409: %s\n' "$(module_path snd_hda_codec_cs8409)"
  lsmod | grep -E '^snd_hda_codec_cs8409' || true
  dkms status 2>/dev/null | grep -i 'snd_hda_macbookpro' || true

  section "touchbar and camera"
  lsusb | grep -Ei '05ac:(8600|1281|8102|8302)' || true
  lsusb -t || true
  lsmod | grep -E 'apple_ibridge|apple_ib_tb|apple_ib_als|uvcvideo|usbhid|hid_appletb|appletbdrm' || true
  for param in idle_timeout dim_timeout fnmode; do
    printf '%s=' "$param"
    cat "/sys/module/apple_ib_tb/parameters/$param" 2>/dev/null || true
  done
  find /sys/class/video4linux -maxdepth 1 -mindepth 1 -printf '%f ' 2>/dev/null || true
  printf '\n'

  section "suspend"
  printf 'mem_sleep: '
  cat /sys/power/mem_sleep 2>/dev/null || true
  printf 'd3cold_allowed enabled count: %s\n' "$(count_enabled_d3cold)"
  [ -f /etc/systemd/sleep.conf.d/10-mbp13-suspend.conf ] && printf 'sleep drop-in: present\n' || printf 'sleep drop-in: missing\n'
  [ -x /lib/systemd/system-sleep/mbp13-suspend ] && printf 'system-sleep hook: present\n' || printf 'system-sleep hook: missing\n'

  section "reboot"
  if [ -s "$NEEDS_REBOOT_FILE" ]; then
    printf 'recommended: yes\n'
    sort -u "$NEEDS_REBOOT_FILE"
  else
    printf 'recommended: no explicit reboot marker\n'
  fi
}

main "$@"
