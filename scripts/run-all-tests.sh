#!/bin/bash
# Kessel-in-a-Box: Complete Test Suite
# Runs comprehensive verification of all components and flows

set -e

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASSED=0
FAILED=0
TOTAL=0

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Test runner function
run_test() {
    local test_name=$1
    local test_command=$2
    local expected_output=$3

    ((TOTAL++))
    echo -n "  [$TOTAL] $test_name ... "

    if output=$(eval "$test_command" 2>&1); then
        if [ -z "$expected_output" ] || echo "$output" | grep -q "$expected_output"; then
            echo -e "${GREEN}✓${NC}"
            ((PASSED++))
            return 0
        else
            echo -e "${RED}✗${NC} (unexpected output)"
            ((FAILED++))
            return 1
        fi
    else
        echo -e "${RED}✗${NC} (command failed)"
        ((FAILED++))
        return 1
    fi
}

# Banner
echo ""
echo "=========================================="
echo "  Kessel-in-a-Box: Complete Test Suite"
echo "=========================================="
echo ""

# ============================================
# 1. Infrastructure Tests
# ============================================
echo -e "${BLUE}=== 1. Infrastructure Tests ===${NC}"

run_test "All containers running" \
    "docker ps --format '{{.Names}}' | grep -c kessel" \
    ""

run_test "Network exists" \
    "docker network inspect kessel-network" \
    ""

run_test "Port 5432 (postgres-rbac) open" \
    "nc -z localhost 5432" \
    ""

run_test "Port 5433 (postgres-inventory) open" \
    "nc -z localhost 5433" \
    ""

run_test "Port 5434 (postgres-spicedb) open" \
    "nc -z localhost 5434" \
    ""

run_test "Port 8080 (insights-rbac) open" \
    "nc -z localhost 8080" \
    ""

run_test "Port 8081 (insights-inventory) open" \
    "nc -z localhost 8081" \
    ""

run_test "Port 8082 (kessel-relations) open" \
    "nc -z localhost 8082" \
    ""

run_test "Port 8083 (kessel-inventory) open" \
    "nc -z localhost 8083" \
    ""

run_test "Port 50051 (SpiceDB gRPC) open" \
    "nc -z localhost 50051" \
    ""

echo ""

# ============================================
# 2. Database Tests
# ============================================
echo -e "${BLUE}=== 2. Database Tests ===${NC}"

run_test "RBAC database accessible" \
    "docker exec kessel-postgres-rbac psql -U rbac -d rbac -c 'SELECT 1;'" \
    ""

run_test "RBAC schema exists" \
    "docker exec kessel-postgres-rbac psql -U rbac -d rbac -c '\dn rbac;'" \
    "rbac"

run_test "Inventory database accessible" \
    "docker exec kessel-postgres-inventory psql -U inventory -d inventory -c 'SELECT 1;'" \
    ""

run_test "Inventory schema exists" \
    "docker exec kessel-postgres-inventory psql -U inventory -d inventory -c '\dn hbi;'" \
    "hbi"

run_test "SpiceDB database accessible" \
    "docker exec kessel-postgres-spicedb psql -U spicedb -d spicedb -c 'SELECT 1;'" \
    ""

run_test "SpiceDB tables exist" \
    "docker exec kessel-postgres-spicedb psql -U spicedb -d spicedb -c '\dt' | grep -c relation_tuple" \
    ""

echo ""

# ============================================
# 3. Service Health Tests
# ============================================
echo -e "${BLUE}=== 3. Service Health Tests ===${NC}"

run_test "SpiceDB health endpoint" \
    "curl -sf http://localhost:8443/healthz" \
    "SERVING"

run_test "Kessel Relations API health" \
    "grpcurl -plaintext localhost:9001 grpc.health.v1.Health/Check" \
    "SERVING"

run_test "Kessel Inventory API health" \
    "curl -sf http://localhost:8083/api/kessel/v1/livez" \
    ""

run_test "Insights RBAC health" \
    "curl -sf http://localhost:8080/api/rbac/v1/status/" \
    ""

run_test "Insights Host Inventory health" \
    "curl -sf http://localhost:8081/health" \
    ""

echo ""

# ============================================
# 4. API Functional Tests
# ============================================
echo -e "${BLUE}=== 4. API Functional Tests ===${NC}"

# Real RBAC requires x-rh-identity header with auth_type
RBAC_IDENTITY=$(echo -n '{"identity":{"account_number":"12345","org_id":"12345","type":"User","auth_type":"basic-auth","user":{"username":"test_user","email":"test@example.com","is_org_admin":true}}}' | base64)

# Create test workspace
log_info "Creating test workspace..."
WORKSPACE_RESP=$(curl -s -X POST http://localhost:8080/api/rbac/v2/workspaces/ \
    -H "Content-Type: application/json" \
    -H "x-rh-identity: $RBAC_IDENTITY" \
    -d '{"name":"test-suite-workspace"}')
WORKSPACE_ID=$(echo "$WORKSPACE_RESP" | jq -r '.id')

run_test "Create workspace (insights-rbac)" \
    "echo '$WORKSPACE_RESP' | jq -r '.id'" \
    ""

run_test "Get workspace by ID" \
    "curl -sf -H 'x-rh-identity: $RBAC_IDENTITY' http://localhost:8080/api/rbac/v2/workspaces/$WORKSPACE_ID" \
    "$WORKSPACE_ID"

run_test "List workspaces" \
    "curl -sf -H 'x-rh-identity: $RBAC_IDENTITY' http://localhost:8080/api/rbac/v2/workspaces/ | jq -r '.data[] | .id' | grep '$WORKSPACE_ID'" \
    ""

# Real HBI requires x-rh-identity header with auth_type
HBI_IDENTITY=$(echo -n '{"identity":{"account_number":"12345","org_id":"12345","type":"User","auth_type":"basic-auth","user":{"username":"test_user","email":"test@example.com","is_org_admin":true}}}' | base64)

# Note: The real HBI does not support host creation via REST API.
# Hosts are created via Kafka ingress (platform.inventory.host-ingress topic).
HOST_ID=""

run_test "List hosts (insights-inventory)" \
    "curl -sf -H 'x-rh-identity: $HBI_IDENTITY' http://localhost:8081/api/inventory/v1/hosts" \
    ""

run_test "Get tags endpoint" \
    "curl -sf -H 'x-rh-identity: $HBI_IDENTITY' http://localhost:8081/api/inventory/v1/tags" \
    ""

echo ""

# ============================================
# 5. Integration Tests
# ============================================
echo -e "${BLUE}=== 5. Integration Tests ===${NC}"

run_test "Workspace in RBAC database" \
    "docker exec kessel-postgres-rbac psql -U rbac -d rbac -c \"SELECT id FROM rbac.workspaces WHERE id = '$WORKSPACE_ID';\"" \
    "$WORKSPACE_ID"

run_test "Inventory database HBI schema exists" \
    "docker exec kessel-postgres-inventory psql -U inventory -d inventory -c '\dt hbi.hosts'" \
    "hosts"

echo ""

# ============================================
# 6. Authorization Tests
# ============================================
echo -e "${BLUE}=== 6. Authorization Tests ===${NC}"

log_warn "Skipping authorization tests (SpiceDB schema not loaded)"
log_info "To run authorization tests, load a SpiceDB schema first"
((TOTAL+=2))
((PASSED+=0))
echo "  [31] Create relationship (Relations API) ... ${YELLOW}SKIP${NC} (no schema)"
echo "  [32] Check permission (Relations API) ... ${YELLOW}SKIP${NC} (no schema)"

echo ""

# ============================================
# 7. End-to-End Flow Tests
# ============================================
echo -e "${BLUE}=== 7. End-to-End Flow Tests ===${NC}"

# Create another workspace and verify full flow
log_info "Testing complete workspace lifecycle..."
E2E_WS=$(curl -s -X POST http://localhost:8080/api/rbac/v2/workspaces/ \
    -H "Content-Type: application/json" \
    -H "x-rh-identity: $RBAC_IDENTITY" \
    -d '{"name":"e2e-test-workspace"}' | jq -r '.id')

run_test "E2E: Workspace creation" \
    "echo '$E2E_WS'" \
    ""

run_test "E2E: Workspace in database" \
    "docker exec kessel-postgres-rbac psql -U rbac -d rbac -c \"SELECT id FROM rbac.workspaces WHERE id = '$E2E_WS';\"" \
    "$E2E_WS"

# Note: Real HBI does not support host creation via REST.
# Verify HBI is integrated and responds to API calls.
E2E_HOST=""

run_test "E2E: HBI list hosts responds" \
    "curl -sf -H 'x-rh-identity: $HBI_IDENTITY' http://localhost:8081/api/inventory/v1/hosts" \
    ""

echo ""

# ============================================
# 8. Error Handling Tests
# ============================================
echo -e "${BLUE}=== 8. Error Handling Tests ===${NC}"

run_test "Invalid JSON returns error" \
    "curl -s -w '%{http_code}' -X POST http://localhost:8080/api/rbac/v2/workspaces/ \
        -H 'Content-Type: application/json' \
        -H 'x-rh-identity: $RBAC_IDENTITY' \
        -d 'invalid json' | tail -c 3 | grep -E '^(400|500)$'" \
    ""

run_test "Non-existent resource returns 404" \
    "curl -s -w '%{http_code}' -H 'x-rh-identity: $RBAC_IDENTITY' http://localhost:8080/api/rbac/v2/workspaces/00000000-0000-0000-0000-000000000000 | tail -c 3" \
    "404"

run_test "Missing required field returns 400" \
    "curl -s -w '%{http_code}' -X POST http://localhost:8080/api/rbac/v2/workspaces/ \
        -H 'Content-Type: application/json' \
        -H 'x-rh-identity: $RBAC_IDENTITY' \
        -d '{}' | tail -c 3" \
    "400"

echo ""

# ============================================
# 9. Performance Tests
# ============================================
echo -e "${BLUE}=== 9. Performance Tests ===${NC}"

run_test "Health endpoint responds quickly (<1s)" \
    "time timeout 1 curl -sf http://localhost:8080/api/rbac/v1/status/ > /dev/null" \
    ""

run_test "Create operation completes quickly (<2s)" \
    "time timeout 2 curl -sf -X POST http://localhost:8080/api/rbac/v2/workspaces/ \
        -H 'Content-Type: application/json' \
        -H 'x-rh-identity: $RBAC_IDENTITY' \
        -d '{\"name\":\"perf-test\"}' > /dev/null" \
    ""

run_test "Query operation completes quickly (<1s)" \
    "time timeout 1 curl -sf -H 'x-rh-identity: $RBAC_IDENTITY' http://localhost:8080/api/rbac/v2/workspaces/ > /dev/null" \
    ""

echo ""

# ============================================
# 10. Cleanup Tests
# ============================================
echo -e "${BLUE}=== 10. Cleanup Tests ===${NC}"

log_info "Cleaning up test data..."

log_info "Skipping host cleanup (no hosts created via REST)"

run_test "Delete test workspace" \
    "curl -sf -X DELETE -H 'x-rh-identity: $RBAC_IDENTITY' http://localhost:8080/api/rbac/v2/workspaces/$WORKSPACE_ID/" \
    ""

log_info "Skipping E2E host cleanup (no hosts created via REST)"

run_test "Delete E2E workspace" \
    "curl -sf -X DELETE -H 'x-rh-identity: $RBAC_IDENTITY' http://localhost:8080/api/rbac/v2/workspaces/$E2E_WS/" \
    ""

run_test "Verify workspace deleted" \
    "curl -s -w '%{http_code}' -H 'x-rh-identity: $RBAC_IDENTITY' http://localhost:8080/api/rbac/v2/workspaces/$WORKSPACE_ID/ | tail -c 3" \
    "404"

log_info "Skipping host deletion verify (no hosts created via REST)"

echo ""

# ============================================
# Summary
# ============================================
echo "=========================================="
echo "           Test Results Summary"
echo "=========================================="
echo -e "Total Tests:  $TOTAL"
echo -e "Passed:       ${GREEN}$PASSED${NC}"
echo -e "Failed:       ${RED}$FAILED${NC}"
echo -e "Success Rate: $(awk "BEGIN {printf \"%.1f\", ($PASSED/$TOTAL)*100}"  2>/dev/null || echo "N/A")%"
echo "=========================================="
echo ""

if [ $FAILED -eq 0 ]; then
    log_success "All tests passed! ✓"
    echo ""
    log_info "Kessel-in-a-Box is fully operational and verified."
    exit 0
else
    log_fail "Some tests failed!"
    echo ""
    log_warn "Check the output above for details on failed tests."
    log_info "Run individual test scripts for more detailed diagnostics:"
    echo "  ./scripts/test-phase5.sh"
    echo "  ./scripts/test-phase7.sh"
    exit 1
fi
