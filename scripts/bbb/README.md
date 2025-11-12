# B3LB BBB Node Scripts Installation Guide

This directory contains scripts that must be installed on BigBlueButton (BBB) nodes to integrate with the B3LB load balancer backend.

## Overview

B3LB (BigBlueButton Load Balancer) requires three services to be installed on each BBB node:

| Service | Purpose | Priority |
|---------|---------|----------|
| **b3lb-load** | CPU load monitoring and HTTP endpoint | **Critical** |
| **b3lb-push** | Recording upload to B3LB backend | High |
| **b3lb-cleaner** | Orphaned meeting cleanup | Optional |

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    BigBlueButton Node                        │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌─────────────────┐                                         │
│  │ Recording       │                                         │
│  │ Published       │                                         │
│  └────────┬────────┘                                         │
│           │                                                   │
│           ▼                                                   │
│  ┌─────────────────────┐      ┌──────────────┐              │
│  │ b3lb-push-hook.rb   │─────▶│ SQLite Queue │              │
│  │ (post_publish)      │      └──────┬───────┘              │
│  └─────────────────────┘             │                       │
│                                       ▼                       │
│  ┌─────────────────────┐      ┌──────────────────┐          │
│  │ b3lb-push           │◀─────│ Systemd Trigger  │          │
│  │ (upload worker)     │      │ (path + timer)   │          │
│  └──────────┬──────────┘      └──────────────────┘          │
│             │                                                 │
│             │ HTTP POST                                       │
│             ▼                                                 │
│         ┌─────────────────────────┐                          │
│         │   B3LB Backend API      │◀──┐                      │
│         │   (Recording Storage)   │   │                      │
│         └─────────────────────────┘   │                      │
│                                        │ HTTP GET /b3lb/load │
│  ┌─────────────────────┐              │                      │
│  │ b3lb-load           │              │                      │
│  │ (CPU monitor)       │              │                      │
│  └──────────┬──────────┘              │                      │
│             │ writes                   │                      │
│             ▼                          │                      │
│  ┌─────────────────────┐              │                      │
│  │ /run/b3lb/load      │              │                      │
│  └──────────┬──────────┘              │                      │
│             │ served by                │                      │
│             ▼                          │                      │
│  ┌─────────────────────┐              │                      │
│  │ nginx               │──────────────┘                      │
│  │ /b3lb/load endpoint │                                     │
│  └─────────────────────┘                                     │
│                                                               │
│  ┌─────────────────────┐      ┌──────────────┐              │
│  │ b3lb-cleaner        │◀─────│ Daily Timer  │              │
│  │ (meeting cleanup)   │      │ (05:00)      │              │
│  └──────────┬──────────┘      └──────────────┘              │
│             │                                                 │
│             ▼                                                 │
│  ┌─────────────────────┐                                     │
│  │ Local BBB API       │                                     │
│  │ (getMeetings/end)   │                                     │
│  └─────────────────────┘                                     │
└─────────────────────────────────────────────────────────────┘
```

## Prerequisites

### System Requirements

- **BigBlueButton**: Fully installed and configured BBB server
- **Operating System**: Ubuntu 20.04 or 22.04 (standard BBB platforms)
- **Python 3**: Already included in BBB installations
- **Ruby**: With `ruby-sqlite3` gem
- **Nginx**: Already part of BBB installation
- **Systemd**: Standard init system
- **Access**: Root or sudo privileges

### Network Requirements

- BBB node must be able to reach B3LB backend API (for b3lb-push)
- B3LB backend must be able to query BBB node HTTPS endpoint (for b3lb-load)
- BBB node must be able to reach its own API on localhost (for b3lb-cleaner)

### Install Dependencies

```bash
# Install Ruby SQLite3 gem (required for b3lb-push hook)
apt-get update
apt-get install -y ruby-sqlite3

# Install Python requests library (required for b3lb-push)
apt-get install -y python3-requests

# Verify installations
ruby -r sqlite3 -e "puts 'SQLite3 gem OK'"
python3 -c "import requests; print('Requests module OK')"
```

## Installation

### Recommended Installation Order

1. **b3lb-load** (provides immediate load balancing capability)
2. **b3lb-push** (enables recording upload)
3. **b3lb-cleaner** (optional maintenance)

---

## 1. Installing b3lb-load (CPU Load Monitor)

### Purpose
Continuously calculates CPU utilization and exposes it via HTTP endpoint for B3LB to query during load balancing decisions.

### Installation Steps

```bash
# Navigate to the b3lb-load directory
cd /path/to/b3lb/scripts/bbb/load

# Create script directory
mkdir -p /usr/local/lib/b3lb

# Copy the monitoring script
cp b3lb-load /usr/local/lib/b3lb/
chmod +x /usr/local/lib/b3lb/b3lb-load

# Copy nginx configuration
cp b3lb-load.nginx /etc/bigbluebutton/nginx/

# Test nginx configuration
nginx -t

# If test passes, reload nginx
systemctl reload nginx

# Install systemd service
cp b3lb-load.service /etc/systemd/system/

# Reload systemd and enable service
systemctl daemon-reload
systemctl enable b3lb-load.service
systemctl start b3lb-load.service

# Verify service is running
systemctl status b3lb-load.service
```

### Verification

```bash
# Check if load file is being created
ls -la /run/b3lb/load

# Test the HTTP endpoint (replace with your BBB hostname)
curl https://your-bbb-node.example.com/b3lb/load

# Expected output: An integer between 0-10000 (e.g., "3542")
```

### Configuration Notes

- **No configuration file needed** - works out of the box
- Load value scale: 0-10000 (0 = idle, 10000 = fully loaded)
- Updates every 10 seconds
- Uses sliding window averaging (60 seconds)

### Security Recommendation

Consider adding nginx access control to restrict the `/b3lb/load` endpoint to B3LB backend IPs only:

```nginx
# Edit /etc/bigbluebutton/nginx/b3lb-load.nginx
location /b3lb/load {
    alias /run/b3lb/load;

    # Add access control
    allow 10.0.0.0/8;        # B3LB backend network
    allow 192.168.1.100;     # B3LB backend IP
    deny all;
}
```

---

## 2. Installing b3lb-push (Recording Uploader)

### Purpose
Automatically uploads published BBB recordings to the B3LB backend for centralized storage and distribution.

### Installation Steps

```bash
# Navigate to the b3lb-push directory
cd /path/to/b3lb/scripts/bbb/push

# Create necessary directories
mkdir -p /usr/local/lib/b3lb
mkdir -p /etc/b3lb
mkdir -p /var/bigbluebutton/b3lb

# Copy the Ruby post-publish hook
cp b3lb-push-hook.rb /usr/local/bigbluebutton/core/scripts/post_publish/
chmod +x /usr/local/bigbluebutton/core/scripts/post_publish/b3lb-push-hook.rb

# Copy the Python upload worker
cp b3lb-push /usr/local/lib/b3lb/
chmod +x /usr/local/lib/b3lb/b3lb-push

# Copy configuration file
cp push.properties /etc/b3lb/

# IMPORTANT: Edit configuration with your B3LB backend URL
nano /etc/b3lb/push.properties
# Set: b3lbBaseDomain=https://your-b3lb-backend.example.com

# Install systemd units
cp b3lb-push.service /etc/systemd/system/
cp b3lb-push.path /etc/systemd/system/
cp b3lb-push.timer /etc/systemd/system/

# Reload systemd and enable services
systemctl daemon-reload
systemctl enable b3lb-push.path
systemctl enable b3lb-push.timer
systemctl start b3lb-push.path
systemctl start b3lb-push.timer

# Verify services are running
systemctl status b3lb-push.path
systemctl status b3lb-push.timer
```

### Configuration (REQUIRED)

Edit `/etc/b3lb/push.properties` and set the following:

```properties
# B3LB backend API URL (REQUIRED - no trailing slash)
b3lbBaseDomain=https://your-b3lb-backend.example.com

# BBB published recordings directory (default - usually no change needed)
publishedFolder=/var/bigbluebutton/published/presentation

# Queue database location (default - usually no change needed)
queueDirname=/var/bigbluebutton/b3lb
queueFilename=queue.db

# Metadata tag for authorization nonce (default - usually no change needed)
nonceMetaTag=b3lb-nonce
```

### Verification

```bash
# Check if queue database is created (after first recording)
ls -la /var/bigbluebutton/b3lb/queue.db

# Monitor the post-publish hook log
tail -f /var/log/bigbluebutton/b3lb_push_hook.log

# Check systemd service logs
journalctl -u b3lb-push.service -f

# Manually trigger the upload processor (for testing)
systemctl start b3lb-push.service
```

### How It Works

1. **Recording Published** → BBB processes recording
2. **Hook Triggered** → `b3lb-push-hook.rb` runs after publishing
3. **Metadata Check** → Hook looks for `b3lb-nonce` metadata
4. **Queue Entry** → If nonce found, recording queued in SQLite
5. **Upload Trigger** → Systemd path monitor or timer triggers upload
6. **Processing** → `b3lb-push` creates tar archive and uploads
7. **Cleanup** → On success, local recording deleted via `bbb-record --delete`

### Troubleshooting

**No recordings being uploaded:**
```bash
# Check if hook is being triggered
tail -f /var/log/bigbluebutton/b3lb_push_hook.log

# Check queue database
sqlite3 /var/bigbluebutton/b3lb/queue.db "SELECT * FROM backlog;"

# Manually trigger upload
systemctl start b3lb-push.service
journalctl -u b3lb-push.service -n 50
```

**Upload failures:**
```bash
# Check network connectivity to B3LB backend
curl -I https://your-b3lb-backend.example.com

# Review upload worker logs
journalctl -u b3lb-push.service -n 100 --no-pager

# Check push.properties configuration
cat /etc/b3lb/push.properties
```

---

## 3. Installing b3lb-cleaner (Meeting Cleanup)

### Purpose
Automatically terminates meetings running longer than a configured timeout (default: 12 hours) to prevent orphaned or forgotten meetings from consuming resources.

### Installation Steps

```bash
# Navigate to the b3lb-cleaner directory
cd /path/to/b3lb/scripts/bbb/cleaner

# Create script directory
mkdir -p /opt/b3lb/scripts

# Copy the cleanup script
cp cleaner.py /opt/b3lb/scripts/
chmod +x /opt/b3lb/scripts/cleaner.py

# (Optional) Adjust meeting timeout
# nano /opt/b3lb/scripts/cleaner.py
# Change: MEETING_TIMEOUT = timedelta(hours=12)

# Install systemd units
cp b3lb-cleaner.service /etc/systemd/system/
cp b3lb-cleaner.timer /etc/systemd/system/

# Reload systemd and enable timer
systemctl daemon-reload
systemctl enable b3lb-cleaner.timer
systemctl start b3lb-cleaner.timer

# Verify timer is active
systemctl status b3lb-cleaner.timer
systemctl list-timers b3lb-cleaner.timer
```

### Configuration

Edit `/opt/b3lb/scripts/cleaner.py` to adjust the timeout:

```python
# Default: 12 hours
MEETING_TIMEOUT = timedelta(hours=12)

# Examples:
# 6 hours:  MEETING_TIMEOUT = timedelta(hours=6)
# 24 hours: MEETING_TIMEOUT = timedelta(hours=24)
```

### Verification

```bash
# Check when the timer will next run
systemctl list-timers b3lb-cleaner.timer

# Manually trigger cleanup (for testing)
systemctl start b3lb-cleaner.service

# View cleanup logs
journalctl -u b3lb-cleaner.service -n 50

# Expected output when meetings terminated:
# "Ending meeting <meeting-id> (running for X hours)"
```

### How It Works

1. **Daily Trigger** → Runs every day at 05:00
2. **API Query** → Calls local BBB `getMeetings` API
3. **Age Check** → Identifies meetings older than timeout
4. **Termination** → Calls BBB `end` API for old meetings
5. **Logging** → Logs terminated meetings to systemd journal

### Configuration Notes

- **No separate config file** - uses BBB's own API credentials
- Runs daily at 05:00 (configurable in `b3lb-cleaner.timer`)
- Safe to run - only affects meetings exceeding the timeout
- Uses `bbb-conf --secret` to retrieve API credentials automatically

---

## Directory Structure Reference

After installation, the following directory structure will be created:

```
/usr/local/lib/b3lb/
├── b3lb-load              # CPU monitoring daemon
└── b3lb-push              # Recording upload worker

/opt/b3lb/scripts/
└── cleaner.py             # Meeting cleanup script

/etc/b3lb/
└── push.properties        # Push service configuration

/etc/systemd/system/
├── b3lb-load.service      # Load monitor service
├── b3lb-push.service      # Push upload service
├── b3lb-push.path         # Push path trigger
├── b3lb-push.timer        # Push timer trigger
├── b3lb-cleaner.service   # Cleaner service
└── b3lb-cleaner.timer     # Cleaner timer

/etc/bigbluebutton/nginx/
└── b3lb-load.nginx        # Load endpoint nginx config

/usr/local/bigbluebutton/core/scripts/post_publish/
└── b3lb-push-hook.rb      # Recording post-publish hook

/var/bigbluebutton/b3lb/
└── queue.db               # Recording upload queue (auto-created)

/run/b3lb/
└── load                   # Current CPU load value (auto-created)

/var/log/bigbluebutton/
└── b3lb_push_hook.log     # Push hook log (auto-created)
```

## Service Status Overview

Check the status of all B3LB services:

```bash
# View all service statuses
systemctl status b3lb-load.service
systemctl status b3lb-push.path
systemctl status b3lb-push.timer
systemctl status b3lb-cleaner.timer

# View service logs
journalctl -u b3lb-load.service -f
journalctl -u b3lb-push.service -f
journalctl -u b3lb-cleaner.service -f

# Check timers
systemctl list-timers | grep b3lb
```

## Uninstallation

To remove B3LB scripts from a BBB node:

```bash
# Stop and disable services
systemctl stop b3lb-load.service b3lb-push.path b3lb-push.timer b3lb-cleaner.timer
systemctl disable b3lb-load.service b3lb-push.path b3lb-push.timer b3lb-cleaner.timer

# Remove systemd units
rm /etc/systemd/system/b3lb-*.{service,path,timer}
systemctl daemon-reload

# Remove scripts
rm /usr/local/lib/b3lb/b3lb-load
rm /usr/local/lib/b3lb/b3lb-push
rm /opt/b3lb/scripts/cleaner.py
rm /usr/local/bigbluebutton/core/scripts/post_publish/b3lb-push-hook.rb

# Remove configuration
rm /etc/b3lb/push.properties
rm /etc/bigbluebutton/nginx/b3lb-load.nginx

# Reload nginx
nginx -t && systemctl reload nginx

# Remove data directories (optional - preserves queue)
# rm -rf /var/bigbluebutton/b3lb
# rm -rf /run/b3lb
```

## Security Considerations

1. **Access Control**: Restrict `/b3lb/load` endpoint to B3LB backend IPs only
2. **HTTPS Required**: Always use HTTPS for B3LB backend communication
3. **API Secrets**: b3lb-nonce metadata must be secured
4. **File Permissions**: Scripts should not be world-writable
5. **Log Monitoring**: Review logs regularly for unauthorized access attempts

## Troubleshooting

### General Diagnostics

```bash
# Check service status
systemctl status b3lb-*.service b3lb-*.path b3lb-*.timer

# View recent logs
journalctl -u b3lb-load.service -n 100
journalctl -u b3lb-push.service -n 100
journalctl -u b3lb-cleaner.service -n 100

# Check file permissions
ls -la /usr/local/lib/b3lb/
ls -la /etc/b3lb/
ls -la /opt/b3lb/scripts/

# Verify dependencies
ruby -r sqlite3 -e "puts 'Ruby SQLite3 OK'"
python3 -c "import requests; print('Python requests OK')"
python3 -c "import sqlite3; print('Python sqlite3 OK')"
```

### Common Issues

**b3lb-load endpoint returns 404:**
- Check nginx configuration: `nginx -t`
- Verify config file exists: `ls /etc/bigbluebutton/nginx/b3lb-load.nginx`
- Reload nginx: `systemctl reload nginx`
- Check load file exists: `ls /run/b3lb/load`

**Recordings not uploading:**
- Verify B3LB backend URL in `/etc/b3lb/push.properties`
- Check network connectivity: `curl -I https://your-b3lb-backend.example.com`
- Review hook log: `tail -f /var/log/bigbluebutton/b3lb_push_hook.log`
- Check queue: `sqlite3 /var/bigbluebutton/b3lb/queue.db "SELECT * FROM backlog;"`
- Manually trigger: `systemctl start b3lb-push.service`

**Meetings not being cleaned up:**
- Check timer status: `systemctl list-timers b3lb-cleaner.timer`
- Manually run: `systemctl start b3lb-cleaner.service`
- View logs: `journalctl -u b3lb-cleaner.service -n 50`
- Verify BBB API access: `bbb-conf --secret`

## Support and Documentation

- **B3LB Documentation**: https://docs.b3lb.io/
- **B3LB GitHub**: https://github.com/DE-IBH/b3lb
- **BigBlueButton Documentation**: https://docs.bigbluebutton.org/
- **License**: GNU Affero General Public License v3.0

## Credits

These scripts are part of the B3LB project developed by IBH IT-Service GmbH.

- **Copyright**: © IBH IT-Service GmbH
- **License**: AGPL-3.0
- **Project Homepage**: https://github.com/DE-IBH/b3lb
