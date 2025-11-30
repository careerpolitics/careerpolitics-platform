# **CareerPolitics Kubernetes Deployment Guide**

This guide walks you through deploying **CareerPolitics** to a **DigitalOcean Kubernetes Service (DOKS)** cluster using:

* NGINX Ingress Controller
* Redis (Bitnami Helm Chart)
* Cert-Manager (Let’s Encrypt SSL)
* DigitalOcean Load Balancer
* Kubernetes Deployment Manifests

---

# 1️⃣ **Prerequisites**

## ✔ DigitalOcean Account & doctl

Install and authenticate:

```bash
doctl auth init
```

## ✔ Domain Setup

You must have control of:

```
careerpolitics.com
```

You will later point DNS A records to the Kubernetes Load Balancer.

---

# 2️⃣ **Create a Kubernetes Cluster**

## **Recommended (DigitalOcean UI)**

1. Navigate to **Kubernetes**
2. Region: **BLR1 (Bangalore)**
3. Version: Latest stable
4. Node Pool: `s-2vcpu-4gb`, 3 nodes
5. Click **Create Cluster**

## CLI Alternative

```bash
doctl kubernetes cluster create careerpolitics-cluster \
  --region blr1 \
  --version latest \
  --size s-2vcpu-4gb \
  --count 2
```

---

# 3️⃣ **Connect kubectl to the Cluster**

```bash
doctl kubernetes cluster kubeconfig save careerpolitics-cluster
kubectl get nodes
kubectl create namespace production
```

---

# 4️⃣ **Build & Push the Application Docker Image**

### Build

```bash
docker build --target production \
  -t muraridevv/careerpolitics-platform:latest .
```

### Push to Docker Hub

```bash
docker push muraridevv/careerpolitics-platform:latest
```

### (Optional) Use DigitalOcean Container Registry

```bash
doctl registry login
docker tag <local-image> registry.digitalocean.com/<registry-name>/careerpolitics-platform:latest
docker push registry.digitalocean.com/<registry-name>/careerpolitics-platform:latest
```

---

# 5️⃣ **Install NGINX Ingress Controller**

## UI (Recommended)

1. Open your Kubernetes cluster → **Add-Ons**
2. Search for **NGINX Ingress Controller**
3. Install

## Verify

```bash
kubectl get pods -n ingress-nginx
```

## CLI Alternative

```bash
doctl kubernetes cluster addon install <CLUSTER-ID> ingress-nginx
```

---

# 6️⃣ **Deploy Redis (Bitnami Helm Chart)**

### Create namespace

```bash
kubectl create namespace redis
```

### Add Helm repo

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
```

### Install Redis

```bash
helm install careerpolitics-redis bitnami/redis --namespace redis
```

### Get password

```bash
kubectl get secret --namespace redis careerpolitics-redis \
  -o jsonpath="{.data.redis-password}" | base64 -d
```

### Redis Connection URL

```
redis://:PASSWORD@careerpolitics-redis-master.redis.svc.cluster.local:6379
```

---

# 8️⃣ **Create Application Secrets & ConfigMap**

Create a local `.env.production` file:

### Contains **sensitive values only**

(database, redis URL, API keys, SMTP password, Algolia key, Spaces secret keys, etc.)

Example:

```
SECRET_KEY_BASE=...
DATABASE_URL=...
FOREM_OWNER_SECRET=...
REDIS_URL=redis://...

DO_SPACES_ACCESS_KEY_ID=...
DO_SPACES_SECRET_ACCESS_KEY=...

ALGOLIA_API_KEY=...
SMTP_PASSWORD=...
```

### Create Kubernetes Secret

```bash
kubectl create secret generic careerpolitics-secrets \
  --from-env-file=.env.production \
  -n production \
  --dry-run=client -o yaml | kubectl apply -f -
```

### Apply ConfigMap (non-sensitive values)

```bash
kubectl apply -f kube/config-app.yaml
```

Your ConfigMap typically includes:

* RAILS_ENV
* SMTP host/port

* App constants
* Public identifiers

---

# 9️⃣ **Install Cert-Manager (for Automatic SSL)**

### Install Cert-Manager

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.15.1/cert-manager.yaml
```

### Verify

```bash
kubectl -n cert-manager rollout status deploy/cert-manager
```

### Install ClusterIssuer

```bash
kubectl apply -f kube/cluster-issuer.yaml
kubectl describe clusterissuer letsencrypt-prod
```

Ensure the email in the issuer is correct.

---

# 🔟 **Deploy the Application**

Apply manifests:

```bash
kubectl apply -f kube/config-app.yaml
kubectl apply -f kube/deployment-web.yaml
kubectl apply -f kube/service-web.yaml
kubectl apply -f kube/deployment-worker.yaml
kubectl apply -f kube/ingress.yaml
```

Monitor:

```bash
kubectl rollout status deployment/careerpolitics-web -n production
kubectl rollout status deployment/careerpolitics-worker -n production
```

---

# 1️⃣1️⃣ **Configure DNS (Required for SSL)**

### Get the LoadBalancer IP

```bash
kubectl get svc -n ingress-nginx
```

Look for:

```
ingress-nginx-controller → EXTERNAL-IP
```

### Add DNS A Records

```
careerpolitics.com           → <EXTERNAL-IP>
www.careerpolitics.com       → <EXTERNAL-IP>
```

TTL: `300`

Wait 5–30 minutes for propagation.

Cert-Manager **will only issue SSL after DNS propagates**.

---

# 1️⃣2️⃣ **Verify SSL**

```bash
kubectl get certificate,certificaterequest,order -n production
kubectl describe certificate careerpolitics-tls -n production
```

A valid certificate shows:

```
Ready: True
```

---

# 1️⃣3️⃣ **Access the Application**

Visit:

```
https://careerpolitics.com
```

Debug routing:

```bash
kubectl describe ingress careerpolitics-ingress -n production
kubectl get endpoints careerpolitics-web -n production -o wide
```

---

# 1️⃣4️⃣ **Optional: Autoscaling**

```bash
kubectl autoscale deployment careerpolitics-web \
  --cpu-percent=50 --min=2 --max=5 -n production
```

---

# 1️⃣5️⃣ **Monitoring & Logs**

```bash
kubectl logs -f deployment/careerpolitics-web -n production
kubectl get pods -n production
kubectl describe ingress careerpolitics-ingress -n production
```

---
