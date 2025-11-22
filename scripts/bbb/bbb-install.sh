#!/usr/bin/env bash
set -e

# ============================================================================
# CONFIGURATION
# ============================================================================

# Domain names (Change these before running)
BBB_DOMAIN="bbb.example.com"
B3LB_DOMAIN="b3lb.example.com"

# Installation settings
BBB_VERSION="jammy-300" # BBB 3.0 for Ubuntu 22.04
EMAIL="admin@majlis.cam"
REPO_URL="https://github.com/ayman-makki/b3lb.git"
INSTALL_DIR="/root/b3lb" # Directory to clone the repo into

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

print_header() {
    echo -e "\n${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  $1${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}\n"
}

print_status() {
    echo -e "${BLUE}▶${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
    exit 1
}

# ============================================================================
# MAIN INSTALLATION
# ============================================================================

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root"
fi

print_header "B3LB Node Installation Wrapper"

# ----------------------------------------------------------------------------
# Step 0: System Update
# ----------------------------------------------------------------------------
print_status "Step 0: Updating system..."
apt-get update && apt-get upgrade -y
print_success "System updated"

# ----------------------------------------------------------------------------
# Step 1: Fetch Repository
# ----------------------------------------------------------------------------
print_status "Step 1: Fetching B3LB repository..."

# Check for git
if ! command -v git &> /dev/null; then
    print_status "Installing git..."
    apt-get update && apt-get install -y git
fi

if [ -d "$INSTALL_DIR" ]; then
    print_status "Updating existing repository at $INSTALL_DIR..."
    cd "$INSTALL_DIR"
    git pull
    print_success "Repository updated"
else
    print_status "Cloning repository to $INSTALL_DIR..."
    git clone "$REPO_URL" "$INSTALL_DIR"
    print_success "Repository cloned"
fi

# ----------------------------------------------------------------------------
# Step 2: Verify Domain DNS
# ----------------------------------------------------------------------------
print_status "Step 2: Verifying DNS for $BBB_DOMAIN..."

# Get public IP
PUBLIC_IP=$(curl -s https://api.ipify.org)
if [ -z "$PUBLIC_IP" ]; then
    PUBLIC_IP=$(wget -qO- https://api.ipify.org)
fi

print_status "Server Public IP: $PUBLIC_IP"

# Resolve Domain IP
DOMAIN_IP=$(dig +short "$BBB_DOMAIN" | head -n 1)

if [ -z "$DOMAIN_IP" ]; then
    print_error "Could not resolve domain $BBB_DOMAIN. Please ensure DNS A record is set."
fi

print_status "Domain $BBB_DOMAIN resolves to: $DOMAIN_IP"

if [ "$PUBLIC_IP" != "$DOMAIN_IP" ]; then
    print_error "Domain $BBB_DOMAIN ($DOMAIN_IP) does not point to this server ($PUBLIC_IP). Installation aborted."
else
    print_success "DNS verification passed."
fi

# ----------------------------------------------------------------------------
# Step 3: Install BigBlueButton
# ----------------------------------------------------------------------------
print_status "Step 3: Checking BigBlueButton installation..."

if command -v bbb-conf &> /dev/null; then
    print_success "BigBlueButton is already installed. Skipping installation."
    # Optionally check version here if needed
else
    print_status "Installing BigBlueButton $BBB_VERSION..."
    print_status "Command: wget -qO- https://raw.githubusercontent.com/bigbluebutton/bbb-install/v3.0.x-release/bbb-install.sh | bash -s -- -v $BBB_VERSION -s $BBB_DOMAIN -e $EMAIL -w"
    
    wget -qO- https://raw.githubusercontent.com/bigbluebutton/bbb-install/v3.0.x-release/bbb-install.sh | bash -s -- -v "$BBB_VERSION" -s "$BBB_DOMAIN" -e "$EMAIL" -w
    
    if [ $? -eq 0 ]; then
        print_success "BigBlueButton installed successfully."
    else
        print_error "BigBlueButton installation failed."
    fi
fi

# ----------------------------------------------------------------------------
# Step 4: Install B3LB Node Scripts
# ----------------------------------------------------------------------------
print_status "Step 4: Installing B3LB Node Scripts..."

INSTALL_SCRIPT_DIR="$INSTALL_DIR/scripts/bbb/install"

if [ ! -d "$INSTALL_SCRIPT_DIR" ]; then
    print_error "Installation scripts not found at $INSTALL_SCRIPT_DIR"
fi

cd "$INSTALL_SCRIPT_DIR"

# Configure environment
CONFIG_FILE="config.env"

if [ -f "$CONFIG_FILE" ]; then
    print_status "Config file $CONFIG_FILE already exists. Checking configuration..."
    # We could add check here if B3LB_BACKEND_URL matches, but for now we assume manual intervention if it exists
    print_success "Using existing configuration."
else
    print_status "Creating configuration from example..."
    cp config.env.example "$CONFIG_FILE"
    
    # Set B3LB Backend URL
    # Escaping slashes for sed
    BACKEND_URL="https://$B3LB_DOMAIN"
    sed -i "s|B3LB_BACKEND_URL=\".*\"|B3LB_BACKEND_URL=\"$BACKEND_URL\"|" "$CONFIG_FILE"
    
    print_success "Configuration created with B3LB_BACKEND_URL=$BACKEND_URL"
fi

# Source config and run install-all.sh
print_status "Running B3LB install-all.sh..."

# Ensure install-all.sh is executable
chmod +x install-all.sh

# Source the configuration as requested
set -a # Automatically export all variables
source "$CONFIG_FILE"
set +a

# Run the script
if ./install-all.sh; then
    print_success "B3LB Node Scripts installed successfully."
else
    print_error "B3LB Node Scripts installation failed."
fi

print_header "Installation Complete!"
echo -e "BigBlueButton Domain: https://$BBB_DOMAIN"
echo -e "B3LB Backend: https://$B3LB_DOMAIN"
echo -e "Check status with: bbb-conf --check"
