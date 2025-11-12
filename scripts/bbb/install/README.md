# B3LB BBB Node - Automated Installation

This directory contains automated installation scripts for deploying B3LB services on BigBlueButton nodes.

## Quick Start

### 1. Clone the Repository

On your BBB node:

```bash
cd /tmp
git clone https://github.com/ayman-makki/b3lb.git
cd b3lb/scripts/bbb/install
```

### 2. Configure

Copy the example configuration and edit it:

```bash
cp config.env.example config.env
nano config.env
```

**Required Settings:**
- `B3LB_BACKEND_URL`: Your B3LB backend API URL (e.g., `https://b3lb-api.example.com`)

**Optional Settings:**
- `MEETING_TIMEOUT_HOURS`: Meeting cleanup timeout (default: 12)
- `ENABLE_LOAD`: Install b3lb-load service (default: true)
- `ENABLE_PUSH`: Install b3lb-push service (default: true)
- `ENABLE_CLEANER`: Install b3lb-cleaner service (default: false)

### 3. Install

Run the automated installation:

```bash
sudo ./install-all.sh
```

Or install components individually:

```bash
sudo ./00-preflight-check.sh
sudo ./01-install-dependencies.sh
sudo ./02-install-b3lb-load.sh
sudo ./03-install-b3lb-push.sh
sudo ./04-install-b3lb-cleaner.sh
```

## Installation Scripts

### `config.env.example`
Template configuration file. Copy to `config.env` and customize for your environment.

### `00-preflight-check.sh`
Verifies all prerequisites before installation:
- Root privileges
- Operating system compatibility
- BigBlueButton installation
- Required system commands
- Configuration file validation
- Network connectivity
- Disk space

### `01-install-dependencies.sh`
Installs required system dependencies:
- `ruby-sqlite3` gem (for b3lb-push hook)
- `python3-requests` library (for b3lb-push worker)

### `02-install-b3lb-load.sh`
Installs the CPU load monitoring service:
- Creates directories (`/usr/local/lib/b3lb`, `/run/b3lb`)
- Copies monitoring daemon
- Configures nginx endpoint
- Installs and starts systemd service
- Verifies HTTP endpoint accessibility

### `03-install-b3lb-push.sh`
Installs the recording upload service:
- Creates directories (`/usr/local/lib/b3lb`, `/etc/b3lb`, `/var/bigbluebutton/b3lb`)
- Copies post-publish hook and upload worker
- Generates `push.properties` from config.env
- Installs systemd service, path monitor, and timer
- Configures permissions for bigbluebutton user

### `04-install-b3lb-cleaner.sh`
Installs the meeting cleanup service:
- Creates directory (`/opt/b3lb/scripts`)
- Copies cleanup script
- Configures meeting timeout
- Installs systemd service and timer (runs daily at 05:00)

### `install-all.sh`
Master script that runs all installation steps in sequence with progress tracking.

### `uninstall.sh`
Complete removal script that:
- Stops and disables all services
- Removes systemd units
- Removes scripts and configuration files
- Cleans up directories
- Preserves recording queue data

## Configuration Reference

### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `B3LB_BACKEND_URL` | B3LB backend API URL | `https://b3lb-api.example.com` |

### Optional Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `MEETING_TIMEOUT_HOURS` | `12` | Meeting cleanup timeout in hours |
| `B3LB_NONCE_TAG` | `b3lb-nonce` | Metadata tag name for authorization |
| `ENABLE_LOAD` | `true` | Install b3lb-load service |
| `ENABLE_PUSH` | `true` | Install b3lb-push service |
| `ENABLE_CLEANER` | `false` | Install b3lb-cleaner service |
| `PUBLISHED_FOLDER` | `/var/bigbluebutton/published/presentation` | BBB recordings location |
| `QUEUE_DIR` | `/var/bigbluebutton/b3lb` | Queue database directory |
| `QUEUE_FILE` | `queue.db` | Queue database filename |
| `B3LB_LIB_DIR` | `/usr/local/lib/b3lb` | Scripts installation directory |
| `B3LB_CONF_DIR` | `/etc/b3lb` | Configuration directory |
| `B3LB_SCRIPTS_DIR` | `/opt/b3lb/scripts` | Cleaner script directory |

## Usage Examples

### Example 1: Full Installation

Install all services with default settings:

```bash
# Configure
cp config.env.example config.env
nano config.env  # Set B3LB_BACKEND_URL

# Install
sudo ./install-all.sh
```

### Example 2: Load Monitoring Only

Install only the load monitoring service:

```bash
# Configure
cp config.env.example config.env
nano config.env  # Set:
# ENABLE_LOAD=true
# ENABLE_PUSH=false
# ENABLE_CLEANER=false

# Install
sudo ./00-preflight-check.sh
sudo ./01-install-dependencies.sh
sudo ./02-install-b3lb-load.sh
```

### Example 3: Custom Meeting Timeout

Install with 6-hour meeting timeout:

```bash
# Configure
cp config.env.example config.env
nano config.env  # Set:
# B3LB_BACKEND_URL=https://b3lb-api.example.com
# MEETING_TIMEOUT_HOURS=6
# ENABLE_CLEANER=true

# Install
sudo ./install-all.sh
```

## Verification

After installation, verify services are running:

```bash
# Check service status
systemctl status b3lb-load.service
systemctl status b3lb-push.path
systemctl status b3lb-push.timer
systemctl status b3lb-cleaner.timer

# Test load endpoint
curl https://$(hostname -f)/b3lb/load

# Monitor logs
journalctl -u b3lb-load.service -f
journalctl -u b3lb-push.service -f
tail -f /var/log/bigbluebutton/b3lb_push_hook.log
```

## Troubleshooting

### Preflight Check Fails

**Issue**: Configuration file not found
```bash
# Solution
cp config.env.example config.env
nano config.env
```

**Issue**: B3LB_BACKEND_URL not set
```bash
# Solution
nano config.env
# Set: B3LB_BACKEND_URL=https://your-b3lb-backend.example.com
```

### Service Won't Start

**Check service status:**
```bash
systemctl status b3lb-load.service
systemctl status b3lb-push.service
```

**View logs:**
```bash
journalctl -u b3lb-load.service -n 50
journalctl -u b3lb-push.service -n 50
```

**Common issues:**
- Missing dependencies: Re-run `01-install-dependencies.sh`
- Permission issues: Check file ownership in `/var/bigbluebutton/b3lb`
- Configuration errors: Verify `config.env` settings

### Load Endpoint Returns 404

```bash
# Check nginx configuration
nginx -t

# Verify config file exists
ls /etc/bigbluebutton/nginx/b3lb-load.nginx

# Reload nginx
systemctl reload nginx

# Check if load file exists
ls /run/b3lb/load
```

### Recordings Not Uploading

```bash
# Check configuration
cat /etc/b3lb/push.properties

# Test backend connectivity
curl -I https://your-b3lb-backend.example.com

# Check hook log
tail -f /var/log/bigbluebutton/b3lb_push_hook.log

# Check queue
sqlite3 /var/bigbluebutton/b3lb/queue.db "SELECT * FROM backlog;"

# Manually trigger upload
systemctl start b3lb-push.service
journalctl -u b3lb-push.service -n 50
```

## Uninstallation

To completely remove B3LB services:

```bash
cd /path/to/b3lb/scripts/bbb/install
sudo ./uninstall.sh
```

This will:
- Stop and disable all services
- Remove all systemd units
- Remove scripts and configurations
- Clean up directories
- **Preserve** recording queue data in `/var/bigbluebutton/b3lb`

To also remove preserved data:
```bash
sudo rm -rf /var/bigbluebutton/b3lb
sudo rm -f /var/log/bigbluebutton/b3lb_push_hook.log
```

## File Locations

After installation, files will be located at:

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
└── queue.db               # Recording upload queue

/run/b3lb/
└── load                   # Current CPU load value

/var/log/bigbluebutton/
└── b3lb_push_hook.log     # Push hook log
```

## Security Recommendations

1. **Restrict Load Endpoint**: Add nginx ACL to limit access to B3LB backend IPs
2. **Use HTTPS**: Always configure SSL/TLS for B3LB backend communication
3. **Protect API Secrets**: Ensure b3lb-nonce metadata is properly secured
4. **Monitor Logs**: Regularly review logs for unauthorized access attempts
5. **File Permissions**: Verify scripts are not world-writable

## Support

- **B3LB Documentation**: https://docs.b3lb.io/
- **B3LB GitHub**: https://github.com/DE-IBH/b3lb
- **Repository**: https://github.com/ayman-makki/b3lb
- **Issue Tracker**: https://github.com/ayman-makki/b3lb/issues

## License

GNU Affero General Public License v3.0

## Credits

These scripts are part of the B3LB project developed by IBH IT-Service GmbH.
Automated installation scripts created for easier deployment.
