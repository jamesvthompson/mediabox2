#!/usr/bin/env bash
# config.sh - System detection, configuration prompting, .env generation

# ========================================
# System Info Auto-Detection
# ========================================

detect_system_info() {
    LOCALUSER=$(id -u -n)
    PUID=$(id -u "$LOCALUSER")
    PGID=$(id -g "$LOCALUSER")
    DOCKERGRP=$(grep docker /etc/group | cut -d ':' -f 3)
    HOSTNAME_VAL=$(hostname)
    IP_ADDRESS=$(hostname -I | awk '{print $1}')
    TZ=$(cat /etc/timezone 2>/dev/null || echo "UTC")
    local slash
    slash=$(ip a | grep "$IP_ADDRESS" | head -1 | awk '{print $2}' | awk -F '/' '{print $2}')
    local lannet
    lannet=$(awk -F"." '{print $1"."$2"."$3".0"}' <<< "$IP_ADDRESS")
    CIDR_ADDRESS="${lannet}/${slash}"

    log_info "Detected system info:"
    log_info "  User: $LOCALUSER (UID=$PUID, GID=$PGID)"
    log_info "  Host: $HOSTNAME_VAL ($IP_ADDRESS)"
    log_info "  Timezone: $TZ"
    log_info "  Network: $CIDR_ADDRESS"
}

# ========================================
# Media Directory Configuration
# ========================================

prompt_media_dirs() {
    local default_base="$BASE_DIR/content"

    DLDIR=$(whiptail_input "Media Directories" \
        "Downloads directory (full path):" \
        "${DLDIR:-$default_base}") || return 1

    TVDIR=$(whiptail_input "Media Directories" \
        "TV Shows directory (full path):" \
        "${TVDIR:-$default_base/tv}") || return 1

    MOVIEDIR=$(whiptail_input "Media Directories" \
        "Movies directory (full path):" \
        "${MOVIEDIR:-$default_base/movies}") || return 1

    MUSICDIR=$(whiptail_input "Media Directories" \
        "Music directory (full path):" \
        "${MUSICDIR:-$default_base/music}") || return 1

    MISCDIR=$(whiptail_input "Media Directories" \
        "Miscellaneous media directory (full path):" \
        "${MISCDIR:-$default_base/misc}") || return 1
}

create_media_dirs() {
    mkdir -p "$DLDIR/completed"
    mkdir -p "$DLDIR/incomplete"
    mkdir -p "$TVDIR"
    mkdir -p "$MOVIEDIR"
    mkdir -p "$MUSICDIR"
    mkdir -p "$MISCDIR"
    log_info "Media directories created."
}

# ========================================
# Service-Specific Config Prompts
# ========================================

prompt_plex_config() {
    PMSTAG=$(whiptail_radiolist "Plex Release Type" \
        "public"   "Public release (stable)" "ON" \
        "latest"   "Latest release"          "OFF" \
        "plexpass" "PlexPass release"        "OFF") || PMSTAG="public"

    if [ -z "$PMSTAG" ]; then
        PMSTAG="public"
    fi
    log_info "Plex release type: $PMSTAG"
}

prompt_vpn_config() {
    PIAUNAME=$(whiptail_input "PIA VPN Configuration" \
        "Enter your PIA (Private Internet Access) username:" \
        "${PIAUNAME:-}") || return 1

    PIAPASS=$(whiptail_password "PIA VPN Configuration" \
        "Enter your PIA password:") || return 1

    # Select VPN server from ovpn files
    local ovpn_dir="$BASE_DIR/ovpn"
    if [ ! -d "$ovpn_dir" ] || [ -z "$(ls -A "$ovpn_dir"/*.ovpn 2>/dev/null)" ]; then
        log_error "No OpenVPN configuration files found in $ovpn_dir"
        return 1
    fi

    local servers=()
    local first=true
    for f in "$ovpn_dir"/*.ovpn; do
        local name
        name=$(basename "$f" .ovpn)
        if $first; then
            servers+=("$name" "" "ON")
            first=false
        else
            servers+=("$name" "" "OFF")
        fi
    done

    local selected_server
    selected_server=$(whiptail_radiolist "PIA VPN Server" "${servers[@]}") || return 1

    # Copy VPN files to delugevpn config
    local vpn_dest="$BASE_DIR/delugevpn/config/openvpn"
    mkdir -p "$vpn_dest"
    rm -f "$vpn_dest"/*.ovpn "$vpn_dest"/*.crt "$vpn_dest"/*.pem 2>/dev/null
    cp "$ovpn_dir/${selected_server}.ovpn" "$vpn_dest/"
    cp "$ovpn_dir"/*.crt "$vpn_dest/" 2>/dev/null || true
    cp "$ovpn_dir"/*.pem "$vpn_dest/" 2>/dev/null || true

    # Adjust cipher settings
    echo "cipher aes-256-gcm" >> "$vpn_dest/${selected_server}.ovpn"

    VPN_REMOTE=$(grep "remote" "$ovpn_dir/${selected_server}.ovpn" | cut -d ' ' -f2 | head -1)

    log_info "VPN server selected: $selected_server ($VPN_REMOTE)"
}

prompt_daemon_credentials() {
    DAEMON_USER=$(whiptail_input "Service Credentials" \
        "Set a username for Deluge daemon & NZBGet access:" \
        "${DAEMON_USER:-}") || return 1

    DAEMON_PASS=$(whiptail_password "Service Credentials" \
        "Set a password for Deluge daemon & NZBGet access:") || return 1
}

# ========================================
# Conditional Config Based on Selected Services
# ========================================

prompt_service_config() {
    local selected_services="$1"

    # Plex config
    if echo "$selected_services" | grep -qw "plex"; then
        prompt_plex_config
    else
        PMSTAG="${PMSTAG:-public}"
    fi

    # VPN config (only if DelugeVPN selected)
    if echo "$selected_services" | grep -qw "delugevpn"; then
        prompt_vpn_config
    else
        PIAUNAME="${PIAUNAME:-}"
        PIAPASS="${PIAPASS:-}"
        VPN_REMOTE="${VPN_REMOTE:-}"
    fi

    # Daemon credentials (if DelugeVPN or NZBGet selected)
    if echo "$selected_services" | grep -qw "delugevpn\|nzbget"; then
        prompt_daemon_credentials
    else
        DAEMON_USER="${DAEMON_USER:-}"
        DAEMON_PASS="${DAEMON_PASS:-}"
    fi
}

# ========================================
# .env File Generation
# ========================================

generate_env_file() {
    local env_file="$BASE_DIR/.env"

    cat << EOF > "$env_file"
###  ------------------------------------------------
###  M E D I A B O X 2   C O N F I G   S E T T I N G S
###  ------------------------------------------------
###  The values configured here are applied during
###  $ docker compose up
###  -----------------------------------------------
LOCALUSER=$LOCALUSER
HOSTNAME=$HOSTNAME_VAL
IP_ADDRESS=$IP_ADDRESS
PUID=$PUID
PGID=$PGID
DOCKERGRP=$DOCKERGRP
PWD=$BASE_DIR
DLDIR=$DLDIR
TVDIR=$TVDIR
MISCDIR=$MISCDIR
MOVIEDIR=$MOVIEDIR
MUSICDIR=$MUSICDIR
PIAUNAME=$PIAUNAME
PIAPASS=$PIAPASS
CIDR_ADDRESS=$CIDR_ADDRESS
TZ=$TZ
PMSTAG=$PMSTAG
VPN_REMOTE=$VPN_REMOTE
CPDAEMONUN=${DAEMON_USER:-}
CPDAEMONPASS=${DAEMON_PASS:-}
NZBGETUN=${DAEMON_USER:-}
NZBGETPASS=${DAEMON_PASS:-}
EOF

    log_info ".env file created at $env_file"
}

# ========================================
# Load Existing Configuration
# ========================================

load_existing_config() {
    local env_file="$BASE_DIR/.env"
    if [ -f "$env_file" ]; then
        # Source env file, ignoring comments
        while IFS='=' read -r key value; do
            case "$key" in
                \#*|"") continue ;;
                LOCALUSER)    LOCALUSER="$value" ;;
                HOSTNAME)     HOSTNAME_VAL="$value" ;;
                IP_ADDRESS)   IP_ADDRESS="$value" ;;
                PUID)         PUID="$value" ;;
                PGID)         PGID="$value" ;;
                DOCKERGRP)    DOCKERGRP="$value" ;;
                DLDIR)        DLDIR="$value" ;;
                TVDIR)        TVDIR="$value" ;;
                MISCDIR)      MISCDIR="$value" ;;
                MOVIEDIR)     MOVIEDIR="$value" ;;
                MUSICDIR)     MUSICDIR="$value" ;;
                PIAUNAME)     PIAUNAME="$value" ;;
                PIAPASS)      PIAPASS="$value" ;;
                CIDR_ADDRESS) CIDR_ADDRESS="$value" ;;
                TZ)           TZ="$value" ;;
                PMSTAG)       PMSTAG="$value" ;;
                VPN_REMOTE)   VPN_REMOTE="$value" ;;
                CPDAEMONUN)   DAEMON_USER="$value" ;;
                CPDAEMONPASS) DAEMON_PASS="$value" ;;
            esac
        done < "$env_file"
        log_info "Loaded existing configuration from $env_file"
        return 0
    fi
    return 1
}
