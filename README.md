# Kessel-in-a-Box 📦

**Complete local development environment for Kessel authorization platform**

A production-aligned, event-driven authorization system demonstrating Google Zanzibar-based Relationship-Based Access Control (ReBAC) with Change Data Capture (CDC) integration.

## 🎯 What is Kessel-in-a-Box?

Kessel-in-a-box is a **complete, working implementation** of Red Hat's Kessel platform that runs entirely on your local machine. It demonstrates:

- ✅ **ReBAC Authorization** using SpiceDB (Google Zanzibar)
- ✅ **Event-Driven Architecture** with Kafka CDC pipeline
- ✅ **Microservices Integration** with Kessel APIs
- ✅ **Real Application Patterns** (RBAC and Host Inventory)
- ✅ **Production-Aligned Architecture** matching Red Hat's hosted deployment



## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   APPLICATION LAYER                         │
│  insights-rbac (8080)      insights-host-inventory (8081)   │
└─────────────────┬─────────────────────┬─────────────────────┘
                  │                     │
                  ↓ CDC                 ↓ CDC + Direct API
┌─────────────────────────────────────────────────────────────┐
│                    EVENT STREAMING LAYER                    │
│  PostgreSQL → Debezium → Kafka → Consumers                  │
└─────────────────┬─────────────────────┬─────────────────────┘
                  │                     │
                  ↓                     ↓
┌─────────────────────────────────────────────────────────────┐
│                    KESSEL PLATFORM LAYER                    │
│  kessel-relations-api (8082)  kessel-inventory-api (8083)   │
└─────────────────────────────┬───────────────────────────────┘
                              │
                              ↓ gRPC
┌─────────────────────────────────────────────────────────────┐
│              AUTHORIZATION ENGINE LAYER                     │
│  SpiceDB (50051) → PostgreSQL (5434)                        │
└─────────────────────────────────────────────────────────────┘
```

## 🚀 Quick Start

### Prerequisites

- Docker/Podman and Docker Compose V2
- 8GB RAM minimum
- 20GB disk space

### Pre-Deployment Check (Recommended)

Verify your system is ready before deploying:

```bash
# Check prerequisites and port availability
./scripts/precheck.sh

# If ports are blocked, auto-cleanup
./scripts/precheck.sh --kill
```

This verifies Docker, Podman, Docker Compose, and checks that all required ports are available.

### Deploy Everything (One Command)

```bash
# Deploy all phases (5-10 min) - RECOMMENDED
./scripts/deploy.sh

```

**What deploys:**
- Kessel Services (relations-api, inventory-api, SpiceDB)
- CDC Infrastructure (Kafka, Debezium, CDC consumers) ← Included!
- Insights Services (rbac, host-inventory)

### Deploy Individual Phases (Alternative)

# Test everything
```
./scripts/run-all-tests.sh
```

### First API Call

```bash
# Create a workspace
curl -X POST http://localhost:8080/api/v1/workspaces \
  -H "Content-Type: application/json" \
  -d '{"name": "my-workspace", "description": "My first workspace"}'

# Create a host
curl -X POST http://localhost:8081/api/v1/hosts \
  -H "Content-Type: application/json" \
  -d '{"display_name": "my-host", "canonical_facts": {"fqdn": "host.local"}}'

# List workspaces
curl http://localhost:8080/api/v1/workspaces | jq
```

## 📋 What's Included

### Kessel Services

**Core authorization platform**

- **SpiceDB** (50051) - Google Zanzibar authorization engine
- **kessel-relations-api** (8082) - SpiceDB frontend
- **kessel-inventory-api** (8083) - Resource management + authz proxy
- **3 PostgreSQL instances** (5432, 5433, 5434) - Data persistence


### CDC Pipeline

**Event-driven data replication**

- **Kafka + Zookeeper** (9092, 2181) - Event streaming
- **Debezium connectors** (8085) - CDC from PostgreSQL
- **Relations Sink** - RBAC events → Relations API
- **Inventory Consumer** - Inventory events → Inventory API
- **Kafka UI** (8086) - Web interface

### Insights Services

**Application integration examples**

- **insights-rbac** (8080) - Workspace/role management
- **insights-host-inventory** (8081) - Host/asset inventory
- **CDC integration** - Automatic replication to Kessel
- **Dual-write pattern** - Direct API + CDC backup

## 📊 Service Ports

| Service | Port | Purpose |
|---------|------|---------|
| **Insights Services** | | |
| insights-rbac | 8080 | Workspace management |
| insights-host-inventory | 8081 | Host inventory |
| **Kessel Platform** | | |
| kessel-relations-api | 8082 | Authorization API |
| kessel-inventory-api | 8083 | Resource API |
| **Authorization Engine** | | |
| SpiceDB gRPC | 50051 | Zanzibar engine |
| SpiceDB HTTP | 8443 | REST API |
| SpiceDB Metrics | 9090 | Prometheus |
| **Data Layer** | | |
| PostgreSQL RBAC | 5432 | RBAC database |
| PostgreSQL Inventory | 5433 | Inventory database |
| PostgreSQL SpiceDB | 5434 | Authorization data |
| **Event Streaming** | | |
| Kafka | 9092 | Event broker |
| Kafka Connect | 8085 | Debezium REST |
| Kafka UI | 8086 | Web interface |
| Zookeeper | 2181 | Kafka coordination |

## 🔄 Data Flows

### Flow 1: Workspace Creation (CDC Pattern)

```
User → insights-rbac API
    ↓ INSERT INTO rbac.workspaces
PostgreSQL RBAC
    ↓ WAL → Debezium
Kafka Topic: rbac.workspaces.events
    ↓ Consumer
Relations Sink
    ↓ POST /v1/relationships
kessel-relations-api
    ↓ gRPC WriteRelationships()
SpiceDB
```

**Latency**: 2-5 seconds (eventual consistency)

### Flow 2: Host Registration (Dual-Write Pattern)

```
User → insights-host-inventory API
    ├─→ INSERT INTO inventory.hosts (CDC backup)
    │       ↓ WAL → Debezium → Kafka → Inventory Consumer
    │
    └─→ Direct POST /v1/resources to kessel-inventory-api (fast path)
            ↓ Store + CreateTuples()
        PostgreSQL Inventory + SpiceDB
```

**Latency**: < 100ms (synchronous API call)

## 🧪 Testing

### Automated Tests

```bash
# Run complete test suite (infrastructure, APIs, CDC, integration, e2e)
./scripts/run-all-tests.sh
```

### Manual Testing

```bash
# Create workspace and verify CDC
WORKSPACE_ID=$(curl -s -X POST http://localhost:8080/api/v1/workspaces \
  -H "Content-Type: application/json" \
  -d '{"name": "test"}' | jq -r '.id')

# Wait for CDC
sleep 3

# Check Kafka
docker exec kessel-kafka kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic rbac.workspaces.events \
  --from-beginning --max-messages 5 | grep "$WORKSPACE_ID"
```

## 🛠️ Management

### View Logs

```bash
# All services
docker compose -f compose/docker-compose.yml \
               -f compose/docker-compose.kessel.yml \
               -f compose/docker-compose.kafka.yml \
               -f compose/docker-compose.insights.yml logs -f

# Specific service
docker logs -f insights-rbac
docker logs -f kessel-relations-api
docker logs -f kessel-relations-sink
```

### Monitor CDC

```bash
# Kafka UI
open http://localhost:8086

# Debezium connectors
curl http://localhost:8085/connectors | jq

# Connector status
curl http://localhost:8085/connectors/rbac-postgres-connector/status | jq
```

### Database Access

```bash
# RBAC database
docker exec -it kessel-postgres-rbac psql -U rbac -d rbac

# Inventory database
docker exec -it kessel-postgres-inventory psql -U inventory -d inventory

# SpiceDB database
docker exec -it kessel-postgres-spicedb psql -U spicedb -d spicedb
```

## 🔧 Troubleshooting

### Common Issues

**Services won't start**
```bash
# Check logs
docker logs <service-name>

# Check dependencies
docker ps | grep kessel

# Restart
./scripts/setup-phase5.sh restart
```

**CDC not working**
```bash
# Check Kafka
docker ps | grep kafka

# Check Debezium
curl http://localhost:8085/connectors

# Restart connector
curl -X POST http://localhost:8085/connectors/rbac-postgres-connector/restart
```

**Database connection errors**
```bash
# Test connectivity
docker exec kessel-postgres-rbac pg_isready -U rbac
docker exec kessel-postgres-inventory pg_isready -U inventory

# Check replication slots
docker exec kessel-postgres-rbac psql -U rbac -d rbac -c \
  "SELECT * FROM pg_replication_slots;"
```

See full troubleshooting guides in each phase's README.

## 📖 References

### External Documentation
- [Kessel Project](https://github.com/project-kessel)
- [SpiceDB Documentation](https://authzed.com/docs/spicedb)
- [Debezium Documentation](https://debezium.io/documentation/)
- [Google Zanzibar Paper](https://research.google/pubs/pub48190/)


