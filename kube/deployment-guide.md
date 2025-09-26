# CareerPolitics Kubernetes Deployment Guide

This guide explains how to deploy the CareerPolitics app on a DigitalOcean Kubernetes cluster using NGINX Ingress and Cert-Manager for SSL.

---

## Prerequisites

1. **DigitalOcean Account & doctl**

  * Create a DigitalOcean account if you don't have one.
  * Install `doctl` CLI: [https://docs.digitalocean.com/reference/doctl/how-to/install/](https://docs.digitalocean.com/reference/doctl/how-to/install/)
  * Authenticate `doctl`:

    ```bash
    doctl auth init
    ```

2. **Docker Image**

  * Build your app Docker image locally or via CI/CD.
  * Push to Docker Hub or DigitalOcean Container Registry:

    ```bash
    docker build --target production -t muraridevv/careerpolitics-platform:latest .
    docker push muraridevv/careerpolitics-platform:latest
    ```

3. **Domain**

  * Ensure you have `careerpolitics.com` (or your custom domain) ready to point to the cluster.

---

## Step 1: Create Kubernetes Cluster

**Option A: DigitalOcean UI**

1. Go to **DigitalOcean → Kubernetes → Create Cluster**.
2. Region: `Bangalore (BLR1)`.
3. Kubernetes Version: latest stable.
4. Node pool: 3 nodes (s-2vcpu-4gb recommended for HA).
5. Click **Create Cluster**.

**Option B: doctl CLI**

```bash
doctl kubernetes cluster create careerpolitics-cluster \
  --region blr1 \
  --version 1.33.1-do.4 \
  --size s-2vcpu-4gb \
  --count 2
```

> Wait for cluster provisioning (\~5–10 min).

---

## Step 2: Connect to Cluster

```bash
doctl kubernetes cluster kubeconfig save careerpolitics-cluster
kubectl get nodes
kubectl create namespace production
```

---

## Step 3: Install NGINX Ingress Controller

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.1/deploy/static/provider/do/deploy.yaml
kubectl get pods -n ingress-nginx
```

---

## Step 4: Install Cert-Manager

```bash
kubectl apply --validate=false -f https://github.com/cert-manager/cert-manager/releases/download/v1.15.1/cert-manager.yaml
kubectl get pods -n cert-manager
```

---

## Step 5: Deploy Redis in Kubernetes

```bash
kubectl create namespace redis
helm repo add bitnami https://charts.bitnami.com/bitnami
helm install careerpolitics-redis bitnami/redis --namespace redis
```

> After deployment, note the Redis URL for environment variables: `redis://careerpolitics-redis-master.redis.svc.cluster.local:6379`

---

## Step 6: Apply Kubernetes Manifests

All your YAML files should be applied in the following order:

```bash
# 1. Apply secrets first
kubectl apply -f secrets.yaml

# 2. Apply cluster issuer for SSL certificates
kubectl apply -f cluster-issuer.yaml

# 3. Apply services
kubectl apply -f service-web.yaml

# 4. Apply deployments
kubectl apply -f deployment-web.yaml
kubectl apply -f deployment-worker.yaml

# 5. Apply ingress last
kubectl apply -f ingress.yaml
```

### Verify Deployment

```bash
# Check if all pods are running
kubectl get pods -n production

# Check if services are created
kubectl get svc -n production

# Check if ingress is configured
kubectl get ingress -n production

# Check logs for any issues
kubectl logs -f deployment/careerpolitics-web -n production
```

---

## Step 7: Point Domain to Ingress

1. Get LoadBalancer IP:

```bash
kubectl get svc -n ingress-nginx
```

2. Add A record in DNS:

```
Host: @
Value: <EXTERNAL-IP>
TTL: 300
```

3. Wait for DNS propagation.

---

## Step 8: Access App

Visit: `https://careerpolitics.in` 🎉

* Verify SSL:

```bash
kubectl describe certificate careerpolitics-tls -n production
kubectl logs -n cert-manager deploy/cert-manager
```

---

## Optional: Horizontal Pod Autoscaler

```bash
kubectl autoscale deployment careerpolitics-web --cpu-percent=50 --min=2 --max=5 -n production
```

---

## Monitoring & Logs

```bash
kubectl logs -f deployment/careerpolitics-web -n production
kubectl get pods -n production
```

---

## Troubleshooting

### Common Issues and Solutions

#### 1. SSL/TLS Issues
If you see "Invalid HTTP format, parsing fails. Are you trying to open an SSL connection to a non-SSL Puma?" errors:

- **Solution**: The ingress is properly configured to handle SSL termination and forward proper headers to the application.
- **Check**: Verify that the ingress annotations are applied correctly.

#### 2. Datadog Agent Unreachable
If you see "agent unreachable: cannot negotiate /v0.7/config" errors:

- **Solution**: This is expected behavior. Datadog tracing is disabled when no agent is present.
- **Note**: The application will work fine without Datadog agent.

#### 3. Pod Startup Issues
If pods are failing to start:

```bash
# Check pod status
kubectl describe pod <pod-name> -n production

# Check logs
kubectl logs <pod-name> -n production

# Check if secrets are properly mounted
kubectl get secret careerpolitics-secrets -n production -o yaml
```

#### 4. Database Connection Issues
If you see database connection errors:

- Verify the DATABASE_URL in your secrets
- Check if the database is accessible from the cluster
- Ensure SSL mode is properly configured

#### 5. Redis Connection Issues
If you see Redis connection errors:

- Verify the REDIS_URL in your secrets
- Check if Redis is running: `kubectl get pods -n redis`
- Ensure Redis service is accessible

### Health Check Endpoints

The application includes health check endpoints:
- **Readiness Probe**: `GET /` - Used to determine if the pod is ready to receive traffic
- **Liveness Probe**: `GET /` - Used to determine if the pod should be restarted

### Resource Monitoring

```bash
# Check resource usage
kubectl top pods -n production

# Check resource limits
kubectl describe pod <pod-name> -n production
```

### SSL Certificate Issues

```bash
# Check certificate status
kubectl describe certificate careerpolitics-tls -n production

# Check cert-manager logs
kubectl logs -n cert-manager deploy/cert-manager

# Check ingress status
kubectl describe ingress careerpolitics-ingress -n production
```
