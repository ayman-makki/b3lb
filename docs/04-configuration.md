# B3LB Configuration

## Overview

B3LB is configured primarily through environment variables following the [12-factor app methodology](https://12factor.net/). Configuration is loaded via `django-environ` for flexible deployment across different environments.

## Configuration File

Settings are managed in [b3lb/loadbalancer/settings.py](../b3lb/loadbalancer/settings.py) with defaults defined in [rest/constants.py](../rest/constants.py).

---

## Required Environment Variables

These variables **must** be set for B3LB to function.

### SECRET_KEY

**Purpose**: Django secret key for cryptographic signing

**Format**: String (50+ characters recommended)

**Security**: Keep secret, rotate periodically

**Generation**:
```bash
# Using pwgen
pwgen -ys 50 1

# Using Python
python -c "from django.core.management.utils import get_random_secret_key; print(get_random_secret_key())"

# Using OpenSSL
openssl rand -base64 50
```

**Example**:
```bash
SECRET_KEY="xy9z!@#$%^&*()_+-=[]{}|;:,.<>?abcdefghijklmnopqrstuvw"
```

---

### DATABASE_URL

**Purpose**: PostgreSQL database connection string

**Format**: `postgres://user:password@host:port/database`

**Requirements**:
- PostgreSQL 9.5+
- Database must exist before first run
- User must have CREATE/ALTER privileges for migrations

**Examples**:
```bash
# Local PostgreSQL
DATABASE_URL="postgres://b3lb:password@localhost:5432/b3lb"

# Remote PostgreSQL
DATABASE_URL="postgres://b3lb:password@postgres.example.com:5432/b3lb"

# PostgreSQL with SSL
DATABASE_URL="postgres://b3lb:password@postgres.example.com:5432/b3lb?sslmode=require"

# Socket connection
DATABASE_URL="postgres://b3lb:password@/b3lb?host=/var/run/postgresql"
```

**Connection Pooling**: Consider using pgbouncer for multiple frontend instances

---

### CELERY_BROKER_URL

**Purpose**: Celery task queue broker (Redis)

**Format**: `redis://[username:password@]host:port/db`

**Requirements**:
- Redis 5.0+
- Same Redis instance can be used for cache and broker
- Consider password protection in production

**Examples**:
```bash
# Local Redis (default database 0)
CELERY_BROKER_URL="redis://localhost:6379/0"

# Remote Redis with password
CELERY_BROKER_URL="redis://:password@redis.example.com:6379/0"

# Redis with username and password (Redis 6+)
CELERY_BROKER_URL="redis://user:password@redis.example.com:6379/0"

# Unix socket
CELERY_BROKER_URL="redis+socket:///var/run/redis/redis.sock?virtual_host=0"
```

---

### B3LB_API_BASE_DOMAIN

**Purpose**: Base domain for tenant API endpoints

**Format**: Domain name (without protocol or paths)

**Usage**: Used to construct tenant URLs

**Examples**:
```bash
# Wildcard DNS setup
B3LB_API_BASE_DOMAIN="bbb.example.com"
# Results in: acme.bbb.example.com, acme-5.bbb.example.com

# Subdomain
B3LB_API_BASE_DOMAIN="lb.bigbluebutton.org"
# Results in: acme.lb.bigbluebutton.org
```

---

## Optional Environment Variables

### Django Core Settings

#### DEBUG

**Purpose**: Enable Django debug mode

**Default**: `False`

**Values**: `True` | `False`

**Warning**: Never enable in production (security risk, performance impact)

```bash
DEBUG="False"
```

---

#### ALLOWED_HOSTS

**Purpose**: Allowed hostnames for HTTP Host header validation

**Default**: `[]` (empty, requires DEBUG=True)

**Format**: Comma-separated list of domains

**Security**: Prevents HTTP Host header attacks

```bash
ALLOWED_HOSTS="bbb.example.com,*.bbb.example.com,lb.example.com"
```

**Production**: Set to specific domains or use wildcard carefully

---

#### LANGUAGE_CODE

**Purpose**: Django admin interface language

**Default**: `en-us`

**Options**: Any Django-supported language code

```bash
LANGUAGE_CODE="en-us"  # English
LANGUAGE_CODE="de-de"  # German
LANGUAGE_CODE="fr-fr"  # French
LANGUAGE_CODE="es-es"  # Spanish
```

---

#### TIME_ZONE

**Purpose**: System timezone for date/time handling

**Default**: `UTC`

**Recommendation**: Use UTC for consistency, display local times in UI

```bash
TIME_ZONE="UTC"              # Recommended
TIME_ZONE="Europe/Berlin"    # Central European Time
TIME_ZONE="America/New_York" # Eastern Time
```

---

### Cache Configuration

#### CACHE_URL

**Purpose**: Django cache backend

**Default**: `locmemcache://b3lb-default-cache`

**Recommendation**: Use Redis for production (shared cache across instances)

**Examples**:
```bash
# Local memory cache (single instance only)
CACHE_URL="locmemcache://b3lb-cache"

# Redis cache (recommended)
CACHE_URL="redis://localhost:6379/1"

# Redis with password
CACHE_URL="redis://:password@redis.example.com:6379/1"

# Memcached
CACHE_URL="memcache://localhost:11211"
```

---

#### CACHEOPS_REDIS

**Purpose**: django-cacheops ORM caching backend

**Default**: `redis://redis/2`

**Usage**: Caches Django ORM queries automatically

**Examples**:
```bash
# Redis database 2 (separate from cache and broker)
CACHEOPS_REDIS="redis://localhost:6379/2"

# With password
CACHEOPS_REDIS="redis://:password@redis.example.com:6379/2"
```

---

#### CACHEOPS_DEGRADE_ON_FAILURE

**Purpose**: Gracefully degrade when Redis unavailable

**Default**: `True`

**Recommendation**: Keep enabled for availability

```bash
CACHEOPS_DEGRADE_ON_FAILURE="True"
```

**Behavior**: When enabled, falls back to database queries if Redis fails

---

### Frontend Server Configuration

#### WEB_CONCURRENCY

**Purpose**: Number of Uvicorn worker processes

**Default**: Auto-detected (CPU cores)

**Calculation**: Recommended = `(2 × CPU_cores) + 1`

**Examples**:
```bash
# Auto-detect (default)
# WEB_CONCURRENCY not set

# Manual override
WEB_CONCURRENCY="5"  # For 2-core system
WEB_CONCURRENCY="9"  # For 4-core system
```

**Considerations**:
- More workers = higher memory usage
- Balance with Celery worker count
- Monitor memory consumption

---

### B3LB Node Configuration

These settings customize how B3LB communicates with BBB nodes.

#### B3LB_NODE_PROTOCOL

**Purpose**: Default protocol for BBB nodes

**Default**: `https://`

**Options**: `https://` | `http://`

```bash
B3LB_NODE_PROTOCOL="https://"
```

---

#### B3LB_NODE_DEFAULT_DOMAIN

**Purpose**: Default domain suffix for node slugs

**Default**: `bbbconf.de`

**Usage**: If node domain not specified, uses `{slug}.{default_domain}`

```bash
B3LB_NODE_DEFAULT_DOMAIN="bbb.example.com"
```

---

#### B3LB_NODE_BBB_ENDPOINT

**Purpose**: BBB API path on nodes

**Default**: `bigbluebutton/api/`

**Usage**: Rarely needs changing

```bash
B3LB_NODE_BBB_ENDPOINT="bigbluebutton/api/"
```

---

#### B3LB_NODE_LOAD_ENDPOINT

**Purpose**: CPU load endpoint path on nodes

**Default**: `b3lb/load`

**Usage**: Path to b3lb-load script endpoint

```bash
B3LB_NODE_LOAD_ENDPOINT="b3lb/load"
```

---

#### B3LB_NODE_REQUEST_TIMEOUT

**Purpose**: HTTP timeout for node requests (seconds)

**Default**: `5`

**Recommendation**: Balance between responsiveness and reliability

```bash
B3LB_NODE_REQUEST_TIMEOUT="5"  # 5 seconds
B3LB_NODE_REQUEST_TIMEOUT="10" # More tolerant
```

---

### Recording Configuration

#### B3LB_RENDERING

**Purpose**: Enable recording rendering

**Default**: `False`

**Values**: `True` | `False`

```bash
B3LB_RENDERING="True"  # Enable rendering
B3LB_RENDERING="False" # Disable rendering
```

**Requirements**: Requires FFmpeg and rendering worker setup

---

#### B3LB_RECORD_STORAGE

**Purpose**: Recording file storage backend

**Default**: `local`

**Options**: `local` | `s3`

```bash
B3LB_RECORD_STORAGE="local"  # Local filesystem
B3LB_RECORD_STORAGE="s3"     # S3-compatible storage
```

---

#### B3LB_S3_ACCESS_KEY

**Purpose**: S3 access key (when B3LB_RECORD_STORAGE=s3)

**Required**: Only if using S3 storage

```bash
B3LB_S3_ACCESS_KEY="AKIAIOSFODNN7EXAMPLE"
```

---

#### B3LB_S3_SECRET_KEY

**Purpose**: S3 secret key (when B3LB_RECORD_STORAGE=s3)

**Required**: Only if using S3 storage

**Security**: Keep secret

```bash
B3LB_S3_SECRET_KEY="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
```

---

#### B3LB_S3_BUCKET_NAME

**Purpose**: S3 bucket name for recordings

**Required**: Only if using S3 storage

```bash
B3LB_S3_BUCKET_NAME="b3lb-recordings"
```

---

#### B3LB_S3_ENDPOINT_URL

**Purpose**: S3 endpoint URL (for non-AWS S3)

**Required**: Only for S3-compatible storage (MinIO, Ceph, etc.)

**Default**: Uses AWS S3 endpoints

```bash
# AWS S3 (omit or leave empty)
# B3LB_S3_ENDPOINT_URL=""

# MinIO
B3LB_S3_ENDPOINT_URL="https://minio.example.com:9000"

# Ceph
B3LB_S3_ENDPOINT_URL="https://ceph.example.com:8080"

# DigitalOcean Spaces
B3LB_S3_ENDPOINT_URL="https://nyc3.digitaloceanspaces.com"
```

---

#### B3LB_RECORD_PATH_HIERARCHY_WIDTH

**Purpose**: Number of characters per hierarchy level

**Default**: `2`

**Example**: With width=2, ID "abc123" becomes "ab/c1/23/"

```bash
B3LB_RECORD_PATH_HIERARCHY_WIDTH="2"
```

---

#### B3LB_RECORD_PATH_HIERARCHY_DEPHT

**Purpose**: Number of hierarchy depth levels

**Default**: `3`

**Example**: With depth=3, creates 3 directory levels

```bash
B3LB_RECORD_PATH_HIERARCHY_DEPHT="3"
```

**Combined Example**:
- Record ID: `abc123def456`
- Width: 2, Depth: 3
- Path: `ab/c1/23/abc123def456.mp4`

---

### Celery Task Queue Configuration

#### B3LB_TASK_QUEUE_CORE

**Purpose**: Queue name for core operations

**Default**: `b3lb`

```bash
B3LB_TASK_QUEUE_CORE="b3lb-core"
```

---

#### B3LB_TASK_QUEUE_HOUSEKEEPING

**Purpose**: Queue name for housekeeping tasks

**Default**: `b3lb`

```bash
B3LB_TASK_QUEUE_HOUSEKEEPING="b3lb-housekeeping"
```

---

#### B3LB_TASK_QUEUE_RECORD

**Purpose**: Queue name for recording tasks

**Default**: `b3lb`

```bash
B3LB_TASK_QUEUE_RECORD="b3lb-record"
```

---

#### B3LB_TASK_QUEUE_STATISTICS

**Purpose**: Queue name for statistics tasks

**Default**: `b3lb`

```bash
B3LB_TASK_QUEUE_STATISTICS="b3lb-stats"
```

**Queue Routing**: Separate queues allow dedicated workers for specific task types

**Example Multi-Queue Setup**:
```bash
# Environment
B3LB_TASK_QUEUE_CORE="core"
B3LB_TASK_QUEUE_RECORD="record"
B3LB_TASK_QUEUE_STATISTICS="stats"
B3LB_TASK_QUEUE_HOUSEKEEPING="housekeeping"

# Start specialized workers
celery -A loadbalancer worker -Q core -c 4
celery -A loadbalancer worker -Q record -c 2  # CPU-intensive
celery -A loadbalancer worker -Q stats -c 2
celery -A loadbalancer worker -Q housekeeping -c 1
```

---

## Configuration Profiles

### Development Profile

**Characteristics**: Debug mode, local services, minimal security

```bash
# Django
DEBUG="True"
SECRET_KEY="dev-secret-key-change-in-production"
ALLOWED_HOSTS="localhost,127.0.0.1"

# Database
DATABASE_URL="postgres://b3lb:b3lb@localhost:5432/b3lb_dev"

# Cache (local memory)
CACHE_URL="locmemcache://dev"

# Celery
CELERY_BROKER_URL="redis://localhost:6379/0"

# ORM Cache
CACHEOPS_REDIS="redis://localhost:6379/2"

# B3LB
B3LB_API_BASE_DOMAIN="localhost:8000"
B3LB_RENDERING="False"
```

---

### Production Profile

**Characteristics**: Security hardened, scalable, monitored

```bash
# Django
DEBUG="False"
SECRET_KEY="$(pwgen -ys 50 1)"  # Generate unique key
ALLOWED_HOSTS="bbb.example.com,*.bbb.example.com"
LANGUAGE_CODE="en-us"
TIME_ZONE="UTC"

# Database (with SSL)
DATABASE_URL="postgres://b3lb:${DB_PASSWORD}@postgres.example.com:5432/b3lb?sslmode=require"

# Cache (Redis cluster)
CACHE_URL="redis://:${REDIS_PASSWORD}@redis.example.com:6379/1"
CACHEOPS_REDIS="redis://:${REDIS_PASSWORD}@redis.example.com:6379/2"
CACHEOPS_DEGRADE_ON_FAILURE="True"

# Celery (with password)
CELERY_BROKER_URL="redis://:${REDIS_PASSWORD}@redis.example.com:6379/0"

# Frontend
WEB_CONCURRENCY="9"  # Adjust based on CPU

# B3LB Core
B3LB_API_BASE_DOMAIN="bbb.example.com"

# Node Configuration
B3LB_NODE_PROTOCOL="https://"
B3LB_NODE_REQUEST_TIMEOUT="5"

# Recording (S3)
B3LB_RENDERING="True"
B3LB_RECORD_STORAGE="s3"
B3LB_S3_ACCESS_KEY="${S3_ACCESS_KEY}"
B3LB_S3_SECRET_KEY="${S3_SECRET_KEY}"
B3LB_S3_BUCKET_NAME="b3lb-recordings-prod"
B3LB_S3_ENDPOINT_URL="https://s3.amazonaws.com"

# Task Queues (separated for scaling)
B3LB_TASK_QUEUE_CORE="core"
B3LB_TASK_QUEUE_HOUSEKEEPING="housekeeping"
B3LB_TASK_QUEUE_RECORD="record"
B3LB_TASK_QUEUE_STATISTICS="stats"
```

---

## Environment Variable Loading

### Docker Compose

**Method 1: env_file**
```yaml
services:
  frontend:
    image: quay.io/ibh/b3lb:3.3.2
    env_file:
      - .env
```

**.env file**:
```bash
SECRET_KEY=xyz123...
DATABASE_URL=postgres://...
```

**Method 2: environment**
```yaml
services:
  frontend:
    image: quay.io/ibh/b3lb:3.3.2
    environment:
      SECRET_KEY: ${SECRET_KEY}
      DATABASE_URL: ${DATABASE_URL}
```

---

### Kubernetes

**ConfigMap** (non-sensitive):
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: b3lb-config
data:
  DEBUG: "False"
  LANGUAGE_CODE: "en-us"
  B3LB_API_BASE_DOMAIN: "bbb.example.com"
```

**Secret** (sensitive):
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: b3lb-secrets
type: Opaque
stringData:
  SECRET_KEY: "xyz123..."
  DATABASE_URL: "postgres://..."
  CELERY_BROKER_URL: "redis://..."
```

**Deployment**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: b3lb-frontend
spec:
  template:
    spec:
      containers:
      - name: b3lb
        image: quay.io/ibh/b3lb:3.3.2
        envFrom:
        - configMapRef:
            name: b3lb-config
        - secretRef:
            name: b3lb-secrets
```

---

### Docker Swarm

**Stack file with secrets**:
```yaml
version: '3.8'

services:
  frontend:
    image: quay.io/ibh/b3lb:3.3.2
    environment:
      SECRET_KEY_FILE: /run/secrets/secret_key
      DATABASE_URL_FILE: /run/secrets/database_url
    secrets:
      - secret_key
      - database_url

secrets:
  secret_key:
    external: true
  database_url:
    external: true
```

**Create secrets**:
```bash
echo "xyz123..." | docker secret create secret_key -
echo "postgres://..." | docker secret create database_url -
```

---

## Configuration Validation

### Check Configuration

```bash
# Test database connection
./manage.py check --database default

# Validate settings
./manage.py check

# Test Celery broker
celery -A loadbalancer inspect ping
```

---

### Common Configuration Issues

#### Database Connection Failed

**Error**: `django.db.utils.OperationalError: could not connect to server`

**Causes**:
- Incorrect DATABASE_URL
- PostgreSQL not running
- Network/firewall issues
- Database doesn't exist

**Solutions**:
```bash
# Test connection
psql "$DATABASE_URL"

# Create database
createdb b3lb

# Check PostgreSQL status
systemctl status postgresql
```

---

#### Redis Connection Failed

**Error**: `redis.exceptions.ConnectionError: Error connecting to Redis`

**Causes**:
- Incorrect CELERY_BROKER_URL or CACHE_URL
- Redis not running
- Password required but not provided

**Solutions**:
```bash
# Test connection
redis-cli -h localhost -p 6379 -a password ping

# Check Redis status
systemctl status redis

# Test with Python
python -c "import redis; r=redis.from_url('$CELERY_BROKER_URL'); print(r.ping())"
```

---

#### Secret Key Not Set

**Error**: `django.core.exceptions.ImproperlyConfigured: The SECRET_KEY setting must not be empty`

**Solution**: Generate and set SECRET_KEY
```bash
export SECRET_KEY="$(pwgen -ys 50 1)"
```

---

#### Base Domain Not Set

**Error**: `B3LB_API_BASE_DOMAIN not configured`

**Solution**: Set base domain
```bash
export B3LB_API_BASE_DOMAIN="bbb.example.com"
```

---

## Security Best Practices

### Secret Management

1. **Never commit secrets to version control**
   - Use `.env` files (add to `.gitignore`)
   - Use environment variable injection
   - Use secret management tools (Vault, AWS Secrets Manager)

2. **Rotate secrets regularly**
   - SECRET_KEY: Annually or on compromise
   - Database passwords: Quarterly
   - API secrets: On-demand via secret2 field

3. **Use strong secrets**
   - Minimum 50 characters for SECRET_KEY
   - Complex passwords for databases
   - Random generation (not dictionary words)

4. **Limit secret access**
   - Restrict who can view secrets
   - Use role-based access control
   - Audit secret access

---

### Network Security

1. **Use TLS everywhere**
   - HTTPS for all public endpoints
   - TLS for database connections (sslmode=require)
   - TLS for Redis (redis+ssl://)

2. **Restrict admin access**
   - Use Traefik ACL for /admin/
   - IP whitelist for management interfaces
   - VPN for administrative access

3. **Firewall configuration**
   - Allow only necessary ports
   - Restrict database/Redis to internal network
   - Use security groups in cloud environments

---

## Next Steps

- [Docker Deployment](./05-docker-deployment.md): Deploy with these configurations
- [Operations](./08-operations.md): Monitor configuration in production
- [Development Guide](./07-development-guide.md): Local development setup
