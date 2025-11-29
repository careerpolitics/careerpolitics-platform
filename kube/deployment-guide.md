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

# **Step 6: Create DigitalOcean Spaces (Object Storage)**

DigitalOcean Spaces is an S3-compatible object storage service for images and files.

## **1. Create a Space**

### **Option A: DigitalOcean UI**

1. Go to **DigitalOcean → Spaces**
2. Click **Create a Space**
3. Choose region: **Singapore (sgp1)** or closest to your cluster
4. Name: `careerpolitics-images` (must be globally unique)
5. Enable **File Listing** (optional, for debugging)
6. Click **Create a Space**

### **Option B: doctl CLI**

```bash
doctl spaces create careerpolitics-images --region sgp1
```

## **2. Generate Access Keys**

1. Go to **API → Spaces Keys**
2. Click **Generate New Key**
3. Name: `careerpolitics-spaces-key`
4. Copy the **Access Key** and **Secret Key**

⚠️ **Save these keys immediately** - the secret is shown only once.

## **3. Configure CORS (Optional)**

If you need direct browser uploads, configure CORS:

```bash
doctl spaces cors put careerpolitics-images \
  --cors-rules '[
    {
      "AllowedOrigins": ["https://careerpolitics.com"],
      "AllowedMethods": ["GET", "PUT", "POST", "DELETE", "HEAD"],
      "AllowedHeaders": ["*"],
      "ExposeHeaders": ["ETag"],
      "MaxAgeSeconds": 3000
    }
  ]'
```

## **4. Enable CDN (Optional)**

1. In Spaces UI, go to **Settings → CDN**
2. Enable **CDN** and note the CDN endpoint
3. Update `DO_SPACES_CDN_ENDPOINT` in your ConfigMap if using CDN

---

# **Step 7: Create App Secrets**

Create an `.env.production` file locally with all sensitive values:

```
# Database
DATABASE_URL=postgres://...

# Rails
SECRET_KEY_BASE=...
FOREM_OWNER_SECRET=...

# Redis
REDIS_URL=redis://:PASSWORD@careerpolitics-redis-master.redis.svc.cluster.local:6379

# DigitalOcean Spaces (replaces AWS S3)
DO_SPACES_ACCESS_KEY_ID=your-spaces-access-key
DO_SPACES_SECRET_ACCESS_KEY=your-spaces-secret-key
# OR use legacy AWS_ID/AWS_SECRET (will work with DO Spaces)
AWS_ID=your-spaces-access-key
AWS_SECRET=your-spaces-secret-key

# Other API keys (Algolia, SMTP, etc.)
ALGOLIA_API_KEY=...
SMTP_PASSWORD=...
# ... include all other secrets from your deployment YAMLs
```

> **Note**: DigitalOcean Spaces uses S3-compatible API. You can use either `DO_SPACES_ACCESS_KEY_ID`/`DO_SPACES_SECRET_ACCESS_KEY` or the legacy `AWS_ID`/`AWS_SECRET` keys. Both will work.

Create/update K8s secret:

```bash
kubectl create secret generic careerpolitics-secrets \
  --from-env-file=env/.env.production \
  -n production \
  --dry-run=client -o yaml | kubectl apply -f -
```

> **Important**: After creating the secret, also apply the ConfigMap which contains non-sensitive configuration:

```bash
kubectl apply -f kube/config-app.yaml
```

The ConfigMap includes DigitalOcean Spaces endpoint and region settings.

---

# **Step 8: Install Cert-Manager (SSL)**

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

# **Step 9: Deploy Application**

Apply all manifests:

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

# **Step 10: Configure DNS**

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

# **Step 11: Validate SSL**

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

# **Step 12: Access the Application**

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
