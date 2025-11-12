# B3LB API Endpoints

## Overview

B3LB implements the complete BigBlueButton API with load balancing, plus additional endpoints for monitoring, statistics, and recording management. All endpoints support both wildcard DNS and path-based routing.

## URL Routing Patterns

### Wildcard DNS (Recommended)

```
https://{tenant}.{base_domain}/bigbluebutton/api/{endpoint}
https://{tenant}-{sub_id}.{base_domain}/bigbluebutton/api/{endpoint}
```

Example:
```
https://acme.bbb.example.com/bigbluebutton/api/create
https://acme-5.bbb.example.com/bigbluebutton/api/join
```

### Path-Based Routing

```
https://{base_domain}/b3lb/t/{tenant}/bbb/api/{endpoint}
https://{base_domain}/b3lb/t/{tenant}-{sub_id}/bbb/api/{endpoint}
```

Example:
```
https://bbb.example.com/b3lb/t/acme/bbb/api/create
https://bbb.example.com/b3lb/t/acme-5/bbb/api/join
```

## Authentication

All BBB API endpoints require checksum validation following the BigBlueButton specification:

```
checksum = SHA256(call_name + query_string + secret)
```

Example:
```python
import hashlib

def generate_checksum(call_name, params, secret):
    query_string = urllib.parse.urlencode(sorted(params.items()))
    data = call_name + query_string + secret
    return hashlib.sha256(data.encode()).hexdigest()

# Usage
params = {'meetingID': 'test-123', 'name': 'Meeting'}
checksum = generate_checksum('create', params, tenant_secret)
url = f"https://acme.bbb.example.com/bigbluebutton/api/create?{query_string}&checksum={checksum}"
```

---

## BigBlueButton API Endpoints

B3LB implements all standard BBB API endpoints with load balancing intelligence.

### create

**Purpose**: Create a new meeting with intelligent node selection

**Method**: GET or POST

**URL**: `/bigbluebutton/api/create`

**Parameters**:

| Parameter | Required | Description |
|-----------|----------|-------------|
| `meetingID` | Yes | Unique meeting identifier |
| `name` | Yes | Meeting name/title |
| `attendeePW` | No | Attendee password |
| `moderatorPW` | No | Moderator password |
| `welcome` | No | Welcome message |
| `dialNumber` | No | Dial-in number |
| `voiceBridge` | No | Voice conference number |
| `maxParticipants` | No | Maximum participants |
| `logoutURL` | No | Logout redirect URL |
| `record` | No | Enable recording (true/false) |
| `duration` | No | Meeting duration (minutes) |
| `meta_*` | No | Custom metadata parameters |
| `checksum` | Yes | Request checksum |

**B3LB Behavior**:

1. **Tenant Resolution**: Extract tenant from domain/path
2. **Checksum Validation**: Validate against tenant secret
3. **Limit Check**: Verify tenant meeting limit not exceeded
4. **Node Selection**: Choose node with lowest load score
5. **Meeting Creation**: Create Meeting record in database
6. **Proxy Request**: Forward request to selected BBB node
7. **Response**: Return BBB node's XML response

**Load Balancing Logic**:
```python
# Get eligible nodes
eligible_nodes = [n for n in tenant.clustergroup.all_nodes() if n.load >= 0]

# Select node with minimum load
selected_node = min(eligible_nodes, key=lambda n: n.load)

# Create meeting record
meeting = Meeting.objects.create(
    secret=secret,
    meeting_id=params['meetingID'],
    meeting_name=params['name'],
    node=selected_node,
    nonce=uuid.uuid4()
)
```

**Response**: Standard BBB XML response from selected node

**Example**:
```bash
curl "https://acme.bbb.example.com/bigbluebutton/api/create?\
meetingID=test-123&\
name=Test+Meeting&\
attendeePW=ap&\
moderatorPW=mp&\
record=true&\
checksum=abc123..."
```

---

### join

**Purpose**: Join an existing meeting with node resolution

**Method**: GET

**URL**: `/bigbluebutton/api/join`

**Parameters**:

| Parameter | Required | Description |
|-----------|----------|-------------|
| `fullName` | Yes | Participant display name |
| `meetingID` | Yes | Meeting identifier |
| `password` | Yes | Attendee or moderator password |
| `createTime` | No | Meeting creation timestamp |
| `userID` | No | User identifier |
| `webVoiceConf` | No | Web voice conference |
| `configToken` | No | Configuration token |
| `avatarURL` | No | User avatar URL |
| `redirect` | No | Enable redirect (default: true) |
| `clientURL` | No | Custom client URL |
| `checksum` | Yes | Request checksum |

**B3LB Behavior**:

1. **Tenant Resolution**: Extract tenant from domain/path
2. **Checksum Validation**: Validate against tenant secret
3. **Meeting Lookup**: Query Meeting record from database
4. **Node Resolution**: Get assigned node for meeting
5. **Limit Check**: Verify tenant attendee limit not exceeded
6. **Redirect**: Build redirect URL to BBB node
7. **Response**: Return redirect to client

**Node Resolution Logic**:
```python
try:
    meeting = Meeting.objects.get(
        secret=secret,
        meeting_id=params['meetingID']
    )
    node = meeting.node
except Meeting.DoesNotExist:
    return error_response("Meeting not found")
```

**Response**: HTTP redirect (302) to BBB node join URL or XML error

**Example**:
```bash
curl "https://acme.bbb.example.com/bigbluebutton/api/join?\
fullName=John+Doe&\
meetingID=test-123&\
password=ap&\
checksum=abc123..."
```

---

### isMeetingRunning

**Purpose**: Check if a meeting is currently active

**Method**: GET

**URL**: `/bigbluebutton/api/isMeetingRunning`

**Parameters**:

| Parameter | Required | Description |
|-----------|----------|-------------|
| `meetingID` | Yes | Meeting identifier |
| `checksum` | Yes | Request checksum |

**B3LB Behavior**:

1. Query Meeting record from database
2. If exists, proxy request to assigned node
3. If not exists, return `running=false`

**Response**: BBB XML response

```xml
<response>
  <returncode>SUCCESS</returncode>
  <running>true</running>
</response>
```

---

### getMeetings

**Purpose**: List all meetings for tenant (cached)

**Method**: GET

**URL**: `/bigbluebutton/api/getMeetings`

**Parameters**:

| Parameter | Required | Description |
|-----------|----------|-------------|
| `checksum` | Yes | Request checksum |

**B3LB Behavior**:

1. **Cache Lookup**: Check Redis/DB for SecretMeetingList
2. **Cache Hit**: Return cached XML (updated every 30-60s)
3. **Cache Miss**: Return empty meeting list

**Caching Strategy**:
- Celery task updates meeting lists every 30-60 seconds
- Polls all BBB nodes in tenant's cluster group
- Aggregates results into single XML response
- Stores in SecretMeetingList model

**Response**: BBB XML with meeting list

```xml
<response>
  <returncode>SUCCESS</returncode>
  <meetings>
    <meeting>
      <meetingID>test-123</meetingID>
      <meetingName>Test Meeting</meetingName>
      <participantCount>5</participantCount>
      <listenerCount>3</listenerCount>
      <voiceParticipantCount>4</voiceParticipantCount>
      <videoCount>2</videoCount>
      <moderatorCount>1</moderatorCount>
      <running>true</running>
      <hasBeenForciblyEnded>false</hasBeenForciblyEnded>
    </meeting>
  </meetings>
</response>
```

---

### end

**Purpose**: End an active meeting

**Method**: GET

**URL**: `/bigbluebutton/api/end`

**Parameters**:

| Parameter | Required | Description |
|-----------|----------|-------------|
| `meetingID` | Yes | Meeting identifier |
| `password` | Yes | Moderator password |
| `checksum` | Yes | Request checksum |

**B3LB Behavior**:

1. Query Meeting record
2. Proxy request to assigned BBB node
3. Delete Meeting record on success

**Response**: BBB XML response

---

### getRecordings

**Purpose**: List recordings for tenant

**Method**: GET

**URL**: `/bigbluebutton/api/getRecordings`

**Parameters**:

| Parameter | Required | Description |
|-----------|----------|-------------|
| `meetingID` | No | Filter by meeting ID (comma-separated) |
| `recordID` | No | Filter by record ID (comma-separated) |
| `state` | No | Filter by state (published/unpublished/any) |
| `checksum` | Yes | Request checksum |

**B3LB Behavior**:

1. Query Record model filtered by tenant
2. Apply meeting ID filter if provided
3. Apply record ID filter if provided
4. Apply state filter (published/unpublished)
5. Build BBB-compatible XML response

**Query Logic**:
```python
records = Record.objects.filter(
    tenant_slug=tenant.slug
)

if meeting_ids:
    records = records.filter(meeting_id__in=meeting_ids)

if record_ids:
    records = records.filter(record_id__in=record_ids)

if state == 'published':
    records = records.filter(published=True)
elif state == 'unpublished':
    records = records.filter(published=False)
```

**Response**: BBB XML with recording list

```xml
<response>
  <returncode>SUCCESS</returncode>
  <recordings>
    <recording>
      <recordID>abc-123-p1</recordID>
      <meetingID>test-123</meetingID>
      <name>Test Meeting</name>
      <published>true</published>
      <state>published</state>
      <startTime>1642598400000</startTime>
      <endTime>1642602000000</endTime>
      <participants>5</participants>
      <playback>
        <format>
          <type>presentation</type>
          <url>https://bbb.example.com/b3lb/r/{nonce}</url>
          <length>60</length>
        </format>
      </playback>
    </recording>
  </recordings>
</response>
```

---

### publishRecordings

**Purpose**: Publish or unpublish recordings

**Method**: GET

**URL**: `/bigbluebutton/api/publishRecordings`

**Parameters**:

| Parameter | Required | Description |
|-----------|----------|-------------|
| `recordID` | Yes | Record ID (comma-separated) |
| `publish` | Yes | Publish flag (true/false) |
| `checksum` | Yes | Request checksum |

**B3LB Behavior**:

1. Parse comma-separated record IDs
2. Update Record.published field for each
3. Return success response

**Update Logic**:
```python
record_ids = params['recordID'].split(',')
publish = params['publish'].lower() == 'true'

Record.objects.filter(
    record_id__in=record_ids,
    tenant_slug=tenant.slug
).update(published=publish)
```

**Response**: BBB XML response

```xml
<response>
  <returncode>SUCCESS</returncode>
  <published>true</published>
</response>
```

---

### deleteRecordings

**Purpose**: Delete recordings

**Method**: GET

**URL**: `/bigbluebutton/api/deleteRecordings`

**Parameters**:

| Parameter | Required | Description |
|-----------|----------|-------------|
| `recordID` | Yes | Record ID (comma-separated) |
| `checksum` | Yes | Request checksum |

**B3LB Behavior**:

1. Parse comma-separated record IDs
2. Update RecordSet.status to 'DELETING'
3. Queue deletion task via Celery
4. Return success response

**Deletion Process**:
```python
record_ids = params['recordID'].split(',')

recordsets = RecordSet.objects.filter(
    records__record_id__in=record_ids,
    tenant_slug=tenant.slug
).distinct()

for recordset in recordsets:
    recordset.status = 'DELETING'
    recordset.save()
    # Queue Celery task to delete files
    delete_recording_files.delay(recordset.id)
```

**Response**: BBB XML response

---

### updateRecordings

**Purpose**: Update recording metadata

**Method**: GET

**URL**: `/bigbluebutton/api/updateRecordings`

**Parameters**:

| Parameter | Required | Description |
|-----------|----------|-------------|
| `recordID` | Yes | Record ID (comma-separated) |
| `meta_*` | No | Metadata parameters to update |
| `checksum` | Yes | Request checksum |

**B3LB Behavior**:

1. Parse record IDs and metadata parameters
2. Update RecordSet metadata fields
3. Return success response

**Note**: Metadata updates stored in RecordSet model

**Response**: BBB XML response

---

## B3LB-Specific Endpoints

### stats

**Purpose**: Get real-time statistics for tenant

**Method**: GET

**URL Patterns**:
- Global: `/b3lb/stats`
- Tenant: `/b3lb/t/{tenant}/stats`
- Secret: `/b3lb/t/{tenant}-{sub_id}/stats`

**Parameters**:

| Parameter | Required | Description |
|-----------|----------|-------------|
| `token` | No | Stats token (for tenant-specific) |

**Response Format**: JSON

```json
{
  "meetings": 25,
  "attendees": 250,
  "listeners": 180,
  "videos": 120,
  "voices": 200,
  "nodes": [
    {
      "slug": "bbb01",
      "meetings": 10,
      "attendees": 100,
      "load": 145.3
    }
  ]
}
```

**Authorization**:
- Global stats: Admin only (via Traefik ACL)
- Tenant stats: Requires valid token parameter

**Data Source**: Stats model (updated every 5 minutes via Celery)

**Example**:
```bash
curl "https://acme.bbb.example.com/b3lb/t/acme/stats?token=abc123..."
```

---

### metrics

**Purpose**: Prometheus metrics export

**Method**: GET

**URL Patterns**:
- Global: `/b3lb/metrics`
- Tenant: `/b3lb/t/{tenant}/metrics`
- Secret: `/b3lb/t/{tenant}-{sub_id}/metrics`

**Parameters**:

| Parameter | Required | Description |
|-----------|----------|-------------|
| `token` | No | Stats token (for tenant-specific) |

**Response Format**: Prometheus text format

```
# HELP b3lb_attendees Current number of attendees
# TYPE b3lb_attendees gauge
b3lb_attendees{tenant="ACME"} 250

# HELP b3lb_meetings Current number of meetings
# TYPE b3lb_meetings gauge
b3lb_meetings{tenant="ACME"} 25

# HELP b3lb_attendees_joined_total Total attendees joined
# TYPE b3lb_attendees_joined_total counter
b3lb_attendees_joined_total{tenant="ACME"} 15000

# HELP b3lb_meetings_created_total Total meetings created
# TYPE b3lb_meetings_created_total counter
b3lb_meetings_created_total{tenant="ACME"} 1000

# HELP b3lb_meetings_duration_seconds_total Total meeting duration
# TYPE b3lb_meetings_duration_seconds_total counter
b3lb_meetings_duration_seconds_total{tenant="ACME"} 360000

# HELP b3lb_attendee_limit_hits_total Attendee limit hits
# TYPE b3lb_attendee_limit_hits_total counter
b3lb_attendee_limit_hits_total{tenant="ACME"} 5

# HELP b3lb_meeting_limit_hits_total Meeting limit hits
# TYPE b3lb_meeting_limit_hits_total counter
b3lb_meeting_limit_hits_total{tenant="ACME"} 2
```

**Authorization**: Same as stats endpoint

**Data Source**: Metric model (cached in SecretMetricsList)

**Prometheus Scrape Config**:
```yaml
scrape_configs:
  - job_name: 'b3lb'
    static_configs:
      - targets: ['bbb.example.com']
    metrics_path: '/b3lb/metrics'
    scheme: https
    basic_auth:
      username: prometheus
      password: secret
```

---

### ping

**Purpose**: Health check endpoint

**Method**: GET

**URL**: `/b3lb/ping`

**Parameters**: None

**Response Format**: JSON

```json
{
  "status": "ok",
  "version": "3.3.2",
  "timestamp": "2025-01-15T10:30:00Z"
}
```

**Use Cases**:
- Load balancer health checks
- Uptime monitoring
- Service availability verification

**Example**:
```bash
curl "https://bbb.example.com/b3lb/ping"
```

---

### logo

**Purpose**: Serve tenant-specific logo

**Method**: GET

**URL**: `/b3lb/t/{tenant}/logo`

**Parameters**: None

**Response**: Image file (PNG, JPG, etc.)

**Usage in BBB**:
```
logo=https://acme.bbb.example.com/b3lb/t/acme/logo
```

**Storage**: Database via django-db-file-storage (AssetLogo)

---

### slide

**Purpose**: Serve tenant-specific default slide

**Method**: GET

**URL**: `/b3lb/t/{tenant}/slide`

**Parameters**: None

**Response**: Image file (PNG, JPG, PDF, etc.)

**Usage in BBB**:
```
defaultPresentationURL=https://acme.bbb.example.com/b3lb/t/acme/slide
```

**Storage**: Database via django-db-file-storage (AssetSlide)

---

### custom_css

**Purpose**: Serve tenant-specific custom CSS

**Method**: GET

**URL**: `/b3lb/t/{tenant}/css`

**Parameters**: None

**Response**: CSS file (text/css)

**Usage in BBB**:
```
customStyleUrl=https://acme.bbb.example.com/b3lb/t/acme/css
```

**Storage**: Database via django-db-file-storage (AssetCustomCSS)

---

### recording (Download)

**Purpose**: Download recording file

**Method**: GET

**URL**: `/b3lb/r/{nonce}`

**Parameters**: None

**Authentication**: None (nonce acts as unguessable token)

**B3LB Behavior**:

1. Query Record by nonce
2. Check published and listed flags
3. Stream file from S3 or local storage
4. Return video file

**Response**: Video file (MP4, WebM, etc.)

**Example**:
```bash
curl "https://bbb.example.com/b3lb/r/550e8400-e29b-41d4-a716-446655440000" -o recording.mp4
```

**Security**: Nonce is UUID4 (unguessable), provides access control

---

### backend_endpoint

**Purpose**: Internal backend API operations

**Method**: GET or POST

**URL**: `/b3lb/b/{backend}/{endpoint}`

**Parameters**: Varies by endpoint

**Authentication**: Restricted access (IP whitelist recommended)

**Use Cases**:
- BBB node callbacks
- Internal service communication
- Administrative operations

**Example Endpoints**:
- `/b3lb/b/recording/upload`: Upload recording archive
- `/b3lb/b/callback/end`: Meeting end callback

---

## Error Responses

### Standard BBB Error Format

```xml
<response>
  <returncode>FAILED</returncode>
  <messageKey>error_key</messageKey>
  <message>Error description</message>
</response>
```

### Common Error Codes

| Error | Message | Cause |
|-------|---------|-------|
| `checksumError` | Checksum validation failed | Invalid checksum or secret |
| `notFound` | Meeting not found | Meeting doesn't exist |
| `maxParticipantsReached` | Maximum participants reached | Attendee limit exceeded |
| `maxMeetingsReached` | Maximum meetings reached | Meeting limit exceeded |
| `noNodesAvailable` | No nodes available | All nodes in maintenance/error |
| `invalidParameters` | Invalid parameters | Missing or invalid parameters |

### HTTP Status Codes

| Status | Meaning | Use Case |
|--------|---------|----------|
| `200 OK` | Success | Normal API response |
| `302 Found` | Redirect | Join meeting redirect |
| `400 Bad Request` | Invalid request | Malformed parameters |
| `401 Unauthorized` | Authentication failed | Invalid checksum |
| `403 Forbidden` | Access denied | Limit exceeded |
| `404 Not Found` | Resource not found | Invalid endpoint or resource |
| `500 Internal Server Error` | Server error | Unexpected error |
| `503 Service Unavailable` | Service down | No nodes available |

---

## Rate Limiting

B3LB does not implement built-in rate limiting. Consider implementing at reverse proxy level:

**Traefik Rate Limiting**:
```yaml
http:
  middlewares:
    ratelimit:
      rateLimit:
        average: 100
        burst: 50
        period: 1s
```

**Recommended Limits**:
- Create: 10 requests/minute per tenant
- Join: 100 requests/minute per tenant
- getMeetings: 30 requests/minute per tenant
- Other: 50 requests/minute per tenant

---

## API Client Examples

### Python Client

```python
import hashlib
import urllib.parse
import requests

class B3LBClient:
    def __init__(self, base_url, secret):
        self.base_url = base_url
        self.secret = secret

    def _checksum(self, call_name, params):
        query = urllib.parse.urlencode(sorted(params.items()))
        data = call_name + query + self.secret
        return hashlib.sha256(data.encode()).hexdigest()

    def create(self, meeting_id, name, **kwargs):
        params = {'meetingID': meeting_id, 'name': name, **kwargs}
        params['checksum'] = self._checksum('create', params)
        url = f"{self.base_url}/bigbluebutton/api/create"
        response = requests.get(url, params=params)
        return response.text

    def join(self, full_name, meeting_id, password):
        params = {
            'fullName': full_name,
            'meetingID': meeting_id,
            'password': password
        }
        params['checksum'] = self._checksum('join', params)
        url = f"{self.base_url}/bigbluebutton/api/join"
        return f"{url}?{urllib.parse.urlencode(params)}"

# Usage
client = B3LBClient(
    "https://acme.bbb.example.com",
    "your-tenant-secret"
)

# Create meeting
xml = client.create("test-123", "Test Meeting", record="true")

# Get join URL
join_url = client.join("John Doe", "test-123", "attendee-password")
```

### JavaScript Client

```javascript
const crypto = require('crypto');
const axios = require('axios');

class B3LBClient {
    constructor(baseUrl, secret) {
        this.baseUrl = baseUrl;
        this.secret = secret;
    }

    checksum(callName, params) {
        const sortedParams = Object.keys(params)
            .sort()
            .map(key => `${key}=${encodeURIComponent(params[key])}`)
            .join('&');
        const data = callName + sortedParams + this.secret;
        return crypto.createHash('sha256').update(data).digest('hex');
    }

    async create(meetingID, name, options = {}) {
        const params = { meetingID, name, ...options };
        params.checksum = this.checksum('create', params);

        const response = await axios.get(
            `${this.baseUrl}/bigbluebutton/api/create`,
            { params }
        );
        return response.data;
    }

    join(fullName, meetingID, password) {
        const params = { fullName, meetingID, password };
        params.checksum = this.checksum('join', params);

        const queryString = new URLSearchParams(params).toString();
        return `${this.baseUrl}/bigbluebutton/api/join?${queryString}`;
    }
}

// Usage
const client = new B3LBClient(
    'https://acme.bbb.example.com',
    'your-tenant-secret'
);

// Create meeting
const xml = await client.create('test-123', 'Test Meeting', {
    record: 'true'
});

// Get join URL
const joinUrl = client.join('John Doe', 'test-123', 'attendee-password');
```

---

## Testing with API Mate

**API Mate**: Interactive BBB API testing tool

**URL**: https://mconf.github.io/api-mate/

**Configuration**:
1. Enter B3LB endpoint URL
2. Enter tenant secret
3. Select API call
4. Fill parameters
5. Execute and view response

**Admin Integration**: B3LB admin interface provides direct API Mate links for tenants and secrets

---

## Next Steps

- [Configuration](./04-configuration.md): Environment setup for API endpoints
- [Operations](./08-operations.md): Monitoring and troubleshooting API issues
- [Development Guide](./07-development-guide.md): Extending API functionality
