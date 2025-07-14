#!/bin/bash

# Bastion-Omni Setup Script
# Complete self-contained Omni deployment with all dependencies

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env.bastion"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.bastion.yml"

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

# Help function
show_help() {
    cat << EOF
Bastion-Omni Setup Script

Usage: $0 [OPTIONS]

Options:
    -d, --domain DOMAIN         Domain name for deployment
    -e, --email EMAIL          Admin email address
    -p, --profiles PROFILES    Comma-separated list of service profiles to enable
    --generate-passwords       Generate secure passwords for all services
    --keycloak-setup          Setup Keycloak with default configuration
    --start                   Start all services after setup
    --stop                    Stop all services
    --logs [SERVICE]          Show logs for all services or specific service
    --status                  Show status of all services
    -h, --help                Show this help message

Available Profiles:
    saml        - Keycloak, PostgreSQL for SAML authentication
    monitoring  - Prometheus, Grafana, Loki for monitoring
    dns         - Pi-hole for DNS services
    registry    - Docker registry for container images
    pxe         - TFTP, DHCP, HTTP boot services for PXE boot
    dhcp        - DHCP server for network bootstrap
    ntp         - NTP server for time synchronization

Examples:
    $0 --domain omni.example.com --email admin@example.com --profiles saml,monitoring --start
    $0 --generate-passwords
    $0 --logs omni
    $0 --stop

EOF
}

# Generate secure passwords
generate_passwords() {
    log "Generating secure passwords..."
    
    local env_file_tmp="${ENV_FILE}.tmp"
    cp "$ENV_FILE" "$env_file_tmp"
    
    # Generate passwords
    local postgres_password=$(openssl rand -base64 32)
    local keycloak_db_password=$(openssl rand -base64 32)
    local keycloak_admin_password=$(openssl rand -base64 32)
    local redis_password=$(openssl rand -base64 32)
    local pihole_password=$(openssl rand -base64 32)
    local grafana_password=$(openssl rand -base64 32)
    
    # Replace in env file
    sed -i "s/POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=${postgres_password}/" "$env_file_tmp"
    sed -i "s/KEYCLOAK_DB_PASSWORD=.*/KEYCLOAK_DB_PASSWORD=${keycloak_db_password}/" "$env_file_tmp"
    sed -i "s/KEYCLOAK_ADMIN_PASSWORD=.*/KEYCLOAK_ADMIN_PASSWORD=${keycloak_admin_password}/" "$env_file_tmp"
    sed -i "s/REDIS_PASSWORD=.*/REDIS_PASSWORD=${redis_password}/" "$env_file_tmp"
    sed -i "s/PIHOLE_PASSWORD=.*/PIHOLE_PASSWORD=${pihole_password}/" "$env_file_tmp"
    sed -i "s/GRAFANA_PASSWORD=.*/GRAFANA_PASSWORD=${grafana_password}/" "$env_file_tmp"
    
    mv "$env_file_tmp" "$ENV_FILE"
    
    log "Passwords generated and updated in $ENV_FILE"
    info "Keycloak Admin Password: $keycloak_admin_password"
    info "Grafana Admin Password: $grafana_password"
    info "Pi-hole Admin Password: $pihole_password"
}

# Generate Omni account UUID
generate_omni_uuid() {
    log "Generating Omni account UUID..."
    local uuid=$(uuidgen)
    sed -i "s/OMNI_ACCOUNT_UUID=.*/OMNI_ACCOUNT_UUID=${uuid}/" "$ENV_FILE"
    log "Omni account UUID: $uuid"
}

# Setup SSL certificates directory
setup_ssl() {
    log "Setting up SSL certificate directories..."
    mkdir -p "${SCRIPT_DIR}/omni"
    
    # Check if certificates exist
    if [[ ! -f "${SCRIPT_DIR}/omni/tls.crt" ]] || [[ ! -f "${SCRIPT_DIR}/omni/tls.key" ]]; then
        warn "SSL certificates not found. Please generate them using Let's Encrypt or place them at:"
        info "  - ${SCRIPT_DIR}/omni/tls.crt"
        info "  - ${SCRIPT_DIR}/omni/tls.key"
        info ""
        info "For Let's Encrypt with DNS challenge:"
        info "  certbot certonly --dns-provider --dns-provider-credentials /path/to/credentials \\"
        info "    -d your-domain.com -d '*.your-domain.com'"
        info ""
        info "Then copy the certificates:"
        info "  cp /etc/letsencrypt/live/your-domain.com/fullchain.pem ${SCRIPT_DIR}/omni/tls.crt"
        info "  cp /etc/letsencrypt/live/your-domain.com/privkey.pem ${SCRIPT_DIR}/omni/tls.key"
    fi
}

# Generate GPG key for Omni
generate_gpg_key() {
    log "Checking for Omni GPG key..."
    
    if [[ ! -f "${SCRIPT_DIR}/omni/omni.asc" ]]; then
        log "Generating GPG key for Omni etcd encryption..."
        
        # Source environment variables
        if [[ -f "$ENV_FILE" ]]; then
            source "$ENV_FILE"
        fi
        
        # Generate GPG key
        gpg --batch --gen-key <<EOF
%no-protection
Key-Type: RSA
Key-Length: 4096
Key-Usage: cert
Name-Real: Omni (Used for etcd data encryption)
Name-Email: ${ADMIN_EMAIL:-admin@example.com}
Expire-Date: 0
%commit
EOF
        
        # Get the fingerprint
        local fingerprint=$(gpg --list-secret-keys --with-colons | grep fpr | head -1 | cut -d: -f10)
        
        if [[ -z "$fingerprint" ]]; then
            error "Failed to generate or find GPG key fingerprint"
        fi
        
        # Add encryption subkey
        gpg --batch --quick-add-key "$fingerprint" rsa4096 encr never
        
        # Export the key
        gpg --export-secret-key --armor "${ADMIN_EMAIL:-admin@example.com}" > "${SCRIPT_DIR}/omni/omni.asc"
        
        log "GPG key generated and exported to ${SCRIPT_DIR}/omni/omni.asc"
    else
        log "GPG key already exists at ${SCRIPT_DIR}/omni/omni.asc"
    fi
}

# Setup registry authentication
setup_registry() {
    log "Setting up Docker registry authentication..."
    
    # Generate htpasswd file for registry
    if command -v htpasswd &> /dev/null; then
        # Generate with random password
        local registry_password=$(openssl rand -base64 16)
        htpasswd -Bbn admin "$registry_password" > "${SCRIPT_DIR}/registry/auth/htpasswd"
        log "Registry admin password: $registry_password"
    else
        warn "htpasswd not found. Using default registry password. Install apache2-utils for custom passwords."
    fi
}

# Keycloak setup
setup_keycloak() {
    log "Setting up Keycloak configuration..."
    
    # Wait for Keycloak to be ready
    info "Waiting for Keycloak to start..."
    while ! curl -f http://localhost:8080/health/ready &>/dev/null; do
        sleep 5
        info "Still waiting for Keycloak..."
    done
    
    log "Keycloak is ready. Manual configuration steps:"
    info "1. Access Keycloak at: https://keycloak.${DOMAIN_NAME:-your-domain.com}"
    info "2. Login with admin credentials from .env.bastion"
    info "3. Create realm 'omni'"
    info "4. Create SAML client with ID 'omni'"
    info "5. Configure client settings as per KEYCLOAK_SETUP.md"
}

# Start services
start_services() {
    log "Starting Bastion-Omni services..."
    
    if [[ ! -f "$ENV_FILE" ]]; then
        error "Environment file not found: $ENV_FILE"
    fi
    
    # Load environment
    source "$ENV_FILE"
    
    # Start services with profiles
    docker-compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d
    
    log "Services started successfully!"
    show_service_info
}

# Stop services
stop_services() {
    log "Stopping Bastion-Omni services..."
    docker-compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" down
    log "Services stopped successfully!"
}

# Show logs
show_logs() {
    local service=${1:-}
    
    if [[ -n "$service" ]]; then
        docker-compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" logs -f "$service"
    else
        docker-compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" logs -f
    fi
}

# Show status
show_status() {
    log "Bastion-Omni Service Status:"
    docker-compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" ps
}

# Show service information
show_service_info() {
    if [[ -f "$ENV_FILE" ]]; then
        source "$ENV_FILE"
    fi
    
    cat << EOF

${GREEN}===============================================================================${NC}
${GREEN}BASTION-OMNI DEPLOYMENT COMPLETE${NC}
${GREEN}===============================================================================${NC}

${YELLOW}Access URLs:${NC}
- Omni UI:          https://${DOMAIN_NAME:-your-domain.com}
- Nginx Status:     http://${DOMAIN_NAME:-your-domain.com}:8080
- Keycloak:         https://keycloak.${DOMAIN_NAME:-your-domain.com}
- Grafana:          https://grafana.${DOMAIN_NAME:-your-domain.com}
- Prometheus:       https://prometheus.${DOMAIN_NAME:-your-domain.com}
- Pi-hole:          https://pihole.${DOMAIN_NAME:-your-domain.com}
- Registry:         https://registry.${DOMAIN_NAME:-your-domain.com}

${YELLOW}Service Status:${NC}
EOF
    docker-compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" ps

    cat << EOF

${YELLOW}Next Steps:${NC}
1. Configure DNS to point all subdomains to this server
2. Setup authentication provider (Auth0 or complete Keycloak setup)
3. Access Omni UI and start creating clusters
4. Configure monitoring dashboards in Grafana

${YELLOW}Configuration Files:${NC}
- Environment: ${ENV_FILE}
- Docker Compose: ${COMPOSE_FILE}
- SSL Certificates: ${SCRIPT_DIR}/omni/tls.{crt,key}
- GPG Key: ${SCRIPT_DIR}/omni/omni.asc

${GREEN}===============================================================================${NC}

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--domain)
                DOMAIN_NAME="$2"
                shift 2
                ;;
            -e|--email)
                ADMIN_EMAIL="$2"
                shift 2
                ;;
            -p|--profiles)
                PROFILES="$2"
                shift 2
                ;;
            --generate-passwords)
                generate_passwords
                exit 0
                ;;
            --keycloak-setup)
                setup_keycloak
                exit 0
                ;;
            --start)
                start_services
                exit 0
                ;;
            --stop)
                stop_services
                exit 0
                ;;
            --logs)
                show_logs "$2"
                exit 0
                ;;
            --status)
                show_status
                exit 0
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                ;;
        esac
    done
}

# Main setup function
main_setup() {
    log "Starting Bastion-Omni setup..."
    
    # Update environment file if domain/email provided
    if [[ -n "${DOMAIN_NAME:-}" ]]; then
        sed -i "s/DOMAIN_NAME=.*/DOMAIN_NAME=${DOMAIN_NAME}/" "$ENV_FILE"
    fi
    
    if [[ -n "${ADMIN_EMAIL:-}" ]]; then
        sed -i "s/ADMIN_EMAIL=.*/ADMIN_EMAIL=${ADMIN_EMAIL}/" "$ENV_FILE"
    fi
    
    if [[ -n "${PROFILES:-}" ]]; then
        sed -i "s/COMPOSE_PROFILES=.*/COMPOSE_PROFILES=${PROFILES}/" "$ENV_FILE"
    fi
    
    # Setup components
    generate_omni_uuid
    setup_ssl
    generate_gpg_key
    setup_registry
    
    log "Bastion-Omni setup completed!"
    info "Run '$0 --start' to start all services"
}

# Main execution
if [[ $# -eq 0 ]]; then
    main_setup
else
    parse_args "$@"
fi
