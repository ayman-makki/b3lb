#!/bin/bash

###############################################################################
# B3LB Pre-Flight Check Script for Hetzner Deployment
#
# This script validates all requirements before deploying B3LB.
#
# Checks:
# - System requirements (CPU, RAM, disk)
# - Required software (Docker, Docker Compose)
# - DNS configuration
# - Storage Box connectivity
# - Network ports
# - Environment configuration
#
# Usage:
#   ./00-preflight-check.sh
###############################################################################

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARNING=0

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
    ((CHECKS_PASSED++))
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
    ((CHECKS_WARNING++))
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
    ((CHECKS_FAILED++))
}

check_command() {
    local cmd="$1"
    local name="$2"

    if command -v "${cmd}" &> /dev/null; then
        local version=$(${cmd} --version 2>/dev/null | head -n1 || echo "unknown")
        log_success "${name} is installed (${version})"
        return 0
    else
        log_error "${name} is NOT installed"
        return 1
    fi
}

###############################################################################
# Header
###############################################################################

echo
echo "======================================================================"
echo "  B3LB Pre-Flight Check for Hetzner EX44 Deployment"
echo "======================================================================"
echo

###############################################################################
# 1. System Requirements
###############################################################################

log_info "Checking system requirements..."
echo

# CPU cores
CPU_CORES=$(nproc)
if [ "${CPU_CORES}" -ge 8 ]; then
    log_success "CPU cores: ${CPU_CORES} (minimum: 8)"
else
    log_warning "CPU cores: ${CPU_CORES} (minimum recommended: 8)"
fi

# RAM
TOTAL_RAM_GB=$(free -g | awk '/^Mem:/{print $2}')
if [ "${TOTAL_RAM_GB}" -ge 32 ]; then
    log_success "Total RAM: ${TOTAL_RAM_GB}GB (minimum: 32GB)"
elif [ "${TOTAL_RAM_GB}" -ge 16 ]; then
    log_warning "Total RAM: ${TOTAL_RAM_GB}GB (recommended: 64GB for production)"
else
    log_error "Total RAM: ${TOTAL_RAM_GB}GB (minimum required: 16GB)"
fi

# Disk space
DISK_SPACE_GB=$(df -BG / | tail -1 | awk '{print $4}' | sed 's/G//')
if [ "${DISK_SPACE_GB}" -ge 100 ]; then
    log_success "Available disk space: ${DISK_SPACE_GB}GB (minimum: 100GB)"
elif [ "${DISK_SPACE_GB}" -ge 50 ]; then
    log_warning "Available disk space: ${DISK_SPACE_GB}GB (recommended: 100GB)"
else
    log_error "Available disk space: ${DISK_SPACE_GB}GB (minimum required: 50GB)"
fi

echo

###############################################################################
# 2. Required Software
###############################################################################

log_info "Checking required software..."
echo

check_command "docker" "Docker"
check_command "docker-compose" "Docker Compose" || check_command "docker" "Docker Compose (plugin)"
check_command "git" "Git"
check_command "curl" "cURL"
check_command "htpasswd" "Apache2 Utils (htpasswd)" || log_warning "htpasswd not found (install apache2-utils)"

# Check if Docker is running
if systemctl is-active --quiet docker 2>/dev/null || pgrep dockerd > /dev/null 2>&1; then
    log_success "Docker service is running"
else
    log_error "Docker service is NOT running"
fi

# Check Docker version
DOCKER_VERSION=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "0")
if [ "$(printf '%s\n' "20.10" "${DOCKER_VERSION}" | sort -V | head -n1)" = "20.10" ]; then
    log_success "Docker version: ${DOCKER_VERSION} (minimum: 20.10)"
else
    log_warning "Docker version: ${DOCKER_VERSION} (recommended: 20.10+)"
fi

echo

###############################################################################
# 3. Network Ports
###############################################################################

log_info "Checking required network ports..."
echo

check_port() {
    local port="$1"
    local service="$2"

    if ss -tuln | grep -q ":${port} "; then
        log_warning "Port ${port} (${service}) is already in use"
        return 1
    else
        log_success "Port ${port} (${service}) is available"
        return 0
    fi
}

check_port 80 "HTTP"
check_port 443 "HTTPS"

echo

###############################################################################
# 4. DNS Configuration
###############################################################################

log_info "Checking DNS configuration..."
echo

# Load .env if exists
if [ -f "../../.env" ]; then
    export $(grep -v '^#' ../../.env | grep -v '^$' | xargs)
fi

DOMAIN="b3lb.serveur.cc"

# Check if domain resolves
if host "${DOMAIN}" &> /dev/null; then
    RESOLVED_IP=$(host "${DOMAIN}" | grep "has address" | awk '{print $4}' | head -n1)
    SERVER_IP=$(curl -s4 ifconfig.me || curl -s4 icanhazip.com)

    if [ "${RESOLVED_IP}" = "${SERVER_IP}" ]; then
        log_success "DNS ${DOMAIN} resolves to server IP (${SERVER_IP})"
    else
        log_warning "DNS ${DOMAIN} resolves to ${RESOLVED_IP}, but server IP is ${SERVER_IP}"
    fi
else
    log_error "DNS ${DOMAIN} does not resolve"
fi

# Check wildcard DNS
WILDCARD_TEST="test-$(date +%s).${DOMAIN}"
if host "${WILDCARD_TEST}" &> /dev/null; then
    WILDCARD_IP=$(host "${WILDCARD_TEST}" | grep "has address" | awk '{print $4}' | head -n1)
    if [ "${WILDCARD_IP}" = "${SERVER_IP}" ]; then
        log_success "Wildcard DNS *.${DOMAIN} is configured correctly"
    else
        log_warning "Wildcard DNS *.${DOMAIN} resolves to ${WILDCARD_IP}, expected ${SERVER_IP}"
    fi
else
    log_warning "Wildcard DNS *.${DOMAIN} is not configured (required for multi-tenancy)"
fi

echo

###############################################################################
# 5. Storage Box
###############################################################################

log_info "Checking Hetzner Storage Box..."
echo

STORAGEBOX_MOUNT="/mnt/b3lb-recordings"

if mountpoint -q "${STORAGEBOX_MOUNT}" 2>/dev/null; then
    log_success "Storage Box is mounted at ${STORAGEBOX_MOUNT}"

    # Check if writable
    if [ -w "${STORAGEBOX_MOUNT}" ]; then
        log_success "Storage Box is writable"
    else
        log_error "Storage Box is NOT writable"
    fi

    # Check available space
    STORAGE_AVAILABLE=$(df -h "${STORAGEBOX_MOUNT}" | tail -1 | awk '{print $4}')
    log_info "Storage Box available space: ${STORAGE_AVAILABLE}"
else
    log_error "Storage Box is NOT mounted at ${STORAGEBOX_MOUNT}"
    log_info "Run: ./scripts/storage/mount-storagebox.sh"
fi

echo

###############################################################################
# 6. Environment Configuration
###############################################################################

log_info "Checking environment configuration..."
echo

if [ -f "../../.env" ]; then
    log_success ".env file exists"

    # Check required variables
    REQUIRED_VARS=(
        "SECRET_KEY"
        "POSTGRES_PASSWORD"
        "REDIS_PASSWORD"
        "HETZNER_DNS_API_TOKEN"
        "TRAEFIK_DASHBOARD_AUTH"
        "GRAFANA_ADMIN_PASSWORD"
    )

    for VAR in "${REQUIRED_VARS[@]}"; do
        if grep -q "^${VAR}=" ../../.env && ! grep -q "^${VAR}=.*change-me" ../../.env; then
            log_success "${VAR} is configured"
        else
            log_error "${VAR} is NOT configured or contains default value"
        fi
    done
else
    log_error ".env file does NOT exist"
    log_info "Run: cp .env.hetzner.example .env"
fi

echo

###############################################################################
# 7. Docker Compose File
###############################################################################

log_info "Checking Docker Compose configuration..."
echo

if [ -f "../../docker-compose.hetzner-production.yml" ]; then
    log_success "docker-compose.hetzner-production.yml exists"

    # Validate syntax
    if docker-compose -f ../../docker-compose.hetzner-production.yml config > /dev/null 2>&1; then
        log_success "docker-compose.hetzner-production.yml syntax is valid"
    else
        log_error "docker-compose.hetzner-production.yml syntax is INVALID"
    fi
else
    log_error "docker-compose.hetzner-production.yml does NOT exist"
fi

echo

###############################################################################
# 8. Traefik Configuration
###############################################################################

log_info "Checking Traefik configuration..."
echo

TRAEFIK_FILES=(
    "../../traefik/traefik.yml"
    "../../traefik/dynamic/middlewares.yml"
    "../../traefik/dynamic/tls.yml"
)

for FILE in "${TRAEFIK_FILES[@]}"; do
    if [ -f "${FILE}" ]; then
        log_success "$(basename ${FILE}) exists"
    else
        log_error "$(basename ${FILE}) does NOT exist"
    fi
done

# Create acme.json if it doesn't exist
if [ ! -f "../../traefik/acme.json" ]; then
    log_info "Creating acme.json for Let's Encrypt certificates..."
    touch ../../traefik/acme.json
    chmod 600 ../../traefik/acme.json
    log_success "acme.json created with correct permissions"
fi

echo

###############################################################################
# 9. Firewall
###############################################################################

log_info "Checking firewall configuration..."
echo

if command -v ufw &> /dev/null; then
    if ufw status | grep -q "Status: active"; then
        log_success "UFW firewall is active"

        # Check required ports
        if ufw status | grep -q "80/tcp.*ALLOW"; then
            log_success "UFW allows port 80 (HTTP)"
        else
            log_warning "UFW does NOT allow port 80"
        fi

        if ufw status | grep -q "443/tcp.*ALLOW"; then
            log_success "UFW allows port 443 (HTTPS)"
        else
            log_warning "UFW does NOT allow port 443"
        fi
    else
        log_warning "UFW firewall is NOT active"
    fi
else
    log_warning "UFW is NOT installed (run scripts/deploy/01-setup-firewall.sh)"
fi

echo

###############################################################################
# 10. SSL/TLS Certificates
###############################################################################

log_info "Checking SSL certificate requirements..."
echo

if [ -n "${HETZNER_DNS_API_TOKEN:-}" ]; then
    log_success "Hetzner DNS API token is configured"
else
    log_error "Hetzner DNS API token is NOT configured"
    log_info "Get your token from: https://dns.hetzner.com/settings/api-token"
fi

echo

###############################################################################
# Summary
###############################################################################

echo "======================================================================"
echo "  Pre-Flight Check Summary"
echo "======================================================================"
echo
echo -e "Checks passed:  ${GREEN}${CHECKS_PASSED}${NC}"
echo -e "Checks warned:  ${YELLOW}${CHECKS_WARNING}${NC}"
echo -e "Checks failed:  ${RED}${CHECKS_FAILED}${NC}"
echo

if [ ${CHECKS_FAILED} -eq 0 ]; then
    if [ ${CHECKS_WARNING} -eq 0 ]; then
        log_success "All checks passed! Ready to deploy B3LB."
        echo
        log_info "Next steps:"
        log_info "1. Review and configure .env file"
        log_info "2. Run: ./scripts/deploy/03-deploy-stack.sh"
        echo
        exit 0
    else
        log_warning "All critical checks passed, but there are warnings."
        echo
        log_info "You can proceed with deployment, but review the warnings above."
        echo
        log_info "Next steps:"
        log_info "1. Address warnings if possible"
        log_info "2. Run: ./scripts/deploy/03-deploy-stack.sh"
        echo
        exit 0
    fi
else
    log_error "Some checks failed. Please fix the errors before deploying."
    echo
    log_info "Common issues:"
    log_info "- Install Docker: curl -fsSL https://get.docker.com | sh"
    log_info "- Mount Storage Box: ./scripts/storage/mount-storagebox.sh"
    log_info "- Configure .env: cp .env.hetzner.example .env && nano .env"
    log_info "- Configure DNS: Add A and wildcard CNAME records in Hetzner DNS"
    echo
    exit 1
fi
