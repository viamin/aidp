# Temporal Feasibility Study: Deployment Notes

This document provides instructions for self-hosted Temporal deployment for Aidp.

---

## 1. Deployment Options Overview

| Option | Complexity | Best For |
|--------|-----------|----------|
| Docker Compose | Low | Development, testing, single-node |
| Kubernetes (Helm) | Medium | Production, multi-node, scaling |
| Temporal Cloud | Low | Production, managed service |

---

## 2. Docker Compose Deployment

### 2.1 Prerequisites

- Docker Engine 20.10+
- Docker Compose v2.0+
- 4GB RAM minimum
- 10GB disk space

### 2.2 Quick Start

```bash
# Clone Temporal docker-compose repository
git clone https://github.com/temporalio/docker-compose.git temporal-docker
cd temporal-docker

# Start with PostgreSQL backend
docker compose -f docker-compose-postgres.yml up -d

# Verify services are running
docker compose ps

# Access Web UI at http://localhost:8080
```

### 2.3 Aidp-Specific Docker Compose

Create `docker-compose.aidp.yml`:

```yaml
version: "3.8"

services:
  # PostgreSQL Database
  postgresql:
    image: postgres:15
    container_name: aidp-temporal-postgres
    environment:
      POSTGRES_USER: temporal
      POSTGRES_PASSWORD: temporal_password
      POSTGRES_DB: temporal
    volumes:
      - aidp-temporal-postgres:/var/lib/postgresql/data
    ports:
      - "5432:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U temporal"]
      interval: 10s
      timeout: 5s
      retries: 5

  # Temporal Server
  temporal:
    image: temporalio/auto-setup:1.24
    container_name: aidp-temporal-server
    depends_on:
      postgresql:
        condition: service_healthy
    environment:
      - DB=postgresql
      - DB_PORT=5432
      - POSTGRES_USER=temporal
      - POSTGRES_PWD=temporal_password
      - POSTGRES_SEEDS=postgresql
      - DYNAMIC_CONFIG_FILE_PATH=config/dynamicconfig/development-sql.yaml
    ports:
      - "7233:7233"  # gRPC frontend
    volumes:
      - ./dynamicconfig:/etc/temporal/config/dynamicconfig
    healthcheck:
      test: ["CMD", "tctl", "--address", "temporal:7233", "cluster", "health"]
      interval: 30s
      timeout: 10s
      retries: 5

  # Temporal Web UI
  temporal-ui:
    image: temporalio/ui:2.26
    container_name: aidp-temporal-ui
    depends_on:
      temporal:
        condition: service_healthy
    environment:
      - TEMPORAL_ADDRESS=temporal:7233
      - TEMPORAL_CORS_ORIGINS=http://localhost:3000
    ports:
      - "8080:8080"

  # Temporal Admin Tools
  temporal-admin-tools:
    image: temporalio/admin-tools:1.24
    container_name: aidp-temporal-admin
    depends_on:
      temporal:
        condition: service_healthy
    environment:
      - TEMPORAL_ADDRESS=temporal:7233
    stdin_open: true
    tty: true

  # Aidp Worker (build from local Dockerfile)
  aidp-worker:
    build:
      context: ..
      dockerfile: docker/Dockerfile.worker
    container_name: aidp-temporal-worker
    depends_on:
      temporal:
        condition: service_healthy
    environment:
      - TEMPORAL_ADDRESS=temporal:7233
      - TEMPORAL_NAMESPACE=default
      - AIDP_PROJECT_DIR=/app/project
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock  # For devcontainer support
      - aidp-worker-data:/app/data
    command: ["bundle", "exec", "aidp", "worker", "start"]

volumes:
  aidp-temporal-postgres:
  aidp-worker-data:

networks:
  default:
    name: aidp-temporal-network
```

### 2.4 Dynamic Configuration

Create `dynamicconfig/development-sql.yaml`:

```yaml
# Temporal Dynamic Configuration for Aidp

# History service settings
history.persistenceMaxQPS:
  - value: 3000
    constraints: {}

# Matching service settings
matching.numTaskqueueReadPartitions:
  - value: 5
    constraints: {}
matching.numTaskqueueWritePartitions:
  - value: 5
    constraints: {}

# Frontend service settings
frontend.persistenceMaxQPS:
  - value: 2000
    constraints: {}

# Worker settings
worker.enableScheduler:
  - value: true
    constraints: {}

# Visibility settings
system.enableActivityEagerExecution:
  - value: true
    constraints: {}

# Archival (disabled for development)
history.enableArchival:
  - value: false
    constraints: {}
visibility.enableArchival:
  - value: false
    constraints: {}
```

### 2.5 Worker Dockerfile

Create `docker/Dockerfile.worker`:

```dockerfile
FROM ruby:3.3-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    curl \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy Gemfile and install dependencies
COPY Gemfile Gemfile.lock ./
RUN bundle install --jobs 4 --retry 3

# Copy application code
COPY . .

# Create data directory
RUN mkdir -p /app/data

# Set environment
ENV RAILS_ENV=production
ENV AIDP_ENV=production

# Default command
CMD ["bundle", "exec", "aidp", "worker", "start"]
```

### 2.6 Startup Script

Create `scripts/start-temporal.sh`:

```bash
#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting Aidp Temporal Stack...${NC}"

# Check prerequisites
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Docker is not installed. Please install Docker first.${NC}"
    exit 1
fi

if ! command -v docker compose &> /dev/null; then
    echo -e "${RED}Docker Compose is not installed. Please install Docker Compose first.${NC}"
    exit 1
fi

# Start services
cd "$(dirname "$0")/../docker"

echo -e "${YELLOW}Starting PostgreSQL...${NC}"
docker compose -f docker-compose.aidp.yml up -d postgresql

echo -e "${YELLOW}Waiting for PostgreSQL to be healthy...${NC}"
until docker compose -f docker-compose.aidp.yml exec -T postgresql pg_isready -U temporal; do
    sleep 2
done

echo -e "${YELLOW}Starting Temporal Server...${NC}"
docker compose -f docker-compose.aidp.yml up -d temporal

echo -e "${YELLOW}Waiting for Temporal to be healthy...${NC}"
sleep 10  # Give Temporal time to initialize

echo -e "${YELLOW}Starting Temporal UI...${NC}"
docker compose -f docker-compose.aidp.yml up -d temporal-ui

echo -e "${GREEN}Temporal Stack Started!${NC}"
echo ""
echo "Services:"
echo "  - Temporal Frontend: localhost:7233"
echo "  - Temporal Web UI:   http://localhost:8080"
echo "  - PostgreSQL:        localhost:5432"
echo ""
echo "To start the Aidp worker:"
echo "  docker compose -f docker-compose.aidp.yml up -d aidp-worker"
echo ""
echo "Or run locally:"
echo "  TEMPORAL_ADDRESS=localhost:7233 bundle exec aidp worker start"
```

---

## 3. Kubernetes Deployment

### 3.1 Prerequisites

- Kubernetes cluster 1.25+
- kubectl configured
- Helm 3.x
- 8GB RAM minimum (cluster total)
- PersistentVolume support

### 3.2 Helm Chart Installation

```bash
# Add Temporal Helm repository
helm repo add temporal https://temporal.github.io/helm-charts
helm repo update

# Create namespace
kubectl create namespace aidp-temporal

# Install with PostgreSQL
helm install temporal temporal/temporal \
  --namespace aidp-temporal \
  --set server.replicaCount=1 \
  --set cassandra.enabled=false \
  --set mysql.enabled=false \
  --set postgresql.enabled=true \
  --set prometheus.enabled=true \
  --set grafana.enabled=true \
  --set elasticsearch.enabled=false \
  --timeout 15m
```

### 3.3 Custom Values File

Create `helm/values-aidp.yaml`:

```yaml
# Aidp Temporal Helm Values

server:
  replicaCount: 1

  config:
    persistence:
      default:
        driver: sql
        sql:
          driver: postgres

  frontend:
    replicaCount: 1
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 512Mi

  history:
    replicaCount: 1
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 512Mi

  matching:
    replicaCount: 1
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 512Mi

  worker:
    replicaCount: 1
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        cpu: 500m
        memory: 256Mi

# Use external managed PostgreSQL in production
postgresql:
  enabled: true
  auth:
    postgresPassword: temporal_password
    database: temporal
  primary:
    persistence:
      size: 10Gi
  # For production, use external managed PostgreSQL:
  # enabled: false
  # external:
  #   host: your-rds-instance.region.rds.amazonaws.com
  #   port: 5432

# Disable other databases
cassandra:
  enabled: false

mysql:
  enabled: false

elasticsearch:
  enabled: false

# Monitoring
prometheus:
  enabled: true
  nodeExporter:
    enabled: false

grafana:
  enabled: true
  adminPassword: admin
  persistence:
    enabled: true
    size: 1Gi

# Web UI
web:
  enabled: true
  replicaCount: 1
  service:
    type: ClusterIP
    port: 8080
  ingress:
    enabled: false
    # Enable for external access:
    # enabled: true
    # hosts:
    #   - host: temporal.example.com
    #     paths:
    #       - path: /
    #         pathType: Prefix
```

### 3.4 Install with Custom Values

```bash
helm install temporal temporal/temporal \
  --namespace aidp-temporal \
  --values helm/values-aidp.yaml \
  --timeout 15m

# Verify installation
kubectl get pods -n aidp-temporal

# Port forward for local access
kubectl port-forward svc/temporal-frontend 7233:7233 -n aidp-temporal &
kubectl port-forward svc/temporal-web 8080:8080 -n aidp-temporal &
```

### 3.5 Aidp Worker Deployment

Create `k8s/aidp-worker.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: aidp-worker
  namespace: aidp-temporal
  labels:
    app: aidp-worker
spec:
  replicas: 2
  selector:
    matchLabels:
      app: aidp-worker
  template:
    metadata:
      labels:
        app: aidp-worker
    spec:
      containers:
        - name: aidp-worker
          image: your-registry/aidp-worker:latest
          imagePullPolicy: Always
          env:
            - name: TEMPORAL_ADDRESS
              value: "temporal-frontend.aidp-temporal.svc.cluster.local:7233"
            - name: TEMPORAL_NAMESPACE
              value: "default"
            - name: AIDP_LOG_LEVEL
              value: "info"
          resources:
            requests:
              cpu: 200m
              memory: 512Mi
            limits:
              cpu: 1000m
              memory: 1Gi
          livenessProbe:
            exec:
              command:
                - /bin/sh
                - -c
                - "bundle exec aidp worker health"
            initialDelaySeconds: 30
            periodSeconds: 30
          readinessProbe:
            exec:
              command:
                - /bin/sh
                - -c
                - "bundle exec aidp worker health"
            initialDelaySeconds: 10
            periodSeconds: 10
      volumes:
        - name: worker-data
          persistentVolumeClaim:
            claimName: aidp-worker-pvc

---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: aidp-worker-pvc
  namespace: aidp-temporal
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
```

---

## 4. Production Considerations

### 4.1 Database Recommendations

| Environment | Recommendation |
|-------------|----------------|
| Development | PostgreSQL via Docker |
| Staging | PostgreSQL via Docker with persistent volume |
| Production | Managed PostgreSQL (RDS, Cloud SQL, Azure DB) |

### 4.2 Resource Sizing

| Component | Development | Staging | Production |
|-----------|-------------|---------|------------|
| Frontend | 256MB / 0.5 CPU | 512MB / 1 CPU | 1GB / 2 CPU |
| History | 256MB / 0.5 CPU | 512MB / 1 CPU | 2GB / 2 CPU |
| Matching | 256MB / 0.5 CPU | 512MB / 1 CPU | 1GB / 2 CPU |
| Worker | 128MB / 0.25 CPU | 256MB / 0.5 CPU | 512MB / 1 CPU |
| PostgreSQL | 256MB | 512MB | Managed service |

### 4.3 High Availability Setup

For production HA:

```yaml
# helm/values-production.yaml
server:
  frontend:
    replicaCount: 3
  history:
    replicaCount: 3
  matching:
    replicaCount: 3
  worker:
    replicaCount: 2

postgresql:
  enabled: false
  # Use external managed database with replication
```

### 4.4 Monitoring & Alerting

**Prometheus Metrics to Monitor:**

| Metric | Alert Threshold |
|--------|----------------|
| `temporal_server_requests_per_second` | > 1000/s |
| `temporal_server_latency_p99` | > 5s |
| `temporal_workflow_started_count` | Trend analysis |
| `temporal_workflow_completed_count` | Trend analysis |
| `temporal_activity_task_schedule_to_start_latency` | > 30s |

**Grafana Dashboards:**

Import official Temporal dashboards:
- Temporal Server Overview
- Temporal Workflow Metrics
- Temporal Activity Metrics

### 4.5 Backup Strategy

**PostgreSQL Backup:**

```bash
# Daily backup script
#!/bin/bash
BACKUP_DIR=/backups/temporal
DATE=$(date +%Y%m%d_%H%M%S)

pg_dump -h localhost -U temporal temporal | gzip > $BACKUP_DIR/temporal_$DATE.sql.gz

# Retention: keep 7 days
find $BACKUP_DIR -name "*.sql.gz" -mtime +7 -delete
```

**Event History Export:**

```bash
# Export workflow histories for archival
tctl --namespace default workflow list --status completed --print_json | \
  jq -c '.[]' | \
  while read workflow; do
    workflow_id=$(echo $workflow | jq -r '.execution.workflowId')
    tctl --namespace default workflow show --workflow_id $workflow_id --print_json >> histories.jsonl
  done
```

---

## 5. Security Configuration

### 5.1 TLS Configuration

Enable TLS for production:

```yaml
# helm/values-tls.yaml
server:
  config:
    tls:
      frontend:
        server:
          certFile: /etc/temporal/certs/cluster.pem
          keyFile: /etc/temporal/certs/cluster.key
          clientCAFiles:
            - /etc/temporal/certs/ca.crt
          requireClientAuth: true
```

### 5.2 Namespace Isolation

Create separate namespaces for different environments:

```bash
# Create namespaces
tctl --namespace default namespace register aidp-dev
tctl --namespace default namespace register aidp-staging
tctl --namespace default namespace register aidp-production

# Configure retention (days)
tctl --namespace aidp-production namespace update --retention 30
```

### 5.3 Access Control

Configure authentication in production:

```yaml
# helm/values-auth.yaml
server:
  config:
    global:
      authorization:
        enabled: true
        permissionsClaimName: permissions
        jwtKeyProvider:
          keySourceURIs:
            - https://your-auth-server/.well-known/jwks.json
```

---

## 6. Troubleshooting

### 6.1 Common Issues

| Issue | Symptom | Solution |
|-------|---------|----------|
| Workflow not starting | Timeout on start | Check worker is running and connected |
| Activity timeout | Activity fails after timeout | Increase `start_to_close_timeout` or add heartbeats |
| History too large | Workflow fails at 50K events | Implement Continue-As-New |
| Database connection | Connection refused | Check PostgreSQL is running and accessible |

### 6.2 Diagnostic Commands

```bash
# Check cluster health
tctl cluster health

# List workflows
tctl workflow list --namespace default

# Show workflow history
tctl workflow show --workflow_id <id>

# Describe workflow
tctl workflow describe --workflow_id <id>

# List task queues
tctl taskqueue list-partitions --taskqueue aidp-work-loop

# Check worker health
tctl taskqueue describe --taskqueue aidp-work-loop
```

### 6.3 Log Analysis

```bash
# Docker Compose logs
docker compose -f docker-compose.aidp.yml logs -f temporal

# Kubernetes logs
kubectl logs -f deployment/temporal-frontend -n aidp-temporal
kubectl logs -f deployment/aidp-worker -n aidp-temporal
```

---

## 7. Migration from Docker Compose to Kubernetes

1. **Export existing data** (if needed)
2. **Deploy Kubernetes stack** with same PostgreSQL data
3. **Migrate workers** one at a time
4. **Verify workflows** continue correctly
5. **Decommission Docker Compose** stack

---

## 8. Cost Estimates

### 8.1 Self-Hosted (AWS Example)

| Component | Instance Type | Monthly Cost |
|-----------|--------------|--------------|
| Temporal Server (3 nodes) | t3.medium | ~$90 |
| PostgreSQL (RDS) | db.t3.medium | ~$60 |
| Worker Nodes (2) | t3.large | ~$120 |
| **Total** | | **~$270/month** |

### 8.2 Temporal Cloud

| Tier | Monthly Cost |
|------|--------------|
| Developer | Free (limited) |
| Starter | ~$200/month |
| Production | Custom pricing |

---

## 9. References

- [Temporal Self-Hosted Guide](https://docs.temporal.io/self-hosted-guide)
- [Temporal Docker Compose](https://github.com/temporalio/docker-compose)
- [Temporal Helm Charts](https://github.com/temporalio/helm-charts)
- [Temporal Production Deployment](https://docs.temporal.io/production-deployment)
- [Temporal on Kubernetes Tips](https://temporal.io/blog/tips-for-running-temporal-on-kubernetes)
