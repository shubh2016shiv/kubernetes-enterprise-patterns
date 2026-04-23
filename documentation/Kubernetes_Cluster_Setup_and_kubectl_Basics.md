# Kubernetes Cluster Setup and kubectl Basics

## From Zero to Running Your First Pod — A Complete Guide for ML/GenAI Engineers

---

> **Who this is for:** You are a Machine Learning or Generative AI Engineer. You write Python, build models, and deploy inference pipelines. You have zero Kubernetes knowledge. This guide takes you from understanding what a cluster actually is to running your first container on Kubernetes — with clear explanations of every decision you'll make along the way.

---

## Table of Contents

1. [The Mental Model — What Is a Kubernetes Cluster, Really?](#1-the-mental-model)
2. [Choosing Your Path — Local vs Cloud Clusters](#2-choosing-your-path)
3. [Local Cluster Options — minikube, kind, and k3s](#3-local-cluster-options)
4. [Cloud Clusters — EKS, GKE, and AKS](#4-cloud-clusters)
5. [Installing kubectl — Your Window to the Cluster](#5-installing-kubectl)
6. [Configuring Access — kubeconfig Demystified](#6-configuring-access)
7. [Context Management — Switching Between Clusters](#7-context-management)
8. [Your First Commands — Exploring the Cluster](#8-first-commands)
9. [Deploying Your First Workload](#9-deploying-first-workload)
10. [Cleaning Up and Next Steps](#10-cleaning-up)

---

## 1. The Mental Model

### What Is a Kubernetes Cluster, Really?

Before installing anything, you need the right mental model. A Kubernetes cluster is not a single machine or a simple server. It is a **distributed system** — a group of computers that work together as one unit.

```
╔══════════════════════════════════════════════════════════════════════════════╗
║                     KUBERNETES CLUSTER: THE BIG PICTURE                      ║
╠══════════════════════════════════════════════════════════════════════════════╣
║                                                                              ║
║   ┌──────────────────────────────────────────────────────────────────────┐   ║
║   │                            CONTROL PLANE                             │   ║
║   │                             (The Brain)                              │   ║
║   │                                                                      │   ║
║   │  ┌────────────────┐      ┌────────────────┐      ┌────────────────┐  │   ║
║   │  │   API Server   │      │   Scheduler    │      │      etcd      │  │   ║
║   │  │    (The Hub)   │      │  (Placement)   │      │    (Memory)    │  │   ║
║   │  └────────────────┘      └────────────────┘      └────────────────┘  │   ║
║   │                                                                      │   ║
║   │  All decisions flow through the API Server.                          │   ║
║   │  etcd remembers everything. Scheduler decides where workloads go.    │   ║
║   └──────────────────────────────────┬───────────────────────────────────┘   ║
║                                      │                                       ║
║                                Communication                                 ║
║                                      ▼                                       ║
║   ┌──────────────────────────────────────────────────────────────────────┐   ║
║   │                             WORKER NODES                             │   ║
║   │                             (The Muscle)                             │   ║
║   │                                                                      │   ║
║   │  ┌────────────────┐      ┌────────────────┐      ┌────────────────┐  │   ║
║   │  │     Node 1     │      │     Node 2     │      │     Node 3     │  │   ║
║   │  │  ┌──────────┐  │      │  ┌──────────┐  │      │  ┌──────────┐  │  │   ║
║   │  │  │  Pod A   │  │      │  │  Pod C   │  │      │  │  Pod E   │  │  │   ║
║   │  │  │  (Your   │  │      │  │  (Your   │  │      │  │  (Your   │  │  │   ║
║   │  │  │   App)   │  │      │  │ ML Model │  │      │  │ Database │  │  │   ║
║   │  │  └──────────┘  │      │  └──────────┘  │      │  └──────────┘  │  │   ║
║   │  └────────────────┘      └────────────────┘      └────────────────┘  │   ║
║   │                                                                      │   ║
║   │  Each node runs kubelet (the node's brain) and container runtime.    │   ║
║   │  Nodes do the actual work — running your containers.                 │   ║
║   └──────────────────────────────────────────────────────────────────────┘   ║
║                                                                              ║
╚══════════════════════════════════════════════════════════════════════════════╝
```

### Why This Architecture Matters for ML/GenAI Engineers

As an ML engineer, you need to understand this architecture because:

| ML/GenAI Challenge               | How the Cluster Helps                         |
| -------------------------------- | --------------------------------------------- |
| Your LLM needs a GPU             | Scheduler places your pod on a node with GPU  |
| Model loading takes 2 minutes    | Pods stay alive, ready to serve after restart |
| Traffic spikes at product launch | Cluster scales pods automatically             |
| Multiple models in production    | Different nodes for different workloads       |
| Model weights are 40GB           | Persistent storage survives pod restarts      |

---

## 2. Choosing Your Path

### The Fundamental Decision: Local vs Cloud

This is the first decision you'll make. Here's a comparison to help you think through it:

```
╔══════════════════════════════════════════════════════════════════════════════╗
║                     LOCAL vs CLOUD: THE DECISION MATRIX                      ║
╠══════════════════════════════════════════════════════════════════════════════╣
║                                                                              ║
║   ┌──────────────────────────────┐      ┌──────────────────────────────┐     ║
║   │        LOCAL CLUSTERS        │      │        CLOUD CLUSTERS        │     ║
║   │                              │      │                              │     ║
║   │ Tools: minikube, kind, k3s   │      │ Services: EKS, GKE, AKS      │     ║
║   │                              │      │                              │     ║
║   ├──────────────────────────────┤      ├──────────────────────────────┤     ║
║   │                              │      │                              │     ║
║   │ ✅ PROS:                     │      │ ✅ PROS:                     │     ║
║   │ • Free to run                │      │ • GPUs available on-demand   │     ║
║   │ • No internet required       │      │ • Scales to thousands        │     ║
║   │ • Fast iteration             │      │ • Managed control plane      │     ║
║   │ • Learn without cost         │      │ • Production-ready           │     ║
║   │ • No credit card needed      │      │ • Multi-node simulation      │     ║
║   │                              │      │                              │     ║
║   ├──────────────────────────────┤      ├──────────────────────────────┤     ║
║   │                              │      │                              │     ║
║   │ ❌ CONS:                     │      │ ❌ CONS:                     │     ║
║   │ • Limited to 1-3 nodes       │      │ • Costs money ($$$ / month)  │     ║
║   │ • No real GPU access         │      │ • Requires cloud account     │     ║
║   │ • Can't test scaling         │      │ • Slower iteration           │     ║
║   │ • Single-node failure = loss │      │ • Configuration complexity   │     ║
║   │ • Not production-ready       │      │ • Vendor lock-in potential   │     ║
║   │                              │      │                              │     ║
║   └──────────────────────────────┘      └──────────────────────────────┘     ║
║                                                                              ║
║   ┌──────────────────────────────────────────────────────────────────────┐   ║
║   │                           RECOMMENDED PATH                           │   ║
║   │                                                                      │   ║
║   │  Phase 1: Start LOCAL (weeks 1-4)                                    │   ║
║   │  ├── Learn kubectl, pods, deployments                                │   ║
║   │  ├── Practice YAML manifests                                         │   ║
║   │  └── Build simple ML inference services                              │   ║
║   │                                                                      │   ║
║   │  Phase 2: Move to CLOUD (weeks 5+)                                   │   ║
║   │  ├── Deploy production ML services                                   │   ║
║   │  ├── Access real GPUs                                                │   ║
║   │  └── Learn cloud-specific tooling                                    │   ║
║   │                                                                      │   ║
║   └──────────────────────────────────────────────────────────────────────┘   ║
║                                                                              ║
╚══════════════════════════════════════════════════════════════════════════════╝
```

### Decision Guide

Answer these questions to find your path:

```
QUESTION 1: What is your goal?
├── Learning Kubernetes fundamentals → LOCAL (start here)
├── Building production ML inference → CLOUD (GKE recommended)
└── Both → Start LOCAL, migrate to CLOUD

QUESTION 2: Do you need GPU access?
├── No (learning basics) → LOCAL (CPU-only is fine)
├── Yes (running actual models) → CLOUD (GPU nodes required)
└── Maybe later → Start LOCAL, plan for CLOUD migration

QUESTION 3: What's your budget?
├── $0 (learning) → LOCAL
├── <$100/month → CLOUD (single small node)
└── >$100/month → CLOUD (full GPU cluster)

QUESTION 4: How fast do you need results?
├── Today → LOCAL (immediate access)
└── This week → CLOUD (account setup takes 1-2 days)
```

---

## 3. Local Cluster Options

### Comparison of Tools

```
╔══════════════════════════════════════════════════════════════════════════╗
║                    LOCAL KUBERNETES TOOLS: COMPARISON                    ║
╠══════════════════════════════════════════════════════════════════════════╣
║                                                                          ║
║  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐        ║
║  │     minikube     │  │       kind       │  │       k3s        │        ║
║  │                  │  │                  │  │                  │        ║
║  │ Kubernetes in a  │  │  Kubernetes in   │  │ Lightweight K8s  │        ║
║  │ Virtual Machine  │  │ Docker Container │  │ (half the size)  │        ║
║  ├──────────────────┤  ├──────────────────┤  ├──────────────────┤        ║
║  │                  │  │                  │  │                  │        ║
║  │ RAM: 2-4 GB      │  │ RAM: 2 GB min    │  │ RAM: 512 MB min  │        ║
║  │ CPU: 2 cores     │  │ CPU: 2 cores     │  │ CPU: 1 core      │        ║
║  │ Disk: 20 GB      │  │ Disk: 10 GB      │  │ Disk: 5 GB       │        ║
║  │                  │  │                  │  │                  │        ║
║  ├──────────────────┤  ├──────────────────┤  ├──────────────────┤        ║
║  │                  │  │                  │  │                  │        ║
║  │ Speed:    ***    │  │ Speed:    *****  │  │ Speed:    *****  │        ║
║  │ Features: ****   │  │ Features: ***    │  │  Features: ****  │        ║
║  │ Ease:     ****   │  │ Ease:     *****  │  │ Ease:     *****  │        ║
║  │                  │  │                  │  │                  │        ║
║  ├──────────────────┤  ├──────────────────┤  ├──────────────────┤        ║
║  │                  │  │                  │  │                  │        ║
║  │ Best For:        │  │ Best For:        │  │ Best For:        │        ║
║  │ * Full K8s       │  │ * CI/CD testing  │  │ * Edge/IoT       │        ║
║  │   feature test   │  │ * Quick demos    │  │ * Resource-      │        ║
║  │ * Addon testing  │  │ * Docker-first   │  │   limited envs   │        ║
║  │ * Beginners      │  │   workflows      │  │ * Home labs      │        ║
║  │                  │  │                  │  │                  │        ║
║  └──────────────────┘  └──────────────────┘  └──────────────────┘        ║
║                                                                          ║
║  ┌────────────────────────────────────────────────────────────────────┐  ║
║  │                  RECOMMENDATION FOR ML ENGINEERS                   │  ║
║  │                                                                    │  ║
║  │ 1. macOS/Linux with Docker -> kind (fastest, most modern)          │  ║
║  │ 2. Windows without WSL -> minikube (best compatibility)            │  ║
║  │ 3. Resource-constrained machine -> k3s (lightest)                  │  ║
║  │ 4. Beginners on any OS -> minikube (most documented)               │  ║
║  │                                                                    │  ║
║  └────────────────────────────────────────────────────────────────────┘  ║
║                                                                          ║
╚══════════════════════════════════════════════════════════════════════════╝
```

### Option 1: minikube (Recommended for Beginners)

minikube runs a full Kubernetes cluster inside a virtual machine. It is the most complete option and the best choice if you're just starting out.

#### Prerequisites

Before installing minikube, you need:

| Requirement                  | What It Is             | How to Check               |
| ---------------------------- | ---------------------- | -------------------------- |
| **Docker** or **containerd** | The container runtime  | Run `docker --version`     |
| **kubectl**                  | The CLI for Kubernetes | Run `kubectl version`      |
| **Hypervisor**               | For creating VMs       | VT-x/AMD-V enabled in BIOS |

#### Installation Steps

**Step 1: Install kubectl (Required for all options)**

```bash
# macOS with Homebrew (recommended)
brew install kubectl

# Verify installation
kubectl version --client

# Output should look like:
# Client Version: v1.29.0
# Kustomize Version: v5.0.1
```

**Step 2: Install a Hypervisor**

```bash
# macOS - Install VirtualBox OR hyperkit (choose one)
brew install hyperkit           # Faster, but requires hyperkit driver
brew install --cask virtualbox   # More compatible, but can have issues with M1/M2

# Linux - Install KVM
sudo apt-get install qemu-kvm libvirt-daemon-system

# Windows - Install Hyper-V or VirtualBox
# Download from: https://www.virtualbox.org/wiki/Downloads
```

**Step 3: Install minikube**

```bash
# macOS
brew install minikube

# Linux
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube

# Windows (with Chocolatey)
choco install minikube
```

**Step 4: Start Your First Cluster**

```bash
# Basic start (uses VirtualBox by default on macOS)
minikube start

# Specify hypervisor explicitly
minikube start --driver=hyperkit    # macOS with hyperkit
minikube start --driver=virtualbox   # VirtualBox
minikube start --driver=kvm2        # Linux with KVM

# With specific Kubernetes version
minikube start --kubernetes-version=v1.28.0

# With more resources (important for ML!)
minikube start --cpus=4 --memory=8192 --disk-size=30g

# Verify cluster is running
minikube status

# Expected output:
# minikube
# type: Control Plane
# host: Running
# kubelet: Running
# apiserver: Running
# kubeconfig: Configured
```

**Step 5: Interact with Your Cluster**

```bash
# kubectl is automatically configured to use minikube
kubectl get nodes

# Output:
# NAME       STATUS   ROLES           AGE   VERSION
# minikube   Ready    control-plane   2m    v1.28.0

# View cluster info
kubectl cluster-info

# Expected output:
# Kubernetes control plane is running at https://192.168.64.2:8443
# CoreDNS is running at https://192.168.64.2:8443/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
```

#### minikube Commands Reference

```bash
# Cluster lifecycle
minikube start              # Start cluster
minikube stop               # Stop cluster (preserves state)
minikube delete             # Delete cluster completely
minikube status             # Check cluster status

# Accessing the cluster
minikube dashboard          # Open Kubernetes dashboard in browser
minikube ssh                # SSH into the minikube VM
minikube tunnel             # Create route to LoadBalancer services

# Addons (extra features)
minikube addons list        # See available addons
minikube addons enable ingress    # Enable ingress controller
minikube addons enable metrics-server  # Enable monitoring

# Resource management
minikube config set cpus 4      # Set default CPU count
minikube config set memory 8192  # Set default memory

# Docker environment (for building images)
eval $(minikube docker-env)     # Point docker to minikube's daemon
docker ps                        # Should show containers in the cluster
```

#### Troubleshooting minikube

```bash
# If cluster won't start
minikube logs --all

# If Docker issues
minikube docker-env
# Follow the instructions to set environment variables

# If driver issues
minikube start --driver=virtualbox --force

# Clean up and restart
minikube delete
minikube start
```

### Option 2: kind (Kubernetes in Docker)

kind runs Kubernetes nodes as Docker containers. It is extremely fast and perfect for CI/CD workflows.

#### When to Use kind

```
╔══════════════════════════════════════════════════════════════════════════╗
║                             KIND: USE CASES                              ║
╠══════════════════════════════════════════════════════════════════════════╣
║                                                                          ║
║   [+] PERFECT FOR:                                                       ║
║   ├── CI/CD pipelines (fast cluster creation/teardown)                   ║
║   ├── Testing Kubernetes manifests                                       ║
║   ├── Quick experimentation                                              ║
║   ├── Resource-constrained environments                                  ║
║   └── When you already live in Docker                                    ║
║                                                                          ║
║   [-] NOT IDEAL FOR:                                                     ║
║   ├── Long-running development sessions                                  ║
║   ├── Testing persistent storage                                         ║
║   ├── Testing actual GPU workloads                                       ║
║   └── Complete Kubernetes feature testing                                ║
║                                                                          ║
╚══════════════════════════════════════════════════════════════════════════╝
```

#### Installation and Setup

```bash
# Install kind (macOS)
brew install kind

# Install kind (Linux)
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind

# Install kubectl (if not already installed)
brew install kubectl
```

#### Creating Your First kind Cluster

```bash
# Create a simple cluster
kind create cluster

# Verify
kubectl get nodes

# Output:
# NAME                 STATUS   ROLES           AGE   VERSION
# kind-control-plane   Ready    control-plane   2m    v1.28.0

# Create cluster with custom name
kind create cluster --name ml-cluster

# Create multi-node cluster (1 control plane + 2 workers)
cat > kind-config.yaml << 'EOF'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
- role: worker
- role: worker
EOF

kind create cluster --config=kind-config.yaml --name=multi-node

# List all clusters
kind get clusters

# Delete a cluster
kind delete cluster --name ml-cluster
```

#### Loading Images into kind

Unlike minikube, kind runs containers inside Docker, so you need to load images explicitly:

```bash
# Build your image (in minikube's Docker daemon)
eval $(minikube docker-env)
docker build -t my-ml-service:v1 .

# Load image into kind cluster
kind load docker-image my-ml-service:v1 --name ml-cluster

# Verify image is available
kubectl run test-pod --image=my-ml-service:v1 --rm -it --restart=Never
```

### Option 3: k3s (Lightweight Kubernetes)

k3s is a CNCF-certified Kubernetes distribution that runs in a single binary under 100MB. It uses half the memory and has no machine requirements beyond Ubuntu 18.04.

#### When to Use k3s

```
╔══════════════════════════════════════════════════════════════════════════╗
║                              k3s: USE CASES                              ║
╠══════════════════════════════════════════════════════════════════════════╣
║                                                                          ║
║   [+] PERFECT FOR:                                                       ║
║   ├── Edge computing and IoT                                             ║
║   ├── Development on Raspberry Pi                                        ║
║   ├── Single-server scenarios                                            ║
║   ├── Resource-constrained environments                                  ║
║   └── Learning Kubernetes basics                                         ║
║                                                                          ║
║   [!] CONSIDERATIONS:                                                    ║
║   ├── Simplified architecture (no HA by default)                         ║
║   ├── Different internal mechanisms than full K8s                        ║
║   └── Some advanced features require extra setup                         ║
║                                                                          ║
╚══════════════════════════════════════════════════════════════════════════╝
```

#### Installation

```bash
# Install k3s (single command!)
curl -sfL https://get.k3s.io | sh -

# Verify installation
kubectl get nodes

# Output:
# NAME              STATUS   ROLES                  AGE   VERSION
# my-server         Ready    control-plane,master   2m    v1.28.0

# Access kubeconfig
cat /etc/rancher/k3s/k3s.yaml

# Save to local kubeconfig
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
```

### Quick Comparison Summary

```bash
# MINIKUBE - Best for beginners, full features
minikube start --cpus=4 --memory=8192
# Takes: ~5 minutes first time
# RAM needed: 4-8 GB
# Perfect for: Learning, ML inference testing

# KIND - Best for CI/CD, fast iteration
kind create cluster
# Takes: ~1 minute
# RAM needed: 2-4 GB
# Perfect for: Testing manifests, quick experiments

# k3s - Best for resource-constrained, edge
curl -sfL https://get.k3s.io | sh -
# Takes: ~30 seconds
# RAM needed: 512 MB - 1 GB
# Perfect for: Raspberry Pi, edge, learning basics
```

---

## 4. Cloud Clusters

### Overview of Cloud Options

```
╔══════════════════════════════════════════════════════════════════════════════╗
║                    CLOUD KUBERNETES SERVICES COMPARISON                      ║
╠══════════════════════════════════════════════════════════════════════════════╣
║                                                                              ║
║  ┌──────────────────────┐  ┌──────────────────────┐  ┌──────────────────────┐║
║  │      Amazon EKS      │  │      Google GKE      │  │      Azure AKS       │║
║  │     (Elastic K8s)    │  │  (Google K8s Engine) │  │  (Azure K8s Service) │║
║  ├──────────────────────┤  ├──────────────────────┤  ├──────────────────────┤║
║  │                      │  │                      │  │                      │║
║  │ Provider: AWS        │  │ Provider: Google     │  │ Provider: Azure      │║
║  │ Control Plane: $0.10 │  │ Control Plane: $0.10 │  │ Control Plane: Free  │║
║  │ /hour per cluster    │  │ /hour per cluster    │  │                      │║
║  │                      │  │                      │  │                      │║
║  │ GPU: A100, V100,     │  │ GPU: A100, TPU       │  │ GPU: NVIDIA          │║
║  │ T4, Inferentia       │  │ support excellent    │  │ support              │║
║  │                      │  │                      │  │                      │║
║  ├──────────────────────┤  ├──────────────────────┤  ├──────────────────────┤║
║  │                      │  │                      │  │                      │║
║  │ Strengths:           │  │ Strengths:           │  │ Strengths:           │║
║  │ * AWS ecosystem      │  │ * Best GPU support   │  │ * Azure ML int.      │║
║  │ * Fargate option     │  │ * Autopilot mode     │  │ * Enterprise SAML    │║
║  │ * IAM integration    │  │ * ML workloads       │  │ * Hybrid cloud       │║
║  │                      │  │   optimized          │  │                      │║
║  │ Best For:            │  │                      │  │ Best For:            │║
║  │ * AWS-heavy teams    │  │ Best For:            │  │ * Azure users        │║
║  │ * ML inference       │  │ * ML/AI workloads    │  │ * Enterprise         │║
║  │ * Cost optimization  │  │ * Data engineering   │  │ * Microsoft shops    │║
║  │                      │  │                      │  │                      │║
║  └──────────────────────┘  └──────────────────────┘  └──────────────────────┘║
║                                                                              ║
║  ┌────────────────────────────────────────────────────────────────────────┐  ║
║  │                 RECOMMENDATION FOR ML/GENAI ENGINEERS                  │  ║
║  │                                                                        │  ║
║  │  [1st] GKE (Google Kubernetes Engine)                                  │  ║
║  │  ├── Best GPU support (A100, TPU available)                            │  ║
║  │  ├── Autopilot mode = no node management                               │  ║
║  │  ├── Optimized for ML workloads                                        │  ║
║  │  └── Strong documentation for ML use cases                             │  ║
║  │                                                                        │  ║
║  │  [2nd] EKS (Elastic Kubernetes Service)                                │  ║
║  │  ├── Best if your organization is AWS-native                           │  ║
║  │  ├── Great integration with SageMaker                                  │  ║
║  │  └── Extensive AWS ecosystem                                           │  ║
║  │                                                                        │  ║
║  │  [3rd] AKS (Azure Kubernetes Service)                                  │  ║
║  │  ├── Best if your organization is Azure-native                         │  ║
║  │  ├── Good Azure ML integration                                         │  ║
║  │  └── Enterprise features                                               │  ║
║  │                                                                        │  ║
║  └────────────────────────────────────────────────────────────────────────┘  ║
║                                                                              ║
╚══════════════════════════════════════════════════════════════════════════════╝
```

### Option 1: Google Kubernetes Engine (GKE)

GKE is Google's managed Kubernetes service and is the recommended choice for ML workloads due to its excellent GPU support and ML-optimized features.

#### Creating a GKE Cluster

**Prerequisites:**

- Google Cloud account (https://cloud.google.com)
- Google Cloud SDK installed (`gcloud`)

```bash
# Install Google Cloud SDK
# macOS
brew install google-cloud-sdk

# Authenticate
gcloud auth login

# Set your project
gcloud config set project your-project-id

# Set default region
gcloud config set compute/region us-central1
```

**Creating a Standard Cluster:**

```bash
# Create a cluster with 3 nodes
gcloud container clusters create ml-cluster \
    --zone=us-central1-a \
    --num-nodes=3 \
    --machine-type=n2-standard-4

# Create a cluster with GPU nodes
gcloud container clusters create ml-gpu-cluster \
    --zone=us-central1-a \
    --num-nodes=2 \
    --machine-type=n1-standard-4 \
    --accelerator type=nvidia-tesla-v100,count=1

# Create an Autopilot cluster (Google manages nodes for you!)
gcloud container clusters create ml-autopilot \
    --zone=us-central1-a \
    --enable-autopilot \
    --num-nodes=3

# Get credentials for kubectl
gcloud container clusters get-credentials ml-cluster --zone=us-central1-a

# Verify
kubectl get nodes
```

**Understanding GKE Node Pools:**

```
╔══════════════════════════════════════════════════════════════════════════╗
║                     GKE: NODE POOLS FOR ML WORKLOADS                     ║
╠══════════════════════════════════════════════════════════════════════════╣
║                                                                          ║
║   CPU Node Pool (for orchestration)                                      ║
║   ┌──────────────────────────────────────────────────────────────────┐   ║
║   │ Machine: n2-standard-4 (4 vCPU, 16 GB RAM)                       │   ║
║   │ Nodes:   3 (default)                                             │   ║
║   │ Use:     API servers, schedulers, orchestrators                  │   ║
║   └──────────────────────────────────────────────────────────────────┘   ║
║                                                                          ║
║   GPU Node Pool (for inference/training)                                 ║
║   ┌──────────────────────────────────────────────────────────────────┐   ║
║   │ Machine: a2-highgpu-1g (12 vCPU, 85 GB RAM, 1x A100)             │   ║
║   │ Nodes:   1-10 (auto-scaled)                                      │   ║
║   │ Use:     LLM inference, model training                           │   ║
║   │ Cost:    ~$3.67/hour per A100                                    │   ║
║   └──────────────────────────────────────────────────────────────────┘   ║
║                                                                          ║
║   Creating a GPU node pool:                                              ║
║                                                                          ║
║   gcloud container node-pools create gpu-pool \                          ║
║      --cluster=ml-cluster \                                              ║
║      --zone=us-central1-a \                                              ║
║      --num-nodes=1 \                                                     ║
║      --machine-type=a2-highgpu-1g \                                      ║
║      --accelerator type=nvidia-tesla-a100,count=1                        ║
║                                                                          ║
╚══════════════════════════════════════════════════════════════════════════╝
```

**GKE Autopilot vs Standard:**

| Feature             | GKE Autopilot        | GKE Standard        |
| ------------------- | -------------------- | ------------------- |
| Node management     | Google manages       | You manage          |
| Pricing             | Pay per pod resource | Pay per node        |
| Scaling             | Automatic            | Manual              |
| GPU access          | Available            | Available           |
| Cost predictability | Lower                | Higher              |
| Best for            | Production ML        | Development/testing |

### Option 2: Amazon Elastic Kubernetes Service (EKS)

EKS is AWS's managed Kubernetes service, ideal if you're already using AWS services.

#### Creating an EKS Cluster

**Prerequisites:**

- AWS account
- AWS CLI installed and configured
- eksctl utility

```bash
# Install eksctl
brew install eksctl

# Authenticate with AWS
aws configure

# Create a basic cluster
eksctl create cluster \
    --name ml-cluster \
    --region us-west-2 \
    --nodes=3 \
    --node-type=m5.xlarge

# Create cluster with GPU nodes
eksctl create cluster \
    --name ml-gpu-cluster \
    --region us-west-2 \
    --nodes=2 \
    --node-type=p3.2xlarge \
    --with-oidc \
    --ssh-public-key=~/.ssh/id_rsa.pub

# This takes 15-20 minutes

# Configure kubectl
aws eks update-kubeconfig --name ml-cluster --region us-west-2

# Verify
kubectl get nodes
```

**EKS with Fargate (Serverless):**

```bash
# Create Fargate profile
eksctl create fargateprofile \
    --cluster ml-cluster \
    --region us-west-2 \
    --name ml-fargate-profile \
    --namespace ml-workloads

# Fargate automatically creates pods without node management
```

### Option 3: Azure Kubernetes Service (AKS)

AKS is Microsoft's managed Kubernetes service, integrated with Azure ML.

#### Creating an AKS Cluster

**Prerequisites:**

- Azure subscription
- Azure CLI installed

```bash
# Install Azure CLI
brew install azure-cli

# Login
az login

# Create resource group
az group create \
    --name ml-resource-group \
    --location eastus

# Create AKS cluster
az aks create \
    --resource-group ml-resource-group \
    --name ml-cluster \
    --node-count=3 \
    --generate-ssh-keys \
    --enable-addons monitoring

# Get credentials
az aks get-credentials \
    --resource-group ml-resource-group \
    --name ml-cluster

# Verify
kubectl get nodes
```

#### Cloud Cluster Cost Comparison for ML

```
╔══════════════════════════════════════════════════════════════════════════╗
║                  ESTIMATED MONTHLY COSTS FOR ML CLUSTER                  ║
║              (1 control plane + 3 nodes, GPU for inference)              ║
╠══════════════════════════════════════════════════════════════════════════╣
║                                                                          ║
║   GKE (Standard):                                                        ║
║   ├── Control plane: $73/month                                           ║
║   ├── 3x n2-standard-4: $450/month                                       ║
║   └── 1x A100 node (on-demand): $2,600/month                             ║
║   TOTAL: ~$3,100/month                                                   ║
║                                                                          ║
║   GKE (Autopilot, pay per pod):                                          ║
║   ├── Control plane: $73/month                                           ║
║   ├── Pods (CPU): ~$200/month                                            ║
║   └── Pods (GPU A100): ~$3,000/month (estimated usage)                   ║
║   TOTAL: ~$3,300/month (variable)                                        ║
║                                                                          ║
║   EKS:                                                                   ║
║   ├── Control plane: $73/month                                           ║
║   ├── 3x m5.xlarge: $500/month                                           ║
║   └── 1x p3.2xlarge (V100): ~$2,400/month                                ║
║   TOTAL: ~$3,000/month                                                   ║
║                                                                          ║
║   AKS:                                                                   ║
║   ├── Control plane: Free                                                ║
║   ├── 3x Standard_D4s_v3: $400/month                                     ║
║   └── 1x Standard_NC6s_v3: ~$2,200/month                                 ║
║   TOTAL: ~$2,600/month                                                   ║
║                                                                          ║
║   [!] COST OPTIMIZATION TIPS:                                            ║
║   ├── Use preemptible/spot instances (60-70% discount)                   ║
║   ├── Use node auto-scaling                                              ║
║   ├── Turn off clusters when not in use                                  ║
║   └── Consider GKE Autopilot for variable workloads                      ║
║                                                                          ║
╚══════════════════════════════════════════════════════════════════════════╝
```

---

## 5. Installing kubectl

### What Is kubectl?

kubectl is your command-line interface to Kubernetes. It is the tool you use to:

```
╔══════════════════════════════════════════════════════════════════════════╗
║                    kubectl: YOUR WINDOW TO KUBERNETES                    ║
╠══════════════════════════════════════════════════════════════════════════╣
║                                                                          ║
║   YOU (kubectl) --------------------> KUBERNETES CLUSTER                 ║
║                                                                          ║
║   Commands you run           What happens                                ║
║   ────────────────────────────────────────────────────────────────────   ║
║   kubectl get pods           "Show me all running pods"                  ║
║   kubectl apply -f app.yaml  "Deploy this application"                   ║
║   kubectl describe pod ml    "Tell me everything about pod 'ml'"         ║
║   kubectl logs ml-pod        "Show me the logs from pod 'ml'"            ║
║   kubectl delete pod ml      "Remove this pod"                           ║
║                                                                          ║
║   kubectl is to Kubernetes what:                                         ║
║   ├── ps is to Linux (process status)                                    ║
║   ├── docker is to Docker (container management)                         ║
║   └── git is to GitHub (version control)                                 ║
║                                                                          ║
╚══════════════════════════════════════════════════════════════════════════╝
```

### Installation Methods

**Method 1: Package Manager (Recommended for Beginners)**

```bash
# macOS with Homebrew
brew install kubectl

# Verify
kubectl version --client
# Client Version: v1.29.0

# Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y kubectl

# Fedora
sudo dnf install -y kubectl
```

**Method 2: Direct Download (Recommended for All)**

```bash
# macOS (Intel)
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/darwin/amd64/kubectl"

# macOS (Apple Silicon)
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/darwin/arm64/kubectl"

# Linux
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"

# Make it executable
chmod +x kubectl

# Move to your PATH
sudo mv kubectl /usr/local/bin/kubectl

# Verify
kubectl version --client
```

**Method 3: Install via SDKMAN (For Python/Java Developers)**

```bash
# Install SDKMAN first
curl -s "https://get.sdkman.io" | bash

# Install kubectl via SDKMAN
sdk install kubectl

# This also gives you kubectl version management
sdk use kubectl 1.28.0
```

### kubectl Autocomplete

**CRITICAL for productivity** - Always set up autocomplete:

```bash
# macOS with Homebrew zsh (Catalina and later)
# Add to ~/.zshrc
autoload -Uz compinit
compinit

# kubectl completion
source <(kubectl completion zsh)

# Or with Homebrew
brew install kubectl
echo 'source <(kubectl completion zsh)' >> ~/.zshrc

# Linux with bash
echo 'source <(kubectl completion bash)' >> ~/.bashrc
source ~/.bashrc

# Verify autocomplete works
kubectl g[Tab]  # Should show "get"
kubectl get [Tab]  # Should show "pods", "services", "deployments", etc.
```

### kubectl Plugins

Extend kubectl with plugins:

```bash
# Install kustomize (infrastructure templating)
brew install kustomize

# Install helm (package manager)
brew install helm

# Install kubectx (switch between contexts easily)
brew install kubectx

# Install k9s (terminal UI - highly recommended!)
brew install k9s

# Install Stern (tail logs across multiple pods)
brew install stern
```

---

## 6. Configuring Access

### Understanding kubeconfig

kubeconfig is the configuration file that tells kubectl how to connect to your Kubernetes clusters. Without it, kubectl doesn't know where your cluster is.

```
╔══════════════════════════════════════════════════════════════════════════╗
║                   kubeconfig: THE KEY TO YOUR CLUSTERS                   ║
╠══════════════════════════════════════════════════════════════════════════╣
║                                                                          ║
║   Default location: ~/.kube/config                                       ║
║                                                                          ║
║   ┌──────────────────────────────────────────────────────────────────┐   ║
║   │ apiVersion: v1                                                   │   ║
║   │ kind: Config                                                     │   ║
║   │ clusters:                                                        │   ║
║   │ - name: production                                               │   ║
║   │   cluster:                                                       │   ║
║   │     server: https://api.production.example.com                   │   ║
║   │     certificate-authority: /path/to/ca.crt                       │   ║
║   │                                                                  │   ║
║   │ users:                                                           │   ║
║   │ - name: admin                                                    │   ║
║   │   user:                                                          │   ║
║   │     client-certificate: /path/to/cert.crt                        │   ║
║   │     client-key: /path/to/key.pem                                 │   ║
║   │                                                                  │   ║
║   │ contexts:                                                        │   ║
║   │ - name: production-admin                                         │   ║
║   │   context:                                                       │   ║
║   │     cluster: production                                          │   ║
║   │     user: admin                                                  │   ║
║   │     namespace: ml-production                                     │   ║
║   └──────────────────────────────────────────────────────────────────┘   ║
║                                                                          ║
║   Components of kubeconfig:                                              ║
║   ├── clusters:  Where are the clusters? (server URLs)                   ║
║   ├── users:     Who are you? (authentication)                           ║
║   └── contexts:  Combine cluster + user + namespace                      ║
║                                                                          ║
╚══════════════════════════════════════════════════════════════════════════╝
```

### kubeconfig Structure Explained

```yaml
# Full kubeconfig example with three contexts
apiVersion: v1
kind: Config

# ─────────────────────────────────────────────────────────────────────────────
# CLUSTERS: Define your Kubernetes clusters
# ─────────────────────────────────────────────────────────────────────────────
clusters:
- name: local-minikube
  cluster:
    server: https://192.168.64.2:8443
    # Certificate for the cluster's API server
    certificate-authority: ~/.minikube/ca.crt

- name: gke-production
  cluster:
    server: https://34.82.123.456
    # Google Cloud uses certificate signed by Google CA
    certificate-authority-data: LS0tLS1...  # Base64 encoded

- name: eks-development
  cluster:
    server: https://ABC123XYZ.sk1.us-west-2.eks.amazonaws.com
    certificate-authority-data: LS0tLS1...

# ─────────────────────────────────────────────────────────────────────────────
# USERS: Define authentication credentials
# ─────────────────────────────────────────────────────────────────────────────
users:
- name: minikube-user
  # Token-based authentication
  user:
    token: eyJhbGc...  # Service account token

- name: gke-admin
  # Google Cloud authentication
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1beta1
      command: gke-gcloud-auth-plugin
      args:
      - get-token
      - --location
      - us-central1
      - --cluster
      - production-cluster

- name: eks-admin
  # AWS IAM authentication
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1beta1
      command: aws-iam-authenticator
      args:
      - token
      - -i
      - development-cluster

# ─────────────────────────────────────────────────────────────────────────────
# CONTEXTS: Combine cluster + user (and optional namespace)
# ─────────────────────────────────────────────────────────────────────────────
contexts:
- name: minikube-dev
  context:
    cluster: local-minikube
    user: minikube-user
    namespace: default

- name: gke-production-ml
  context:
    cluster: gke-production
    user: gke-admin
    namespace: ml-production

- name: eks-development-api
  context:
    cluster: eks-development
    user: eks-admin
    namespace: api-services

# ─────────────────────────────────────────────────────────────────────────────
# CURRENT CONTEXT: Which context is active?
# ─────────────────────────────────────────────────────────────────────────────
current-context: minikube-dev
```

### Managing Multiple Clusters

**Viewing Your Configuration:**

```bash
# View current kubeconfig
kubectl config view

# View with secrets masked (safe to share)
kubectl config view --flatten

# Show current context
kubectl config current-context

# List all contexts
kubectl config get-contexts

# Output:
# CURRENT   NAME                    CLUSTER           AUTHINFO       NAMESPACE
# *         minikube-dev             local-minikube    minikube-user  default
#           gke-production-ml        gke-production    gke-admin      ml-production
#           eks-development-api      eks-development    eks-admin      api-services
```

**Switching Between Contexts:**

```bash
# Switch to a different context
kubectl config use-context gke-production-ml

# Switch context shorthand
kubectl config use-context minikube-dev

# Verify current context
kubectl config current-context

# Now kubectl commands will target the new cluster
kubectl get pods  # Shows pods in gke-production-ml cluster
```

**Setting Default Namespace for a Context:**

```bash
# Set default namespace for current context
kubectl config set-context --current --namespace=ml-workloads

# Verify
kubectl config view | grep -A 5 "contexts:"
```

### Merging Multiple kubeconfig Files

When working with multiple tools (minikube, Docker Desktop, cloud providers), you may have multiple kubeconfig files:

```bash
# Default kubeconfig location
echo $KUBECONFIG
# Usually: ~/.kube/config

# If KUBECONFIG is not set, kubectl uses ~/.kube/config

# Merge kubeconfig from another file
export KUBECONFIG="$KUBECONFIG:~/.kube/config:~/.kube/config-minikube:~/.kube/config-gke"

# Or use KUBECONFIG environment variable
KUBECONFIG=~/.kube/config:~/.kube/my-cluster-config kubectl get contexts

# Append a new cluster config
kubectl config view --flatten > ~/.kube/config.merged
mv ~/.kube/config.merged ~/.kube/config
```

---

## 7. Context Management

### What Is a Context?

A context in Kubernetes is a **named combination** of:

1. A cluster to connect to
2. A user (with authentication credentials)
3. An optional default namespace

Think of contexts as **bookmarks** to different clusters. You switch between them without changing your commands.

```
╔══════════════════════════════════════════════════════════════════════════╗
║                  CONTEXTS: MULTIPLE CLUSTERS, ONE TOOL                   ║
╠══════════════════════════════════════════════════════════════════════════╣
║                                                                          ║
║   ┌──────────────────────────────────────────────────────────────────┐   ║
║   │                         ~/.kube/config                           │   ║
║   │                                                                  │   ║
║   │ Context: local-dev                                               │   ║
║   │ ├── Cluster:   kind-local                                        │   ║
║   │ ├── User:      developer                                         │   ║
║   │ └── Namespace: default                                           │   ║
║   │                                                                  │   ║
║   │ Context: gke-ml-production                                       │   ║
║   │ ├── Cluster:   gke-ml-project                                    │   ║
║   │ ├── User:      gke-admin                                         │   ║
║   │ └── Namespace: ml-production                                     │   ║
║   │                                                                  │   ║
║   │ Context: eks-data-science                                        │   ║
║   │ ├── Cluster:   eks-data-cluster                                  │   ║
║   │ ├── User:      data-team                                         │   ║
║   │ └── Namespace: inference                                         │   ║
║   └──────────────────────────────────────────────────────────────────┘   ║
║                                                                          ║
║   WORKFLOW:                                                              ║
║   kubectl config use-context gke-ml-production  <-- Switch context       ║
║   kubectl get pods                              <-- Shows prod pods      ║
║                                                                          ║
╚══════════════════════════════════════════════════════════════════════════╝
```

### Context Operations

```bash
# Rename a context
kubectl config rename-context old-name new-name

# Delete a context
kubectl config delete-context context-to-delete

# Set a context as current
kubectl config use-context my-context

# Update context credentials
kubectl config set-credentials my-user \
    --token=my-new-token

# View full context details
kubectl config view --context=my-context
```

### Practical Workflow: Managing ML Environments

```bash
# 1. Set up your contexts for different environments
#    (usually done automatically when you create clusters)

# 2. Create custom contexts with specific namespaces
kubectl config set-context staging \
    --cluster=gke-ml-project \
    --user=gke-admin \
    --namespace=ml-staging

# 3. Use k9s for visual context switching (recommended!)
#    Just run: k9s
#    Then press Ctrl+F to see all contexts

# 4. Quick status check across all clusters
for ctx in $(kubectl config get-contexts -o name); do
    echo "=== $ctx ==="
    kubectl --context $ctx get nodes --no-headers 2>/dev/null || echo "Cluster unreachable"
done
```

### Context Names Best Practices

Use descriptive names that tell you everything at a glance:

```
╔══════════════════════════════════════════════════════════════════════════╗
║                   NAMING CONVENTION: context-name                        ║
╠══════════════════════════════════════════════════════════════════════════╣
║                                                                          ║
║   FORMAT: <provider>-<team/department>-<environment>                     ║
║                                                                          ║
║   EXAMPLES:                                                              ║
║   ├── gke-mlops-production      --> GKE, ML team, production             ║
║   ├── eks-data-science-staging  --> EKS, data science, staging           ║
║   ├── aks-ml-platform-dev       --> AKS, ML platform team, development   ║
║   ├── kind-local-dev            --> kind, local machine, development     ║
║   └── minikube-learning         --> minikube, personal learning          ║
║                                                                          ║
║   WHAT NOT TO DO:                                                        ║
║   ├── context1                                                           ║
║   ├── test                                                               ║
║   ├── prod                                                               ║
║   └── k8s                                                                ║
║                                                                          ║
╚══════════════════════════════════════════════════════════════════════════╝---
```

## 8. Your First Commands

Now that you have kubectl installed and connected to a cluster, let's run some commands to explore your environment.

### Essential kubectl Commands

```
╔══════════════════════════════════════════════════════════════════════════╗
║                 kubectl CHEAT SHEET: ESSENTIAL COMMANDS                  ║
╠══════════════════════════════════════════════════════════════════════════╣
║                                                                          ║
║   GETTING INFORMATION                                                    ║
║   ────────────────────────────────────────────────────────────────────   ║
║   kubectl get pods                # List all pods in namespace           ║
║   kubectl get pods -n <ns>        # List pods in specific namespace      ║
║   kubectl get pods -A             # List pods in all namespaces          ║
║   kubectl get nodes               # List all nodes in cluster            ║
║   kubectl get services            # List all services                    ║
║   kubectl get deployments         # List all deployments                 ║
║   kubectl get namespaces          # List all namespaces                  ║
║   kubectl get events              # List all events (sorted by time)     ║
║                                                                          ║
║   DESCRIBING RESOURCES                                                   ║
║   ────────────────────────────────────────────────────────────────────   ║
║   kubectl describe pod <name>     # Detailed info about a pod            ║
║   kubectl describe node <name>    # Detailed info about a node           ║
║   kubectl describe svc <name>     # Detailed info about a service        ║
║                                                                          ║
║   CREATING AND APPLYING                                                  ║
║   ────────────────────────────────────────────────────────────────────   ║
║   kubectl apply -f <file.yaml>    # Apply config from file               ║
║   kubectl create -f <file.yaml>   # Create resources from file           ║
║   kubectl delete -f <file.yaml>   # Delete resources from file           ║
║   kubectl apply -f <dir/>         # Apply all YAML files in directory    ║
║                                                                          ║
║   LOGS AND EXEC                                                          ║
║   ────────────────────────────────────────────────────────────────────   ║
║   kubectl logs <pod-name>         # View pod logs (latest)               ║
║   kubectl logs -f <pod-name>      # Stream pod logs in real-time         ║
║   kubectl logs -p <pod-name>      # Logs from previous container run     ║
║   kubectl exec -it <pod> -- bash  # Open shell in running pod            ║
║                                                                          ║
║   DEBUGGING                                                              ║
║   ────────────────────────────────────────────────────────────────────   ║
║   kubectl port-forward <pod> 8080 # Forward local port to pod            ║
║   kubectl top nodes               # Show resource usage per node         ║
║   kubectl top pods                # Show resource usage per pod          ║
║   kubectl cordon <node>           # Mark node as unschedulable           ║
║   kubectl drain <node>            # Evict pods from node                 ║
║                                                                          ║
╚══════════════════════════════════════════════════════════════════════════╝
```

### Exploring Your Cluster

```bash
# 1. View cluster information
kubectl cluster-info

# Expected output:
# Kubernetes control plane is running at https://192.168.64.2:8443
# CoreDNS is running at https://192.168.64.2:8443/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy

# 2. List all nodes
kubectl get nodes

# Example output:
# NAME       STATUS   ROLES           AGE   VERSION
# minikube   Ready    control-plane   10m   v1.28.0

# 3. Get detailed node information
kubectl describe node minikube

# This shows:
# - Node capacity (CPU, memory, pods)
# - Node allocatable (what can be scheduled)
# - Node conditions (Ready, MemoryPressure, etc.)
# - Node events

# 4. List all namespaces
kubectl get namespaces

# Example output:
# NAME              STATUS   AGE
# default           Active   10m
# kube-node-lease   Active   10m
# kube-public       Active   10m
# kube-system       Active   10m

# 5. Understand what runs in kube-system
kubectl get pods -n kube-system

# This includes:
# - kube-apiserver: The API server
# - kube-controller-manager: Controllers
# - kube-scheduler: Scheduler
# - etcd: The datastore
# - coredns: DNS service
```

### Understanding Pod States

```bash
# List pods with more detail
kubectl get pods -o wide

# Example output:
# NAME                      READY   STATUS    RESTARTS   AGE   IP           NODE
# my-pod-abc123             1/1     Running   0          5m    10.244.0.5   minikube

# Understanding READY column:
# 1/1 means: 1 container ready out of 1 total containers
# For pods with multiple containers, this shows all

# Understanding STATUS column:
kubectl get pods

# STATUS meanings:
# Pending        → Pod is being scheduled or waiting for resources
# Running        → Pod is running on a node
# Succeeded      → Pod completed successfully (for jobs)
# Failed         → Pod failed (for jobs)
# CrashLoopBackOff → Container keeps crashing and restarting
# ImagePullBackOff  → Can't pull the container image
# Terminating    → Pod is being deleted

# View all possible phases
kubectl get pods --show-labels

# Filter pods by label
kubectl get pods -l app=ml-inference
kubectl get pods -l tier=frontend
```

### Understanding Resource Output Formats

```bash
# Default output (simple)
kubectl get pods

# Wide output (more details)
kubectl get pods -o wide

# JSON output (for scripting)
kubectl get pods -o json

# YAML output (for copying/configs)
kubectl get pod my-pod -o yaml

# Custom columns
kubectl get pods -o=custom-columns=\
  "NAME:.metadata.name",\
  "STATUS:.status.phase",\
  "NODE:.spec.nodeName"

# Example:
# NAME           STATUS    NODE
# my-pod-abc123  Running   minikube
```

---

## 9. Deploying Your First Workload

Now for the exciting part - deploying your first container to Kubernetes!

### Understanding the Basic Workflow

```
╔══════════════════════════════════════════════════════════════════════════╗
║                    THE KUBERNETES DEPLOYMENT WORKFLOW                    ║
╠══════════════════════════════════════════════════════════════════════════╣
║                                                                          ║
║   STEP 1: Write a YAML manifest (what you want)                          ║
║   ────────────────────────────────────────────────────────────────────   ║
║   ┌──────────────────────────────────────────────────────────────────┐   ║
║   │ apiVersion: apps/v1                                              │   ║
║   │ kind: Deployment                                                 │   ║
║   │ metadata:                                                        │   ║
║   │   name: ml-inference                                             │   ║
║   │ spec:                                                            │   ║
║   │   replicas: 3                                                    │   ║
║   │   selector:                                                      │   ║
║   │     matchLabels:                                                 │   ║
║   │       app: ml-inference                                          │   ║
║   │   template:                                                      │   ║
║   │     metadata:                                                    │   ║
║   │       labels:                                                    │   ║
║   │         app: ml-inference                                        │   ║
║   │     spec:                                                        │   ║
║   │       containers:                                                │   ║
║   │       - name: inference                                          │   ║
║   │         image: my-ml-model:v1                                    │   ║
║   │         ports:                                                   │   ║
║   │         - containerPort: 8000                                    │   ║
║   └──────────────────────────────────────────────────────────────────┘   ║
║                                                                          ║
║   STEP 2: Apply to cluster (kubectl apply)                               ║
║   ────────────────────────────────────────────────────────────────────   ║
║   kubectl apply -f deployment.yaml                                       ║
║                                                                          ║
║   STEP 3: Kubernetes creates the resources                               ║
║   ────────────────────────────────────────────────────────────────────   ║
║   Deployment --> Creates Pods --> Schedules --> Pulls Image --> Runs     ║
║                                                                          ║
║   STEP 4: Verify and monitor                                             ║
║   ────────────────────────────────────────────────────────────────────   ║
║   kubectl get pods                                                       ║
║   kubectl describe deployment ml-inference                               ║
║   kubectl logs <pod-name>                                                ║
║                                                                          ║
╚══════════════════════════════════════════════════════════════════════════╝
```

### Step 1: Create a Simple Deployment

Create a file named `deployment.yaml`:

```yaml
# deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ml-inference-demo
  labels:
    app: ml-inference
    environment: demo
spec:
  # How many copies of the pod should run?
  replicas: 2

  # How should we find the pods to manage?
  selector:
    matchLabels:
      app: ml-inference

  # What does each pod look like?
  template:
    metadata:
      labels:
        app: ml-inference
    spec:
      containers:
      - name: inference-server
        # Using a simple Python web server for demo
        # In real ML, this would be: your-ml-model:v1
        image: hashicorp/http-echo:latest
        args:
        - "-text=ML Inference Server is running!"
        ports:
        - containerPort: 5678
          name: http
        resources:
          requests:
            memory: "64Mi"
            cpu: "100m"
          limits:
            memory: "128Mi"
            cpu: "200m"
        livenessProbe:
          httpGet:
            path: /
            port: 5678
          initialDelaySeconds: 5
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /
            port: 5678
          initialDelaySeconds: 3
          periodSeconds: 5
```

### Step 2: Apply the Deployment

```bash
# Apply the deployment
kubectl apply -f deployment.yaml

# Verify deployment was created
kubectl get deployments

# Output:
# NAME              READY   UP-TO-DATE   AVAILABLE   AGE
# ml-inference-demo  2/2     2            2           10s

# What does READY mean?
# 2/2 → 2 pods ready out of 2 desired replicas

# Watch pods come up
kubectl get pods -w

# Output:
# NAME                              READY   STATUS    RESTARTS   AGE
# ml-inference-demo-7d9f8b-xk2p4   0/1     Pending   0          0s
# ml-inference-demo-7d9f8b-xk2p4   0/1     Running   0          2s
# ml-inference-demo-7d9f8b-xk2p4   1/1     Running   0          5s
# ml-inference-demo-7d9f8b-abc123  0/1     Running   0          3s
# ml-inference-demo-7d9f8b-abc123  1/1     Running   0          6s
```

### Step 3: Create a Service (Expose Your Deployment)

A Deployment manages your pods, but you need a Service to access them:

```yaml
# service.yaml
apiVersion: v1
kind: Service
metadata:
  name: ml-inference-service
  labels:
    app: ml-inference
spec:
  # Service type options:
  # - ClusterIP: Internal only (default)
  # - NodePort: Exposes via Node IP (for development)
  # - LoadBalancer: Cloud load balancer (for production)
  type: ClusterIP

  # Which pods does this service route to?
  selector:
    app: ml-inference

  # What ports does this service expose?
  ports:
  - port: 80
    targetPort: 5678
    protocol: TCP
    name: http
```

```bash
# Apply the service
kubectl apply -f service.yaml

# Verify service
kubectl get services

# Output:
# NAME                   TYPE        CLUSTER-IP      PORT(S)   AGE
# kubernetes             ClusterIP   10.96.0.1       443/TCP   30m
# ml-inference-service   ClusterIP   10.96.123.456   80/TCP    5s
```

### Step 4: Test Your Deployment

```bash
# Get pod names
kubectl get pods -l app=ml-inference

# Access logs from a pod
kubectl logs -l app=ml-inference

# Open shell in a pod
kubectl exec -it $(kubectl get pods -l app=ml-inference -o jsonpath='{.items[0].metadata.name}') -- /bin/sh

# Inside the pod, test the server
wget -qO- http://localhost:5678
# Output: ML Inference Server is running!

# Port-forward to access from your local machine
kubectl port-forward service/ml-inference-service 8080:80

# Now open browser to: http://localhost:8080
# You'll see: ML Inference Server is running!
```

### Step 5: Scale Your Deployment

```bash
# Scale up
kubectl scale deployment ml-inference-demo --replicas=5

# Verify new pods
kubectl get pods -l app=ml-inference

# Output:
# NAME                              READY   STATUS    RESTARTS   AGE
# ml-inference-demo-7d9f8b-xk2p4   1/1     Running   0          5m
# ml-inference-demo-7d9f8b-abc123  1/1     Running   0          5m
# ml-inference-demo-7d9f8b-def456  1/1     Running   0          30s
# ml-inference-demo-7d9f8b-ghi789  1/1     Running   0          30s
# ml-inference-demo-7dife8b-jkl012  1/1     Running   0          30s

# Scale down
kubectl scale deployment ml-inference-demo --replicas=2
```

### Step 6: Update Your Deployment

Update the deployment with a new image version:

```bash
# Update the image
kubectl set image deployment/ml-inference-demo \
    inference-server=hashicorp/http-echo:latest \
    --text="Updated ML Inference Server!"

# Watch the rollout
kubectl rollout status deployment/ml-inference-demo

# Output:
# Waiting for deployment "ml-inference-demo" rollout to finish: 1 out of 2 new replicas have been updated...
# Waiting for deployment "ml-inference-demo" rollout to finish: 1 out of 2 new replicas have been updated...
# Waiting for deployment "ml-inference-demo" rollout to finish: 1 old replicas are pending termination...
# deployment "ml-inference-demo" successfully rolled out

# If something goes wrong, rollback
kubectl rollout undo deployment/ml-inference-demo
```

### Complete YAML Reference for a Production ML Deployment

Here's a more complete example that includes what you'll need for real ML workloads:

```yaml
# ml-inference-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ml-inference-server
  namespace: ml-production
  labels:
    app: ml-inference
    version: v1
    team: ml-platform
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  selector:
    matchLabels:
      app: ml-inference
      version: v1
  template:
    metadata:
      labels:
        app: ml-inference
        version: v1
        team: ml-platform
    spec:
      # Security context
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        fsGroup: 1000

      containers:
      - name: inference
        image: gcr.io/my-project/ml-model:v1.2.0
        imagePullPolicy: Always
        ports:
        - name: http
          containerPort: 8000
          protocol: TCP

        env:
        - name: MODEL_NAME
          value: "llama-3-8b"
        - name: MAX_TOKENS
          value: "2048"
        - name: LOG_LEVEL
          value: "INFO"

        resources:
          requests:
            memory: "16Gi"
            cpu: "4"
            nvidia.com/gpu: "1"
          limits:
            memory: "20Gi"
            cpu: "8"
            nvidia.com/gpu: "1"

        livenessProbe:
          httpGet:
            path: /health
            port: 8000
          initialDelaySeconds: 60
          periodSeconds: 30
          timeoutSeconds: 5
          failureThreshold: 3

        readinessProbe:
          httpGet:
            path: /ready
            port: 8000
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 3
          failureThreshold: 5

        lifecycle:
          preStop:
            exec:
              command: ["/bin/sh", "-c", "sleep 10"]

      nodeSelector:
        node-type: gpu-compute
        accelerator: nvidia-a100

      tolerations:
      - key: "gpu-reserved"
        operator: "Equal"
        value: "true"
        effect: "NoSchedule"

      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchExpressions:
                - key: app
                  operator: In
                  values: [ml-inference]
              topologyKey: kubernetes.io/hostname
```

---

## 10. Cleaning Up and Next Steps

### Cleaning Up Resources

```bash
# Delete resources created in this guide
kubectl delete -f service.yaml
kubectl delete -f deployment.yaml

# Verify everything is deleted
kubectl get all

# For minikube, stop the cluster
minikube stop

# For kind, delete the cluster
kind delete cluster --name ml-cluster

# For cloud clusters, delete them
# GKE:
gcloud container clusters delete ml-cluster --zone=us-central1-a

# EKS:
eksctl delete cluster --name ml-cluster --region us-west-2

# AKS:
az aks delete --name ml-cluster --resource-group ml-resource-group
```

### What You've Learned

```
╔══════════════════════════════════════════════════════════════════════════╗
║                       CHECKLIST: WHAT YOU NOW KNOW                       ║
╠══════════════════════════════════════════════════════════════════════════╣
║                                                                          ║
║   CLUSTER FUNDAMENTALS                                                   ║
║   ├── [X] What a Kubernetes cluster is                                   ║
║   ├── [X] Difference between control plane and worker nodes              ║
║   ├── [X] How pods, deployments, and services work together              ║
║                                                                          ║
║   LOCAL DEVELOPMENT                                                      ║
║   ├── [X] Installed and configured minikube/kind/k3s                     ║
║   ├── [X] Started and stopped local clusters                             ║
║   ├── [X] Access cluster dashboard                                       ║
║                                                                          ║
║   kubectl MASTERING                                                      ║
║   ├── [X] Installed kubectl and configured autocomplete                  ║
║   ├── [X] Understood kubeconfig structure                                ║
║   ├── [X] Managed multiple contexts                                      ║
║   ├── [X] Run essential kubectl commands                                 ║
║                                                                          ║
║   CLOUD CLUSTERS                                                         ║
║   ├── [X] Understood GKE, EKS, and AKS options                           ║
║   ├── [X] Know how to create clusters on each cloud                      ║
║   ├── [X] Understood GPU node provisioning                               ║
║                                                                          ║
║   PRACTICAL SKILLS                                                       ║
║   ├── [X] Created a Kubernetes Deployment                                ║
║   ├── [X] Created a Kubernetes Service                                   ║
║   ├── [X] Scaled a deployment                                            ║
║   ├── [X] Updated a deployment                                           ║
║   ├── [X] Viewed logs and debugged issues                                ║
║   └── [X] Cleaned up resources                                           ║
║                                                                          ║
╚══════════════════════════════════════════════════════════════════════════╝
```

### Your Learning Path Forward

```
╔══════════════════════════════════════════════════════════════════════════╗
║                        NEXT STEPS: LEARNING PATH                         ║
╠══════════════════════════════════════════════════════════════════════════╣
║                                                                          ║
║   WEEK 1-2: Kubernetes Fundamentals                                      ║
║   ├── Continue with this guide (namespaces, configmaps, secrets)         ║
║   ├── Practice kubectl commands until they're muscle memory              ║
║   └── Deploy simple web applications                                     ║
║                                                                          ║
║   WEEK 3-4: ML Workloads on Kubernetes                                   ║
║   ├── Deploy a Python ML model serving API                               ║
║   ├── Configure resource requests and limits                             ║
║   ├── Set up persistent storage for model weights                        ║
║   └── Learn about GPU scheduling                                         ║
║                                                                          ║
║   WEEK 5-6: Advanced Kubernetes                                          ║
║   ├── Ingress controllers and networking                                 ║
║   ├── Helm charts for package management                                 ║
║   ├── Kubernetes operators and custom resources                          ║
║   └── RBAC and security                                                  ║
║                                                                          ║
║   WEEK 7-8: ML Platform Engineering                                      ║
║   ├── Model serving with KServe/Seldon                                   ║
║   ├── MLflow on Kubernetes                                               ║
║   ├── Argo Workflows for ML pipelines                                    ║
║   └── Observability with Prometheus/Grafana                              ║
║                                                                          ║
║   WEEK 9+: Production Readiness                                          ║
║   ├── GitOps with ArgoCD                                                 ║
║   ├── Multi-cluster strategies                                           ║
║   ├── Cost optimization                                                  ║
║   └── Disaster recovery                                                  ║
║                                                                          ║
╚══════════════════════════════════════════════════════════════════════════╝
```

### Recommended Next Documents

Based on the documents you already have, your next steps are:

1. **Review the documents you have:**
   
   - `kubernetes-for-genai-engineers.md` - Start from Phase 1
   - `docs_Kubernetes_for_Machine_Learning_Complete_Guide.md` - Section 1-2

2. **Create these topics as standalone learning modules:**
   
   - Namespaces, RBAC, and Security
   - ConfigMaps, Secrets, and Configuration Management
   - Persistent Storage and PVCS
   - Networking and Ingress
   - Helm and Kustomize
   - Monitoring and Observability

---

## Quick Reference: Commands Used in This Guide

```bash
# ─────────────────────────────────────────────────────────────────────────────
# INSTALLATION
# ─────────────────────────────────────────────────────────────────────────────
brew install kubectl                    # macOS kubectl
brew install minikube                   # macOS minikube
brew install kind                       # macOS kind
brew install k9s                       # macOS k9s (terminal UI)

# ─────────────────────────────────────────────────────────────────────────────
# CLUSTER MANAGEMENT
# ─────────────────────────────────────────────────────────────────────────────
minikube start                          # Start minikube
minikube stop                           # Stop minikube
minikube status                         # Check status
minikube delete                         # Delete cluster
minikube dashboard                      # Open dashboard

kind create cluster                     # Create kind cluster
kind delete cluster                     # Delete kind cluster

gcloud container clusters create        # Create GKE cluster
aws eks create-cluster                  # Create EKS cluster
az aks create                           # Create AKS cluster

# ─────────────────────────────────────────────────────────────────────────────
# kubectl FUNDAMENTALS
# ─────────────────────────────────────────────────────────────────────────────
kubectl version                         # Check kubectl version
kubectl cluster-info                    # Cluster information
kubectl get nodes                       # List nodes
kubectl get pods                       # List pods
kubectl get services                   # List services
kubectl get deployments                 # List deployments
kubectl get namespaces                 # List namespaces

kubectl describe pod <name>            # Detailed pod info
kubectl describe node <name>           # Detailed node info

kubectl apply -f file.yaml            # Apply YAML
kubectl delete -f file.yaml            # Delete YAML

kubectl logs <pod-name>               # View logs
kubectl logs -f <pod-name>            # Stream logs
kubectl exec -it <pod> -- bash         # Shell into pod

kubectl port-forward svc/<name> 8080:80  # Port forward

kubectl scale deployment <name> --replicas=5   # Scale

kubectl set image deployment/<name> <image>   # Update image
kubectl rollout status deployment/<name>      # Watch rollout
kubectl rollout undo deployment/<name>         # Rollback

# ─────────────────────────────────────────────────────────────────────────────
# kubeconfig MANAGEMENT
# ─────────────────────────────────────────────────────────────────────────────
kubectl config view                     # View kubeconfig
kubectl config get-contexts             # List contexts
kubectl config current-context          # Current context
kubectl config use-context <name>       # Switch context
kubectl config set-context --current --namespace=<ns>  # Set namespace
```

---

> **Remember:** Kubernetes is best learned by doing. Every concept in this guide becomes clear when you run the commands yourself. Start your cluster, deploy an application, break something, and fix it. That's how you learn Kubernetes.

---

**Next Guide:** [Namespaces, RBAC, and Security Fundamentals](02_Namespaces_RBAC_and_Security.md)
