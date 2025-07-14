# Omni Self-Hosted Deployment

This directory contains scripts and configuration for deploying Omni on-premises on AlmaLinux.

## Overview

Omni is a Kubernetes management platform that can be deployed on your own infrastructure. This deployment script automates the installation of all necessary components on an AlmaLinux machine.

## Prerequisites

- AlmaLinux machine (8+ recommended) with sudo access
- Domain name with DNS pointing to your server
- SSL certificates (can be auto-generated with Let's Encrypt)
- Auth0 account or other SAML identity provider configured

## Quick Start

### 1. Configure Authentication (Auth0)

1. Create an [Auth0 account](https://auth0.com/signup)
2. Create a "Single Page Web Application"
3. Configure the application with:
   - Allowed callback URLs: `https://your-domain.com`
   - Allowed web origins: `https://your-domain.com`
   - Allowed logout URLs: `https://your-domain.com`
4. Enable GitHub and Google login in Auth0
5. Note down your Auth0 Domain and Client ID

### 2. Deploy via SSH

Copy the deployment script to your target machine:

```bash
# Copy script to remote machine
scp deploy-omni.sh user@your-server:/tmp/

# SSH into the machine
ssh user@your-server

# Make script executable and run
chmod +x /tmp/deploy-omni.sh
/tmp/deploy-omni.sh --domain omni.example.com \
                    --email admin@example.com \
                    --auth0-client your_auth0_client_id \
                    --auth0-domain your_auth0_domain.us.auth0.com
```

### 3. Alternative: Environment Variables

You can also use environment variables:

```bash
export DOMAIN_NAME="omni.example.com"
export ADMIN_EMAIL="admin@example.com"
export AUTH0_CLIENT_ID="your_auth0_client_id"
export AUTH0_DOMAIN="your_auth0_domain.us.auth0.com"
export CERT_EMAIL="ssl@example.com"

./deploy-omni.sh
```

## Configuration Options

| Option | Environment Variable | Description | Required |
|--------|---------------------|-------------|----------|
| `--domain` | `DOMAIN_NAME` | Domain name for Omni | Yes |
| `--email` | `ADMIN_EMAIL` | Admin email address | Yes |
| `--auth0-client` | `AUTH0_CLIENT_ID` | Auth0 client ID | Yes |
| `--auth0-domain` | `AUTH0_DOMAIN` | Auth0 domain | Yes |
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
