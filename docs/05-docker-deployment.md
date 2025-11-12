# B3LB Docker Deployment

## Overview

B3LB is designed for containerized deployment using Docker. The project provides multiple Dockerfile variants optimized for different use cases and deployment scenarios.

## Docker Images

### Official Images

**Registry**: `quay.io/ibh/b3lb`

**Tags**:
- `latest`: Latest stable release
- `3.3.2`: Specific version
- `develop`: Development branch (unstable)

**Image Variants**:
1. **Standard** (`b3lb`): CPython-based, general purpose
2. **PyPy** (`b3lb-pypy`): PyPy-based, optimized for CPU-intensive tasks
3. **Static** (`b3lb-static`): Static file server (Caddy)
4. **Development** (`b3lb-dev`): Development tools included
5. **Render** (`b3lb-render`): Specialized for rendering operations

---

## Dockerfile Variants

### 1. Standard Dockerfile

**Location**: [docker/Dockerfile](../docker/Dockerfile)

**Base Image**: `python:3.12-slim`

**Purpose**: Main application image for frontend and celery workers

**Build Stages**:
1. **Build Stage**: Install dependencies, compile packages
2. **Runtime Stage**: Minimal runtime with compiled dependencies

**Key Features**:
- Multi-stage build for smaller image size
- Non-root user (`b3lb`, UID 8318)
- Optimized layer caching
- Production-ready

**Build**:
```bash
docker build -f docker/Dockerfile -t b3lb:latest .
```

**Image Size**: ~200-300 MB

**Use Cases**:
- Frontend (Uvicorn/ASGI)
- Celery workers (I/O-bound tasks)
- Celery Beat scheduler

---

### 2. PyPy Dockerfile

**Location**: [docker/Dockerfile.pypy](../docker/Dockerfile.pypy)

**Base Image**: `pypy:3.10-slim`

**Purpose**: CPU-intensive task processing (recording rendering)

**Key Features**:
- PyPy JIT compiler for faster execution
- Same structure as standard Dockerfile
- Higher memory requirements (~10GB allocated)

**Build**:
```bash
docker build -f docker/Dockerfile.pypy -t b3lb-pypy:latest .
```

**Image Size**: ~400-500 MB

**Performance**:
- 2-5x faster for CPU-intensive Python code
- Better for rendering, calculations, data processing
- Higher memory overhead for JIT compilation

**Use Cases**:
- Celery workers for recording rendering
- Celery workers for heavy data processing
- Statistics aggregation (if CPU-bound)

**Recommended Allocation**:
```yaml
resources:
  limits:
    memory: 10G
    cpu: 4
  reservations:
    memory: 8G
    cpu: 2
```

---

### 3. Static Assets Dockerfile

**Location**: [docker/Dockerfile.static](../docker/Dockerfile.static)

**Base Image**: `caddy:2.9.1-alpine`

**Purpose**: Serve Django static files (CSS, JS, images)

**Build Process**:
1. Use B3LB image to collect static files
2. Copy collected files to Caddy image
3. Configure Caddy server

**Build**:
```bash
docker build -f docker/Dockerfile.static -t b3lb-static:latest .
```

**Image Size**: ~50-100 MB

**Caddy Configuration**: Built-in, optimized for static content

**Use Cases**:
- Serving Django admin static files
- Serving application CSS/JS
- Optimized static content delivery

**Performance**: Much faster than Django serving static files

---

### 4. Development Dockerfile

**Location**: [docker/Dockerfile.dev](../docker/Dockerfile.dev)

**Purpose**: Development environment with additional tools

**Additional Features**:
- Development dependencies installed
- Debug tools included
- Hot reload support

**Build**:
```bash
docker build -f docker/Dockerfile.dev -t b3lb-dev:latest .
```

**Use Cases**:
- Local development
- Testing
- Debugging

**Not for Production**: Includes unnecessary dependencies

---

### 5. Render Dockerfile

**Location**: [docker/Dockerfile.render](../docker/Dockerfile.render)

**Purpose**: Specialized image for rendering operations

**Features**:
- FFmpeg installed
- Video processing libraries
- Rendering dependencies

**Build**:
```bash
docker build -f docker/Dockerfile.render -t b3lb-render:latest .
```

---

## Entrypoint Commands

The [docker/entrypoint.sh](../docker/entrypoint.sh) script provides multiple operational modes.

### Frontend Commands

#### uvicorn

**Purpose**: Run ASGI frontend server

**Command**:
```bash
docker run quay.io/ibh/b3lb:3.3.2 uvicorn --host 0.0.0.0 --ws none
```

**Behavior**:
- Runs database migrations automatically
- Starts Uvicorn ASGI server
- Binds to 0.0.0.0:8000
- WebSocket support disabled (--ws none)

**Workers**: Controlled by `WEB_CONCURRENCY` environment variable

**Use Case**: Main application frontend

---

#### gunicorn (Legacy)

**Purpose**: Run WSGI frontend server (deprecated)

**Command**:
```bash
docker run quay.io/ibh/b3lb:3.3.2 gunicorn
```

**Recommendation**: Use `uvicorn` instead for async support

---

### Celery Commands

#### celery-beat

**Purpose**: Run Celery scheduler for periodic tasks

**Command**:
```bash
docker run quay.io/ibh/b3lb:3.3.2 celery-beat
```

**Behavior**:
- Starts Celery Beat scheduler
- Reads schedule from database (django-celery-beat)
- Triggers periodic tasks

**Instances**: **Only one** Beat instance should run

**Use Case**: Task scheduling

---

#### celery-tasks

**Purpose**: Run Celery worker for background tasks

**Command**:
```bash
# All queues
docker run quay.io/ibh/b3lb:3.3.2 celery-tasks

# Specific queue
docker run quay.io/ibh/b3lb:3.3.2 celery-tasks -Q b3lb-core

# Multiple queues
docker run quay.io/ibh/b3lb:3.3.2 celery-tasks -Q b3lb-core,b3lb-stats
```

**Behavior**:
- Starts Celery worker
- Processes tasks from specified queues
- Auto-scales based on load

**Instances**: Scale horizontally as needed

**Concurrency**: Controlled by `-c` flag or default (CPU cores)

**Recommended Setup**:
```bash
# Core operations (CPython)
celery-tasks -Q b3lb-core -c 4

# Recording (PyPy for performance)
celery-tasks -Q b3lb-record -c 2

# Statistics (CPython)
celery-tasks -Q b3lb-stats -c 2

# Housekeeping (CPython)
celery-tasks -Q b3lb-housekeeping -c 1
```

---

#### celery-flower

**Purpose**: Run Celery monitoring UI

**Command**:
```bash
docker run -p 5555:5555 quay.io/ibh/b3lb:3.3.2 celery-flower
```

**Access**: http://localhost:5555

**Features**:
- Real-time task monitoring
- Worker status
- Task history
- Queue depths

**Security**: Restrict access (no built-in authentication)

---

### Management Commands

#### addnode

**Purpose**: Add BBB node via CLI

**Command**:
```bash
docker run quay.io/ibh/b3lb:3.3.2 addnode <slug> <domain> <secret> <cluster>
```

**Example**:
```bash
docker run quay.io/ibh/b3lb:3.3.2 addnode \
  bbb01 \
  bbb01.example.com \
  bbb_secret_key \
  main-cluster
```

---

#### addsecrets

**Purpose**: Generate tenant API secrets

**Command**:
```bash
docker run quay.io/ibh/b3lb:3.3.2 addsecrets <tenant_slug> <sub_id_range>
```

**Example**:
```bash
# Generate secrets 0-5 for tenant ACME
docker run quay.io/ibh/b3lb:3.3.2 addsecrets ACME 0-5
```

---

#### Additional Commands

- `meetingstats`: Dump meeting statistics
- `getloadvalues`: Show current node loads
- `gettenantsecrets`: Get secrets for tenant
- `listalltenantsecrets`: List all tenant secrets
- `static`: Serve static files via Python HTTP server (development only)

---

## Docker Compose Deployment

### Minimal Setup

**File**: `docker-compose.yml`

```yaml
version: '3.8'

services:
  # PostgreSQL Database
  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: b3lb
      POSTGRES_USER: b3lb
      POSTGRES_PASSWORD: ${DB_PASSWORD}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - b3lb

  # Redis Cache & Broker
  redis:
    image: redis:6.0.16-alpine
    command: redis-server --requirepass ${REDIS_PASSWORD}
    volumes:
      - redis_data:/data
    networks:
      - b3lb

  # B3LB Frontend
  frontend:
    image: quay.io/ibh/b3lb:3.3.2
    command: uvicorn --host 0.0.0.0 --ws none
    environment:
      SECRET_KEY: ${SECRET_KEY}
      DATABASE_URL: postgres://b3lb:${DB_PASSWORD}@postgres:5432/b3lb
      CELERY_BROKER_URL: redis://:${REDIS_PASSWORD}@redis:6379/0
      CACHE_URL: redis://:${REDIS_PASSWORD}@redis:6379/1
      CACHEOPS_REDIS: redis://:${REDIS_PASSWORD}@redis:6379/2
      B3LB_API_BASE_DOMAIN: ${BASE_DOMAIN}
    depends_on:
      - postgres
      - redis
    networks:
      - b3lb
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.b3lb.rule=Host(`${BASE_DOMAIN}`) || Host(`{subdomain:[a-z0-9-]+}.${BASE_DOMAIN}`)"
      - "traefik.http.services.b3lb.loadbalancer.server.port=8000"

  # Static Files
  static:
    image: quay.io/ibh/b3lb-static:3.3.2
    networks:
      - b3lb
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.static.rule=Host(`${BASE_DOMAIN}`) && PathPrefix(`/static/`)"

  # Celery Beat
  celery-beat:
    image: quay.io/ibh/b3lb:3.3.2
    command: celery-beat
    environment:
      SECRET_KEY: ${SECRET_KEY}
      DATABASE_URL: postgres://b3lb:${DB_PASSWORD}@postgres:5432/b3lb
      CELERY_BROKER_URL: redis://:${REDIS_PASSWORD}@redis:6379/0
      CACHEOPS_REDIS: redis://:${REDIS_PASSWORD}@redis:6379/2
    depends_on:
      - postgres
      - redis
    networks:
      - b3lb

  # Celery Workers
  celery-worker:
    image: quay.io/ibh/b3lb:3.3.2
    command: celery-tasks -Q b3lb
    environment:
      SECRET_KEY: ${SECRET_KEY}
      DATABASE_URL: postgres://b3lb:${DB_PASSWORD}@postgres:5432/b3lb
      CELERY_BROKER_URL: redis://:${REDIS_PASSWORD}@redis:6379/0
      CACHEOPS_REDIS: redis://:${REDIS_PASSWORD}@redis:6379/2
    depends_on:
      - postgres
      - redis
    networks:
      - b3lb
    deploy:
      replicas: 3

networks:
  b3lb:
    driver: bridge

volumes:
  postgres_data:
  redis_data:
```

**.env file**:
```bash
SECRET_KEY=your-secret-key-here
DB_PASSWORD=your-db-password
REDIS_PASSWORD=your-redis-password
BASE_DOMAIN=bbb.example.com
```

**Start**:
```bash
docker-compose up -d
```

---

### Production Setup with Traefik

**File**: `docker-compose.prod.yml`

```yaml
version: '3.8'

services:
  # Traefik Reverse Proxy
  traefik:
    image: traefik:v2.10
    command:
      - "--api.dashboard=true"
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.letsencrypt.acme.dnschallenge=true"
      - "--certificatesresolvers.letsencrypt.acme.dnschallenge.provider=rfc2136"
      - "--certificatesresolvers.letsencrypt.acme.email=${ACME_EMAIL}"
      - "--certificatesresolvers.letsencrypt.acme.storage=/letsencrypt/acme.json"
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - traefik_certs:/letsencrypt
    environment:
      RFC2136_NAMESERVER: ${RFC2136_NAMESERVER}
      RFC2136_TSIG_ALGORITHM: ${RFC2136_TSIG_ALGORITHM}
      RFC2136_TSIG_KEY: ${RFC2136_TSIG_KEY}
      RFC2136_TSIG_SECRET: ${RFC2136_TSIG_SECRET}
    networks:
      - b3lb
    labels:
      # Dashboard
      - "traefik.enable=true"
      - "traefik.http.routers.dashboard.rule=Host(`traefik.${BASE_DOMAIN}`)"
      - "traefik.http.routers.dashboard.service=api@internal"
      - "traefik.http.routers.dashboard.middlewares=auth"
      - "traefik.http.middlewares.auth.basicauth.users=${TRAEFIK_BASIC_AUTH}"

  # PostgreSQL
  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: b3lb
      POSTGRES_USER: b3lb
      POSTGRES_PASSWORD: ${DB_PASSWORD}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - b3lb

  # Redis
  redis:
    image: redis:6.0.16-alpine
    command: redis-server --requirepass ${REDIS_PASSWORD} --maxmemory 2gb --maxmemory-policy allkeys-lru
    volumes:
      - redis_data:/data
    networks:
      - b3lb

  # B3LB Frontend (Multiple Instances)
  frontend:
    image: quay.io/ibh/b3lb:3.3.2
    command: uvicorn --host 0.0.0.0 --ws none
    environment:
      DEBUG: "False"
      SECRET_KEY: ${SECRET_KEY}
      DATABASE_URL: postgres://b3lb:${DB_PASSWORD}@postgres:5432/b3lb
      CELERY_BROKER_URL: redis://:${REDIS_PASSWORD}@redis:6379/0
      CACHE_URL: redis://:${REDIS_PASSWORD}@redis:6379/1
      CACHEOPS_REDIS: redis://:${REDIS_PASSWORD}@redis:6379/2
      B3LB_API_BASE_DOMAIN: ${BASE_DOMAIN}
      WEB_CONCURRENCY: "5"
      ALLOWED_HOSTS: "${BASE_DOMAIN},*.${BASE_DOMAIN}"
    depends_on:
      - postgres
      - redis
    networks:
      - b3lb
    deploy:
      replicas: 3
      resources:
        limits:
          memory: 2G
        reservations:
          memory: 1G
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.b3lb.rule=Host(`${BASE_DOMAIN}`) || Host(`{subdomain:[a-z0-9-]+}.${BASE_DOMAIN}`)"
      - "traefik.http.routers.b3lb.entrypoints=websecure"
      - "traefik.http.routers.b3lb.tls=true"
      - "traefik.http.routers.b3lb.tls.certresolver=letsencrypt"
      - "traefik.http.routers.b3lb.tls.domains[0].main=${BASE_DOMAIN}"
      - "traefik.http.routers.b3lb.tls.domains[0].sans=*.${BASE_DOMAIN}"
      - "traefik.http.services.b3lb.loadbalancer.server.port=8000"

  # Static Files
  static:
    image: quay.io/ibh/b3lb-static:3.3.2
    networks:
      - b3lb
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.static.rule=Host(`${BASE_DOMAIN}`) && PathPrefix(`/static/`)"
      - "traefik.http.routers.static.entrypoints=websecure"
      - "traefik.http.routers.static.tls=true"

  # Celery Beat (Single Instance)
  celery-beat:
    image: quay.io/ibh/b3lb:3.3.2
    command: celery-beat
    environment:
      SECRET_KEY: ${SECRET_KEY}
      DATABASE_URL: postgres://b3lb:${DB_PASSWORD}@postgres:5432/b3lb
      CELERY_BROKER_URL: redis://:${REDIS_PASSWORD}@redis:6379/0
      CACHEOPS_REDIS: redis://:${REDIS_PASSWORD}@redis:6379/2
    depends_on:
      - postgres
      - redis
    networks:
      - b3lb
    deploy:
      replicas: 1

  # Celery Workers (Core)
  celery-core:
    image: quay.io/ibh/b3lb:3.3.2
    command: celery-tasks -Q b3lb-core -c 4
    environment:
      SECRET_KEY: ${SECRET_KEY}
      DATABASE_URL: postgres://b3lb:${DB_PASSWORD}@postgres:5432/b3lb
      CELERY_BROKER_URL: redis://:${REDIS_PASSWORD}@redis:6379/0
      CACHEOPS_REDIS: redis://:${REDIS_PASSWORD}@redis:6379/2
    depends_on:
      - postgres
      - redis
    networks:
      - b3lb
    deploy:
      replicas: 3
      resources:
        limits:
          memory: 1G

  # Celery Workers (Recording) - PyPy
  celery-record:
    image: quay.io/ibh/b3lb-pypy:3.3.2
    command: celery-tasks -Q b3lb-record -c 2
    environment:
      SECRET_KEY: ${SECRET_KEY}
      DATABASE_URL: postgres://b3lb:${DB_PASSWORD}@postgres:5432/b3lb
      CELERY_BROKER_URL: redis://:${REDIS_PASSWORD}@redis:6379/0
      CACHEOPS_REDIS: redis://:${REDIS_PASSWORD}@redis:6379/2
      B3LB_RENDERING: "True"
      B3LB_RECORD_STORAGE: "s3"
      B3LB_S3_ACCESS_KEY: ${S3_ACCESS_KEY}
      B3LB_S3_SECRET_KEY: ${S3_SECRET_KEY}
      B3LB_S3_BUCKET_NAME: ${S3_BUCKET_NAME}
    depends_on:
      - postgres
      - redis
    networks:
      - b3lb
    deploy:
      replicas: 2
      resources:
        limits:
          memory: 10G
          cpus: '4'
        reservations:
          memory: 8G
          cpus: '2'

networks:
  b3lb:
    driver: bridge

volumes:
  postgres_data:
  redis_data:
  traefik_certs:
```

---

## Kubernetes Deployment

### Basic Deployment

**Frontend Deployment**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: b3lb-frontend
  labels:
    app: b3lb
    component: frontend
spec:
  replicas: 3
  selector:
    matchLabels:
      app: b3lb
      component: frontend
  template:
    metadata:
      labels:
        app: b3lb
        component: frontend
    spec:
      containers:
      - name: b3lb
        image: quay.io/ibh/b3lb:3.3.2
        command: ["uvicorn", "--host", "0.0.0.0", "--ws", "none"]
        ports:
        - containerPort: 8000
        envFrom:
        - configMapRef:
            name: b3lb-config
        - secretRef:
            name: b3lb-secrets
        resources:
          requests:
            memory: "1Gi"
            cpu: "500m"
          limits:
            memory: "2Gi"
            cpu: "2"
        livenessProbe:
          httpGet:
            path: /b3lb/ping
            port: 8000
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /b3lb/ping
            port: 8000
          initialDelaySeconds: 10
          periodSeconds: 5
```

**Service**:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: b3lb-frontend
spec:
  selector:
    app: b3lb
    component: frontend
  ports:
  - protocol: TCP
    port: 8000
    targetPort: 8000
  type: ClusterIP
```

**Celery Beat**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: b3lb-celery-beat
spec:
  replicas: 1  # Only one Beat instance
  selector:
    matchLabels:
      app: b3lb
      component: celery-beat
  template:
    metadata:
      labels:
        app: b3lb
        component: celery-beat
    spec:
      containers:
      - name: celery-beat
        image: quay.io/ibh/b3lb:3.3.2
        command: ["celery-beat"]
        envFrom:
        - configMapRef:
            name: b3lb-config
        - secretRef:
            name: b3lb-secrets
        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "500m"
```

**Celery Workers**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: b3lb-celery-worker
spec:
  replicas: 5
  selector:
    matchLabels:
      app: b3lb
      component: celery-worker
  template:
    metadata:
      labels:
        app: b3lb
        component: celery-worker
    spec:
      containers:
      - name: celery-worker
        image: quay.io/ibh/b3lb:3.3.2
        command: ["celery-tasks", "-Q", "b3lb", "-c", "4"]
        envFrom:
        - configMapRef:
            name: b3lb-config
        - secretRef:
            name: b3lb-secrets
        resources:
          requests:
            memory: "512Mi"
            cpu: "500m"
          limits:
            memory: "1Gi"
            cpu: "2"
```

---

## Health Checks

### Docker Compose

```yaml
services:
  frontend:
    image: quay.io/ibh/b3lb:3.3.2
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/b3lb/ping"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
```

### Kubernetes

```yaml
livenessProbe:
  httpGet:
    path: /b3lb/ping
    port: 8000
  initialDelaySeconds: 30
  periodSeconds: 10

readinessProbe:
  httpGet:
    path: /b3lb/ping
    port: 8000
  initialDelaySeconds: 10
  periodSeconds: 5
```

---

## Resource Recommendations

### Small Deployment (10-20 nodes)

| Service | Replicas | CPU | Memory |
|---------|----------|-----|--------|
| Frontend | 2 | 1 core | 1 GB |
| Celery Worker | 2 | 1 core | 1 GB |
| Celery Beat | 1 | 0.5 core | 512 MB |
| PostgreSQL | 1 | 2 cores | 4 GB |
| Redis | 1 | 1 core | 2 GB |

**Total**: ~6 cores, ~15 GB RAM

---

### Medium Deployment (50-100 nodes)

| Service | Replicas | CPU | Memory |
|---------|----------|-----|--------|
| Frontend | 3 | 2 cores | 2 GB |
| Celery Worker | 5 | 2 cores | 1 GB |
| Celery Beat | 1 | 0.5 core | 512 MB |
| PostgreSQL | 1 | 4 cores | 8 GB |
| Redis | 1 | 2 cores | 4 GB |

**Total**: ~20 cores, ~40 GB RAM

---

### Large Deployment (100+ nodes)

| Service | Replicas | CPU | Memory |
|---------|----------|-----|--------|
| Frontend | 5 | 2 cores | 2 GB |
| Celery Worker (Core) | 8 | 2 cores | 1 GB |
| Celery Worker (Record, PyPy) | 3 | 4 cores | 10 GB |
| Celery Beat | 1 | 0.5 core | 512 MB |
| PostgreSQL | 1 | 8 cores | 16 GB |
| Redis | 1 | 4 cores | 8 GB |

**Total**: ~50 cores, ~100 GB RAM

---

## Scaling Strategies

### Horizontal Scaling

**Frontend**: Scale based on request rate
```bash
docker-compose up --scale frontend=5
# or
kubectl scale deployment b3lb-frontend --replicas=5
```

**Celery Workers**: Scale based on queue depth
```bash
docker-compose up --scale celery-worker=8
```

### Vertical Scaling

**Database**: Increase PostgreSQL resources
```yaml
resources:
  limits:
    memory: 16G
    cpu: 8
```

**Redis**: Increase max memory
```bash
redis-server --maxmemory 8gb
```

---

## Monitoring

### Container Health

```bash
# Docker Compose
docker-compose ps

# Check logs
docker-compose logs -f frontend

# Kubernetes
kubectl get pods
kubectl logs -f deployment/b3lb-frontend
```

### Application Metrics

Access Prometheus metrics:
```
https://bbb.example.com/b3lb/metrics
```

Configure Prometheus scraping:
```yaml
scrape_configs:
  - job_name: 'b3lb'
    static_configs:
      - targets: ['frontend:8000']
    metrics_path: '/b3lb/metrics'
```

---

## Backup & Recovery

### Database Backup

```bash
# Automated backup
docker exec postgres pg_dump -U b3lb b3lb | gzip > b3lb-$(date +%Y%m%d).sql.gz

# Kubernetes
kubectl exec deployment/postgres -- pg_dump -U b3lb b3lb | gzip > backup.sql.gz
```

### Database Restore

```bash
# Docker
gunzip < backup.sql.gz | docker exec -i postgres psql -U b3lb b3lb

# Kubernetes
gunzip < backup.sql.gz | kubectl exec -i deployment/postgres -- psql -U b3lb b3lb
```

---

## Troubleshooting

### Container Logs

```bash
# All services
docker-compose logs

# Specific service
docker-compose logs frontend

# Follow logs
docker-compose logs -f --tail=100 celery-worker
```

### Database Connection Issues

```bash
# Test connection
docker-compose exec frontend python manage.py check --database default

# Enter PostgreSQL
docker-compose exec postgres psql -U b3lb
```

### Celery Issues

```bash
# Check Celery status
docker-compose exec celery-worker celery -A loadbalancer inspect ping

# Active tasks
docker-compose exec celery-worker celery -A loadbalancer inspect active

# Queue status
docker-compose exec celery-worker celery -A loadbalancer inspect stats
```

---

## Next Steps

- [Configuration](./04-configuration.md): Environment variable setup
- [Celery Tasks](./06-celery-tasks.md): Background job configuration
- [Operations](./08-operations.md): Monitoring and maintenance
