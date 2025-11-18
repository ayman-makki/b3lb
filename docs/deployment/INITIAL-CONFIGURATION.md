# B3LB Initial Configuration Guide

**Step-by-step guide for configuring B3LB after deployment**

---

## Table of Contents

1. [Access Django Admin](#access-django-admin)
2. [Create Cluster Group](#create-cluster-group)
3. [Create Cluster](#create-cluster)
4. [Add BigBlueButton Nodes](#add-bigbluebutton-nodes)
5. [Create Tenant](#create-tenant)
6. [Generate API Secrets](#generate-api-secrets)
7. [Test API](#test-api)
8. [Configure Recording Settings](#configure-recording-settings)
9. [Multi-Tenant Setup](#multi-tenant-setup)

---

## Access Django Admin

### 1. Open Django Admin Interface

Navigate to: https://b3lb.example.com/admin/

### 2. Login with Superuser Credentials

- **Username**: `admin`
- **Password**: The password you set during deployment

If you forgot the password, reset it:

```bash
docker-compose -f docker-compose.hetzner-production.yml exec frontend \
    python manage.py changepassword admin
```

---

## Create Cluster Group

Cluster Groups organize your BBB nodes into logical groups (e.g., by region, performance tier, or purpose).

### Steps:

1. In Django Admin, click **Cluster Groups** → **Add Cluster Group**

2. Fill in the details:
   - **Name**: `Primary Cluster Group`
   - **Active**: ✓ (checked)

3. Click **Save**

### Example Configuration:

```yaml
Name: Primary Cluster Group
Active: Yes
Description: Main cluster group for production nodes
```

---

## Create Cluster

Clusters are collections of BBB nodes that work together under a Cluster Group.

### Steps:

1. Click **Clusters** → **Add Cluster**

2. Fill in the details:
   - **Name**: `Production Cluster`
   - **Cluster Group**: Select "Primary Cluster Group"
   - **Active**: ✓ (checked)
   - **Attendee Factor**: `1.0` (default)
   - **Meeting Factor**: `1.0` (default)

3. Click **Save**

### Load Balancing Factors:

The load balancing algorithm uses this formula:

```
Load = (Attendees × Attendee Factor) + (Meetings × Meeting Factor) + CPU Load
```

- **Attendee Factor**: Weight given to number of attendees (default: 1.0)
- **Meeting Factor**: Weight given to number of meetings (default: 1.0)

**Tip**: Increase Meeting Factor if you have many small meetings. Increase Attendee Factor for large meetings.

---

## Add BigBlueButton Nodes

Now add your actual BBB servers to the cluster.

### Prerequisites:

Before adding nodes, ensure each BBB server has:
1. ✅ B3LB load monitoring installed (see [BBB-NODE-SETUP.md](./BBB-NODE-SETUP.md))
2. ✅ HTTPS with valid SSL certificate
3. ✅ Accessible from B3LB server

### Steps:

1. Click **Nodes** → **Add Node**

2. Fill in the details:
   - **Domain**: `bbb1.example.com` (your BBB server domain)
   - **Secret**: (BBB server shared secret)
   - **Cluster**: Select "Production Cluster"
   - **Active**: ✓ (checked)
   - **Load Factor**: `1.0` (adjust based on server capacity)
   - **State**: Select "ENABLED"

3. Click **Save**

### How to Get BBB Server Secret:

On your BBB server, run:

```bash
bbb-conf --secret
```

Output will show:
```
URL: https://bbb1.example.com/bigbluebutton/
Secret: 1234567890abcdef...
```

### Load Factor Examples:

| Server Specs | Load Factor | Capacity |
|--------------|-------------|----------|
| 4 vCPU, 8GB RAM | 0.5 | ~50 attendees |
| 8 vCPU, 16GB RAM | 1.0 | ~100 attendees |
| 16 vCPU, 32GB RAM | 2.0 | ~200 attendees |

**Tip**: Higher Load Factor = More capacity = Higher priority for new meetings.

### Repeat for All Nodes:

Add all your BBB servers (e.g., bbb1, bbb2, bbb3, etc.)

---

## Create Tenant

Tenants are organizations or departments using your B3LB service. Each tenant gets their own subdomain and API endpoint.

### Steps:

1. Click **Tenants** → **Add Tenant**

2. Fill in the details:
   - **Slug**: `my-organization` (alphanumeric, lowercase, hyphens)
   - **Name**: `My Organization`
   - **Cluster Group**: Select "Primary Cluster Group"
   - **Active**: ✓ (checked)
   - **Attendee Limit**: `1000` (max concurrent attendees)
   - **Meeting Limit**: `100` (max concurrent meetings)
   - **Slide URL**: (optional, custom default presentation)
   - **Logo URL**: (optional, custom logo)

3. Click **Save**

### Tenant Endpoint:

Based on slug `my-organization`, the tenant's API endpoint will be:
```
https://my-organization.b3lb.example.com/bigbluebutton/api
```

### Multiple Tenant Example:

| Organization | Slug | Endpoint |
|--------------|------|----------|
| Engineering Team | `engineering` | `https://engineering.b3lb.example.com/bigbluebutton/api` |
| Sales Team | `sales` | `https://sales.b3lb.example.com/bigbluebutton/api` |
| Customer A | `customer-a` | `https://customer-a.b3lb.example.com/bigbluebutton/api` |

---

## Generate API Secrets

Each tenant needs at least one API secret for authentication.

### Steps:

1. Click **Secrets** → **Add Secret**

2. Fill in the details:
   - **Tenant**: Select "My Organization"
   - **Sub-ID**: `0` (start with 0, increment for rollover)
   - **Secret**: (leave blank to auto-generate)
   - **Active**: ✓ (checked)

3. Click **Save**

### Auto-Generated Secret:

B3LB will generate a secure random secret like:
```
a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6
```

**Save this secret!** You'll need it to configure your BigBlueButton frontend (Greenlight, Moodle, etc.).

### Secret Rollover:

For zero-downtime secret rotation:

1. Add new secret with Sub-ID `1` (keep old secret active)
2. Update clients to use new secret
3. After all clients updated, deactivate old secret (Sub-ID `0`)
4. Delete old secret after grace period

---

## Test API

### 1. Test getMeetings Endpoint

```bash
curl "https://my-organization.b3lb.example.com/bigbluebutton/api/getMeetings?checksum=..."
```

For easier testing, use B3LB's built-in test page:

```bash
# Get checksum helper
curl "https://my-organization.b3lb.example.com/bigbluebutton/api"
```

### 2. Test with bbb-conf --check

On your frontend server (Greenlight, Moodle, etc.), configure:

```
BBB_SERVER_URL=https://my-organization.b3lb.example.com/bigbluebutton/
BBB_SECRET=a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6
```

Then test:

```bash
bbb-conf --secret
bbb-conf --check
```

### 3. Create Test Meeting

Use the official BBB API MATE tool:
https://mconf.github.io/api-mate/

Enter:
- **Server URL**: `https://my-organization.b3lb.example.com/bigbluebutton/api`
- **Secret**: Your generated secret

Click "create" to test meeting creation.

---

## Configure Recording Settings

### Enable Recording Processing

Recordings are already enabled in the docker-compose setup. To configure:

1. Click **Tenants** → Select your tenant

2. Scroll to **Recording Settings**:
   - **Enable Recordings**: ✓
   - **Recording Profiles**: `720p,1080p` (configured in `.env`)
   - **Retention Days**: `90` (auto-delete after 90 days)

3. Click **Save**

### Recording Workflow:

```
BBB Server → Record → Archive → Upload to B3LB → Render Videos → Serve to Users
```

1. **Record**: BBB records meeting
2. **Archive**: BBB post-publish script creates archive
3. **Upload**: b3lb-push uploads to B3LB Storage Box
4. **Render**: Celery workers render multiple quality profiles
5. **Serve**: Users access via getRecordings API

### Storage Location:

All recordings are stored in:
```
/mnt/b3lb-recordings/recordings/
```

(On Hetzner Storage Box: `u123456.your-storagebox.de:/b3lb/recordings/`)

---

## Multi-Tenant Setup

### Example: 3 Tenants with Different Cluster Groups

#### Scenario:
- **Team A**: High-performance nodes
- **Team B**: Standard nodes
- **Team C**: Standard nodes

#### Configuration:

**1. Create Cluster Groups:**

| Name | Purpose |
|------|---------|
| High-Performance | Premium nodes for Team A |
| Standard | Regular nodes for Team B & C |

**2. Create Clusters:**

| Name | Cluster Group | Nodes |
|------|---------------|-------|
| Premium Cluster | High-Performance | bbb1, bbb2 (16 vCPU) |
| Standard Cluster | Standard | bbb3, bbb4, bbb5 (8 vCPU) |

**3. Create Tenants:**

| Tenant | Slug | Cluster Group | Limits |
|--------|------|---------------|--------|
| Team A | `team-a` | High-Performance | 500 attendees |
| Team B | `team-b` | Standard | 300 attendees |
| Team C | `team-c` | Standard | 300 attendees |

**4. Generate Secrets:**

Each tenant gets 1-2 secrets (with Sub-ID 0 and optionally 1 for rollover).

### Result:

- Team A meetings → bbb1 or bbb2 (high-performance nodes)
- Team B meetings → bbb3, bbb4, or bbb5 (standard nodes)
- Team C meetings → bbb3, bbb4, or bbb5 (standard nodes)

### Tenant Isolation:

Each tenant is **fully isolated**:
- ✅ Separate API endpoint
- ✅ Separate secrets
- ✅ Separate recording storage
- ✅ Separate branding (optional)
- ✅ Separate limits

---

## Advanced Configuration

### Custom Branding Per Tenant

1. Upload logo to `/opt/b3lb/media/logos/tenant-a-logo.png`
2. Edit tenant:
   - **Logo URL**: `https://static.b3lb.example.com/logos/tenant-a-logo.png`
3. Upload default slides to `/opt/b3lb/media/slides/tenant-a-default.pdf`
4. Edit tenant:
   - **Slide URL**: `https://static.b3lb.example.com/slides/tenant-a-default.pdf`

### Custom BBB Parameters

1. Click **Parameters** → **Add Parameter**
2. Configure custom BBB create parameters per tenant:
   - **Tenant**: Select tenant
   - **Parameter Name**: e.g., `muteOnStart`
   - **Parameter Value**: `true`
   - **Active**: ✓

### Node Maintenance Mode

To take a node offline for maintenance without deleting it:

1. Click **Nodes** → Select node
2. Change **State** to `DRAINING`
3. Click **Save**

The node will:
- ❌ Stop accepting new meetings
- ✅ Continue serving existing meetings
- ✅ Auto-disable when all meetings end

To re-enable:
1. Change **State** back to `ENABLED`
2. Click **Save**

---

## Verification Checklist

After configuration, verify:

- ✅ All nodes show "healthy" in admin
- ✅ Tenant API endpoint responds
- ✅ Can create test meeting via API MATE
- ✅ Meetings distribute across nodes
- ✅ Recordings upload successfully
- ✅ Grafana shows metrics
- ✅ Prometheus scraping data

---

## Next Steps

1. **Configure BBB Nodes**: See [BBB-NODE-SETUP.md](./BBB-NODE-SETUP.md)
2. **Setup Frontend**: Configure Greenlight, Moodle, or your LMS
3. **Monitor System**: Access Grafana dashboards
4. **Test Failover**: Disable a node, verify redistribution
5. **Setup Backups**: Enable automated backups

---

## Troubleshooting

### Tenant Endpoint Not Accessible

**Problem**: `https://my-tenant.b3lb.example.com` returns 404

**Solutions**:
1. Verify wildcard DNS: `dig +short my-tenant.b3lb.example.com`
2. Check Traefik logs: `docker-compose logs traefik`
3. Verify tenant slug matches subdomain
4. Restart Traefik: `docker-compose restart traefik`

### Nodes Not Accepting Meetings

**Problem**: Meetings not distributed to nodes

**Solutions**:
1. Check node state is "ENABLED"
2. Verify node health endpoint: `curl https://bbb1.example.com/b3lb/load`
3. Check cluster group assignment matches tenant
4. Review logs: `docker-compose logs frontend`

### Recording Upload Failures

**Problem**: Recordings not appearing in B3LB

**Solutions**:
1. Check Storage Box mount: `mountpoint /mnt/b3lb-recordings`
2. Verify b3lb-push installed on BBB nodes
3. Check BBB node can reach B3LB API
4. Review Celery logs: `docker-compose logs celery-record`

---

**Configuration Guide Version**: 1.0
**Last Updated**: 2025-01-15
