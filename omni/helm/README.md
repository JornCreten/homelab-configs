# Helm Charts for Omni Deployment

This directory contains modular Helm charts for deploying Omni and its optional dependencies.

## Chart Structure

### Core Charts
- **`omni-core/`** - Essential Omni components (Omni, Nginx, Redis)
- **`omni-auth/`** - Authentication services (Keycloak, PostgreSQL)

### Optional Charts
- **`omni-monitoring/`** - Monitoring stack (Prometheus, Grafana, Loki)
- **`omni-dns/`** - DNS services (Pi-hole)
- **`omni-registry/`** - Docker registry
- **`omni-bootstrap/`** - Network bootstrap services (DHCP, TFTP, PXE, NTP)
- **`omni-security/`** - Security services (certificate management, firewalls)

## Quick Deploy

### Core Deployment (Minimal)
```bash
# Deploy core Omni with external authentication
helm install omni-core ./helm/omni-core \
  --set domain=omni.example.com \
  --set auth.external.enabled=true \
  --set auth.external.samlUrl=https://external-keycloak.com/realms/omni/protocol/saml
```

### Full Self-Contained Deployment
```bash
# Deploy everything with dependencies
./deploy-helm.sh --profile complete --domain omni.example.com
```

### Modular Deployment
```bash
# Deploy core + specific components
helm install omni-core ./helm/omni-core --set domain=omni.example.com
helm install omni-auth ./helm/omni-auth --set domain=omni.example.com
helm install omni-monitoring ./helm/omni-monitoring --set domain=omni.example.com
```

## Chart Dependencies

```
omni-core (essential)
├── nginx (reverse proxy)
├── omni (main service)
└── redis (caching)

omni-auth (authentication)
├── keycloak (SAML provider)
└── postgresql (auth database)

omni-monitoring (observability)
├── prometheus (metrics)
├── grafana (dashboards)
└── loki (logs)

omni-dns (DNS services)
└── pihole (DNS + ad-blocking)

omni-registry (container registry)
└── docker-registry (private registry)

omni-bootstrap (network services)
├── dhcp-server (DHCP)
├── tftp-server (TFTP)
├── http-boot (PXE boot)
└── ntp-server (time sync)

omni-security (security)
├── cert-manager (SSL certs)
└── fail2ban (intrusion prevention)
```

## Configuration

Each chart can be configured independently:

- **Values files**: `values.yaml` for each chart
- **Global values**: Shared configuration across charts
- **Environment-specific**: Override files for dev/staging/prod

## Management Scripts

- **`deploy-helm.sh`** - Deploy charts with profiles
- **`upgrade-helm.sh`** - Upgrade existing deployments
- **`cleanup-helm.sh`** - Remove charts and cleanup
