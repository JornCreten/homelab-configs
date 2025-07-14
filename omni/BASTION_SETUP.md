# Bastion-Omni Host Setup Guide

This guide describes how to set up a complete "bastion-omni" host that includes Omni and all its dependencies to prevent bootstrapping issues.

## Overview

The bastion-omni deployment provides:

- **Omni**: Kubernetes management platform
- **Keycloak**: On-premises SAML identity provider
- **Nginx**: Reverse proxy and SSL termination
- **PostgreSQL**: Database for Keycloak
- **Redis**: Session storage and caching
- **Prometheus/Grafana**: Monitoring and observability
- **Pi-hole**: DNS services
- **Docker Registry**: Container image storage
- **PXE Boot Services**: TFTP, DHCP for network bootstrapping
- **NTP Server**: Time synchronization

## Quick Start

### 1. Prerequisites

- Linux server with Docker and Docker Compose
- Domain name with wildcard DNS pointing to the server
- SSL certificates (Let's Encrypt recommended)

### 2. Initial Setup

```bash
# Clone the configuration
git clone <your-repo> && cd omni

# Configure environment
cp .env.bastion .env.local
nano .env.local  # Edit your domain, email, and passwords

# Generate secure passwords
./setup-bastion.sh --generate-passwords

# Setup the environment
./setup-bastion.sh --domain omni.example.com --email admin@example.com
```

### 3. SSL Certificates

Generate SSL certificates using Let's Encrypt with DNS challenge:

```bash
# Install certbot
sudo snap install --classic certbot

# Generate wildcard certificate (DigitalOcean example)
certbot certonly --dns-digitalocean \
  --dns-digitalocean-credentials ~/.secrets/certbot/digitalocean.ini \
  -d omni.example.com \
  -d '*.omni.example.com'

# Copy certificates
cp /etc/letsencrypt/live/omni.example.com/fullchain.pem omni/tls.crt
cp /etc/letsencrypt/live/omni.example.com/privkey.pem omni/tls.key
```

### 4. Start Services

```bash
# Start with SAML and monitoring
./setup-bastion.sh --profiles saml,monitoring --start

# Check status
./setup-bastion.sh --status

# View logs
./setup-bastion.sh --logs omni
```

## Service Profiles

Enable different service combinations based on your needs:

### Core Profile (Always Enabled)
- Omni
- Nginx
- Redis

### Available Profiles

| Profile | Services | Description |
|---------|----------|-------------|
| `saml` | Keycloak, PostgreSQL | SAML authentication with Keycloak |
| `monitoring` | Prometheus, Grafana, Loki | Complete monitoring stack |
| `dns` | Pi-hole | DNS services and ad-blocking |
| `registry` | Docker Registry | Private container registry |
| `pxe` | TFTP, HTTP Boot Server | PXE boot services |
| `dhcp` | DHCP Server | Network DHCP services |
| `ntp` | NTP Server | Time synchronization |

### Profile Examples

```bash
# Minimal deployment (Omni + Auth0)
COMPOSE_PROFILES=""

# SAML authentication only
COMPOSE_PROFILES="saml"

# Full monitoring stack
COMPOSE_PROFILES="saml,monitoring,dns"

# Complete bootstrap environment
COMPOSE_PROFILES="saml,monitoring,dns,registry,pxe,dhcp,ntp"
```

## Configuration

### Environment Variables

Key variables in `.env.bastion`:

```bash
# Core
DOMAIN_NAME=omni.example.com
ADMIN_EMAIL=admin@example.com

# Authentication (choose one)
AUTH0_ENABLED=false
SAML_ENABLED=true
SAML_URL=https://keycloak.omni.example.com/realms/omni/protocol/saml

# Service profiles
COMPOSE_PROFILES=saml,monitoring,dns
```

### DNS Configuration

Set up DNS records for all services:

```
A       omni.example.com         -> SERVER_IP
CNAME   *.omni.example.com       -> omni.example.com
```

Required subdomains:
- `omni.example.com` - Main Omni interface
- `keycloak.omni.example.com` - Keycloak admin
- `traefik.omni.example.com` - Nginx status page
- `grafana.omni.example.com` - Grafana monitoring
- `prometheus.omni.example.com` - Prometheus metrics
- `pihole.omni.example.com` - Pi-hole admin
- `registry.omni.example.com` - Docker registry

## Authentication Setup

### Option 1: Auth0 (Cloud)

1. Set `AUTH0_ENABLED=true` in `.env.bastion`
2. Configure Auth0 application settings
3. Set `AUTH0_CLIENT_ID` and `AUTH0_DOMAIN`

### Option 2: Keycloak (On-premises)

1. Set `SAML_ENABLED=true` in `.env.bastion`
2. Enable SAML profile: `COMPOSE_PROFILES=saml`
3. Start services and configure Keycloak:

```bash
./setup-bastion.sh --start
./setup-bastion.sh --keycloak-setup
```

Follow the [KEYCLOAK_SETUP.md](./KEYCLOAK_SETUP.md) guide for detailed configuration.

## Operations

### Starting Services

```bash
# Start all configured services
./setup-bastion.sh --start

# Start specific profile
./setup-bastion.sh --profiles saml,monitoring --start
```

### Monitoring

```bash
# Check service status
./setup-bastion.sh --status

# View logs for all services
./setup-bastion.sh --logs

# View logs for specific service
./setup-bastion.sh --logs omni
./setup-bastion.sh --logs keycloak
```

### Stopping Services

```bash
# Stop all services
./setup-bastion.sh --stop

# Stop and remove volumes (DESTRUCTIVE)
docker-compose -f docker-compose.bastion.yml down -v
```

### Updates

```bash
# Update Omni version
sed -i 's/OMNI_VERSION=.*/OMNI_VERSION=0.42.0/' .env.bastion

# Pull new images
docker-compose -f docker-compose.bastion.yml pull

# Restart services
./setup-bastion.sh --stop
./setup-bastion.sh --start
```

## Storage and Backup

### Important Data Locations

| Service | Volume | Description |
|---------|--------|-------------|
| Omni | `omni_etcd` | Kubernetes cluster state |
| Keycloak | `keycloak_data` | User accounts and configuration |
| PostgreSQL | `postgres_data` | Database data |
| Prometheus | `prometheus_data` | Metrics data |
| Registry | `registry_data` | Container images |

### Backup Strategy

```bash
# Create backup directory
mkdir -p /backup/bastion-omni

# Backup volumes
docker run --rm -v omni_etcd:/data -v /backup/bastion-omni:/backup alpine tar czf /backup/omni-etcd-$(date +%Y%m%d).tar.gz -C /data .
docker run --rm -v postgres_data:/data -v /backup/bastion-omni:/backup alpine tar czf /backup/postgres-$(date +%Y%m%d).tar.gz -C /data .

# Backup configuration
cp -r omni /backup/bastion-omni/config-$(date +%Y%m%d)
```

## Troubleshooting

### Service Won't Start

```bash
# Check service logs
./setup-bastion.sh --logs SERVICE_NAME

# Check Docker compose status
docker-compose -f docker-compose.bastion.yml ps

# Restart individual service
docker-compose -f docker-compose.bastion.yml restart SERVICE_NAME
```

### SSL Issues

```bash
# Check certificate validity
openssl x509 -in omni/tls.crt -text -noout

# Regenerate certificates
certbot renew
cp /etc/letsencrypt/live/omni.example.com/fullchain.pem omni/tls.crt
cp /etc/letsencrypt/live/omni.example.com/privkey.pem omni/tls.key
```

### Network Issues

```bash
# Check port bindings
docker-compose -f docker-compose.bastion.yml port omni 8443

# Test internal connectivity
docker-compose -f docker-compose.bastion.yml exec omni ping keycloak
```

### Database Issues

```bash
# Check PostgreSQL status
./setup-bastion.sh --logs postgres

# Connect to database
docker-compose -f docker-compose.bastion.yml exec postgres psql -U postgres
```

## Security Considerations

1. **Firewall Configuration**:
   ```bash
   # Allow required ports
   ufw allow 80/tcp   # HTTP (redirects to HTTPS)
   ufw allow 443/tcp  # HTTPS
   ufw allow 8090/tcp # Omni Machine API
   ufw allow 8100/tcp # Omni K8s Proxy
   ufw allow 50180/udp # WireGuard
   ```

2. **Password Security**:
   - Use `--generate-passwords` for secure random passwords
   - Store passwords in a secure password manager
   - Rotate passwords regularly

3. **Access Control**:
   - Configure Nginx IP restrictions for admin services
   - Use strong authentication policies in Keycloak
   - Enable 2FA where possible

4. **Updates**:
   - Regularly update container images
   - Monitor security advisories
   - Test updates in staging environment

## Advanced Configuration

### Custom DNS Records

Add custom DNS records in Pi-hole:

```bash
# Access Pi-hole admin interface
https://pihole.omni.example.com

# Add local DNS records for internal services
omni.local          -> 172.20.0.10
keycloak.local      -> 172.20.0.11
```

### Registry Configuration

Configure Docker daemon to use local registry:

```json
{
  "insecure-registries": ["registry.omni.example.com"],
  "registry-mirrors": ["https://registry.omni.example.com"]
}
```

### Monitoring Dashboards

Import pre-built dashboards in Grafana:
- Docker container metrics
- Nginx performance
- Keycloak authentication metrics
- Omni cluster status

## Support

For issues with the bastion setup:

1. Check service logs: `./setup-bastion.sh --logs`
2. Verify configuration files in each service directory
3. Consult individual service documentation
4. Check Docker Compose networking and volumes

This bastion approach ensures that Omni and all its dependencies are self-contained and can bootstrap without external dependencies.
