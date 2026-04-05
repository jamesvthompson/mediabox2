#!/usr/bin/env bash
# compose.sh - Docker-compose assembly and management

# ========================================
# Compose Assembly
# ========================================

assemble_compose() {
    local selected="$1"
    local output="$BASE_DIR/docker-compose.yml"
    local modules_dir="$BASE_DIR/modules"
    local temp_dir
    temp_dir=$(mktemp -d)

    log_step "Assembling docker-compose.yml from selected modules..."

    # Start with empty compose structure
    echo "services: {}" > "$temp_dir/base.yml"

    local current="$temp_dir/base.yml"
    local count=0

    for mod in $selected; do
        local mod_file="$modules_dir/${mod}.yml"

        # Swap plex module for GPU variant if configured
        if [ "$mod" = "plex" ] && [ -n "${PLEX_GPU:-}" ] && [ "$PLEX_GPU" != "none" ]; then
            mod_file="$modules_dir/plex-${PLEX_GPU}-gpu.yml"
            log_info "Using Plex with ${PLEX_GPU} GPU transcoding"
        fi

        if [ ! -f "$mod_file" ]; then
            log_warn "Module file not found: $mod_file (skipping)"
            continue
        fi

        # Strip metadata comments and merge
        local clean_file="$temp_dir/${mod}_clean.yml"
        grep -v "^#" "$mod_file" | grep -v "^$" > "$clean_file" || true

        # If the clean file is empty or has no content, skip
        if [ ! -s "$clean_file" ]; then
            continue
        fi

        local merged="$temp_dir/merged_${count}.yml"
        yq eval-all 'select(fileIndex == 0) *+ select(fileIndex == 1)' \
            "$current" "$clean_file" > "$merged" 2>/dev/null

        if [ $? -eq 0 ] && [ -s "$merged" ]; then
            current="$merged"
            count=$((count + 1))
        else
            log_warn "Failed to merge module: $mod (skipping)"
        fi
    done

    # Write final compose file
    cp "$current" "$output"

    # Clean up
    rm -rf "$temp_dir"

    log_info "docker-compose.yml assembled with $count services."
}

# ========================================
# Docker Compose Operations
# ========================================

compose_up() {
    log_step "Starting containers..."
    cd "$BASE_DIR"
    docker compose up -d --remove-orphans 2>&1
    local exit_code=$?
    if [ $exit_code -eq 0 ]; then
        log_info "Containers started successfully."
    else
        log_error "Failed to start containers (exit code: $exit_code)"
    fi
    return $exit_code
}

compose_down() {
    local remove_volumes="${1:-false}"
    log_step "Stopping containers..."
    cd "$BASE_DIR"
    if [ "$remove_volumes" = "true" ]; then
        docker compose down -v 2>&1
    else
        docker compose down 2>&1
    fi
    local exit_code=$?
    if [ $exit_code -eq 0 ]; then
        log_info "Containers stopped."
    else
        log_error "Failed to stop containers (exit code: $exit_code)"
    fi
    return $exit_code
}

compose_pull() {
    log_step "Pulling latest images..."
    cd "$BASE_DIR"
    docker compose pull 2>&1
    local exit_code=$?
    if [ $exit_code -eq 0 ]; then
        log_info "Images updated."
    else
        log_error "Failed to pull images (exit code: $exit_code)"
    fi
    return $exit_code
}

compose_stop() {
    log_step "Stopping containers..."
    cd "$BASE_DIR"
    docker compose stop 2>&1
}

compose_restart() {
    log_step "Restarting containers..."
    cd "$BASE_DIR"
    docker compose restart 2>&1
}

# ========================================
# Status Display
# ========================================

compose_status() {
    cd "$BASE_DIR"
    if [ ! -f docker-compose.yml ]; then
        echo "No docker-compose.yml found. Nothing is installed."
        return 1
    fi

    local status_output
    status_output=$(docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}" 2>&1)
    echo "$status_output"
}

# Format status for whiptail display
compose_status_formatted() {
    local status
    status=$(compose_status 2>&1)

    if [ $? -ne 0 ]; then
        echo "$status"
        return
    fi

    # Build a nice summary
    local running stopped total
    running=$(docker compose ps --status running -q 2>/dev/null | wc -l)
    stopped=$(docker compose ps --status exited -q 2>/dev/null | wc -l)
    total=$((running + stopped))

    local summary="Mediabox2 Status\n"
    summary+="========================\n"
    summary+="Total services: $total\n"
    summary+="Running: $running\n"
    summary+="Stopped: $stopped\n"
    summary+="========================\n\n"
    summary+="$status"

    echo -e "$summary"
}

# Generate port mapping summary
generate_port_summary() {
    cd "$BASE_DIR"
    local summary="Service Port Mapping\n"
    summary+="========================\n\n"

    for container in $(docker ps --format '{{.Names}}' | sort); do
        local ports
        ports=$(docker port "$container" 2>/dev/null)
        if [ -n "$ports" ]; then
            summary+="=== $container ===\n$ports\n\n"
        fi
    done

    summary+="========================\n"
    summary+="Access dashboard: http://${IP_ADDRESS}:80\n"

    echo -e "$summary"
}

# ========================================
# Remove Specific Services
# ========================================

remove_services() {
    local services_to_remove="$1"
    cd "$BASE_DIR"

    for svc in $services_to_remove; do
        log_info "Removing service: $svc"
        docker compose rm -f -s "$svc" 2>/dev/null || true
    done
}
