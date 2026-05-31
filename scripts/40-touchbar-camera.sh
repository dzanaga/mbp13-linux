#!/usr/bin/env bash
set -Eeuo pipefail

MBP13_ROOT="${MBP13_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=scripts/00-lib.sh
source "$MBP13_ROOT/scripts/00-lib.sh"
load_config
require_root "$@"
setup_logging
ensure_ubuntu

SERVICE_HELPER="/usr/local/sbin/enable-apple-ibridge-touchbar"
SERVICE_FILE="/etc/systemd/system/apple-ibridge.service"
MODPROBE_FILE="/etc/modprobe.d/ibridge.conf"
MODULES_LOAD_FILE="/etc/modules-load.d/apple-ibridge.conf"

find_ibridge_usb() {
  local dev
  for dev in /sys/bus/usb/devices/*; do
    [ -r "$dev/idVendor" ] || continue
    [ -r "$dev/idProduct" ] || continue
    if [ "$(read_sysfs "$dev/idVendor")" = "05ac" ] &&
       [ "$(read_sysfs "$dev/idProduct")" = "8600" ]; then
      basename "$dev"
      return 0
    fi
  done
  return 1
}

build_touchbar_driver_if_needed() {
  local repo
  if modinfo apple-ibridge >/dev/null 2>&1 &&
     modinfo apple-ib-tb >/dev/null 2>&1 &&
     modinfo apple-ib-als >/dev/null 2>&1; then
    log "Legacy iBridge modules already available for $(uname -r)"
    return 0
  fi

  log "Legacy iBridge modules missing; cloning and attempting driver build"
  apt_install git gcc make dkms "linux-headers-$(uname -r)"
  repo="$WORK_DIR/mbp-t1-touchbar-driver"
  clone_or_update_repo "https://github.com/parport0/mbp-t1-touchbar-driver.git" "$repo"

  if [ -x "$repo/install.sh" ]; then
    run_in_dir "$repo" ./install.sh
  elif [ -f "$repo/dkms.conf" ]; then
    run ln -sfn "$repo" /usr/src/mbp-t1-touchbar-driver-0.1
    run dkms install -m mbp-t1-touchbar-driver -v 0.1 --force
  elif [ -f "$repo/Makefile" ]; then
    run_in_dir "$repo" make
    run_in_dir "$repo" make install
  else
    die "Could not find an install method in $repo"
  fi

  run depmod -a
}

install_touchbar_helper() {
  local helper service modprobe_conf modules_load

  modprobe_conf="# Managed by mbp13-linux-setup.
options apple-ib-tb idle_timeout=$TOUCHBAR_IDLE_TIMEOUT dim_timeout=$TOUCHBAR_DIM_TIMEOUT fnmode=$TOUCHBAR_FNMODE
"
  write_file_if_changed "$MODPROBE_FILE" 0644 "$modprobe_conf"

  modules_load="apple-ibridge
apple-ib-tb
apple-ib-als
"
  write_file_if_changed "$MODULES_LOAD_FILE" 0644 "$modules_load"

helper='#!/usr/bin/env bash
set -Eeuo pipefail

log() { printf "[%s] %s\n" "$(date "+%F %T")" "$*"; }
read_sysfs() { [ -r "$1" ] && cat "$1" 2>/dev/null || true; }
force_reconfigure=0

case "${1:-}" in
  "")
    ;;
  --resume|--force-reconfigure)
    force_reconfigure=1
    ;;
  *)
    printf "usage: %s [--resume|--force-reconfigure]\n" "$0" >&2
    exit 2
    ;;
esac

find_ibridge_usb() {
  local dev
  for dev in /sys/bus/usb/devices/*; do
    [ -r "$dev/idVendor" ] || continue
    [ -r "$dev/idProduct" ] || continue
    if [ "$(read_sysfs "$dev/idVendor")" = "05ac" ] &&
       [ "$(read_sysfs "$dev/idProduct")" = "8600" ]; then
      basename "$dev"
      return 0
    fi
  done
  return 1
}

if lsusb 2>/dev/null | grep -qi "05ac:1281"; then
  log "iBridge/T1 is in recovery mode; boot macOS/OCLP and repair bridgeOS"
  exit 1
fi

modprobe hid
modprobe usbhid
modprobe uvcvideo || true
modprobe apple-ibridge
modprobe apple-ib-tb
modprobe apple-ib-als || true

usbdev="$(find_ibridge_usb)" || { log "05ac:8600 iBridge not found"; exit 1; }
path="/sys/bus/usb/devices/$usbdev"

if [ "$force_reconfigure" = "1" ]; then
  log "Force reconfiguring iBridge USB configuration 1 for $usbdev"
  printf 0 >"$path/bConfigurationValue" 2>/dev/null || true
  sleep 1
  printf 1 >"$path/bConfigurationValue"
  sleep 2
elif [ "$(read_sysfs "$path/bConfigurationValue")" != "1" ]; then
  log "Selecting iBridge USB configuration 1 for $usbdev"
  printf 1 >"$path/bConfigurationValue"
  sleep 2
fi
printf on >"$path/power/control" 2>/dev/null || true

printf "%s" "$usbdev" >/sys/bus/usb/drivers_probe 2>/dev/null || true
for intf in "$usbdev":1.0 "$usbdev":1.1 "$usbdev":1.2 "$usbdev":1.3; do
  [ -e "/sys/bus/usb/devices/$intf" ] || continue
  printf "%s" "$intf" >/sys/bus/usb/drivers_probe 2>/dev/null || true
done

udevadm settle --timeout=10 || true
'
  write_file_if_changed "$SERVICE_HELPER" 0755 "$helper"

  service="[Unit]
Description=Enable Apple T1 iBridge Touch Bar and Camera
After=systemd-udev-settle.service
Wants=systemd-udev-settle.service

[Service]
Type=oneshot
ExecStart=$SERVICE_HELPER
RemainAfterExit=yes
TimeoutSec=30

[Install]
WantedBy=multi-user.target
"
  write_file_if_changed "$SERVICE_FILE" 0644 "$service"
  run systemctl daemon-reload
  run systemctl enable apple-ibridge.service
}

main() {
  local usbdev

  if lsusb 2>/dev/null | grep -qi '05ac:1281'; then
    die "iBridge/T1 is in recovery mode (05ac:1281); boot macOS/OCLP and repair bridgeOS first"
  fi

  build_touchbar_driver_if_needed
  install_touchbar_helper
  update_initramfs_if_available

  if usbdev="$(find_ibridge_usb)"; then
    log "Found iBridge at $usbdev"
  else
    die "Could not find 05ac:8600 Apple iBridge"
  fi

  run systemctl restart apple-ibridge.service
  mark_reboot_needed "Touch Bar/camera service installed"
}

main "$@"
