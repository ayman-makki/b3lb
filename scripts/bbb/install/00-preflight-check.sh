#!/usr/bin/env bash
set -e

# B3LB BBB Node Installation - Preflight Check
# This script verifies all prerequisites before installation

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.env"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARNING=0

# Print functions
print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

print_check() {
    echo -n "  Checking $1... "
}

print_pass() {
    echo -e "${GREEN}✓ PASS${NC}"
    ((CHECKS_PASSED++))
}

print_fail() {
    echo -e "${RED}✗ FAIL${NC}"
    if [ -n "$1" ]; then
        echo -e "    ${RED}→ $1${NC}"
    fi
    ((CHECKS_FAILED++))
}

print_warning() {
    echo -e "${YELLOW}⚠ WARNING${NC}"
    if [ -n "$1" ]; then
        echo -e "    ${YELLOW}→ $1${NC}"
    fi
    ((CHECKS_WARNING++))
}

print_info() {
    echo -e "    ${BLUE}→ $1${NC}"
}

# Main header
clear
echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  B3LB BBB Node - Preflight Check      ║${NC}"
echo -e "${BLUE}╔════════════════════════════════════════╝${NC}"
echo ""

# Check 1: Root privileges
print_header "System Privileges"
print_check "root/sudo privileges"
if [[ $EUID -ne 0 ]]; then
    print_fail "This script must be run as root or with sudo"
    exit 1
else
    print_pass
fi

# Check 2: Operating System
print_header "Operating System"
print_check "OS distribution"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [[ "$ID" == "ubuntu" ]]; then
        print_pass
        print_info "Detected: Ubuntu $VERSION_ID"
        if [[ "$VERSION_ID" != "20.04" && "$VERSION_ID" != "22.04" ]]; then
            print_warning "Ubuntu $VERSION_ID detected. Recommended: 20.04 or 22.04"
        fi
    else
        print_warning "Non-Ubuntu OS detected: $ID $VERSION_ID"
    fi
else
    print_fail "Cannot determine OS distribution"
fi

# Check 3: BigBlueButton Installation
print_header "BigBlueButton Installation"
print_check "bbb-conf command"
if command -v bbb-conf &> /dev/null; then
    print_pass
    BBB_VERSION=$(bbb-conf --version 2>/dev/null | grep -oP 'BigBlueButton Server \K[0-9.]+' || echo "unknown")
    print_info "BBB Version: $BBB_VERSION"
else
    print_fail "bbb-conf not found. Is BigBlueButton installed?"
fi

print_check "BBB status"
if command -v bbb-conf &> /dev/null; then
    if bbb-conf --check &> /dev/null; then
        print_pass
    else
        print_warning "BBB health check reported issues. Run: bbb-conf --check"
    fi
else
    print_fail "Cannot check BBB status without bbb-conf"
fi

# Check 4: Required Commands
print_header "Required System Commands"
for cmd in systemctl nginx python3 ruby tar curl; do
    print_check "$cmd"
    if command -v $cmd &> /dev/null; then
        print_pass
        if [ "$cmd" == "python3" ]; then
            print_info "Python version: $(python3 --version | cut -d' ' -f2)"
        elif [ "$cmd" == "ruby" ]; then
            print_info "Ruby version: $(ruby --version | cut -d' ' -f2)"
        fi
    else
        print_fail "$cmd is required but not installed"
    fi
done

# Check 5: Configuration File
print_header "Configuration File"
print_check "config.env exists"
if [ -f "$CONFIG_FILE" ]; then
    print_pass
    source "$CONFIG_FILE"

    print_check "B3LB_BACKEND_URL configured"
    if [ -n "$B3LB_BACKEND_URL" ]; then
        print_pass
        print_info "Backend URL: $B3LB_BACKEND_URL"
    else
        print_fail "B3LB_BACKEND_URL is not set in config.env"
    fi

    print_check "Service enablement settings"
    print_info "ENABLE_LOAD=$ENABLE_LOAD"
    print_info "ENABLE_PUSH=$ENABLE_PUSH"
    print_info "ENABLE_CLEANER=$ENABLE_CLEANER"
    print_pass
else
    print_fail "config.env not found. Copy config.env.example to config.env"
    echo -e "\n${YELLOW}To create config.env:${NC}"
    echo -e "  ${BLUE}cp ${SCRIPT_DIR}/config.env.example ${SCRIPT_DIR}/config.env${NC}"
    echo -e "  ${BLUE}nano ${SCRIPT_DIR}/config.env${NC}"
fi

# Check 6: Network Connectivity
print_header "Network Connectivity"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
    if [ -n "$B3LB_BACKEND_URL" ]; then
        print_check "B3LB backend reachability"
        if curl -s --head --connect-timeout 5 "$B3LB_BACKEND_URL" &> /dev/null; then
            print_pass
        else
            print_warning "Cannot reach B3LB backend. Check URL and network connectivity"
        fi
    fi
fi

print_check "Internet connectivity"
if curl -s --head --connect-timeout 5 https://www.google.com &> /dev/null; then
    print_pass
else
    print_warning "No internet connectivity. Package installation may fail"
fi

# Check 7: Disk Space
print_header "System Resources"
print_check "disk space in /var"
AVAILABLE_SPACE=$(df -BG /var | tail -1 | awk '{print $4}' | sed 's/G//')
if [ "$AVAILABLE_SPACE" -gt 10 ]; then
    print_pass
    print_info "Available: ${AVAILABLE_SPACE}GB"
else
    print_warning "Low disk space: ${AVAILABLE_SPACE}GB available in /var"
fi

# Check 8: Existing Installation
print_header "Existing Installation Check"
print_check "b3lb-load service"
if systemctl list-unit-files | grep -q b3lb-load.service; then
    print_warning "b3lb-load.service already exists. Re-installation will overwrite"
else
    print_pass
fi

print_check "b3lb-push service"
if systemctl list-unit-files | grep -q b3lb-push.service; then
    print_warning "b3lb-push.service already exists. Re-installation will overwrite"
else
    print_pass
fi

print_check "b3lb-cleaner service"
if systemctl list-unit-files | grep -q b3lb-cleaner.timer; then
    print_warning "b3lb-cleaner.timer already exists. Re-installation will overwrite"
else
    print_pass
fi

# Summary
print_header "Preflight Check Summary"
echo -e "  ${GREEN}Passed:  $CHECKS_PASSED${NC}"
echo -e "  ${YELLOW}Warnings: $CHECKS_WARNING${NC}"
echo -e "  ${RED}Failed:  $CHECKS_FAILED${NC}"
echo ""

if [ $CHECKS_FAILED -gt 0 ]; then
    echo -e "${RED}╔════════════════════════════════════════╗${NC}"
    echo -e "${RED}║  Preflight check FAILED                ║${NC}"
    echo -e "${RED}║  Please fix the errors above           ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════╝${NC}"
    exit 1
elif [ $CHECKS_WARNING -gt 0 ]; then
    echo -e "${YELLOW}╔════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║  Preflight check passed with warnings ║${NC}"
    echo -e "${YELLOW}║  Review warnings before proceeding     ║${NC}"
    echo -e "${YELLOW}╚════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}Continue with installation? [y/N]${NC} "
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo "Installation cancelled."
        exit 1
    fi
else
    echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  All preflight checks PASSED!          ║${NC}"
    echo -e "${GREEN}║  Ready to proceed with installation    ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
fi

echo ""
echo -e "${BLUE}Next steps:${NC}"
echo -e "  ${BLUE}1.${NC} Run: ${GREEN}sudo ./01-install-dependencies.sh${NC}"
echo -e "  ${BLUE}2.${NC} Or run all: ${GREEN}sudo ./install-all.sh${NC}"
echo ""

exit 0
