#!/usr/bin/env bash
set -e

# B3LB BBB Node Installation - Master Install Script
# This script runs all installation steps in sequence

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print functions
print_header() {
    echo -e "\n${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  $1${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}\n"
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
echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  B3LB BBB Node - Complete Installation ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""
echo "This script will install all B3LB services in sequence:"
echo "  1. Preflight checks"
echo "  2. Install dependencies"
echo "  3. Install b3lb-load (CPU monitoring)"
echo "  4. Install b3lb-push (recording upload)"
echo "  5. Install b3lb-cleaner (meeting cleanup)"
echo ""
echo -e "${YELLOW}Press Ctrl+C to cancel, or Enter to continue...${NC}"
read

# Track installation progress
STEPS_COMPLETED=0
STEPS_TOTAL=5
START_TIME=$(date +%s)

# Function to run a script and track progress
run_script() {
    local script_name=$1
    local script_path="${SCRIPT_DIR}/${script_name}"

    print_header "Running ${script_name}"

    if [ ! -f "$script_path" ]; then
        print_error "Script not found: $script_path"
        return 1
    fi

    if bash "$script_path"; then
        ((STEPS_COMPLETED++))
        print_success "Step $STEPS_COMPLETED/$STEPS_TOTAL completed"
        return 0
    else
        print_error "Script failed: $script_name"
        return 1
    fi
}

# Step 1: Preflight checks
if ! run_script "00-preflight-check.sh"; then
    print_error "Preflight checks failed. Please fix the issues and try again."
    exit 1
fi

echo ""
echo -e "${BLUE}Press Enter to continue with installation...${NC}"
read

# Step 2: Install dependencies
if ! run_script "01-install-dependencies.sh"; then
    print_error "Dependency installation failed."
    exit 1
fi

# Step 3: Install b3lb-load
if ! run_script "02-install-b3lb-load.sh"; then
    print_error "b3lb-load installation failed."
    exit 1
fi

# Step 4: Install b3lb-push
if ! run_script "03-install-b3lb-push.sh"; then
    print_error "b3lb-push installation failed."
    exit 1
fi

# Step 5: Install b3lb-cleaner
if ! run_script "04-install-b3lb-cleaner.sh"; then
    # Cleaner failure is not critical if disabled
    print_warning "b3lb-cleaner installation skipped or failed (may be disabled in config)"
fi

# Calculate installation time
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
MINUTES=$((DURATION / 60))
SECONDS=$((DURATION % 60))

# Final summary
clear
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Installation Complete!                 ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Installation Time:${NC} ${MINUTES}m ${SECONDS}s"
echo -e "${BLUE}Steps Completed:${NC} $STEPS_COMPLETED/$STEPS_TOTAL"
echo ""

# Show installed services
print_header "Installed Services"

echo -e "${BLUE}Service Status:${NC}"
for service in b3lb-load.service b3lb-push.path b3lb-push.timer b3lb-cleaner.timer; do
    if systemctl is-active --quiet $service 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} $service - ${GREEN}active${NC}"
    elif systemctl list-unit-files | grep -q $service 2>/dev/null; then
        echo -e "  ${YELLOW}○${NC} $service - ${YELLOW}inactive${NC}"
    else
        echo -e "  ${RED}✗${NC} $service - ${RED}not installed${NC}"
    fi
done

echo ""
print_header "Verification Commands"
echo -e "${BLUE}Test b3lb-load endpoint:${NC}"
echo -e "  curl https://\$(hostname -f)/b3lb/load"
echo ""
echo -e "${BLUE}Monitor recording uploads:${NC}"
echo -e "  tail -f /var/log/bigbluebutton/b3lb_push_hook.log"
echo -e "  journalctl -u b3lb-push.service -f"
echo ""
echo -e "${BLUE}Check cleaner schedule:${NC}"
echo -e "  systemctl list-timers b3lb-cleaner.timer"
echo ""
echo -e "${BLUE}View all service status:${NC}"
echo -e "  systemctl status b3lb-*.service b3lb-*.path b3lb-*.timer"
echo ""

print_header "Next Steps"
echo "1. Verify the load endpoint is accessible from B3LB backend"
echo "2. Test recording upload by publishing a test recording"
echo "3. Monitor logs for any issues"
echo "4. Add this BBB node to your B3LB cluster configuration"
echo ""
echo -e "${GREEN}Thank you for installing B3LB!${NC}"
echo ""

exit 0
