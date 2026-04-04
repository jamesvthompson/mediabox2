#!/usr/bin/env bash
# postinstall.sh - Post-deploy configuration hooks

# ========================================
# Main Post-Install Runner
# ========================================

run_postinstall_hooks() {
    local selected="$1"
    log_step "Running post-install configuration..."

    for mod in $selected; do
        case "$mod" in
            delugevpn)  configure_delugevpn ;;
            jackett)    configure_jackett ;;
            nzbget)     configure_nzbget ;;
            homer)      configure_homer "$selected" ;;
        esac
    done

    log_info "Post-install configuration complete."
}

# ========================================
# DelugeVPN Configuration
# ========================================

configure_delugevpn() {
    log_info "Configuring DelugeVPN..."

    local config_file="$BASE_DIR/delugevpn/config/core.conf"

    # Wait for DelugeVPN to create its config
    if ! wait_for_file "$config_file" 120; then
        log_warn "DelugeVPN config not found after 120s. Skipping configuration."
        return
    fi

    docker stop delugevpn >/dev/null 2>&1 || true
    rm -f "$BASE_DIR/delugevpn/config/core.conf~" 2>/dev/null

    # Enable remote daemon access and move completed
    sed -i 's/"allow_remote": false/"allow_remote": true/g' "$config_file"
    sed -i 's/"move_completed": false/"move_completed": true/g' "$config_file"

    docker start delugevpn >/dev/null 2>&1 || true

    # Add daemon credentials to auth file
    if [ -n "${DAEMON_USER:-}" ] && [ -n "${DAEMON_PASS:-}" ]; then
        echo "${DAEMON_USER}:${DAEMON_PASS}:10" >> "$BASE_DIR/delugevpn/config/auth"
    fi

    log_info "DelugeVPN configured."
}

# ========================================
# Jackett Configuration
# ========================================

configure_jackett() {
    log_info "Configuring Jackett..."

    local config_file="$BASE_DIR/jackett/Jackett/ServerConfig.json"

    if ! wait_for_file "$config_file" 120; then
        log_warn "Jackett config not found after 120s. Skipping configuration."
        return
    fi

    docker stop jackett >/dev/null 2>&1 || true

    # Set FlareSolverr URL
    sed -i "s|\"FlareSolverrUrl\": \".*\"|\"FlareSolverrUrl\": \"http://${IP_ADDRESS}:8191\"|g" "$config_file"

    docker start jackett >/dev/null 2>&1 || true

    log_info "Jackett configured with FlareSolverr URL."
}

# ========================================
# NZBGet Configuration
# ========================================

configure_nzbget() {
    log_info "Configuring NZBGet..."

    local config_file="$BASE_DIR/nzbget/nzbget.conf"

    if ! wait_for_file "$config_file" 120; then
        log_warn "NZBGet config not found after 120s. Skipping configuration."
        return
    fi

    docker stop nzbget >/dev/null 2>&1 || true

    if [ -n "${DAEMON_USER:-}" ]; then
        sed -i "s/ControlUsername=nzbget/ControlUsername=${DAEMON_USER}/g" "$config_file"
    fi
    if [ -n "${DAEMON_PASS:-}" ]; then
        sed -i "s/ControlPassword=tegbzn6789/ControlPassword=${DAEMON_PASS}/g" "$config_file"
    fi
    sed -i 's/{MainDir}\/intermediate/{MainDir}\/incomplete/g' "$config_file"

    docker start nzbget >/dev/null 2>&1 || true

    log_info "NZBGet configured."
}

# ========================================
# Homer Dashboard Configuration
# ========================================

configure_homer() {
    local selected="$1"
    log_info "Configuring Homer dashboard..."

    local homer_dir="$BASE_DIR/homer"
    local assets_dir="$BASE_DIR/homer_assets"

    if ! wait_for_file "$homer_dir/config.yml" 60; then
        log_warn "Homer config not found. Attempting to copy from assets..."
    fi

    docker stop homer >/dev/null 2>&1 || true

    # Copy base config and assets if available
    if [ -d "$assets_dir" ]; then
        [ -f "$assets_dir/config.yml" ] && cp "$assets_dir/config.yml" "$homer_dir/config.yml"
        [ -f "$assets_dir/mediaboxconfig.html" ] && cp "$assets_dir/mediaboxconfig.html" "$homer_dir/"
        [ -f "$assets_dir/portmap.html" ] && cp "$assets_dir/portmap.html" "$homer_dir/"
        [ -d "$assets_dir/icons" ] && cp -r "$assets_dir/icons/"* "$homer_dir/icons/" 2>/dev/null || true
    fi

    # Substitute variables in Homer config
    if [ -f "$homer_dir/config.yml" ]; then
        sed -i "s/thishost/${HOSTNAME_VAL}/g" "$homer_dir/config.yml"
        sed -i "s/locip/${IP_ADDRESS}/g" "$homer_dir/config.yml"
    fi

    if [ -f "$homer_dir/mediaboxconfig.html" ]; then
        sed -i "s/locip/${IP_ADDRESS}/g" "$homer_dir/mediaboxconfig.html"
        if [ -n "${DAEMON_USER:-}" ]; then
            sed -i "s/daemonun/${DAEMON_USER}/g" "$homer_dir/mediaboxconfig.html"
        fi
        if [ -n "${DAEMON_PASS:-}" ]; then
            sed -i "s/daemonpass/${DAEMON_PASS}/g" "$homer_dir/mediaboxconfig.html"
        fi
    fi

    # Create sanitized env display (no PIA creds)
    if [ -f "$BASE_DIR/.env" ]; then
        sed '/^PIA/d' < "$BASE_DIR/.env" > "$homer_dir/env.txt"
    fi

    docker start homer >/dev/null 2>&1 || true

    log_info "Homer dashboard configured."
}
