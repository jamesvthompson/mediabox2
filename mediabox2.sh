#!/usr/bin/env bash
#
# ================================
# |   M E D I A B O X  2        |
# |   Modular Media Installer   |
# ================================
#
# A modular, whiptail-based installer for Docker media server stacks.
# Select which services to install, update, reconfigure, or manage.

set -euo pipefail

# Resolve the base directory (where this script lives)
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export BASE_DIR

# Source library files
source "$BASE_DIR/lib/common.sh"
source "$BASE_DIR/lib/config.sh"
source "$BASE_DIR/lib/services.sh"
source "$BASE_DIR/lib/compose.sh"
source "$BASE_DIR/lib/postinstall.sh"

# ========================================
# Menu Actions
# ========================================

do_new_install() {
    log_step "Starting new installation..."

    # 1. Detect system info
    detect_system_info

    # 2. Prompt for media directories
    prompt_media_dirs || { log_error "Media directory configuration cancelled."; return 1; }

    # 3. Discover available modules
    discover_modules

    # 4. Service selection
    local selected
    selected=$(show_service_selector) || { log_error "Service selection cancelled."; return 1; }

    if [ -z "$selected" ]; then
        whiptail_msgbox "No Selection" "No services were selected. Returning to main menu."
        return 1
    fi

    # 5. Resolve dependencies
    selected=$(resolve_dependencies "$selected")

    # 6. Prompt for service-specific config
    prompt_service_config "$selected"

    # 7. Show confirmation
    local summary="The following services will be installed:\n\n"
    for svc in $selected; do
        local port_info=""
        if [ -n "${MODULE_PORT[$svc]:-}" ]; then
            port_info=" (port ${MODULE_PORT[$svc]})"
        fi
        summary+="  - ${MODULE_DESC[$svc]:-$svc}${port_info}\n"
    done
    summary+="\nMedia Directories:\n"
    summary+="  Downloads: $DLDIR\n"
    summary+="  TV: $TVDIR\n"
    summary+="  Movies: $MOVIEDIR\n"
    summary+="  Music: $MUSICDIR\n"
    summary+="  Misc: $MISCDIR\n"

    if ! whiptail_yesno "Confirm Installation" "$summary"; then
        log_info "Installation cancelled by user."
        return 1
    fi

    # 8. Create directories
    create_media_dirs
    create_service_dirs "$selected"

    # 9. Generate .env file
    generate_env_file

    # 10. Assemble docker-compose.yml
    assemble_compose "$selected"

    # 11. Deploy
    log_step "Pulling and launching containers..."
    whiptail_msgbox "Deploying" "Containers will now be pulled and launched.\nThis may take a while depending on your download speed.\n\nPress OK to continue."
    compose_up

    # 12. Post-install hooks
    run_postinstall_hooks "$selected"

    # 13. Save state
    save_state "$selected"

    # 14. Generate port mapping
    local port_file="$BASE_DIR/homer/ports.txt"
    if [ -d "$BASE_DIR/homer" ]; then
        generate_port_summary > "$port_file" 2>/dev/null || true
    fi

    # 15. Show completion
    local completion_msg="Installation complete!\n\n"
    if echo "$selected" | grep -qw "homer"; then
        completion_msg+="Dashboard: http://${IP_ADDRESS}:80\n"
    fi
    if echo "$selected" | grep -qw "portainer"; then
        completion_msg+="Portainer: https://${IP_ADDRESS}:9443\n"
    fi
    if echo "$selected" | grep -qw "plex"; then
        completion_msg+="Plex: http://${IP_ADDRESS}:32400/web\n"
    fi
    completion_msg+="\nAll services are starting up. Some may take a minute to become available."

    whiptail_msgbox "Installation Complete" "$completion_msg"
    log_info "Installation complete!"
}

do_update() {
    if ! is_installed; then
        whiptail_msgbox "Not Installed" "No existing installation found.\nPlease run 'New Install' first."
        return 1
    fi

    log_step "Updating existing installation..."

    load_state
    load_existing_config

    whiptail_msgbox "Update" "This will pull the latest images for all installed services and restart them.\n\nPress OK to continue."

    compose_pull
    compose_up

    # Update state
    save_state "$INSTALLED_SERVICES"

    whiptail_msgbox "Update Complete" "All containers have been updated to their latest images."
    log_info "Update complete!"
}

do_relaunch() {
    if ! is_installed; then
        whiptail_msgbox "Not Installed" "No existing installation found.\nPlease run 'New Install' first."
        return 1
    fi

    log_step "Relaunching existing stack..."

    load_existing_config
    compose_up

    whiptail_msgbox "Relaunch Complete" "All containers have been relaunched."
    log_info "Relaunch complete!"
}

do_reconfigure() {
    if ! is_installed; then
        whiptail_msgbox "Not Installed" "No existing installation found.\nPlease run 'New Install' first."
        return 1
    fi

    log_step "Reconfiguring services..."

    load_state
    load_existing_config
    detect_system_info
    discover_modules

    # Show service selector with currently installed services pre-checked
    local selected
    selected=$(show_service_selector "$INSTALLED_SERVICES") || { log_error "Reconfiguration cancelled."; return 1; }

    if [ -z "$selected" ]; then
        whiptail_msgbox "No Selection" "No services were selected. Returning to main menu."
        return 1
    fi

    selected=$(resolve_dependencies "$selected")

    # Determine added and removed services
    local added="" removed=""
    for svc in $selected; do
        if ! echo "$INSTALLED_SERVICES" | grep -qw "$svc"; then
            added+="$svc "
        fi
    done
    for svc in $INSTALLED_SERVICES; do
        if ! echo "$selected" | grep -qw "$svc"; then
            removed+="$svc "
        fi
    done

    # Prompt for config of newly added services
    if [ -n "$added" ]; then
        prompt_service_config "$added"
    fi

    # Confirm changes
    local summary="Reconfiguration Summary:\n\n"
    if [ -n "$added" ]; then
        summary+="Services to ADD:\n"
        for svc in $added; do
            summary+="  + ${MODULE_DESC[$svc]:-$svc}\n"
        done
    fi
    if [ -n "$removed" ]; then
        summary+="\nServices to REMOVE:\n"
        for svc in $removed; do
            summary+="  - ${MODULE_DESC[$svc]:-$svc}\n"
        done
    fi
    if [ -z "$added" ] && [ -z "$removed" ]; then
        summary+="No changes detected."
    fi

    if ! whiptail_yesno "Confirm Reconfiguration" "$summary"; then
        log_info "Reconfiguration cancelled."
        return 1
    fi

    # Create dirs for new services
    if [ -n "$added" ]; then
        create_service_dirs "$added"
    fi

    # Regenerate .env and docker-compose.yml
    generate_env_file
    assemble_compose "$selected"

    # Remove old services
    if [ -n "$removed" ]; then
        remove_services "$removed"
    fi

    # Launch updated stack
    compose_up

    # Post-install for new services
    if [ -n "$added" ]; then
        run_postinstall_hooks "$added"
    fi

    save_state "$selected"

    whiptail_msgbox "Reconfiguration Complete" "Services have been reconfigured successfully."
    log_info "Reconfiguration complete!"
}

do_status() {
    if ! is_installed; then
        whiptail_msgbox "Not Installed" "No existing installation found.\nPlease run 'New Install' first."
        return 1
    fi

    load_existing_config

    local status
    status=$(compose_status_formatted 2>&1)

    # Write to temp file for textbox display
    local tmp_file
    tmp_file=$(mktemp)
    echo "$status" > "$tmp_file"
    whiptail_textbox "Mediabox2 Status" "$tmp_file"
    rm -f "$tmp_file"
}

do_reset() {
    if ! is_installed; then
        whiptail_msgbox "Not Installed" "No existing installation found. Nothing to reset."
        return 1
    fi

    if ! whiptail_yesno "Confirm Reset" "WARNING: This will stop and remove all containers.\n\nDo you want to continue?"; then
        return 1
    fi

    local remove_volumes=false
    if whiptail_yesno "Remove Volumes?" "Do you also want to remove Docker volumes?\n\n(This will delete all container data)"; then
        remove_volumes=true
    fi

    load_existing_config

    compose_down "$remove_volumes"

    # Archive env file
    if [ -f "$BASE_DIR/.env" ]; then
        mkdir -p "$BASE_DIR/historical/env_files"
        mv "$BASE_DIR/.env" "$BASE_DIR/historical/env_files/$(date +%Y-%m-%d_%H:%M).env"
    fi

    # Remove generated files
    rm -f "$BASE_DIR/docker-compose.yml"
    rm -f "$BASE_DIR/$STATE_FILE"

    whiptail_msgbox "Reset Complete" "All containers have been stopped and removed.\nGenerated files have been cleaned up.\n\nYou can run 'New Install' to start fresh."
    log_info "Reset complete!"
}

# ========================================
# Main Menu
# ========================================

main_menu() {
    while true; do
        local choice
        choice=$(whiptail_menu "Mediabox2 Installer" \
            "new_install"  "New Install" \
            "update"       "Update Existing Install" \
            "relaunch"     "Relaunch Existing Stack" \
            "reconfigure"  "Reconfigure Services" \
            "status"       "Status" \
            "reset"        "Reset" \
            "exit"         "Exit") || break

        case "$choice" in
            new_install)  do_new_install ;;
            update)       do_update ;;
            relaunch)     do_relaunch ;;
            reconfigure)  do_reconfigure ;;
            status)       do_status ;;
            reset)        do_reset ;;
            exit|"")      break ;;
        esac
    done
}

# ========================================
# Entry Point
# ========================================

main() {
    check_prerequisites
    main_menu
    log_info "Goodbye!"
}

main "$@"
