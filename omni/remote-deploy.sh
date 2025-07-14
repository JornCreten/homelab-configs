#!/bin/bash

# Remote Omni Deployment Script for AlmaLinux
# This script deploys Omni to remote AlmaLinux machines via SSH
# Usage: ./remote-deploy.sh [OPTIONS] HOST1 [HOST2 ...]

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
SSH_USER="${SSH_USER:-}"
SSH_PORT="${SSH_PORT:-22}"
SSH_KEY="${SSH_KEY:-}"
CONFIG_FILE="${CONFIG_FILE:-omni-config.env}"
SCRIPT_NAME="deploy-omni.sh"
REMOTE_DIR="/tmp/omni-deploy"

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
Remote Omni Deployment Script

Usage: $0 [OPTIONS] HOST1 [HOST2 ...]

Options:
    -u, --user USER         SSH username (default: current user)
    -p, --port PORT         SSH port (default: 22)
    -k, --key KEY_FILE      SSH private key file
    -c, --config CONFIG     Configuration file (default: omni-config.env)
    -h, --help              Show this help message

Environment Variables:
    SSH_USER                SSH username
    SSH_PORT                SSH port
    SSH_KEY                 SSH private key file
    CONFIG_FILE             Configuration file path

Examples:
    # Deploy to single host
    $0 server1.example.com

    # Deploy to multiple hosts with specific user
    $0 -u ubuntu server1.example.com server2.example.com

    # Deploy with custom SSH key and config
    $0 -k ~/.ssh/omni-key -c production-config.env server.example.com

    # Using environment variables
    SSH_USER=ubuntu SSH_KEY=~/.ssh/mykey $0 server1.example.com

Prerequisites:
    1. Copy omni-config.env.template to omni-config.env and customize
    2. Ensure SSH access to target hosts
    3. Target hosts should be AlmaLinux with sudo access

EOF
}

# Parse command line arguments
parse_args() {
    HOSTS=()
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -u|--user)
                SSH_USER="$2"
                shift 2
                ;;
            -p|--port)
                SSH_PORT="$2"
                shift 2
                ;;
            -k|--key)
                SSH_KEY="$2"
                shift 2
                ;;
            -c|--config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -*)
                error "Unknown option $1"
                ;;
            *)
                HOSTS+=("$1")
                shift
                ;;
        esac
    done
    
    if [[ ${#HOSTS[@]} -eq 0 ]]; then
        error "No hosts specified. Run '$0 --help' for usage information."
    fi
}

# Validate prerequisites
validate_prerequisites() {
    # Check if deployment script exists
    if [[ ! -f "$SCRIPT_NAME" ]]; then
        error "Deployment script '$SCRIPT_NAME' not found in current directory"
    fi
    
    # Check if config file exists
    if [[ ! -f "$CONFIG_FILE" ]]; then
        error "Configuration file '$CONFIG_FILE' not found. Copy and customize omni-config.env.template"
    fi
    
    # Validate config file
    source "$CONFIG_FILE"
    
    local missing_params=()
    
    if [[ -z "${DOMAIN_NAME:-}" ]]; then
        missing_params+=("DOMAIN_NAME")
    fi
    
    if [[ -z "${ADMIN_EMAIL:-}" ]]; then
        missing_params+=("ADMIN_EMAIL")
    fi
    
    if [[ -z "${AUTH0_CLIENT_ID:-}" ]]; then
        missing_params+=("AUTH0_CLIENT_ID")
    fi
    
    if [[ -z "${AUTH0_DOMAIN:-}" ]]; then
        missing_params+=("AUTH0_DOMAIN")
    fi
    
    if [[ ${#missing_params[@]} -gt 0 ]]; then
        error "Missing required parameters in $CONFIG_FILE: ${missing_params[*]}"
    fi
    
    log "Configuration validated successfully"
}

# Build SSH command with options
build_ssh_cmd() {
    local host="$1"
    local ssh_cmd="ssh"
    
    if [[ -n "$SSH_PORT" && "$SSH_PORT" != "22" ]]; then
        ssh_cmd="$ssh_cmd -p $SSH_PORT"
    fi
    
    if [[ -n "$SSH_KEY" ]]; then
        ssh_cmd="$ssh_cmd -i $SSH_KEY"
    fi
    
    if [[ -n "$SSH_USER" ]]; then
        ssh_cmd="$ssh_cmd ${SSH_USER}@${host}"
    else
        ssh_cmd="$ssh_cmd $host"
    fi
    
    echo "$ssh_cmd"
}

# Build SCP command with options
build_scp_cmd() {
    local src="$1"
    local host="$2"
    local dest="$3"
    local scp_cmd="scp"
    
    if [[ -n "$SSH_PORT" && "$SSH_PORT" != "22" ]]; then
        scp_cmd="$scp_cmd -P $SSH_PORT"
    fi
    
    if [[ -n "$SSH_KEY" ]]; then
        scp_cmd="$scp_cmd -i $SSH_KEY"
    fi
    
    if [[ -n "$SSH_USER" ]]; then
        scp_cmd="$scp_cmd $src ${SSH_USER}@${host}:${dest}"
    else
        scp_cmd="$scp_cmd $src ${host}:${dest}"
    fi
    
    echo "$scp_cmd"
}

# Test SSH connectivity
test_ssh_connection() {
    local host="$1"
    local ssh_cmd=$(build_ssh_cmd "$host")
    
    info "Testing SSH connection to $host..."
    
    if $ssh_cmd "echo 'SSH connection successful'" >/dev/null 2>&1; then
        log "SSH connection to $host successful"
        return 0
    else
        error "Failed to connect to $host via SSH"
    fi
}

# Deploy to a single host
deploy_to_host() {
    local host="$1"
    
    log "Starting deployment to $host..."
    
    # Test SSH connection
    test_ssh_connection "$host"
    
    # Create remote directory
    local ssh_cmd=$(build_ssh_cmd "$host")
    $ssh_cmd "mkdir -p $REMOTE_DIR"
    
    # Copy deployment script
    info "Copying deployment script to $host..."
    local scp_cmd=$(build_scp_cmd "$SCRIPT_NAME" "$host" "$REMOTE_DIR/")
    $scp_cmd
    
    # Copy configuration
    info "Copying configuration to $host..."
    scp_cmd=$(build_scp_cmd "$CONFIG_FILE" "$host" "$REMOTE_DIR/omni-config.env")
    $scp_cmd
    
    # Make script executable and run deployment
    info "Running deployment on $host..."
    $ssh_cmd "cd $REMOTE_DIR && chmod +x $SCRIPT_NAME && source omni-config.env && ./$SCRIPT_NAME"
    
    # Check if deployment was successful
    if $ssh_cmd "docker --version && test -d /opt/omni" >/dev/null 2>&1; then
        log "Deployment to $host completed successfully!"
    else
        warn "Deployment to $host may have failed. Please check manually."
    fi
    
    # Clean up
    info "Cleaning up temporary files on $host..."
    $ssh_cmd "rm -rf $REMOTE_DIR" || warn "Failed to clean up temporary files on $host"
}

# Deploy to all hosts
deploy_to_all_hosts() {
    local total_hosts=${#HOSTS[@]}
    local success_count=0
    local failed_hosts=()
    
    log "Starting deployment to $total_hosts host(s)..."
    
    for host in "${HOSTS[@]}"; do
        echo
        log "=== Deploying to $host ==="
        
        if deploy_to_host "$host"; then
            ((success_count++))
        else
            failed_hosts+=("$host")
        fi
        
        echo
    done
    
    # Summary
    echo
    log "=== Deployment Summary ==="
    log "Total hosts: $total_hosts"
    log "Successful: $success_count"
    log "Failed: $((total_hosts - success_count))"
    
    if [[ ${#failed_hosts[@]} -gt 0 ]]; then
        warn "Failed deployments: ${failed_hosts[*]}"
        exit 1
    else
        log "All deployments completed successfully!"
    fi
}

# Main execution
main() {
    log "Starting remote Omni deployment..."
    
    parse_args "$@"
    validate_prerequisites
    deploy_to_all_hosts
    
    log "Remote deployment script completed!"
}

# Run main function with all arguments
main "$@"
