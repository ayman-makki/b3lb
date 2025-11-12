# B3LB Celery Tasks

## Overview

B3LB uses Celery for asynchronous background task processing. Tasks handle node polling, meeting list updates, recording processing, statistics aggregation, and housekeeping operations.

## Celery Architecture

### Components

```
┌─────────────────┐
│  Celery Beat    │ (Scheduler)
│  (Single Node)  │
└────────┬────────┘
         │ Schedule
         ▼
┌─────────────────┐
│  Redis Broker   │ (Task Queue)
└────────┬────────┘
         │ Tasks
         ▼
┌─────────────────┐
│ Celery Workers  │ (Task Processors)
│ (Multiple Nodes)│
└────────┬────────┘
         │ Results
         ▼
┌─────────────────┐
│   PostgreSQL    │ (Result Backend)
└─────────────────┘
```

### Configuration

**Location**: [b3lb/loadbalancer/celery.py](../b3lb/loadbalancer/celery.py)

**Settings**:
```python
# Celery app initialization
app = Celery('loadbalancer')
app.config_from_object('django.conf:settings', namespace='CELERY')

# Task discovery
app.autodiscover_tasks()

# Result backend
app.conf.result_backend = 'django-db'  # Store results in database

# Task serializer
app.conf.task_serializer = 'json'
app.conf.result_serializer = 'json'
app.conf.accept_content = ['json']
```

---

## Task Queues

B3LB uses 4 task queues for task routing and priority management.

### Queue Configuration

**Environment Variables**:
- `B3LB_TASK_QUEUE_CORE`: Core operations (default: `b3lb`)
- `B3LB_TASK_QUEUE_HOUSEKEEPING`: Cleanup tasks (default: `b3lb`)
- `B3LB_TASK_QUEUE_RECORD`: Recording processing (default: `b3lb`)
- `B3LB_TASK_QUEUE_STATISTICS`: Statistics aggregation (default: `b3lb`)

### Queue Descriptions

#### Core Queue (b3lb-core)

**Purpose**: Critical operational tasks

**Tasks**:
- Node health checks
- Meeting list updates
- Real-time data synchronization

**Priority**: High

**Worker Recommendation**:
- Image: CPython (`b3lb:3.3.2`)
- Concurrency: 4-8 workers
- Resource: 1 GB RAM per worker

**Start Worker**:
```bash
celery -A loadbalancer worker -Q b3lb-core -c 4
```

---

#### Housekeeping Queue (b3lb-housekeeping)

**Purpose**: Maintenance and cleanup operations

**Tasks**:
- Old recording deletion
- Stale data cleanup
- Cache invalidation

**Priority**: Low

**Worker Recommendation**:
- Image: CPython (`b3lb:3.3.2`)
- Concurrency: 1-2 workers
- Resource: 512 MB RAM per worker

**Start Worker**:
```bash
celery -A loadbalancer worker -Q b3lb-housekeeping -c 1
```

---

#### Record Queue (b3lb-record)

**Purpose**: Recording processing and rendering

**Tasks**:
- Video rendering
- Recording uploads
- File processing

**Priority**: Medium

**Worker Recommendation**:
- Image: **PyPy** (`b3lb-pypy:3.3.2`) for performance
- Concurrency: 2-4 workers
- Resource: 8-10 GB RAM per worker (PyPy JIT overhead)

**Start Worker**:
```bash
celery -A loadbalancer worker -Q b3lb-record -c 2
```

---

#### Statistics Queue (b3lb-stats)

**Purpose**: Metrics aggregation and reporting

**Tasks**:
- Statistics calculation
- Metrics export
- Report generation

**Priority**: Medium

**Worker Recommendation**:
- Image: CPython (`b3lb:3.3.2`)
- Concurrency: 2-4 workers
- Resource: 512 MB - 1 GB RAM per worker

**Start Worker**:
```bash
celery -A loadbalancer worker -Q b3lb-stats -c 2
```

---

## Periodic Tasks (Celery Beat)

Celery Beat schedules periodic tasks. Configuration stored in database via `django-celery-beat`.

### Task Scheduling

**Location**: Django admin → Periodic Tasks

**Default Schedule** (configured via code):

1. **Update Meeting Lists**: Every 30-60 seconds
2. **Check Node Status**: Every 1 minute
3. **Update Statistics**: Every 5 minutes
4. **Render Recordings**: Continuous (triggered by uploads)
5. **Housekeeping**: Daily

---

## Core Tasks

### Update Secrets Lists

**Function**: `update_secrets_lists_task()`

**Location**: `rest/tasks.py`

**Purpose**: Refresh meeting lists for all tenants

**Schedule**: Every 30-60 seconds

**Queue**: `b3lb-core`

**Process**:
1. Get all active secrets
2. Spawn `update_secret_meeting_list` for each secret
3. Aggregate results
4. Update metrics

**Spawned Subtask**: `update_secret_meeting_list(secret_id)`

**Subtask Process**:
1. Get secret's cluster group nodes
2. Poll each node's `getMeetings` API
3. Aggregate meeting data
4. Update Meeting records in database
5. Cache aggregated XML in SecretMeetingList
6. Update Redis cache

**Code Reference**:
```python
@shared_task(queue=get_core_queue())
def update_secrets_lists_task():
    secrets = Secret.objects.all()
    for secret in secrets:
        update_secret_meeting_list.delay(secret.id)
```

**Performance**:
- Parallel execution per secret
- Async HTTP requests to nodes
- Redis caching for fast API responses

---

### Check Status of Nodes

**Function**: `check_status_of_nodes_task()`

**Location**: `rest/tasks.py`

**Purpose**: Health check all BBB nodes

**Schedule**: Every 1 minute

**Queue**: `b3lb-core`

**Process**:
1. Get all active nodes
2. For each node:
   - Poll `/b3lb/load` endpoint for CPU
   - Poll `/bigbluebutton/api/getMeetings`
   - Update node metrics (cpu_load, attendees, meetings)
   - Set `has_errors` flag on failure
3. Update NodeMeetingList cache
4. Update node load calculations

**Code Reference**:
```python
@shared_task(queue=get_core_queue())
def check_status_of_nodes_task():
    nodes = Node.objects.filter(maintenance=False)
    for node in nodes:
        try:
            # Poll load endpoint
            cpu_load = fetch_node_load(node)
            node.cpu_load = cpu_load

            # Poll getMeetings
            meetings_xml = fetch_node_meetings(node)
            update_node_meetings(node, meetings_xml)

            node.has_errors = False
        except Exception as e:
            node.has_errors = True
            logger.error(f"Node {node.slug} health check failed: {e}")

        node.save()
```

**Error Handling**:
- Nodes with errors excluded from load balancing
- Automatic recovery when node responds again
- Exponential backoff for failed nodes

---

### Update Statistics

**Function**: `update_statistics_task()`

**Location**: `rest/task/statistics.py`

**Purpose**: Aggregate tenant statistics

**Schedule**: Every 5 minutes

**Queue**: `b3lb-stats`

**Process**:
1. For each tenant:
   - Aggregate meeting data
   - Calculate totals (attendees, meetings, etc.)
   - Update Stats model
   - Generate Prometheus metrics
   - Cache metrics in SecretMetricsList

**Metrics Generated**:
- **Gauges**: Current attendees, meetings, listeners, videos, voices
- **Counters**: Total attendees joined, meetings created, duration
- **Limit Hits**: Attendee limit hits, meeting limit hits

**Code Reference**:
```python
@shared_task(queue=get_statistics_queue())
def update_statistics_task():
    tenants = Tenant.objects.all()
    for tenant in tenants:
        meetings = Meeting.objects.filter(secret__tenant=tenant)

        stats = {
            'attendees': sum(m.attendees for m in meetings),
            'meetings': meetings.count(),
            'listeners': sum(m.listeners for m in meetings),
            'videos': sum(m.videos for m in meetings),
            'voices': sum(m.voice for m in meetings)
        }

        Stats.objects.update_or_create(
            tenant=tenant,
            defaults={
                'time': timezone.now(),
                **stats
            }
        )

        # Generate and cache Prometheus metrics
        metrics_text = generate_prometheus_metrics(tenant, stats)
        cache_metrics(tenant, metrics_text)
```

---

## Recording Tasks

### Render Records

**Function**: `render_records_task(recordset_id)`

**Location**: `rest/task/recording.py`

**Purpose**: Process and render uploaded recordings

**Trigger**: On recording upload

**Queue**: `b3lb-record`

**Process**:
1. Get RecordSet by ID
2. Extract recording archive
3. Parse metadata.xml
4. For each RecordProfile:
   - Run FFmpeg rendering
   - Generate video file
   - Upload to S3/local storage
   - Create Record object
5. Update RecordSet status to RENDERED
6. Cleanup temporary files

**Code Reference**:
```python
@shared_task(queue=get_record_queue())
def render_records_task(recordset_id):
    recordset = RecordSet.objects.get(id=recordset_id)
    recordset.status = 'RENDERING'
    recordset.save()

    try:
        # Extract archive
        extract_recording_archive(recordset)

        # Get metadata
        metadata = parse_metadata_xml(recordset)

        # Render each profile
        profiles = RecordProfile.objects.all()
        for profile in profiles:
            video_file = render_video(recordset, profile, metadata)
            upload_video(video_file, recordset, profile)
            create_record(recordset, profile, metadata)

        recordset.status = 'RENDERED'
        recordset.save()

    except Exception as e:
        recordset.status = 'FAILED'
        recordset.save()
        logger.error(f"Rendering failed for {recordset_id}: {e}")
        raise
```

**Performance**:
- PyPy workers recommended (2-5x faster)
- Parallel rendering across multiple workers
- Configurable video quality/resolution
- Progress tracking in database

---

### Housekeeping Recordings

**Function**: `housekeeping_recordings_task()`

**Location**: `rest/task/recording.py`

**Purpose**: Delete old recordings based on retention policy

**Schedule**: Daily

**Queue**: `b3lb-housekeeping`

**Process**:
1. Get retention policy per tenant/secret
2. Find recordings older than hold_time
3. Mark RecordSet as DELETING
4. Delete video files from S3/local storage
5. Delete Record and RecordSet from database

**Code Reference**:
```python
@shared_task(queue=get_housekeeping_queue())
def housekeeping_recordings_task():
    # Get recordings past retention period
    cutoff = timezone.now() - timedelta(days=hold_time)
    old_recordsets = RecordSet.objects.filter(
        end_time__lt=cutoff,
        status='RENDERED'
    )

    for recordset in old_recordsets:
        delete_recording.delay(recordset.id)
```

**Subtask**: `delete_recording(recordset_id)`

**Deletion Process**:
1. Mark status as DELETING
2. Delete files from S3/storage
3. Delete Record objects
4. Delete RecordSet object
5. Log deletion

---

## Task Monitoring

### Celery Flower

**Purpose**: Real-time Celery monitoring UI

**Start**:
```bash
celery -A loadbalancer flower --port=5555
```

**Access**: http://localhost:5555

**Features**:
- Active tasks
- Worker status
- Task history
- Queue depths
- Success/failure rates
- Task runtime statistics

---

### Celery Inspect Commands

**Ping Workers**:
```bash
celery -A loadbalancer inspect ping
```

**Active Tasks**:
```bash
celery -A loadbalancer inspect active
```

**Scheduled Tasks**:
```bash
celery -A loadbalancer inspect scheduled
```

**Registered Tasks**:
```bash
celery -A loadbalancer inspect registered
```

**Statistics**:
```bash
celery -A loadbalancer inspect stats
```

**Queue Status**:
```bash
celery -A loadbalancer inspect active_queues
```

---

### Task Result Inspection

**Get Task Result**:
```python
from celery.result import AsyncResult

result = AsyncResult(task_id)
print(result.state)  # PENDING, STARTED, SUCCESS, FAILURE
print(result.result)  # Task return value
print(result.traceback)  # Error traceback if failed
```

**Task States**:
- `PENDING`: Task waiting in queue
- `STARTED`: Worker picked up task
- `SUCCESS`: Task completed successfully
- `FAILURE`: Task failed with error
- `RETRY`: Task being retried
- `REVOKED`: Task cancelled

---

## Task Configuration

### Task Rate Limiting

**Purpose**: Prevent task flooding

**Configuration**:
```python
@shared_task(rate_limit='10/m')  # 10 tasks per minute
def rate_limited_task():
    pass
```

---

### Task Retry

**Purpose**: Automatic retry on failure

**Configuration**:
```python
@shared_task(
    autoretry_for=(Exception,),
    retry_kwargs={'max_retries': 3},
    retry_backoff=True,
    retry_jitter=True
)
def retriable_task():
    pass
```

**Backoff**: Exponential backoff between retries
**Jitter**: Random jitter to prevent thundering herd

---

### Task Timeout

**Purpose**: Kill long-running tasks

**Configuration**:
```python
@shared_task(time_limit=300, soft_time_limit=240)  # 4min soft, 5min hard
def timeout_task():
    pass
```

**Soft Time Limit**: Raises SoftTimeLimitExceeded (catchable)
**Hard Time Limit**: Kills worker process (not catchable)

---

### Task Prioritization

**Purpose**: Control task execution order

**Configuration**:
```python
@shared_task(priority=9)  # 0-9, higher = higher priority
def high_priority_task():
    pass

# Or at call time
task.apply_async(priority=9)
```

---

## Worker Configuration

### Concurrency

**Auto-detection**: Based on CPU cores
```bash
celery -A loadbalancer worker  # Auto-detects
```

**Manual**:
```bash
celery -A loadbalancer worker -c 4  # 4 concurrent tasks
```

**Pool Types**:
- `prefork`: Multi-process (default, recommended)
- `gevent`: Greenlets (high I/O concurrency)
- `eventlet`: Similar to gevent
- `solo`: Single thread (debugging)

---

### Worker Pool Configuration

**Prefork Pool** (default):
```bash
celery -A loadbalancer worker --pool=prefork -c 4
```

**Gevent Pool** (high I/O):
```bash
celery -A loadbalancer worker --pool=gevent -c 100
```

---

### Worker Autoscaling

**Dynamic Concurrency**:
```bash
celery -A loadbalancer worker --autoscale=10,3
# Min 3 workers, max 10 workers
```

**Behavior**: Scales up/down based on queue depth

---

### Worker Optimization

**Prefetch Multiplier**:
```bash
celery -A loadbalancer worker --prefetch-multiplier=4
# Each worker prefetches 4 tasks
```

**Lower = More fair distribution**
**Higher = Better throughput**

**Max Tasks Per Child**:
```bash
celery -A loadbalancer worker --max-tasks-per-child=1000
# Restart worker after 1000 tasks (prevent memory leaks)
```

---

## Performance Tuning

### Queue Depth Monitoring

**Check Queue Length**:
```python
from celery import current_app

def get_queue_length(queue_name):
    with current_app.connection_or_acquire() as conn:
        return conn.default_channel.client.llen(queue_name)
```

**Alerts**:
- Queue depth > 100: Consider scaling workers
- Queue depth > 1000: Immediate attention needed

---

### Task Execution Time

**Track Task Duration**:
```python
import time
from celery import shared_task

@shared_task
def timed_task():
    start = time.time()
    # Task logic
    duration = time.time() - start
    logger.info(f"Task took {duration:.2f}s")
```

**Optimization**:
- Tasks > 5s: Consider optimization
- Tasks > 60s: Consider breaking into subtasks

---

### Resource Usage

**Worker Memory**:
```bash
# Monitor worker memory
ps aux | grep celery

# Or use Flower
```

**Database Connections**:
- Each worker maintains database connection pool
- Configure `CONN_MAX_AGE` in Django settings
- Use connection pooler (pgbouncer) for many workers

---

## Troubleshooting

### Task Not Executing

**Check Worker Status**:
```bash
celery -A loadbalancer inspect ping
```

**Check Queue**:
```bash
celery -A loadbalancer inspect active_queues
```

**Check Task Registration**:
```bash
celery -A loadbalancer inspect registered
```

---

### Task Failing

**View Traceback**:
```bash
celery -A loadbalancer events
# Or check Flower UI
```

**Debug Mode**:
```python
# Run task synchronously for debugging
result = task.apply(args=[...])
```

---

### Worker Memory Leak

**Symptoms**: Worker memory grows over time

**Solutions**:
1. Set `--max-tasks-per-child`:
   ```bash
   celery -A loadbalancer worker --max-tasks-per-child=1000
   ```

2. Monitor with Flower

3. Investigate task code for unclosed resources

---

### Task Retry Loop

**Symptoms**: Task continuously retrying

**Solutions**:
1. Check retry configuration
2. Add max_retries limit
3. Investigate underlying cause
4. Add exponential backoff

**Example Fix**:
```python
@shared_task(
    autoretry_for=(TransientError,),
    retry_kwargs={'max_retries': 5},
    retry_backoff=True
)
def safe_task():
    pass
```

---

### Broker Connection Lost

**Symptoms**: Workers disconnect from Redis

**Solutions**:
1. Check Redis status
2. Check network connectivity
3. Increase Redis timeout
4. Use Redis Sentinel for HA

---

## Best Practices

### Task Design

1. **Idempotent**: Tasks should be safe to retry
2. **Small**: Keep tasks focused and short-running
3. **Atomic**: Complete units of work
4. **Logged**: Log important events
5. **Monitored**: Track execution time and failures

---

### Error Handling

```python
@shared_task
def robust_task():
    try:
        # Task logic
        pass
    except TransientError as e:
        # Retry on transient errors
        raise self.retry(exc=e, countdown=60)
    except PermanentError as e:
        # Log and don't retry
        logger.error(f"Permanent error: {e}")
        return {'status': 'failed', 'error': str(e)}
```

---

### Task Chunking

**For Large Batches**:
```python
from celery import group

@shared_task
def process_item(item_id):
    # Process single item
    pass

# Process 1000 items in chunks of 100
items = list(range(1000))
job = group(process_item.s(i) for i in items)
result = job.apply_async()
```

---

### Task Chains

**Sequential Tasks**:
```python
from celery import chain

workflow = chain(
    task1.s(arg1),
    task2.s(),
    task3.s()
)
result = workflow.apply_async()
```

---

### Task Groups

**Parallel Tasks**:
```python
from celery import group

job = group(
    task1.s(1),
    task2.s(2),
    task3.s(3)
)
result = job.apply_async()
```

---

## Monitoring & Alerts

### Prometheus Metrics

**Celery Exporter**: https://github.com/danihodovic/celery-exporter

**Metrics**:
- `celery_task_total`: Total tasks executed
- `celery_task_runtime_seconds`: Task execution time
- `celery_worker_up`: Worker status
- `celery_queue_length`: Queue depth

**Alert Rules**:
```yaml
groups:
- name: celery
  rules:
  - alert: CeleryWorkerDown
    expr: celery_worker_up == 0
    for: 5m
    annotations:
      summary: "Celery worker down"

  - alert: CeleryQueueBacklog
    expr: celery_queue_length > 1000
    for: 10m
    annotations:
      summary: "Celery queue backlog"
```

---

## Next Steps

- [Docker Deployment](./05-docker-deployment.md): Deploy Celery workers
- [Operations](./08-operations.md): Monitor and troubleshoot tasks
- [Development Guide](./07-development-guide.md): Create custom tasks
