# B3LB Operations Manual

## Overview

This manual covers operational procedures for monitoring, maintaining, and troubleshooting B3LB in production environments.

## Pre-Deployment Checklist

### Infrastructure

- [ ] PostgreSQL 9.5+ running and accessible
- [ ] Redis running and accessible
- [ ] Reverse proxy configured (Traefik recommended)
- [ ] DNS configured (wildcard or path-based)
- [ ] SSL certificates configured
- [ ] Firewall rules configured
- [ ] Backup procedures in place

### Configuration

- [ ] `SECRET_KEY` generated and set
- [ ] `DATABASE_URL` configured
- [ ] `CELERY_BROKER_URL` configured
- [ ] `B3LB_API_BASE_DOMAIN` set correctly
- [ ] All optional environment variables reviewed
- [ ] BBB node scripts installed on nodes
- [ ] S3 storage configured (if using recordings)

### Initial Setup

- [ ] Database migrations applied
- [ ] Superuser created
- [ ] Clusters configured
- [ ] Nodes added and tested
- [ ] Cluster groups created
- [ ] Tenants created
- [ ] API secrets generated
- [ ] Test meeting successful

---

## Daily Operations

### Morning Checks

**Health Status**:
```bash
# Check all services
curl https://bbb.example.com/b3lb/ping

# Check node status
docker-compose exec frontend python manage.py getloadvalues
```

**System Metrics**:
```bash
# Check resource usage
docker stats

# Or Kubernetes
kubectl top pods
```

**Queue Depths**:
```bash
# Check Celery queues
docker-compose exec celery-worker celery -A loadbalancer inspect active_queues
```

---

### Monitoring Dashboards

Access monitoring interfaces:

- **Admin Interface**: `https://bbb.example.com/admin/`
- **Metrics**: `https://bbb.example.com/b3lb/metrics`
- **Statistics**: `https://bbb.example.com/b3lb/stats`
- **Celery Flower**: `http://localhost:5555` (if enabled)
- **Traefik Dashboard**: `https://traefik.bbb.example.com/dashboard/`

---

## Monitoring

### Health Checks

**Ping Endpoint**:
```bash
curl https://bbb.example.com/b3lb/ping
```

**Expected Response**:
```json
{
  "status": "ok",
  "version": "3.3.2",
  "timestamp": "2025-01-15T10:30:00Z"
}
```

---

### Prometheus Metrics

**Scrape Endpoint**:
```
https://bbb.example.com/b3lb/metrics
```

**Key Metrics**:

| Metric | Type | Description |
|--------|------|-------------|
| `b3lb_attendees` | Gauge | Current attendee count |
| `b3lb_meetings` | Gauge | Current meeting count |
| `b3lb_attendees_joined_total` | Counter | Total attendees joined |
| `b3lb_meetings_created_total` | Counter | Total meetings created |
| `b3lb_attendee_limit_hits_total` | Counter | Attendee limit violations |
| `b3lb_meeting_limit_hits_total` | Counter | Meeting limit violations |

**Prometheus Config**:
```yaml
scrape_configs:
  - job_name: 'b3lb'
    scrape_interval: 30s
    static_configs:
      - targets: ['bbb.example.com:443']
    scheme: https
    metrics_path: '/b3lb/metrics'
    basic_auth:
      username: prometheus
      password: ${PROMETHEUS_PASSWORD}
```

---

### Grafana Dashboards

**Recommended Panels**:

1. **System Health**
   - Active meetings (gauge)
   - Active attendees (gauge)
   - Node status (table)

2. **Load Distribution**
   - Meetings per node (bar chart)
   - Attendees per node (bar chart)
   - Node load scores (time series)

3. **API Performance**
   - Request rate (time series)
   - Response time (histogram)
   - Error rate (time series)

4. **Celery Monitoring**
   - Task queue depth (time series)
   - Task execution time (histogram)
   - Worker status (table)

5. **Limits & Capacity**
   - Attendee limit hits (counter)
   - Meeting limit hits (counter)
   - Capacity utilization (gauge)

---

### Log Monitoring

**Application Logs**:
```bash
# Docker Compose
docker-compose logs -f --tail=100 frontend

# Kubernetes
kubectl logs -f deployment/b3lb-frontend
```

**Log Levels**:
- `ERROR`: Immediate attention required
- `WARNING`: Review during daily checks
- `INFO`: Normal operations
- `DEBUG`: Development only

**Important Log Patterns**:
```bash
# Errors
grep ERROR logs/b3lb.log

# Node failures
grep "Node.*failed" logs/b3lb.log

# Limit hits
grep "limit exceeded" logs/b3lb.log
```

---

### Alerting Rules

**Critical Alerts**:

```yaml
groups:
- name: b3lb-critical
  rules:
  # Service down
  - alert: B3LBServiceDown
    expr: up{job="b3lb"} == 0
    for: 2m
    labels:
      severity: critical
    annotations:
      summary: "B3LB service is down"

  # All nodes down
  - alert: AllNodesDown
    expr: sum(b3lb_node_up) == 0
    for: 5m
    labels:
      severity: critical
    annotations:
      summary: "All BBB nodes are down"

  # Database connection lost
  - alert: DatabaseConnectionLost
    expr: b3lb_database_up == 0
    for: 1m
    labels:
      severity: critical
    annotations:
      summary: "Database connection lost"
```

**Warning Alerts**:

```yaml
- name: b3lb-warning
  rules:
  # High queue depth
  - alert: CeleryQueueBacklog
    expr: celery_queue_length > 1000
    for: 10m
    labels:
      severity: warning
    annotations:
      summary: "Celery queue backlog detected"

  # Node in maintenance
  - alert: NodeMaintenance
    expr: b3lb_node_maintenance == 1
    for: 1h
    labels:
      severity: warning
    annotations:
      summary: "Node in maintenance mode for >1h"

  # Approaching limits
  - alert: ApproachingAttendeeLimit
    expr: b3lb_attendees / b3lb_attendee_limit > 0.9
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "Approaching attendee limit (>90%)"
```

---

## Common Operations

### Adding a BBB Node

**1. Install BBB Node Scripts**:

See [BBB Node Scripts](./09-bbb-node-scripts.md) for details.

**2. Add Node via Admin**:

Navigate to Admin → Nodes → Add Node:
- Slug: `bbb05`
- Domain: `bbb05.example.com`
- Secret: `[BBB node secret]`
- Cluster: Select cluster
- Protocol: `https`
- Port: `443`

**3. Or via CLI**:
```bash
docker-compose exec frontend python manage.py addnode \
  bbb05 \
  bbb05.example.com \
  bbb_secret_here \
  main-cluster
```

**4. Verify**:
```bash
# Check node status
docker-compose exec frontend python manage.py getloadvalues
```

**5. Monitor**:
- Wait 1 minute for Celery to poll node
- Check Admin → Nodes → verify cpu_load updated
- Test create meeting via API Mate

---

### Removing a BBB Node

**1. Set Maintenance Mode**:

Admin → Nodes → Select node → Set maintenance mode

This prevents new meetings from being created on the node.

**2. Wait for Meetings to End**:

Monitor active meetings on the node:
```bash
# Check meetings on node
docker-compose exec frontend python manage.py shell
```

```python
from rest.models import Node
node = Node.objects.get(slug='bbb05')
meetings = node.meetings_on_node()
print(f"Active meetings: {meetings.count()}")
```

**3. Remove Node**:

Admin → Nodes → Delete node

Or via shell:
```python
from rest.models import Node
Node.objects.get(slug='bbb05').delete()
```

---

### Creating a Tenant

**1. Via Admin**:

Navigate to Admin → Tenants → Add Tenant:
- Slug: `ACME` (2-10 uppercase letters)
- Cluster Group: Select group
- Attendee Limit: `500`
- Meeting Limit: `50`
- Record by Default: Check if desired

**2. Generate Secrets**:

Admin → Secrets → Add Secret:
- Tenant: Select tenant
- Sub ID: `0` (primary secret)
- Secret: Generate 64-char hex string
- Secret2: Generate 64-char hex string (rollover)

Or via CLI:
```bash
docker-compose exec frontend python manage.py addsecrets ACME 0-5
```

This creates secrets 0-5 for tenant ACME.

**3. Get Tenant Secrets**:

```bash
docker-compose exec frontend python manage.py gettenantsecrets ACME
```

**Output**:
```
Tenant: ACME
Sub-ID 0:
  Secret: abc123...
  Secret2: def456...
  Endpoint: https://acme.bbb.example.com/bigbluebutton/api/
```

**4. Test API**:

Use API Mate to test create/join with the generated secret.

---

### Rotating API Secrets

**Process**:

1. **Generate New Secret2**:

Admin → Secrets → Select secret → Update `secret2` field

2. **Communicate to Clients**:

Inform clients that both `secret` and `secret2` are valid.

3. **Wait for Migration** (30 days recommended)

4. **Promote Secret2 to Secret**:

```python
from rest.models import Secret
import secrets

s = Secret.objects.get(tenant__slug='ACME', sub_id=0)
s.secret = s.secret2  # Promote secret2
s.secret2 = secrets.token_hex(32)  # Generate new secret2
s.save()
```

5. **Communicate to Clients**:

Inform clients of the old secret deprecation.

---

### Updating Tenant Limits

**Via Admin**:

Admin → Tenants → Select tenant → Update limits

**Via Shell**:
```python
from rest.models import Tenant

tenant = Tenant.objects.get(slug='ACME')
tenant.attendee_limit = 1000  # Increase
tenant.meeting_limit = 100    # Increase
tenant.save()
```

**Effective Immediately**: New meetings will use updated limits.

---

### Uploading Tenant Assets

**Logo**:

Admin → Assets → Select tenant asset → Upload logo file

**Slide**:

Admin → Assets → Select tenant asset → Upload slide file

**Custom CSS**:

Admin → Assets → Select tenant asset → Upload CSS file

**Usage in BBB**:
```
logo=https://acme.bbb.example.com/b3lb/t/acme/logo
defaultPresentationURL=https://acme.bbb.example.com/b3lb/t/acme/slide
customStyleUrl=https://acme.bbb.example.com/b3lb/t/acme/css
```

---

## Scaling Operations

### Horizontal Scaling

**Frontend**:
```bash
# Docker Compose
docker-compose up --scale frontend=5

# Kubernetes
kubectl scale deployment b3lb-frontend --replicas=5
```

**Celery Workers**:
```bash
# Docker Compose
docker-compose up --scale celery-worker=8

# Kubernetes
kubectl scale deployment b3lb-celery-worker --replicas=8
```

**When to Scale**:
- High request rate (>1000 req/s)
- Celery queue depth > 100 consistently
- CPU usage > 70%
- Response time degradation

---

### Vertical Scaling

**Database**:

Increase PostgreSQL resources:
```yaml
resources:
  limits:
    memory: 16G
    cpu: 8
```

**Redis**:

Increase max memory:
```bash
redis-server --maxmemory 8gb
```

**When to Scale**:
- Database CPU > 80%
- Redis memory > 80%
- Slow query performance

---

## Backup & Recovery

### Database Backup

**Automated Backup Script**:
```bash
#!/bin/bash
# backup-b3lb.sh

DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="/backups/b3lb"
RETENTION_DAYS=30

# Create backup
docker-compose exec -T postgres pg_dump -U b3lb b3lb | gzip > "$BACKUP_DIR/b3lb-$DATE.sql.gz"

# Verify backup
if [ $? -eq 0 ]; then
    echo "Backup successful: b3lb-$DATE.sql.gz"
else
    echo "Backup failed!" >&2
    exit 1
fi

# Delete old backups
find "$BACKUP_DIR" -name "b3lb-*.sql.gz" -mtime +$RETENTION_DAYS -delete

# Upload to S3 (optional)
aws s3 cp "$BACKUP_DIR/b3lb-$DATE.sql.gz" s3://backups/b3lb/
```

**Schedule with Cron**:
```bash
# Daily backup at 2 AM
0 2 * * * /usr/local/bin/backup-b3lb.sh >> /var/log/b3lb-backup.log 2>&1
```

---

### Database Restore

**Restore from Backup**:
```bash
# Stop services
docker-compose stop frontend celery-worker celery-beat

# Drop and recreate database
docker-compose exec postgres psql -U postgres -c "DROP DATABASE b3lb;"
docker-compose exec postgres psql -U postgres -c "CREATE DATABASE b3lb OWNER b3lb;"

# Restore backup
gunzip < /backups/b3lb/b3lb-20250115-020000.sql.gz | \
  docker-compose exec -T postgres psql -U b3lb b3lb

# Start services
docker-compose start frontend celery-worker celery-beat

# Verify
docker-compose exec frontend python manage.py check --database default
```

---

### Configuration Backup

**Backup Configuration**:
```bash
# Environment variables
cp .env .env.backup-$(date +%Y%m%d)

# Docker Compose
cp docker-compose.yml docker-compose.yml.backup-$(date +%Y%m%d)

# Store in version control or secure location
```

---

## Troubleshooting

### Service Not Responding

**Symptoms**: HTTP requests timeout or fail

**Diagnosis**:
```bash
# Check service status
docker-compose ps

# Check logs
docker-compose logs frontend

# Check resource usage
docker stats
```

**Solutions**:
1. Restart service: `docker-compose restart frontend`
2. Check database connection: `docker-compose exec frontend python manage.py check --database default`
3. Check Redis connection: `redis-cli -h redis ping`
4. Verify environment variables

---

### Node Not Receiving Meetings

**Symptoms**: Specific node never gets meetings

**Diagnosis**:
```bash
# Check node status
docker-compose exec frontend python manage.py getloadvalues

# Check node in admin
# Admin → Nodes → Check has_errors and maintenance flags
```

**Solutions**:
1. Verify node is not in maintenance mode
2. Check `has_errors` flag - if true, investigate node health
3. Verify node is in correct cluster group
4. Test node directly: `curl https://bbb05.example.com/bigbluebutton/api/`

---

### High Database Load

**Symptoms**: Slow queries, high CPU on PostgreSQL

**Diagnosis**:
```bash
# Check slow queries
docker-compose exec postgres psql -U b3lb -c "SELECT query, calls, mean_exec_time FROM pg_stat_statements ORDER BY mean_exec_time DESC LIMIT 10;"

# Check connection count
docker-compose exec postgres psql -U b3lb -c "SELECT count(*) FROM pg_stat_activity;"
```

**Solutions**:
1. Add indexes for frequent queries
2. Enable query caching (django-cacheops)
3. Use connection pooling (pgbouncer)
4. Scale database vertically
5. Consider read replicas for reporting

---

### Celery Tasks Not Executing

**Symptoms**: Queue depth increasing, tasks not completing

**Diagnosis**:
```bash
# Check workers
docker-compose exec celery-worker celery -A loadbalancer inspect ping

# Check active tasks
docker-compose exec celery-worker celery -A loadbalancer inspect active

# Check queue depth
# Use Celery Flower or Redis CLI
redis-cli llen celery
```

**Solutions**:
1. Restart workers: `docker-compose restart celery-worker`
2. Scale workers: `docker-compose up --scale celery-worker=5`
3. Check task errors: Review Celery Flower
4. Verify broker connection: `redis-cli ping`

---

### Recording Rendering Failed

**Symptoms**: RecordSet stuck in UPLOADED status

**Diagnosis**:
```bash
# Check rendering queue
docker-compose logs celery-record

# Check RecordSet status
docker-compose exec frontend python manage.py shell
```

```python
from rest.models import RecordSet
failed = RecordSet.objects.filter(status='UPLOADED')
for rs in failed:
    print(f"{rs.id}: {rs.meeting_id}")
```

**Solutions**:
1. Check FFmpeg installed in worker
2. Verify S3 credentials (if using S3)
3. Check disk space
4. Manually trigger render: `render_records_task.delay(recordset_id)`
5. Review worker logs for errors

---

### Meeting Not Found on Join

**Symptoms**: Join request fails with "Meeting not found"

**Diagnosis**:
```bash
# Check Meeting record
docker-compose exec frontend python manage.py shell
```

```python
from rest.models import Meeting
meeting = Meeting.objects.filter(meeting_id='test-123')
if meeting.exists():
    print(f"Meeting exists, node: {meeting.first().node.slug}")
else:
    print("Meeting not in database")
```

**Solutions**:
1. Verify meeting was created successfully
2. Check meeting not ended
3. Verify tenant/secret matches
4. Check BBB node is responding
5. Review create API logs

---

## Maintenance Windows

### Planned Maintenance

**Pre-Maintenance**:
1. Announce maintenance window to users
2. Set node to maintenance mode (if node-specific)
3. Wait for active meetings to end
4. Take database backup

**During Maintenance**:
1. Stop services: `docker-compose stop`
2. Perform maintenance (updates, migrations, etc.)
3. Test in staging environment first
4. Start services: `docker-compose start`
5. Verify health checks

**Post-Maintenance**:
1. Monitor logs for errors
2. Verify all nodes responding
3. Test create/join meetings
4. Clear maintenance mode flags
5. Confirm with users

---

### Rolling Updates

**Zero-Downtime Update Process**:

1. **Update Docker Images**:
```bash
docker-compose pull
```

2. **Update Frontend** (rolling):
```bash
# Scale up with new version
docker-compose up -d --scale frontend=6

# Wait 30s for new instances to be healthy
sleep 30

# Scale down old instances
docker-compose up -d --scale frontend=3
```

3. **Update Celery Workers**:
```bash
# Gracefully stop workers (finish current tasks)
docker-compose exec celery-worker celery -A loadbalancer control shutdown

# Start new workers
docker-compose up -d celery-worker
```

4. **Update Celery Beat**:
```bash
# Stop and restart
docker-compose restart celery-beat
```

---

## Performance Optimization

### Database Optimization

**Vacuum and Analyze**:
```bash
# Vacuum database
docker-compose exec postgres vacuumdb -U b3lb -d b3lb --analyze

# Auto-vacuum settings
docker-compose exec postgres psql -U postgres -c "ALTER DATABASE b3lb SET autovacuum = on;"
```

**Connection Pooling**:

Use pgbouncer for many frontend instances:
```yaml
pgbouncer:
  image: pgbouncer/pgbouncer
  environment:
    DATABASES_HOST: postgres
    DATABASES_PORT: 5432
    DATABASES_USER: b3lb
    DATABASES_PASSWORD: ${DB_PASSWORD}
    DATABASES_DBNAME: b3lb
    POOL_MODE: transaction
    MAX_CLIENT_CONN: 1000
    DEFAULT_POOL_SIZE: 25
```

---

### Redis Optimization

**Memory Management**:
```bash
# Set max memory
redis-cli CONFIG SET maxmemory 4gb

# Set eviction policy
redis-cli CONFIG SET maxmemory-policy allkeys-lru
```

**Persistence**:
```bash
# Disable persistence for cache (optional)
redis-cli CONFIG SET save ""
```

---

### Application Optimization

**ORM Query Optimization**:
- Use `select_related()` for foreign keys
- Use `prefetch_related()` for reverse foreign keys
- Add indexes for frequent filters
- Use `only()` / `defer()` to limit fields

**Caching Strategy**:
- Enable django-cacheops for ORM caching
- Use Redis for cache backend
- Cache expensive calculations
- Set appropriate TTLs

---

## Security Hardening

### Access Control

**Restrict Admin Access**:

Traefik ACL configuration:
```yaml
- "traefik.http.middlewares.admin-auth.ipwhitelist.sourcerange=10.0.0.0/8,192.168.0.0/16"
- "traefik.http.routers.admin.middlewares=admin-auth"
```

**Restrict Metrics Access**:
```yaml
- "traefik.http.middlewares.metrics-auth.basicauth.users=${METRICS_BASIC_AUTH}"
```

---

### SSL/TLS

**Force HTTPS**:
```yaml
- "traefik.http.routers.http.middlewares=redirect-https"
- "traefik.http.middlewares.redirect-https.redirectscheme.scheme=https"
```

**Modern TLS Config**:
```yaml
- "traefik.http.routers.b3lb.tls.options=modern@file"
```

---

### Rate Limiting

**Traefik Rate Limit**:
```yaml
- "traefik.http.middlewares.ratelimit.ratelimit.average=100"
- "traefik.http.middlewares.ratelimit.ratelimit.burst=50"
```

---

## Disaster Recovery

### Recovery Time Objectives

| Component | RTO | RPO |
|-----------|-----|-----|
| Database | 1 hour | 24 hours |
| Application | 15 minutes | 0 (stateless) |
| Configuration | 15 minutes | As of last commit |
| Recordings | N/A | 24 hours |

### Disaster Recovery Plan

**1. Infrastructure Failure**:
- Deploy to backup infrastructure
- Restore database from latest backup
- Update DNS to point to new infrastructure
- Verify functionality

**2. Data Corruption**:
- Stop all services
- Restore database from backup
- Replay transaction logs if available
- Restart services

**3. Complete System Failure**:
- Follow deployment guide with backup data
- Restore all configurations
- Verify all components operational
- Resume service

---

## Next Steps

- [Configuration](./04-configuration.md): Review configuration options
- [Docker Deployment](./05-docker-deployment.md): Deployment procedures
- [BBB Node Scripts](./09-bbb-node-scripts.md): Configure BBB nodes
