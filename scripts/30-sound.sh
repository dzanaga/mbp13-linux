#!/usr/bin/env bash
set -Eeuo pipefail

MBP13_ROOT="${MBP13_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=scripts/00-lib.sh
source "$MBP13_ROOT/scripts/00-lib.sh"
load_config
require_root "$@"
setup_logging
ensure_ubuntu

main() {
  local repo kernel_base source_pkg

  log "Installing Cirrus CS8409 MacBook audio driver"
  apt_install gcc make patch wget dkms "linux-headers-$(uname -r)"

  repo="$WORK_DIR/snd_hda_macbookpro"
  clone_or_update_repo "https://github.com/davidjo/snd_hda_macbookpro.git" "$repo"

  kernel_base="$(kernel_base_version)"
  source_pkg="linux-source-$kernel_base"
  if [ ! -e "/usr/src/linux-source-$kernel_base.tar.bz2" ]; then
    warn "Ubuntu kernel source /usr/src/linux-source-$kernel_base.tar.bz2 is missing"
    warn "Trying apt package $source_pkg; if unavailable, the driver installer will explain the required source package"
    apt_install "$source_pkg" || warn "Could not install $source_pkg"
  fi

  run_in_dir "$repo" ./install.cirrus.driver.sh -i
  run depmod -a
  update_initramfs_if_available
  mark_reboot_needed "sound driver installed"
}

main "$@"

