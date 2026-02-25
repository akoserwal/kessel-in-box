#!/bin/bash
# Kessel-in-a-Box: Deployment Validation Script
# Quick validation of deployment health

set -e

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
CHECKS=0
PASSED=0
FAILED=0

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_fail() { echo -e "${RED}[✗]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[⚠]${NC} $1"; }

# Check function
check() {
    local name=$1
    local command=$2

    ((CHECKS++))
    echo -n "  Checking $name ... "

    if eval "$command" &>/dev/null; then
        echo -e "${GREEN}✓${NC}"
        ((PASSED++))
        return 0
    else
        echo -e "${RED}✗${NC}"
        ((FAILED++))
        return 1
    fi
}

# Banner
cat << "EOF"
╔════════════════════════════════════════════════════════════╗
║                                                            ║
║        Kessel-in-a-Box: Deployment Validation              ║
║                                                            ║
╚════════════════════════════════════════════════════════════╝
EOF

echo ""
log_info "Validating Kessel-in-a-Box deployment..."
echo ""

# 1. Docker Check
echo -e "${BLUE}=== Docker Environment ===${NC}"
check "Docker installed" "command -v docker"
check "Docker running" "docker ps"
check "Kessel network exists" "docker network inspect kessel-network"
echo ""

# 2. Container Check
echo -e "${BLUE}=== Containers Running ===${NC}"
check "postgres-rbac" "docker ps --filter 'name=kessel-postgres-rbac' --format '{{.Names}}' | grep -q kessel-postgres-rbac"
check "postgres-inventory" "docker ps --filter 'name=kessel-postgres-inventory' --format '{{.Names}}' | grep -q kessel-postgres-inventory"
check "postgres-spicedb" "docker ps --filter 'name=kessel-postgres-spicedb' --format '{{.Names}}' | grep -q kessel-postgres-spicedb"
check "spicedb" "docker ps --filter 'name=kessel-spicedb' --format '{{.Names}}' | grep -q kessel-spicedb"
check "kessel-relations-api" "docker ps --filter 'name=kessel-relations-api' --format '{{.Names}}' | grep -q kessel-relations-api"
check "kessel-inventory-api" "docker ps --filter 'name=kessel-inventory-api' --format '{{.Names}}' | grep -q kessel-inventory-api"
check "insights-rbac" "docker ps --filter 'name=insights-rbac' --format '{{.Names}}' | grep -q insights-rbac"
check "insights-host-inventory" "docker ps --filter 'name=insights-host-inventory' --format '{{.Names}}' | grep -q insights-host-inventory"
echo ""

# 3. Database Check
echo -e "${BLUE}=== Database Connectivity ===${NC}"
check "RBAC database" "docker exec kessel-postgres-rbac pg_isready -U rbac"
check "Inventory database" "docker exec kessel-postgres-inventory pg_isready -U inventory"
check "SpiceDB database" "docker exec kessel-postgres-spicedb pg_isready -U spicedb"
echo ""

# 4. Service Health Check
echo -e "${BLUE}=== Service Health ===${NC}"
check "SpiceDB health" "curl -sf http://localhost:8443/healthz | grep -q SERVING"
check "Kessel Relations API health" "grpcurl -plaintext localhost:9001 grpc.health.v1.Health/Check"
check "Kessel Inventory API health" "curl -sf http://localhost:8083/api/kessel/v1/livez"
check "Insights RBAC health" "curl -sf http://localhost:8080/api/rbac/v1/status/"
check "Insights Host Inventory health" "curl -sf http://localhost:8081/health"
echo ""

# 5. Port Accessibility Check
echo -e "${BLUE}=== Port Accessibility ===${NC}"
check "Port 5432 (postgres-rbac)" "nc -z localhost 5432"
check "Port 5433 (postgres-inventory)" "nc -z localhost 5433"
check "Port 5434 (postgres-spicedb)" "nc -z localhost 5434"
check "Port 8080 (insights-rbac)" "nc -z localhost 8080"
check "Port 8081 (insights-inventory)" "nc -z localhost 8081"
check "Port 8082 (kessel-relations)" "nc -z localhost 8082"
check "Port 8083 (kessel-inventory)" "nc -z localhost 8083"
check "Port 50051 (spicedb-grpc)" "nc -z localhost 50051"
check "Port 8443 (spicedb-http)" "nc -z localhost 8443"
echo ""

# Summary
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                   Validation Summary                       ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "  Total Checks: $CHECKS"
echo -e "  Passed:       ${GREEN}$PASSED${NC}"
echo -e "  Failed:       ${RED}$FAILED${NC}"
echo ""

if [ $FAILED -eq 0 ]; then
    log_success "All validation checks passed!"
    echo ""
    log_info "Your Kessel-in-a-Box deployment is healthy and ready to use."
    echo ""
    echo "Next steps:"
    echo "  - Run tests:        ./scripts/run-all-tests.sh"
    echo "  - View logs:        docker logs <container-name> -f"
    echo "  - Make API calls:   See QUICKSTART.md for examples"
    echo ""
    exit 0
else
    log_fail "Some validation checks failed!"
    echo ""
    log_warn "Troubleshooting steps:"
    echo "  1. Check container logs: docker logs <container-name>"
    echo "  2. Restart failed services: docker restart <container-name>"
    echo "  3. Redeploy if needed: ./scripts/deploy.sh"
    echo "  4. Check QUICKSTART.md for detailed troubleshooting"
    echo ""
    exit 1
fi
