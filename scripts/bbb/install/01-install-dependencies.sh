#!/usr/bin/env bash
set -e

# B3LB BBB Node Installation - Install Dependencies
# This script installs all required system dependencies

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.env"

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
    echo "Please copy config.env.example to config.env and configure it"
    exit 1
fi

source "$CONFIG_FILE"

# Main header
clear
echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  B3LB BBB Node - Install Dependencies  ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

# Step 1: Update package lists
print_header "Updating Package Lists"
print_step "Running apt-get update..."
if apt-get update -qq; then
    print_success "Package lists updated"
else
    print_error "Failed to update package lists"
    exit 1
fi

# Step 2: Install Ruby SQLite3 gem
print_header "Installing Ruby Dependencies"
print_step "Installing ruby-sqlite3..."
if apt-get install -y ruby-sqlite3 > /dev/null 2>&1; then
    print_success "ruby-sqlite3 installed"
else
    print_error "Failed to install ruby-sqlite3"
    exit 1
fi

# Verify Ruby SQLite3
print_step "Verifying ruby-sqlite3..."
if ruby -r sqlite3 -e "puts 'OK'" &> /dev/null; then
    print_success "ruby-sqlite3 verified"
else
    print_error "ruby-sqlite3 verification failed"
    exit 1
fi

# Step 3: Install Python requests library
print_header "Installing Python Dependencies"
print_step "Installing python3-requests..."
if apt-get install -y python3-requests > /dev/null 2>&1; then
    print_success "python3-requests installed"
else
    print_error "Failed to install python3-requests"
    exit 1
fi

# Verify Python requests
print_step "Verifying python3-requests..."
if python3 -c "import requests; print('OK')" &> /dev/null; then
    print_success "python3-requests verified"
else
    print_error "python3-requests verification failed"
    exit 1
fi

# Step 4: Verify other required tools (should already exist in BBB)
print_header "Verifying System Tools"
for tool in systemctl nginx tar curl sqlite3; do
    print_step "Checking $tool..."
    if command -v $tool &> /dev/null; then
        print_success "$tool available"
    else
        print_warning "$tool not found"
    fi
done

# Summary
print_header "Installation Summary"
echo -e "${GREEN}✓ All dependencies installed successfully${NC}"
echo ""
echo -e "${BLUE}Installed packages:${NC}"
echo -e "  • ruby-sqlite3"
echo -e "  • python3-requests"
echo ""
echo -e "${BLUE}Next step:${NC}"
echo -e "  Run: ${GREEN}sudo ./02-install-b3lb-load.sh${NC}"
echo ""

exit 0
