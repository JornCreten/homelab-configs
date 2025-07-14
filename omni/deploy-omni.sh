#!/bin/bash

# Omni Self-Hosted Deployment Script for AlmaLinux
# This script deploys all necessary packages for Omni on an AlmaLinux machine
# Usage: ./deploy-omni.sh [OPTIONS]
# 
# Prerequisites:
# - AlmaLinux machine with sudo access
# - Internet connectivity
# - Domain name for SSL certificates

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration variables - modify these as needed
OMNI_VERSION="${OMNI_VERSION:-0.41.0}"
DOMAIN_NAME="${DOMAIN_NAME:-}"
WG_IP="${WG_IP:-10.10.1.100}"
ADMIN_EMAIL="${ADMIN_EMAIL:-}"
AUTH0_CLIENT_ID="${AUTH0_CLIENT_ID:-}"
AUTH0_DOMAIN="${AUTH0_DOMAIN:-}"
CERT_EMAIL="${CERT_EMAIL:-}"
DNS_PROVIDER="${DNS_PROVIDER:-digitalocean}"

# Default values
SKIP_DOCKER_INSTALL="${SKIP_DOCKER_INSTALL:-false}"
SKIP_CERT_GENERATION="${SKIP_CERT_GENERATION:-false}"
INSTALL_DIR="/opt/omni"

# Logging function
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
Omni Self-Hosted Deployment Script

Usage: $0 [OPTIONS]

Options:
    -d, --domain DOMAIN          Domain name for Omni (required)
    -e, --email EMAIL           Admin email address (required)
    -a, --auth0-client CLIENT   Auth0 client ID (required)
    -A, --auth0-domain DOMAIN   Auth0 domain (required)
    -c, --cert-email EMAIL      Email for SSL certificate generation
    -p, --dns-provider PROVIDER DNS provider for certbot (default: digitalocean)
    -v, --version VERSION       Omni version (default: $OMNI_VERSION)
    -w, --wireguard-ip IP       WireGuard IP (default: $WG_IP)
    -i, --install-dir DIR       Installation directory (default: $INSTALL_DIR)
    --skip-docker               Skip Docker installation
    --skip-certs                Skip SSL certificate generation
    -h, --help                  Show this help message

Environment Variables:
    DOMAIN_NAME                 Domain name for Omni
    ADMIN_EMAIL                 Admin email address
    AUTH0_CLIENT_ID            Auth0 client ID
    AUTH0_DOMAIN               Auth0 domain
    CERT_EMAIL                 Email for SSL certificates
    DNS_PROVIDER               DNS provider for certbot
    OMNI_VERSION               Omni version
    WG_IP                      WireGuard IP
    SKIP_DOCKER_INSTALL        Skip Docker installation (true/false)
    SKIP_CERT_GENERATION       Skip SSL certificate generation (true/false)

Examples:
    $0 --domain omni.example.com --email admin@example.com \\
       --auth0-client abc123 --auth0-domain dev-xyz.us.auth0.com

    DOMAIN_NAME=omni.example.com ADMIN_EMAIL=admin@example.com $0

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
            -a|--auth0-client)
                AUTH0_CLIENT_ID="$2"
                shift 2
                ;;
            -A|--auth0-domain)
                AUTH0_DOMAIN="$2"
                shift 2
                ;;
            -c|--cert-email)
                CERT_EMAIL="$2"
                shift 2
                ;;
            -p|--dns-provider)
                DNS_PROVIDER="$2"
                shift 2
                ;;
            -v|--version)
                OMNI_VERSION="$2"
                shift 2
                ;;
            -w|--wireguard-ip)
                WG_IP="$2"
                shift 2
                ;;
            -i|--install-dir)
                INSTALL_DIR="$2"
                shift 2
                ;;
            --skip-docker)
                SKIP_DOCKER_INSTALL="true"
                shift
                ;;
            --skip-certs)
                SKIP_CERT_GENERATION="true"
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

# Validate required parameters
validate_config() {
    local missing_params=()
    
    if [[ -z "$DOMAIN_NAME" ]]; then
        missing_params+=("DOMAIN_NAME")
    fi
    
    if [[ -z "$ADMIN_EMAIL" ]]; then
        missing_params+=("ADMIN_EMAIL")
    fi
    
    if [[ -z "$AUTH0_CLIENT_ID" ]]; then
        missing_params+=("AUTH0_CLIENT_ID")
    fi
    
    if [[ -z "$AUTH0_DOMAIN" ]]; then
        missing_params+=("AUTH0_DOMAIN")
    fi
    
    if [[ ${#missing_params[@]} -gt 0 ]]; then
        error "Missing required parameters: ${missing_params[*]}\nRun '$0 --help' for usage information."
    fi
    
    # Set default cert email if not provided
    if [[ -z "$CERT_EMAIL" ]]; then
        CERT_EMAIL="$ADMIN_EMAIL"
    fi
}

# Check if running as root
check_privileges() {
    if [[ $EUID -eq 0 ]]; then
        error "This script should not be run as root. Please run as a regular user with sudo privileges."
    fi
    
    # Check if user has sudo privileges
    if ! sudo -n true 2>/dev/null; then
        error "This script requires sudo privileges. Please ensure your user can run sudo commands."
    fi
}

# Update system packages
update_system() {
    log "Updating system packages..."
    sudo dnf update -y
    sudo dnf install -y curl wget gnupg2 ca-certificates epel-release
    # Install additional tools commonly needed
    sudo dnf install -y git unzip tar which
}

# Install Docker
install_docker() {
    if [[ "$SKIP_DOCKER_INSTALL" == "true" ]]; then
        log "Skipping Docker installation as requested"
        return 0
    fi
    
    log "Installing Docker..."
    
    # Check if Docker is already installed
    if command -v docker &> /dev/null; then
        warn "Docker is already installed. Skipping installation."
        return 0
    fi
    
    # Remove old versions
    sudo dnf remove -y docker docker-client docker-client-latest docker-common \
        docker-latest docker-latest-logrotate docker-logrotate docker-engine \
        podman runc 2>/dev/null || true
    
    # Add Docker's official repository
    sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    
    # Install Docker Engine, containerd, and Docker Compose
    sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Add current user to docker group
    sudo usermod -aG docker $USER
    
    # Start and enable Docker
    sudo systemctl start docker
    sudo systemctl enable docker
    
    log "Docker installation completed"
    info "Note: You may need to log out and back in for Docker group membership to take effect"
}

# Install and configure certbot for SSL certificates
install_certbot() {
    if [[ "$SKIP_CERT_GENERATION" == "true" ]]; then
        log "Skipping SSL certificate generation as requested"
        return 0
    fi
    
    log "Installing certbot for SSL certificate generation..."
    
    # Install snapd if not present
    if ! command -v snap &> /dev/null; then
        sudo dnf install -y snapd
        sudo systemctl enable --now snapd.socket
        sudo ln -sf /var/lib/snapd/snap /snap 2>/dev/null || true
        # Add snap to PATH
        export PATH="$PATH:/var/lib/snapd/snap/bin"
        echo 'export PATH="$PATH:/var/lib/snapd/snap/bin"' >> ~/.bashrc
    fi
    
    # Install certbot
    sudo snap install --classic certbot
    sudo snap set certbot trust-plugin-with-root=ok
    
    # Install DNS provider plugin
    case "$DNS_PROVIDER" in
        digitalocean)
            sudo snap install certbot-dns-digitalocean
            ;;
        route53)
            sudo snap install certbot-dns-route53
            ;;
        cloudflare)
            sudo snap install certbot-dns-cloudflare
            ;;
        *)
            warn "DNS provider '$DNS_PROVIDER' may not be supported. Please install the appropriate certbot plugin manually."
            ;;
    esac
    
    # Create symlink for certbot
    sudo ln -sf /var/lib/snapd/snap/bin/certbot /usr/bin/certbot 2>/dev/null || true
    
    log "Certbot installation completed"
}

# Generate GPG key for etcd encryption
generate_gpg_key() {
    log "Generating GPG key for etcd encryption..."
    
    # Create GPG directory if it doesn't exist
    mkdir -p ~/.gnupg
    chmod 700 ~/.gnupg
    
    # Check if key already exists
    if gpg --list-secret-keys | grep -q "Omni (Used for etcd data encryption)"; then
        warn "GPG key for Omni already exists. Skipping generation."
        return 0
    fi
    
    # Generate GPG key
    gpg --batch --gen-key <<EOF
%no-protection
Key-Type: RSA
Key-Length: 4096
Key-Usage: cert
Name-Real: Omni (Used for etcd data encryption)
Name-Email: $ADMIN_EMAIL
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
    gpg --export-secret-key --armor "$ADMIN_EMAIL" > "$INSTALL_DIR/omni.asc"
    
    log "GPG key generated and exported to $INSTALL_DIR/omni.asc"
}

# Create installation directory and set up environment
setup_environment() {
    log "Setting up Omni environment..."
    
    # Create installation directory
    sudo mkdir -p "$INSTALL_DIR"
    sudo chown $USER:$USER "$INSTALL_DIR"
    cd "$INSTALL_DIR"
    
    # Generate UUID for account
    local account_uuid=$(uuidgen)
    
    # Export environment variables
    cat > omni-vars.env << EOF
export OMNI_VERSION=$OMNI_VERSION
export OMNI_ACCOUNT_UUID=$account_uuid
export OMNI_DOMAIN_NAME=$DOMAIN_NAME
export OMNI_WG_IP=$WG_IP
export OMNI_ADMIN_EMAIL=$ADMIN_EMAIL
export AUTH0_CLIENT_ID=$AUTH0_CLIENT_ID
export AUTH0_DOMAIN=$AUTH0_DOMAIN
EOF
    
    # Source the variables
    source omni-vars.env
    
    log "Environment variables configured"
}

# Download Omni deployment assets
download_assets() {
    log "Downloading Omni deployment assets..."
    
    cd "$INSTALL_DIR"
    
    # Source environment variables
    source omni-vars.env
    
    # Download environment template
    curl -sSL "https://raw.githubusercontent.com/siderolabs/omni/v${OMNI_VERSION}/deploy/env.template" \
        | envsubst > omni.env
    
    # Download docker-compose file
    curl -sSL "https://raw.githubusercontent.com/siderolabs/omni/v${OMNI_VERSION}/deploy/compose.yaml" \
        -o compose.yaml
    
    log "Omni assets downloaded successfully"
}

# Display SSL certificate generation instructions
show_ssl_instructions() {
    if [[ "$SKIP_CERT_GENERATION" == "true" ]]; then
        return 0
    fi
    
    cat << EOF

${YELLOW}===============================================================================${NC}
${YELLOW}SSL CERTIFICATE GENERATION${NC}
${YELLOW}===============================================================================${NC}

You need to generate SSL certificates for your domain: ${BLUE}$DOMAIN_NAME${NC}

1. Create a credentials file for your DNS provider:
   ${GREEN}nano ~/dns-credentials.ini${NC}

2. For DigitalOcean, the file should contain:
   ${BLUE}dns_digitalocean_token = your_api_token_here${NC}

3. Secure the credentials file:
   ${GREEN}chmod 600 ~/dns-credentials.ini${NC}

4. Generate the certificate:
   ${GREEN}sudo certbot certonly --dns-$DNS_PROVIDER \\
     --dns-$DNS_PROVIDER-credentials ~/dns-credentials.ini \\
     -d $DOMAIN_NAME \\
     --email $CERT_EMAIL \\
     --agree-tos \\
     --non-interactive${NC}

5. The certificates will be available at:
   ${BLUE}/etc/letsencrypt/live/$DOMAIN_NAME/${NC}

${YELLOW}===============================================================================${NC}

EOF
}

# Display deployment instructions
show_deployment_instructions() {
    cat << EOF

${GREEN}===============================================================================${NC}
${GREEN}OMNI DEPLOYMENT READY${NC}
${GREEN}===============================================================================${NC}

Installation completed successfully! Next steps:

1. ${YELLOW}Configure firewall (AlmaLinux specific):${NC}
   ${BLUE}sudo systemctl start firewalld${NC}
   ${BLUE}sudo firewall-cmd --permanent --add-service=http${NC}
   ${BLUE}sudo firewall-cmd --permanent --add-service=https${NC}
   ${BLUE}sudo firewall-cmd --permanent --add-port=51820/udp${NC}
   ${BLUE}sudo firewall-cmd --reload${NC}

2. ${YELLOW}Review the configuration:${NC}
   ${BLUE}cd $INSTALL_DIR${NC}
   ${BLUE}cat omni.env${NC}

3. ${YELLOW}Source environment variables:${NC}
   ${BLUE}source omni-vars.env${NC}

4. ${YELLOW}Start Omni services:${NC}
   ${BLUE}docker compose --env-file omni.env up -d${NC}

5. ${YELLOW}Check service status:${NC}
   ${BLUE}docker compose --env-file omni.env ps${NC}

6. ${YELLOW}View logs:${NC}
   ${BLUE}docker compose --env-file omni.env logs -f${NC}

7. ${YELLOW}Access Omni at:${NC}
   ${BLUE}https://$DOMAIN_NAME${NC}

${GREEN}Files created:${NC}
- $INSTALL_DIR/omni.env (environment configuration)
- $INSTALL_DIR/compose.yaml (docker-compose file)
- $INSTALL_DIR/omni-vars.env (environment variables)
- $INSTALL_DIR/omni.asc (GPG key for etcd encryption)

${YELLOW}Important Notes for AlmaLinux:${NC}
- Ensure your domain DNS points to this server
- SSL certificates must be properly configured
- Firewall should allow ports 80, 443, and your WireGuard port
- SELinux may need configuration for Docker containers
- If you added your user to the docker group, you may need to log out and back in

${GREEN}===============================================================================${NC}

EOF
}

# Main execution
main() {
    log "Starting Omni self-hosted deployment..."
    
    parse_args "$@"
    validate_config
    check_privileges
    
    update_system
    install_docker
    install_certbot
    setup_environment
    generate_gpg_key
    download_assets
    
    show_ssl_instructions
    show_deployment_instructions
    
    log "Omni deployment script completed successfully!"
}

# Run main function with all arguments
main "$@"
