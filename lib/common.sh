#!/usr/bin/env bash
# common.sh - Shared functions: logging, whiptail wrappers, prerequisites

set -euo pipefail

DEBUG_MODE=${DEBUG_MODE:-false}
LOG_FILE=""

# Terminal dimensions for whiptail
WT_HEIGHT=${WT_HEIGHT:-24}
WT_WIDTH=${WT_WIDTH:-78}
WT_MENU_HEIGHT=${WT_MENU_HEIGHT:-16}
WT_LIST_HEIGHT=${WT_LIST_HEIGHT:-20}

# Colors for logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ========================================
# Logging
# ========================================

log_info() {
    printf "${GREEN}[INFO]${NC} %s\n" "$*"
    log_to_file "INFO" "$*"
}

log_warn() {
    printf "${YELLOW}[WARN]${NC} %s\n" "$*"
    log_to_file "WARN" "$*"
}

log_error() {
    printf "${RED}[ERROR]${NC} %s\n" "$*" >&2
    log_to_file "ERROR" "$*"
}

log_step() {
    printf "${BLUE}[STEP]${NC} %s\n" "$*"
    log_to_file "STEP" "$*"
}

log_debug() {
    if [ "${DEBUG_MODE:-false}" = "true" ]; then
        printf "[DEBUG] %s\n" "$*"
    fi
    log_to_file "DEBUG" "$*"
}

log_decision() {
    log_info "Decision: $*"
}

log_to_file() {
    local level="$1"
    shift
    if [ -n "${LOG_FILE:-}" ]; then
        printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$*" >> "$LOG_FILE"
    fi
}

init_logging() {
    local base_dir="$1"
    LOG_FILE="$base_dir/install.log"
    touch "$LOG_FILE"
    log_info "Logging initialized: $LOG_FILE"
    if [ "${DEBUG_MODE:-false}" = "true" ]; then
        log_info "Debug mode enabled."
    fi
}

run_and_log() {
    local cmd_display="$1"
    shift
    log_debug "Running command: $cmd_display"
    local tmp_output
    tmp_output=$(mktemp)
    local exit_code=0

    # Keep compose's interactive per-container progress when running in a TTY.
    # `script` allocates a pseudo-terminal and mirrors output to a transcript file.
    if [ -t 1 ] && command -v script >/dev/null 2>&1; then
        local cmd_escaped=""
        local arg
        for arg in "$@"; do
            printf -v cmd_escaped '%s%q ' "$cmd_escaped" "$arg"
        done
        set +e
        script -q -e -c "$cmd_escaped" "$tmp_output"
        exit_code=$?
        set -e
    else
        # Fallback for non-interactive shells/environments.
        set +e
        "$@" 2>&1 | tee "$tmp_output"
        exit_code=${PIPESTATUS[0]}
        set -e
    fi

    if [ -s "$tmp_output" ]; then
        while IFS= read -r line; do
            # Ignore util-linux script session headers/footers.
            case "$line" in
                "Script started on "*|"Script done on "*)
                    continue
                    ;;
            esac
            log_to_file "CMD" "$line"
        done < "$tmp_output"
    fi
    rm -f "$tmp_output"

    if [ $exit_code -ne 0 ]; then
        log_error "Command failed (exit $exit_code): $cmd_display"
    fi
    return $exit_code
}

# ========================================
# Whiptail Wrappers
# ========================================

whiptail_menu() {
    local title="$1"
    shift
    # Remaining args are tag/description pairs
    whiptail --title "$title" --menu "" "$WT_HEIGHT" "$WT_WIDTH" "$WT_MENU_HEIGHT" "$@" 3>&1 1>&2 2>&3
}

whiptail_checklist() {
    local title="$1"
    shift
    # Remaining args are tag/description/status triples
    whiptail --title "$title" --checklist "" "$WT_HEIGHT" "$WT_WIDTH" "$WT_LIST_HEIGHT" "$@" 3>&1 1>&2 2>&3
}

whiptail_input() {
    local title="$1"
    local prompt="$2"
    local default="${3:-}"
    whiptail --title "$title" --inputbox "$prompt" "$WT_HEIGHT" "$WT_WIDTH" "$default" 3>&1 1>&2 2>&3
}

whiptail_password() {
    local title="$1"
    local prompt="$2"
    whiptail --title "$title" --passwordbox "$prompt" "$WT_HEIGHT" "$WT_WIDTH" 3>&1 1>&2 2>&3
}

whiptail_yesno() {
    local title="$1"
    local prompt="$2"
    whiptail --title "$title" --yesno "$prompt" "$WT_HEIGHT" "$WT_WIDTH" 3>&1 1>&2 2>&3
}

whiptail_msgbox() {
    local title="$1"
    local message="$2"
    whiptail --title "$title" --msgbox "$message" "$WT_HEIGHT" "$WT_WIDTH" 3>&1 1>&2 2>&3
}

whiptail_gauge() {
    local title="$1"
    local prompt="$2"
    # Reads percentage from stdin
    whiptail --title "$title" --gauge "$prompt" 7 "$WT_WIDTH" 0
}

whiptail_radiolist() {
    local title="$1"
    local prompt="$2"
    shift 2
    whiptail --title "$title" --radiolist "$prompt" 28 "$WT_WIDTH" 18 "$@" 3>&1 1>&2 2>&3
}

whiptail_textbox() {
    local title="$1"
    local file="$2"
    whiptail --title "$title" --textbox "$file" "$WT_HEIGHT" "$WT_WIDTH"
}

# ========================================
# Prerequisites
# ========================================

check_not_root() {
    if [ "$EUID" -eq 0 ]; then
        log_error "Please do not run this script as root or using sudo"
        exit 1
    fi
}

check_command() {
    local cmd="$1"
    local install_msg="${2:-}"
    if ! command -v "$cmd" &>/dev/null; then
        log_error "'$cmd' is not installed."
        if [ -n "$install_msg" ]; then
            log_error "$install_msg"
        fi
        return 1
    fi
    return 0
}

check_prerequisites() {
    local missing=0

    check_not_root

    if ! check_command docker "Install Docker: https://docs.docker.com/engine/install/"; then
        missing=1
    fi

    if ! docker compose version &>/dev/null; then
        log_error "'docker compose' plugin is not available."
        log_error "Install Docker Compose plugin: https://docs.docker.com/compose/install/"
        missing=1
    fi

    if ! check_command whiptail "Install whiptail: sudo apt-get install whiptail"; then
        missing=1
    fi

    # Check/install yq
    if ! check_command yq; then
        log_info "Installing yq (YAML processor)..."
        install_yq || {
            log_error "Failed to install yq. Please install manually."
            missing=1
        }
    fi

    if [ "$missing" -eq 1 ]; then
        log_error "Missing prerequisites. Please install them and try again."
        exit 1
    fi

    log_info "All prerequisites satisfied."
}

install_yq() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64)  arch="amd64" ;;
        aarch64) arch="arm64" ;;
        armv7l)  arch="arm" ;;
        *)
            log_error "Unsupported architecture: $arch"
            return 1
            ;;
    esac

    local yq_url="https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${arch}"
    local yq_bin="/usr/local/bin/yq"

    log_info "Downloading yq for linux/${arch}..."
    if sudo curl -sL "$yq_url" -o "$yq_bin" && sudo chmod +x "$yq_bin"; then
        log_info "yq installed successfully."
        return 0
    else
        return 1
    fi
}

# ========================================
# Utility Functions
# ========================================

# Get the base directory of the Mediabox installation
get_base_dir() {
    cd "$(dirname "${BASH_SOURCE[1]}")" && pwd
}

# Check if a file exists, with optional wait
wait_for_file() {
    local file="$1"
    local timeout="${2:-60}"
    local elapsed=0
    while [ ! -f "$file" ] && [ "$elapsed" -lt "$timeout" ]; do
        sleep 1
        elapsed=$((elapsed + 1))
    done
    [ -f "$file" ]
}
