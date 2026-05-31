#!/usr/bin/env bash
set -Eeuo pipefail

MBP13_ROOT="${MBP13_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=scripts/00-lib.sh
source "$MBP13_ROOT/scripts/00-lib.sh"
load_config

find_brcmfmac_iface() {
  local iface module driver
  for iface_path in /sys/class/net/*; do
    iface="$(basename "$iface_path")"
    [ "$iface" = "lo" ] && continue
    [ -d "$iface_path/wireless" ] || continue
    module=""
    driver=""
    [ -L "$iface_path/device/driver/module" ] && module="$(basename "$(readlink "$iface_path/device/driver/module")")"
    [ -L "$iface_path/device/driver" ] && driver="$(basename "$(readlink "$iface_path/device/driver")")"
    if [ "$module" = "brcmfmac" ] || [ "$driver" = "brcmfmac" ]; then
      printf '%s\n' "$iface"
      return 0
    fi
  done

  for iface_path in /sys/class/net/*; do
    iface="$(basename "$iface_path")"
    [ "$iface" = "lo" ] && continue
    [ -d "$iface_path/wireless" ] || continue
    printf '%s\n' "$iface"
    return 0
  done

  return 1
}

wifi_mac_address() {
  local iface="$1"
  local mac
  mac="$(read_sysfs "/sys/class/net/$iface/address")"
  [ -n "$mac" ] || return 1
  printf '%s\n' "$mac"
}

render_template() {
  local template="$1"
  local mac="$2"
  local country="$3"
  sed \
    -e "s/{{WIFI_MACADDR}}/$mac/g" \
    -e "s/{{WIFI_COUNTRY}}/$country/g" \
    "$template"
}

main() {
  local iface mac template_abs firmware_dir model rendered targets target

  iface="$(find_brcmfmac_iface)" || die "Could not find a wireless Broadcom/brcmfmac interface"

  if [ "${1:-}" = "--print-mac" ]; then
    wifi_mac_address "$iface"
    exit 0
  fi

  require_root "$@"
  setup_logging
  ensure_ubuntu

  log "Installing offline Wi-Fi firmware/NVRAM support"
  mac="$(wifi_mac_address "$iface")"
  [ -n "$mac" ] || die "Could not read MAC address for $iface"

  template_abs="$MBP13_ROOT/$WIFI_TEMPLATE"
  [ -r "$template_abs" ] || die "Missing Wi-Fi template: $template_abs"

  firmware_dir="/usr/lib/firmware/brcm"
  ensure_dir "$firmware_dir"
  rendered="$(render_template "$template_abs" "$mac" "$WIFI_COUNTRY")"
  model="$(model_name)"

  targets=("$firmware_dir/brcmfmac43602-pcie.txt")
  if [ -n "$model" ]; then
    targets+=("$firmware_dir/brcmfmac43602-pcie.Apple Inc.-$model.txt")
  fi

  log "Detected Wi-Fi interface $iface with MAC $mac"
  for target in "${targets[@]}"; do
    log "Installing $(basename "$target") for $iface"
    write_file_if_changed "$target" 0644 "$rendered"
  done

  if command_exists iw; then
    run iw reg set "$WIFI_COUNTRY" || warn "Could not set regulatory domain to $WIFI_COUNTRY"
  else
    warn "iw is not installed; skipping live regulatory-domain command"
  fi

  update_initramfs_if_available
  mark_reboot_needed "Wi-Fi firmware installed"
}

main "$@"
