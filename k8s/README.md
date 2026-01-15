# Kubernetes Deployment

Kubernetes manifests for deploying ComfyUI API with horizontal scaling.

## Prerequisites

- Kubernetes cluster with GPU nodes
- NVIDIA GPU Operator installed
- kubectl configured to access cluster

## Quick Start

1. **Create secrets** (optional, for Hugging Face token):

```bash
kubectl create secret generic comfyui-secrets \
  --from-literal=hf-token='your-token-here'
```

2. **Create PersistentVolumeClaims** (for model storage):

```bash
kubectl apply -f pvc-models.yaml
kubectl apply -f pvc-custom-nodes.yaml  # Optional
```

3. **Deploy ComfyUI API**:

```bash
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
```

4. **Check status**:

```bash
kubectl get pods -l app=comfyui-api
kubectl get svc comfyui-api
```

## Scaling

Scale the deployment:

```bash
# Scale to N replicas
kubectl scale deployment comfyui-api --replicas=4

# Auto-scaling (requires HPA)
kubectl apply -f hpa.yaml  # If created
```

## Configuration

### Storage

Update PVC sizes in `pvc-models.yaml` and `pvc-custom-nodes.yaml`:

```yaml
resources:
  requests:
    storage: 500Gi  # Adjust based on model storage needs
```

### Resources

Adjust GPU and CPU requests/limits in `deployment.yaml`:

```yaml
resources:
  limits:
    nvidia.com/gpu: 1
    memory: "32Gi"
    cpu: "8"
  requests:
    nvidia.com/gpu: 1
    memory: "16Gi"
    cpu: "4"
```

### External Access

For external access, change Service type in `service.yaml`:

```yaml
spec:
  type: LoadBalancer  # Instead of ClusterIP
```

Or use Ingress with ClusterIP service.

## Troubleshooting

### Check Pod Status

```bash
kubectl describe pod -l app=comfyui-api
kubectl logs -l app=comfyui-api
```

### Verify GPU Access

```bash
kubectl exec -it <pod-name> -- nvidia-smi
```

### Check Storage

```bash
kubectl get pvc
kubectl describe pvc comfyui-models
```

### Port Forward for Testing

```bash
kubectl port-forward svc/comfyui-api 3001:80
# Access at http://localhost:3001
```
