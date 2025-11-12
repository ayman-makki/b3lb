# B3LB Architecture

## System Architecture Overview

B3LB is designed as a multi-layered, scalable architecture with clear separation between frontend request handling, background processing, data persistence, and external BBB node communication.

## Architecture Layers

### Layer 1: Reverse Proxy (Traefik)

**Purpose**: SSL termination, access control, load balancing

**Key Responsibilities**:
- ACME DNS-01 challenge for wildcard SSL certificates
- ACL-based access control for admin and metrics endpoints
- Round-robin load balancing across frontend instances
- Request routing based on domain/path
- HTTP/HTTPS traffic management

**Configuration**:
```yaml
Traefik Router Rules:
  - Host wildcard: *.{base_domain}
  - Path-based: /b3lb/t/{tenant}/
  - Admin ACL: IP whitelist for /admin/
  - Metrics ACL: IP whitelist for /b3lb/metrics
```

### Layer 2: Application Frontend (Uvicorn/ASGI)

**Purpose**: HTTP request handling, BBB API implementation

**Key Characteristics**:
- **Server**: Uvicorn ASGI server
- **Concurrency**: Async/await throughout
- **Scaling**: Horizontal (multiple instances)
- **State**: Stateless (all state in database/Redis)

**Request Processing Flow**:
```
1. Receive HTTP request
2. Extract tenant from domain/path
3. Validate API checksum
4. Resolve tenant → secret → cluster group
5. Execute BBB API operation:
   - create: Select node via load algorithm
   - join: Resolve meeting → node
   - getMeetings: Return cached data
   - recordings: Query database
6. Proxy to BBB node (async) or return data
7. Return response to client
```

**Key Components**:
- Django views with async support
- aiohttp for async HTTP requests
- ClientB3lbRequest class (main API handler)
- Tenant/secret resolution middleware
- Checksum validation

### Layer 3: Background Processing (Celery)

**Purpose**: Asynchronous task execution

**Architecture**:
```
Celery Beat (Scheduler)
    ↓
Task Queues (4 queues)
    ↓
Celery Workers (Multiple instances)
    ↓
Database/External APIs
```

**Task Queues**:
1. **b3lb-core**: Node polling, meeting list updates
2. **b3lb-housekeeping**: Data cleanup, old record removal
3. **b3lb-record**: Recording rendering and processing
4. **b3lb-statistics**: Metrics aggregation

**Worker Types**:
- **CPython Workers**: Standard tasks, 512MB-1GB RAM
- **PyPy Workers**: CPU-intensive tasks, 8-10GB RAM (faster execution)

**Periodic Tasks** (from Celery Beat):
- Update meeting lists (every 30s-1m)
- Check node status (every 1m)
- Update statistics (every 5m)
- Render recordings (continuous)
- Housekeeping cleanup (daily)

### Layer 4: Caching Layer (Redis)

**Purpose**: Performance optimization, task brokering

**Three Redis Functions**:

1. **Cache Backend** (django-redis)
   - Django cache framework
   - Session storage (optional)
   - General-purpose caching

2. **ORM Cache** (django-cacheops)
   - Query result caching
   - Model instance caching
   - Automatic invalidation

3. **Celery Broker**
   - Task queue management
   - Result backend (django-celery-results)
   - Worker coordination

**Cache Strategy**:
```python
# Meeting lists cached per tenant
cache_key = f"meeting_list_{secret_id}"
ttl = 60 seconds

# Node status cached
cache_key = f"node_status_{node_id}"
ttl = 60 seconds

# Metrics cached per tenant
cache_key = f"metrics_{tenant_slug}"
ttl = 30 seconds
```

### Layer 5: Data Persistence (PostgreSQL)

**Purpose**: Primary data store

**Data Categories**:

1. **Configuration Data**:
   - Clusters, nodes, tenants
   - Secrets, parameters, assets
   - Load factors, limits

2. **Operational Data**:
   - Active meetings
   - Node status
   - Cached meeting lists

3. **Historical Data**:
   - Recordings (metadata)
   - Statistics
   - Metrics

4. **Binary Assets** (via django-db-file-storage):
   - Tenant logos
   - Custom slides
   - Custom CSS

**Database Optimization**:
- Indexes on foreign keys
- Composite indexes for common queries
- django-cacheops for ORM caching
- Connection pooling

### Layer 6: Static Assets (Caddy)

**Purpose**: Serve static files (CSS, JavaScript, images)

**Architecture**:
- Separate Caddy container
- Django collectstatic output
- Optimized for static content delivery
- Caching headers configured

**Static Files**:
- Django admin CSS/JS
- Application static assets
- Collected from installed apps

### Layer 7: File Storage (S3/Local)

**Purpose**: Recording file storage

**Storage Options**:

1. **S3-Compatible Storage** (recommended for scale):
   - AWS S3, MinIO, Ceph
   - Hierarchical path structure
   - Configurable bucket and endpoint

2. **Local Filesystem**:
   - Direct disk storage
   - Hierarchical directory structure
   - Suitable for smaller deployments

**File Hierarchy**:
```
/recordings/
  ├── aa/
  │   ├── ab/
  │   │   ├── ac/
  │   │   │   └── {record_id}.{ext}
```

Hierarchy depth and width configurable via:
- `B3LB_RECORD_PATH_HIERARCHY_WIDTH`: 2 (default)
- `B3LB_RECORD_PATH_HIERARCHY_DEPHT`: 3 (default)

## Load Balancing Algorithm

### Multi-Factor Load Calculation

B3LB uses a sophisticated load calculation to distribute meetings across nodes intelligently.

**Formula**:
```python
node_load = (
    (attendees × load_a_factor) +
    (meetings × load_m_factor) +
    synthetic_cpu_load
)
```

**Factors**:
- `load_a_factor`: Weight per attendee (default: 1.0)
- `load_m_factor`: Weight per meeting (default: 10.0)
- `synthetic_cpu_load`: Polynomial CPU calculation

### Synthetic CPU Load Calculation

**Purpose**: Emphasize CPU load non-linearly to prevent overload

**Algorithm**: Taylor polynomial series
```python
def calculate_cpu_load(cpu_percent, iterations=6, max_load=5000):
    result = 0
    for i in range(1, iterations + 1):
        result += (cpu_percent ** i) / factorial(i)
    return min(result, max_load)
```

**Characteristics**:
- Low CPU (0-50%): Minimal load contribution
- Medium CPU (50-70%): Moderate load increase
- High CPU (70-90%): Steep load increase
- Critical CPU (90%+): Approaches max_load (5000)

**Configuration** (per cluster):
- `load_cpu_series_iteratations`: 6 (default)
- `load_cpu_maximum`: 5000 (default)

### Node Selection Logic

```python
def select_node(tenant):
    cluster_group = tenant.clustergroup
    eligible_nodes = []

    for node in cluster_group.all_nodes():
        if node.load == -2:  # Maintenance mode
            continue
        if node.load == -1:  # Has errors
            continue
        eligible_nodes.append((node, node.load))

    if not eligible_nodes:
        raise NoNodesAvailableError

    # Select node with minimum load
    selected_node = min(eligible_nodes, key=lambda x: x[1])[0]
    return selected_node
```

**Special Load Values**:
- `-2`: Maintenance mode (excluded from selection)
- `-1`: Node has errors (excluded from selection)
- `0+`: Normal operation (selected based on lowest value)

## Multi-Tenant Architecture

### Tenant Isolation

**URL-Based Tenant Resolution**:

1. **Wildcard DNS Method**:
   ```
   {tenant}.bbb.example.com → Tenant "TENANT"
   {tenant}-5.bbb.example.com → Tenant "TENANT", sub-secret 5
   ```

2. **Path-Based Method**:
   ```
   bbb.example.com/b3lb/t/{tenant}/ → Tenant "{tenant}"
   bbb.example.com/b3lb/t/{tenant}-5/ → Tenant "{tenant}", sub-secret 5
   ```

**Resolution Process**:
```python
1. Extract tenant slug from request (domain or path)
2. Query Tenant model by slug
3. Extract sub_id if present (0-999)
4. Query Secret model by tenant + sub_id
5. Validate API checksum using secret
6. Return tenant context for request
```

### Per-Tenant Configuration

**Cluster Assignment**:
- Each tenant assigned to ClusterGroup
- ClusterGroup contains multiple Clusters
- Each Cluster contains multiple Nodes
- Tenant requests routed only to assigned nodes

**Limits**:
- `attendee_limit`: Max concurrent attendees per tenant
- `meeting_limit`: Max concurrent meetings per tenant
- Per-secret override of tenant limits

**Customization**:
- **Logo**: Custom logo in BBB interface
- **Slide**: Default presentation slide
- **CSS**: Custom CSS for branding
- All stored in database via django-db-file-storage

**Parameters**:
- Per-tenant BBB parameter customization
- Three modes:
  - `BLOCK`: Remove parameter from BBB request
  - `SET`: Add parameter if not present
  - `OVERRIDE`: Force parameter value

### Secret Management

**Structure**:
- Each tenant has 1-1000 secrets (sub_id 0-999)
- Primary secret (sub_id=0)
- Additional secrets for API key rotation
- Each secret can override tenant limits

**Secret Properties**:
```python
class Secret:
    tenant: ForeignKey(Tenant)
    sub_id: IntegerField(0-999)
    secret: CharField(64)      # API secret
    secret2: CharField(64)     # Rollover secret

    # Optional overrides
    attendee_limit: IntegerField(null=True)
    meeting_limit: IntegerField(null=True)
    slide_id: IntegerField(null=True)
    record_by_default: BooleanField(null=True)
```

**URL Generation**:
```python
def get_endpoint_url(secret):
    if sub_id == 0:
        return f"https://{tenant.slug}.{base_domain}/bigbluebutton/api/"
    else:
        return f"https://{tenant.slug}-{sub_id}.{base_domain}/bigbluebutton/api/"
```

## Data Flow Diagrams

### Create Meeting Flow

```
Client
  ↓ POST /bigbluebutton/api/create
Frontend (Uvicorn)
  ↓ 1. Resolve tenant from domain/path
  ↓ 2. Validate checksum
  ↓ 3. Check tenant limits
  ↓ 4. Select node via load algorithm
  ↓ 5. Create Meeting record in DB
  ↓ 6. Async HTTP POST to selected BBB node
  ↓ 7. Parse BBB response
  ↓ 8. Return response to client
Client
```

### Join Meeting Flow

```
Client
  ↓ GET /bigbluebutton/api/join
Frontend (Uvicorn)
  ↓ 1. Resolve tenant from domain/path
  ↓ 2. Validate checksum
  ↓ 3. Query Meeting record from DB
  ↓ 4. Get node assignment
  ↓ 5. Build redirect URL to BBB node
  ↓ 6. Return redirect response
Client
  ↓ Redirect to BBB node
BBB Node
```

### Get Meetings Flow (Cached)

```
Client
  ↓ GET /bigbluebutton/api/getMeetings
Frontend (Uvicorn)
  ↓ 1. Resolve tenant from domain/path
  ↓ 2. Validate checksum
  ↓ 3. Check Redis cache for meeting list
  ↓ 4a. Cache HIT → Return cached XML
  ↓ 4b. Cache MISS → Query DB for SecretMeetingList
Client
```

### Background Node Polling

```
Celery Beat
  ↓ Trigger: update_secrets_lists (every 30s-1m)
Task Queue
  ↓ Spawn per-secret tasks
Celery Workers
  ↓ For each secret:
  ↓   1. Query BBB nodes for getMeetings
  ↓   2. Aggregate responses
  ↓   3. Update Meeting records in DB
  ↓   4. Cache meeting list in Redis
  ↓   5. Update metrics
Database + Redis
```

### Recording Upload & Render Flow

```
BBB Node
  ↓ Meeting ends, recording archived
  ↓ Post-archive hook: b3lb-push-hook.rb
  ↓ Upload recording.tar to B3LB
B3LB Frontend
  ↓ Receive upload, create RecordSet
  ↓ Status: UPLOADED
  ↓ Queue render task
Celery Worker (PyPy)
  ↓ 1. Extract recording.tar
  ↓ 2. Parse metadata.xml
  ↓ 3. For each RecordProfile:
  ↓   - Run ffmpeg rendering
  ↓   - Create Record object
  ↓   - Upload to S3/local storage
  ↓ 4. Update RecordSet status: RENDERED
Database + S3
```

## Component Interactions

### Frontend ↔ Database

**Read Operations**:
- Tenant/Secret lookup (cached via cacheops)
- Meeting queries (join, isMeetingRunning)
- Recording metadata (getRecordings)
- Cluster/Node configuration

**Write Operations**:
- Create Meeting records (create API)
- Update meeting participant counts (background)
- Delete recordings (deleteRecordings API)
- Update recording metadata (updateRecordings API)

### Frontend ↔ Redis

**Cache Reads**:
- Meeting lists (getMeetings API)
- Metrics (stats/metrics endpoints)
- Node status

**Cache Writes**:
- Update meeting lists (background tasks)
- Update metrics (background tasks)

### Frontend ↔ BBB Nodes

**Synchronous Operations** (via aiohttp):
- create: Proxy create request to selected node
- end: Proxy end request to meeting's node
- Node-specific operations

**Asynchronous Operations** (via Celery):
- getMeetings polling (background)
- Load endpoint polling (background)
- Health checks (background)

### Celery ↔ Database

**Task Operations**:
- Query nodes for polling
- Update Meeting records
- Create/update Metric records
- Process RecordSet/Record objects
- Cleanup old data

### Celery ↔ BBB Nodes

**Polling Operations**:
- GET /bigbluebutton/api/getMeetings (every 30s-1m)
- GET /b3lb/load (every 1m)
- Health check requests

### Celery ↔ S3/Storage

**File Operations**:
- Upload rendered recordings
- Download recordings for processing
- Delete old recordings

## Scaling Strategies

### Horizontal Scaling

**Frontend Instances**:
- Stateless design enables easy horizontal scaling
- Traefik load balancing across instances
- Scale based on request rate
- Recommended: 2-5 instances for 100+ nodes

**Celery Workers**:
- Scale workers based on queue depth
- Different worker types for different queues
- CPython for I/O-bound tasks
- PyPy for CPU-bound tasks (rendering)
- Recommended: 3-10 workers for 100+ nodes

**Redis**:
- Single Redis instance usually sufficient
- Redis Cluster for extreme scale (1000+ nodes)
- Sentinel for high availability

**PostgreSQL**:
- Single primary usually sufficient
- Read replicas for reporting/analytics
- Connection pooling (pgbouncer) for many frontends

### Vertical Scaling

**Frontend**:
- `WEB_CONCURRENCY`: Control Uvicorn workers per instance
- Default: Auto-detected based on CPU cores
- Increase for CPU-bound operations

**Celery Workers**:
- Concurrency per worker (default: CPU cores)
- PyPy workers: Allocate 8-10GB RAM
- CPython workers: 512MB-1GB RAM

**Database**:
- Increase PostgreSQL shared_buffers
- Tune work_mem for complex queries
- Optimize connection pool size

## High Availability

### Failure Scenarios

**Frontend Instance Failure**:
- Traefik detects health check failure
- Removes instance from load balancer pool
- Remaining instances handle traffic
- No data loss (stateless)

**Celery Worker Failure**:
- Celery broker requeues unacknowledged tasks
- Other workers pick up tasks
- Task retry mechanism handles transient failures
- No data loss (tasks persisted in Redis)

**Redis Failure**:
- Frontend continues with degraded performance
- ORM cache degradation enabled (cacheops)
- Celery tasks queued in memory temporarily
- Cache rebuilt on Redis recovery

**PostgreSQL Failure**:
- Critical failure (service unavailable)
- Requires database recovery
- Consider PostgreSQL replication for HA

**BBB Node Failure**:
- Node marked with has_errors flag
- Excluded from load balancing
- Periodic health checks detect recovery
- Automatic reintegration on recovery

### Health Monitoring

**Endpoints**:
- `/b3lb/ping`: Basic health check
- `/b3lb/stats`: System statistics
- `/b3lb/metrics`: Prometheus metrics

**Metrics to Monitor**:
- Node status (up/down/maintenance)
- Meeting counts per tenant/node
- Attendee counts per tenant/node
- API response times
- Celery queue depths
- Redis hit/miss ratios
- Database connection pool usage

## Security Considerations

### Authentication

**API Checksum Validation**:
- All BBB API calls require valid checksum
- Checksum = SHA256(call_name + parameters + secret)
- Prevents unauthorized API access
- Secret rotation via secret2 field

### Access Control

**Admin Interface**:
- Django admin authentication required
- Traefik ACL restricts by IP (recommended)
- Strong password policy recommended

**Metrics Endpoint**:
- Traefik ACL restricts by IP (recommended)
- Consider authentication for Prometheus scraper

### Data Protection

**Secrets Storage**:
- API secrets stored hashed in database (consider)
- Environment variables for system secrets
- No secrets in logs

**Recording Files**:
- Access via nonce (unguessable URLs)
- Published/unlisted flag for privacy
- Automatic deletion based on retention policy

### Network Security

**Traefik Configuration**:
- HTTPS only (no HTTP)
- Wildcard SSL certificates
- Modern TLS versions only
- HSTS headers recommended

**BBB Node Communication**:
- HTTPS for all node requests
- Timeout configurations prevent hanging
- Certificate validation enabled

## Performance Characteristics

### Latency Targets

**API Operations**:
- `create`: < 200ms (p95)
- `join`: < 100ms (p95, cached meeting data)
- `getMeetings`: < 50ms (p95, from cache)
- `getRecordings`: < 200ms (p95, from database)

**Background Operations**:
- Meeting list update: 30-60 seconds
- Node health check: 1 minute
- Statistics aggregation: 5 minutes

### Throughput Capacity

**Frontend** (per instance):
- ~500-1000 concurrent requests
- ~5000-10000 requests/minute
- Limited by database and BBB node response times

**Recording Processing**:
- Depends on video length and profile settings
- PyPy workers recommended for better performance
- Parallel processing across multiple workers

### Resource Utilization

**Typical Load** (100 nodes, 10000 attendees):
- Frontend: 2-4 instances, 2GB RAM each
- Celery: 5-10 workers, 1-10GB RAM each
- Redis: 1 instance, 2GB RAM
- PostgreSQL: 1 instance, 4-8GB RAM
- Total: ~30-60GB RAM, 10-20 CPU cores

## Next Steps

- [Database Schema](./02-database-schema.md): Detailed model documentation
- [API Endpoints](./03-api-endpoints.md): Complete API reference
- [Configuration](./04-configuration.md): Environment variables and settings
- [Docker Deployment](./05-docker-deployment.md): Deployment architecture
- [Celery Tasks](./06-celery-tasks.md): Background job details
