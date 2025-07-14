#!/bin/bash

# Bastion-Omni Backup Script
# Creates comprehensive backups of all critical data

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="${PROJECT_DIR}/.env.local"

# Load environment variables
if [[ -f "$ENV_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$ENV_FILE"
fi

# Configuration
BACKUP_DIR="${BACKUP_DIR:-${PROJECT_DIR}/backups}"
BACKUP_TYPE="${BACKUP_TYPE:-full}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_NAME="backup-${TIMESTAMP}"
COMPRESSION_LEVEL="${COMPRESSION_LEVEL:-6}"
QUIET="${QUIET:-false}"

# Retention settings
FULL_RETENTION_DAYS="${FULL_RETENTION_DAYS:-30}"
INCREMENTAL_RETENTION_DAYS="${INCREMENTAL_RETENTION_DAYS:-7}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    if [[ "$QUIET" != "true" ]]; then
        echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
    fi
}

log_success() {
    if [[ "$QUIET" != "true" ]]; then
        echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} ✓ $1"
    fi
}

log_warn() {
    if [[ "$QUIET" != "true" ]]; then
        echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} ⚠ $1"
    fi
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} ✗ $1" >&2
}

create_backup_structure() {
    local backup_path="$1"
    
    mkdir -p "$backup_path"/{config,data,databases,volumes}
    
    # Create manifest file
    cat > "$backup_path/manifest.json" << EOF
{
    "backup_name": "$BACKUP_NAME",
    "backup_type": "$BACKUP_TYPE",
    "timestamp": "$TIMESTAMP",
    "domain": "${DOMAIN_NAME:-unknown}",
    "version": "1.0"
}
EOF
}

backup_configuration() {
    local backup_path="$1"
    local config_dir="$backup_path/config"
    
    log "Backing up configuration files..."
    
    # Environment files
    cp "$PROJECT_DIR"/.env.* "$config_dir/" 2>/dev/null || true
    
    # Omni configuration
    if [[ -d "$PROJECT_DIR/omni" ]]; then
        mkdir -p "$config_dir/omni"
        cp -r "$PROJECT_DIR/omni"/* "$config_dir/omni/" 2>/dev/null || true
    fi
    
    # Nginx configuration
    if [[ -d "$PROJECT_DIR/nginx" ]]; then
        cp -r "$PROJECT_DIR/nginx" "$config_dir/"
    fi
    
    # Other service configurations
    for service in prometheus grafana loki registry postgres certbot; do
        if [[ -d "$PROJECT_DIR/$service" ]]; then
            cp -r "$PROJECT_DIR/$service" "$config_dir/"
        fi
    done
    
    # Docker Compose files
    cp "$PROJECT_DIR"/docker-compose.*.yml "$config_dir/" 2>/dev/null || true
    
    log_success "Configuration backup completed"
}

backup_databases() {
    local backup_path="$1"
    local db_dir="$backup_path/databases"
    
    log "Backing up databases..."
    
    # PostgreSQL backup (if running)
    if docker ps --format "table {{.Names}}" | grep -q "bastion-postgres"; then
        log "Backing up PostgreSQL databases..."
        
        # Keycloak database
        docker exec bastion-postgres pg_dump -U postgres keycloak > "$db_dir/keycloak.sql" 2>/dev/null || {
            log_warn "Failed to backup Keycloak database"
        }
        
        # Main postgres database
        docker exec bastion-postgres pg_dumpall -U postgres > "$db_dir/postgres-all.sql" 2>/dev/null || {
            log_warn "Failed to backup PostgreSQL databases"
        }
    fi
    
    log_success "Database backup completed"
}

backup_docker_volumes() {
    local backup_path="$1"
    local volumes_dir="$backup_path/volumes"
    
    log "Backing up Docker volumes..."
    
    # Get list of volumes for this project
    local project_name="${COMPOSE_PROJECT_NAME:-omni}"
    
    # Common volumes to backup
    local volumes=(
        "${project_name}_omni_data"
        "${project_name}_postgres_data"
        "${project_name}_keycloak_data"
        "${project_name}_prometheus_data"
        "${project_name}_grafana_data"
        "${project_name}_registry_data"
        "${project_name}_pihole_data"
        "${project_name}_nginx_logs"
        "${project_name}_certbot_certs"
    )
    
    for volume in "${volumes[@]}"; do
        if docker volume ls --format "{{.Name}}" | grep -q "^${volume}$"; then
            log "Backing up volume: $volume"
            docker run --rm \
                -v "$volume:/volume:ro" \
                -v "$volumes_dir:/backup" \
                busybox tar czf "/backup/${volume}.tar.gz" -C /volume . 2>/dev/null || {
                log_warn "Failed to backup volume: $volume"
            }
        fi
    done
    
    log_success "Volume backup completed"
}

backup_ssl_certificates() {
    local backup_path="$1"
    local certs_dir="$backup_path/data/ssl"
    
    mkdir -p "$certs_dir"
    
    log "Backing up SSL certificates..."
    
    # Omni TLS certificates
    if [[ -f "$PROJECT_DIR/omni/tls.crt" ]]; then
        cp "$PROJECT_DIR/omni/tls.crt" "$certs_dir/"
        cp "$PROJECT_DIR/omni/tls.key" "$certs_dir/" 2>/dev/null || true
    fi
    
    # Let's Encrypt certificates (if certbot volume exists)
    if docker volume ls --format "{{.Name}}" | grep -q "certbot_certs"; then
        docker run --rm \
            -v certbot_certs:/letsencrypt:ro \
            -v "$certs_dir:/backup" \
            busybox tar czf "/backup/letsencrypt.tar.gz" -C /letsencrypt . 2>/dev/null || {
            log_warn "Failed to backup Let's Encrypt certificates"
        }
    fi
    
    log_success "SSL certificates backup completed"
}

compress_backup() {
    local backup_path="$1"
    local archive_path="${backup_path}.tar.gz"
    
    log "Compressing backup..."
    
    tar -czf "$archive_path" -C "$(dirname "$backup_path")" "$(basename "$backup_path")"
    
    # Remove uncompressed backup
    rm -rf "$backup_path"
    
    log_success "Backup compressed: $(basename "$archive_path")"
    log_success "Backup size: $(du -h "$archive_path" | cut -f1)"
}

cleanup_old_backups() {
    log "Cleaning up old backups..."
    
    local retention_days
    case "$BACKUP_TYPE" in
        "full")
            retention_days="$FULL_RETENTION_DAYS"
            ;;
        "incremental")
            retention_days="$INCREMENTAL_RETENTION_DAYS"
            ;;
        *)
            retention_days="30"
            ;;
    esac
    
    # Remove backups older than retention period
    find "$BACKUP_DIR" -name "backup-*.tar.gz" -type f -mtime "+$retention_days" -delete 2>/dev/null || true
    
    log_success "Old backups cleaned up (retention: ${retention_days} days)"
}

list_backups() {
    echo "Available Backups:"
    echo "=================="
    
    if [[ ! -d "$BACKUP_DIR" ]]; then
        echo "No backup directory found: $BACKUP_DIR"
        return 1
    fi
    
    local backups=()
    while IFS= read -r -d '' backup; do
        backups+=("$backup")
    done < <(find "$BACKUP_DIR" -name "backup-*.tar.gz" -type f -print0 | sort -z)
    
    if [[ ${#backups[@]} -eq 0 ]]; then
        echo "No backups found"
        return 0
    fi
    
    printf "%-25s %-10s %-10s %s\n" "BACKUP NAME" "TYPE" "SIZE" "DATE"
    echo "-------------------------------------------------------------------"
    
    for backup in "${backups[@]}"; do
        local name
        name=$(basename "$backup" .tar.gz)
        local size
        size=$(du -h "$backup" | cut -f1)
        local date
        date=$(stat -c %y "$backup" | cut -d' ' -f1)
        local type="full" # Default, could be enhanced to detect type
        
        printf "%-25s %-10s %-10s %s\n" "$name" "$type" "$size" "$date"
    done
}

show_help() {
    cat << EOF
Bastion-Omni Backup Script

Usage: $0 [OPTIONS]

Options:
    -t, --type TYPE         Backup type: full, incremental (default: full)
    -o, --output DIR        Backup output directory (default: ./backups)
    -q, --quiet             Quiet mode - minimal output
    -l, --list              List available backups
    -h, --help              Show this help message

Environment Variables:
    BACKUP_DIR              Default backup directory
    FULL_RETENTION_DAYS     Full backup retention in days (default: 30)
    INCREMENTAL_RETENTION_DAYS  Incremental backup retention in days (default: 7)
    COMPRESSION_LEVEL       Compression level 1-9 (default: 6)

Examples:
    $0                      # Create full backup
    $0 --type incremental   # Create incremental backup
    $0 --list               # List available backups
    $0 --quiet              # Create backup with minimal output

EOF
}

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -t|--type)
                BACKUP_TYPE="$2"
                shift 2
                ;;
            -o|--output)
                BACKUP_DIR="$2"
                shift 2
                ;;
            -q|--quiet)
                QUIET="true"
                shift
                ;;
            -l|--list)
                list_backups
                exit 0
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    # Validate backup type
    if [[ "$BACKUP_TYPE" != "full" && "$BACKUP_TYPE" != "incremental" ]]; then
        log_error "Invalid backup type: $BACKUP_TYPE"
        echo "Valid types: full, incremental"
        exit 1
    fi
    
    # Create backup directory
    mkdir -p "$BACKUP_DIR"
    
    local backup_path="$BACKUP_DIR/$BACKUP_NAME"
    
    log "Starting $BACKUP_TYPE backup..."
    log "Backup path: $backup_path"
    
    # Create backup structure
    create_backup_structure "$backup_path"
    
    # Perform backup based on type
    case "$BACKUP_TYPE" in
        "full")
            backup_configuration "$backup_path"
            backup_databases "$backup_path"
            backup_docker_volumes "$backup_path"
            backup_ssl_certificates "$backup_path"
            ;;
        "incremental")
            backup_configuration "$backup_path"
            backup_databases "$backup_path"
            # Skip volumes for incremental
            ;;
    esac
    
    # Compress the backup
    compress_backup "$backup_path"
    
    # Cleanup old backups
    cleanup_old_backups
    
    log_success "Backup completed successfully!"
    log_success "Backup file: ${backup_path}.tar.gz"
}

main "$@"
