#!/usr/bin/env bash
set -e

# B3LB BBB Node - Uninstall Script
# This script removes all B3LB services and files

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

# Main header
clear
echo -e "${RED}╔════════════════════════════════════════╗${NC}"
echo -e "${RED}║  B3LB BBB Node - Uninstall             ║${NC}"
echo -e "${RED}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}WARNING: This will remove all B3LB services and files.${NC}"
echo ""
echo "The following will be removed:"
echo "  • b3lb-load service (CPU monitoring)"
echo "  • b3lb-push service (recording upload)"
echo "  • b3lb-cleaner service (meeting cleanup)"
echo "  • All configuration files"
echo "  • All systemd units"
echo ""
echo -e "${YELLOW}Recording queue data will be PRESERVED in /var/bigbluebutton/b3lb${NC}"
echo ""
echo -e "${RED}Are you sure you want to continue? [y/N]${NC} "
read -r response

if [[ ! "$response" =~ ^[Yy]$ ]]; then
    echo "Uninstall cancelled."
    exit 0
fi

echo ""
echo -e "${YELLOW}Last chance! Type 'yes' to confirm uninstall:${NC} "
read -r confirm

if [[ "$confirm" != "yes" ]]; then
    echo "Uninstall cancelled."
    exit 0
fi

# Track progress
ITEMS_REMOVED=0

# Step 1: Stop and disable services
print_header "Stopping Services"

for service in b3lb-load.service b3lb-push.service b3lb-push.path b3lb-push.timer b3lb-cleaner.service b3lb-cleaner.timer; do
    print_step "Stopping $service..."
    if systemctl is-active --quiet $service 2>/dev/null; then
        systemctl stop $service && print_success "Stopped" || print_warning "Failed to stop"
    else
        print_warning "Not running"
    fi

    print_step "Disabling $service..."
    if systemctl is-enabled --quiet $service 2>/dev/null; then
        systemctl disable $service && print_success "Disabled" || print_warning "Failed to disable"
    else
        print_warning "Not enabled"
    fi
done

# Step 2: Remove systemd units
print_header "Removing Systemd Units"

for unit in b3lb-load.service b3lb-push.service b3lb-push.path b3lb-push.timer b3lb-cleaner.service b3lb-cleaner.timer; do
    print_step "Removing $unit..."
    if [ -f "/etc/systemd/system/$unit" ]; then
        rm -f "/etc/systemd/system/$unit"
        print_success "Removed"
        ((ITEMS_REMOVED++)) || true
    else
        print_warning "Not found"
    fi
done

print_step "Reloading systemd daemon..."
systemctl daemon-reload
print_success "Systemd daemon reloaded"

# Step 3: Remove scripts
print_header "Removing Scripts"

print_step "Removing b3lb-load script..."
if [ -f /usr/local/lib/b3lb/b3lb-load ]; then
    rm -f /usr/local/lib/b3lb/b3lb-load
    print_success "Removed"
    ((ITEMS_REMOVED++)) || true
else
    print_warning "Not found"
fi

print_step "Removing b3lb-push script..."
if [ -f /usr/local/lib/b3lb/b3lb-push ]; then
    rm -f /usr/local/lib/b3lb/b3lb-push
    print_success "Removed"
    ((ITEMS_REMOVED++)) || true
else
    print_warning "Not found"
fi

print_step "Removing b3lb-push-hook.rb..."
if [ -f /usr/local/bigbluebutton/core/scripts/post_publish/b3lb-push-hook.rb ]; then
    rm -f /usr/local/bigbluebutton/core/scripts/post_publish/b3lb-push-hook.rb
    print_success "Removed"
    ((ITEMS_REMOVED++)) || true
else
    print_warning "Not found"
fi

print_step "Removing cleaner.py..."
if [ -f /opt/b3lb/scripts/cleaner.py ]; then
    rm -f /opt/b3lb/scripts/cleaner.py
    print_success "Removed"
    ((ITEMS_REMOVED++)) || true
else
    print_warning "Not found"
fi

# Step 4: Remove nginx configuration
print_header "Removing Nginx Configuration"

print_step "Removing b3lb-load.nginx..."
if [ -f /etc/bigbluebutton/nginx/b3lb-load.nginx ]; then
    rm -f /etc/bigbluebutton/nginx/b3lb-load.nginx
    print_success "Removed"
    ((ITEMS_REMOVED++)) || true
else
    print_warning "Not found"
fi

print_step "Testing nginx configuration..."
if nginx -t 2>&1 | grep -q "successful"; then
    print_success "Nginx configuration valid"
else
    print_error "Nginx configuration test failed"
fi

print_step "Reloading nginx..."
if systemctl reload nginx; then
    print_success "Nginx reloaded"
else
    print_error "Failed to reload nginx"
fi

# Step 5: Remove configuration files
print_header "Removing Configuration Files"

print_step "Removing push.properties..."
if [ -f /etc/b3lb/push.properties ]; then
    rm -f /etc/b3lb/push.properties
    print_success "Removed"
    ((ITEMS_REMOVED++)) || true
else
    print_warning "Not found"
fi

# Step 6: Remove empty directories
print_header "Removing Directories"

print_step "Removing /usr/local/lib/b3lb..."
if [ -d /usr/local/lib/b3lb ]; then
    if [ -z "$(ls -A /usr/local/lib/b3lb)" ]; then
        rmdir /usr/local/lib/b3lb
        print_success "Removed (empty)"
        ((ITEMS_REMOVED++)) || true
    else
        print_warning "Directory not empty, preserved"
    fi
else
    print_warning "Not found"
fi

print_step "Removing /etc/b3lb..."
if [ -d /etc/b3lb ]; then
    if [ -z "$(ls -A /etc/b3lb)" ]; then
        rmdir /etc/b3lb
        print_success "Removed (empty)"
        ((ITEMS_REMOVED++)) || true
    else
        print_warning "Directory not empty, preserved"
    fi
else
    print_warning "Not found"
fi

print_step "Removing /opt/b3lb/scripts..."
if [ -d /opt/b3lb/scripts ]; then
    if [ -z "$(ls -A /opt/b3lb/scripts)" ]; then
        rmdir /opt/b3lb/scripts
        print_success "Removed (empty)"
        ((ITEMS_REMOVED++)) || true
    else
        print_warning "Directory not empty, preserved"
    fi
else
    print_warning "Not found"
fi

print_step "Removing /opt/b3lb..."
if [ -d /opt/b3lb ]; then
    if [ -z "$(ls -A /opt/b3lb)" ]; then
        rmdir /opt/b3lb
        print_success "Removed (empty)"
        ((ITEMS_REMOVED++)) || true
    else
        print_warning "Directory not empty, preserved"
    fi
else
    print_warning "Not found"
fi

print_step "Removing /run/b3lb..."
if [ -d /run/b3lb ]; then
    rm -rf /run/b3lb
    print_success "Removed"
    ((ITEMS_REMOVED++)) || true
else
    print_warning "Not found"
fi

# Step 7: Preserved data
print_header "Preserved Data"

echo -e "${BLUE}The following data has been preserved:${NC}"
if [ -d /var/bigbluebutton/b3lb ]; then
    echo -e "  ${GREEN}✓${NC} Recording queue: /var/bigbluebutton/b3lb"
    if [ -f /var/bigbluebutton/b3lb/queue.db ]; then
        QUEUE_SIZE=$(du -h /var/bigbluebutton/b3lb/queue.db | cut -f1)
        echo -e "    Queue database: $QUEUE_SIZE"
    fi
else
    echo -e "  ${YELLOW}○${NC} No queue data found"
fi

if [ -f /var/log/bigbluebutton/b3lb_push_hook.log ]; then
    LOG_SIZE=$(du -h /var/log/bigbluebutton/b3lb_push_hook.log | cut -f1)
    echo -e "  ${GREEN}✓${NC} Hook log: /var/log/bigbluebutton/b3lb_push_hook.log ($LOG_SIZE)"
else
    echo -e "  ${YELLOW}○${NC} No hook log found"
fi

echo ""
echo -e "${YELLOW}To remove preserved data:${NC}"
echo -e "  ${RED}rm -rf /var/bigbluebutton/b3lb${NC}"
echo -e "  ${RED}rm -f /var/log/bigbluebutton/b3lb_push_hook.log${NC}"

# Summary
print_header "Uninstall Summary"
echo -e "${GREEN}✓ B3LB services removed successfully${NC}"
echo -e "${BLUE}Items removed:${NC} $ITEMS_REMOVED"
echo ""
echo -e "${BLUE}Verification:${NC}"
for service in b3lb-load.service b3lb-push.path b3lb-push.timer b3lb-cleaner.timer; do
    if systemctl list-unit-files | grep -q $service 2>/dev/null; then
        echo -e "  ${RED}✗${NC} $service still present"
    else
        echo -e "  ${GREEN}✓${NC} $service removed"
    fi
done

echo ""
echo -e "${GREEN}Uninstall complete!${NC}"
echo ""

exit 0
