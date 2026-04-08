#!/usr/bin/env bash
# services.sh - Module discovery, service selection UI, dependency resolution

# Service categories in display order (guided/custom flows)
INSTALL_CATEGORY_KEYS=(
    "media_servers"
    "library_management"
    "indexers_search"
    "download_clients"
    "request_management"
    "dashboard"
    "monitoring"
    "network_bypass"
    "media_tools"
    "storage_file_management"
    "system_infrastructure"
)

# One shared default selection state for guided and custom install flows.
NEW_INSTALL_DEFAULTS="plex sonarr radarr prowlarr qbittorrentvpn sabnzbd overseerr dashy uptimekuma netdata dozzle byparr"

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
    choose_new_install_services "${1:-}"
}

# Sets global SELECTED_SERVICES variable (not stdout) to avoid subshell issues
# with associative arrays. Caller must NOT use $(...) to capture output.
show_service_selector() {
    local preselected="${1:-}"
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

get_category_title() {
    case "$1" in
        media_servers) echo "Media Servers" ;;
        library_management) echo "Library Management" ;;
        indexers_search) echo "Indexers & Search" ;;
        download_clients) echo "Download Clients" ;;
        request_management) echo "Request Management" ;;
        dashboard) echo "Dashboard" ;;
        monitoring) echo "Monitoring" ;;
        network_bypass) echo "Network & Bypass" ;;
        media_tools) echo "Media Tools" ;;
        storage_file_management) echo "Storage & File Management" ;;
        system_infrastructure) echo "System & Infrastructure" ;;
        *) echo "$1" ;;
    esac
}

get_category_modules() {
    case "$1" in
        media_servers) echo "plex jellyfin emby" ;;
        library_management) echo "sonarr radarr lidarr maintainerr couchpotato sickchill headphones" ;;
        indexers_search) echo "prowlarr nzbhydra2 jackett" ;;
        download_clients) echo "qbittorrentvpn delugevpn sabnzbd nzbget autobrr metube tubesync" ;;
        request_management) echo "overseerr jellyseerr requestrr ombi" ;;
        dashboard) echo "dashy homer none" ;;
        monitoring) echo "uptimekuma netdata dozzle tautulli glances speedtest" ;;
        network_bypass) echo "byparr flaresolverr" ;;
        media_tools) echo "tdarr fileflows maintainerr" ;;
        storage_file_management) echo "filebrowser duplicati minio sqlitebrowser" ;;
        system_infrastructure) echo "portainer watchtower" ;;
        *) echo "" ;;
    esac
}

is_single_select_category() {
    case "$1" in
        media_servers|dashboard) return 0 ;;
        *) return 1 ;;
    esac
}

build_category_prompt() {
    case "$1" in
        media_servers) echo "Select media server:" ;;
        library_management) echo "Select library managers:" ;;
        indexers_search) echo "Select indexer tools:" ;;
        download_clients) echo "Select download clients:" ;;
        request_management) echo "Select request tools:" ;;
        dashboard) echo "Select dashboard:" ;;
        monitoring) echo "Select monitoring tools:" ;;
        network_bypass) echo "Select anti-bot tools:" ;;
        media_tools) echo "Optional media tools:" ;;
        storage_file_management) echo "Optional tools:" ;;
        system_infrastructure) echo "Optional system tools:" ;;
        *) echo "Select services:" ;;
    esac
}

get_module_label() {
    case "$1" in
        plex) echo "Plex - best apps, remote streaming" ;;
        jellyfin) echo "Jellyfin - free, open source" ;;
        emby) echo "Emby - similar to Plex (alt)" ;;
        sonarr) echo "Sonarr - auto TV downloads" ;;
        radarr) echo "Radarr - auto movies" ;;
        lidarr) echo "Lidarr - auto music" ;;
        maintainerr) echo "Maintainerr - removes unused media" ;;
        couchpotato) echo "CouchPotato - movies (legacy)" ;;
        sickchill) echo "SickChill - TV (legacy)" ;;
        headphones) echo "Headphones - music (legacy)" ;;
        prowlarr) echo "Prowlarr - syncs indexers to apps" ;;
        nzbhydra2) echo "NZBHydra2 - advanced Usenet search" ;;
        jackett) echo "Jackett - indexer proxy (legacy)" ;;
        qbittorrentvpn) echo "qBittorrent VPN - fast, stable, recommended" ;;
        delugevpn) echo "Deluge VPN - simple, lightweight torrent client (alt)" ;;
        sabnzbd) echo "SABnzbd - best Usenet downloader" ;;
        nzbget) echo "NZBGet - lightweight (legacy)" ;;
        autobrr) echo "Autobrr - auto-grabs releases before indexers update" ;;
        metube) echo "MeTube - download videos (manual)" ;;
        tubesync) echo "TubeSync - auto YouTube downloads" ;;
        overseerr) echo "Overseerr - best overall UI + automation" ;;
        jellyseerr) echo "Jellyseerr - supports Jellyfin + Emby" ;;
        requestrr) echo "Requestrr - Discord requests (limited)" ;;
        ombi) echo "Ombi - older request system (legacy)" ;;
        dashy) echo "Dashy - modern, widgets, dynamic" ;;
        homer) echo "Homer - simple, lightweight" ;;
        none) echo "None" ;;
        uptimekuma) echo "Uptime Kuma - alerts when services go down" ;;
        netdata) echo "Netdata - CPU, RAM, system stats" ;;
        dozzle) echo "Dozzle - live container logs" ;;
        tautulli) echo "Tautulli - Plex usage stats" ;;
        glances) echo "Glances - simple system view (alt)" ;;
        speedtest) echo "Speedtest - track internet speed" ;;
        byparr) echo "Byparr - modern, lightweight bypass" ;;
        flaresolverr) echo "FlareSolverr - fallback for some sites" ;;
        tdarr) echo "Tdarr - auto converts media to save space and fix formats" ;;
        fileflows) echo "FileFlows - automate media: convert, rename, organize (paid features)" ;;
        filebrowser) echo "FileBrowser - manage files in browser" ;;
        duplicati) echo "Duplicati - backups to cloud/local" ;;
        minio) echo "MinIO - S3-compatible storage" ;;
        sqlitebrowser) echo "SQLiteBrowser - view/edit databases" ;;
        portainer) echo "Portainer - Docker management UI" ;;
        watchtower) echo "Watchtower - auto update containers" ;;
        *) echo "${MODULE_DESC[$1]:-$1}" ;;
    esac
}

module_available() {
    local mod="$1"
    [ "$mod" = "none" ] && return 0
    for existing in "${ALL_MODULES[@]}"; do
        if [ "$existing" = "$mod" ]; then
            return 0
        fi
    done
    return 1
}

choose_category_services() {
    local category_key="$1"
    local title prompt modules
    title="$(get_category_title "$category_key")"
    prompt="$(build_category_prompt "$category_key")"
    modules="$(get_category_modules "$category_key")"
    local args=()
    local mod status label

    for mod in $modules; do
        status="OFF"
        if [ "$mod" != "none" ] && echo "$SELECTED_SERVICES" | grep -qw "$mod"; then
            status="ON"
        fi
        if [ "$mod" = "none" ] && [ "$category_key" = "dashboard" ] && ! echo "$SELECTED_SERVICES" | grep -qw "dashy\|homer"; then
            status="ON"
        fi
        label="$(get_module_label "$mod")"
        if [ "$mod" != "none" ] && ! module_available "$mod"; then
            label="$label (unavailable)"
        fi
        args+=("$mod" "$label" "$status")
    done

    local selected_raw selected_clean
    if is_single_select_category "$category_key"; then
        selected_raw=$(whiptail_radiolist "$title" "$prompt" "${args[@]}") || return 1
        selected_clean="$selected_raw"
    else
        selected_raw=$(whiptail --title "$title" --checklist "$prompt" "$WT_HEIGHT" "$WT_WIDTH" "$WT_LIST_HEIGHT" "${args[@]}" 3>&1 1>&2 2>&3) || return 1
        selected_clean=$(echo "$selected_raw" | tr -d '"')
    fi

    for mod in $modules; do
        if [ "$mod" = "none" ]; then
            continue
        fi
        SELECTED_SERVICES=$(echo " $SELECTED_SERVICES " | sed "s/ $mod / /g")
    done
    SELECTED_SERVICES=$(normalize_whitespace "$SELECTED_SERVICES")

    if [ "$category_key" = "dashboard" ] && [ "$selected_clean" = "none" ]; then
        return 0
    fi

    for mod in $selected_clean; do
        [ "$mod" = "none" ] && continue
        if module_available "$mod"; then
            SELECTED_SERVICES=$(normalize_whitespace "$SELECTED_SERVICES $mod")
        fi
    done
}

build_selection_review() {
    local review="Review your setup:\n\n"
    local key title modules found
    for key in "${INSTALL_CATEGORY_KEYS[@]}"; do
        title=$(get_category_title "$key")
        modules=$(get_category_modules "$key")
        review+="$title:\n"
        found=0
        for mod in $modules; do
            [ "$mod" = "none" ] && continue
            if echo "$SELECTED_SERVICES" | grep -qw "$mod"; then
                review+="- ${MODULE_DESC[$mod]:-$mod}\n"
                found=1
            fi
        done
        if [ "$found" -eq 0 ]; then
            review+="- None\n"
        fi
        review+="\n"
    done
    echo -e "$review"
}

choose_custom_install_services() {
    while true; do
        local choice
        choice=$(whiptail_menu "Custom Install" \
            "1" "Media Servers" \
            "2" "Library Management" \
            "3" "Indexers & Search" \
            "4" "Download Clients" \
            "5" "Request Management" \
            "6" "Dashboard" \
            "7" "Monitoring" \
            "8" "Network & Bypass" \
            "9" "Media Tools" \
            "10" "Storage & File Management" \
            "11" "System & Infrastructure" \
            "12" "Review Selection" \
            "13" "Back") || return 1

        case "$choice" in
            1) choose_category_services "media_servers" || true ;;
            2) choose_category_services "library_management" || true ;;
            3) choose_category_services "indexers_search" || true ;;
            4) choose_category_services "download_clients" || true ;;
            5) choose_category_services "request_management" || true ;;
            6) choose_category_services "dashboard" || true ;;
            7) choose_category_services "monitoring" || true ;;
            8) choose_category_services "network_bypass" || true ;;
            9) choose_category_services "media_tools" || true ;;
            10) choose_category_services "storage_file_management" || true ;;
            11) choose_category_services "system_infrastructure" || true ;;
            12) whiptail_msgbox "Review Selection" "$(build_selection_review)" ;;
            13) return 0 ;;
        esac
    done
}

choose_guided_install_services() {
    while true; do
        local choice
        choice=$(whiptail_menu "Guided Install" \
            "1" "Media Servers" \
            "2" "Library Management" \
            "3" "Indexers & Search" \
            "4" "Download Clients" \
            "5" "Request Management" \
            "6" "Dashboard" \
            "7" "Monitoring" \
            "8" "Network & Bypass" \
            "9" "Media Tools" \
            "10" "Storage & File Management" \
            "11" "System & Infrastructure" \
            "12" "Review Selection" \
            "13" "Install" \
            "14" "Back") || return 1

        case "$choice" in
            1) choose_category_services "media_servers" || true ;;
            2) choose_category_services "library_management" || true ;;
            3) choose_category_services "indexers_search" || true ;;
            4) choose_category_services "download_clients" || true ;;
            5) choose_category_services "request_management" || true ;;
            6) choose_category_services "dashboard" || true ;;
            7) choose_category_services "monitoring" || true ;;
            8) choose_category_services "network_bypass" || true ;;
            9) choose_category_services "media_tools" || true ;;
            10) choose_category_services "storage_file_management" || true ;;
            11) choose_category_services "system_infrastructure" || true ;;
            12) whiptail_msgbox "Guided Install - Review Selection" "$(build_selection_review)" ;;
            13) return 0 ;;
            14) return 1 ;;
        esac
    done
}

choose_new_install_services() {
    local preselected="${1:-$NEW_INSTALL_DEFAULTS}"
    SELECTED_SERVICES=$(normalize_whitespace "$preselected")

    while true; do
        local choice
        choice=$(whiptail_menu "New Install" \
            "guided" "Guided Install" \
            "custom" "Custom Install" \
            "legacy" "Import Legacy Mediabox Install" \
            "back" "Back") || return 1

        case "$choice" in
            guided)
                choose_guided_install_services || true
                if [ -n "$SELECTED_SERVICES" ]; then
                    return 0
                fi
                ;;
            custom)
                choose_custom_install_services || true
                if whiptail_yesno "Custom Install" "Use current selection and continue to installation?"; then
                    return 0
                fi
                ;;
            legacy)
                whiptail_msgbox "Import Legacy Mediabox Install" "Legacy import is not available yet.\nThis will be added later."
                ;;
            back)
                return 1
                ;;
        esac
    done
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
            qbittorrentvpn)
                mkdir -p "$BASE_DIR/qbittorrentvpn/openvpn"
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
