#!/bin/bash

###############################################################################
# Hetzner Storage Box Mount Script for B3LB
#
# This script mounts a Hetzner Storage Box via CIFS for storing B3LB recordings.
#
# Requirements:
# - cifs-utils package installed
# - Hetzner Storage Box credentials
# - Root privileges
#
# Usage:
#   sudo ./mount-storagebox.sh
#
# The script will:
# 1. Install required packages
# 2. Create mount point
# 3. Store credentials securely
# 4. Configure systemd auto-mount
# 5. Mount the Storage Box
###############################################################################

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root (use sudo)"
   exit 1
fi

###############################################################################
# Configuration
###############################################################################

# Load environment variables from .env file if it exists
if [ -f "../../.env" ]; then
    log_info "Loading configuration from .env file..."
    export $(grep -v '^#' ../../.env | xargs)
elif [ -f ".env" ]; then
    export $(grep -v '^#' .env | xargs)
fi

# Prompt for Storage Box details if not in environment
if [ -z "${STORAGEBOX_HOST:-}" ]; then
    read -p "Enter Storage Box hostname (e.g., u123456.your-storagebox.de): " STORAGEBOX_HOST
fi

if [ -z "${STORAGEBOX_USERNAME:-}" ]; then
    read -p "Enter Storage Box username (e.g., u123456): " STORAGEBOX_USERNAME
fi

if [ -z "${STORAGEBOX_PASSWORD:-}" ]; then
    read -sp "Enter Storage Box password: " STORAGEBOX_PASSWORD
    echo
fi

if [ -z "${STORAGEBOX_MOUNT_POINT:-}" ]; then
    STORAGEBOX_MOUNT_POINT="/mnt/b3lb-recordings"
fi

if [ -z "${STORAGEBOX_SUBDIRECTORY:-}" ]; then
    STORAGEBOX_SUBDIRECTORY="/b3lb"
fi

# Credentials file location
CREDENTIALS_FILE="/root/.storagebox-credentials"

###############################################################################
# Install Required Packages
###############################################################################

log_info "Installing required packages..."

if command -v apt-get &> /dev/null; then
    apt-get update -qq
    apt-get install -y -qq cifs-utils
elif command -v yum &> /dev/null; then
    yum install -y -q cifs-utils
elif command -v dnf &> /dev/null; then
    dnf install -y -q cifs-utils
else
    log_error "Could not detect package manager. Please install cifs-utils manually."
    exit 1
fi

log_success "Required packages installed"

###############################################################################
# Create Mount Point
###############################################################################

log_info "Creating mount point at ${STORAGEBOX_MOUNT_POINT}..."

if [ ! -d "${STORAGEBOX_MOUNT_POINT}" ]; then
    mkdir -p "${STORAGEBOX_MOUNT_POINT}"
    log_success "Mount point created"
else
    log_info "Mount point already exists"
fi

###############################################################################
# Store Credentials Securely
###############################################################################

log_info "Storing credentials in ${CREDENTIALS_FILE}..."

cat > "${CREDENTIALS_FILE}" <<EOF
username=${STORAGEBOX_USERNAME}
password=${STORAGEBOX_PASSWORD}
EOF

# Secure the credentials file
chmod 600 "${CREDENTIALS_FILE}"
log_success "Credentials stored securely"

###############################################################################
# Test Connection
###############################################################################

log_info "Testing Storage Box connectivity..."

if ping -c 1 -W 3 "${STORAGEBOX_HOST}" &> /dev/null; then
    log_success "Storage Box is reachable"
else
    log_warning "Cannot ping Storage Box (ICMP might be blocked, continuing anyway)"
fi

###############################################################################
# Configure /etc/fstab for Auto-Mount
###############################################################################

log_info "Configuring /etc/fstab for automatic mounting..."

FSTAB_ENTRY="//${STORAGEBOX_HOST}${STORAGEBOX_SUBDIRECTORY} ${STORAGEBOX_MOUNT_POINT} cifs credentials=${CREDENTIALS_FILE},iocharset=utf8,rw,uid=0,gid=0,file_mode=0660,dir_mode=0770,_netdev,nofail 0 0"

# Check if entry already exists
if grep -q "${STORAGEBOX_MOUNT_POINT}" /etc/fstab; then
    log_warning "Entry already exists in /etc/fstab, updating..."
    # Remove old entry
    sed -i "\|${STORAGEBOX_MOUNT_POINT}|d" /etc/fstab
fi

# Add new entry
echo "${FSTAB_ENTRY}" >> /etc/fstab
log_success "/etc/fstab configured"

###############################################################################
# Create Systemd Mount Unit (alternative to fstab)
###############################################################################

log_info "Creating systemd mount unit..."

# Convert mount point to systemd unit name
# /mnt/b3lb-recordings -> mnt-b3lb\x2drecordings.mount
UNIT_NAME=$(systemd-escape -p --suffix=mount "${STORAGEBOX_MOUNT_POINT}")

cat > "/etc/systemd/system/${UNIT_NAME}" <<EOF
[Unit]
Description=Mount Hetzner Storage Box for B3LB Recordings
After=network-online.target
Wants=network-online.target

[Mount]
What=//${STORAGEBOX_HOST}${STORAGEBOX_SUBDIRECTORY}
Where=${STORAGEBOX_MOUNT_POINT}
Type=cifs
Options=credentials=${CREDENTIALS_FILE},iocharset=utf8,rw,uid=0,gid=0,file_mode=0660,dir_mode=0770,_netdev,nofail

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd
systemctl daemon-reload
log_success "Systemd mount unit created"

###############################################################################
# Mount the Storage Box
###############################################################################

log_info "Mounting Storage Box..."

# Try mounting via systemd
if systemctl start "${UNIT_NAME}"; then
    log_success "Storage Box mounted successfully via systemd"
else
    log_warning "Systemd mount failed, trying manual mount..."
    # Try manual mount
    if mount "${STORAGEBOX_MOUNT_POINT}"; then
        log_success "Storage Box mounted successfully via manual mount"
    else
        log_error "Failed to mount Storage Box"
        log_error "Please check your credentials and network connectivity"
        exit 1
    fi
fi

# Enable auto-mount on boot
systemctl enable "${UNIT_NAME}"
log_success "Auto-mount on boot enabled"

###############################################################################
# Verify Mount
###############################################################################

log_info "Verifying mount..."

if mountpoint -q "${STORAGEBOX_MOUNT_POINT}"; then
    log_success "Storage Box is mounted at ${STORAGEBOX_MOUNT_POINT}"

    # Show mount info
    log_info "Mount information:"
    df -h "${STORAGEBOX_MOUNT_POINT}"

    # Test write permissions
    log_info "Testing write permissions..."
    TEST_FILE="${STORAGEBOX_MOUNT_POINT}/.test-write-$(date +%s)"
    if echo "test" > "${TEST_FILE}" 2>/dev/null; then
        rm -f "${TEST_FILE}"
        log_success "Write test successful"
    else
        log_error "Cannot write to Storage Box"
        log_error "Please check permissions"
        exit 1
    fi
else
    log_error "Storage Box is not mounted"
    exit 1
fi

###############################################################################
# Create Required Subdirectories
###############################################################################

log_info "Creating required subdirectories..."

mkdir -p "${STORAGEBOX_MOUNT_POINT}/recordings"
mkdir -p "${STORAGEBOX_MOUNT_POINT}/backups"
mkdir -p "${STORAGEBOX_MOUNT_POINT}/tmp"

log_success "Subdirectories created"

###############################################################################
# Summary
###############################################################################

echo
log_success "======================================================================"
log_success "Storage Box mounted successfully!"
log_success "======================================================================"
echo
log_info "Mount point: ${STORAGEBOX_MOUNT_POINT}"
log_info "Storage Box: //${STORAGEBOX_HOST}${STORAGEBOX_SUBDIRECTORY}"
log_info "Credentials: ${CREDENTIALS_FILE}"
log_info "Systemd unit: ${UNIT_NAME}"
echo
log_info "The Storage Box will auto-mount on boot."
log_info "To unmount: systemctl stop ${UNIT_NAME}"
log_info "To check status: systemctl status ${UNIT_NAME}"
echo
log_success "You can now start deploying B3LB!"
echo
