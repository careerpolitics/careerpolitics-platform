# **CareerPolitics Kubernetes Deployment Guide**

This guide explains how to deploy the **CareerPolitics** application onto a **DigitalOcean Kubernetes (DOKS)** cluster using:

* NGINX Ingress Controller
* Redis (Bitnami Helm Chart)
* Cert-Manager (Let’s Encrypt SSL)
* DigitalOcean Load Balancer
* Kubernetes Manifests

---

# **Prerequisites**

## **1. DigitalOcean Account & doctl**

Install and authenticate:

```bash
doctl auth init
```

## **2. Domain Setup**

You must own a domain such as:

```
careerpolitics.com
```

and manage DNS records.

---

# **Step 1: Create Kubernetes Cluster**

## **Option A: DigitalOcean UI (Recommended)**

1. DigitalOcean → **Kubernetes**
2. Region: **Bangalore (BLR1)**
3. Version: Latest stable
4. Node Pool: **s-2vcpu-4gb**, 3 nodes
5. Click **Create Cluster**

## **Option B: CLI**

```bash
doctl kubernetes cluster create careerpolitics-cluster \
  --region blr1 \
  --version latest \
  --size s-1vcpu-2gb \
  --count 2
```

---

# **Step 2: Connect to the Cluster**

```bash
doctl kubernetes cluster kubeconfig save careerpolitics-cluster

kubectl get nodes
kubectl create namespace production
```

---

# **Step 3: Build & Push the Docker Image**

## **1. Build image**

```bash
docker build --target production \
  -t muraridevv/careerpolitics-platform:latest .
```

## **2. Push to Docker Hub**

```bash
docker push muraridevv/careerpolitics-platform:latest
```

### Using DigitalOcean Container Registry (optional)

```bash
doctl registry login
docker tag <local-image> registry.digitalocean.com/<registry-name>/careerpolitics-platform:latest
docker push registry.digitalocean.com/<registry-name>/careerpolitics-platform:latest
```

---

# **Step 4: Install NGINX Ingress Controller**

DigitalOcean provides a managed ingress installation.

## **Option A: UI (Recommended)**

1. Go to your Kubernetes cluster
2. Click **Add-Ons**
3. Search for **NGINX Ingress Controller**
4. **Install**
5. Verify pods:

```bash
kubectl get pods -n ingress-nginx
```

## **Option B: doctl command**

```bash
doctl kubernetes cluster addon install <CLUSTER-ID> ingress-nginx
kubectl get pods -n ingress-nginx
```

---

# **Step 5: Install Redis via Helm (Bitnami)**

## **1. Create Redis namespace**

```bash
kubectl create namespace redis
```

## **2. Add Bitnami chart repo**

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
```

## **3. Install Redis**

```bash
helm install careerpolitics-redis bitnami/redis --namespace redis
```

## **4. Get Redis password**

```bash
kubectl get secret --namespace redis careerpolitics-redis \
  -o jsonpath="{.data.redis-password}" | base64 -d
```

## **5. Redis URL**

```
redis://:PASSWORD@careerpolitics-redis-master.redis.svc.cluster.local:6379
```

---

# **Step 6: Create App Secrets**

Create an `.env.production` file locally:

```
DATABASE_URL=postgres://...
SECRET_KEY_BASE=...
REDIS_URL=redis://:PASSWORD@careerpolitics-redis-master.redis.svc.cluster.local:6379
FOREM_OWNER_SECRET=...
```

Create/update K8s secret:

```bash
kubectl create secret generic careerpolitics-secrets \
  --from-env-file=env/.env.production \
  -n production \
  --dry-run=client -o yaml | kubectl apply -f -
```

---

# **Step 7: Install Cert-Manager (SSL)**

## **1. Apply official manifests**

```bash
kubectl apply --validate=false -f https://github.com/cert-manager/cert-manager/releases/download/v1.15.1/cert-manager.yaml
```

Wait for pods:

```bash
kubectl rollout status deployment/cert-manager -n cert-manager
kubectl rollout status deployment/cert-manager-webhook -n cert-manager
kubectl rollout status deployment/cert-manager-cainjector -n cert-manager
```

## **2. Apply ClusterIssuer**

```bash
kubectl apply -f kube/cluster-issuer.yaml
kubectl describe clusterissuer letsencrypt-prod
```

⚠ Ensure email is correct.

## **3. Optional: Staging Issuer**

Use staging to avoid rate limits during testing.

---

# **Step 8: Deploy Application**

Apply all manifests:

```bash
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

# **Step 9: Configure DNS**

## **1. Get LoadBalancer IP**

```bash
kubectl get svc -n ingress-nginx
```

Find:

```
ingress-nginx-controller  EXTERNAL-IP: <IP>
```

## **2. Add A Records**

```
careerpolitics.com → <EXTERNAL-IP>
www.careerpolitics.com → <EXTERNAL-IP>
```

TTL: 300

## **3. Wait for DNS propagation (important)**

Cert-Manager will fail until DNS is propagated globally.

---

# **Step 10: Validate SSL**

```bash
kubectl get certificate,certificaterequest,order -n production
kubectl describe certificate careerpolitics-tls -n production
kubectl logs -n cert-manager deploy/cert-manager --tail=200
```

A valid certificate shows:

```
Ready: True
```

If not, inspect the related `Order` → `Challenge` objects.

---

# **Step 11: Access the Application**

Visit:

```
https://careerpolitics.com
```

Check routing:

```bash
kubectl describe ingress careerpolitics-ingress -n production
kubectl get endpoints careerpolitics-web -n production -o wide
```

---

# **Optional: Autoscaling**

```bash
kubectl autoscale deployment careerpolitics-web \
  --cpu-percent=50 --min=2 --max=5 -n production
```

---

# **Monitoring & Logs**

```bash
kubectl logs -f deployment/careerpolitics-web -n production
kubectl get pods -n production
kubectl describe ingress careerpolitics-ingress -n production
```

---
