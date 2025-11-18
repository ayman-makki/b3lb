#!/bin/bash

###############################################################################
# Hetzner Storage Box Test Script for B3LB
#
# This script tests the Hetzner Storage Box connection and permissions.
#
# Requirements:
# - Storage Box already mounted
#
# Usage:
#   ./test-storagebox.sh [mount-point]
#
# Example:
#   ./test-storagebox.sh /mnt/b3lb-recordings
###############################################################################

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

###############################################################################
# Configuration
###############################################################################

MOUNT_POINT="${1:-/mnt/b3lb-recordings}"
TEST_PASSED=0
TEST_FAILED=0

###############################################################################
# Test Functions
###############################################################################

run_test() {
    local test_name="$1"
    local test_command="$2"

    echo -n "Testing ${test_name}... "

    if eval "${test_command}" &> /dev/null; then
        log_success "${test_name}"
        ((TEST_PASSED++))
        return 0
    else
        log_error "${test_name}"
        ((TEST_FAILED++))
        return 1
    fi
}

###############################################################################
# Main Tests
###############################################################################

echo
log_info "======================================================================"
log_info "Hetzner Storage Box Test Suite"
log_info "======================================================================"
echo
log_info "Mount point: ${MOUNT_POINT}"
echo

# Test 1: Mount point exists
run_test "Mount point exists" "[ -d '${MOUNT_POINT}' ]"

# Test 2: Mount point is mounted
if mountpoint -q "${MOUNT_POINT}" 2>/dev/null; then
    log_success "Mount point is mounted"
    ((TEST_PASSED++))
else
    log_error "Mount point is NOT mounted"
    log_error "Please run mount-storagebox.sh first"
    ((TEST_FAILED++))
    exit 1
fi

# Test 3: Mount point is accessible
run_test "Mount point is accessible" "cd '${MOUNT_POINT}' && cd -"

# Test 4: Can list files
run_test "Can list files" "ls -la '${MOUNT_POINT}'"

# Test 5: Can write files
TEST_FILE="${MOUNT_POINT}/.test-write-$(date +%s).txt"
if echo "B3LB Storage Box Write Test - $(date)" > "${TEST_FILE}" 2>/dev/null; then
    log_success "Can write files"
    ((TEST_PASSED++))

    # Test 6: Can read files
    if cat "${TEST_FILE}" > /dev/null 2>&1; then
        log_success "Can read files"
        ((TEST_PASSED++))
    else
        log_error "Can read files"
        ((TEST_FAILED++))
    fi

    # Test 7: Can delete files
    if rm -f "${TEST_FILE}" 2>/dev/null; then
        log_success "Can delete files"
        ((TEST_PASSED++))
    else
        log_error "Can delete files"
        ((TEST_FAILED++))
    fi
else
    log_error "Can write files"
    log_error "Check permissions and credentials"
    ((TEST_FAILED++))
fi

# Test 8: Can create directories
TEST_DIR="${MOUNT_POINT}/.test-dir-$(date +%s)"
if mkdir "${TEST_DIR}" 2>/dev/null; then
    log_success "Can create directories"
    ((TEST_PASSED++))

    # Test 9: Can remove directories
    if rmdir "${TEST_DIR}" 2>/dev/null; then
        log_success "Can remove directories"
        ((TEST_PASSED++))
    else
        log_error "Can remove directories"
        ((TEST_FAILED++))
    fi
else
    log_error "Can create directories"
    ((TEST_FAILED++))
fi

# Test 10: Check available space
echo -n "Checking available space... "
AVAILABLE_SPACE=$(df -h "${MOUNT_POINT}" | tail -1 | awk '{print $4}')
USED_PERCENT=$(df -h "${MOUNT_POINT}" | tail -1 | awk '{print $5}')

if [ -n "${AVAILABLE_SPACE}" ]; then
    log_success "Available space: ${AVAILABLE_SPACE} (Used: ${USED_PERCENT})"
    ((TEST_PASSED++))
else
    log_error "Cannot determine available space"
    ((TEST_FAILED++))
fi

# Test 11: Check mount options
echo -n "Checking mount options... "
MOUNT_OPTIONS=$(mount | grep "${MOUNT_POINT}" | sed 's/.*(\(.*\))/\1/')

if [ -n "${MOUNT_OPTIONS}" ]; then
    log_success "Mount options: ${MOUNT_OPTIONS}"
    ((TEST_PASSED++))
else
    log_warning "Cannot determine mount options"
    ((TEST_FAILED++))
fi

# Test 12: Performance test - Write speed
echo -n "Testing write speed... "
WRITE_TEST_FILE="${MOUNT_POINT}/.test-performance-$(date +%s).bin"
WRITE_START=$(date +%s.%N)

if dd if=/dev/zero of="${WRITE_TEST_FILE}" bs=1M count=10 conv=fdatasync &> /dev/null; then
    WRITE_END=$(date +%s.%N)
    WRITE_DURATION=$(echo "${WRITE_END} - ${WRITE_START}" | bc)
    WRITE_SPEED=$(echo "scale=2; 10 / ${WRITE_DURATION}" | bc)
    log_success "Write speed: ${WRITE_SPEED} MB/s"
    ((TEST_PASSED++))

    # Test 13: Performance test - Read speed
    echo -n "Testing read speed... "
    READ_START=$(date +%s.%N)

    if dd if="${WRITE_TEST_FILE}" of=/dev/null bs=1M &> /dev/null; then
        READ_END=$(date +%s.%N)
        READ_DURATION=$(echo "${READ_END} - ${READ_START}" | bc)
        READ_SPEED=$(echo "scale=2; 10 / ${READ_DURATION}" | bc)
        log_success "Read speed: ${READ_SPEED} MB/s"
        ((TEST_PASSED++))
    else
        log_error "Read speed test failed"
        ((TEST_FAILED++))
    fi

    # Cleanup
    rm -f "${WRITE_TEST_FILE}"
else
    log_error "Write speed test failed"
    ((TEST_FAILED++))
fi

# Test 14: Check if required subdirectories exist
echo
log_info "Checking required subdirectories..."

for DIR in "recordings" "backups" "tmp"; do
    if [ -d "${MOUNT_POINT}/${DIR}" ]; then
        log_success "Directory exists: ${DIR}/"
        ((TEST_PASSED++))
    else
        log_warning "Directory missing: ${DIR}/ (will be created automatically)"
        mkdir -p "${MOUNT_POINT}/${DIR}"
    fi
done

###############################################################################
# Test Results Summary
###############################################################################

echo
log_info "======================================================================"
log_info "Test Results Summary"
log_info "======================================================================"
echo
log_info "Tests passed: ${GREEN}${TEST_PASSED}${NC}"
log_info "Tests failed: ${RED}${TEST_FAILED}${NC}"
echo

if [ ${TEST_FAILED} -eq 0 ]; then
    log_success "All tests passed! Storage Box is ready for B3LB."
    echo
    log_info "Mount Information:"
    df -h "${MOUNT_POINT}"
    echo
    exit 0
else
    log_error "Some tests failed. Please review the errors above."
    echo
    log_info "Troubleshooting tips:"
    log_info "1. Check if Storage Box is mounted: mountpoint ${MOUNT_POINT}"
    log_info "2. Verify credentials in /root/.storagebox-credentials"
    log_info "3. Check network connectivity to Storage Box host"
    log_info "4. Review systemd mount status: systemctl status mnt-b3lb\\x2drecordings.mount"
    echo
    exit 1
fi
