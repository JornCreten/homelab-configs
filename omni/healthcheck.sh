#!/bin/bash

# Bastion-Omni Health Check Script
# Verifies all services are running correctly

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env.local"

# Load environment variables
if [[ -f "$ENV_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$ENV_FILE"
else
    echo "Error: Environment file not found: $ENV_FILE"
    echo "Run setup-bastion.sh first to create configuration"
    exit 1
fi

# Default values
DOMAIN_NAME="${DOMAIN_NAME:-omni.example.com}"
TIMEOUT="${HEALTH_CHECK_TIMEOUT:-10}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
    local service="$1"
    local status="$2"
    local message="$3"
    
    case "$status" in
        "OK")
            echo -e "${service}: ${GREEN}✓ ${message}${NC}"
            ;;
        "WARN")
            echo -e "${service}: ${YELLOW}⚠ ${message}${NC}"
            ;;
        "FAIL")
            echo -e "${service}: ${RED}✗ ${message}${NC}"
            ;;
    esac
}

check_http_endpoint() {
    local name="$1"
    local url="$2"
    local expected_code="${3:-200}"
    
    if curl -s -o /dev/null -w "%{http_code}" --max-time "$TIMEOUT" "$url" | grep -q "$expected_code"; then
        print_status "$name" "OK" "Responding ($url)"
        return 0
    else
        print_status "$name" "FAIL" "Not responding ($url)"
        return 1
    fi
}

check_docker_service() {
    local service_name="$1"
    local container_name="$2"
    
    if docker ps --format "table {{.Names}}\t{{.Status}}" | grep -q "$container_name.*Up"; then
        print_status "$service_name" "OK" "Container running"
        return 0
    else
        print_status "$service_name" "FAIL" "Container not running"
        return 1
    fi
}

check_ssl_certificate() {
    local domain="$1"
    
    if echo | timeout "$TIMEOUT" openssl s_client -servername "$domain" -connect "$domain:443" 2>/dev/null | openssl x509 -noout -dates 2>/dev/null; then
        local expiry
        expiry=$(echo | timeout "$TIMEOUT" openssl s_client -servername "$domain" -connect "$domain:443" 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
        local days_until_expiry
        days_until_expiry=$(( ($(date -d "$expiry" +%s) - $(date +%s)) / 86400 ))
        
        if [[ $days_until_expiry -lt 30 ]]; then
            print_status "SSL Certificate" "WARN" "Expires in $days_until_expiry days"
        else
            print_status "SSL Certificate" "OK" "Valid, expires in $days_until_expiry days"
        fi
        return 0
    else
        print_status "SSL Certificate" "FAIL" "Certificate check failed"
        return 1
    fi
}

main() {
    echo "Bastion-Omni Health Check"
    echo "========================="
    echo "Domain: $DOMAIN_NAME"
    echo "Timeout: ${TIMEOUT}s"
    echo ""
    
    local failed_checks=0
    
    # Check Docker Compose services
    echo "Docker Services:"
    echo "---------------"
    
    # Core services
    check_docker_service "Nginx" "bastion-nginx" || ((failed_checks++))
    check_docker_service "Omni" "bastion-omni" || ((failed_checks++))
    check_docker_service "Redis" "bastion-redis" || ((failed_checks++))
    
    # Profile-based services
    if [[ "${COMPOSE_PROFILES:-}" =~ saml ]]; then
        check_docker_service "Keycloak" "bastion-keycloak" || ((failed_checks++))
        check_docker_service "PostgreSQL" "bastion-postgres" || ((failed_checks++))
    fi
    
    if [[ "${COMPOSE_PROFILES:-}" =~ monitoring ]]; then
        check_docker_service "Prometheus" "bastion-prometheus" || ((failed_checks++))
        check_docker_service "Grafana" "bastion-grafana" || ((failed_checks++))
        check_docker_service "Loki" "bastion-loki" || ((failed_checks++))
    fi
    
    if [[ "${COMPOSE_PROFILES:-}" =~ dns ]]; then
        check_docker_service "Pi-hole" "bastion-pihole" || ((failed_checks++))
    fi
    
    if [[ "${COMPOSE_PROFILES:-}" =~ registry ]]; then
        check_docker_service "Docker Registry" "bastion-registry" || ((failed_checks++))
    fi
    
    echo ""
    echo "HTTP Endpoints:"
    echo "---------------"
    
    # Check HTTP endpoints
    check_http_endpoint "Omni UI" "https://${DOMAIN_NAME}" || ((failed_checks++))
    check_http_endpoint "Nginx Status" "http://${DOMAIN_NAME}:8080/nginx_status" || ((failed_checks++))
    
    if [[ "${COMPOSE_PROFILES:-}" =~ saml ]]; then
        check_http_endpoint "Keycloak" "https://keycloak.${DOMAIN_NAME}" || ((failed_checks++))
    fi
    
    if [[ "${COMPOSE_PROFILES:-}" =~ monitoring ]]; then
        check_http_endpoint "Prometheus" "https://prometheus.${DOMAIN_NAME}" || ((failed_checks++))
        check_http_endpoint "Grafana" "https://grafana.${DOMAIN_NAME}" || ((failed_checks++))
    fi
    
    if [[ "${COMPOSE_PROFILES:-}" =~ dns ]]; then
        check_http_endpoint "Pi-hole Admin" "https://pihole.${DOMAIN_NAME}/admin" || ((failed_checks++))
    fi
    
    echo ""
    echo "SSL Certificate:"
    echo "----------------"
    check_ssl_certificate "$DOMAIN_NAME" || ((failed_checks++))
    
    echo ""
    echo "Summary:"
    echo "--------"
    
    if [[ $failed_checks -eq 0 ]]; then
        echo -e "${GREEN}✓ All health checks passed${NC}"
        exit 0
    else
        echo -e "${RED}✗ $failed_checks health check(s) failed${NC}"
        exit 1
    fi
}

# Show help
if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    echo "Bastion-Omni Health Check Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "    -h, --help              Show this help message"
    echo "    --timeout SECONDS       HTTP timeout in seconds (default: 10)"
    echo ""
    echo "Environment Variables:"
    echo "    DOMAIN_NAME            Domain name to check (from .env.local)"
    echo "    COMPOSE_PROFILES       Service profiles to check (from .env.local)"
    echo "    HEALTH_CHECK_TIMEOUT   Default timeout in seconds"
    echo ""
    echo "Examples:"
    echo "    $0                     # Run all health checks"
    echo "    $0 --timeout 30        # Use 30 second timeout"
    exit 0
fi

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

main "$@"
