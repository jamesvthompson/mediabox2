#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="legacy-migration-prep.sh"
SCRIPT_VERSION="1.1.1"

C_RESET='\033[0m'
C_INFO='\033[1;34m'
C_OK='\033[1;32m'
C_WARN='\033[1;33m'
C_FAIL='\033[1;31m'

CHECK_ONLY=0
ASSUME_YES=0
FORCE_NOT_MEDIABOX=0
INSTALL_DIR_INPUT=""
INSTALL_DIR=""
INSTALL_DIR_RESOLVED=""
BACKUP_PATH=""
COMPOSE_CMD=""
COMPOSE_FILE=""
PROJECT_NAME=""
IDENTITY_SCORE=0
IDENTITY_MAX=100
CURRENT_REPO_TOPLEVEL=""

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

KNOWN_SERVICES=(
  plex jellyfin emby sonarr radarr lidarr prowlarr bazarr readarr
  overseerr ombi tautulli delugevpn deluge qbittorrent transmission
  sabnzbd nzbget jackett flaresolverr nzbhydra2 watchtower portainer
  glances dozzle netdata homer filebrowser tdarr metube duplicati
  couchpotato headphones sickchill minio requestrr speedtest-tracker
)

log_info() { echo -e "${C_INFO}[INFO]${C_RESET} $*"; }
log_ok()   { echo -e "${C_OK}[OK]${C_RESET} $*"; }
log_warn() { echo -e "${C_WARN}[WARN]${C_RESET} $*"; }
log_fail() { echo -e "${C_FAIL}[FAIL]${C_RESET} $*"; }

record_ok() { PASS_COUNT=$((PASS_COUNT + 1)); log_ok "$*"; }
record_warn() { WARN_COUNT=$((WARN_COUNT + 1)); log_warn "$*"; }
record_fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); log_fail "$*"; }

usage() {
  cat <<USAGE
$SCRIPT_NAME v$SCRIPT_VERSION

Prepare a legacy Mediabox installation for migration by stopping the old stack
and archiving the install directory into a timestamped backup path.

Usage:
  ./$SCRIPT_NAME [install_dir] [options]

Options:
  --check-only            Run checks/detection only (no stop/archive)
  -y, --yes               Non-interactive confirmation for archive step
  --force-not-mediabox    Skip identity confidence gate for non-standard installs
  -h, --help              Show this help

Notes:
  - Default install_dir is: ~/mediabox
  - Never deletes data.
  - Never runs docker prune.
  - Never moves media directories.
  - Never clones repositories.
USAGE
}

parse_args() {
  local positionals=()

  while (($#)); do
    case "$1" in
      --check-only)
        CHECK_ONLY=1
        ;;
      -y|--yes)
        ASSUME_YES=1
        ;;
      --force-not-mediabox)
        FORCE_NOT_MEDIABOX=1
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      -*)
        record_fail "Unknown option: $1"
        usage
        exit 2
        ;;
      *)
        positionals+=("$1")
        ;;
    esac
    shift
  done

  if ((${#positionals[@]} > 1)); then
    record_fail "Only one positional argument is allowed: [install_dir]"
    usage
    exit 2
  fi

  INSTALL_DIR_INPUT="${positionals[0]:-}"
}

resolve_path() {
  local p="$1"

  if command -v realpath >/dev/null 2>&1; then
    realpath -m "$p"
    return
  fi

  if command -v python3 >/dev/null 2>&1; then
    python3 - "$p" <<'PY'
import os
import sys
print(os.path.abspath(os.path.expanduser(sys.argv[1])))
PY
    return
  fi

  # Best effort fallback
  case "$p" in
    ~*) printf '%s\n' "${HOME}${p#\~}" ;;
    *) printf '%s\n' "$p" ;;
  esac
}

get_git_toplevel() {
  local p="$1"
  if ! command -v git >/dev/null 2>&1; then
    return 0
  fi

  git -C "$p" rev-parse --show-toplevel 2>/dev/null || true
}

is_known_service() {
  local name="$1"
  for s in "${KNOWN_SERVICES[@]}"; do
    if [[ "$s" == "$name" ]]; then
      return 0
    fi
  done
  return 1
}

choose_compose_cmd() {
  if docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
    record_ok "Compose command available: docker compose"
    return
  fi

  if command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_CMD="docker-compose"
    record_ok "Compose command available: docker-compose"
    return
  fi

  record_fail "No Compose command found (docker compose / docker-compose)"
}

find_compose_file() {
  local d="$1"
  local candidates=(
    "$d/docker-compose.yml"
    "$d/docker-compose.yaml"
    "$d/compose.yml"
    "$d/compose.yaml"
  )
  local c

  for c in "${candidates[@]}"; do
    if [[ -f "$c" ]]; then
      COMPOSE_FILE="$c"
      record_ok "Compose file found: $COMPOSE_FILE"
      return
    fi
  done

  record_warn "No compose file found in $d"
}

check_core_tools() {
  local required=(mv date awk sed find)
  local missing=0
  local t

  for t in "${required[@]}"; do
    if ! command -v "$t" >/dev/null 2>&1; then
      record_fail "Missing required tool: $t"
      missing=1
    fi
  done

  if ((missing == 0)); then
    record_ok "Required core tools are present"
  fi
}

run_compatibility_checks() {
  log_info "Running compatibility checks..."

  if command -v docker >/dev/null 2>&1; then
    record_ok "Docker binary detected"
  else
    record_fail "Docker is not installed"
  fi

  choose_compose_cmd

  if docker info >/dev/null 2>&1; then
    record_ok "Docker daemon is accessible"
  else
    record_fail "Docker daemon is not accessible for current user"
  fi

  local parent_dir
  parent_dir="$(dirname "$INSTALL_DIR_RESOLVED")"
  if [[ -w "$parent_dir" ]]; then
    record_ok "Parent directory writable: $parent_dir"
  else
    record_fail "Parent directory is not writable: $parent_dir"
  fi

  check_core_tools
}

check_not_current_version_dir() {
  local target_git_root
  target_git_root="$(get_git_toplevel "$INSTALL_DIR_RESOLVED")"
  if [[ -z "$target_git_root" ]]; then
    record_ok "Target install directory is not inside a Git repository"
    return
  fi

  local target_git_root_resolved
  target_git_root_resolved="$(resolve_path "$target_git_root")"
  record_ok "Target Git repository detected: $target_git_root_resolved"

  if [[ -n "$CURRENT_REPO_TOPLEVEL" && "$target_git_root_resolved" == "$CURRENT_REPO_TOPLEVEL" ]]; then
    record_fail "Target path is inside the current Mediabox repo. Provide a legacy install path instead."
    print_summary
    exit 1
  fi

  record_ok "Target path is not the current repo location (legacy path check passed)"
}

detect_project_name() {
  if [[ -f "$INSTALL_DIR_RESOLVED/.env" ]]; then
    PROJECT_NAME="$(awk -F= '/^COMPOSE_PROJECT_NAME=/{print $2; exit}' "$INSTALL_DIR_RESOLVED/.env" | tr -d '"' | xargs || true)"
  fi

  if [[ -z "$PROJECT_NAME" ]]; then
    PROJECT_NAME="$(basename "$INSTALL_DIR_RESOLVED" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_-')"
  fi

  log_info "Compose project scope: ${PROJECT_NAME:-unknown}"
}

detect_services_from_dirs() {
  local base="$1"
  local roots=("$base/config" "$base/appdata" "$base/data")
  local found=()
  local root

  for root in "${roots[@]}"; do
    if [[ -d "$root" ]]; then
      while IFS= read -r -d '' dir; do
        local name
        name="$(basename "$dir" | tr '[:upper:]' '[:lower:]')"
        if is_known_service "$name"; then
          found+=("$name")
        fi
      done < <(find "$root" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null || true)
    fi
  done

  if ((${#found[@]} > 0)); then
    printf '%s\n' "${found[@]}" | sort -u
  fi
}

detect_services_from_compose() {
  if [[ -z "$COMPOSE_CMD" || -z "$COMPOSE_FILE" ]]; then
    return 0
  fi

  if [[ "$COMPOSE_CMD" == "docker compose" ]]; then
    docker compose -f "$COMPOSE_FILE" config --services 2>/dev/null || true
  else
    docker-compose -f "$COMPOSE_FILE" config --services 2>/dev/null || true
  fi
}

detect_services_from_running() {
  if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
    return 0
  fi

  if [[ -n "$PROJECT_NAME" ]]; then
    docker ps --filter "label=com.docker.compose.project=$PROJECT_NAME" --format '{{.Names}}' 2>/dev/null \
      | sed -E 's/.*[_-]([a-zA-Z0-9.-]+)[_-][0-9]+$/\1/' \
      | tr '[:upper:]' '[:lower:]' \
      | sed 's/\..*$//' \
      | sed '/^$/d' || true
  fi
}

score_identity() {
  local score=0

  [[ -f "$INSTALL_DIR_RESOLVED/.env" ]] && score=$((score + 20))
  [[ -d "$INSTALL_DIR_RESOLVED/config" ]] && score=$((score + 20))
  [[ -d "$INSTALL_DIR_RESOLVED/appdata" ]] && score=$((score + 15))
  [[ -n "$COMPOSE_FILE" ]] && score=$((score + 20))

  local known_count=0
  if [[ -n "${1:-}" ]]; then
    known_count=$(printf '%s\n' "$1" | sed '/^$/d' | wc -l | xargs)
  fi

  if ((known_count >= 1)); then
    score=$((score + 10))
  fi
  if ((known_count >= 3)); then
    score=$((score + 10))
  fi
  if ((known_count >= 6)); then
    score=$((score + 5))
  fi

  IDENTITY_SCORE=$score
}

show_identity_and_gate() {
  local merged_services="$1"
  score_identity "$merged_services"

  log_info "Identity confidence score: $IDENTITY_SCORE/$IDENTITY_MAX"

  if ((IDENTITY_SCORE >= 60)); then
    record_ok "Install path looks like a legacy Mediabox installation"
    return
  fi

  record_warn "Low confidence that path is a Mediabox install"

  if ((FORCE_NOT_MEDIABOX == 1)); then
    record_warn "Bypassing identity confirmation due to --force-not-mediabox"
    return
  fi

  if ((ASSUME_YES == 1)); then
    record_fail "Refusing low-confidence archive with --yes unless --force-not-mediabox is set"
    exit 3
  fi

  echo
  log_warn "Type ARCHIVE to confirm archive rename for low-confidence path:"
  read -r typed
  if [[ "$typed" != "ARCHIVE" ]]; then
    record_fail "Confirmation did not match ARCHIVE. Aborting."
    exit 3
  fi

  record_ok "Manual ARCHIVE confirmation accepted"
}

stop_old_stack() {
  if [[ -z "$COMPOSE_CMD" || -z "$COMPOSE_FILE" ]]; then
    record_warn "Skipping stack stop (compose command/file unavailable)"
    return
  fi

  log_info "Stopping legacy stack..."
  if [[ "$COMPOSE_CMD" == "docker compose" ]]; then
    if docker compose -f "$COMPOSE_FILE" down; then
      record_ok "Legacy stack stopped via docker compose down"
    else
      record_fail "Failed to stop stack via docker compose down"
      exit 4
    fi
  else
    if docker-compose -f "$COMPOSE_FILE" down; then
      record_ok "Legacy stack stopped via docker-compose down"
    else
      record_fail "Failed to stop stack via docker-compose down"
      exit 4
    fi
  fi
}

archive_install_dir() {
  local ts
  ts="$(date +%Y%m%d-%H%M%S)"
  BACKUP_PATH="${INSTALL_DIR_RESOLVED}.backup-${ts}"

  if [[ -e "$BACKUP_PATH" ]]; then
    record_fail "Backup path already exists: $BACKUP_PATH"
    exit 5
  fi

  mv "$INSTALL_DIR_RESOLVED" "$BACKUP_PATH"
  record_ok "Archived install directory"
  echo
  log_ok "Backup path for import: $BACKUP_PATH"
}

print_summary() {
  echo
  echo "========== Result Summary =========="
  echo "Script:   $SCRIPT_NAME v$SCRIPT_VERSION"
  echo "Target:   $INSTALL_DIR_RESOLVED"
  [[ -n "$BACKUP_PATH" ]] && echo "Backup:   $BACKUP_PATH"
  echo "Checks:   $PASS_COUNT passed, $WARN_COUNT warnings, $FAIL_COUNT failed"
  echo "===================================="
}

main() {
  parse_args "$@"

  if [[ -n "$INSTALL_DIR_INPUT" ]]; then
    INSTALL_DIR="$INSTALL_DIR_INPUT"
  else
    INSTALL_DIR="$HOME/mediabox"
  fi
  INSTALL_DIR_RESOLVED="$(resolve_path "$INSTALL_DIR")"
  CURRENT_REPO_TOPLEVEL="$(get_git_toplevel "$(pwd)")"
  if [[ -n "$CURRENT_REPO_TOPLEVEL" ]]; then
    CURRENT_REPO_TOPLEVEL="$(resolve_path "$CURRENT_REPO_TOPLEVEL")"
  fi

  log_info "$SCRIPT_NAME v$SCRIPT_VERSION"
  log_info "Target install dir: $INSTALL_DIR_RESOLVED"
  [[ -n "$CURRENT_REPO_TOPLEVEL" ]] && log_info "Current repo dir: $CURRENT_REPO_TOPLEVEL"

  if [[ ! -d "$INSTALL_DIR_RESOLVED" ]]; then
    record_fail "Install directory does not exist: $INSTALL_DIR_RESOLVED"
    print_summary
    exit 1
  fi

  run_compatibility_checks
  check_not_current_version_dir
  find_compose_file "$INSTALL_DIR_RESOLVED"
  detect_project_name

  log_info "Detecting known services..."
  local dirs_services compose_services running_services merged_services
  dirs_services="$(detect_services_from_dirs "$INSTALL_DIR_RESOLVED" || true)"
  compose_services="$(detect_services_from_compose || true)"
  running_services="$(detect_services_from_running || true)"
  merged_services="$(printf '%s\n%s\n%s\n' "$dirs_services" "$compose_services" "$running_services" \
    | tr '[:upper:]' '[:lower:]' | sed '/^$/d' | sort -u)"

  if [[ -n "$merged_services" ]]; then
    record_ok "Detected services: $(echo "$merged_services" | tr '\n' ' ' | xargs)"
  else
    record_warn "No known services detected"
  fi

  if ((CHECK_ONLY == 1)); then
    score_identity "$merged_services"
    log_info "Identity confidence score: $IDENTITY_SCORE/$IDENTITY_MAX"
    if ((IDENTITY_SCORE >= 60)); then
      record_ok "Install path looks like a legacy Mediabox installation"
    else
      record_warn "Low confidence that path is a Mediabox install (check-only mode: no ARCHIVE confirmation required)"
    fi
    log_info "Check-only mode enabled; skipping stop/archive."
    print_summary
    if ((FAIL_COUNT > 0)); then
      exit 1
    fi
    exit 0
  fi

  show_identity_and_gate "$merged_services"

  if ((ASSUME_YES == 0)); then
    echo
    log_warn "About to stop old stack (if detected) and rename install directory."
    read -r -p "Continue? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
      record_warn "User cancelled operation"
      print_summary
      exit 0
    fi
  fi

  stop_old_stack
  archive_install_dir

  print_summary

  if ((FAIL_COUNT > 0)); then
    exit 1
  fi
}

main "$@"
