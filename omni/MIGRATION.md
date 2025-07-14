# Migration Guide: Bastion to Modular Deployment

This guide helps you migrate from the monolithic bastion deployment to the new modular Helm chart approach.

## Why Migrate?

The modular approach offers several advantages:

- **Separation of Concerns**: Each service is independently managed
- **Scalability**: Scale individual components based on needs
- **Maintenance**: Update/upgrade components independently
- **Resource Efficiency**: Deploy only what you need
- **Kubernetes Native**: Better integration with K8s ecosystem
- **Production Ready**: Industry-standard deployment patterns

## Migration Paths

### Path 1: Fresh Deployment (Recommended)

The cleanest approach is to deploy fresh using Helm charts:

1. **Backup existing data** from bastion deployment
2. **Deploy new modular setup** with Helm
3. **Restore data** to new deployment
4. **Update DNS/ingress** to point to new services
5. **Decommission** old bastion deployment

### Path 2: Gradual Migration

Migrate services one by one while keeping others running:

1. **Deploy core Helm chart** alongside bastion
2. **Migrate data** for core services
3. **Switch traffic** to new core services
4. **Deploy additional charts** (auth, monitoring, etc.)
5. **Migrate remaining services** one by one
6. **Decommission** bastion deployment

## Pre-Migration Checklist

- [ ] **Backup all data** using backup scripts
- [ ] **Document current configuration** (domains, passwords, etc.)
- [ ] **Prepare Kubernetes cluster** or plan to deploy one
- [ ] **Install Helm 3.x** and kubectl
- [ ] **Prepare SSL certificates** (cert-manager recommended)
- [ ] **Plan maintenance window** for DNS/traffic switching

## Step-by-Step Migration

### 1. Backup Current Deployment

```bash
# Backup everything from bastion deployment
cd /path/to/omni
./backup/backup.sh --type full

# List backups to confirm
./backup/backup.sh --list
```

### 2. Prepare New Environment

```bash
# Install Helm (if not already installed)
curl https://get.helm.sh/helm-v3.13.0-linux-amd64.tar.gz | tar xz
sudo mv linux-amd64/helm /usr/local/bin/

# Verify Kubernetes access
kubectl cluster-info

# Create namespace for new deployment
kubectl create namespace omni
```

### 3. Extract Configuration

Document your current configuration:

```bash
# Extract key configuration from bastion
echo "Current Domain: $(grep DOMAIN_NAME .env.local)"
echo "Auth Provider: $(grep AUTH_PROVIDER .env.local)"
echo "Keycloak URL: $(grep SAML_URL .env.local)"

# Save important passwords
grep -E "(PASSWORD|SECRET)" .env.local > migration-secrets.txt
chmod 600 migration-secrets.txt
```

### 4. Deploy Core Services

```bash
# Deploy core Omni services
./deploy-helm.sh --profile core \
  --domain your-domain.com \
  --namespace omni-new

# Wait for deployment to be ready
kubectl wait --for=condition=available deployment -l app.kubernetes.io/name=omni-core -n omni-new
```

### 5. Deploy Authentication (if using SAML)

```bash
# Deploy Keycloak for SAML
./deploy-helm.sh --profile auth \
  --domain your-domain.com \
  --namespace omni-new

# Wait for Keycloak to be ready
kubectl wait --for=condition=available deployment -l app.kubernetes.io/name=omni-auth -n omni-new
```

### 6. Migrate Data

#### Omni Data Migration

```bash
# Extract Omni data from backup
tar -xzf backups/backup-YYYYMMDD-HHMMSS.tar.gz
cd backup-YYYYMMDD-HHMMSS/volumes

# Copy to new deployment (example using kubectl cp)
kubectl cp omni_omni_data.tar.gz omni-new/omni-core-pod:/tmp/
kubectl exec -n omni-new omni-core-pod -- tar -xzf /tmp/omni_omni_data.tar.gz -C /var/lib/omni/
```

#### Keycloak Data Migration

```bash
# Restore Keycloak database
kubectl exec -n omni-new postgres-pod -- psql -U postgres -c "DROP DATABASE IF EXISTS keycloak;"
kubectl exec -n omni-new postgres-pod -- psql -U postgres -c "CREATE DATABASE keycloak;"
kubectl exec -i -n omni-new postgres-pod -- psql -U postgres keycloak < backup-YYYYMMDD-HHMMSS/databases/keycloak.sql
```

### 7. Configure SSL/Ingress

If using cert-manager:

```bash
# Install cert-manager
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set installCRDs=true

# Create ClusterIssuer for Let's Encrypt
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@domain.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
EOF
```

### 8. Test New Deployment

```bash
# Port-forward to test locally
kubectl port-forward -n omni-new service/omni-core-nginx 8443:443

# Test in browser: https://localhost:8443
# Verify authentication works
# Check all functionality
```

### 9. Switch Traffic

Update your DNS or load balancer to point to the new deployment:

```bash
# Get the new service external IP
kubectl get service -n omni-new omni-core-nginx

# Update DNS records to point to new IP
# Or update load balancer configuration
```

### 10. Deploy Additional Services

```bash
# Deploy monitoring
./deploy-helm.sh --upgrade --profile monitoring \
  --domain your-domain.com \
  --namespace omni-new

# Deploy other services as needed
./deploy-helm.sh --upgrade --profile complete \
  --domain your-domain.com \
  --namespace omni-new
```

### 11. Cleanup Old Deployment

Once everything is working:

```bash
# Stop bastion services
cd /path/to/old/omni
./setup-bastion.sh --stop

# Remove old containers and volumes (be careful!)
docker-compose -f docker-compose.bastion.yml down -v

# Archive old configuration
tar -czf omni-bastion-archive.tar.gz /opt/omni/
```

## Configuration Mapping

### Environment Variables

| Bastion (.env.local) | Helm Values | Description |
|---------------------|-------------|-------------|
| `DOMAIN_NAME` | `global.domain` | Main domain |
| `SAML_URL` | `auth.external.samlUrl` | SAML endpoint |
| `AUTH0_CLIENT_ID` | `auth.external.oidcClientId` | OIDC client |
| `POSTGRES_PASSWORD` | `postgresql.config.password` | DB password |
| `KEYCLOAK_ADMIN_PASSWORD` | `keycloak.config.adminPassword` | Keycloak admin |
| `REDIS_PASSWORD` | `redis.auth.password` | Redis auth |

### Service Mapping

| Bastion Service | Helm Chart | Component |
|----------------|------------|-----------|
| `bastion-omni` | `omni-core` | `omni` |
| `bastion-nginx` | `omni-core` | `nginx` |
| `bastion-redis` | `omni-core` | `redis` |
| `bastion-keycloak` | `omni-auth` | `keycloak` |
| `bastion-postgres` | `omni-auth` | `postgresql` |
| `bastion-prometheus` | `omni-monitoring` | `prometheus` |
| `bastion-grafana` | `omni-monitoring` | `grafana` |
| `bastion-loki` | `omni-monitoring` | `loki` |

## Troubleshooting

### Common Issues

1. **SSL Certificate Issues**
   - Use cert-manager with Let's Encrypt
   - Or manually copy certificates to secrets

2. **Data Migration Problems**
   - Verify file permissions and ownership
   - Check volume mount paths
   - Ensure databases are properly restored

3. **Authentication Not Working**
   - Verify Keycloak realm configuration
   - Check SAML endpoint URLs
   - Ensure client configuration matches

4. **Network Connectivity**
   - Verify service discovery works
   - Check network policies
   - Ensure ingress is properly configured

### Getting Help

1. **Check logs**: `kubectl logs -n omni-new deployment/omni-core-omni`
2. **Describe resources**: `kubectl describe pod -n omni-new`
3. **Check events**: `kubectl get events -n omni-new --sort-by=.metadata.creationTimestamp`
4. **Validate configuration**: `helm get values omni-core -n omni-new`

## Rollback Plan

If migration fails, you can quickly rollback:

```bash
# Start old bastion deployment
cd /path/to/old/omni
./setup-bastion.sh --start

# Update DNS back to old deployment
# Or revert load balancer configuration

# Clean up failed new deployment
kubectl delete namespace omni-new
```

## Benefits After Migration

Once migrated, you'll have:

- ✅ **Independent scaling** of components
- ✅ **Rolling updates** without downtime
- ✅ **Better resource utilization**
- ✅ **Standard Kubernetes tooling**
- ✅ **Easier backup/restore** procedures
- ✅ **Improved security** with pod security standards
- ✅ **Better monitoring** integration
- ✅ **Simplified day-2 operations**

The migration investment pays off with improved operational efficiency and reduced complexity in the long term.
