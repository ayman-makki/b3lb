#!/bin/bash

###############################################################################
# B3LB Deployment Script for Hetzner EX44 with Traefik
#
# This script deploys the complete B3LB stack including:
# - Traefik reverse proxy with Let's Encrypt
# - PostgreSQL database
# - Redis cache
# - B3LB frontend (3 replicas)
# - Celery workers
# - Prometheus & Grafana monitoring
#
# Prerequisites:
# - Pre-flight checks passed (run 00-preflight-check.sh)
# - Storage Box mounted
# - .env file configured
# - DNS configured
#
# Usage:
#   sudo ./03-deploy-stack.sh
###############################################################################

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

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

log_step() {
    echo -e "${CYAN}==>${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root (use sudo)"
   exit 1
fi

###############################################################################
# Header
###############################################################################

clear
echo
echo "======================================================================"
echo "  B3LB Deployment for Hetzner EX44 with Traefik"
echo "======================================================================"
echo

###############################################################################
# Step 1: Pre-Deployment Checks
###############################################################################

log_step "Step 1/10: Running pre-deployment checks..."
echo

# Check if .env exists
if [ ! -f ".env" ] && [ ! -f "../../.env" ]; then
    log_error ".env file not found!"
    log_info "Run: cp .env.hetzner.example .env && nano .env"
    exit 1
fi

# Load environment
if [ -f "../../.env" ]; then
    cd ../..
fi

if [ ! -f ".env" ]; then
    log_error ".env file not found in $(pwd)"
    exit 1
fi

source .env

log_success "Environment loaded"

# Verify critical variables
CRITICAL_VARS=("SECRET_KEY" "POSTGRES_PASSWORD" "REDIS_PASSWORD" "HETZNER_DNS_API_TOKEN")
for VAR in "${CRITICAL_VARS[@]}"; do
    if [ -z "${!VAR:-}" ] || [[ "${!VAR:-}" == *"change-me"* ]]; then
        log_error "${VAR} is not configured properly in .env"
        exit 1
    fi
done

log_success "All critical variables configured"
echo

###############################################################################
# Step 2: Generate Secrets
###############################################################################

log_step "Step 2/10: Generating secrets..."
echo

# Generate SECRET_KEY if not already set
if [[ "${SECRET_KEY}" == *"your-secret-key-here"* ]]; then
    log_info "Generating new SECRET_KEY..."
    NEW_SECRET=$(python3 -c 'from django.core.management.utils import get_random_secret_key; print(get_random_secret_key())')
    sed -i "s|SECRET_KEY=.*|SECRET_KEY=${NEW_SECRET}|g" .env
    source .env
    log_success "SECRET_KEY generated"
fi

# Generate Traefik dashboard password if needed
if [[ "${TRAEFIK_DASHBOARD_AUTH:-}" == *"change-this"* ]] || [ -z "${TRAEFIK_DASHBOARD_AUTH:-}" ]; then
    log_info "Generating Traefik dashboard password..."
    TRAEFIK_PASS=$(openssl rand -base64 16)
    TRAEFIK_HASH=$(htpasswd -nb admin "${TRAEFIK_PASS}" | sed -e s/\\$/\\$\\$/g)
    sed -i "s|TRAEFIK_DASHBOARD_AUTH=.*|TRAEFIK_DASHBOARD_AUTH=${TRAEFIK_HASH}|g" .env
    source .env
    echo "admin:${TRAEFIK_PASS}" > .traefik-password.txt
    chmod 600 .traefik-password.txt
    log_success "Traefik password: ${TRAEFIK_PASS} (saved to .traefik-password.txt)"
fi

log_success "All secrets generated"
echo

###############################################################################
# Step 3: Create Required Directories
###############################################################################

log_step "Step 3/10: Creating required directories..."
echo

REQUIRED_DIRS=(
    "traefik/dynamic"
    "monitoring/prometheus"
    "monitoring/grafana/dashboards"
    "monitoring/grafana/provisioning/datasources"
    "monitoring/grafana/provisioning/dashboards"
    "media"
    "scripts/postgres"
)

for DIR in "${REQUIRED_DIRS[@]}"; do
    if [ ! -d "${DIR}" ]; then
        mkdir -p "${DIR}"
        log_info "Created directory: ${DIR}"
    fi
done

# Create acme.json for Let's Encrypt
if [ ! -f "traefik/acme.json" ]; then
    touch traefik/acme.json
    chmod 600 traefik/acme.json
    log_success "Created traefik/acme.json"
fi

# Create simple PostgreSQL init script if not exists
if [ ! -f "scripts/postgres/init.sql" ]; then
    cat > scripts/postgres/init.sql <<'EOF'
-- B3LB PostgreSQL Initialization
-- This file is executed once when the database is first created

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Create additional settings if needed
ALTER DATABASE b3lb SET timezone TO 'UTC';
EOF
    log_success "Created PostgreSQL init script"
fi

log_success "All directories created"
echo

###############################################################################
# Step 4: Verify Storage Box Mount
###############################################################################

log_step "Step 4/10: Verifying Storage Box mount..."
echo

STORAGE_MOUNT="${STORAGEBOX_MOUNT_POINT:-/mnt/b3lb-recordings}"

if mountpoint -q "${STORAGE_MOUNT}"; then
    log_success "Storage Box is mounted at ${STORAGE_MOUNT}"

    # Create subdirectories
    mkdir -p "${STORAGE_MOUNT}/recordings"
    mkdir -p "${STORAGE_MOUNT}/backups"
    mkdir -p "${STORAGE_MOUNT}/tmp"
    log_success "Storage subdirectories created"
else
    log_error "Storage Box is NOT mounted!"
    log_info "Run: sudo ./scripts/storage/mount-storagebox.sh"
    exit 1
fi

echo

###############################################################################
# Step 5: Pull Docker Images
###############################################################################

log_step "Step 5/10: Pulling Docker images..."
echo

log_info "This may take several minutes..."

if docker compose -f docker-compose.hetzner-production.yml pull; then
    log_success "All images pulled successfully"
else
    log_error "Failed to pull images"
    exit 1
fi

echo

###############################################################################
# Step 6: Stop Existing Containers (if any)
###############################################################################

log_step "Step 6/10: Stopping existing containers..."
echo

if docker compose -f docker-compose.hetzner-production.yml ps -q 2>/dev/null | grep -q .; then
    log_info "Found existing containers, stopping..."
    docker compose -f docker-compose.hetzner-production.yml down
    log_success "Existing containers stopped"
else
    log_info "No existing containers found"
fi

echo

###############################################################################
# Step 7: Start Database Services
###############################################################################

log_step "Step 7/10: Starting database services..."
echo

log_info "Starting PostgreSQL and Redis..."

docker compose -f docker-compose.hetzner-production.yml up -d postgres redis

# Wait for databases to be healthy
log_info "Waiting for databases to be ready..."
sleep 10

MAX_RETRIES=30
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if docker compose -f docker-compose.hetzner-production.yml ps postgres | grep -q "healthy"; then
        log_success "PostgreSQL is ready"
        break
    fi
    RETRY_COUNT=$((RETRY_COUNT + 1))
    echo -n "."
    sleep 2
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    log_error "PostgreSQL failed to start"
    docker compose -f docker-compose.hetzner-production.yml logs postgres
    exit 1
fi

echo
log_success "Database services started"
echo

###############################################################################
# Step 8: Run Database Migrations
###############################################################################

log_step "Step 8/10: Running database migrations..."
echo

log_info "Applying Django migrations..."

# Run migrations using temporary container
docker compose -f docker-compose.hetzner-production.yml run --rm \
    -e DATABASE_URL="postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}" \
    -e SECRET_KEY="${SECRET_KEY}" \
    --entrypoint "python manage.py migrate" \
    frontend

log_success "Database migrations completed"

# Collect static files
log_info "Collecting static files..."

docker compose -f docker-compose.hetzner-production.yml run --rm \
    -e DATABASE_URL="postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}" \
    -e SECRET_KEY="${SECRET_KEY}" \
    --entrypoint "python manage.py collectstatic --noinput" \
    frontend

log_success "Static files collected"
echo

###############################################################################
# Step 9: Start All Services
###############################################################################

log_step "Step 9/10: Starting all services..."
echo

log_info "Starting B3LB stack (this may take a minute)..."

if docker compose -f docker-compose.hetzner-production.yml up -d; then
    log_success "All services started"
else
    log_error "Failed to start services"
    exit 1
fi

# Wait for services to be healthy
log_info "Waiting for services to be healthy..."
sleep 15

echo

###############################################################################
# Step 10: Create Django Superuser
###############################################################################

log_step "Step 10/10: Creating Django superuser..."
echo

if docker compose -f docker-compose.hetzner-production.yml exec -T frontend \
    python manage.py shell -c "from django.contrib.auth import get_user_model; User = get_user_model(); User.objects.filter(username='admin').exists()" 2>/dev/null | grep -q "True"; then
    log_info "Superuser 'admin' already exists"
else
    log_info "Creating superuser 'admin'..."
    log_warning "You will be prompted to set a password for the admin user"
    echo

    docker compose -f docker-compose.hetzner-production.yml exec frontend \
        python manage.py createsuperuser --username admin --email admin@b3lb.serveur.cc || true

    log_success "Superuser created"
fi

echo

###############################################################################
# Deployment Summary
###############################################################################

echo
echo "======================================================================"
echo "  B3LB Deployment Complete!"
echo "======================================================================"
echo

log_success "All services are running!"
echo

log_info "Service URLs:"
echo "  - B3LB API:           https://b3lb.serveur.cc"
echo "  - Django Admin:       https://b3lb.serveur.cc/admin/"
echo "  - Traefik Dashboard:  https://traefik.b3lb.serveur.cc"
echo "  - Grafana:            https://grafana.b3lb.serveur.cc"
echo "  - Prometheus:         https://prometheus.b3lb.serveur.cc"
echo

log_info "Credentials:"
echo "  - Django Admin:  admin / (password you just set)"
echo "  - Grafana:       ${GRAFANA_ADMIN_USER:-admin} / ${GRAFANA_ADMIN_PASSWORD}"
if [ -f ".traefik-password.txt" ]; then
    TRAEFIK_CREDS=$(cat .traefik-password.txt)
    echo "  - Traefik:       ${TRAEFIK_CREDS}"
fi
echo

log_info "Next Steps:"
echo "  1. Run post-deployment verification:"
echo "     ./scripts/deploy/04-post-deploy-verify.sh"
echo
echo "  2. Configure your first tenant:"
echo "     - Go to: https://b3lb.serveur.cc/admin/"
echo "     - Add a Cluster Group"
echo "     - Add a Cluster"
echo "     - Add your BBB Nodes"
echo "     - Add a Tenant"
echo "     - Generate API secrets"
echo
echo "  3. Test the API:"
echo "     curl https://your-tenant.b3lb.serveur.cc/bigbluebutton/api"
echo
echo "  4. Monitor logs:"
echo "     docker compose -f docker-compose.hetzner-production.yml logs -f"
echo

log_info "Documentation:"
echo "  - Main docs: docs/deployment/HETZNER-VPS-TRAEFIK-DEPLOYMENT.md"
echo "  - Initial config: docs/deployment/INITIAL-CONFIGURATION.md"
echo "  - BBB node setup: docs/deployment/BBB-NODE-SETUP.md"
echo

log_success "Deployment completed successfully!"
echo
