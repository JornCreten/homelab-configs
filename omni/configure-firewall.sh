#!/bin/bash

# AlmaLinux Firewall Configuration for Omni
# This script configures firewalld for Omni deployment
# Usage: ./configure-firewall.sh [OPTIONS]

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
WG_PORT="${WG_PORT:-51820}"
OMNI_PORT="${OMNI_PORT:-8080}"
ENABLE_SSH="${ENABLE_SSH:-true}"

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
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Help function
show_help() {
    cat << EOF
AlmaLinux Firewall Configuration for Omni

Usage: $0 [OPTIONS]

Options:
    -w, --wireguard-port PORT   WireGuard port (default: $WG_PORT)
    -o, --omni-port PORT        Omni internal port (default: $OMNI_PORT)
    --disable-ssh               Don't configure SSH access
    -h, --help                  Show this help message

This script configures firewalld to allow:
- HTTP (80/tcp) - for Let's Encrypt challenges
- HTTPS (443/tcp) - for Omni web interface
- SSH (22/tcp) - for remote access (optional)
- WireGuard (51820/udp) - for VPN connections
- Docker bridge network access

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -w|--wireguard-port)
                WG_PORT="$2"
                shift 2
                ;;
            -o|--omni-port)
                OMNI_PORT="$2"
                shift 2
                ;;
            --disable-ssh)
                ENABLE_SSH="false"
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                error "Unknown option $1"
                ;;
        esac
    done
}

# Check if running with proper privileges
check_privileges() {
    if ! sudo -n true 2>/dev/null; then
        error "This script requires sudo privileges. Please ensure your user can run sudo commands."
    fi
}

# Configure firewalld
configure_firewall() {
    log "Configuring firewalld for Omni..."
    
    # Start and enable firewalld
    sudo systemctl start firewalld
    sudo systemctl enable firewalld
    
    # Configure HTTP and HTTPS
    log "Allowing HTTP and HTTPS traffic..."
    sudo firewall-cmd --permanent --add-service=http
    sudo firewall-cmd --permanent --add-service=https
    
    # Configure SSH if enabled
    if [[ "$ENABLE_SSH" == "true" ]]; then
        log "Allowing SSH traffic..."
        sudo firewall-cmd --permanent --add-service=ssh
    fi
    
    # Configure WireGuard
    log "Allowing WireGuard traffic on port $WG_PORT/udp..."
    sudo firewall-cmd --permanent --add-port=$WG_PORT/udp
    
    # Allow Docker bridge network
    log "Configuring Docker bridge network access..."
    sudo firewall-cmd --permanent --zone=trusted --add-interface=docker0 2>/dev/null || true
    sudo firewall-cmd --permanent --zone=trusted --add-source=172.17.0.0/16
    
    # Allow container-to-container communication
    sudo firewall-cmd --permanent --add-masquerade
    
    # Reload firewall rules
    log "Reloading firewall rules..."
    sudo firewall-cmd --reload
    
    log "Firewall configuration completed successfully!"
}

# Display current configuration
show_current_config() {
    cat << EOF

${GREEN}===============================================================================${NC}
${GREEN}FIREWALL CONFIGURATION SUMMARY${NC}
${GREEN}===============================================================================${NC}

${YELLOW}Active Services:${NC}
$(sudo firewall-cmd --list-services)

${YELLOW}Open Ports:${NC}
$(sudo firewall-cmd --list-ports)

${YELLOW}Trusted Sources:${NC}
$(sudo firewall-cmd --zone=trusted --list-sources 2>/dev/null || echo "None")

${YELLOW}Masquerading:${NC}
$(sudo firewall-cmd --query-masquerade && echo "Enabled" || echo "Disabled")

${GREEN}===============================================================================${NC}

${BLUE}Verification Commands:${NC}
- Check firewall status: ${GREEN}sudo firewall-cmd --state${NC}
- List all rules: ${GREEN}sudo firewall-cmd --list-all${NC}
- Test port access: ${GREEN}sudo firewall-cmd --query-port=443/tcp${NC}

${YELLOW}Important Notes:${NC}
- Ensure your cloud provider security groups also allow these ports
- Test connectivity after configuration
- Consider restricting SSH access to specific IP ranges in production

${GREEN}===============================================================================${NC}

EOF
}

# Main execution
main() {
    log "Starting firewall configuration for Omni..."
    
    parse_args "$@"
    check_privileges
    configure_firewall
    show_current_config
    
    log "Firewall configuration completed!"
}

# Run main function with all arguments
main "$@"
