# ComfyUI API Scaling Guide

ComfyUI API is stateless and horizontally scalable. This guide covers scaling strategies for production deployments.

**For Infrastructure Team:** See [README.md](../README.md#for-infrastructure-team) for quick start. This guide covers scaling details.

## Architecture Overview

```
┌─────────────────────────────────────────┐
│  Client Applications                     │
│  (OpenAI-compatible wrappers, etc.)     │
└──────────────┬──────────────────────────┘
               │
               │ HTTP requests
               │
┌──────────────▼──────────────────────────┐
│  comfyui-api (Stateless API Layer)      │
│  - Port 3000 (internal)                 │
│  - Horizontally scalable                │
│  - Load balancer distributes requests   │
└──────────────┬──────────────────────────┘
               │
               │ Internal communication
               │
┌──────────────▼──────────────────────────┐
│  ComfyUI Core (Workflow Execution)      │
│  - Port 8188 (internal)                 │
│  - One instance per GPU                  │
│  - Handles model loading & inference    │
└─────────────────────────────────────────┘
```

**Key Points:**
- `comfyui-api` is stateless - any instance can handle any request
- ComfyUI core runs one process per GPU for optimal resource utilization
- Requests are distributed via load balancer or Kubernetes Service

## Single-Node Multi-GPU Scaling

Scale `comfyui-api` instances on a single node with multiple GPUs using Docker Compose.

**Important:** Docker Compose scaling uses the `--scale` CLI flag, not YAML configuration. When scaling, Docker Compose creates multiple containers from the same service definition, which can cause port conflicts if fixed ports are used.

### Setup

1. **Use the scaling script** (recommended):

```bash
# Scale to N replicas (one per GPU)
bash scripts/scale-compose.sh 4

# Check health of all instances
bash scripts/health-check.sh http://localhost:3001
```

The script uses `docker compose up --scale comfyui-api=N` to create multiple containers.

2. **Manual scaling**:

```bash
# Scale using Docker Compose CLI
docker compose up -d --scale comfyui-api=4

# Check running containers
docker compose ps
```

### Port Conflicts

**Problem:** When scaling with fixed port mappings (e.g., `"3001:3000"`), Docker Compose will fail because multiple containers cannot bind to the same host port.

**Solutions:**

**Option 1: Use a reverse proxy** (recommended for production)

Remove fixed port mappings from `docker-compose.yml` and use a load balancer:

```yaml
services:
  comfyui-api:
    # Remove ports section or use dynamic ports
    # ports:
    #   - "3001:3000"
```

Then configure nginx/Traefik to discover containers via Docker network:

```nginx
upstream comfyui_api {
    least_conn;
    # Use Docker service name - containers accessible via service name
    server comfyui-api:3000;
}

server {
    listen 80;
    location / {
        proxy_pass http://comfyui_api;
    }
}
```

**Option 2: Dynamic port mapping** (for testing)

Use Docker's automatic port assignment by removing the host port:

```yaml
services:
  comfyui-api:
    ports:
      - "3000"  # Only container port, Docker assigns host port
```

Then discover ports via `docker compose ps` or Docker API.

**Option 3: Separate services** (not recommended)

Create separate service definitions for each instance (manual management required):

```yaml
services:
  comfyui-api-0:
    extends:
      file: docker-compose.yml
      service: comfyui-api
    ports:
      - "3001:3000"
  comfyui-api-1:
    extends:
      file: docker-compose.yml
      service: comfyui-api
    ports:
      - "3002:3000"
```

### GPU Allocation

For multi-GPU setups, use `device_ids` to assign specific GPUs:

```yaml
services:
  comfyui-api:
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              device_ids: ['0']  # Assign GPU 0
              capabilities: [gpu]
```

**Note:** When scaling, all containers will use the same GPU configuration. For per-GPU assignment, use separate service definitions or Kubernetes.

## Multi-Node Kubernetes Scaling

Deploy `comfyui-api` across multiple nodes with Kubernetes for true horizontal scaling.

### Prerequisites

- Kubernetes cluster with GPU nodes
- NVIDIA GPU Operator installed
- Shared storage for models (NFS, S3, or PVC)

### Deployment

1. **Apply manifests**:

```bash
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
```

2. **Scale replicas**:

```bash
kubectl scale deployment comfyui-api --replicas=4
```

3. **Check status**:

```bash
kubectl get pods -l app=comfyui-api
kubectl get svc comfyui-api
```

### GPU Resource Allocation

Each pod requests one GPU:

```yaml
resources:
  limits:
    nvidia.com/gpu: 1
  requests:
    nvidia.com/gpu: 1
```

Kubernetes scheduler ensures pods are distributed across nodes with available GPUs.

### Service Discovery

Kubernetes Service provides load balancing automatically:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: comfyui-api
spec:
  selector:
    app: comfyui-api
  ports:
    - port: 80
      targetPort: 3000
  type: LoadBalancer  # or ClusterIP with Ingress
```

### Model Storage

Use PersistentVolumeClaim for shared model storage:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: comfyui-models
spec:
  accessModes:
    - ReadOnlyMany
  resources:
    requests:
      storage: 500Gi
```

Mount in deployment:

```yaml
volumes:
  - name: models
    persistentVolumeClaim:
      claimName: comfyui-models
```

## Health Checks

Monitor API health for scaling decisions:

```bash
# Single endpoint
bash scripts/health-check.sh http://localhost:3001

# Multiple endpoints
for port in 3001 3002 3003 3004; do
  bash scripts/health-check.sh http://localhost:$port
done
```

### Endpoints

- `GET /health` - Liveness probe (returns 200 if API is running)
- `GET /ready` - Readiness probe (returns 200 if ready to accept requests)

### Integration with Orchestrators

**Docker Compose:**
```yaml
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:3000/health"]
  interval: 30s
  timeout: 10s
  retries: 3
```

**Kubernetes:**
```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 3000
  initialDelaySeconds: 60
  periodSeconds: 30
readinessProbe:
  httpGet:
    path: /ready
    port: 3000
  initialDelaySeconds: 30
  periodSeconds: 10
```

## Configuration for Scaling

### Environment Variables

Set these in your deployment configuration:

- `PORT=3000` - Internal API port
- `COMFY_HOME=/opt/ComfyUI` - ComfyUI installation path
- `MODEL_DIR=/opt/ComfyUI/models` - Model directory (shared storage)
- `LRU_CACHE_SIZE_GB=50` - Per-instance cache size
- `MAX_BODY_SIZE_MB=200` - Max request size
- `CMD=python main.py --normalvram --listen 0.0.0.0` - ComfyUI startup command

### Backend URL Configuration

When using `comfyui-api` as backend, configure clients to point to the load balancer:

```bash
# For OpenAI-compatible wrappers
export COMFYUI_URL="http://load-balancer:80"
```

Or use Kubernetes Service DNS:

```bash
export COMFYUI_URL="http://comfyui-api.default.svc.cluster.local"
```

## Performance Considerations

### Stateless Design

- No session state - any instance can handle any request
- Model cache is per-instance (LRU eviction)
- First request per model incurs loading overhead

### Load Distribution

- Use least-connections or round-robin load balancing
- Consider request size for large workflow submissions
- Monitor per-instance metrics (CPU, GPU, memory)

### Scaling Triggers

Scale based on:
- Request queue depth
- Average response time
- GPU utilization
- Error rates

## Troubleshooting

### Port Conflicts

If scaling fails due to port conflicts:

```bash
# Check used ports
netstat -tuln | grep -E ':(3001|3002|3003|3004)'

# Use different port range in compose file
```

### GPU Allocation

Verify GPU access:

```bash
# Docker
docker exec comfyui-api nvidia-smi

# Kubernetes
kubectl exec -it <pod-name> -- nvidia-smi
```

### Model Access

Ensure shared storage is accessible:

```bash
# Check mount
docker exec comfyui-api ls -la /opt/ComfyUI/models/

# Kubernetes
kubectl exec -it <pod-name> -- ls -la /opt/ComfyUI/models/
```

## References

- [Docker Compose Scaling](https://docs.docker.com/compose/reference/scale/)
- [Kubernetes Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
- [NVIDIA GPU Operator](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/)
