# Backup and Restore Scripts for Bastion-Omni

This directory contains scripts for backing up and restoring the bastion-omni deployment.

## Files

- `backup.sh` - Creates backups of all critical data
- `restore.sh` - Restores from backup files
- `backup-config/` - Configuration for backup settings

## Quick Backup

```bash
# Create a full backup
./backup.sh --full

# Create incremental backup
./backup.sh --incremental

# List available backups
./backup.sh --list
```

## Quick Restore

```bash
# Restore from latest backup
./restore.sh --latest

# Restore from specific backup
./restore.sh --backup backup-20240101-120000

# Restore only configuration
./restore.sh --config-only --backup backup-20240101-120000
```

## Backup Contents

### Full Backup Includes:
- Omni configuration and TLS certificates
- Keycloak realm and user data
- PostgreSQL databases
- Prometheus metrics (optional)
- Grafana dashboards and settings
- Docker registry data
- Nginx configuration
- All environment files

### Incremental Backup Includes:
- Changed configuration files
- Database incremental changes
- New registry images

## Backup Storage

Backups are stored in:
- Local: `./backups/`
- Remote: S3/MinIO (if configured)
- Archive: Compressed tar.gz files

## Automation

Setup automated backups with cron:

```bash
# Daily full backup at 2 AM
0 2 * * * /path/to/omni/backup.sh --full --quiet

# Hourly incremental backup
0 * * * * /path/to/omni/backup.sh --incremental --quiet
```

## Retention Policy

Default retention:
- Full backups: 30 days
- Incremental backups: 7 days
- Archive backups: 365 days

Configure in `backup-config/retention.conf`.
