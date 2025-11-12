# BBB Node Scripts

## Overview

B3LB requires three scripts to be installed on each BigBlueButton node for full functionality:

1. **Load Script** (`b3lb-load`): Exposes CPU load via HTTP endpoint
2. **Push Hook** (`b3lb-push-hook.rb` & `b3lb-push`): Uploads recordings to B3LB
3. **Cleaner** (`cleaner.py`): Cleans up processed recordings

These scripts are located in the [scripts/bbb/](../scripts/bbb/) directory of the B3LB repository.

---

## Load Script

### Purpose

Exposes the BBB node's CPU load as an HTTP endpoint for B3LB's load balancing algorithm.

### Location

[scripts/bbb/load/](../scripts/bbb/load/)

### Components

1. **b3lb-load**: Python script that reads CPU load
2. **b3lb-load.service**: Systemd service
3. **b3lb-load.nginx**: Nginx configuration

---

### Installation

**1. Copy Load Script**:

```bash
# On BBB node
sudo cp b3lb-load /usr/local/bin/
sudo chmod +x /usr/local/bin/b3lb-load
```

**2. Install Systemd Service**:

```bash
# Copy service file
sudo cp b3lb-load.service /etc/systemd/system/

# Reload systemd
sudo systemctl daemon-reload

# Enable and start service
sudo systemctl enable b3lb-load
sudo systemctl start b3lb-load

# Verify status
sudo systemctl status b3lb-load
```

**3. Configure Nginx**:

```bash
# Copy nginx config
sudo cp b3lb-load.nginx /etc/bigbluebutton/nginx/

# Test nginx config
sudo nginx -t

# Reload nginx
sudo systemctl reload nginx
```

---

### Script Details

**b3lb-load**:

```python
#!/usr/bin/env python3
"""
B3LB Load Endpoint
Serves CPU load over HTTP for B3LB load balancing
"""

import http.server
import socketserver
import os

PORT = 8765

class LoadHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/':
            # Read 1-minute load average
            load = os.getloadavg()[0]

            # Read CPU count
            cpu_count = os.cpu_count() or 1

            # Calculate CPU percentage (load / cpu_count * 100)
            cpu_percent = (load / cpu_count) * 100

            self.send_response(200)
            self.send_header('Content-Type', 'text/plain')
            self.end_headers()
            self.wfile.write(f"{cpu_percent:.2f}\n".encode())
        else:
            self.send_error(404)

    def log_message(self, format, *args):
        pass  # Disable logging

if __name__ == '__main__':
    with socketserver.TCPServer(("127.0.0.1", PORT), LoadHandler) as httpd:
        print(f"Serving load on port {PORT}")
        httpd.serve_forever()
```

**Systemd Service** (`b3lb-load.service`):

```ini
[Unit]
Description=B3LB Load Endpoint
After=network.target

[Service]
Type=simple
User=bigbluebutton
ExecStart=/usr/local/bin/b3lb-load
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
```

**Nginx Configuration** (`b3lb-load.nginx`):

```nginx
location /b3lb/load {
    proxy_pass http://127.0.0.1:8765/;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;

    # Allow only B3LB to access
    allow 10.0.0.0/8;      # Internal network
    allow 172.16.0.0/12;   # Docker network
    allow 192.168.0.0/16;  # Local network
    deny all;
}
```

---

### Verification

**Test Locally**:
```bash
curl http://localhost/b3lb/load
```

**Expected Output**:
```
45.32
```

**Test from B3LB**:
```bash
curl https://bbb01.example.com/b3lb/load
```

---

### Troubleshooting

**Service Not Running**:
```bash
# Check status
sudo systemctl status b3lb-load

# Check logs
sudo journalctl -u b3lb-load -f
```

**Port Already in Use**:
```bash
# Check what's using port 8765
sudo netstat -tulpn | grep 8765

# Change port in b3lb-load script and restart
```

**Nginx 403 Forbidden**:
```bash
# Verify IP whitelist in b3lb-load.nginx
# Add B3LB server IP to allow list
```

---

## Push Hook & Script

### Purpose

Automatically uploads recordings from BBB nodes to B3LB for processing and distribution.

### Location

[scripts/bbb/push/](../scripts/bbb/push/)

### Components

1. **b3lb-push-hook.rb**: BBB post-archive hook (Ruby)
2. **b3lb-push**: Upload script (bash)
3. **b3lb-push.service**: Systemd service (one-shot)
4. **b3lb-push.timer**: Systemd timer (periodic uploads)

---

### Installation

**1. Copy Hook Script**:

```bash
# On BBB node
sudo cp b3lb-push-hook.rb /usr/local/bigbluebutton/core/scripts/post_archive/
sudo chmod +x /usr/local/bigbluebutton/core/scripts/post_archive/b3lb-push-hook.rb
```

**2. Copy Upload Script**:

```bash
sudo cp b3lb-push /usr/local/bin/
sudo chmod +x /usr/local/bin/b3lb-push
```

**3. Configure Upload Script**:

Edit `/usr/local/bin/b3lb-push`:

```bash
# B3LB Configuration
B3LB_ENDPOINT="https://bbb.example.com/b3lb/b/recording/upload"
B3LB_NODE_SECRET="your-node-secret-here"
B3LB_RECORDING_DIR="/var/bigbluebutton/recording/status/archived"
```

**4. Install Systemd Service & Timer**:

```bash
# Copy service and timer
sudo cp b3lb-push.service /etc/systemd/system/
sudo cp b3lb-push.timer /etc/systemd/system/

# Reload systemd
sudo systemctl daemon-reload

# Enable timer (runs every 5 minutes)
sudo systemctl enable b3lb-push.timer
sudo systemctl start b3lb-push.timer

# Verify timer
sudo systemctl list-timers | grep b3lb-push
```

---

### Script Details

**Post-Archive Hook** (`b3lb-push-hook.rb`):

```ruby
#!/usr/bin/ruby
# B3LB Post-Archive Hook
# Triggers upload of archived recordings to B3LB

require 'fileutils'

meeting_id = ARGV[0]
recording_dir = "/var/bigbluebutton/recording/status/archived"

# Create marker file for upload script
marker_file = File.join(recording_dir, "#{meeting_id}.ready")
FileUtils.touch(marker_file)

puts "B3LB: Marked recording #{meeting_id} for upload"
exit 0
```

**Upload Script** (`b3lb-push`):

```bash
#!/bin/bash
# B3LB Recording Upload Script
# Uploads archived recordings to B3LB

set -e

# Configuration
B3LB_ENDPOINT="https://bbb.example.com/b3lb/b/recording/upload"
B3LB_NODE_SECRET="your-node-secret-here"
B3LB_RECORDING_DIR="/var/bigbluebutton/recording/status/archived"

# Find ready recordings
for marker in "$B3LB_RECORDING_DIR"/*.ready; do
    [ -e "$marker" ] || continue

    meeting_id=$(basename "$marker" .ready)
    recording_file="$B3LB_RECORDING_DIR/$meeting_id.tar"

    # Check if tar exists
    if [ ! -f "$recording_file" ]; then
        echo "Recording tar not found: $recording_file"
        rm "$marker"
        continue
    fi

    echo "Uploading recording: $meeting_id"

    # Upload to B3LB
    response=$(curl -s -w "\n%{http_code}" \
        -X POST \
        -H "X-Node-Secret: $B3LB_NODE_SECRET" \
        -F "recording=@$recording_file" \
        "$B3LB_ENDPOINT")

    http_code=$(echo "$response" | tail -n1)

    if [ "$http_code" = "200" ]; then
        echo "Upload successful: $meeting_id"
        # Remove marker (tar will be cleaned by cleaner script)
        rm "$marker"
    else
        echo "Upload failed: $meeting_id (HTTP $http_code)"
        # Keep marker for retry
    fi
done
```

**Systemd Service** (`b3lb-push.service`):

```ini
[Unit]
Description=B3LB Recording Upload
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/b3lb-push
User=bigbluebutton

[Install]
WantedBy=multi-user.target
```

**Systemd Timer** (`b3lb-push.timer`):

```ini
[Unit]
Description=B3LB Recording Upload Timer
Requires=b3lb-push.service

[Timer]
OnBootSec=5min
OnUnitActiveSec=5min

[Install]
WantedBy=timers.target
```

---

### Verification

**Test Upload Manually**:
```bash
sudo -u bigbluebutton /usr/local/bin/b3lb-push
```

**Check Timer Status**:
```bash
sudo systemctl status b3lb-push.timer
```

**View Upload Logs**:
```bash
sudo journalctl -u b3lb-push.service -f
```

---

### Troubleshooting

**Upload Fails with 401 Unauthorized**:
- Verify `B3LB_NODE_SECRET` matches B3LB configuration
- Check B3LB backend endpoint URL

**Recording Not Uploaded**:
- Verify post-archive hook executed: Check for `.ready` marker files
- Check recording tar exists in archived directory
- Verify network connectivity to B3LB
- Check B3LB logs for upload errors

**Timer Not Running**:
```bash
# Check timer status
sudo systemctl status b3lb-push.timer

# Enable timer
sudo systemctl enable b3lb-push.timer
sudo systemctl start b3lb-push.timer
```

---

## Cleaner Script

### Purpose

Removes processed recordings from BBB nodes after successful upload to B3LB, freeing disk space.

### Location

[scripts/bbb/cleaner/](../scripts/bbb/cleaner/)

### Components

1. **cleaner.py**: Python script to clean recordings
2. **b3lb-cleaner.service**: Systemd service (one-shot)
3. **b3lb-cleaner.timer**: Systemd timer (daily cleanup)

---

### Installation

**1. Copy Cleaner Script**:

```bash
# On BBB node
sudo cp cleaner.py /usr/local/bin/b3lb-cleaner
sudo chmod +x /usr/local/bin/b3lb-cleaner
```

**2. Configure Cleaner**:

Edit `/usr/local/bin/b3lb-cleaner`:

```python
# Configuration
RECORDING_DIR = "/var/bigbluebutton/recording/status/archived"
RETENTION_DAYS = 7  # Keep recordings for 7 days after upload
DRY_RUN = False     # Set to True for testing
```

**3. Install Systemd Service & Timer**:

```bash
# Copy service and timer
sudo cp b3lb-cleaner.service /etc/systemd/system/
sudo cp b3lb-cleaner.timer /etc/systemd/system/

# Reload systemd
sudo systemctl daemon-reload

# Enable timer (runs daily at 3 AM)
sudo systemctl enable b3lb-cleaner.timer
sudo systemctl start b3lb-cleaner.timer

# Verify timer
sudo systemctl list-timers | grep b3lb-cleaner
```

---

### Script Details

**Cleaner Script** (`cleaner.py`):

```python
#!/usr/bin/env python3
"""
B3LB Recording Cleaner
Removes old recordings that have been uploaded to B3LB
"""

import os
import time
from datetime import datetime, timedelta

# Configuration
RECORDING_DIR = "/var/bigbluebutton/recording/status/archived"
RETENTION_DAYS = 7
DRY_RUN = False

def clean_old_recordings():
    """Clean recordings older than retention period"""
    cutoff_time = time.time() - (RETENTION_DAYS * 86400)
    cleaned_count = 0

    for filename in os.listdir(RECORDING_DIR):
        if not filename.endswith('.tar'):
            continue

        filepath = os.path.join(RECORDING_DIR, filename)

        # Check if file is old enough
        if os.path.getmtime(filepath) < cutoff_time:
            # Check if already uploaded (no .ready marker)
            marker = filepath.replace('.tar', '.ready')
            if not os.path.exists(marker):
                # Safe to delete
                if DRY_RUN:
                    print(f"Would delete: {filename}")
                else:
                    os.remove(filepath)
                    print(f"Deleted: {filename}")
                cleaned_count += 1

    print(f"Cleaned {cleaned_count} recordings")

if __name__ == '__main__':
    clean_old_recordings()
```

**Systemd Service** (`b3lb-cleaner.service`):

```ini
[Unit]
Description=B3LB Recording Cleaner
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/b3lb-cleaner
User=bigbluebutton

[Install]
WantedBy=multi-user.target
```

**Systemd Timer** (`b3lb-cleaner.timer`):

```ini
[Unit]
Description=B3LB Recording Cleaner Timer
Requires=b3lb-cleaner.service

[Timer]
OnCalendar=daily
OnCalendar=03:00
Persistent=true

[Install]
WantedBy=timers.target
```

---

### Verification

**Test Cleaner (Dry Run)**:

Edit script to set `DRY_RUN = True`, then:
```bash
sudo -u bigbluebutton /usr/local/bin/b3lb-cleaner
```

**Check Timer Status**:
```bash
sudo systemctl status b3lb-cleaner.timer
```

**View Cleaner Logs**:
```bash
sudo journalctl -u b3lb-cleaner.service -f
```

---

### Troubleshooting

**Disk Space Still Full**:
- Check `RETENTION_DAYS` setting
- Verify `.ready` markers removed after successful upload
- Check for recordings stuck in other BBB directories

**Cleaner Not Running**:
```bash
# Check timer status
sudo systemctl status b3lb-cleaner.timer

# Enable timer
sudo systemctl enable b3lb-cleaner.timer
sudo systemctl start b3lb-cleaner.timer
```

**Recordings Deleted Too Quickly**:
- Increase `RETENTION_DAYS` in cleaner script
- Verify upload is completing successfully first

---

## Complete Installation Procedure

### Prerequisites

- BigBlueButton node installed and operational
- B3LB server deployed and accessible
- Node added to B3LB (see [Operations Manual](./08-operations.md))

---

### Step-by-Step Installation

**1. Prepare BBB Node**:

```bash
# SSH to BBB node
ssh root@bbb01.example.com

# Create working directory
mkdir /tmp/b3lb-scripts
cd /tmp/b3lb-scripts
```

**2. Download Scripts**:

```bash
# Clone B3LB repository
git clone https://github.com/DE-IBH/b3lb.git
cd b3lb/scripts/bbb/
```

**3. Install Load Script**:

```bash
cd load/

# Copy files
sudo cp b3lb-load /usr/local/bin/
sudo chmod +x /usr/local/bin/b3lb-load
sudo cp b3lb-load.service /etc/systemd/system/
sudo cp b3lb-load.nginx /etc/bigbluebutton/nginx/

# Enable and start
sudo systemctl daemon-reload
sudo systemctl enable b3lb-load
sudo systemctl start b3lb-load

# Verify
sudo systemctl status b3lb-load
curl http://localhost/b3lb/load
```

**4. Install Push Hook**:

```bash
cd ../push/

# Copy hook
sudo cp b3lb-push-hook.rb /usr/local/bigbluebutton/core/scripts/post_archive/
sudo chmod +x /usr/local/bigbluebutton/core/scripts/post_archive/b3lb-push-hook.rb

# Copy and configure upload script
sudo cp b3lb-push /usr/local/bin/
sudo chmod +x /usr/local/bin/b3lb-push

# IMPORTANT: Edit configuration
sudo nano /usr/local/bin/b3lb-push
# Set B3LB_ENDPOINT and B3LB_NODE_SECRET

# Install systemd units
sudo cp b3lb-push.service /etc/systemd/system/
sudo cp b3lb-push.timer /etc/systemd/system/

# Enable and start timer
sudo systemctl daemon-reload
sudo systemctl enable b3lb-push.timer
sudo systemctl start b3lb-push.timer

# Verify
sudo systemctl list-timers | grep b3lb-push
```

**5. Install Cleaner**:

```bash
cd ../cleaner/

# Copy and configure script
sudo cp cleaner.py /usr/local/bin/b3lb-cleaner
sudo chmod +x /usr/local/bin/b3lb-cleaner

# OPTIONAL: Edit retention settings
sudo nano /usr/local/bin/b3lb-cleaner

# Install systemd units
sudo cp b3lb-cleaner.service /etc/systemd/system/
sudo cp b3lb-cleaner.timer /etc/systemd/system/

# Enable and start timer
sudo systemctl daemon-reload
sudo systemctl enable b3lb-cleaner.timer
sudo systemctl start b3lb-cleaner.timer

# Verify
sudo systemctl list-timers | grep b3lb-cleaner
```

**6. Final Verification**:

```bash
# Check all services
sudo systemctl status b3lb-load
sudo systemctl status b3lb-push.timer
sudo systemctl status b3lb-cleaner.timer

# Test load endpoint
curl http://localhost/b3lb/load

# Check timers
sudo systemctl list-timers
```

**7. Add Node to B3LB**:

```bash
# On B3LB server
docker-compose exec frontend python manage.py addnode \
  bbb01 \
  bbb01.example.com \
  <bbb-secret> \
  main-cluster
```

**8. Test Integration**:

- Create a test meeting via B3LB
- Verify meeting created on bbb01 node
- Check B3LB admin for node CPU load
- Record a short meeting
- Wait for upload (check logs: `sudo journalctl -u b3lb-push.service`)
- Verify recording appears in B3LB admin

---

## Automation Script

**Automated Installation**:

```bash
#!/bin/bash
# install-b3lb-scripts.sh
# Automated installation of B3LB node scripts

set -e

# Configuration
B3LB_ENDPOINT="https://bbb.example.com/b3lb/b/recording/upload"
B3LB_NODE_SECRET="your-node-secret-here"
RETENTION_DAYS=7

# Clone repository
git clone https://github.com/DE-IBH/b3lb.git /tmp/b3lb
cd /tmp/b3lb/scripts/bbb

# Install load script
cd load
cp b3lb-load /usr/local/bin/
chmod +x /usr/local/bin/b3lb-load
cp b3lb-load.service /etc/systemd/system/
cp b3lb-load.nginx /etc/bigbluebutton/nginx/
systemctl daemon-reload
systemctl enable b3lb-load
systemctl start b3lb-load
nginx -t && systemctl reload nginx
echo "✓ Load script installed"

# Install push hook
cd ../push
cp b3lb-push-hook.rb /usr/local/bigbluebutton/core/scripts/post_archive/
chmod +x /usr/local/bigbluebutton/core/scripts/post_archive/b3lb-push-hook.rb
cp b3lb-push /usr/local/bin/
chmod +x /usr/local/bin/b3lb-push
sed -i "s|B3LB_ENDPOINT=.*|B3LB_ENDPOINT=\"$B3LB_ENDPOINT\"|" /usr/local/bin/b3lb-push
sed -i "s|B3LB_NODE_SECRET=.*|B3LB_NODE_SECRET=\"$B3LB_NODE_SECRET\"|" /usr/local/bin/b3lb-push
cp b3lb-push.service /etc/systemd/system/
cp b3lb-push.timer /etc/systemd/system/
systemctl daemon-reload
systemctl enable b3lb-push.timer
systemctl start b3lb-push.timer
echo "✓ Push hook installed"

# Install cleaner
cd ../cleaner
cp cleaner.py /usr/local/bin/b3lb-cleaner
chmod +x /usr/local/bin/b3lb-cleaner
sed -i "s|RETENTION_DAYS = .*|RETENTION_DAYS = $RETENTION_DAYS|" /usr/local/bin/b3lb-cleaner
cp b3lb-cleaner.service /etc/systemd/system/
cp b3lb-cleaner.timer /etc/systemd/system/
systemctl daemon-reload
systemctl enable b3lb-cleaner.timer
systemctl start b3lb-cleaner.timer
echo "✓ Cleaner installed"

# Verify
echo ""
echo "Installation complete!"
echo "Verifying services..."
systemctl status b3lb-load --no-pager
systemctl list-timers | grep b3lb
echo ""
echo "Load endpoint: http://localhost/b3lb/load"
curl -s http://localhost/b3lb/load
echo ""
```

**Usage**:
```bash
# Edit configuration in script
sudo nano install-b3lb-scripts.sh

# Run installation
sudo bash install-b3lb-scripts.sh
```

---

## Monitoring BBB Node Integration

### Check Node Status in B3LB

**Via Admin**:
- Admin → Nodes → View node list
- Check CPU load, attendees, meetings columns
- Verify `has_errors` is False
- Verify `maintenance` is False

**Via CLI**:
```bash
docker-compose exec frontend python manage.py getloadvalues
```

### Monitor Recording Uploads

**On BBB Node**:
```bash
# Check for pending uploads
ls /var/bigbluebutton/recording/status/archived/*.ready

# View upload logs
sudo journalctl -u b3lb-push.service -n 50

# Manual upload
sudo -u bigbluebutton /usr/local/bin/b3lb-push
```

**On B3LB**:
- Admin → RecordSets → View recent uploads
- Check status (UPLOADED, RENDERED)

---

## Next Steps

- [Operations Manual](./08-operations.md): Monitor node integration
- [Configuration](./04-configuration.md): Configure B3LB settings
- [Docker Deployment](./05-docker-deployment.md): Deploy B3LB services
