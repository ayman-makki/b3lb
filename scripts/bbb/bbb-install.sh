#!/usr/bin/env bash
set -e

# ============================================================================
# CONFIGURATION
# ============================================================================

# Installation settings
BBB_VERSION="jammy-300" # BBB 3.0 for Ubuntu 22.04
REPO_URL="https://github.com/ayman-makki/b3lb.git"
INSTALL_DIR="/root/b3lb" # Directory to clone the repo into

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# USAGE AND ARGUMENT PARSING
# ============================================================================

usage() {
    echo "Usage: $0 --bbb-domain <domain> --b3lb-domain <domain> [--email <email>]"
    echo ""
    echo "Required:"
    echo "  --bbb-domain    BigBlueButton server domain (e.g., bbb.example.com)"
    echo "  --b3lb-domain   B3LB backend domain (e.g., b3lb.example.com)"
    echo ""
    echo "Optional:"
    echo "  --email         Email for Let's Encrypt (default: admin@example.com)"
    exit 1
}

# Default values
BBB_DOMAIN=""
B3LB_DOMAIN=""
EMAIL="admin@example.com"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --bbb-domain)
            BBB_DOMAIN="$2"
            shift 2
            ;;
        --b3lb-domain)
            B3LB_DOMAIN="$2"
            shift 2
            ;;
        --email)
            EMAIL="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

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

# Validate required arguments
if [ -z "$BBB_DOMAIN" ] || [ -z "$B3LB_DOMAIN" ]; then
    echo -e "${RED}✗${NC} Missing required arguments."
    usage
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

# Resolve Domain IP (with fallback methods)
if command -v dig &> /dev/null; then
    DOMAIN_IP=$(dig +short "$BBB_DOMAIN" | head -n 1)
elif command -v host &> /dev/null; then
    DOMAIN_IP=$(host "$BBB_DOMAIN" | awk '/has address/ { print $4; exit }')
elif command -v getent &> /dev/null; then
    DOMAIN_IP=$(getent hosts "$BBB_DOMAIN" | awk '{ print $1; exit }')
else
    print_status "Installing dnsutils for DNS resolution..."
    apt-get install -y dnsutils
    DOMAIN_IP=$(dig +short "$BBB_DOMAIN" | head -n 1)
fi

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

    if ! wget -qO- https://raw.githubusercontent.com/bigbluebutton/bbb-install/v3.0.x-release/bbb-install.sh | bash -s -- -v "$BBB_VERSION" -s "$BBB_DOMAIN" -e "$EMAIL" -w; then
        print_error "BigBlueButton installation failed."
    fi
    print_success "BigBlueButton installed successfully."
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
