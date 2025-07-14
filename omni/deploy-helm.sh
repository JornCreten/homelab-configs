#!/bin/bash

# Omni Helm Deployment Script
# Deploy Omni and optional components using Helm charts

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values
DEPLOYMENT_TYPE="helm"  # or "compose"
NAMESPACE="omni"
DOMAIN="omni.example.com"
PROFILE="core"  # core, auth, monitoring, complete
HELM_RELEASE="omni"
DRY_RUN=false
UPGRADE=false
UNINSTALL=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} ✓ $1"
}

log_warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} ⚠ $1"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} ✗ $1" >&2
}

show_help() {
    cat << EOF
Omni Helm Deployment Script

Usage: $0 [OPTIONS]

Options:
    -t, --type TYPE         Deployment type: helm, compose (default: helm)
    -n, --namespace NS      Kubernetes namespace (default: omni)
    -d, --domain DOMAIN     Domain name (default: omni.example.com)
    -p, --profile PROFILE   Deployment profile (default: core)
    -r, --release NAME      Helm release name (default: omni)
    --dry-run              Show what would be deployed without deploying
    --upgrade              Upgrade existing deployment
    --uninstall            Uninstall deployment
    -h, --help             Show this help message

Deployment Profiles:
    core                   Essential services only (Omni, Nginx, Redis)
    auth                   Core + Authentication (Keycloak, PostgreSQL)
    monitoring             Core + Monitoring (Prometheus, Grafana, Loki)
    dns                    Core + DNS services (Pi-hole)
    registry               Core + Docker registry
    bootstrap              Core + Network bootstrap (DHCP, TFTP, PXE, NTP)
    complete               All services (everything)

Examples:
    # Deploy core services with Helm
    $0 --profile core --domain omni.example.com

    # Deploy complete stack
    $0 --profile complete --domain omni.example.com

    # Deploy with Docker Compose (core only)
    $0 --type compose --profile core --domain omni.example.com

    # Upgrade existing deployment
    $0 --upgrade --profile complete

    # Dry run to see what would be deployed
    $0 --dry-run --profile complete

    # Uninstall deployment
    $0 --uninstall

EOF
}

check_prerequisites() {
    log "Checking prerequisites..."
    
    if [[ "$DEPLOYMENT_TYPE" == "helm" ]]; then
        if ! command -v helm &> /dev/null; then
            log_error "Helm is required but not installed"
            exit 1
        fi
        
        if ! command -v kubectl &> /dev/null; then
            log_error "kubectl is required but not installed"
            exit 1
        fi
        
        # Check if kubectl can connect to cluster
        if ! kubectl cluster-info &> /dev/null; then
            log_error "Cannot connect to Kubernetes cluster"
            exit 1
        fi
    elif [[ "$DEPLOYMENT_TYPE" == "compose" ]]; then
        if ! command -v docker &> /dev/null; then
            log_error "Docker is required but not installed"
            exit 1
        fi
        
        if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
            log_error "Docker Compose is required but not installed"
            exit 1
        fi
    fi
    
    log_success "Prerequisites check passed"
}

create_namespace() {
    if [[ "$DEPLOYMENT_TYPE" == "helm" ]]; then
        log "Creating namespace: $NAMESPACE"
        kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
        log_success "Namespace created/updated"
    fi
}

deploy_with_helm() {
    local profile="$1"
    local common_args=(
        --namespace "$NAMESPACE"
        --set global.domain="$DOMAIN"
        --set domain="$DOMAIN"
    )
    
    if [[ "$DRY_RUN" == "true" ]]; then
        common_args+=("--dry-run")
    fi
    
    case "$profile" in
        "core")
            deploy_helm_chart "omni-core" "${common_args[@]}"
            ;;
        "auth")
            deploy_helm_chart "omni-core" "${common_args[@]}"
            deploy_helm_chart "omni-auth" "${common_args[@]}"
            ;;
        "monitoring")
            deploy_helm_chart "omni-core" "${common_args[@]}"
            deploy_helm_chart "omni-monitoring" "${common_args[@]}"
            ;;
        "dns")
            deploy_helm_chart "omni-core" "${common_args[@]}"
            # TODO: Add omni-dns chart
            log_warn "DNS chart not yet implemented"
            ;;
        "registry")
            deploy_helm_chart "omni-core" "${common_args[@]}"
            # TODO: Add omni-registry chart
            log_warn "Registry chart not yet implemented"
            ;;
        "bootstrap")
            deploy_helm_chart "omni-core" "${common_args[@]}"
            # TODO: Add omni-bootstrap chart
            log_warn "Bootstrap chart not yet implemented"
            ;;
        "complete")
            deploy_helm_chart "omni-core" "${common_args[@]}"
            deploy_helm_chart "omni-auth" "${common_args[@]}"
            deploy_helm_chart "omni-monitoring" "${common_args[@]}"
            # TODO: Add other charts
            log_warn "Some charts not yet implemented (DNS, Registry, Bootstrap)"
            ;;
        *)
            log_error "Unknown profile: $profile"
            exit 1
            ;;
    esac
}

deploy_helm_chart() {
    local chart_name="$1"
    shift
    local args=("$@")
    
    local chart_path="$SCRIPT_DIR/helm/$chart_name"
    
    if [[ ! -d "$chart_path" ]]; then
        log_error "Chart not found: $chart_path"
        return 1
    fi
    
    log "Deploying Helm chart: $chart_name"
    
    if [[ "$UPGRADE" == "true" ]]; then
        helm upgrade --install "${HELM_RELEASE}-${chart_name##*-}" "$chart_path" "${args[@]}"
    else
        helm install "${HELM_RELEASE}-${chart_name##*-}" "$chart_path" "${args[@]}"
    fi
    
    log_success "Chart deployed: $chart_name"
}

deploy_with_compose() {
    local profile="$1"
    
    log "Deploying with Docker Compose (profile: $profile)"
    
    case "$profile" in
        "core")
            local compose_file="docker-compose.core.yml"
            ;;
        *)
            log_error "Docker Compose only supports 'core' profile"
            log_error "Use 'helm' deployment type for other profiles"
            exit 1
            ;;
    esac
    
    # Create environment file
    local env_file="$SCRIPT_DIR/.env.core"
    create_compose_env_file "$env_file"
    
    # Deploy with compose
    local compose_cmd="docker-compose"
    if docker compose version &> /dev/null; then
        compose_cmd="docker compose"
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "Dry run - would execute:"
        echo "$compose_cmd -f $SCRIPT_DIR/$compose_file --env-file $env_file up -d"
    else
        cd "$SCRIPT_DIR"
        $compose_cmd -f "$compose_file" --env-file "$env_file" up -d
        log_success "Docker Compose deployment completed"
    fi
}

create_compose_env_file() {
    local env_file="$1"
    
    log "Creating environment file: $env_file"
    
    # Generate required values if they don't exist
    local account_uuid
    account_uuid=$(uuidgen 2>/dev/null || python3 -c "import uuid; print(uuid.uuid4())" 2>/dev/null || echo "00000000-0000-0000-0000-000000000000")
    
    local redis_password
    redis_password=$(openssl rand -base64 32 2>/dev/null || echo "default-redis-password")
    
    cat > "$env_file" << EOF
# Omni Core Environment Configuration
DOMAIN_NAME=$DOMAIN
OMNI_VERSION=0.41.0
OMNI_ACCOUNT_UUID=$account_uuid
OMNI_NAME=omni
WG_IP=10.10.1.100

# Authentication (configure as needed)
SAML_URL=
AUTH0_CLIENT_ID=
AUTH0_DOMAIN=

# Redis
REDIS_PASSWORD=$redis_password

# Timezone
TZ=UTC
EOF
    
    log_success "Environment file created"
}

uninstall_deployment() {
    if [[ "$DEPLOYMENT_TYPE" == "helm" ]]; then
        log "Uninstalling Helm releases..."
        
        # List all releases with our prefix
        local releases
        releases=$(helm list -n "$NAMESPACE" -q | grep "^$HELM_RELEASE-" || true)
        
        if [[ -n "$releases" ]]; then
            for release in $releases; do
                log "Uninstalling release: $release"
                helm uninstall "$release" -n "$NAMESPACE"
            done
            log_success "Helm releases uninstalled"
        else
            log_warn "No Helm releases found to uninstall"
        fi
        
        # Optionally delete namespace
        read -p "Delete namespace $NAMESPACE? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            kubectl delete namespace "$NAMESPACE"
            log_success "Namespace deleted"
        fi
        
    elif [[ "$DEPLOYMENT_TYPE" == "compose" ]]; then
        log "Stopping Docker Compose services..."
        
        cd "$SCRIPT_DIR"
        local compose_cmd="docker-compose"
        if docker compose version &> /dev/null; then
            compose_cmd="docker compose"
        fi
        
        $compose_cmd -f docker-compose.core.yml down -v
        log_success "Docker Compose services stopped"
    fi
}

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -t|--type)
                DEPLOYMENT_TYPE="$2"
                shift 2
                ;;
            -n|--namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            -d|--domain)
                DOMAIN="$2"
                shift 2
                ;;
            -p|--profile)
                PROFILE="$2"
                shift 2
                ;;
            -r|--release)
                HELM_RELEASE="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --upgrade)
                UPGRADE=true
                shift
                ;;
            --uninstall)
                UNINSTALL=true
                shift
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
    
    # Validate deployment type
    if [[ "$DEPLOYMENT_TYPE" != "helm" && "$DEPLOYMENT_TYPE" != "compose" ]]; then
        log_error "Invalid deployment type: $DEPLOYMENT_TYPE"
        echo "Valid types: helm, compose"
        exit 1
    fi
    
    log "Omni Deployment Script"
    log "======================"
    log "Type: $DEPLOYMENT_TYPE"
    log "Profile: $PROFILE"
    log "Domain: $DOMAIN"
    log "Namespace: $NAMESPACE"
    log "Dry run: $DRY_RUN"
    echo
    
    check_prerequisites
    
    if [[ "$UNINSTALL" == "true" ]]; then
        uninstall_deployment
        exit 0
    fi
    
    if [[ "$DEPLOYMENT_TYPE" == "helm" ]]; then
        create_namespace
        deploy_with_helm "$PROFILE"
    elif [[ "$DEPLOYMENT_TYPE" == "compose" ]]; then
        deploy_with_compose "$PROFILE"
    fi
    
    log_success "Deployment completed successfully!"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        echo
        log "Next steps:"
        echo "1. Check deployment status:"
        if [[ "$DEPLOYMENT_TYPE" == "helm" ]]; then
            echo "   kubectl get pods -n $NAMESPACE"
            echo "   helm list -n $NAMESPACE"
        else
            echo "   docker-compose -f docker-compose.core.yml ps"
        fi
        echo "2. Access Omni at: https://$DOMAIN"
        echo "3. Configure authentication and SSL certificates as needed"
    fi
}

main "$@"
