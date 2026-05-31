#!/usr/bin/env bash

MBP13_ROOT="${MBP13_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
CONFIG_FILE="${CONFIG_FILE:-$MBP13_ROOT/config.env}"

RUN_MISC="${RUN_MISC:-1}"
RUN_WIFI="${RUN_WIFI:-1}"
RUN_SOUND="${RUN_SOUND:-1}"
RUN_TOUCHBAR_CAMERA="${RUN_TOUCHBAR_CAMERA:-1}"
RUN_SUSPEND="${RUN_SUSPEND:-1}"
PASSWORDLESS_SUDO="${PASSWORDLESS_SUDO:-1}"
SUDOERS_MODE="${SUDOERS_MODE:-full-user-nopasswd}"
WIFI_COUNTRY="${WIFI_COUNTRY:-BE}"
WIFI_TEMPLATE="${WIFI_TEMPLATE:-assets/wifi/brcmfmac43602-pcie.template.txt}"
TOUCHBAR_FNMODE="${TOUCHBAR_FNMODE:-1}"
TOUCHBAR_IDLE_TIMEOUT="${TOUCHBAR_IDLE_TIMEOUT:--1}"
TOUCHBAR_DIM_TIMEOUT="${TOUCHBAR_DIM_TIMEOUT:--1}"
TOUCHBAR_RESUME_DELAY="${TOUCHBAR_RESUME_DELAY:-3}"
SUSPEND_MEMORY_SLEEP="${SUSPEND_MEMORY_SLEEP:-s2idle}"
WORK_DIR="${WORK_DIR:-/var/lib/mbp13-linux-setup}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/mbp13-linux-setup}"
LOG_FILE="${LOG_FILE:-/tmp/mbp13-linux-setup.log}"
REPORT_FILE="${REPORT_FILE:-/tmp/mbp13-linux-setup.report}"
DRY_RUN="${DRY_RUN:-0}"
NEEDS_REBOOT_FILE="${NEEDS_REBOOT_FILE:-/tmp/mbp13-linux-setup.needs-reboot}"

log() {
  printf '[%s] %s\n' "$(date '+%F %T')" "$*"
}

warn() {
  log "WARN: $*" >&2
}

die() {
  log "ERROR: $*" >&2
  exit 1
}

load_config() {
  if [ -f "$CONFIG_FILE" ]; then
    # This is intentionally a shell config owned by this repo.
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
  fi
}

setup_logging() {
  if [ "${MBP13_LOGGING_ACTIVE:-0}" = "1" ]; then
    return 0
  fi
  export MBP13_LOGGING_ACTIVE=1
  if [ "$DRY_RUN" = "1" ]; then
    log "DRY_RUN=1; mutating actions will be printed only"
  fi
  if ! : 2>/dev/null >>"$LOG_FILE"; then
    warn "Log file $LOG_FILE is not writable; using console output only"
    return 0
  fi
  exec > >(tee -a "$LOG_FILE") 2>&1
}

require_root() {
  if [ "$(id -u)" -eq 0 ]; then
    return 0
  fi
  if [ "$DRY_RUN" = "1" ]; then
    log "DRY_RUN=1; not escalating to root"
    return 0
  fi
  exec sudo \
    MBP13_ROOT="$MBP13_ROOT" \
    CONFIG_FILE="$CONFIG_FILE" \
    RUN_MISC="$RUN_MISC" \
    RUN_WIFI="$RUN_WIFI" \
    RUN_SOUND="$RUN_SOUND" \
    RUN_TOUCHBAR_CAMERA="$RUN_TOUCHBAR_CAMERA" \
    RUN_SUSPEND="$RUN_SUSPEND" \
    PASSWORDLESS_SUDO="$PASSWORDLESS_SUDO" \
    SUDOERS_MODE="$SUDOERS_MODE" \
    WIFI_COUNTRY="$WIFI_COUNTRY" \
    WIFI_TEMPLATE="$WIFI_TEMPLATE" \
    TOUCHBAR_FNMODE="$TOUCHBAR_FNMODE" \
    TOUCHBAR_IDLE_TIMEOUT="$TOUCHBAR_IDLE_TIMEOUT" \
    TOUCHBAR_DIM_TIMEOUT="$TOUCHBAR_DIM_TIMEOUT" \
    TOUCHBAR_RESUME_DELAY="$TOUCHBAR_RESUME_DELAY" \
    SUSPEND_MEMORY_SLEEP="$SUSPEND_MEMORY_SLEEP" \
    WORK_DIR="$WORK_DIR" \
    BACKUP_DIR="$BACKUP_DIR" \
    LOG_FILE="$LOG_FILE" \
    bash "$0" "$@"
}

is_enabled() {
  local name="$1"
  local value="${!name:-0}"
  case "$value" in
    1|yes|true|on|Y|y|TRUE|YES|ON) return 0 ;;
    *) return 1 ;;
  esac
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

run() {
  if [ "$DRY_RUN" = "1" ]; then
    printf '[dry-run]'
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}

run_in_dir() {
  local dir="$1"
  shift
  if [ "$DRY_RUN" = "1" ]; then
    printf '[dry-run] cd %q &&' "$dir"
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi
  (cd "$dir" && "$@")
}

ensure_dir() {
  local dir="$1"
  if [ "$DRY_RUN" = "1" ]; then
    log "[dry-run] mkdir -p $dir"
  else
    mkdir -p "$dir"
  fi
}

backup_file() {
  local path="$1"
  [ -e "$path" ] || return 0
  ensure_dir "$BACKUP_DIR"
  run cp -a "$path" "$BACKUP_DIR/$(basename "$path").$(date '+%Y%m%d-%H%M%S')"
}

write_file_if_changed() {
  local path="$1"
  local mode="$2"
  local content="$3"
  local tmp

  if [ "$DRY_RUN" = "1" ]; then
    log "[dry-run] write $path mode $mode"
    return 0
  fi

  tmp="$(mktemp)"
  printf '%s' "$content" >"$tmp"
  if [ -f "$path" ] && cmp -s "$tmp" "$path"; then
    chmod "$mode" "$path"
    chown root:root "$path"
    rm -f "$tmp"
    return 0
  fi
  backup_file "$path"
  install -o root -g root -m "$mode" -D "$tmp" "$path"
  rm -f "$tmp"
}

append_report() {
  printf '%s\n' "$*" >>"$REPORT_FILE"
}

init_report() {
  if [ "$DRY_RUN" = "1" ]; then
    log "[dry-run] initialize report $REPORT_FILE"
  else
    : >"$REPORT_FILE"
    rm -f "$NEEDS_REBOOT_FILE"
  fi
}

record_status() {
  append_report "$1: $2"
}

mark_reboot_needed() {
  if [ "$DRY_RUN" = "1" ]; then
    log "[dry-run] mark reboot needed: $*"
  else
    printf '%s\n' "$*" >>"$NEEDS_REBOOT_FILE"
  fi
}

apt_install() {
  local packages=("$@")
  [ "${#packages[@]}" -gt 0 ] || return 0

  if [ "$DRY_RUN" = "1" ]; then
    log "[dry-run] apt-get update"
    printf '[dry-run] apt-get install -y'
    printf ' %q' "${packages[@]}"
    printf '\n'
    return 0
  fi

  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y "${packages[@]}"
}

update_initramfs_if_available() {
  if command_exists update-initramfs; then
    run update-initramfs -u -k "$(uname -r)"
    mark_reboot_needed "initramfs updated"
  elif command_exists mkinitcpio; then
    run mkinitcpio -P
    mark_reboot_needed "initramfs updated"
  else
    warn "No supported initramfs updater found"
  fi
}

clone_or_update_repo() {
  local url="$1"
  local dest="$2"
  ensure_dir "$(dirname "$dest")"

  if [ -d "$dest/.git" ]; then
    run_in_dir "$dest" git pull --ff-only
  elif [ -e "$dest" ]; then
    die "$dest exists but is not a git repository"
  else
    run git clone "$url" "$dest"
  fi
}

setup_user() {
  if [ -n "${SETUP_USER:-}" ]; then
    printf '%s\n' "$SETUP_USER"
  elif [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
    printf '%s\n' "$SUDO_USER"
  elif command_exists logname && logname >/dev/null 2>&1; then
    logname
  else
    awk -F: '$3 == 1000 { print $1; exit }' /etc/passwd
  fi
}

model_name() {
  cat /sys/class/dmi/id/product_name 2>/dev/null || true
}

kernel_base_version() {
  uname -r | cut -d- -f1
}

read_sysfs() {
  local path="$1"
  [ -r "$path" ] && cat "$path" 2>/dev/null || true
}

ensure_ubuntu() {
  if [ ! -r /etc/os-release ] || ! grep -Eq '^(ID=ubuntu|ID_LIKE=.*ubuntu)' /etc/os-release; then
    die "This setup currently supports Ubuntu only"
  fi
}
