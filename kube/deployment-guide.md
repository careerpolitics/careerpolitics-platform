# **CareerPolitics Kubernetes Deployment Guide**

This guide explains how to deploy the **CareerPolitics** application onto a **DigitalOcean Kubernetes (DOKS)** cluster using:

* NGINX Ingress Controller
* Redis (Bitnami Helm Chart)
* Cert-Manager (Let’s Encrypt SSL)
* DigitalOcean Load Balancer
* Kubernetes Manifests

---

# **Prerequisites**

### **1. DigitalOcean Account & doctl**

* Create a DigitalOcean account
* Install `doctl`:
  [https://docs.digitalocean.com/reference/doctl/how-to/install/](https://docs.digitalocean.com/reference/doctl/how-to/install/)
* Authenticate:

```bash
doctl auth init
```

---

### **2. Domain Setup**

Ensure you own a domain (e.g., `careerpolitics.com`) and can create DNS records.

---

# **Step 1: Create Kubernetes Cluster**

## **Option A: Using the DigitalOcean UI (Recommended)**

1. Go to **DigitalOcean → Kubernetes → Create Cluster**
2. Region: **Bangalore (BLR1)**
3. Kubernetes Version: **Latest Stable**
4. Node Pool: **3 nodes (s-2vcpu-4gb recommended)**
5. Click **Create Cluster**

---

## **Option B: Using doctl**

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

This step ensures your application image is available for Kubernetes deployments.

### **1. Build the image**

Run inside your project root:

```bash
docker build --target production \
  -t muraridevv/careerpolitics-platform:latest .
```

---

### **2. Push the image to Docker Hub**

```bash
docker push muraridevv/careerpolitics-platform:latest
```

> If using **DigitalOcean Container Registry (DOCR)** instead of Docker Hub, run:

```bash
doctl registry login
docker tag <local-image> registry.digitalocean.com/<registry-name>/careerpolitics-platform:latest
docker push registry.digitalocean.com/<registry-name>/careerpolitics-platform:latest
```

---

# **Step 4: Install NGINX Ingress Controller (DigitalOcean Method)**

DigitalOcean provides a fully managed installation for NGINX.

---

## **Option A: Install via DigitalOcean UI**

1. Open your Kubernetes cluster
2. Go to **Add-Ons**
3. Search **NGINX Ingress Controller**
4. Click **Install**
5. Verify installation:

```bash
kubectl get pods -n ingress-nginx
```

---

## **Option B: Install via doctl**

```bash
doctl kubernetes cluster addon install <CLUSTER-ID> ingress-nginx
kubectl get pods -n ingress-nginx
```

---

# **Step 5: Install Redis (Bitnami Helm Chart)**

Redis is required for caching and job processing.

---

### **1. Create Redis namespace**

```bash
kubectl create namespace redis
```

---

### **2. Add Bitnami Helm charts repo**

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
```

---

### **3. Install Redis**

```bash
helm install careerpolitics-redis bitnami/redis --namespace redis
```

---

### **4. Retrieve Redis password**

```bash
kubectl get secret --namespace redis careerpolitics-redis \
  -o jsonpath="{.data.redis-password}" | base64 -d
```

Example output:

```
NiJZSC7CFr
```

---

### **5. Redis connection URL**

```
redis://:PASSWORD@careerpolitics-redis-master.redis.svc.cluster.local:6379
```

Example:

```
redis://:NiJZSC7CFr@careerpolitics-redis-master.redis.svc.cluster.local:6379
```

---

# **Step 6: Install Cert-Manager (SSL Certificates)**

### **1. Install Cert-Manager CRDs + components**

```bash
kubectl apply --validate=false -f https://github.com/cert-manager/cert-manager/releases/download/v1.15.1/cert-manager.yaml

kubectl rollout status deployment/cert-manager -n cert-manager
kubectl rollout status deployment/cert-manager-webhook -n cert-manager
kubectl rollout status deployment/cert-manager-cainjector -n cert-manager
```

---

### **2. Apply the Let's Encrypt ClusterIssuer**

```bash
kubectl apply -f kube/cluster-issuer.yaml
kubectl describe clusterissuer letsencrypt-prod
```

Make sure the email in `cluster-issuer.yaml` is updated:

```yaml
spec:
  acme:
    email: your@email
```

---

### **3. (Optional) Create staging issuer for testing**

Switch ACME server:

```
https://acme-staging-v02.api.letsencrypt.org/directory
```

---

# **Step 7: Deploy Application Manifests**

Apply Deployment, Services, Ingress, etc.

```bash
kubectl apply -f kube/cluster-issuer.yaml
kubectl apply -f kube/deployment-web.yaml
kubectl apply -f kube/service-web.yaml
kubectl apply -f kube/deployment-worker.yaml
kubectl apply -f kube/ingress.yaml
```

Verify:

```
kubectl get all -n production
```

---

# **Step 8: Configure DNS for Ingress LoadBalancer**

### **1. Get the LoadBalancer IP**

```bash
kubectl get svc -n ingress-nginx
```

Look for the EXTERNAL-IP.

---

### **2. Add DNS A records**

```
Host: @
Value: <EXTERNAL-IP>
TTL: 300
```

```
Host: www
Value: <EXTERNAL-IP>
TTL: 300
```

---

### **3. Wait for DNS propagation**

SSL will only issue after domain resolves publicly.

---

# **Step 9: Validate SSL**

```bash
kubectl get certificate,certificaterequest,order -n production
kubectl describe certificate careerpolitics-tls -n production
kubectl logs deploy/cert-manager -n cert-manager --tail=200
```

Healthy certificate:

```
Ready=True
```

---

# **Step 10: Access the Application**

Visit:

```
https://careerpolitics.com
```

🎉 Your application is now live on Kubernetes!

---

# **Optional: Enable Autoscaling**

```bash
kubectl autoscale deployment careerpolitics-web \
  --cpu-percent=50 --min=2 --max=5 -n production
```

---

# **Monitoring & Logs**

```bash
kubectl logs -f deployment/careerpolitics-web -n production
kubectl get pods -n production
kubectl describe ingress -n production
```

---
