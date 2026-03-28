# DevOps Internship Challenge
**Karlo Jagar**

---

## Overview

This repository contains the complete solution for the DevOps Internship Challenge. The project covers provisioning a Linux VM on Azure, containerizing a custom nginx application with Docker, pushing it to Docker Hub, and deploying it to an Azure Kubernetes Service (AKS) cluster exposed publicly via the Traefik ingress controller.

---

## Architecture

```
Internet
    │
    ▼
Azure Load Balancer (9.223.252.236:80)
    │
    ▼
Traefik Ingress Controller  ◄── Ingress rules (path: /)
    │
    ▼
nginx-service (ClusterIP: 10.0.240.125)
    │
    ▼
nginx Pod (karlojagar/moj-nginx:v2)
    │
    ▼
AKS Cluster — devops-aks (Sweden Central, Kubernetes 1.33.7)
```

Separately, the same Docker image runs on a standalone Azure VM:
```
Internet → Azure VM (20.199.137.109:80) → Docker container (nginx)
```

---

## Repository Structure

```
devops-challenge/
├── Dockerfile
├── index.html
├── k8s/
│   ├── deployment.yaml
│   ├── service.yaml
│   └── ingress.yaml
└── README.md
```

---

## Part 1 — Virtual Machine & Docker

### Azure VM

A Linux VM was provisioned on Azure with the following specifications:

| Parameter | Value |
|---|---|
| Name | devops-vm |
| Resource group | devops-challenge-rg |
| Region | Switzerland North (Zone 1) |
| OS | Ubuntu Server 24.04 LTS |
| Size | Standard B2ats v2 (2 vCPU, 1 GiB RAM) |
| Public IP | 20.199.137.109 |
| Subscription | Azure for Students |

![Azure VM Overview](screenshots/azure-vm.png)

### SSH Security

The VM was hardened to use SSH key-based authentication only. Password login was completely disabled by editing `/etc/ssh/sshd_config`:

```
PasswordAuthentication no
PubkeyAuthentication yes
```

A `devops` user was created with SSH key access. The SSH service was restarted to apply the changes:

```bash
sudo systemctl restart ssh
```

### Docker on a Separate Disk

Docker was installed and configured to store all data on a dedicated data disk (`/dev/sdb`, 32 GiB) rather than the OS disk. This is a best practice that prevents Docker data from filling up the OS disk and causing system issues.

The disk was formatted, mounted, and added to `/etc/fstab` for automatic mounting on reboot:

```bash
sudo mkfs.ext4 /dev/sdb
sudo mkdir -p /mnt/docker-data
sudo mount /dev/sdb /mnt/docker-data
echo '/dev/sdb /mnt/docker-data ext4 defaults 0 0' | sudo tee -a /etc/fstab
```

Docker was configured to use that disk via `/etc/docker/daemon.json`:

```json
{
  "data-root": "/mnt/docker-data"
}
```

Verified with:
```bash
docker info | grep "Docker Root Dir"
# Docker Root Dir: /mnt/docker-data
```

### Custom Nginx Image

A `Dockerfile` was written to build a custom nginx image that displays my full name in the browser:

```dockerfile
FROM nginx:alpine
COPY index.html /usr/share/nginx/html/index.html
```

`nginx:alpine` was chosen as the base image because it is extremely lightweight (~5MB) compared to the full nginx image (~200MB), which is a best practice for production images.

The image was built, tagged and pushed to Docker Hub:

```bash
docker build -t moj-nginx .
docker tag moj-nginx karlojagar/moj-nginx:v1
docker push karlojagar/moj-nginx:v1
```

Docker Hub: [hub.docker.com/r/karlojagar/moj-nginx](https://hub.docker.com/r/karlojagar/moj-nginx)

![Docker Desktop](screenshots/docker-desktop.png)

### Running on the VM

The image was pulled onto the Azure VM and run as a container with `--restart always` so it starts automatically whenever the VM reboots:

```bash
docker pull karlojagar/moj-nginx:v2
docker run -d -p 80:80 --restart always --name moj-nginx karlojagar/moj-nginx:v2
```

The application is publicly accessible at: **http://20.199.137.109**

![App running on Azure VM](screenshots/app-vm.png)

---

## Part 2 — Kubernetes

### AKS Cluster

An Azure Kubernetes Service cluster was provisioned with the following specifications:

| Parameter | Value |
|---|---|
| Cluster name | devops-aks |
| Resource group | devops-challenge-rg |
| Region | Sweden Central |
| Kubernetes version | 1.33.7 |
| Node size | Standard_D2s_v3 |
| Node count | 1 |
| Pricing tier | Free |
| Network configuration | Azure CNI Overlay |

![AKS Cluster Overview](screenshots/aks-cluster.png)

The local kubectl was connected to the AKS cluster using the Azure CLI:

```bash
az aks get-credentials --resource-group devops-challenge-rg --name devops-aks
kubectl get nodes
# NAME                                STATUS   ROLES    AGE   VERSION
# aks-agentpool-29782353-vmss000000   Ready    <none>   4m    v1.33.7
```

> **Note:** On AKS, worker nodes show `<none>` for roles because Azure manages the control plane separately. This is expected behaviour.

### Deploying the Nginx Image

A Kubernetes Deployment was created to run the nginx image from Docker Hub:

```yaml
# deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
spec:
  replicas: 1
  selector:
    matchLabels:
      app: moj-nginx
  template:
    metadata:
      labels:
        app: moj-nginx
    spec:
      containers:
      - name: moj-nginx
        image: karlojagar/moj-nginx:v2
        ports:
        - containerPort: 80
```

A ClusterIP Service was created to allow internal cluster communication:

```yaml
# service.yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
spec:
  selector:
    app: moj-nginx
  ports:
  - port: 80
    targetPort: 80
  type: ClusterIP
```

```bash
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
kubectl get pods
# NAME                                    READY   STATUS    RESTARTS   AGE
# nginx-deployment-7bbfc56b5b-bxtd8       1/1     Running   0          3m
```

### Traefik Ingress Controller

Traefik was installed as the ingress controller using Helm:

```bash
helm repo add traefik https://traefik.github.io/charts
helm repo update
helm install traefik traefik/traefik --namespace traefik --create-namespace
```

An Ingress resource was created to route all incoming traffic to the nginx service:

```yaml
# ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx-ingress
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web
spec:
  ingressClassName: traefik
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: nginx-service
            port:
              number: 80
```

```bash
kubectl apply -f ingress.yaml
kubectl get svc -n traefik
# NAME      TYPE           CLUSTER-IP     EXTERNAL-IP     PORT(S)
# traefik   LoadBalancer   10.0.240.125   9.223.252.236   80:30606/TCP,443:30370/TCP
```

![kubectl output](screenshots/kubectl-output.png)

Traefik received public IP `9.223.252.236` from the Azure Load Balancer. The application is publicly accessible at: **http://9.223.252.236**

![App on AKS via Traefik](screenshots/app-aks.png)

---

## Problems & Solutions

| Problem | Cause | Solution |
|---|---|---|
| Azure VM image dropdown only showed Windows images | The "Free account VM" wizard has a limited marketplace | Used the standard "Virtual machines" flow instead |
| West Europe region not supported on student subscription | Azure for Students has regional restrictions | Changed region to Switzerland North |
| Port 80 not accessible from the internet | Azure NSG blocks all ports by default | Added an inbound port rule for HTTP (80) in Azure portal |
| AKS cluster creation failed — vCPU quota was 0 | Azure for Students has very limited vCPU quotas | Tried multiple regions until finding availability in Sweden Central |
| minikube not found after winget install | winget did not add minikube to the system PATH | Manually downloaded minikube.exe and added it to PATH |
| App showing old version after image update | Kubernetes Pod was still using the old image tag | Used `kubectl set image` to update the deployment to v2 |

---

## Key Concepts

### What does an ingress controller do?
An ingress controller is the "gatekeeper" of a Kubernetes cluster. It receives all external HTTP traffic through a single entry point and routes it to the correct internal service based on defined rules. For example, routing `/api` to a backend service and `/` to a frontend service — all through one public IP address.

### What is Traefik's role?
Traefik is a concrete implementation of an ingress controller. Kubernetes defines the concept of ingress but does not ship a router — you need to install something that does the actual routing. Traefik is one of the most popular options. It automatically discovers services in the cluster and configures itself when new services are added.

### How does traffic get from the internet to the container?
```
1. User opens http://9.223.252.236 in their browser
2. Request hits the Azure Load Balancer (the cluster's public face)
3. Azure Load Balancer forwards to Traefik
4. Traefik reads the path and routes to the correct service
5. Kubernetes Service (ClusterIP) finds the correct Pod
6. Pod (nginx container) responds
```

### What is load balancing?
Load balancing distributes incoming requests across multiple instances of an application so no single instance gets overwhelmed. If one Pod crashes, the load balancer automatically stops sending traffic to it and distributes requests across the remaining healthy ones.

### ClusterIP vs NodePort vs LoadBalancer

| Type | Accessibility | Use case |
|---|---|---|
| ClusterIP | Inside cluster only | Databases, internal services |
| NodePort | External, on a specific high port | Testing, dev environments |
| LoadBalancer | Public IP, standard port 80/443 | Production |

In this project: `nginx-service` uses **ClusterIP** (internal only, not exposed directly), while `traefik` uses **LoadBalancer** (gets a real Azure public IP and handles all external traffic).

---

## How to Run Locally

```bash
# Clone the repository
git clone https://github.com/karlojagar/devops-challenge
cd devops-challenge

# Build and run with Docker
docker build -t moj-nginx .
docker run -d -p 8080:80 moj-nginx
# Open http://localhost:8080

# Or deploy to Kubernetes locally with minikube
minikube start --driver=docker
kubectl apply -f k8s/
minikube tunnel
# Open http://127.0.0.1
```

---

## Live URLs

| Environment | URL |
|---|---|
| Azure VM (Docker) | http://20.199.137.109 |
| AKS + Traefik (Kubernetes) | http://9.223.252.236 |
| Docker Hub | https://hub.docker.com/r/karlojagar/moj-nginx |
