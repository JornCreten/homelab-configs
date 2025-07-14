# Omni Self-Hosted Deployment

This directory contains scripts and configuration for deploying Omni on-premises on AlmaLinux.

## Deployment Options

### 1. Modular Helm Charts (Recommended)
Deploy Omni and optional components using separate Helm charts for maximum flexibility.
- **Files**: `helm/` directory, `deploy-helm.sh`
- **Guide**: [helm/README.md](./helm/README.md)
- **Features**: Modular deployment, Kubernetes-native, production-ready

### 2. Core Docker Compose
Minimal deployment with essential services only (Omni, Nginx, Redis).
- **File**: `docker-compose.core.yml`
- **Guide**: This README (section below)
- **Features**: Lightweight, essential services only

### 3. Legacy Bastion Deployment
Complete self-contained deployment with all dependencies (monolithic approach).
- **File**: `docker-compose.bastion.yml`
- **Guide**: [BASTION_SETUP.md](./BASTION_SETUP.md)
- **Features**: Everything included, bootstrap-ready (legacy)

### 4. Standalone Deployment
Traditional single-service deployment using the deployment script.
- **Files**: `deploy-omni.sh`, `omni-config.env.template`
- **Guide**: This README (below)
- **Features**: Minimal Omni deployment with external dependencies

---

## Modular Helm Deployment Guide

The recommended approach for production deployments is to use the modular Helm charts.

### Quick Start with Helm

```bash
# Deploy core services only
./deploy-helm.sh --profile core --domain omni.example.com

# Deploy with authentication
./deploy-helm.sh --profile auth --domain omni.example.com

# Deploy complete stack
./deploy-helm.sh --profile complete --domain omni.example.com

# Upgrade existing deployment
./deploy-helm.sh --upgrade --profile complete
```

### Available Profiles

| Profile | Components | Use Case |
|---------|------------|----------|
| `core` | Omni, Nginx, Redis | Minimal setup with external auth |
| `auth` | Core + Keycloak, PostgreSQL | Self-contained with SAML auth |
| `monitoring` | Core + Prometheus, Grafana, Loki | Core with observability |
| `complete` | All components | Full-featured deployment |

### Prerequisites

- Kubernetes cluster with kubectl access
- Helm 3.x installed
- SSL certificates (can be managed by cert-manager)

### Chart Structure

```
helm/
├── omni-core/          # Essential Omni components
├── omni-auth/          # Keycloak SAML authentication
├── omni-monitoring/    # Prometheus, Grafana, Loki
├── omni-dns/           # Pi-hole (TODO)
├── omni-registry/      # Docker registry (TODO)
└── omni-bootstrap/     # DHCP, TFTP, PXE, NTP (TODO)
```

See [helm/README.md](./helm/README.md) for detailed information.

---

## Core Docker Compose Guide

For simple deployments without Kubernetes, use the core Docker Compose setup.

### Quick Start with Core Compose

```bash
# Deploy core services with Docker Compose
./deploy-helm.sh --type compose --profile core --domain omni.example.com

# Or manually
cp .env.bastion .env.core
# Edit .env.core with your settings
docker-compose -f docker-compose.core.yml up -d
```

### What's Included

- **Omni**: Main Kubernetes management service
- **Nginx**: SSL termination and reverse proxy
- **Redis**: Session storage and caching

### What's NOT Included

For additional services, deploy them separately or use Helm charts:

- Authentication (Keycloak) - use `omni-auth` Helm chart
- Monitoring (Prometheus/Grafana) - use `omni-monitoring` Helm chart
- DNS services - use `omni-dns` Helm chart
- Container registry - use `omni-registry` Helm chart

---

## Standalone Deployment Guide

The following guide covers the standalone deployment option. For the recommended bastion approach, see [BASTION_SETUP.md](./BASTION_SETUP.md).

## Overview

Omni is a Kubernetes management platform that can be deployed on your own infrastructure. This deployment script automates the installation of all necessary components on an AlmaLinux machine.

## Authentication Options

This deployment supports two authentication methods:

1. **Auth0** (OIDC/OAuth2) - Cloud-based identity provider
2. **SAML** - For on-premises identity providers like Keycloak, AD FS, etc.

## Prerequisites

- AlmaLinux machine (8+ recommended) with sudo access
- Domain name with DNS pointing to your server
- SSL certificates (can be auto-generated with Let's Encrypt)
- **For Auth0**: Auth0 account configured
- **For SAML**: SAML identity provider (see [KEYCLOAK_SETUP.md](./KEYCLOAK_SETUP.md) for Keycloak setup)

## Quick Start

## Quick Start

### 1. Configure Authentication

#### Option A: Auth0 (OIDC/OAuth2)

1. Create an [Auth0 account](https://auth0.com/signup)
2. Create a "Single Page Web Application"
3. Configure the application with:
   - Allowed callback URLs: `https://your-domain.com`
   - Allowed web origins: `https://your-domain.com`
   - Allowed logout URLs: `https://your-domain.com`
4. Enable GitHub and Google login in Auth0
5. Note down your Auth0 Domain and Client ID

#### Option B: SAML (Keycloak, AD FS, etc.)

1. Set up your SAML Identity Provider (see [KEYCLOAK_SETUP.md](./KEYCLOAK_SETUP.md) for Keycloak)
2. Configure SAML client with:
   - Valid Redirect URIs: `https://your-domain.com/*`
   - Master SAML Processing URL: `https://your-domain.com/saml/acs`
   - Attribute mappings for email, first name, last name
3. Note down your SAML endpoint URL

### 2. Deploy via SSH

Copy the deployment script to your target machine:

```bash
# Copy script to remote machine
scp deploy-omni.sh user@your-server:/tmp/

# SSH into the machine
ssh user@your-server

# Make script executable and run with Auth0
chmod +x /tmp/deploy-omni.sh
/tmp/deploy-omni.sh --domain omni.example.com \
                    --email admin@example.com \
                    --auth-provider auth0 \
                    --auth0-client your_auth0_client_id \
                    --auth0-domain your_auth0_domain.us.auth0.com

# Or with SAML/Keycloak
/tmp/deploy-omni.sh --domain omni.example.com \
                    --email admin@example.com \
                    --auth-provider saml \
                    --saml-url https://keycloak.example.com/realms/omni/protocol/saml
```

### 3. Alternative: Environment Variables

You can also use environment variables:

```bash
# For Auth0
export DOMAIN_NAME="omni.example.com"
export ADMIN_EMAIL="admin@example.com"
export AUTH_PROVIDER="auth0"
export AUTH0_CLIENT_ID="your_auth0_client_id"
export AUTH0_DOMAIN="your_auth0_domain.us.auth0.com"
export CERT_EMAIL="ssl@example.com"

# For SAML/Keycloak
export DOMAIN_NAME="omni.example.com"
export ADMIN_EMAIL="admin@example.com"
export AUTH_PROVIDER="saml"
export SAML_URL="https://keycloak.example.com/realms/omni/protocol/saml"
export CERT_EMAIL="ssl@example.com"

./deploy-omni.sh
```

## Configuration Options

| Option | Environment Variable | Description | Required |
|--------|---------------------|-------------|----------|
| `--domain` | `DOMAIN_NAME` | Domain name for Omni | Yes |
| `--email` | `ADMIN_EMAIL` | Admin email address | Yes |
| `--auth-provider` | `AUTH_PROVIDER` | Authentication provider (auth0 or saml) | No (default: auth0) |
| `--auth0-client` | `AUTH0_CLIENT_ID` | Auth0 client ID | Yes (if using auth0) |
| `--auth0-domain` | `AUTH0_DOMAIN` | Auth0 domain | Yes (if using auth0) |
| `--saml-url` | `SAML_URL` | SAML endpoint URL | Yes (if using saml) |
| `--cert-email` | `CERT_EMAIL` | Email for SSL certificates | No |
| `--dns-provider` | `DNS_PROVIDER` | DNS provider for certbot | No |
| `--version` | `OMNI_VERSION` | Omni version | No |
| `--wireguard-ip` | `WG_IP` | WireGuard IP | No |
| `--skip-docker` | `SKIP_DOCKER_INSTALL` | Skip Docker installation | No |
| `--skip-certs` | `SKIP_CERT_GENERATION` | Skip SSL cert generation | No |

## What the Script Does

1. **System Updates**: Updates AlmaLinux packages and installs dependencies
2. **Docker Installation**: Installs Docker Engine and Docker Compose via official Docker repository
3. **Certbot Setup**: Installs certbot via snap for SSL certificate generation
4. **GPG Key Generation**: Creates GPG key for etcd encryption
5. **Environment Setup**: Downloads and configures Omni deployment files
6. **Service Configuration**: Prepares docker-compose configuration

## Post-Deployment Steps

After running the script:

1. **Configure Firewall** (AlmaLinux specific):
   ```bash
   # Use the provided script
   ./configure-firewall.sh
   
   # Or manually configure
   sudo systemctl start firewalld
   sudo firewall-cmd --permanent --add-service=http
   sudo firewall-cmd --permanent --add-service=https
   sudo firewall-cmd --permanent --add-port=51820/udp
   sudo firewall-cmd --reload
   ```

2. **Generate SSL Certificates** (if not skipped):
   ```bash
   # Create DNS provider credentials
   nano ~/dns-credentials.ini
   chmod 600 ~/dns-credentials.ini
   
   # Generate certificates
   sudo certbot certonly --dns-digitalocean \
     --dns-digitalocean-credentials ~/dns-credentials.ini \
     -d your-domain.com \
     --email your-email@example.com \
     --agree-tos --non-interactive
   ```

3. **Start Omni Services**:
   ```bash
   cd /opt/omni
   source omni-vars.env
   docker compose --env-file omni.env up -d
   ```

4. **Verify Deployment**:
   ```bash
   docker compose --env-file omni.env ps
   docker compose --env-file omni.env logs -f
   ```

5. **Access Omni**: Navigate to `https://your-domain.com`

## DNS Provider Support

The script supports multiple DNS providers for automatic SSL certificate generation:

- DigitalOcean (`digitalocean`)
- AWS Route53 (`route53`)
- Cloudflare (`cloudflare`)

## Firewall Configuration

Ensure the following ports are open:

- **80/tcp**: HTTP (for Let's Encrypt challenges)
- **443/tcp**: HTTPS (for Omni web interface)
- **51820/udp**: WireGuard (default, configurable)

## Directory Structure

After deployment, you'll find these files in `/opt/omni`:

```
/opt/omni/
├── omni.env           # Environment configuration
├── compose.yaml       # Docker Compose file
├── omni-vars.env      # Environment variables
└── omni.asc          # GPG key for etcd encryption
```

## Troubleshooting

### Docker Permission Issues
If you get permission errors with Docker:
```bash
# Log out and back in, or run:
newgrp docker
```

### Snap/Certbot Issues on AlmaLinux
If snap commands aren't working:
```bash
# Ensure snap is properly initialized
sudo systemctl enable --now snapd.socket
export PATH="$PATH:/var/lib/snapd/snap/bin"
```

### SSL Certificate Issues
- Verify DNS is pointing to your server
- Check DNS provider credentials
- Ensure ports 80 and 443 are accessible
- Make sure SELinux is not blocking certbot

### Service Won't Start
Check logs for detailed error information:
```bash
docker compose --env-file omni.env logs omni
```

### SELinux Issues
If SELinux is causing problems:
```bash
# Check SELinux status
getenforce

# Temporarily disable (not recommended for production)
sudo setenforce 0

# Or configure SELinux policies for Docker
sudo setsebool -P container_manage_cgroup true
```

## Security Considerations

- Keep your Auth0 credentials secure
- Regularly update SSL certificates
- Monitor access logs
- Keep Docker and system packages updated
- Backup the GPG key (`omni.asc`) securely
- Configure SELinux policies appropriately for production
- Consider firewalld configuration for port management

## Support

For issues related to:
- **Script**: Check the logs and error messages
- **Omni**: Visit [Omni Documentation](https://omni.siderolabs.com/)
- **Auth0**: Check [Auth0 Documentation](https://auth0.com/docs)

## License

Omni is available under the [Business Source License](https://github.com/siderolabs/omni/blob/main/LICENSE). Free for non-production use. Contact [Sidero Sales](mailto:sales@siderolabs.com) for production licensing.

## Management Scripts

The Omni deployment includes several management scripts for different deployment scenarios:

### Deploy Script (`deploy-omni.sh`) - Legacy

Original deployment script with support for both Auth0 and SAML authentication:

```bash
# Deploy with Auth0
./deploy-omni.sh --auth0 --client-id YOUR_CLIENT_ID --domain YOUR_DOMAIN.auth0.com

# Deploy with SAML
./deploy-omni.sh --saml --url https://keycloak.example.com/realms/omni/protocol/saml

# Show help
./deploy-omni.sh --help
```

### Helm Deployment Script (`deploy-helm.sh`) - Recommended

Modern deployment script for Helm charts and Docker Compose:

```bash
# Deploy with Helm (recommended)
./deploy-helm.sh --profile complete --domain omni.example.com

# Deploy core services with Docker Compose
./deploy-helm.sh --type compose --profile core --domain omni.example.com

# Dry run to see what would be deployed
./deploy-helm.sh --dry-run --profile complete

# Upgrade existing deployment
./deploy-helm.sh --upgrade --profile complete

# Uninstall deployment
./deploy-helm.sh --uninstall
```

### Bastion Setup Script (`setup-bastion.sh`) - Legacy

Legacy complete bastion-omni deployment with all dependencies:

```bash
# Quick setup with SAML and monitoring (legacy)
./setup-bastion.sh --domain omni.example.com --email admin@example.com --profiles saml,monitoring --start

# Generate secure passwords
./setup-bastion.sh --generate-passwords

# Setup Keycloak automatically
./setup-bastion.sh --keycloak-setup

# Check deployment status
./setup-bastion.sh --status

# View service logs
./setup-bastion.sh --logs omni
```

**Note**: The bastion setup is now considered legacy. Use Helm charts for new deployments.

### Health Check Script (`healthcheck.sh`)

Monitor all services and endpoints:

```bash
# Run comprehensive health check
./healthcheck.sh

# Use custom timeout
./healthcheck.sh --timeout 30
```

### Backup Script (`backup/backup.sh`)

Create backups of all critical data:

```bash
# Create full backup
./backup/backup.sh --type full

# Create incremental backup
./backup/backup.sh --type incremental

# List available backups
./backup/backup.sh --list
```

### Environment Template (`omni-config.env.template`)

Copy and customize the environment template:

```bash
cp omni-config.env.template omni-config.env
# Edit the file to set your domain, authentication, and other settings
```

## Bastion-Omni Deployment

For a complete self-contained deployment with all dependencies, use the bastion setup:

### Quick Start

```bash
# 1. Configure environment
cp .env.bastion .env.local
nano .env.local  # Edit your domain, passwords, etc.

# 2. Setup with SAML and monitoring
./setup-bastion.sh --domain omni.example.com --email admin@example.com --profiles saml,monitoring --start

# 3. Check health
./healthcheck.sh
```

### Service Profiles

The bastion deployment supports different service profiles:

| Profile | Services | Description |
|---------|----------|-------------|
| `saml` | Keycloak, PostgreSQL | SAML authentication with Keycloak |
| `monitoring` | Prometheus, Grafana, Loki | Complete monitoring stack |
| `dns` | Pi-hole | DNS services and ad-blocking |
| `registry` | Docker Registry | Private container registry |
| `pxe` | TFTP, HTTP Boot Server | PXE boot services |
| `dhcp` | DHCP Server | Network DHCP services |
| `ntp` | NTP Server | Time synchronization |

See [BASTION_SETUP.md](./BASTION_SETUP.md) for detailed setup instructions.
