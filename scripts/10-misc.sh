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
  local user sudoers_file content
  user="$(setup_user)"
  [ -n "$user" ] || die "Could not determine setup user for sudoers configuration"

  log "Installing miscellaneous baseline packages"
  apt_install git curl wget ca-certificates build-essential dkms "linux-headers-$(uname -r)"

  if is_enabled PASSWORDLESS_SUDO; then
    if [ "$SUDOERS_MODE" != "full-user-nopasswd" ]; then
      die "Unsupported SUDOERS_MODE=$SUDOERS_MODE"
    fi
    log "Installing full passwordless sudo for $user"
    sudoers_file="/etc/sudoers.d/90-mbp13-linux-setup-$user"
    content="$user ALL=(ALL) NOPASSWD:ALL
"
    write_file_if_changed "$sudoers_file" 0440 "$content"
    if [ "$DRY_RUN" != "1" ]; then
      visudo -cf "$sudoers_file"
    fi
  else
    log "Skipping passwordless sudo"
  fi

  if command_exists gsettings && [ -n "$user" ]; then
    log "Disabling GNOME auto-brightness when available"
    if [ "$DRY_RUN" = "1" ]; then
      log "[dry-run] sudo -u $user gsettings set org.gnome.settings-daemon.plugins.power ambient-enabled false"
    elif sudo -u "$user" gsettings writable org.gnome.settings-daemon.plugins.power ambient-enabled >/dev/null 2>&1; then
      sudo -u "$user" gsettings set org.gnome.settings-daemon.plugins.power ambient-enabled false || warn "Could not write GNOME auto-brightness setting"
    else
      warn "GNOME auto-brightness setting not available for $user"
    fi
  else
    warn "gsettings not available; skipping auto-brightness"
  fi

  log "TODO: add personal installs here later, for example Node.js and Chrome"
}

main "$@"

