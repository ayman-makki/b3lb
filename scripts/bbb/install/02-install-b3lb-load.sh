#!/usr/bin/env bash
set -e

# B3LB BBB Node Installation - Install b3lb-load Service
# This script installs the CPU load monitoring service

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.env"
LOAD_SOURCE_DIR="${SCRIPT_DIR}/../load"

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
if [ "$ENABLE_LOAD" != "true" ]; then
    print_warning "b3lb-load is disabled in config.env (ENABLE_LOAD=$ENABLE_LOAD)"
    echo "Skipping installation."
    exit 0
fi

# Main header
clear
echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  B3LB BBB Node - Install b3lb-load     ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

# Verify source files exist
if [ ! -d "$LOAD_SOURCE_DIR" ]; then
    print_error "Source directory not found: $LOAD_SOURCE_DIR"
    exit 1
fi

# Step 1: Create directories
print_header "Creating Directories"
print_step "Creating $B3LB_LIB_DIR..."
mkdir -p "$B3LB_LIB_DIR"
print_success "Directory created"

print_step "Creating /run/b3lb..."
mkdir -p /run/b3lb
print_success "Directory created"

# Step 2: Copy monitoring script
print_header "Installing Monitoring Script"
print_step "Copying b3lb-load to $B3LB_LIB_DIR..."
if [ -f "$LOAD_SOURCE_DIR/b3lb-load" ]; then
    cp "$LOAD_SOURCE_DIR/b3lb-load" "$B3LB_LIB_DIR/"
    chmod +x "$B3LB_LIB_DIR/b3lb-load"
    print_success "Script installed"
else
    print_error "Source file not found: $LOAD_SOURCE_DIR/b3lb-load"
    exit 1
fi

# Step 3: Configure nginx
print_header "Configuring Nginx"
print_step "Copying nginx configuration..."
if [ -f "$LOAD_SOURCE_DIR/b3lb-load.nginx" ]; then
    # Backup existing config if it exists
    if [ -f /etc/bigbluebutton/nginx/b3lb-load.nginx ]; then
        cp /etc/bigbluebutton/nginx/b3lb-load.nginx /etc/bigbluebutton/nginx/b3lb-load.nginx.bak
        print_warning "Existing config backed up to b3lb-load.nginx.bak"
    fi

    cp "$LOAD_SOURCE_DIR/b3lb-load.nginx" /etc/bigbluebutton/nginx/
    print_success "Nginx configuration installed"
else
    print_error "Source file not found: $LOAD_SOURCE_DIR/b3lb-load.nginx"
    exit 1
fi

print_step "Testing nginx configuration..."
if nginx -t 2>&1 | grep -q "successful"; then
    print_success "Nginx configuration valid"
else
    print_error "Nginx configuration test failed"
    exit 1
fi

print_step "Reloading nginx..."
if systemctl reload nginx; then
    print_success "Nginx reloaded"
else
    print_error "Failed to reload nginx"
    exit 1
fi

# Step 4: Install systemd service
print_header "Installing Systemd Service"
print_step "Copying b3lb-load.service..."
if [ -f "$LOAD_SOURCE_DIR/b3lb-load.service" ]; then
    # Backup existing service if it exists
    if [ -f /etc/systemd/system/b3lb-load.service ]; then
        cp /etc/systemd/system/b3lb-load.service /etc/systemd/system/b3lb-load.service.bak
        print_warning "Existing service backed up to b3lb-load.service.bak"
    fi

    cp "$LOAD_SOURCE_DIR/b3lb-load.service" /etc/systemd/system/
    print_success "Service file installed"
else
    print_error "Source file not found: $LOAD_SOURCE_DIR/b3lb-load.service"
    exit 1
fi

print_step "Reloading systemd daemon..."
systemctl daemon-reload
print_success "Systemd daemon reloaded"

# Step 5: Enable and start service
print_header "Starting Service"
print_step "Enabling b3lb-load.service..."
if systemctl enable b3lb-load.service; then
    print_success "Service enabled"
else
    print_error "Failed to enable service"
    exit 1
fi

print_step "Starting b3lb-load.service..."
if systemctl start b3lb-load.service; then
    print_success "Service started"
else
    print_error "Failed to start service"
    systemctl status b3lb-load.service --no-pager
    exit 1
fi

# Step 6: Verify installation
print_header "Verifying Installation"
print_step "Checking service status..."
sleep 2  # Give service time to start
if systemctl is-active --quiet b3lb-load.service; then
    print_success "Service is running"
else
    print_error "Service is not running"
    systemctl status b3lb-load.service --no-pager
    exit 1
fi

print_step "Checking load file creation..."
if [ -f /run/b3lb/load ]; then
    LOAD_VALUE=$(cat /run/b3lb/load)
    print_success "Load file created (value: $LOAD_VALUE)"
else
    print_error "Load file not created"
    exit 1
fi

print_step "Testing HTTP endpoint..."
sleep 1  # Give nginx a moment
HOSTNAME=$(hostname -f)
if curl -s "https://$HOSTNAME/b3lb/load" > /dev/null 2>&1; then
    ENDPOINT_VALUE=$(curl -s "https://$HOSTNAME/b3lb/load")
    print_success "HTTP endpoint accessible (value: $ENDPOINT_VALUE)"
else
    print_warning "HTTP endpoint test failed (may be normal if SSL not configured)"
    echo "    Try: curl http://localhost/b3lb/load"
fi

# Summary
print_header "Installation Summary"
echo -e "${GREEN}✓ b3lb-load service installed successfully${NC}"
echo ""
echo -e "${BLUE}Service Status:${NC}"
systemctl status b3lb-load.service --no-pager | head -n 5
echo ""
echo -e "${BLUE}Current Load Value:${NC}"
echo -e "  File: $(cat /run/b3lb/load 2>/dev/null || echo 'N/A')"
echo ""
echo -e "${BLUE}Useful Commands:${NC}"
echo -e "  • Check status:  ${GREEN}systemctl status b3lb-load.service${NC}"
echo -e "  • View logs:     ${GREEN}journalctl -u b3lb-load.service -f${NC}"
echo -e "  • Test endpoint: ${GREEN}curl https://$HOSTNAME/b3lb/load${NC}"
echo ""
echo -e "${BLUE}Next step:${NC}"
echo -e "  Run: ${GREEN}sudo ./03-install-b3lb-push.sh${NC}"
echo ""

exit 0
