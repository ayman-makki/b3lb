# B3LB Development Guide

## Overview

This guide covers local development setup, testing, code organization, and contribution guidelines for B3LB development.

## Prerequisites

### Required Software

- **Python**: 3.12+ (CPython) or 3.10+ (PyPy)
- **PostgreSQL**: 9.5+
- **Redis**: 5.0+
- **Git**: 2.0+

### Optional Software

- **Docker**: For containerized development
- **docker-compose**: For running full stack locally
- **FFmpeg**: For recording rendering development
- **VSCode/PyCharm**: Recommended IDEs

---

## Local Development Setup

### 1. Clone Repository

```bash
git clone https://github.com/DE-IBH/b3lb.git
cd b3lb
```

### 2. Create Virtual Environment

```bash
# Using venv
python3.12 -m venv venv
source venv/bin/activate  # Linux/Mac
# venv\Scripts\activate  # Windows

# Or using virtualenv
virtualenv venv -p python3.12
source venv/bin/activate
```

### 3. Install Dependencies

```bash
# Core requirements
pip install -r requirements/requirements.txt

# Extra requirements (Uvicorn with optimizations)
pip install -r requirements/requirements_extra.txt

# Development dependencies
pip install -r requirements/requirements_dev.txt  # If exists
```

**Dependencies Installed**:
- Django 5.2.2
- Celery 5.5.3
- aiohttp 3.12.7
- psycopg 3.2.6 (PostgreSQL adapter)
- redis, django-redis, django-cacheops
- django-celery-beat, django-celery-results
- And more (see requirements.txt)

### 4. Configure PostgreSQL

```bash
# Create database
sudo -u postgres createdb b3lb_dev
sudo -u postgres createuser b3lb_dev -P

# Grant privileges
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE b3lb_dev TO b3lb_dev;"
```

### 5. Configure Redis

```bash
# Start Redis (if not running)
sudo systemctl start redis

# Or with Docker
docker run -d -p 6379:6379 redis:6.0.16-alpine
```

### 6. Environment Configuration

Create `.env` file in project root:

```bash
# Django
DEBUG=True
SECRET_KEY="dev-secret-key-not-for-production"
ALLOWED_HOSTS="localhost,127.0.0.1"

# Database
DATABASE_URL="postgres://b3lb_dev:password@localhost:5432/b3lb_dev"

# Cache
CACHE_URL="redis://localhost:6379/1"
CACHEOPS_REDIS="redis://localhost:6379/2"
CACHEOPS_DEGRADE_ON_FAILURE=True

# Celery
CELERY_BROKER_URL="redis://localhost:6379/0"

# B3LB
B3LB_API_BASE_DOMAIN="localhost:8000"

# Optional: Recording (disabled for dev)
B3LB_RENDERING=False

# Optional: Logging
DJANGO_LOG_LEVEL=DEBUG
```

### 7. Run Migrations

```bash
cd b3lb  # Change to b3lb subdirectory
./manage.py migrate
```

**Output**: Database tables created

### 8. Create Superuser

```bash
./manage.py createsuperuser
```

Enter username, email, and password for admin access.

### 9. Load Initial Data (Optional)

```bash
# Create test cluster
./manage.py shell
```

```python
from rest.models import Cluster, ClusterGroup, Tenant, Secret

# Create cluster
cluster = Cluster.objects.create(
    name="dev-cluster",
    load_a_factor=1.0,
    load_m_factor=10.0
)

# Create cluster group
group = ClusterGroup.objects.create(name="dev-group")
from rest.models import ClusterGroupRelation
ClusterGroupRelation.objects.create(clustergroup=group, cluster=cluster)

# Create tenant
tenant = Tenant.objects.create(
    slug="DEV",
    clustergroup=group,
    attendee_limit=1000,
    meeting_limit=100
)

# Create secret
import secrets
Secret.objects.create(
    tenant=tenant,
    sub_id=0,
    secret=secrets.token_hex(32),
    secret2=secrets.token_hex(32)
)

print("Initial data created!")
```

### 10. Run Development Server

```bash
# Using Django development server
./manage.py runserver

# Or using Uvicorn (recommended)
uvicorn loadbalancer.asgi:application --reload
```

**Access**:
- Application: http://localhost:8000/
- Admin: http://localhost:8000/admin/
- API: http://localhost:8000/bigbluebutton/api/

### 11. Run Celery Workers (Optional)

**Terminal 2** - Celery Worker:
```bash
cd b3lb
celery -A loadbalancer worker -l INFO
```

**Terminal 3** - Celery Beat:
```bash
cd b3lb
celery -A loadbalancer beat -l INFO
```

---

## Docker Development Setup

### docker-compose for Development

Create `docker-compose.dev.yml`:

```yaml
version: '3.8'

services:
  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: b3lb_dev
      POSTGRES_USER: b3lb_dev
      POSTGRES_PASSWORD: devpassword
    ports:
      - "5432:5432"
    volumes:
      - postgres_dev:/var/lib/postgresql/data

  redis:
    image: redis:6.0.16-alpine
    ports:
      - "6379:6379"
    volumes:
      - redis_dev:/data

  frontend:
    build:
      context: .
      dockerfile: docker/Dockerfile.dev
    command: uvicorn --host 0.0.0.0 --reload
    ports:
      - "8000:8000"
    volumes:
      - .:/app  # Mount source code for live reload
    environment:
      DEBUG: "True"
      SECRET_KEY: "dev-secret"
      DATABASE_URL: "postgres://b3lb_dev:devpassword@postgres:5432/b3lb_dev"
      CELERY_BROKER_URL: "redis://redis:6379/0"
      CACHE_URL: "redis://redis:6379/1"
      CACHEOPS_REDIS: "redis://redis:6379/2"
      B3LB_API_BASE_DOMAIN: "localhost:8000"
    depends_on:
      - postgres
      - redis

  celery-worker:
    build:
      context: .
      dockerfile: docker/Dockerfile.dev
    command: celery-tasks
    volumes:
      - .:/app
    environment:
      SECRET_KEY: "dev-secret"
      DATABASE_URL: "postgres://b3lb_dev:devpassword@postgres:5432/b3lb_dev"
      CELERY_BROKER_URL: "redis://redis:6379/0"
      CACHEOPS_REDIS: "redis://redis:6379/2"
    depends_on:
      - postgres
      - redis

  celery-beat:
    build:
      context: .
      dockerfile: docker/Dockerfile.dev
    command: celery-beat
    volumes:
      - .:/app
    environment:
      SECRET_KEY: "dev-secret"
      DATABASE_URL: "postgres://b3lb_dev:devpassword@postgres:5432/b3lb_dev"
      CELERY_BROKER_URL: "redis://redis:6379/0"
      CACHEOPS_REDIS: "redis://redis:6379/2"
    depends_on:
      - postgres
      - redis

volumes:
  postgres_dev:
  redis_dev:
```

**Start**:
```bash
docker-compose -f docker-compose.dev.yml up
```

**Run migrations**:
```bash
docker-compose -f docker-compose.dev.yml exec frontend python manage.py migrate
```

**Create superuser**:
```bash
docker-compose -f docker-compose.dev.yml exec frontend python manage.py createsuperuser
```

---

## Project Structure

```
b3lb/
├── b3lb/                       # Main project directory
│   └── loadbalancer/          # Django project configuration
│       ├── __init__.py
│       ├── asgi.py            # ASGI application
│       ├── celery.py          # Celery configuration
│       ├── settings.py        # Django settings
│       ├── urls.py            # URL routing
│       └── wsgi.py            # WSGI application (legacy)
├── rest/                       # Main application
│   ├── models/                # Database models
│   │   ├── __init__.py
│   │   ├── lb.py              # Load balancing models
│   │   ├── tenant.py          # Tenant models
│   │   ├── meeting.py         # Meeting models
│   │   ├── record.py          # Recording models
│   │   └── metric.py          # Metrics models
│   ├── classes/               # Business logic classes
│   │   ├── api.py             # BBB API handler
│   │   └── ...
│   ├── task/                  # Celery tasks (organized)
│   │   ├── core.py            # Core tasks
│   │   ├── recording.py       # Recording tasks
│   │   ├── statistics.py      # Statistics tasks
│   │   └── b3lb.py            # Task wrappers
│   ├── admin.py               # Django admin configuration
│   ├── apps.py                # App configuration
│   ├── constants.py           # Constants and defaults
│   ├── tasks.py               # Task definitions
│   ├── views.py               # HTTP views
│   └── tests.py               # Tests
├── docker/                     # Docker configurations
│   ├── Dockerfile             # Standard image
│   ├── Dockerfile.pypy        # PyPy image
│   ├── Dockerfile.static      # Static files image
│   ├── Dockerfile.dev         # Development image
│   ├── Dockerfile.render      # Rendering image
│   └── entrypoint.sh          # Container entrypoint
├── scripts/                    # Utility scripts
│   └── bbb/                   # BBB node scripts
│       ├── load/              # CPU load script
│       ├── push/              # Recording upload script
│       └── cleaner/           # Recording cleanup script
├── requirements/               # Python dependencies
│   ├── requirements.txt       # Core dependencies
│   └── requirements_extra.txt # Extra dependencies
├── manage.py                   # Django management script
└── README.md                   # Project README
```

---

## Code Organization

### Models (`rest/models/`)

**Conventions**:
- One file per model category
- Use Django ORM best practices
- Add indexes for common queries
- Document complex relationships

**Example**:
```python
# rest/models/tenant.py
from django.db import models

class Tenant(models.Model):
    slug = models.SlugField(max_length=10, unique=True)
    clustergroup = models.ForeignKey('ClusterGroup', on_delete=models.PROTECT)

    class Meta:
        db_table = 'rest_tenant'
        indexes = [
            models.Index(fields=['slug']),
        ]

    def __str__(self):
        return self.slug
```

---

### Views (`rest/views.py`)

**Conventions**:
- Use async views for I/O-bound operations
- Validate input parameters
- Use proper HTTP status codes
- Log important events

**Example**:
```python
# rest/views.py
from django.http import JsonResponse
from asgiref.sync import sync_to_async

async def bbb_entrypoint(request, endpoint):
    # Tenant resolution
    tenant = await sync_to_async(get_tenant)(request)

    # Checksum validation
    if not validate_checksum(request, tenant.secret):
        return error_response("checksumError")

    # Handle endpoint
    handler = ClientB3lbRequest(request, tenant)
    return await handler.handle(endpoint)
```

---

### Tasks (`rest/task/`)

**Conventions**:
- Keep tasks small and focused
- Use proper queue routing
- Implement retry logic
- Log task execution

**Example**:
```python
# rest/task/core.py
from celery import shared_task
from rest.constants import get_core_queue

@shared_task(
    queue=get_core_queue(),
    autoretry_for=(Exception,),
    retry_kwargs={'max_retries': 3},
    retry_backoff=True
)
def update_node_status(node_id):
    node = Node.objects.get(id=node_id)
    # Update logic
    logger.info(f"Updated node {node.slug}")
```

---

### Admin (`rest/admin.py`)

**Conventions**:
- Provide useful list displays
- Add filters and search fields
- Create custom actions
- Link related objects

**Example**:
```python
# rest/admin.py
from django.contrib import admin

@admin.register(Node)
class NodeAdmin(admin.ModelAdmin):
    list_display = ['slug', 'domain', 'cluster', 'load', 'has_errors', 'maintenance']
    list_filter = ['cluster', 'has_errors', 'maintenance']
    search_fields = ['slug', 'domain']
    actions = ['set_maintenance', 'clear_maintenance']

    def set_maintenance(self, request, queryset):
        queryset.update(maintenance=True)
    set_maintenance.short_description = "Set to maintenance mode"
```

---

## Testing

### Unit Tests

**Location**: `rest/tests.py`

**Run Tests**:
```bash
./manage.py test
```

**Example Test**:
```python
# rest/tests.py
from django.test import TestCase
from rest.models import Cluster, Node

class NodeTestCase(TestCase):
    def setUp(self):
        self.cluster = Cluster.objects.create(name="test-cluster")
        self.node = Node.objects.create(
            cluster=self.cluster,
            slug="test-node",
            domain="test.example.com",
            secret="secret123"
        )

    def test_node_load_calculation(self):
        self.node.attendees = 100
        self.node.meetings = 10
        self.node.cpu_load = 50.0
        self.node.save()

        load = self.node.load
        self.assertGreater(load, 0)
        self.assertIsInstance(load, float)

    def test_maintenance_mode(self):
        self.node.maintenance = True
        self.node.save()

        self.assertEqual(self.node.load, -2)
```

---

### Integration Tests

**Test BBB API Endpoints**:
```python
from django.test import TestCase
from django.test.client import Client

class APITestCase(TestCase):
    def setUp(self):
        self.client = Client()
        # Create tenant, secret, cluster, node
        ...

    def test_create_meeting(self):
        params = {
            'meetingID': 'test-123',
            'name': 'Test Meeting',
            'checksum': self.generate_checksum('create', {...})
        }
        response = self.client.get('/bigbluebutton/api/create', params)
        self.assertEqual(response.status_code, 200)
        # Verify response XML
```

---

### Manual Testing

**Using API Mate**:
1. Open https://mconf.github.io/api-mate/
2. Enter B3LB endpoint: `http://localhost:8000/bigbluebutton/api/`
3. Enter secret from database
4. Test create, join, getMeetings, etc.

**Using curl**:
```bash
# Test ping endpoint
curl http://localhost:8000/b3lb/ping

# Test stats endpoint
curl http://localhost:8000/b3lb/stats
```

---

## Debugging

### Django Debug Toolbar

**Install**:
```bash
pip install django-debug-toolbar
```

**Configure** (`settings.py`):
```python
if DEBUG:
    INSTALLED_APPS += ['debug_toolbar']
    MIDDLEWARE += ['debug_toolbar.middleware.DebugToolbarMiddleware']
    INTERNAL_IPS = ['127.0.0.1']
```

**Access**: Shows SQL queries, cache hits, request/response data

---

### Django Shell

**Interactive Python Shell**:
```bash
./manage.py shell
```

**Test Queries**:
```python
from rest.models import *

# Get all tenants
tenants = Tenant.objects.all()

# Get meetings
meetings = Meeting.objects.select_related('node', 'secret')

# Test load calculation
node = Node.objects.first()
print(f"Node load: {node.load}")
```

---

### Celery Debugging

**Run Worker in Foreground**:
```bash
celery -A loadbalancer worker -l DEBUG
```

**Test Task Execution**:
```python
from rest.tasks import update_node_status
result = update_node_status.delay(node_id=1)
print(result.get())  # Wait for result
```

---

## Code Style

### PEP 8 Compliance

**Tools**:
- **black**: Code formatter
- **flake8**: Linter
- **isort**: Import sorter

**Install**:
```bash
pip install black flake8 isort
```

**Usage**:
```bash
# Format code
black rest/

# Check style
flake8 rest/

# Sort imports
isort rest/
```

---

### Type Hints

**Use Type Hints** for better code clarity:
```python
from typing import Optional, List
from rest.models import Node

def get_available_nodes(cluster_id: int) -> List[Node]:
    nodes: List[Node] = Node.objects.filter(cluster_id=cluster_id)
    return [n for n in nodes if n.load >= 0]

def find_node(slug: str) -> Optional[Node]:
    try:
        return Node.objects.get(slug=slug)
    except Node.DoesNotExist:
        return None
```

---

## Git Workflow

### Branching Strategy

- **main**: Stable production code
- **develop**: Development branch
- **feature/**: Feature branches
- **bugfix/**: Bug fix branches
- **hotfix/**: Critical production fixes

**Create Feature Branch**:
```bash
git checkout -b feature/add-new-endpoint develop
```

**Merge Back**:
```bash
git checkout develop
git merge --no-ff feature/add-new-endpoint
git branch -d feature/add-new-endpoint
```

---

### Commit Messages

**Format**:
```
type(scope): subject

body

footer
```

**Types**:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation
- `style`: Code style
- `refactor`: Code refactoring
- `test`: Tests
- `chore`: Maintenance

**Example**:
```
feat(api): add getRecordingTextTracks endpoint

Implement BBB 2.6 recording text tracks API endpoint.
Includes database model changes and API handler.

Closes #123
```

---

## Contributing

### Contribution Process

1. **Fork Repository**
2. **Create Feature Branch**
3. **Make Changes**
4. **Write Tests**
5. **Commit Changes**
6. **Push to Fork**
7. **Create Pull Request**

---

### Pull Request Guidelines

- **Description**: Clear description of changes
- **Tests**: Include tests for new features
- **Documentation**: Update docs if needed
- **Code Style**: Follow PEP 8
- **Commits**: Clean, logical commits
- **Review**: Address review feedback

---

## Development Resources

### Official Documentation

- Django: https://docs.djangoproject.com/
- Celery: https://docs.celeryproject.org/
- PostgreSQL: https://www.postgresql.org/docs/
- Redis: https://redis.io/documentation

### BBB API Documentation

- API Docs: https://docs.bigbluebutton.org/development/api/
- API Mate: https://mconf.github.io/api-mate/

### B3LB Documentation

- Official Docs: https://docs.b3lb.io/
- GitHub: https://github.com/DE-IBH/b3lb

---

## Next Steps

- [Docker Deployment](./05-docker-deployment.md): Deploy your changes
- [Operations](./08-operations.md): Monitor in production
- [BBB Node Scripts](./09-bbb-node-scripts.md): Set up BBB nodes
