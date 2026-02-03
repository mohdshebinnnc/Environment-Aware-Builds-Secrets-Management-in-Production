#!/bin/bash

##############################################################################
# Smoke Test Script
# Runs basic health checks after deployment to ensure the application
# is functioning correctly.
##############################################################################

set -e

# Configuration
HEALTH_ENDPOINT="${HEALTH_ENDPOINT:-http://localhost:3000/health}"
MAX_RETRIES=5
RETRY_DELAY=5

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${YELLOW}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Test 1: Health endpoint
test_health_endpoint() {
    log_info "Testing health endpoint..."
    
    for i in $(seq 1 $MAX_RETRIES); do
        if curl -f -s "$HEALTH_ENDPOINT" > /dev/null 2>&1; then
            log_success "Health endpoint is responding"
            return 0
        else
            log_info "Attempt $i/$MAX_RETRIES failed, retrying in ${RETRY_DELAY}s..."
            sleep $RETRY_DELAY
        fi
    done
    
    log_error "Health endpoint failed after $MAX_RETRIES attempts"
    return 1
}

# Test 2: Response time
test_response_time() {
    log_info "Testing response time..."
    
    RESPONSE_TIME=$(curl -o /dev/null -s -w '%{time_total}\n' "$HEALTH_ENDPOINT")
    RESPONSE_MS=$(echo "$RESPONSE_TIME * 1000" | bc)
    
    log_info "Response time: ${RESPONSE_MS}ms"
    
    # Fail if response time > 2000ms
    if (( $(echo "$RESPONSE_TIME > 2.0" | bc -l) )); then
        log_error "Response time too slow: ${RESPONSE_MS}ms"
        return 1
    fi
    
    log_success "Response time acceptable"
    return 0
}

# Test 3: Health check content
test_health_content() {
    log_info "Testing health check response content..."
    
    RESPONSE=$(curl -s "$HEALTH_ENDPOINT")
    
    # Check if response contains expected fields
    if echo "$RESPONSE" | grep -q "status"; then
        log_success "Health response contains status field"
    else
        log_error "Health response missing status field"
        return 1
    fi
    
    # Check if status is OK
    if echo "$RESPONSE" | grep -q '"status":"OK"' || echo "$RESPONSE" | grep -q '"status": "OK"'; then
        log_success "Application status is OK"
    else
        log_error "Application status is not OK"
        echo "Response: $RESPONSE"
        return 1
    fi
    
    return 0
}

# Main
main() {
    echo ""
    log_info "🧪 Running smoke tests..."
    echo ""
    
    FAILED=0
    
    # Run tests
    test_health_endpoint || FAILED=$((FAILED + 1))
    test_response_time || FAILED=$((FAILED + 1))
    test_health_content || FAILED=$((FAILED + 1))
    
    echo ""
    if [ $FAILED -eq 0 ]; then
        log_success "🎉 All smoke tests passed!"
        exit 0
    else
        log_error "❌ $FAILED test(s) failed"
        exit 1
    fi
}

main "$@"
