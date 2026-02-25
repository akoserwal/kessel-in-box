# Kessel-in-a-Box

**Complete local development environment for Kessel authorization platform**

A production-aligned, event-driven authorization system demonstrating Google Zanzibar-based Relationship-Based Access Control (ReBAC) with Change Data Capture (CDC) integration.

## What is Kessel-in-a-Box?

Kessel-in-a-box is a **complete, working implementation** of Red Hat's Kessel platform that runs entirely on your local machine using real upstream service images. It demonstrates:

- **ReBAC Authorization** using SpiceDB (Google Zanzibar)
- **Event-Driven Architecture** with Kafka CDC pipeline
- **Microservices Integration** with Kessel APIs
- **Real Application Patterns** (RBAC and Host Inventory)
- **Production-Aligned Architecture** matching Red Hat's hosted deployment

All services use real upstream images from `quay.io/cloudservices` and other official sources — no mocks.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   APPLICATION LAYER                         │
│  insights-rbac (8080)      insights-host-inventory (8081)   │
│  quay.io/cloudservices/rbac  quay.io/cloudservices/         │
│                              insights-inventory             │
└─────────────────┬─────────────────────┬─────────────────────┘
                  │ CDC                 │ CDC (Kafka ingress)
                  ↓                     ↓
┌─────────────────────────────────────────────────────────────┐
│                    EVENT STREAMING LAYER                    │
│  PostgreSQL → Debezium → Kafka → Consumers                  │
└─────────────────┬─────────────────────┬─────────────────────┘
                  │                     │
                  ↓                     ↓
┌─────────────────────────────────────────────────────────────┐
│                    KESSEL PLATFORM LAYER                    │
│  kessel-relations-api (8082/9001)  kessel-inventory-api     │
│                                    (8083/9002)              │
└─────────────────────────────┬───────────────────────────────┘
                              │ gRPC
                              ↓
┌─────────────────────────────────────────────────────────────┐
│              AUTHORIZATION ENGINE LAYER                     │
│  SpiceDB (50051/8443) → PostgreSQL (5434)                   │
└─────────────────────────────────────────────────────────────┘
```

## Quick Start

### Prerequisites

- Docker/Podman and Docker Compose V2
- `grpcurl` (for gRPC health checks and demo)
- 8GB RAM minimum, 20GB disk space

### Deploy Everything

```bash
# Check prerequisites and port availability first
./scripts/precheck.sh

# Deploy all services
./scripts/deploy.sh
```

### Run the Demo

```bash
# Set up demo data (verifies all services)
./scripts/demo-setup.sh

# Run interactive authorization demo (5 scenarios)
./scripts/demo-run.sh
```

## Service Endpoints

### Insights Services (Application Layer)

| Service | HTTP | Purpose |
|---------|------|---------|
| insights-rbac | `http://localhost:8080` | RBAC management (workspaces, roles, groups) |
| insights-host-inventory | `http://localhost:8081` | Host inventory (read-only REST; write via Kafka) |

All requests to insights services require an `x-rh-identity` header (base64-encoded JSON):

```bash
IDENTITY=$(echo -n '{"identity":{"account_number":"12345","org_id":"12345","type":"User","auth_type":"basic-auth","user":{"username":"admin","email":"admin@example.com","is_org_admin":true}}}' | base64)
```

**RBAC API paths:**

```bash
# Health / status
curl http://localhost:8080/api/rbac/v1/status/

# List workspaces (v2 API)
curl -H "x-rh-identity: $IDENTITY" http://localhost:8080/api/rbac/v2/workspaces/

# Create a workspace
curl -X POST http://localhost:8080/api/rbac/v2/workspaces/ \
  -H "Content-Type: application/json" \
  -H "x-rh-identity: $IDENTITY" \
  -d '{"name": "my-workspace"}'

# List groups / roles
curl -H "x-rh-identity: $IDENTITY" http://localhost:8080/api/rbac/v1/groups/
curl -H "x-rh-identity: $IDENTITY" http://localhost:8080/api/rbac/v1/roles/
```

**Host Inventory API paths:**

```bash
# Health check (returns 200 with empty body)
curl -sf http://localhost:8081/health

# List hosts
curl -H "x-rh-identity: $IDENTITY" http://localhost:8081/api/inventory/v1/hosts

# Get host tags
curl -H "x-rh-identity: $IDENTITY" http://localhost:8081/api/inventory/v1/tags

# Note: Host creation goes via Kafka ingress (platform.inventory.host-ingress topic),
# not via REST POST. The REST API is read-only for hosts.
```

### Kessel Platform (Authorization Layer)

Both Kessel APIs are **gRPC-primary**. HTTP is available for some endpoints.

| Service | HTTP | gRPC | Purpose |
|---------|------|------|---------|
| kessel-relations-api | `http://localhost:8082` | `localhost:9001` | Relationship management |
| kessel-inventory-api | `http://localhost:8083` | `localhost:9002` | Resource inventory + authz proxy |

```bash
# Relations API — gRPC health
grpcurl -plaintext localhost:9001 grpc.health.v1.Health/Check

# Create a relationship tuple
grpcurl -plaintext -d '{"tuples":[{"resource":{"type":{"namespace":"rbac","name":"group"},"id":"engineering"},"relation":"t_member","subject":{"subject":{"type":{"namespace":"rbac","name":"principal"},"id":"alice"}}}],"upsert":true}' \
  localhost:9001 kessel.relations.v1beta1.KesselTupleService/CreateTuples

# Check a permission (rbac/* resources)
grpcurl -plaintext -d '{"resource":{"type":{"namespace":"rbac","name":"workspace"},"id":"production"},"relation":"inventory_host_view","subject":{"subject":{"type":{"namespace":"rbac","name":"principal"},"id":"alice"}}}' \
  localhost:9001 kessel.relations.v1beta1.KesselCheckService/Check

# Inventory API — gRPC health
grpcurl -plaintext localhost:9002 grpc.health.v1.Health/Check

# Check a permission (hbi/* resources — routes through Inventory API → Relations API)
grpcurl -plaintext -d '{"object":{"resource_type":"host","resource_id":"web-server-01","reporter":{"type":"hbi"}},"relation":"view","subject":{"resource":{"resource_type":"principal","resource_id":"alice","reporter":{"type":"rbac"}}}}' \
  localhost:9002 kessel.inventory.v1beta2.KesselInventoryService/Check

# Inventory API HTTP — livez endpoint
curl http://localhost:8083/api/kessel/v1/livez
```

### Authorization Engine

```bash
# SpiceDB health
curl http://localhost:8443/healthz

# SpiceDB gRPC (used internally by kessel-relations-api)
# localhost:50051

# SpiceDB Prometheus metrics
curl http://localhost:9090/metrics | head -20
```

### Infrastructure

| Service | Port | Purpose |
|---------|------|---------|
| PostgreSQL RBAC | `5432` | Insights RBAC database |
| PostgreSQL Inventory | `5433` | Insights HBI database (`hbi` schema) |
| PostgreSQL SpiceDB | `5434` | SpiceDB relationship storage |
| Kafka | `9092` | Event broker |
| Kafka Connect | `8085` | Debezium REST API |
| Kafka UI | `8086` | Web UI — `http://localhost:8086` |
| Zookeeper | `2181` | Kafka coordination |
| Redis | `6379` | RBAC Celery broker |

### Observability

| Service | Port | Purpose |
|---------|------|---------|
| Prometheus | `9091` | Metrics — `http://localhost:9091` |
| Grafana | `3000` | Dashboards — `http://localhost:3000` (admin/admin) |
| AlertManager | `9093` | Alerts — `http://localhost:9093` |

### Monitoring Dashboard

```bash
# Start the local monitoring dashboard
cd monitoring && python3 app.py

# Opens at http://localhost:8888
```

## Data Flows

### Flow 1: Workspace Creation (RBAC → CDC → SpiceDB)

```
User → POST /api/rbac/v2/workspaces/ (x-rh-identity required)
    ↓ INSERT INTO rbac.workspaces
PostgreSQL RBAC (wal_level=logical)
    ↓ WAL → Debezium (rbac-connector)
Kafka Topic: rbac.workspaces.events
    ↓ rbac-consumer (Go)
kessel-relations-api gRPC: CreateTuples
    ↓ WriteRelationships()
SpiceDB
```

**Latency**: 2–5 seconds (eventual consistency via CDC)

### Flow 2: Host Registration (Kafka Ingress)

```
Host agent → Kafka Topic: platform.inventory.host-ingress
    ↓ inv_mq_service.py (MQ consumer — optional)
insights-host-inventory: process and persist
    ↓ INSERT INTO hbi.hosts
PostgreSQL Inventory (wal_level=logical)
    ↓ WAL → Debezium (inventory-connector)
Kafka Topic: platform.inventory.events
    ↓ inventory-consumer
kessel-inventory-api gRPC: ReportResource
    ↓ CreateTuples() in SpiceDB
SpiceDB
```

**Note**: The HBI REST API (`/api/inventory/v1/hosts`) is read-only. Host ingestion goes via Kafka.

### Flow 3: Permission Check

```
App → kessel-inventory-api gRPC: Check (hbi/* resources)
   OR kessel-relations-api gRPC: Check (rbac/* resources)
    ↓
kessel-relations-api → SpiceDB: CheckPermission
    ↓ Graph traversal through relationship tuples
SpiceDB → ALLOWED_TRUE / ALLOWED_FALSE
```

**Latency**: 5–50ms

## Testing

```bash
# Full test suite
./scripts/run-all-tests.sh

# Service health validation
./scripts/validate.sh

# Comprehensive flow verification
./scripts/verify-all-flows.sh
```

## Management

### View Logs

```bash
# All services
docker compose \
  -f compose/docker-compose.yml \
  -f compose/docker-compose.kessel.yml \
  -f compose/docker-compose.kafka.yml \
  -f compose/docker-compose.insights.yml \
  logs -f

# Specific service
docker logs -f insights-rbac
docker logs -f insights-host-inventory
docker logs -f kessel-relations-api
docker logs -f kessel-inventory-api
```

### Database Access

```bash
# RBAC database
docker exec -it kessel-postgres-rbac psql -U rbac -d rbac

# Inventory database (HBI uses hbi schema)
docker exec -it kessel-postgres-inventory psql -U inventory -d inventory
# \dt hbi.*   — list HBI tables (created by Alembic)

# SpiceDB database
docker exec -it kessel-postgres-spicedb psql -U spicedb -d spicedb
```

### Monitor CDC

```bash
# Debezium connector status
curl http://localhost:8085/connectors | jq
curl http://localhost:8085/connectors/rbac-postgres-connector/status | jq

# Restart a connector
curl -X POST http://localhost:8085/connectors/rbac-postgres-connector/restart

# Kafka UI
open http://localhost:8086
```

## Troubleshooting

### Services won't start

```bash
docker logs <container-name>
docker ps --format "table {{.Names}}\t{{.Status}}"
```

### HBI returns 401/400 errors

The real HBI requires a valid `x-rh-identity` header on every request. The header must include `auth_type`:

```bash
IDENTITY=$(echo -n '{"identity":{"account_number":"12345","org_id":"12345","type":"User","auth_type":"basic-auth","user":{"username":"admin","email":"admin@example.com","is_org_admin":true}}}' | base64)
curl -H "x-rh-identity: $IDENTITY" http://localhost:8081/api/inventory/v1/hosts
```

### HBI returns 405 on POST /hosts

The real HBI REST API is **read-only**. Host creation is only supported via Kafka ingress on the `platform.inventory.host-ingress` topic. Use GET to list hosts:

```bash
curl -H "x-rh-identity: $IDENTITY" http://localhost:8081/api/inventory/v1/hosts
```

### RBAC returns 404 on /api/v1/workspaces

RBAC workspaces are on the **v2** API. Groups and roles remain on v1:

```bash
# Workspaces — v2
curl -H "x-rh-identity: $IDENTITY" http://localhost:8080/api/rbac/v2/workspaces/

# Groups, roles — v1
curl -H "x-rh-identity: $IDENTITY" http://localhost:8080/api/rbac/v1/groups/
```

### Kessel APIs return 404 on /health

Both Kessel APIs are gRPC-primary — `curl .../health` returns 404. Use gRPC or the correct HTTP paths:

```bash
grpcurl -plaintext localhost:9001 grpc.health.v1.Health/Check  # Relations API
grpcurl -plaintext localhost:9002 grpc.health.v1.Health/Check  # Inventory API
curl http://localhost:8083/api/kessel/v1/livez                 # Inventory API HTTP livez
curl http://localhost:8080/api/rbac/v1/status/                 # RBAC status
```

### CDC not working

```bash
# Check replication slots
docker exec kessel-postgres-rbac psql -U rbac -d rbac -c "SELECT * FROM pg_replication_slots;"
docker exec kessel-postgres-inventory psql -U inventory -d inventory -c "SELECT * FROM pg_replication_slots;"

# Verify WAL level
docker exec kessel-postgres-inventory psql -U inventory -c "SHOW wal_level;"
# Should return: logical
```

## References

- [project-kessel/relations-api](https://github.com/project-kessel/relations-api)
- [project-kessel/inventory-api](https://github.com/project-kessel/inventory-api)
- [RedHatInsights/insights-rbac](https://github.com/RedHatInsights/insights-rbac)
- [RedHatInsights/insights-host-inventory](https://github.com/RedHatInsights/insights-host-inventory)
- [SpiceDB Documentation](https://authzed.com/docs/spicedb)
- [Debezium Documentation](https://debezium.io/documentation/)
- [Google Zanzibar Paper](https://research.google/pubs/pub48190/)
