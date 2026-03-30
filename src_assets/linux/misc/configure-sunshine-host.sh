#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="${0##*/}"
CAPTURE_BACKEND="${SUNSHINE_CAPTURE_BACKEND:-kms}"
HOST=""
LOCAL_ONLY=0
DRY_RUN=0
SSH_BIN="${SUNSHINE_SSH_BIN:-ssh}"

usage() {
  cat <<EOF
Usage: ${SCRIPT_NAME} [--host <user@host>] [--capture <backend>] [--dry-run]

Configure Sunshine on a Linux machine by:
  - Setting ~/.config/sunshine/sunshine.conf capture backend
  - Creating/updating ~/.config/systemd/user/sunshine.service
  - Enabling and starting the user service

Options:
  --host <user@host>   Configure a remote machine over SSH.
  --capture <backend>  Capture backend to set (default: kms).
  --dry-run            Print planned actions without changing files/services.
  --local              Internal use: force local execution path.
  -h, --help           Show this help message.

Examples:
  ${SCRIPT_NAME}
  ${SCRIPT_NAME} --capture x11
  ${SCRIPT_NAME} --host mini
  ${SCRIPT_NAME} --host colivier@mini --capture kms
EOF
}

log() {
  printf '%s\n' "$*"
}

warn() {
  printf 'warning: %s\n' "$*" >&2
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --host)
        [ "$#" -ge 2 ] || die "--host requires a value"
        HOST="$2"
        shift 2
        ;;
      --capture)
        [ "$#" -ge 2 ] || die "--capture requires a value"
        CAPTURE_BACKEND="$2"
        shift 2
        ;;
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      --local)
        LOCAL_ONLY=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "unknown argument: $1"
        ;;
    esac
  done
}

validate_capture_backend() {
  if ! printf '%s' "$CAPTURE_BACKEND" | grep -Eq '^[A-Za-z0-9_-]+$'; then
    die "invalid capture backend: ${CAPTURE_BACKEND}"
  fi
}

run_remote() {
  [ -n "$HOST" ] || return 1

  log "Applying Sunshine configuration on remote host: ${HOST}"
  local remote_cmd=(bash -s -- --local --capture "$CAPTURE_BACKEND")
  if [ "$DRY_RUN" -eq 1 ]; then
    remote_cmd+=(--dry-run)
  fi

  "${SSH_BIN}" "$HOST" "${remote_cmd[@]}" < "$0"
  exit $?
}

find_sunshine_binary() {
  local candidate
  candidate="$(command -v sunshine 2>/dev/null || true)"

  for path in "$candidate" /usr/local/bin/sunshine /usr/bin/sunshine; do
    [ -n "$path" ] || continue
    if [ -e "$path" ]; then
      local resolved
      resolved="$(readlink -f "$path" 2>/dev/null || printf '%s' "$path")"
      if [ -x "$resolved" ]; then
        printf '%s\n' "$resolved"
        return 0
      fi
    fi
  done

  return 1
}

ensure_capture_config() {
  local config_dir="${HOME}/.config/sunshine"
  local config_file="${config_dir}/sunshine.conf"

  if [ "$DRY_RUN" -eq 1 ]; then
    log "[dry-run] ensure ${config_file} contains: capture = ${CAPTURE_BACKEND}"
    return 0
  fi

  mkdir -p "$config_dir"

  if [ -f "$config_file" ]; then
    local tmp_file
    tmp_file="$(mktemp)"
    if grep -Eq '^[[:space:]]*capture[[:space:]]*=' "$config_file"; then
      sed -E "s|^[[:space:]]*capture[[:space:]]*=.*$|capture = ${CAPTURE_BACKEND}|" \
        "$config_file" > "$tmp_file"
    else
      cat "$config_file" > "$tmp_file"
      printf '\n# Set by %s\ncapture = %s\n' "$SCRIPT_NAME" "$CAPTURE_BACKEND" >> "$tmp_file"
    fi
    mv "$tmp_file" "$config_file"
  else
    cat > "$config_file" <<EOF
# Set by ${SCRIPT_NAME}
capture = ${CAPTURE_BACKEND}
EOF
  fi

  chmod 0644 "$config_file" || true
}

write_user_service() {
  local sunshine_bin="$1"
  local unit_dir="${HOME}/.config/systemd/user"
  local unit_file="${unit_dir}/sunshine.service"

  if [ "$DRY_RUN" -eq 1 ]; then
    log "[dry-run] write ${unit_file} with ExecStart=${sunshine_bin}"
    return 0
  fi

  mkdir -p "$unit_dir"
  cat > "$unit_file" <<EOF
[Unit]
Description=Sunshine Game Stream Host
After=graphical-session.target xdg-desktop-autostart.target network-online.target
Wants=network-online.target

[Service]
ExecStartPre=/bin/sleep 5
ExecStart=${sunshine_bin}
Restart=on-failure
RestartSec=5s
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

[Install]
WantedBy=default.target
WantedBy=graphical-session.target
EOF
}

apply_local() {
  command -v systemctl >/dev/null 2>&1 || die "systemctl not found"

  local sunshine_bin
  sunshine_bin="$(find_sunshine_binary)" || die "sunshine binary not found in PATH, /usr/local/bin, or /usr/bin"

  log "Using Sunshine binary: ${sunshine_bin}"
  ensure_capture_config
  write_user_service "$sunshine_bin"

  if [ "$DRY_RUN" -eq 1 ]; then
    log "[dry-run] systemctl --user daemon-reload"
    log "[dry-run] systemctl --user enable --now sunshine"
    return 0
  fi

  if ! systemctl --user show-environment >/dev/null 2>&1; then
    die "systemctl --user is unavailable (no user manager/session bus)"
  fi

  if ! systemctl --user show-environment | grep -q '^DISPLAY='; then
    warn "DISPLAY is not set in user manager environment; Sunshine may fail until a graphical session is active"
  fi

  systemctl --user daemon-reload
  systemctl --user enable --now sunshine
  sleep 2

  log
  log "Sunshine status:"
  systemctl --user status sunshine --no-pager -l | sed -n '1,60p'

  log
  log "Sunshine listener ports:"
  ss -ltnup 2>/dev/null | grep -E ':(47984|47989|47990|48010)[[:space:]]' || true

  log
  log "Host IPv4 addresses:"
  ip -4 -br addr show up | sed -n '1,120p'
}

main() {
  parse_args "$@"
  validate_capture_backend

  if [ "$LOCAL_ONLY" -eq 0 ] && [ -n "$HOST" ]; then
    run_remote
  fi

  apply_local
}

main "$@"
