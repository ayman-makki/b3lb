#!/usr/bin/env bash
set -e

# B3LB BBB Node Installation - Install b3lb-cleaner Service
# This script installs the meeting cleanup service

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.env"
CLEANER_SOURCE_DIR="${SCRIPT_DIR}/../cleaner"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print functions
print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

print_step() {
    echo -e "${BLUE}▶${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Check root
if [[ $EUID -ne 0 ]]; then
    print_error "This script must be run as root or with sudo"
    exit 1
fi

# Load configuration
if [ ! -f "$CONFIG_FILE" ]; then
    print_error "Configuration file not found: $CONFIG_FILE"
    exit 1
fi

source "$CONFIG_FILE"

# Check if service is enabled
if [ "$ENABLE_CLEANER" != "true" ]; then
    print_warning "b3lb-cleaner is disabled in config.env (ENABLE_CLEANER=$ENABLE_CLEANER)"
    echo "Skipping installation."
    exit 0
fi

# Main header
clear
echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  B3LB BBB Node - Install b3lb-cleaner  ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

# Verify source files exist
if [ ! -d "$CLEANER_SOURCE_DIR" ]; then
    print_error "Source directory not found: $CLEANER_SOURCE_DIR"
    exit 1
fi

# Step 1: Create directories
print_header "Creating Directories"
print_step "Creating $B3LB_SCRIPTS_DIR..."
mkdir -p "$B3LB_SCRIPTS_DIR"
print_success "Directory created"

# Step 2: Copy and configure cleanup script
print_header "Installing Cleanup Script"
print_step "Copying cleaner.py to $B3LB_SCRIPTS_DIR..."
if [ -f "$CLEANER_SOURCE_DIR/cleaner.py" ]; then
    # Backup existing script if it exists
    if [ -f "$B3LB_SCRIPTS_DIR/cleaner.py" ]; then
        cp "$B3LB_SCRIPTS_DIR/cleaner.py" "$B3LB_SCRIPTS_DIR/cleaner.py.bak"
        print_warning "Existing script backed up to cleaner.py.bak"
    fi

    cp "$CLEANER_SOURCE_DIR/cleaner.py" "$B3LB_SCRIPTS_DIR/"
    chmod +x "$B3LB_SCRIPTS_DIR/cleaner.py"
    print_success "Script installed"
else
    print_error "Source file not found: $CLEANER_SOURCE_DIR/cleaner.py"
    exit 1
fi

# Update timeout in script if different from default
print_step "Configuring meeting timeout..."
if [ -n "$MEETING_TIMEOUT_HOURS" ] && [ "$MEETING_TIMEOUT_HOURS" != "12" ]; then
    sed -i "s/MEETING_TIMEOUT = timedelta(hours=12)/MEETING_TIMEOUT = timedelta(hours=$MEETING_TIMEOUT_HOURS)/" \
        "$B3LB_SCRIPTS_DIR/cleaner.py"
    print_success "Timeout set to ${MEETING_TIMEOUT_HOURS} hours"
else
    print_success "Using default timeout (12 hours)"
fi

# Step 3: Install systemd units
print_header "Installing Systemd Units"

# Service file
print_step "Installing b3lb-cleaner.service..."
if [ -f "$CLEANER_SOURCE_DIR/b3lb-cleaner.service" ]; then
    if [ -f /etc/systemd/system/b3lb-cleaner.service ]; then
        cp /etc/systemd/system/b3lb-cleaner.service /etc/systemd/system/b3lb-cleaner.service.bak
        print_warning "Existing service backed up"
    fi
    cp "$CLEANER_SOURCE_DIR/b3lb-cleaner.service" /etc/systemd/system/
    print_success "Service file installed"
else
    print_error "Source file not found: $CLEANER_SOURCE_DIR/b3lb-cleaner.service"
    exit 1
fi

# Timer
print_step "Installing b3lb-cleaner.timer..."
if [ -f "$CLEANER_SOURCE_DIR/b3lb-cleaner.timer" ]; then
    if [ -f /etc/systemd/system/b3lb-cleaner.timer ]; then
        cp /etc/systemd/system/b3lb-cleaner.timer /etc/systemd/system/b3lb-cleaner.timer.bak
        print_warning "Existing timer backed up"
    fi
    cp "$CLEANER_SOURCE_DIR/b3lb-cleaner.timer" /etc/systemd/system/
    print_success "Timer installed"
else
    print_error "Source file not found: $CLEANER_SOURCE_DIR/b3lb-cleaner.timer"
    exit 1
fi

print_step "Reloading systemd daemon..."
systemctl daemon-reload
print_success "Systemd daemon reloaded"

# Step 4: Enable and start timer
print_header "Starting Timer"

print_step "Enabling b3lb-cleaner.timer..."
if systemctl enable b3lb-cleaner.timer; then
    print_success "Timer enabled"
else
    print_error "Failed to enable timer"
    exit 1
fi

print_step "Starting b3lb-cleaner.timer..."
if systemctl start b3lb-cleaner.timer; then
    print_success "Timer started"
else
    print_error "Failed to start timer"
    exit 1
fi

# Step 5: Verify installation
print_header "Verifying Installation"

print_step "Checking timer status..."
if systemctl is-active --quiet b3lb-cleaner.timer; then
    print_success "Timer is active"
else
    print_error "Timer is not active"
    systemctl status b3lb-cleaner.timer --no-pager
    exit 1
fi

print_step "Verifying BBB API access..."
if command -v bbb-conf &> /dev/null; then
    if bbb-conf --secret &> /dev/null; then
        print_success "BBB API credentials accessible"
    else
        print_warning "Cannot retrieve BBB API credentials"
    fi
else
    print_warning "bbb-conf not found"
fi

# Summary
print_header "Installation Summary"
echo -e "${GREEN}✓ b3lb-cleaner service installed successfully${NC}"
echo ""
echo -e "${BLUE}Configuration:${NC}"
echo -e "  Meeting Timeout: ${MEETING_TIMEOUT_HOURS} hours"
echo -e "  Script Location: $B3LB_SCRIPTS_DIR/cleaner.py"
echo ""
echo -e "${BLUE}Timer Status:${NC}"
systemctl status b3lb-cleaner.timer --no-pager | head -n 3
echo ""
echo -e "${BLUE}Timer Schedule:${NC}"
systemctl list-timers b3lb-cleaner.timer --no-pager | grep b3lb-cleaner || echo "  Daily at 05:00"
echo ""
echo -e "${BLUE}Useful Commands:${NC}"
echo -e "  • Check timer:    ${GREEN}systemctl status b3lb-cleaner.timer${NC}"
echo -e "  • View schedule:  ${GREEN}systemctl list-timers b3lb-cleaner.timer${NC}"
echo -e "  • View logs:      ${GREEN}journalctl -u b3lb-cleaner.service -n 50${NC}"
echo -e "  • Manual run:     ${GREEN}systemctl start b3lb-cleaner.service${NC}"
echo -e "  • Test script:    ${GREEN}sudo $B3LB_SCRIPTS_DIR/cleaner.py${NC}"
echo ""
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  All B3LB services installed!          ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""

exit 0
