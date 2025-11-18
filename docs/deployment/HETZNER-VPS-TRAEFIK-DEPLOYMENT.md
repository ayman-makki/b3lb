# B3LB Production Deployment on Hetzner EX44 with Traefik

**Complete guide for deploying B3LB on a Hetzner dedicated server with Traefik reverse proxy, Let's Encrypt SSL, and comprehensive monitoring.**

---

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Architecture](#architecture)
4. [Initial Server Setup](#initial-server-setup)
5. [DNS Configuration](#dns-configuration)
6. [Storage Box Setup](#storage-box-setup)
7. [Environment Configuration](#environment-configuration)
8. [Deployment](#deployment)
9. [Post-Deployment](#post-deployment)
10. [Monitoring](#monitoring)
11. [Troubleshooting](#troubleshooting)

---

## Overview

This deployment guide covers installing B3LB on a **Hetzner EX44 dedicated server** with the following stack:

- **B3LB**: BigBlueButton Load Balancer (v3.3.2)
- **Traefik v3**: Reverse proxy with automatic Let's Encrypt SSL
- **PostgreSQL 16**: Primary database
- **Redis 7**: Cache and message broker
- **Prometheus + Grafana**: Monitoring and dashboards
- **Hetzner Storage Box**: 5TB storage for recordings

### Key Features

✅ **Multi-tenant support** - Multiple organizations on one server
✅ **Wildcard SSL** - Automatic certificates for `*.b3lb.serveur.cc`
✅ **High availability** - 3 frontend replicas
✅ **Recording processing** - Video rendering with Storage Box
✅ **Comprehensive monitoring** - Prometheus + Grafana dashboards
✅ **Automated backups** - Daily PostgreSQL and Redis backups

### Target Capacity

- **BBB Nodes**: < 20 nodes (expandable to 50+)
- **Concurrent Meetings**: 100-500 depending on node capacity
- **Recordings**: 5TB storage (expandable)

---

## Prerequisites

### Hardware Requirements (Hetzner EX44)

| Component | Specification | Status |
|-----------|---------------|--------|
| CPU | Intel i5-13500 (14 cores) | ✅ Optimal |
| RAM | 64 GB DDR4 | ✅ Excellent |
| Storage | 2x 512GB NVMe SSD | ✅ Sufficient |
| Network | 1 Gbit/s | ✅ Excellent |

### Software Requirements

| Software | Version | Purpose |
|----------|---------|---------|
| **Ubuntu Server** | 22.04 LTS or 24.04 LTS | Operating system |
| **Docker** | 20.10+ | Container runtime |
| **Docker Compose** | 2.0+ | Container orchestration |
| **Git** | Latest | Source control |

### Hetzner Services

1. **Dedicated Server**: EX44 or similar (ordered from Hetzner)
2. **Storage Box**: 5TB (ordered from Hetzner Robot panel)
3. **DNS Service**: Hetzner DNS (free) with API access
4. **Domain**: `b3lb.serveur.cc` (or your domain)

### Access Requirements

- ✅ SSH root access to server
- ✅ Hetzner Robot panel credentials
- ✅ Hetzner DNS Console access
- ✅ Storage Box credentials

---

## Architecture

```
┌────────────────────────────────────────────────────────────────┐
│                      Internet Traffic                           │
│                     (Port 80 & 443)                            │
└────────────────────┬───────────────────────────────────────────┘
                     │
            ┌────────▼────────┐
            │     Traefik     │  ← Let's Encrypt DNS-01 (Hetzner)
            │  Reverse Proxy  │
            └────────┬────────┘
                     │
        ┌────────────┼────────────┐
        │            │            │
   ┌────▼───┐   ┌───▼────┐  ┌───▼────┐
   │Frontend│   │Frontend│  │Frontend│  ← B3LB API (3 replicas)
   │Replica1│   │Replica2│  │Replica3│
   └────┬───┘   └───┬────┘  └───┬────┘
        │           │           │
        └───────────┼───────────┘
                    │
        ┌───────────┴───────────┐
        │                       │
   ┌────▼────┐          ┌──────▼─────┐
   │ Postgres│          │   Redis    │
   │Database │          │Cache/Broker│
   └─────────┘          └────────────┘
        │                       │
        └───────────┬───────────┘
                    │
        ┌───────────┴───────────────────┐
        │                               │
   ┌────▼─────┐                  ┌─────▼──────┐
   │  Celery  │                  │   Celery   │
   │   Beat   │                  │  Workers   │
   │(Scheduler)│                  │(Core+Record)│
   └──────────┘                  └────────────┘
                                        │
                                 ┌──────▼──────┐
                                 │   Storage   │
                                 │     Box     │
                                 │   (5 TB)    │
                                 └─────────────┘
                                        │
                                 ┌──────▼──────┐
                                 │ Prometheus  │
                                 │  + Grafana  │
                                 └─────────────┘
```

### Service Overview

| Service | Replicas | RAM | Purpose |
|---------|----------|-----|---------|
| Traefik | 1 | 512MB | Reverse proxy + SSL |
| Frontend | 3 | 6GB | B3LB API endpoints |
| PostgreSQL | 1 | 16GB | Database |
| Redis | 1 | 4GB | Cache + broker |
| Celery Beat | 1 | 512MB | Task scheduler |
| Celery Core | 3 | 6GB | Background tasks |
| Celery Record | 2 | 20GB | Video rendering |
| Prometheus | 1 | 2GB | Metrics collection |
| Grafana | 1 | 1GB | Dashboards |

**Total RAM Usage**: ~56GB (leaves 8GB for system)

---

## Initial Server Setup

### 1. Connect to Server

```bash
ssh root@your-server-ip
```

### 2. Update System

```bash
apt update && apt upgrade -y
apt install -y curl wget git htop vim
```

### 3. Install Docker

```bash
curl -fsSL https://get.docker.com | sh
systemctl enable docker
systemctl start docker
```

### 4. Install Docker Compose

```bash
apt install -y docker-compose-plugin
```

Verify installation:

```bash
docker --version
docker compose version
```

### 5. Clone B3LB Repository

```bash
cd /opt
git clone https://github.com/DE-IBH/b3lb.git
cd b3lb
```

---

## DNS Configuration

### Required DNS Records

Configure in **Hetzner DNS Console** (https://dns.hetzner.com):

```dns
Type    Name                TTL     Value
────────────────────────────────────────────────────
A       b3lb.serveur.cc     3600    YOUR_SERVER_IP
A       *.b3lb.serveur.cc   3600    YOUR_SERVER_IP
```

### Alternative: CNAME Wildcard

```dns
Type    Name                TTL     Value
────────────────────────────────────────────────────
A       b3lb.serveur.cc     3600    YOUR_SERVER_IP
CNAME   *.b3lb.serveur.cc   3600    b3lb.serveur.cc
```

### Get Hetzner DNS API Token

1. Go to: https://dns.hetzner.com/settings/api-token
2. Create new token with **Read & Write** permissions
3. Save token securely (you'll need it for `.env`)

### Verify DNS Propagation

```bash
# Check main domain
dig +short b3lb.serveur.cc

# Check wildcard
dig +short test-tenant.b3lb.serveur.cc
```

Both should return your server IP.

---

## Storage Box Setup

### 1. Get Storage Box Credentials

1. Log in to **Hetzner Robot**: https://robot.hetzner.com/storage
2. Find your Storage Box (e.g., `u123456`)
3. Note down:
   - Hostname: `u123456.your-storagebox.de`
   - Username: `u123456`
   - Password: (shown in panel)

### 2. Mount Storage Box

Run the automated mount script:

```bash
cd /opt/b3lb
chmod +x scripts/storage/mount-storagebox.sh
sudo ./scripts/storage/mount-storagebox.sh
```

The script will:
- Install `cifs-utils`
- Create mount point at `/mnt/b3lb-recordings`
- Store credentials in `/root/.storagebox-credentials`
- Configure systemd auto-mount
- Test write permissions

### 3. Verify Mount

```bash
cd /opt/b3lb
chmod +x scripts/storage/test-storagebox.sh
./scripts/storage/test-storagebox.sh
```

Expected output: All tests passed ✓

---

## Environment Configuration

### 1. Copy Environment Template

```bash
cd /opt/b3lb
cp .env.hetzner.example .env
```

### 2. Generate Secrets

```bash
# Generate Django SECRET_KEY
python3 -c 'from django.core.management.utils import get_random_secret_key; print(get_random_secret_key())'

# Generate strong passwords
openssl rand -base64 32  # For PostgreSQL
openssl rand -base64 32  # For Redis
openssl rand -base64 16  # For Grafana

# Generate htpasswd for Traefik dashboard
htpasswd -nb admin your-password
```

### 3. Edit Configuration

```bash
nano .env
```

**Critical variables to configure:**

```bash
# Django
SECRET_KEY="your-generated-secret-key-here"
TIME_ZONE="Europe/Paris"

# Database
POSTGRES_PASSWORD="your-strong-postgres-password"

# Redis
REDIS_PASSWORD="your-strong-redis-password"

# Hetzner DNS (for Let's Encrypt)
HETZNER_DNS_API_TOKEN="your-hetzner-dns-api-token"

# Traefik Dashboard
TRAEFIK_DASHBOARD_AUTH="admin:$$apr1$$hash-from-htpasswd"

# Grafana
GRAFANA_ADMIN_PASSWORD="your-grafana-password"

# Storage Box
STORAGEBOX_HOST="u123456.your-storagebox.de"
STORAGEBOX_USERNAME="u123456"
STORAGEBOX_PASSWORD="your-storagebox-password"
```

### 4. Secure the File

```bash
chmod 600 .env
```

**⚠️ NEVER commit .env to version control!**

---

## Deployment

### Step 1: Pre-Flight Checks

Run comprehensive system validation:

```bash
cd /opt/b3lb
chmod +x scripts/deploy/00-preflight-check.sh
./scripts/deploy/00-preflight-check.sh
```

✅ All checks should pass before proceeding.

### Step 2: Deploy Stack

Run the main deployment script:

```bash
chmod +x scripts/deploy/03-deploy-stack.sh
sudo ./scripts/deploy/03-deploy-stack.sh
```

The script will:
1. ✅ Validate environment
2. ✅ Generate remaining secrets
3. ✅ Create required directories
4. ✅ Pull Docker images
5. ✅ Start database services
6. ✅ Run migrations
7. ✅ Start all services
8. ✅ Create Django superuser

**Deployment time**: ~10-15 minutes

### Step 3: Verify Deployment

Wait 2-3 minutes for Let's Encrypt certificates, then check services:

```bash
docker-compose -f docker-compose.hetzner-production.yml ps
```

All services should show "healthy" status.

Check logs:

```bash
docker-compose -f docker-compose.hetzner-production.yml logs -f traefik
```

Look for: `Certificate obtained for domain *.b3lb.serveur.cc`

---

## Post-Deployment

### Access Web Interfaces

| Service | URL | Credentials |
|---------|-----|-------------|
| **B3LB API** | https://b3lb.serveur.cc | N/A |
| **Django Admin** | https://b3lb.serveur.cc/admin/ | admin / your-password |
| **Traefik Dashboard** | https://traefik.b3lb.serveur.cc | From `.env` or `.traefik-password.txt` |
| **Grafana** | https://grafana.b3lb.serveur.cc | admin / from `.env` |
| **Prometheus** | https://prometheus.b3lb.serveur.cc | (protected by Traefik auth) |

### Initial Configuration

See [INITIAL-CONFIGURATION.md](./INITIAL-CONFIGURATION.md) for:
- Creating your first tenant
- Adding cluster groups
- Configuring BBB nodes
- Generating API secrets
- Testing the API

---

## Monitoring

### Grafana Dashboards

Access Grafana at: https://grafana.b3lb.serveur.cc

**Available Dashboards:**
- B3LB Overview: Tenants, meetings, nodes, recordings
- Traefik: Request rates, response codes, SSL
- PostgreSQL: Connections, queries, performance
- Redis: Memory, commands, hit rates
- System: CPU, RAM, disk, network

### Prometheus Metrics

Access raw metrics: https://prometheus.b3lb.serveur.cc

**Key Metrics:**
- `b3lb_meetings_total` - Total active meetings
- `b3lb_attendees_total` - Total attendees
- `b3lb_node_health` - Node health status
- `traefik_http_requests_total` - HTTP requests
- `postgres_connections` - Database connections

### Logs

View real-time logs:

```bash
# All services
docker-compose -f docker-compose.hetzner-production.yml logs -f

# Specific service
docker-compose -f docker-compose.hetzner-production.yml logs -f frontend

# Traefik access logs
docker-compose -f docker-compose.hetzner-production.yml logs -f traefik | grep "access"
```

---

## Backup & Restore

### Automated Daily Backups

Backups are configured to run daily at 3 AM:

```bash
# Enable backup automation
chmod +x scripts/backup/backup.sh
sudo cp scripts/backup/backup.service /etc/systemd/system/
sudo cp scripts/backup/backup.timer /etc/systemd/system/
sudo systemctl enable backup.timer
sudo systemctl start backup.timer
```

**Backup includes:**
- PostgreSQL database dump
- Redis RDB snapshot
- Configuration files (.env, docker-compose.yml)

**Backup location:** `/mnt/b3lb-recordings/backups/`

**Retention:** 30 days (configurable)

### Manual Backup

```bash
sudo ./scripts/backup/backup.sh
```

### Restore from Backup

```bash
sudo ./scripts/backup/restore.sh /mnt/b3lb-recordings/backups/backup-2025-01-15.tar.gz
```

---

## Troubleshooting

### SSL Certificate Issues

**Problem**: Certificate not obtained after 10 minutes

**Solutions:**
1. Check DNS propagation: `dig +short b3lb.serveur.cc`
2. Verify Hetzner DNS API token in `.env`
3. Check Traefik logs: `docker-compose logs traefik`
4. Ensure ports 80 and 443 are open

### Service Not Starting

**Problem**: Container keeps restarting

**Solutions:**
1. Check logs: `docker-compose logs [service-name]`
2. Verify `.env` configuration
3. Check disk space: `df -h`
4. Check RAM usage: `free -h`
5. Restart service: `docker-compose restart [service-name]`

### Database Connection Errors

**Problem**: "could not connect to server"

**Solutions:**
1. Check PostgreSQL is running: `docker-compose ps postgres`
2. Verify credentials in `.env`
3. Check logs: `docker-compose logs postgres`
4. Restart database: `docker-compose restart postgres`

### Storage Box Mount Issues

**Problem**: `/mnt/b3lb-recordings` not accessible

**Solutions:**
1. Check mount status: `mountpoint /mnt/b3lb-recordings`
2. Verify credentials: `cat /root/.storagebox-credentials`
3. Test connectivity: `ping u123456.your-storagebox.de`
4. Remount: `systemctl restart mnt-b3lb\\x2drecordings.mount`
5. Re-run mount script: `./scripts/storage/mount-storagebox.sh`

### High CPU Usage

**Solutions:**
1. Check Celery recording workers (PyPy uses more CPU during rendering)
2. Reduce recording quality profiles in `.env`
3. Scale down recording workers if not needed
4. Monitor with: `docker stats`

### Out of Memory

**Solutions:**
1. Check memory usage: `docker stats`
2. Reduce worker replicas in `docker-compose.yml`
3. Adjust PostgreSQL `shared_buffers`
4. Reduce Redis `maxmemory`

---

## Maintenance

### Update B3LB

```bash
cd /opt/b3lb
git pull
docker-compose -f docker-compose.hetzner-production.yml pull
docker-compose -f docker-compose.hetzner-production.yml up -d
docker-compose -f docker-compose.hetzner-production.yml exec frontend python manage.py migrate
```

### Scale Services

Edit `docker-compose.hetzner-production.yml`:

```yaml
frontend:
  deploy:
    replicas: 5  # Increase from 3 to 5

celery-core:
  deploy:
    replicas: 5  # Increase from 3 to 5
```

Apply changes:

```bash
docker-compose -f docker-compose.hetzner-production.yml up -d --scale frontend=5 --scale celery-core=5
```

### View Resource Usage

```bash
# Real-time container stats
docker stats

# Disk usage
du -sh /var/lib/docker/
df -h /mnt/b3lb-recordings
```

---

## Security Recommendations

### Firewall Configuration

```bash
# Allow SSH, HTTP, HTTPS only
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw enable
```

### Harden SSH

Edit `/etc/ssh/sshd_config`:

```
PermitRootLogin prohibit-password
PasswordAuthentication no
PubkeyAuthentication yes
```

Restart SSH: `systemctl restart sshd`

### Enable Automatic Security Updates

```bash
apt install unattended-upgrades
dpkg-reconfigure --priority=low unattended-upgrades
```

### Regular Maintenance

- ✅ Review logs weekly
- ✅ Update system monthly
- ✅ Test backups monthly
- ✅ Monitor disk space
- ✅ Review Grafana alerts

---

## Additional Resources

- **Official B3LB Docs**: https://docs.b3lb.io/
- **Traefik Docs**: https://doc.traefik.io/traefik/
- **Hetzner Docs**: https://docs.hetzner.com/
- **Community Support**: https://github.com/DE-IBH/b3lb/issues

---

## Support

For issues specific to this deployment setup:
1. Check [TROUBLESHOOTING.md](../operations/TROUBLESHOOTING.md)
2. Review logs: `docker-compose logs`
3. Open issue on GitHub: https://github.com/DE-IBH/b3lb/issues

---

**Deployment Guide Version**: 1.0
**Last Updated**: 2025-01-15
**B3LB Version**: 3.3.2
