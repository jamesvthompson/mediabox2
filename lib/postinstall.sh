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

    wait_for_file "$homer_dir/config.yml" 60 || true
    docker stop homer >/dev/null 2>&1 || true

    # Copy assets (icons, html pages) — but NOT config.yml (generated dynamically below)
    if [ -d "$assets_dir" ]; then
        [ -f "$assets_dir/mediaboxconfig.html" ] && cp "$assets_dir/mediaboxconfig.html" "$homer_dir/"
        [ -f "$assets_dir/portmap.html" ]        && cp "$assets_dir/portmap.html" "$homer_dir/"
        if [ -d "$assets_dir/icons" ]; then
            mkdir -p "$homer_dir/icons"
            cp -r "$assets_dir/icons/"* "$homer_dir/icons/" 2>/dev/null || true
        fi
    fi

    # Generate dynamic config.yml based only on selected services
    _generate_homer_config "$selected" > "$homer_dir/config.yml"

    # Substitute variables in mediaboxconfig.html
    if [ -f "$homer_dir/mediaboxconfig.html" ]; then
        sed -i "s/locip/${IP_ADDRESS}/g" "$homer_dir/mediaboxconfig.html"
        [ -n "${DAEMON_USER:-}" ] && sed -i "s/daemonun/${DAEMON_USER}/g" "$homer_dir/mediaboxconfig.html"
        [ -n "${DAEMON_PASS:-}" ] && sed -i "s/daemonpass/${DAEMON_PASS}/g" "$homer_dir/mediaboxconfig.html"
    fi

    # Create sanitized env display (no PIA creds)
    [ -f "$BASE_DIR/.env" ] && sed '/^PIA/d' < "$BASE_DIR/.env" > "$homer_dir/env.txt"

    docker start homer >/dev/null 2>&1 || true
    log_info "Homer dashboard configured."
}

# Generate Homer config.yml dynamically from selected modules.
# Writes to stdout — caller redirects to file (not a subshell, so arrays are fine).
_generate_homer_config() {
    local selected="$1"
    local modules_dir="$BASE_DIR/modules"

    # ── Static header ──────────────────────────────────────────
    cat <<HEADER
---
title: "Mediabox2"
subtitle: "${HOSTNAME_VAL}"
icon: "far fa-play-circle"

header: true
footer: false
columns: "4"
theme: default
colors:
  light:
    highlight-primary: "#3367d6"
    highlight-secondary: "#4285f4"
    highlight-hover: "#5a95f5"
    background: "#f5f5f5"
    card-background: "#ffffff"
    text: "#363636"
    text-header: "#ffffff"
    text-title: "#303030"
    text-subtitle: "#424242"
    card-shadow: rgba(0, 0, 0, 0.1)
    link: "#3273dc"
    link-hover: "#363636"
  dark:
    highlight-primary: "#3367d6"
    highlight-secondary: "#4285f4"
    highlight-hover: "#5a95f5"
    background: "#131313"
    card-background: "#2b2b2b"
    text: "#eaeaea"
    text-header: "#ffffff"
    text-title: "#fafafa"
    text-subtitle: "#f5f5f5"
    card-shadow: rgba(0, 0, 0, 0.4)
    link: "#3273dc"
    link-hover: "#ffdd57"

links:
  - name: "Mediabox2"
    icon: "fab fa-github"
    url: "https://github.com/jamesvthompson/mediabox2"
    target: "_blank"
  - name: "Getting Started"
    icon: "fas fa-check-square"
    url: "/assets/mediaboxconfig.html"
    target: "_blank"
  - name: "Port Mappings"
    icon: "fas fa-network-wired"
    url: "/assets/portmap.html"
    target: "_blank"

services:
HEADER

    # ── Dynamic service sections ───────────────────────────────
    local groups="get manage monitor watch"
    declare -A GROUP_NAMES=(
        [get]="Get It"
        [manage]="Manage It"
        [monitor]="Monitor It"
        [watch]="Watch It"
    )
    declare -A GROUP_ICONS=(
        [get]="fas fa-download"
        [manage]="fas fa-edit"
        [monitor]="fas fa-heartbeat"
        [watch]="fas fa-tv"
    )
    declare -A GROUP_TAGSTYLE=(
        [get]="is-info"
        [manage]="is-info"
        [monitor]="is-danger"
        [watch]="is-success"
    )

    for group in $groups; do
        local items=""
        for mod in $selected; do
            local mod_file="$modules_dir/${mod}.yml"
            [ -f "$mod_file" ] || continue

            local homer_group
            homer_group=$(grep "^# homer_group:" "$mod_file" | sed 's/^# homer_group: *//' | head -1)
            [ "$homer_group" = "$group" ] || continue

            local homer_name homer_icon homer_url
            homer_name=$(grep "^# homer_name:" "$mod_file" | sed 's/^# homer_name: *//' | head -1)
            homer_icon=$(grep "^# homer_icon:" "$mod_file" | sed 's/^# homer_icon: *//' | head -1)
            homer_url=$(grep "^# homer_url:" "$mod_file" | sed 's/^# homer_url: *//' | \
                        sed "s/locip/${IP_ADDRESS}/g" | head -1)

            items+="      - name: \"${homer_name}\"\n"
            items+="        logo: \"${homer_icon}\"\n"
            items+="        tag: \"${group}\"\n"
            items+="        tagstyle: \"${GROUP_TAGSTYLE[$group]}\"\n"
            items+="        url: \"${homer_url}\"\n"
            items+="        target: \"_blank\"\n"
        done

        if [ -n "$items" ]; then
            echo "  - name: \"${GROUP_NAMES[$group]}\""
            echo "    icon: \"${GROUP_ICONS[$group]}\""
            echo "    items:"
            echo -e "$items"
        fi
    done
}
