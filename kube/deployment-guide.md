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

## Step 6: Create Secrets for Sensitive Environment Variables

Include database, secret key, SMTP, and Redis URL.

```bash
kubectl create secret generic careerpolitics-secrets \
  --from-literal=DATABASE_URL="postgresql://doadmin:AVNS_Wn_xOCvNSCfyhgjMxxb@postgresql-db-do-user-24455640-0.d.db.ondigitalocean.com:25060/defaultdb?sslmode=require" \
  --from-literal=SECRET_KEY_BASE="<your-secret-key>" \
  --from-literal=AWS_SECRET="<your-aws-secret>" \
  --from-literal=SMTP_PASSWORD="<your-smtp-password>" \
  --from-literal=REDIS_URL="redis://careerpolitics-redis-master.redis.svc.cluster.local:6379" \
  --from-literal=GA_API_SECRET="<your-ga-api-secret>" \
  --from-literal=MAILCHIMP_API_KEY="<your-mailchimp-api-key>" \
  --from-literal=GEMINI_API_KEY="<your-gemini-api-key>" \
  -n production

```

> Add other secrets like `HONEYBADGER_API_KEY`, `FOREM_OWNER_SECRET` as needed.

---

## Step 7: Apply Kubernetes Manifests

All your YAML files (`cluster-issuer.yaml`, `deployment-web.yaml`, `service-web.yaml`, `deployment-worker.yaml`, `ingress.yaml`) should be applied:

```bash
kubectl apply -f cluster-issuer.yaml
kubectl apply -f deployment-web.yaml
kubectl apply -f service-web.yaml
kubectl apply -f deployment-worker.yaml
kubectl apply -f ingress.yaml
```

---

## Step 8: Point Domain to Ingress

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

## Step 9: Access App

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
