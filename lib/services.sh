#!/usr/bin/env bash
# services.sh - Module discovery, service selection UI, dependency resolution

# Service categories in display order
CATEGORIES=(
    "Media Servers"
    "Content Automation"
    "Indexers"
    "Download Clients"
    "Request Management"
    "Media Processing"
    "System & Monitoring"
    "Utilities"
)

# Config profiles
# Keep values as plain strings and normalize before use.
DEFAULT_PLEX="plex sonarr radarr prowlarr delugevpn overseerr tautulli homer watchtower portainer"
DEFAULT_JELLYFIN="jellyfin sonarr radarr prowlarr delugevpn overseerr homer watchtower portainer"
PROFILE_MINIMAL_PLEX="plex"
PROFILE_MINIMAL_JELLYFIN="jellyfin"

# ========================================
# Module Discovery
# ========================================

# Parse metadata from a module YAML file
# Metadata is in comments at the top: # key: value
parse_module_meta() {
    local file="$1"
    local key="$2"
    grep "^# ${key}:" "$file" 2>/dev/null | sed "s/^# ${key}: *//" | head -1 || true
}

# Discover all modules in the modules/ directory
# Populates associative arrays for module metadata
declare -A MODULE_DESC MODULE_CAT MODULE_DEPS MODULE_PORT MODULE_CONFIG

normalize_whitespace() {
    echo "$1" | xargs
}

expand_service_preset() {
    case "$1" in
        DEFAULT_PLEX) echo "$DEFAULT_PLEX" ;;
        DEFAULT_JELLYFIN) echo "$DEFAULT_JELLYFIN" ;;
        PROFILE_MINIMAL_PLEX) echo "$PROFILE_MINIMAL_PLEX" ;;
        PROFILE_MINIMAL_JELLYFIN) echo "$PROFILE_MINIMAL_JELLYFIN" ;;
        *) echo "$1" ;;
    esac
}

discover_modules() {
    local modules_dir="$BASE_DIR/modules"
    ALL_MODULES=()

    for yml in "$modules_dir"/*.yml; do
        [ -f "$yml" ] || continue
        local mod
        mod=$(parse_module_meta "$yml" "module")
        [ -z "$mod" ] && continue

        ALL_MODULES+=("$mod")
        MODULE_DESC[$mod]=$(parse_module_meta "$yml" "description")
        MODULE_CAT[$mod]=$(parse_module_meta "$yml" "category")
        MODULE_DEPS[$mod]=$(parse_module_meta "$yml" "depends")
        MODULE_PORT[$mod]=$(parse_module_meta "$yml" "port")
        MODULE_CONFIG[$mod]=$(parse_module_meta "$yml" "config_requires")
    done

    log_info "Discovered ${#ALL_MODULES[@]} modules."
}

# ========================================
# Service Selection UI
# ========================================

choose_services_with_profile() {
    local custom_preselected="${1:-}"
    SELECTED_SERVICES=""

    local profile
    profile=$(whiptail_radiolist "Configuration Profile" \
        "Choose a configuration profile.\n\nStandard Plex: plex + sonarr + radarr + prowlarr + delugevpn + overseerr + tautulli + homer + watchtower + portainer\nStandard Jellyfin: jellyfin + sonarr + radarr + prowlarr + delugevpn + overseerr + homer + watchtower + portainer\n\nCustom lets you select individual services on the next screen." \
        "full"              "Full (everything)"        "OFF" \
        "standard_plex"     "Standard Plex stack"      "ON" \
        "standard_jellyfin" "Standard Jellyfin stack"  "OFF" \
        "minimal_plex"      "Minimal (Plex only)"      "OFF" \
        "minimal_jellyfin"  "Minimal (Jellyfin only)"  "OFF" \
        "custom"            "Custom"                   "OFF") || return 1

    case "$profile" in
        minimal_plex)
            SELECTED_SERVICES=$(normalize_whitespace "$PROFILE_MINIMAL_PLEX")
            ;;
        minimal_jellyfin)
            SELECTED_SERVICES=$(normalize_whitespace "$PROFILE_MINIMAL_JELLYFIN")
            ;;
        standard_plex)
            SELECTED_SERVICES=$(normalize_whitespace "$DEFAULT_PLEX")
            ;;
        standard_jellyfin)
            SELECTED_SERVICES=$(normalize_whitespace "$DEFAULT_JELLYFIN")
            ;;
        full)
            local all_selected=""
            for mod in "${ALL_MODULES[@]}"; do
                all_selected+="$mod "
            done
            SELECTED_SERVICES=$(normalize_whitespace "$all_selected")
            ;;
        custom)
            show_service_selector "$custom_preselected" || return 1
            ;;
        *)
            return 1
            ;;
    esac
}

# Sets global SELECTED_SERVICES variable (not stdout) to avoid subshell issues
# with associative arrays. Caller must NOT use $(...) to capture output.
show_service_selector() {
    local preselected="${1:-}"
    preselected=$(expand_service_preset "$preselected")
    preselected=$(normalize_whitespace "$preselected")
    SELECTED_SERVICES=""
    local checklist_args=()

    # Group modules by category
    for category in "${CATEGORIES[@]}"; do
        local has_items=false
        for mod in "${ALL_MODULES[@]}"; do
            if [ "${MODULE_CAT[$mod]}" = "$category" ]; then
                has_items=true
                break
            fi
        done
        $has_items || continue

        # Add modules in this category
        for mod in "${ALL_MODULES[@]}"; do
            if [ "${MODULE_CAT[$mod]}" = "$category" ]; then
                local status="OFF"
                if [ "$preselected" = "ALL" ] || echo "$preselected" | grep -qw "$mod"; then
                    status="ON"
                fi
                checklist_args+=("$mod" "${MODULE_DESC[$mod]}" "$status")
            fi
        done
    done

    local checklist_height="$WT_HEIGHT"
    local checklist_width="$WT_WIDTH"
    local checklist_list_height="$WT_LIST_HEIGHT"

    # Keep enough room for title/prompt/buttons so the list never overlaps
    # the top of the dialog on smaller terminals.
    local max_list_height=$((checklist_height - 8))
    if [ "$max_list_height" -lt 5 ]; then
        max_list_height=5
    fi
    if [ "$checklist_list_height" -gt "$max_list_height" ]; then
        checklist_list_height="$max_list_height"
    fi

    local selected
    selected=$(whiptail --title "Service Selection" \
        --checklist "Select services (SPACE toggle, TAB buttons, ENTER confirm)." \
        "$checklist_height" "$checklist_width" "$checklist_list_height" "${checklist_args[@]}" 3>&1 1>&2 2>&3) || return 1

    # Remove quotes from whiptail output
    selected=$(echo "$selected" | tr -d '"')

    # Deduplicate while preserving order
    selected=$(for mod in $selected; do echo "$mod"; done | awk '!seen[$0]++')

    SELECTED_SERVICES=$(normalize_whitespace "$selected")
}

# ========================================
# Dependency Resolution
# ========================================

# Sets global RESOLVED_SERVICES variable (not stdout) to avoid subshell issues
# with associative arrays. Caller must NOT use $(...) to capture output.
resolve_dependencies() {
    local selected="$1"
    RESOLVED_SERVICES="$selected"
    local changed=true

    while $changed; do
        changed=false
        for mod in $RESOLVED_SERVICES; do
            local deps="${MODULE_DEPS[$mod]:-}"
            [ -z "$deps" ] || [ "$deps" = "(none)" ] && continue

            IFS=',' read -ra dep_array <<< "$deps"
            for dep in "${dep_array[@]}"; do
                dep=$(echo "$dep" | xargs) # trim whitespace
                if ! echo "$RESOLVED_SERVICES" | grep -qw "$dep"; then
                    RESOLVED_SERVICES+=" $dep"
                    changed=true
                    log_info "Auto-added '$dep' (required by '$mod')"
                fi
            done
        done
    done

    # Soft dependency warnings
    if echo "$RESOLVED_SERVICES" | grep -qw "tautulli" && ! echo "$RESOLVED_SERVICES" | grep -qw "plex"; then
        log_warn "Tautulli is selected but Plex is not. Tautulli requires Plex to function."
    fi
}

# ========================================
# Service Directory Creation
# ========================================

create_service_dirs() {
    local selected="$1"

    for mod in $selected; do
        case "$mod" in
            plex)
                mkdir -p "$BASE_DIR/plex/Library/Application Support/Plex Media Server/Logs"
                mkdir -p "$BASE_DIR/plex/transcode"
                ;;
            delugevpn)
                mkdir -p "$BASE_DIR/delugevpn/config/openvpn"
                ;;
            duplicati)
                mkdir -p "$BASE_DIR/duplicati/backups"
                ;;
            tdarr)
                mkdir -p "$BASE_DIR/tdarr/server"
                mkdir -p "$BASE_DIR/tdarr/configs"
                mkdir -p "$BASE_DIR/tdarr/logs"
                mkdir -p "$BASE_DIR/tdarr/transcode_cache"
                ;;
            maintainerr)
                mkdir -p "$BASE_DIR/maintainerr/data"
                ;;
            *)
                mkdir -p "$BASE_DIR/$mod"
                ;;
        esac
    done

    mkdir -p "$BASE_DIR/historical/env_files"
    log_info "Service directories created."
}

# ========================================
# State Management
# ========================================

STATE_FILE=".mediabox_state"

save_state() {
    local selected="$1"
    cat << EOF > "$BASE_DIR/$STATE_FILE"
INSTALLED_SERVICES="$selected"
INSTALL_DATE="${INSTALL_DATE:-$(date +%Y-%m-%d)}"
LAST_UPDATE="$(date +%Y-%m-%d)"
EOF
    log_info "State saved."
}

load_state() {
    local state_file="$BASE_DIR/$STATE_FILE"
    if [ -f "$state_file" ]; then
        # shellcheck source=/dev/null
        source "$state_file"
        return 0
    fi
    return 1
}

is_installed() {
    [ -f "$BASE_DIR/$STATE_FILE" ] && [ -f "$BASE_DIR/.env" ] && [ -f "$BASE_DIR/docker-compose.yml" ]
}
