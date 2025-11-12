# B3LB Overview

## Project Identity

**B3LB** (BigBlueButton Load Balancer) is an open-source API load balancer for BigBlueButton, built on the Django Python web framework. It serves as an enterprise-grade alternative to Scalelite, specifically designed for large-scale deployments supporting **100+ BigBlueButton conference nodes** with high attendee join rates.

### Key Information

- **Developer**: IBH IT-Service GmbH
- **Initial Release**: Fall 2020 (internally), February 2021 (public)
- **Current Version**: 3.3.2 (as of 2025-06-11)
- **License**: GNU Affero General Public License v3.0
- **Official Documentation**: https://docs.b3lb.io/
- **Status**: Independent project using BigBlueButton (not endorsed by BigBlueButton Inc.)

## Technology Stack

### Core Technologies

- **Web Framework**: Django 5.2.2
- **Python Version**: 3.12 (CPython) or 3.10 (PyPy for workers)
- **ASGI Server**: Uvicorn with async/await support
- **Task Queue**: Celery 5.5.3
- **Message Broker**: Redis
- **Database**: PostgreSQL 9.5+ (highly recommended)
- **Caching**: Redis (django-cacheops for ORM, django-redis for cache backend)
- **HTTP Client**: aiohttp (async operations)
- **Reverse Proxy**: Traefik (recommended)

### Additional Technologies

- **Static File Server**: Caddy 2.9.1
- **File Storage**: S3-compatible or local filesystem
- **Container Runtime**: Docker, Docker Swarm, or Kubernetes
- **Monitoring**: Prometheus metrics export
- **Task Monitoring**: Celery Flower (optional)

## Core Capabilities

### 1. API Load Balancing
- Full BigBlueButton API implementation
- Intelligent load distribution across multiple BBB nodes
- Automatic node selection based on real-time metrics
- Maintenance mode support for graceful node updates

### 2. Multi-Tenant Architecture
- Per-tenant configuration and isolation
- Custom cluster group assignment per tenant
- Tenant-specific limits (attendees, meetings)
- API secret management with rollover support
- Sub-secrets for API key rotation (0-999 per tenant)

### 3. Customization & Branding
- Per-tenant logo customization
- Custom presentation slides
- Custom CSS for branding
- Database-stored assets (not filesystem)
- BBB parameter customization (block, set, override)

### 4. Recording Management
- Post-archive upload from BBB nodes
- Multi-profile video rendering
- S3 or local storage
- Recording metadata management
- Automatic cleanup based on retention policies
- Publishing/unpublishing controls

### 5. Monitoring & Observability
- Prometheus metrics export (global and per-tenant)
- Real-time statistics API
- Health check endpoints
- Per-node status tracking
- Meeting and attendee metrics
- Limit hit tracking

### 6. Intelligent Load Distribution
- Multi-factor load calculation:
  - Current attendee count × attendee factor
  - Current meeting count × meeting factor
  - Synthetic CPU load (polynomial calculation)
- Polynomial CPU load calculation prevents overload
- Configurable load factors per cluster
- Automatic node exclusion on errors

### 7. Asynchronous Operations
- Full async/await support in Django views
- Asynchronous HTTP requests via aiohttp
- Non-blocking node communication
- Background task processing via Celery
- High-concurrency request handling

### 8. Scalability Features
- Horizontal scaling of frontend instances
- Horizontal scaling of Celery workers
- Redis-based caching for performance
- ORM query caching via django-cacheops
- Meeting list caching per tenant
- Optimized database queries

## Key Features Comparison

### B3LB vs. Scalelite

| Feature | B3LB | Scalelite |
|---------|------|-----------|
| **Language** | Python/Django | Ruby on Rails |
| **Async Support** | Native async/await | Limited |
| **Multi-Tenancy** | Built-in with advanced features | Basic |
| **Customization** | Per-tenant assets, CSS, parameters | Limited |
| **Load Algorithm** | Polynomial CPU + multi-factor | Simpler algorithm |
| **Recording Rendering** | Multi-profile with custom settings | Standard rendering |
| **Deployment** | Docker-based, flexible | Docker-based |
| **Scale Target** | 100+ nodes | Medium deployments |
| **Admin Interface** | Django admin with custom actions | Rails admin |
| **Monitoring** | Prometheus + statistics API | Basic monitoring |

## Architecture Highlights

### Component Layout

```
┌─────────────────────────────────────────────────────────────┐
│                      Reverse Proxy (Traefik)                 │
│         SSL Termination + ACL + Load Balancing              │
└──────────┬─────────────────────────────────┬────────────────┘
           │                                 │
           ▼                                 ▼
┌──────────────────────┐          ┌──────────────────────┐
│   B3LB Frontend      │          │   Static Assets      │
│   (Uvicorn/ASGI)     │          │   (Caddy)            │
│   Multiple instances │          │   CSS/JS/Images      │
└──────────┬───────────┘          └──────────────────────┘
           │
           ▼
┌─────────────────────────────────────────────────────────────┐
│                         Redis Layer                          │
│              Cache Backend + ORM Cache + Broker             │
└──────────┬──────────────────────────────────────────────────┘
           │
           ▼
┌─────────────────────────────────────────────────────────────┐
│                     PostgreSQL Database                      │
│         Clusters, Nodes, Tenants, Meetings, Records         │
└─────────────────────────────────────────────────────────────┘
           ▲
           │
┌──────────┴───────────┐
│  Celery Workers      │
│  - Beat (scheduler)  │
│  - Task workers      │
│  Background jobs     │
└──────────────────────┘
```

### Request Flow

1. **Client Request** → Traefik reverse proxy
2. **Traefik** → Frontend instance (round-robin)
3. **Frontend** → Tenant resolution via slug/domain
4. **Authentication** → Checksum validation
5. **BBB API Call** → Load balancing decision
6. **Node Selection** → Based on load algorithm
7. **Proxy Request** → Selected BBB node (async)
8. **Response** → Back to client

### Background Processing

1. **Celery Beat** → Triggers periodic tasks
2. **Task Queues** → Core, housekeeping, record, statistics
3. **Workers** → Process tasks asynchronously
4. **Tasks**:
   - Poll BBB nodes for status (CPU, meetings)
   - Update meeting lists and metrics
   - Process and render recordings
   - Aggregate statistics
   - Cleanup old data

## URL Patterns

### Wildcard DNS (Recommended)

```
{tenant}.{base_domain}/bigbluebutton/api/
{tenant}-{sub_id}.{base_domain}/bigbluebutton/api/
```

Example:
- `acme.bbb.example.com/bigbluebutton/api/`
- `acme-5.bbb.example.com/bigbluebutton/api/` (sub-secret #5)

### Single Domain (Path-Based)

```
{base_domain}/b3lb/t/{tenant}/bbb/api/
{base_domain}/b3lb/t/{tenant}-{sub_id}/bbb/api/
```

Example:
- `bbb.example.com/b3lb/t/acme/bbb/api/`
- `bbb.example.com/b3lb/t/acme-5/bbb/api/`

## Use Cases

### Ideal For

- **Large Educational Institutions**: Universities with 100+ BBB nodes
- **Enterprise Deployments**: Organizations requiring high availability
- **Multi-Tenant Providers**: Hosting providers serving multiple clients
- **High-Scale Events**: Virtual conferences with thousands of attendees
- **Customization Requirements**: Organizations needing branding and custom parameters

### Not Ideal For

- **Small Deployments**: Single BBB node or small clusters (< 5 nodes)
- **Simple Setups**: Basic load balancing without multi-tenancy needs
- **Limited Resources**: Environments without PostgreSQL/Redis infrastructure
- **Ruby Ecosystem**: Teams already invested in Rails/Ruby tooling

## Design Philosophy

### Performance First
- Async operations prevent blocking
- Redis caching minimizes database queries
- ORM caching reduces repetitive lookups
- Horizontal scaling for increased load

### Multi-Tenant by Design
- Isolation between tenants
- Per-tenant configuration
- Separate secrets and limits
- Independent branding and assets

### Production Ready
- Comprehensive error handling
- Graceful degradation
- Health monitoring
- Operational admin actions

### Developer Friendly
- Django admin interface
- Management commands
- Standard Django patterns
- Extensive logging

## Getting Started

### Quick Links

- **Official Documentation**: https://docs.b3lb.io/en/latest/
- **Prerequisites**: [docs/04-configuration.md](./04-configuration.md)
- **Docker Deployment**: [docs/05-docker-deployment.md](./05-docker-deployment.md)
- **Development Guide**: [docs/07-development-guide.md](./07-development-guide.md)
- **Operations Manual**: [docs/08-operations.md](./08-operations.md)

### Basic Setup Steps

1. Set up infrastructure (PostgreSQL, Redis, reverse proxy)
2. Configure DNS (wildcard or single domain)
3. Deploy B3LB services via Docker
4. Run database migrations
5. Create superuser account
6. Configure clusters and BBB nodes
7. Create tenants and generate secrets
8. Configure BBB nodes with load script
9. Test API endpoints
10. Monitor metrics and logs

## License & Support

### License
B3LB is licensed under the **GNU Affero General Public License v3.0** (AGPL-3.0). This means:
- Source code must be made available for any deployed modifications
- Network use counts as distribution (AGPL provision)
- Commercial use is permitted with license compliance
- No warranty or liability from developers

### Community & Support
- **GitHub Repository**: Primary source and issue tracking
- **Official Docs**: Comprehensive deployment and configuration guides
- **Developer**: IBH IT-Service GmbH (professional services available)

### Contributing
As an open-source project, B3LB welcomes contributions:
- Bug reports and feature requests via GitHub issues
- Code contributions via pull requests
- Documentation improvements
- Testing and feedback

## Next Steps

1. Read the [Architecture Guide](./01-architecture.md) for system design details
2. Review [Database Schema](./02-database-schema.md) for data models
3. Explore [API Endpoints](./03-api-endpoints.md) for integration details
4. Follow [Docker Deployment](./05-docker-deployment.md) for installation
5. Consult [Operations Manual](./08-operations.md) for ongoing management
