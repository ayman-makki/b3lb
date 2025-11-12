# B3LB Database Schema

## Overview

B3LB uses PostgreSQL (9.5+) as its primary data store with 16 core models organized into functional categories. The schema is designed for multi-tenant isolation, efficient load balancing, and comprehensive recording management.

## Entity Relationship Overview

```
┌────────────────┐
│ ClusterGroup   │
└────────┬───────┘
         │ 1:N
         ▼
┌────────────────┐       ┌────────────────┐
│ Tenant         │──────▶│ Asset          │
└────────┬───────┘  1:1  └────────────────┘
         │ 1:N
         ▼
┌────────────────┐       ┌────────────────┐
│ Secret         │──────▶│ Parameter      │
└────────┬───────┘  1:N  └────────────────┘
         │
         │ 1:N
         ▼
┌────────────────┐       ┌────────────────┐
│ Meeting        │──────▶│ Node           │
└────────┬───────┘  N:1  └────────┬───────┘
         │                        │ N:1
         │                        ▼
         │                ┌────────────────┐
         │                │ Cluster        │
         │                └────────────────┘
         │ 1:N
         ▼
┌────────────────┐       ┌────────────────┐
│ RecordSet      │──────▶│ Record         │
└────────────────┘  1:N  └────────┬───────┘
                                  │ N:1
                                  ▼
                         ┌────────────────┐
                         │ RecordProfile  │
                         └────────────────┘

┌────────────────┐
│ Metric         │──────▶ Per-tenant/node metrics
└────────────────┘

┌────────────────┐
│ Stats          │──────▶ Aggregated statistics
└────────────────┘
```

## Model Categories

### Load Balancing Infrastructure
- [Cluster](#cluster-model)
- [Node](#node-model)
- [ClusterGroup](#clustergroup-model)
- [ClusterGroupRelation](#clustergrouprelation-model)

### Multi-Tenant Management
- [Tenant](#tenant-model)
- [Secret](#secret-model)
- [Asset](#asset-model)
- [Parameter](#parameter-model)

### Meeting Management
- [Meeting](#meeting-model)
- [NodeMeetingList](#nodemeetinglist-model)
- [SecretMeetingList](#secretmeetinglist-model)

### Recording Management
- [RecordSet](#recordset-model)
- [Record](#record-model)
- [RecordProfile](#recordprofile-model)

### Metrics & Statistics
- [Metric](#metric-model)
- [Stats](#stats-model)
- [SecretMetricsList](#secretmetricslist-model)

---

## Load Balancing Models

### Cluster Model

**Purpose**: Group of BBB nodes with shared load calculation configuration

**Location**: `rest/models/lb.py`

#### Fields

| Field | Type | Description | Default |
|-------|------|-------------|---------|
| `id` | AutoField | Primary key | Auto |
| `name` | CharField(200) | Cluster name (unique) | Required |
| `load_a_factor` | FloatField | Load factor per attendee | 1.0 |
| `load_m_factor` | FloatField | Load factor per meeting | 10.0 |
| `load_cpu_series_iteratations` | IntegerField | CPU polynomial iterations | 6 |
| `load_cpu_maximum` | IntegerField | Maximum CPU load value | 5000 |
| `sha_algorithm` | CharField(10) | Checksum algorithm | "SHA256" |

#### Methods

```python
def node_count(self) -> int
    # Count all nodes in cluster

def active_node_count(self) -> int
    # Count nodes not in maintenance

def maintenance_node_count(self) -> int
    # Count nodes in maintenance mode
```

#### Relationships

- **Has many**: Nodes
- **Belongs to many**: ClusterGroups (via ClusterGroupRelation)

#### Constraints

- Unique: `name`
- Choices for `sha_algorithm`: SHA256, SHA384, SHA512

#### Usage

```python
cluster = Cluster.objects.create(
    name="main-cluster",
    load_a_factor=1.0,
    load_m_factor=10.0,
    load_cpu_series_iteratations=6,
    load_cpu_maximum=5000
)
```

---

### Node Model

**Purpose**: Individual BigBlueButton server with current metrics

**Location**: `rest/models/lb.py`

#### Fields

| Field | Type | Description | Default |
|-------|------|-------------|---------|
| `id` | AutoField | Primary key | Auto |
| `cluster` | ForeignKey(Cluster) | Parent cluster | Required |
| `slug` | SlugField(200) | Node identifier | Required |
| `domain` | CharField(200) | Node domain/IP | Required |
| `secret` | CharField(200) | BBB API secret | Required |
| `protocol` | CharField(10) | Protocol (http/https) | From settings |
| `port` | IntegerField | Port number | 443 |
| `bbb_endpoint` | CharField(200) | BBB API path | "bigbluebutton/api/" |
| `load_endpoint` | CharField(200) | Load endpoint path | "b3lb/load" |
| `cpu_load` | FloatField | Current CPU load (0-100) | 0 |
| `attendees` | IntegerField | Current attendee count | 0 |
| `meetings` | IntegerField | Current meeting count | 0 |
| `has_errors` | BooleanField | Error flag | False |
| `maintenance` | BooleanField | Maintenance mode flag | False |

#### Properties

```python
@property
def load(self) -> float
    # Calculate current load score
    # Returns -2 for maintenance, -1 for errors
    # Otherwise: (attendees × load_a_factor) +
    #            (meetings × load_m_factor) +
    #            synthetic_cpu_load

@property
def api_url(self) -> str
    # Full BBB API URL
    # Example: "https://bbb1.example.com:443/bigbluebutton/api/"

@property
def load_url(self) -> str
    # Full load endpoint URL
    # Example: "https://bbb1.example.com:443/b3lb/load"
```

#### Methods

```python
def meetings_on_node(self) -> QuerySet[Meeting]
    # Get all meetings currently on this node

def cpu_load_formatted(self) -> str
    # Format: "85.3%"
```

#### Relationships

- **Belongs to**: Cluster
- **Has many**: Meetings

#### Constraints

- Unique together: (`cluster`, `slug`)
- Unique together: (`cluster`, `domain`)

#### Indexes

- Index on: `slug`
- Index on: `has_errors`
- Index on: `maintenance`

#### Usage

```python
node = Node.objects.create(
    cluster=cluster,
    slug="bbb01",
    domain="bbb01.example.com",
    secret="bbb_secret_key",
    protocol="https",
    port=443
)

# Get load
current_load = node.load  # e.g., 145.3

# Check if available
if node.load >= 0:
    print("Node available for meetings")
```

---

### ClusterGroup Model

**Purpose**: Logical grouping of clusters for tenant assignment

**Location**: `rest/models/lb.py`

#### Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | AutoField | Primary key |
| `name` | CharField(200) | Group name (unique) |

#### Methods

```python
def all_nodes(self) -> QuerySet[Node]
    # Get all nodes from all clusters in this group
```

#### Relationships

- **Has many**: Tenants
- **Has many**: Clusters (via ClusterGroupRelation)

#### Usage

```python
group = ClusterGroup.objects.create(name="production")

# Add clusters to group
ClusterGroupRelation.objects.create(
    clustergroup=group,
    cluster=cluster1
)

# Get all nodes
all_nodes = group.all_nodes()
```

---

### ClusterGroupRelation Model

**Purpose**: Many-to-many relationship between ClusterGroups and Clusters

**Location**: `rest/models/lb.py`

#### Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | AutoField | Primary key |
| `clustergroup` | ForeignKey(ClusterGroup) | Parent group |
| `cluster` | ForeignKey(Cluster) | Related cluster |

#### Constraints

- Unique together: (`clustergroup`, `cluster`)

---

## Multi-Tenant Models

### Tenant Model

**Purpose**: Main tenant entity with configuration and limits

**Location**: `rest/models/tenant.py`

#### Fields

| Field | Type | Description | Validation |
|-------|------|-------------|------------|
| `id` | AutoField | Primary key | Auto |
| `slug` | SlugField(10) | Tenant identifier | 2-10 uppercase letters |
| `clustergroup` | ForeignKey(ClusterGroup) | Assigned cluster group | Required |
| `attendee_limit` | IntegerField | Max concurrent attendees | Default: 999999 |
| `meeting_limit` | IntegerField | Max concurrent meetings | Default: 999999 |
| `record_by_default` | BooleanField | Enable recording by default | Default: False |
| `stats_token` | CharField(40) | API token for stats | Auto-generated |

#### Validators

```python
slug: RegexValidator(
    regex=r'^[A-Z]{2,10}$',
    message='2-10 uppercase letters required'
)
```

#### Methods

```python
def get_asset(self) -> Asset
    # Get or create tenant asset object

def api_mate_join_link(self, secret_id=0) -> str
    # Generate API Mate test link for tenant
```

#### Relationships

- **Belongs to**: ClusterGroup
- **Has many**: Secrets
- **Has one**: Asset
- **Has many**: Parameters

#### Constraints

- Unique: `slug`
- Unique: `stats_token`

#### Admin Features

- Custom admin actions
- API Mate integration
- Recording toggle

#### Usage

```python
tenant = Tenant.objects.create(
    slug="ACME",
    clustergroup=group,
    attendee_limit=500,
    meeting_limit=50,
    record_by_default=True
)

# Check limits
if tenant.attendee_limit > current_attendees:
    # Allow more attendees
    pass
```

---

### Secret Model

**Purpose**: API credentials per tenant with sub-IDs for key rotation

**Location**: `rest/models/tenant.py`

#### Fields

| Field | Type | Description | Validation |
|-------|------|-------------|------------|
| `id` | AutoField | Primary key | Auto |
| `tenant` | ForeignKey(Tenant) | Parent tenant | Required |
| `sub_id` | IntegerField | Sub-secret ID | 0-999 |
| `secret` | CharField(64) | Primary API secret | 64 chars |
| `secret2` | CharField(64) | Rollover API secret | 64 chars |
| `attendee_limit` | IntegerField | Override tenant limit | Nullable |
| `meeting_limit` | IntegerField | Override tenant limit | Nullable |
| `slide_id` | IntegerField | Override default slide | Nullable |
| `record_by_default` | BooleanField | Override recording | Nullable |

#### Properties

```python
@property
def endpoint(self) -> str
    # Generate API endpoint URL
    # Returns: "https://{tenant}-{sub_id}.{domain}/bigbluebutton/api/"
    # Or: "https://{tenant}.{domain}/bigbluebutton/api/" if sub_id=0
```

#### Methods

```python
def get_limits(self) -> tuple[int, int]
    # Returns: (effective_attendee_limit, effective_meeting_limit)
    # Uses secret override or falls back to tenant limits

def api_mate_join_link(self) -> str
    # Generate API Mate test link

def api_mate_create_link(self) -> str
    # Generate API Mate create link
```

#### Relationships

- **Belongs to**: Tenant
- **Has many**: Meetings
- **Has many**: Parameters

#### Constraints

- Unique together: (`tenant`, `sub_id`)
- Check: `sub_id >= 0 AND sub_id <= 999`

#### Usage

```python
# Primary secret
secret = Secret.objects.create(
    tenant=tenant,
    sub_id=0,
    secret=secrets.token_hex(32),
    secret2=secrets.token_hex(32)
)

# Additional secret with overrides
secret_5 = Secret.objects.create(
    tenant=tenant,
    sub_id=5,
    secret=secrets.token_hex(32),
    secret2=secrets.token_hex(32),
    attendee_limit=100,  # Override
    meeting_limit=10     # Override
)

# Get effective limits
attendee_limit, meeting_limit = secret.get_limits()

# Get API endpoint
endpoint = secret.endpoint
# "https://acme-5.bbb.example.com/bigbluebutton/api/"
```

---

### Asset Model

**Purpose**: Tenant-specific customization assets (logo, slide, CSS)

**Location**: `rest/models/tenant.py`

#### Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | AutoField | Primary key |
| `tenant` | OneToOneField(Tenant) | Parent tenant (unique) |
| `logo` | CharField(200) | Logo file reference |
| `slide` | CharField(200) | Slide file reference |
| `css` | CharField(200) | CSS file reference |

#### Storage

All files stored in database via `django-db-file-storage`:

- `AssetLogo`: Logo image files
- `AssetSlide`: Slide image files
- `AssetCustomCSS`: CSS stylesheet files

#### Methods

```python
def get_logo_url(self) -> str
    # Returns: "/b3lb/t/{tenant_slug}/logo"

def get_slide_url(self) -> str
    # Returns: "/b3lb/t/{tenant_slug}/slide"

def get_css_url(self) -> str
    # Returns: "/b3lb/t/{tenant_slug}/css"
```

#### Relationships

- **Belongs to**: Tenant (one-to-one)

#### Usage

```python
asset = tenant.get_asset()

# Upload logo
from django.core.files import File
with open('logo.png', 'rb') as f:
    asset.logo.save('logo.png', File(f))

# Access URLs
logo_url = asset.get_logo_url()
# Use in BBB: logo={logo_url}
```

---

### Parameter Model

**Purpose**: Per-tenant BBB parameter customization

**Location**: `rest/models/tenant.py`

#### Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | AutoField | Primary key |
| `tenant` | ForeignKey(Tenant) | Parent tenant (optional) |
| `secret` | ForeignKey(Secret) | Parent secret (optional) |
| `create_join` | CharField(10) | Apply to create/join | Choices |
| `mode` | CharField(10) | Parameter mode | Choices |
| `name` | CharField(200) | Parameter name | Required |
| `value` | CharField(200) | Parameter value | Optional |

#### Choices

**create_join**:
- `CREATE`: Apply to create API calls
- `JOIN`: Apply to join API calls
- `BOTH`: Apply to both

**mode**:
- `BLOCK`: Remove parameter from request
- `SET`: Add parameter if not present
- `OVERRIDE`: Force parameter value

#### Constraints

- Unique together: (`tenant`, `secret`, `create_join`, `name`)
- Either `tenant` OR `secret` must be set (not both, not neither)

#### Usage

```python
# Block a parameter for all tenant requests
Parameter.objects.create(
    tenant=tenant,
    create_join='BOTH',
    mode='BLOCK',
    name='guestPolicy'
)

# Force a parameter value for specific secret
Parameter.objects.create(
    secret=secret,
    create_join='CREATE',
    mode='OVERRIDE',
    name='record',
    value='true'
)

# Set default if not present
Parameter.objects.create(
    tenant=tenant,
    create_join='JOIN',
    mode='SET',
    name='userdata-welcome',
    value='Welcome to ACME meetings!'
)
```

---

## Meeting Models

### Meeting Model

**Purpose**: Active meeting tracking with participant metrics

**Location**: `rest/models/meeting.py`

#### Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | AutoField | Primary key |
| `secret` | ForeignKey(Secret) | Parent secret/tenant |
| `meeting_id` | CharField(200) | BBB meeting ID |
| `meeting_name` | CharField(200) | Meeting room name |
| `node` | ForeignKey(Node) | Assigned BBB node |
| `create_time` | DateTimeField | Meeting creation time |
| `end_callback_url` | URLField | End callback URL |
| `attendees` | IntegerField | Current attendee count |
| `listeners` | IntegerField | Listener count |
| `voice` | IntegerField | Voice participant count |
| `videos` | IntegerField | Video participant count |
| `moderators` | IntegerField | Moderator count |
| `origin` | CharField(200) | BBB origin metadata |
| `nonce` | UUIDField | Recording reference |

#### Properties

```python
@property
def tenant_slug(self) -> str
    # Returns parent tenant's slug
```

#### Methods

```python
def get_node_for_meeting(meeting_id: str, secret: Secret) -> Node
    # Class method to resolve meeting → node
    # Used in join API
```

#### Relationships

- **Belongs to**: Secret
- **Belongs to**: Node
- **Has many**: RecordSets (via nonce)

#### Constraints

- Unique together: (`secret`, `meeting_id`)
- Index on: `meeting_id`
- Index on: `node`
- Index on: `nonce`

#### Usage

```python
# Create meeting record
meeting = Meeting.objects.create(
    secret=secret,
    meeting_id="meeting-123",
    meeting_name="Team Standup",
    node=selected_node,
    nonce=uuid.uuid4(),
    end_callback_url="https://example.com/callback"
)

# Update participant counts (from polling)
meeting.attendees = 25
meeting.videos = 12
meeting.save()

# Resolve meeting for join
node = Meeting.get_node_for_meeting("meeting-123", secret)
```

---

### NodeMeetingList Model

**Purpose**: Cached XML response from node's getMeetings API

**Location**: `rest/models/meeting.py`

#### Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | AutoField | Primary key |
| `node` | ForeignKey(Node) | Parent node (unique) |
| `meetings_xml` | TextField | XML response |

#### Constraints

- Unique: `node`

#### Usage

```python
# Cache node's meeting list
NodeMeetingList.objects.update_or_create(
    node=node,
    defaults={'meetings_xml': xml_response}
)

# Retrieve cached list
cached = NodeMeetingList.objects.get(node=node)
xml_data = cached.meetings_xml
```

---

### SecretMeetingList Model

**Purpose**: Cached aggregated meeting list per tenant/secret

**Location**: `rest/models/meeting.py`

#### Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | AutoField | Primary key |
| `secret` | ForeignKey(Secret) | Parent secret (unique) |
| `meetings_xml` | TextField | Aggregated XML |

#### Constraints

- Unique: `secret`

#### Usage

```python
# Cache secret's meeting list
SecretMeetingList.objects.update_or_create(
    secret=secret,
    defaults={'meetings_xml': aggregated_xml}
)

# getMeetings API retrieves from cache
cached = SecretMeetingList.objects.get(secret=secret)
return cached.meetings_xml
```

---

## Recording Models

### RecordSet Model

**Purpose**: Raw recording archive uploaded from BBB node

**Location**: `rest/models/record.py`

#### Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | CharField(200) | Primary key (record ID) |
| `nonce` | UUIDField | Meeting reference |
| `meeting_id` | CharField(200) | BBB meeting ID |
| `tenant_slug` | CharField(10) | Tenant identifier |
| `meta_name` | CharField(200) | Meeting name |
| `start_time` | DateTimeField | Recording start |
| `end_time` | DateTimeField | Recording end |
| `participants` | IntegerField | Participant count |
| `status` | CharField(20) | Processing status |
| `format_type` | CharField(20) | Format (presentation/video) |
| `raw_size` | IntegerField | Archive size (bytes) |

#### Status Choices

- `UNKNOWN`: Initial state
- `UPLOADED`: Archive received
- `RENDERED`: Processing complete
- `DELETING`: Deletion in progress

#### Relationships

- **Has many**: Records (rendered videos)

#### Constraints

- Primary key: `id`
- Index on: `nonce`
- Index on: `tenant_slug`

#### Usage

```python
# Create from upload
recordset = RecordSet.objects.create(
    id="abc-123-def-456",
    nonce=meeting.nonce,
    meeting_id=meeting.meeting_id,
    tenant_slug=meeting.tenant_slug,
    status='UPLOADED',
    raw_size=1024*1024*500  # 500MB
)

# Queue for rendering
from rest.tasks import render_records
render_records.delay(recordset.id)
```

---

### Record Model

**Purpose**: Rendered video file from RecordSet

**Location**: `rest/models/record.py`

#### Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | AutoField | Primary key |
| `recordset` | ForeignKey(RecordSet) | Parent recordset |
| `record_id` | CharField(200) | Composite ID |
| `profile` | ForeignKey(RecordProfile) | Render profile |
| `published` | BooleanField | Published flag |
| `listed` | BooleanField | Listed in results |
| `file` | CharField(200) | Video file reference |
| `meeting_id` | CharField(200) | BBB meeting ID |
| `nonce` | UUIDField | Meeting reference |
| `tenant_slug` | CharField(10) | Tenant identifier |
| `meta_name` | CharField(200) | Meeting name |
| `start_time` | DateTimeField | Recording start |
| `end_time` | DateTimeField | Recording end |
| `participants` | IntegerField | Participant count |
| `format_type` | CharField(20) | Format type |

#### Properties

```python
@property
def record_id(self) -> str
    # Format: "{recordset_id}-{profile_id}"
    # Example: "abc-123-def-456-p1"
```

#### Relationships

- **Belongs to**: RecordSet
- **Belongs to**: RecordProfile

#### Constraints

- Unique together: (`recordset`, `profile`)
- Index on: `nonce`
- Index on: `record_id`

#### Usage

```python
# Create rendered record
record = Record.objects.create(
    recordset=recordset,
    profile=profile,
    published=True,
    listed=True,
    meeting_id=recordset.meeting_id,
    nonce=recordset.nonce,
    tenant_slug=recordset.tenant_slug
)

# Generate download URL
url = f"/b3lb/r/{record.nonce}"
```

---

### RecordProfile Model

**Purpose**: Video rendering configuration

**Location**: `rest/models/record.py`

#### Fields

| Field | Type | Description | Default |
|-------|------|-------------|---------|
| `id` | AutoField | Primary key | Auto |
| `name` | CharField(200) | Profile name | Required |
| `width` | IntegerField | Video width (px) | 1920 |
| `height` | IntegerField | Video height (px) | 1080 |
| `webcam_width` | IntegerField | Webcam width (px) | 320 |
| `webcam_height` | IntegerField | Webcam height (px) | 180 |
| `webcam_stretch` | BooleanField | Stretch webcam | False |
| `webcam_crop` | BooleanField | Crop webcam | False |
| `format` | CharField(10) | Video format | MP4 |
| `annotate` | BooleanField | Include annotations | True |
| `backdrop` | BooleanField | Add backdrop | True |

#### Format Choices

- `MP4`: H.264 MP4 video
- `WEBM`: VP9 WebM video

#### Usage

```python
# HD profile
hd_profile = RecordProfile.objects.create(
    name="HD 1080p",
    width=1920,
    height=1080,
    webcam_width=320,
    webcam_height=180,
    format='MP4',
    annotate=True
)

# SD profile
sd_profile = RecordProfile.objects.create(
    name="SD 480p",
    width=854,
    height=480,
    webcam_width=160,
    webcam_height=90,
    format='MP4'
)
```

---

## Metrics & Statistics Models

### Metric Model

**Purpose**: Prometheus-style metrics per tenant/node

**Location**: `rest/models/metric.py`

#### Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | AutoField | Primary key |
| `tenant` | ForeignKey(Tenant) | Parent tenant (optional) |
| `node` | ForeignKey(Node) | Parent node (optional) |
| `time` | DateTimeField | Metric timestamp |
| `attendees` | IntegerField | Gauge: Current attendees |
| `meetings` | IntegerField | Gauge: Current meetings |
| `listeners` | IntegerField | Gauge: Listeners |
| `videos` | IntegerField | Gauge: Video participants |
| `voices` | IntegerField | Gauge: Voice participants |
| `attendees_joined_sum` | IntegerField | Counter: Total joined |
| `meetings_created_sum` | IntegerField | Counter: Total created |
| `meetings_duration_sum` | IntegerField | Counter: Duration (seconds) |
| `attendee_limit_hits` | IntegerField | Counter: Limit hits |
| `meeting_limit_hits` | IntegerField | Counter: Limit hits |

#### Constraints

- Index on: `tenant`
- Index on: `node`
- Index on: `time`

#### Usage

```python
# Record tenant metrics
Metric.objects.create(
    tenant=tenant,
    time=timezone.now(),
    attendees=250,
    meetings=25,
    attendees_joined_sum=1500,
    meetings_created_sum=100
)

# Record node metrics
Metric.objects.create(
    node=node,
    time=timezone.now(),
    attendees=50,
    meetings=5,
    listeners=30,
    videos=15,
    voices=40
)
```

---

### Stats Model

**Purpose**: Aggregated statistics per tenant

**Location**: `rest/models/metric.py`

#### Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | AutoField | Primary key |
| `tenant` | ForeignKey(Tenant) | Parent tenant |
| `time` | DateTimeField | Stats timestamp |
| `attendees` | IntegerField | Current attendees |
| `meetings` | IntegerField | Current meetings |
| `listeners` | IntegerField | Current listeners |
| `videos` | IntegerField | Current videos |
| `voices` | IntegerField | Current voices |

#### Relationships

- **Belongs to**: Tenant

#### Usage

```python
# Update tenant stats
Stats.objects.update_or_create(
    tenant=tenant,
    defaults={
        'time': timezone.now(),
        'attendees': total_attendees,
        'meetings': total_meetings,
        'listeners': total_listeners,
        'videos': total_videos,
        'voices': total_voices
    }
)

# Retrieve stats
stats = Stats.objects.get(tenant=tenant)
```

---

### SecretMetricsList Model

**Purpose**: Cached Prometheus metrics text per secret

**Location**: `rest/models/metric.py`

#### Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | AutoField | Primary key |
| `secret` | ForeignKey(Secret) | Parent secret (unique) |
| `metrics_text` | TextField | Prometheus format text |

#### Constraints

- Unique: `secret`

#### Usage

```python
# Cache metrics
SecretMetricsList.objects.update_or_create(
    secret=secret,
    defaults={'metrics_text': prometheus_text}
)

# Serve metrics
cached = SecretMetricsList.objects.get(secret=secret)
return HttpResponse(cached.metrics_text, content_type='text/plain')
```

---

## Database Indexes

### Critical Indexes

**Meeting Lookups**:
```sql
CREATE INDEX idx_meeting_id ON rest_meeting(meeting_id);
CREATE INDEX idx_meeting_node ON rest_meeting(node_id);
CREATE INDEX idx_meeting_nonce ON rest_meeting(nonce);
```

**Node Selection**:
```sql
CREATE INDEX idx_node_errors ON rest_node(has_errors);
CREATE INDEX idx_node_maintenance ON rest_node(maintenance);
CREATE INDEX idx_node_slug ON rest_node(slug);
```

**Recording Queries**:
```sql
CREATE INDEX idx_record_nonce ON rest_record(nonce);
CREATE INDEX idx_record_id ON rest_record(record_id);
CREATE INDEX idx_recordset_nonce ON rest_recordset(nonce);
CREATE INDEX idx_recordset_tenant ON rest_recordset(tenant_slug);
```

**Metrics Queries**:
```sql
CREATE INDEX idx_metric_tenant ON rest_metric(tenant_id);
CREATE INDEX idx_metric_node ON rest_metric(node_id);
CREATE INDEX idx_metric_time ON rest_metric(time);
```

---

## Common Queries

### Find Available Nodes for Tenant

```python
tenant = Tenant.objects.select_related('clustergroup').get(slug='ACME')
nodes = tenant.clustergroup.all_nodes()
available_nodes = [n for n in nodes if n.load >= 0]
selected_node = min(available_nodes, key=lambda n: n.load)
```

### Get Tenant's Active Meetings

```python
meetings = Meeting.objects.filter(
    secret__tenant=tenant
).select_related('node', 'secret')
```

### Get Recordings for Tenant

```python
records = Record.objects.filter(
    tenant_slug=tenant.slug,
    published=True,
    listed=True
).select_related('recordset', 'profile')
```

### Calculate Tenant Metrics

```python
meetings = Meeting.objects.filter(secret__tenant=tenant)
total_attendees = sum(m.attendees for m in meetings)
total_meetings = meetings.count()
total_videos = sum(m.videos for m in meetings)
```

---

## Database Maintenance

### Cleanup Tasks

**Old Metrics** (retention: 30 days):
```python
cutoff = timezone.now() - timedelta(days=30)
Metric.objects.filter(time__lt=cutoff).delete()
```

**Ended Meetings**:
```python
# Meetings not in any node's meeting list
stale_meetings = Meeting.objects.exclude(
    meeting_id__in=active_meeting_ids
)
stale_meetings.delete()
```

**Old Recordings** (based on hold_time):
```python
cutoff = timezone.now() - timedelta(days=hold_time)
old_recordsets = RecordSet.objects.filter(
    end_time__lt=cutoff,
    status='RENDERED'
)
for rs in old_recordsets:
    rs.status = 'DELETING'
    rs.save()
    # Delete files and records
```

### Backup Recommendations

**Critical Data**:
- Clusters, Nodes (configuration)
- Tenants, Secrets (multi-tenant setup)
- Assets, Parameters (customization)

**Transient Data**:
- Meetings (can be rebuilt from polling)
- Cached meeting lists (rebuilt every 60s)
- Metrics (retention-based)

**Important Data**:
- RecordSets, Records (recording metadata)
- Stats (historical statistics)

### Performance Tuning

**Connection Pooling**:
```python
DATABASES = {
    'default': {
        'CONN_MAX_AGE': 600,  # 10 minutes
    }
}
```

**ORM Caching**:
```python
CACHEOPS = {
    'rest.tenant': {'ops': 'all', 'timeout': 3600},
    'rest.secret': {'ops': 'all', 'timeout': 3600},
    'rest.node': {'ops': 'all', 'timeout': 60},
    'rest.cluster': {'ops': 'all', 'timeout': 3600},
}
```

**Query Optimization**:
- Use `select_related()` for foreign keys
- Use `prefetch_related()` for reverse foreign keys
- Add indexes for frequent filters
- Use `only()` to limit field retrieval

---

## Next Steps

- [API Endpoints](./03-api-endpoints.md): How these models are accessed via API
- [Configuration](./04-configuration.md): Database connection setup
- [Operations](./08-operations.md): Database maintenance procedures
