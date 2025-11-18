# B3LB Local Development Setup Guide

Complete guide for setting up B3LB (BigBlueButton Load Balancer) for local development.

## Overview

This guide will help you set up a simplified B3LB development environment on your local machine using Docker Compose. The local setup includes:

- **PostgreSQL 16** - Database (exposed on port 5432)
- **Redis 7** - Cache & Celery broker (exposed on port 6379)
- **B3LB Frontend** - Django API server (exposed on port 8000)
- **Celery Beat** - Task scheduler
- **Celery Worker** - Background task processor

**What's NOT included** (to keep it simple):
- Traefik reverse proxy
- SSL/TLS certificates
- Static file server (Django serves static files in debug mode)
- Monitoring stack (Prometheus/Grafana)
- Multiple replicas
- Recording rendering (disabled by default, can be enabled)

## Prerequisites

### Required Software

1. **Docker** (version 20.10+)
   ```bash
   docker --version
   ```

2. **Docker Compose** (version 2.0+)
   ```bash
   docker-compose --version
   ```

3. **Git**
   ```bash
   git --version
   ```

### Optional Tools

- **PostgreSQL client** - For database inspection
  ```bash
  sudo apt install postgresql-client  # Debian/Ubuntu
  brew install postgresql              # macOS
  ```

- **Redis CLI** - For cache inspection
  ```bash
  sudo apt install redis-tools         # Debian/Ubuntu
  brew install redis                   # macOS
  ```

- **Make** - For using the Makefile commands (usually pre-installed)
  ```bash
  make --version
  ```

## Quick Start (Using Makefile)

**Easiest method** - Use the provided Makefile for common tasks:

```bash
# Initial setup (creates .env, starts services, runs migrations)
make setup

# Create admin user
make createsuperuser

# Access the application
# Django Admin: http://localhost:8000/admin/
# API Health: http://localhost:8000/b3lb/ping

# Common commands:
make help           # Show all available commands
make start          # Start services
make stop           # Stop services
make logs           # View logs
make migrate        # Run migrations
make makemigrations # Create new migrations
make shell          # Django shell
make test           # Run tests
```

See the full list of commands with `make help`.

## Quick Start (Manual)

### 1. Clone the Repository

```bash
git clone https://github.com/DE-IBH/b3lb.git
cd b3lb
```

### 2. Create Local Environment File

```bash
# Copy the local environment template
cp .env.local .env

# (Optional) Edit .env if you want to change any settings
nano .env
```

The default `.env.local` file includes:
- `DEBUG=True` - Enable Django debug mode
- `SECRET_KEY` - Development secret key (change for production!)
- PostgreSQL connection to `b3lb_dev` database
- Redis password: `dev_redis_password`
- `B3LB_API_BASE_DOMAIN=localhost`
- Recording disabled by default

### 3. Start the Services

```bash
# Start all services in detached mode
docker-compose -f docker-compose.local.yml up -d

# Watch the logs (optional)
docker-compose -f docker-compose.local.yml logs -f
```

### 4. Wait for Services to Be Healthy

```bash
# Check service health status
docker-compose -f docker-compose.local.yml ps

# All services should show "healthy" status
# This may take 30-60 seconds on first start
```

Expected output:
```
NAME                        STATUS              PORTS
b3lb-postgres-local         Up (healthy)        0.0.0.0:5432->5432/tcp
b3lb-redis-local            Up (healthy)        0.0.0.0:6379->6379/tcp
b3lb-frontend-local         Up (healthy)        0.0.0.0:8000->8000/tcp
b3lb-celery-beat-local      Up (healthy)
b3lb-celery-worker-local    Up (healthy)
```

### 5. Run Database Migrations

```bash
# Apply all database migrations
docker-compose -f docker-compose.local.yml exec frontend ./manage.py migrate
```

Expected output:
```
Running migrations:
  Applying contenttypes.0001_initial... OK
  Applying auth.0001_initial... OK
  ...
  Applying rest.XXXX_xxx... OK
```

### 6. Create Superuser Account

```bash
# Create admin user for Django admin
docker-compose -f docker-compose.local.yml exec frontend ./manage.py createsuperuser
```

Follow the prompts:
```
Username: admin
Email address: admin@localhost
Password: ********
Password (again): ********
Superuser created successfully.
```

### 7. Access the Application

**Django Admin Interface:**
- URL: http://localhost:8000/admin/
- Login with superuser credentials created in step 6

**API Health Check:**
- URL: http://localhost:8000/b3lb/ping
- Expected response: `{"status": "ok"}`

**API Documentation:**
- URL: http://localhost:8000/b3lb/

## Common Operations

### View Logs

```bash
# All services
docker-compose -f docker-compose.local.yml logs -f

# Specific service
docker-compose -f docker-compose.local.yml logs -f frontend
docker-compose -f docker-compose.local.yml logs -f celery-worker
docker-compose -f docker-compose.local.yml logs -f postgres
```

### Run Django Management Commands

```bash
# General format
docker-compose -f docker-compose.local.yml exec frontend ./manage.py <command>

# Examples:
# Run tests
docker-compose -f docker-compose.local.yml exec frontend ./manage.py test

# Create migrations
docker-compose -f docker-compose.local.yml exec frontend ./manage.py makemigrations

# Django shell
docker-compose -f docker-compose.local.yml exec frontend ./manage.py shell

# Collect static files (if needed)
docker-compose -f docker-compose.local.yml exec frontend ./manage.py collectstatic --noinput
```

### Access Database

```bash
# Using psql from host (if PostgreSQL client installed)
psql -h localhost -p 5432 -U b3lb_dev -d b3lb_dev
# Password: dev_password_change_in_production

# Or through Docker
docker-compose -f docker-compose.local.yml exec postgres psql -U b3lb_dev -d b3lb_dev
```

Common PostgreSQL commands:
```sql
\dt              -- List all tables
\d rest_tenant   -- Describe tenant table
SELECT * FROM rest_tenant;
\q               -- Quit
```

### Access Redis

```bash
# Using redis-cli from host (if redis-tools installed)
redis-cli -h localhost -p 6379 -a dev_redis_password

# Or through Docker
docker-compose -f docker-compose.local.yml exec redis redis-cli -a dev_redis_password
```

Common Redis commands:
```
INFO             # Server information
KEYS *           # List all keys (don't use in production!)
SELECT 0         # Switch to DB 0 (Celery broker)
SELECT 1         # Switch to DB 1 (Django cache)
SELECT 2         # Switch to DB 2 (ORM cache)
FLUSHDB          # Clear current database
```

### Restart Services

```bash
# Restart all services
docker-compose -f docker-compose.local.yml restart

# Restart specific service
docker-compose -f docker-compose.local.yml restart frontend
docker-compose -f docker-compose.local.yml restart celery-worker
```

### Stop Services

```bash
# Stop all services (keeps data)
docker-compose -f docker-compose.local.yml stop

# Stop and remove containers (keeps volumes/data)
docker-compose -f docker-compose.local.yml down

# Stop and remove everything including data
docker-compose -f docker-compose.local.yml down -v
```

### Clean Start (Reset Everything)

```bash
# Stop and remove all containers, networks, and volumes
docker-compose -f docker-compose.local.yml down -v

# Start fresh
docker-compose -f docker-compose.local.yml up -d

# Wait for healthy, then re-run migrations and create superuser
docker-compose -f docker-compose.local.yml exec frontend ./manage.py migrate
docker-compose -f docker-compose.local.yml exec frontend ./manage.py createsuperuser
```

## Configuration Details

### Environment Variables

All configuration is in `.env` file. Key variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `DEBUG` | `True` | Enable Django debug mode |
| `SECRET_KEY` | (provided) | Django secret key |
| `DATABASE_URL` | `postgres://...` | PostgreSQL connection |
| `CELERY_BROKER_URL` | `redis://...` | Celery broker (Redis DB 0) |
| `CACHE_URL` | `redis://...` | Django cache (Redis DB 1) |
| `CACHEOPS_REDIS` | `redis://...` | ORM cache (Redis DB 2) |
| `B3LB_API_BASE_DOMAIN` | `localhost` | API base domain |
| `B3LB_RENDERING` | `False` | Enable recording rendering |
| `WEB_CONCURRENCY` | `2` | Number of Uvicorn workers |

### Port Mappings

| Service | Container Port | Host Port | Access URL |
|---------|---------------|-----------|------------|
| Frontend | 8000 | 8000 | http://localhost:8000 |
| PostgreSQL | 5432 | 5432 | localhost:5432 |
| Redis | 6379 | 6379 | localhost:6379 |

### Volume Mounts

| Volume | Purpose | Location |
|--------|---------|----------|
| `postgres_data_local` | PostgreSQL data | Docker volume |
| `redis_data_local` | Redis persistence | Docker volume |
| `./media` | User uploads | `./media` directory |
| `./recordings` | Recording files | `./recordings` directory |

## Development Workflow

### Code Changes

The Docker setup uses the published image from `quay.io/ibh/b3lb`. For live code editing:

1. **Option A: Rebuild custom image** (recommended for extensive changes)
   ```bash
   # Build local image
   docker build -t b3lb-local:dev -f docker/Dockerfile .

   # Edit docker-compose.local.yml to use your image:
   # Change: image: quay.io/ibh/b3lb:3.3.2
   # To: image: b3lb-local:dev

   # Restart
   docker-compose -f docker-compose.local.yml up -d --build
   ```

2. **Option B: Volume mount for live reload** (quick changes)
   ```bash
   # Uncomment volume mounts in docker-compose.local.yml:
   volumes:
     - ./b3lb:/usr/src/app/b3lb
     - ./rest:/usr/src/app/rest

   # Restart frontend
   docker-compose -f docker-compose.local.yml restart frontend
   ```

### Running Tests

```bash
# Run all tests
docker-compose -f docker-compose.local.yml exec frontend ./manage.py test

# Run specific app tests
docker-compose -f docker-compose.local.yml exec frontend ./manage.py test rest

# Run with coverage
docker-compose -f docker-compose.local.yml exec frontend coverage run --source='.' ./manage.py test
docker-compose -f docker-compose.local.yml exec frontend coverage report
```

### Database Migrations

```bash
# Create migrations after model changes
docker-compose -f docker-compose.local.yml exec frontend ./manage.py makemigrations

# Review migration file
ls -la rest/migrations/

# Apply migrations
docker-compose -f docker-compose.local.yml exec frontend ./manage.py migrate

# Show migration status
docker-compose -f docker-compose.local.yml exec frontend ./manage.py showmigrations
```

## Testing B3LB Features

### 1. Create a Tenant

Using Django admin (http://localhost:8000/admin/):

1. Navigate to **Rest → Tenants**
2. Click **Add tenant**
3. Fill in:
   - Slug: `test-tenant` (will be subdomain)
   - Secret: (auto-generated or set custom)
   - Check **Active**
4. Click **Save**

### 2. Create BBB Nodes

1. Navigate to **Rest → Nodes**
2. Click **Add node**
3. Fill in:
   - Domain: Your BBB server domain (e.g., `bbb1.example.com`)
   - Secret: BBB server shared secret
   - Check **Active**
4. Click **Save**
5. Repeat for multiple nodes

### 3. Test API Endpoint

```bash
# Health check
curl http://localhost:8000/b3lb/ping

# Tenant endpoint (replace with your tenant slug and secret)
curl "http://localhost:8000/bigbluebutton/api?checksum=xxx" \
  -H "Host: test-tenant.localhost"
```

## Troubleshooting

### Services Won't Start

```bash
# Check logs
docker-compose -f docker-compose.local.yml logs

# Check if ports are already in use
sudo lsof -i :8000  # Frontend
sudo lsof -i :5432  # PostgreSQL
sudo lsof -i :6379  # Redis
```

### Database Connection Errors

```bash
# Verify PostgreSQL is healthy
docker-compose -f docker-compose.local.yml ps postgres

# Check PostgreSQL logs
docker-compose -f docker-compose.local.yml logs postgres

# Test connection manually
docker-compose -f docker-compose.local.yml exec postgres psql -U b3lb_dev -d b3lb_dev -c "SELECT 1;"
```

### Celery Not Processing Tasks

```bash
# Check Celery worker logs
docker-compose -f docker-compose.local.yml logs celery-worker

# Check Celery beat logs
docker-compose -f docker-compose.local.yml logs celery-beat

# Inspect Celery status
docker-compose -f docker-compose.local.yml exec frontend celery -A b3lb inspect active
docker-compose -f docker-compose.local.yml exec frontend celery -A b3lb inspect stats
```

### Frontend Health Check Failing

```bash
# Check frontend logs
docker-compose -f docker-compose.local.yml logs frontend

# Manual health check
docker-compose -f docker-compose.local.yml exec frontend python3 -c "import urllib.request; print(urllib.request.urlopen('http://localhost:8000/b3lb/ping').read())"

# Check if migrations are applied
docker-compose -f docker-compose.local.yml exec frontend ./manage.py showmigrations
```

### Permission Errors with Volumes

```bash
# Fix permissions on media/recordings directories
sudo chown -R $USER:$USER media recordings
chmod -R 755 media recordings
```

## Optional: Enable Recording Rendering

If you need to test recording features:

1. **Edit `.env`:**
   ```bash
   B3LB_RENDERING=True
   B3LB_RECORD_PROFILES=720p,1080p
   ```

2. **Uncomment recording worker in `docker-compose.local.yml`:**
   - Find the `celery-record` service section (at the bottom)
   - Remove the `#` comment markers

3. **Restart services:**
   ```bash
   docker-compose -f docker-compose.local.yml up -d
   ```

4. **Create recordings directory:**
   ```bash
   mkdir -p recordings
   chmod 755 recordings
   ```

## Production Deployment

**WARNING:** The local setup is NOT suitable for production!

For production deployment, refer to:
- [docker-compose.hetzner-production.yml](docker-compose.hetzner-production.yml)
- [.env.hetzner.example](.env.hetzner.example)
- Official documentation: https://docs.b3lb.io/

Key differences for production:
- Use strong, randomly generated secrets
- Enable SSL/TLS with Let's Encrypt
- Configure Traefik reverse proxy
- Set `DEBUG=False`
- Use proper `ALLOWED_HOSTS`
- Enable monitoring (Prometheus/Grafana)
- Scale with multiple replicas
- Configure backups
- Use external managed database and Redis

## Additional Resources

- **Official Documentation**: https://docs.b3lb.io/
- **GitHub Repository**: https://github.com/DE-IBH/b3lb
- **Docker Hub**: https://quay.io/ibh/b3lb
- **BigBlueButton Docs**: https://docs.bigbluebutton.org/

## Getting Help

If you encounter issues:

1. Check the [Troubleshooting](#troubleshooting) section
2. Review service logs: `docker-compose -f docker-compose.local.yml logs`
3. Search existing GitHub issues: https://github.com/DE-IBH/b3lb/issues
4. Create a new issue with:
   - Your environment details (`docker --version`, OS)
   - Complete error logs
   - Steps to reproduce

## License

B3LB is licensed under the GNU Affero General Public License v3.0 (AGPL-3.0).
See [LICENSE](LICENSE) for full details.
