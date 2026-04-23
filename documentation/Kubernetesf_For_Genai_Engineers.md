# Kubernetes for Generative AI Engineers

### A Zero-to-Production Field Guide for LLMs · RAG · Multi-Agent Systems · AI Inference at Scale

---

> **Who this is for:** You are a Generative AI Engineer. You write Python, build LLM pipelines, work with RAG, and deploy agents. You have zero Kubernetes knowledge today. This guide treats every single concept as brand new and explains it through the lens of the systems you already build.

---

## Table of Contents

1. [The Mental Model — What Is Kubernetes, Really?](#the-mental-model)
2. [Phase 1 — The Unit of Deployment: Mastering Containers](#phase-1)
   - [1.1 Multi-Stage Builds: Keeping AI Images Lean](#11-multi-stage-builds)
   - [1.2 GPU Pass-through: Letting Your Container See the GPU](#12-gpu-pass-through)
   - [1.3 Handling Large Model Weights (10 GB+)](#13-handling-large-model-weights)
3. [Phase 2 — Kubernetes Workloads: The Bread and Butter](#phase-2)
   - [2.1 The Cluster Mental Model](#21-the-cluster-mental-model)
   - [2.2 Pods and Deployments: Running Your Agents](#22-pods-and-deployments)
   - [2.3 Services: How Agents Find Each Other](#23-services)
   - [2.4 ConfigMaps and Secrets: Injecting API Keys Safely](#24-configmaps-and-secrets)
4. [Phase 3 — Resource Management: The Architect Level](#phase-3)
   - [3.1 Requests and Limits: GPU and Memory Budgeting](#31-requests-and-limits)
   - [3.2 Node Selectors and Affinity: GPU vs CPU Node Routing](#32-node-selectors-and-affinity)
   - [3.3 Persistent Volumes: Shared Storage for RAG and Models](#33-persistent-volumes)
5. [Phase 4 — AI-Specific Orchestration: The Pro Level](#phase-4)
   - [4.1 KubeRay: Distributed AI Across GPU Pods](#41-kuberay)
   - [4.2 KEDA: Event-Driven Autoscaling for Agent Queues](#42-keda)
   - [4.3 KServe and BentoML: Production Inference Servers](#43-kserve-and-bentoml)
6. [Reference Architecture: Full GenAI Platform on K8s](#reference-architecture)
7. [kubectl Cheat Sheet with AI Context](#kubectl-cheat-sheet)

---

---

## The Mental Model

### What Is Kubernetes, Really?

Before writing a single line of YAML, you need the right mental model. Kubernetes is not a deployment tool. It is an **operating system for a cluster of machines**.

Your laptop has macOS or Linux. That OS manages your CPU, RAM, and disk. It decides which application gets how much memory. It restarts a crashed process. It routes network traffic. You run your app and the OS handles the rest.

**Kubernetes does the exact same thing — but for a group of machines (called nodes) instead of one laptop.**

You tell Kubernetes: *"I want 3 copies of my RAG agent running, each needing 4 GB of RAM and 0.5 CPU cores."* Kubernetes looks at your pool of machines, finds ones with sufficient resources, places your containers on them, and then watches them forever. If one crashes at 3 AM, Kubernetes restarts it in seconds. If a machine dies, Kubernetes moves your containers to a healthy one. You sleep. The system stays up.

### Why AI Engineers Specifically Need Kubernetes

Most engineers first encounter K8s as "the thing DevOps uses." As a GenAI engineer, you need it for reasons that are uniquely yours:

| Problem you will hit                                           | What K8s does about it                                                    |
| -------------------------------------------------------------- | ------------------------------------------------------------------------- |
| Your LLM pod crashes at 3 AM                                   | Detects it in seconds and restarts it automatically                       |
| Serving 10x traffic during a product launch                    | Scales your inference pods up in real time                                |
| 10 engineers each spinning up their own GPU instance           | Schedules everyone's work onto shared GPU nodes — huge cost savings       |
| OpenAI key hardcoded in your Docker image                      | Injects credentials at runtime via Secrets — never in code or images      |
| Your Qdrant vector index wiped on pod restart                  | Persistent Volumes survive pod death forever                              |
| LLM takes 2 minutes to load but K8s routes traffic immediately | Readiness probes prevent traffic until the model is fully loaded          |
| Document processing queue backlog at peak hours                | KEDA scales worker pods from 0 to 50 based on queue depth, then back to 0 |
| 70B model too large for one GPU                                | KubeRay distributes it across multiple GPU nodes with 3 lines of Python   |

### The Six Objects You Must Know

Kubernetes has over 50 object types. As a GenAI engineer, you will live inside six of them. Master these and you can build anything.

```
  Pod            The actual running container — your LLM server, your RAG agent
  Deployment     The manager that keeps N pods alive at all times
  Service        A stable address so agents can find each other by name, not IP
  ConfigMap      Runtime config injected into pods (model names, endpoints, flags)
  Secret         Runtime credentials injected into pods (API keys, DB passwords)
  PersistentVol  A network disk that survives pod restarts (model weights, indexes)
```

---

---

## Phase 1

# Phase 1 — The Unit of Deployment: Mastering Containers

Everything in Kubernetes runs inside a container. Before deploying to K8s, you must master containerizing AI applications — which is far more complex than containerizing a web server. You are dealing with GPU drivers, multi-gigabyte model weights, CUDA libraries, and Python dependency chains that require C++ compilation.

---

## 1.1 Multi-Stage Builds

### The Problem: Naive AI Dockerfiles are Enormous

Most engineers write their first Dockerfile like this:

```dockerfile
# THE NAIVE APPROACH — never do this for production AI

FROM python:3.11

RUN apt-get install -y build-essential cmake gcc g++   # compilers
COPY requirements.txt .
RUN pip install -r requirements.txt                    # includes torch, vllm, faiss...
COPY ./src /app/src
CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

This image ends up **12–15 GB** because the build tools (`gcc`, `cmake`, etc.) are baked permanently into the final image alongside the compiled packages. When Kubernetes needs to spin up a new pod — because yours crashed or you are scaling — it must download this 15 GB image. On a GPU node that can take **10–15 minutes**. Your agent is dead for 15 minutes after every single crash.

### The Fix: Multi-Stage Builds

The idea is simple: use a heavy first stage to compile everything, then start fresh with a minimal second stage and copy only the compiled output. The final image never contains compilers, build tools, or anything that was only needed at compile time.

```
MULTI-STAGE BUILD FLOW

Stage 1: builder  ← temporary, NEVER shipped to Kubernetes
┌────────────────────────────────────────────────────────┐
│  FROM python:3.11                (full image)          │
│  + build-essential, cmake, gcc   (compilers)           │
│  + pip wheel → /build/wheels     (pre-compiled .whl)   │
│                     Final size: ~8 GB                  │
└──────────────────────────┬─────────────────────────────┘
                           │
   COPY --from=builder /build/wheels  (only compiled files)
                           │
                           ▼
Stage 2: runtime  ← this is what Kubernetes actually runs
┌────────────────────────────────────────────────────────┐
│  FROM python:3.11-slim           (lean, no compilers)  │
│  + pip install from wheels       (fast, no compiling)  │
│  + your application code                               │
│                     Final size: ~2.5 GB                │
└────────────────────────────────────────────────────────┘

Result: 68% smaller image → pod starts in 30 seconds, not 15 minutes
```

### Production Multi-Stage Dockerfile for a RAG Agent

```dockerfile
# =============================================================
# STAGE 1: builder
# This stage is temporary. Kubernetes never sees it.
# Its only job is to compile Python packages into .whl files.
# =============================================================
FROM python:3.11 AS builder

WORKDIR /build

# Install OS-level build tools needed to compile packages like
# faiss-cpu, tokenizers, and sentencepiece (they have C++ extensions).
# These will NOT appear in the final image — Stage 2 starts completely fresh.
RUN apt-get update && apt-get install -y \
    build-essential \
    curl \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .

# "pip wheel" compiles packages into .whl files without installing them.
# A .whl file is a pre-compiled zip — it installs instantly with no compiler needed.
# Think of it as: "do the hard work now so the runtime image doesn't have to."
RUN pip install --upgrade pip && \
    pip wheel \
        --no-cache-dir \
        --wheel-dir /build/wheels \
        -r requirements.txt


# =============================================================
# STAGE 2: runtime
# This is what Kubernetes runs on every pod.
# Starts completely fresh from a lean base image.
# Zero compilers. Zero build artifacts from Stage 1.
# =============================================================
FROM python:3.11-slim AS runtime

WORKDIR /app

# Copy ONLY the pre-compiled wheel files from the builder stage.
# The entire builder filesystem (8 GB of compilers and temp files) is discarded here.
COPY --from=builder /build/wheels /wheels
COPY --from=builder /build/requirements.txt .

# Install from pre-built wheels. No internet required. No compilation.
# This is just unzipping pre-compiled binaries — takes seconds.
RUN pip install \
        --no-cache-dir \
        --no-index \
        --find-links=/wheels \
        -r requirements.txt \
    && rm -rf /wheels

COPY ./src /app/src

# Security: never run as root inside a container.
# Kubernetes security policies frequently enforce this.
RUN useradd --create-home appuser && chown -R appuser /app
USER appuser

EXPOSE 8000
CMD ["uvicorn", "src.rag_agent:app", "--host", "0.0.0.0", "--port", "8000"]
```

### Key Commands Decoded

| Command                 | What it does                                         | When to use it                                                                  |
| ----------------------- | ---------------------------------------------------- | ------------------------------------------------------------------------------- |
| `FROM ... AS builder`   | Names this stage so later stages can reference it    | Always in multi-stage builds                                                    |
| `pip wheel --wheel-dir` | Compiles packages to `.whl` files without installing | When packages need C/C++ compilation: torch, faiss, tokenizers, flash-attention |
| `COPY --from=builder`   | Copies specific files from a previous stage          | The heart of multi-stage builds — discards everything else                      |
| `python:3.11-slim`      | Minimal Python image with no compilers or extras     | Always for your runtime stage                                                   |
| `USER appuser`          | Process runs as a non-root user inside the container | Always — K8s security policies require it                                       |

---

## 1.2 GPU Pass-through

### The Core Confusion

Your K8s **node** (the physical machine) has NVIDIA GPU drivers installed on its host OS. Your **container** is an isolated sandbox that by default sees nothing from the host. If you run `import torch; print(torch.cuda.is_available())` inside a naive container, you get `False`. Your LLM crashes before it even starts.

Two things must work together to bridge the gap:

```
╔══════════════════════════════════════════════════════════════════════════════╗
║                        GPU PASS-THROUGH: HOW IT WORKS                        ║
╠══════════════════════════════════════════════════════════════════════════════╣
║                                                                              ║
║  Physical Machine (the K8s node):                                            ║
║  ┌──────────────────────────────────────────────────────────────────────┐    ║
║  │                                                                      │    ║
║  │  ┌──────────────────────────┐                                        │    ║
║  │  │  NVIDIA A100 GPU (80 GB) │  ← the actual hardware                 │    ║
║  │  └────────────┬─────────────┘                                        │    ║
║  │               │                                                      │    ║
║  │  ┌────────────▼─────────────┐                                        │    ║
║  │  │  Host NVIDIA Driver 525+ │  ← installed on the OS                 │    ║
║  │  └────────────┬─────────────┘    (by cloud provider or admin)        │    ║
║  │               │                                                      │    ║
║  │  ┌────────────▼─────────────┐                                        │    ║
║  │  │  NVIDIA Container Toolkit│  ← THE BRIDGE                          │    ║
║  │  │  (nvidia-container-      │    installed once on each GPU node     │    ║
║  │  │     runtime)             │    makes /dev/nvidia0 visible          │    ║
║  │  └────────────┬─────────────┘    inside containers                   │    ║
║  │               │                                                      │    ║
║  │  ┌────────────▼─────────────┐                                        │    ║
║  │  │  Your Container (LLM Pod)│                                        │    ║
║  │  │  FROM nvidia/cuda:12.1   │  ← Part 2: CUDA libs in your image     │    ║
║  │  │  torch, vllm, etc.       │                                        │    ║
║  │  │  cuda.is_available()=True│  ← GPU visible! ✓                      │    ║
║  │  └──────────────────────────┘                                        │    ║
║  └──────────────────────────────────────────────────────────────────────┘    ║
║                                                                              ║
╚══════════════════════════════════════════════════════════════════════════════╝
```

**Part 1 (host side):** NVIDIA Container Toolkit installed on the node — done once by your cluster admin. You do not touch this.

**Part 2 (image side):** Your Docker image must be built FROM NVIDIA's official CUDA base images, which come pre-loaded with the CUDA runtime libraries that PyTorch, vLLM, and transformers need.

### Choosing the Right CUDA Base Image

Never use `python:3.11` for GPU workloads. Use images from `nvcr.io/nvidia/cuda`:

| Image                      | Contains                             | Size    | Use For                                            |
| -------------------------- | ------------------------------------ | ------- | -------------------------------------------------- |
| `cuda:12.1-base`           | Bare minimum CUDA runtime            | ~200 MB | Rare — only if you manually specify every CUDA lib |
| `cuda:12.1-cudnn8-runtime` | CUDA + cuDNN + runtime libs          | ~3 GB   | **Most LLM inference — use this**                  |
| `cuda:12.1-cudnn8-devel`   | Everything + headers + nvcc compiler | ~8 GB   | Compiling CUDA kernels — builder stage only        |

**cuDNN** is NVIDIA's neural network math library. Every LLM inference framework (vLLM, transformers, TensorRT-LLM) needs it at runtime. Always use the `cudnn8-runtime` variant in your runtime stage.

### GPU-Enabled Multi-Stage Dockerfile for vLLM

```dockerfile
# =============================================================
# STAGE 1: builder
# Uses the devel image because flash-attention and vLLM need
# CUDA headers to compile. This stage is never deployed.
# =============================================================
FROM nvcr.io/nvidia/cuda:12.1-cudnn8-devel-ubuntu22.04 AS builder

RUN apt-get update && apt-get install -y python3 python3-pip \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .

# vLLM and flash-attention require CUDA headers to compile.
# Those headers only exist in the -devel image.
RUN pip3 wheel --no-cache-dir --wheel-dir /wheels -r requirements.txt


# =============================================================
# STAGE 2: runtime
# Uses the smaller -runtime image.
# Has cuDNN for inference. No compiler. This is what K8s runs.
# =============================================================
FROM nvcr.io/nvidia/cuda:12.1-cudnn8-runtime-ubuntu22.04 AS runtime

RUN apt-get update && apt-get install -y python3 python3-pip \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /wheels /wheels
COPY requirements.txt .
RUN pip3 install --no-index --find-links=/wheels -r requirements.txt \
    && rm -rf /wheels

COPY ./src /app/src
WORKDIR /app

EXPOSE 8000
CMD ["python3", "-m", "vllm.entrypoints.openai.api_server", \
     "--model", "/models/llama-3-8b", \
     "--tensor-parallel-size", "1"]
```

### Installing the NVIDIA Device Plugin on Your Cluster

Without this, Kubernetes has no concept that GPUs exist as schedulable resources. The Device Plugin is a DaemonSet (a pod that automatically runs on every GPU node in your cluster) that advertises each node's GPUs to the K8s API server.

```bash
# Run once per cluster (usually done by whoever sets up the cluster)
kubectl apply -f \
  https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.15.0/deployments/static/nvidia-device-plugin.yml

# Verify GPU nodes now advertise their GPUs
kubectl describe node <gpu-node-name> | grep -A 5 "Capacity"

# Expected output:
# Capacity:
#   nvidia.com/gpu: 2      ← this node has 2 GPUs K8s can schedule work onto
# Allocatable:
#   nvidia.com/gpu: 2      ← both are currently free
```

Once installed, pods can request GPUs exactly like CPU and RAM — covered in Phase 3.

---

## 1.3 Handling Large Model Weights

### Why You Cannot Put Weights Inside the Docker Image

Llama-3-70B is ~40 GB. Mistral-7B is ~14 GB. If you `COPY` weights into your Docker image:

- Your image becomes 40+ GB — takes 30+ minutes to push to any container registry
- Every pod restart re-downloads 40 GB before it can start serving
- Scaling from 2 to 10 pods triggers 10 simultaneous 40 GB downloads
- Container registry storage costs become enormous

The solution: keep your image small and get weights from external storage at runtime.

### Strategy 1 — Download at Startup (Never for Production)

Simple: container starts, downloads model from HuggingFace, then serves it. Fatal flaw: every pod restart, every new scaling pod, re-downloads everything. A CrashLoopBackOff loop will re-download 14 GB repeatedly. Never use in production.

```bash
# entrypoint.sh — naive approach, do not use in production
#!/bin/bash
huggingface-cli download meta-llama/Meta-Llama-3-8B \
    --local-dir /tmp/models/llama-3-8b \
    --token "$HF_TOKEN"   # injected from K8s Secret

python -m vllm.entrypoints.openai.api_server --model /tmp/models/llama-3-8b
```

### Strategy 2 — Init Containers (Better, but Still Downloads Per-Pod)

An **Init Container** is a K8s concept: a container that runs before your main container starts. The main container only starts after ALL init containers complete successfully. This is cleaner because the server never starts with a partially downloaded model.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: llm-pod
  namespace: ai-platform
spec:

  # Init containers run BEFORE main containers.
  # If any init container fails, the pod restarts the failed init container.
  # The main containers never start until all init containers succeed.
  initContainers:
  - name: model-downloader
    image: python:3.11-slim
    command: ["python3", "-c", |
      import subprocess, os
      subprocess.run(['pip', 'install', '-q', 'huggingface_hub'], check=True)
      from huggingface_hub import snapshot_download
      snapshot_download(
          repo_id='meta-llama/Meta-Llama-3-8B',
          local_dir='/models/llama-3-8b',
          token=os.environ['HF_TOKEN'],
          ignore_patterns=['*.msgpack', '*.h5'],
      )
    ]
    env:
    - name: HF_TOKEN
      valueFrom:
        secretKeyRef:       # reads from a K8s Secret (Phase 2)
          name: hf-credentials
          key: token
    volumeMounts:
    - name: model-storage
      mountPath: /models    # init container writes here

  containers:
  - name: llm-server
    image: your-registry/vllm:latest
    command: ["python3", "-m", "vllm.entrypoints.openai.api_server",
              "--model", "/models/llama-3-8b"]
    volumeMounts:
    - name: model-storage
      mountPath: /models    # main container reads from the same volume

  volumes:
  - name: model-storage
    emptyDir: {}            # temporary volume shared between init and main container
                            # exists only as long as the pod lives
```

### Strategy 3 — Persistent Volume Pre-Population (Production Standard)

Download weights **once** to a Persistent Volume. Mount it read-only into every inference pod. No re-downloading on crashes, scaling, or restarts. This is the only approach used in production.

```
PERSISTENT VOLUME STRATEGY

One-time setup:
┌──────────────────────────────────────────────────────────────────┐
│  K8s Job: seed-llama3-70b                                        │
│  Runs once to completion.                                        │
│  Downloads Llama-3-70B from HuggingFace → writes to PV           │
│  Job exits. Weights live on the network disk forever.            │
└──────────────────────────────────────────────────────────────────┘

Every pod restart thereafter (instant):
┌──────────────────────────────────────────────────────────────────┐
│  Pod starts → mounts PV (takes ~1 second)                        │
│  Weights already there → loads into GPU VRAM in ~2 minutes       │ 
│  Serving in ~2 minutes instead of ~15 minutes                    │ 
└──────────────────────────────────────────────────────────────────┘

  Pod-1 ──reads──┐
  Pod-2 ──reads──┼──► PersistentVolume (40 GB of weights, permanent)
  Pod-3 ──reads──┘    downloaded exactly once, ever
```

We cover the full PersistentVolumeClaim YAML in Phase 3.3.

---

---

## Phase 2

# Phase 2 — Kubernetes Workloads: The Bread and Butter

This phase is what you will use every single day. How to run your agents so they stay up, how they communicate without hardcoded IPs, and how configuration gets injected safely.

---

## 2.1 The Cluster Mental Model

### A Kubernetes Cluster is a Company

```
KUBERNETES CLUSTER

┌──────────────────────────────────────────────────────────────────────────┐
│  CONTROL PLANE  (the executive floor — makes all decisions)              │
│                                                                          │
│  API Server          etcd                Controller Manager              │
│  ─────────────       ──────────────       ─────────────────────          │
│  The reception       The official         The department managers.       │
│  desk. Every         record book.         Their job: make reality        │
│  request goes        Stores ALL           match what etcd says           │
│  through here.       cluster state.       should exist. Forever.         │
│  kubectl talks       Who declared         "3 replicas wanted,            │
│  to this.            what, when.          2 running → create 1 more"     │
│                                                                          │
│  Scheduler                                                               │
│  ─────────────                                                           │
│  Assigns pods to                                                         │
│  nodes. Looks at                                                         │
│  available RAM/                                                          │
│  CPU/GPU on each                                                         │
│  node and picks.                                                         │
└────────────────────────────────────┬─────────────────────────────────────┘
                                     │ issues instructions to
                     ┌───────────────┼───────────────┐
                     ▼               ▼               ▼
             ┌────────────┐  ┌────────────┐  ┌────────────┐
             │  NODE 1    │  │  NODE 2    │  │  NODE 3    │
             │  GPU node  │  │  CPU node  │  │  CPU node  │
             │            │  │            │  │            │
             │  kubelet   │  │  kubelet   │  │  kubelet   │
             │  ────────  │  │  ────────  │  │  ────────  │
             │  The agent │  │  The agent │  │  The agent │
             │  running   │  │  running   │  │  running   │
             │  on each   │  │  on each   │  │  on each   │
             │  node.     │  │  node.     │  │  node.     │
             │  Starts    │  │  Starts    │  │  Starts    │
             │  and stops │  │  and stops │  │  and stops │
             │  containers│  │  containers│  │  containers│
             └────────────┘  └────────────┘  └────────────┘
```

### What Happens When You Run `kubectl apply`

```
You type: kubectl apply -f rag-agent-deployment.yaml
               │
               ▼
    API Server receives your YAML,
    validates it, authenticates you.
               │
               ▼
    etcd records the desired state:
    "3 replicas of rag-agent should exist"
               │
               ▼
    Scheduler sees 3 pods that need homes.
    Checks each node's free RAM/CPU/GPU.
    Pod-1 → Node-2  Pod-2 → Node-3  Pod-3 → Node-2
               │
               ▼
    kubelet on Node-2 and Node-3 receive instructions.
    They pull the Docker image and start the containers.
               │
               ▼
    Controller Manager enters its infinite watch loop:
    "Desired: 3 pods. Actual: 3 pods. ✓"
    (One dies) →
    "Desired: 3 pods. Actual: 2 pods. ✗ → creating replacement now."
```

This loop runs 24/7 without human intervention. You declare what you want. K8s continuously works to make it so.

### Namespaces — Logical Folders for Your Resources

```bash
# Create a dedicated namespace for your AI platform
kubectl create namespace ai-platform

# All resource commands need -n to specify the namespace
kubectl get pods -n ai-platform
kubectl get services -n ai-platform

# Typical namespace layout for an AI platform:
#   ai-platform   → your LLM servers, agents, RAG services
#   monitoring    → Prometheus, Grafana
#   ray-system    → KubeRay operator
#   keda          → KEDA operator
#   kserve        → KServe controller
```

---

## 2.2 Pods and Deployments

### The Most Important Rule in Kubernetes

> **Never create Pods directly. Always create Deployments.**

A Pod is the actual running container — your LLM server, your RAG agent. But if you create a Pod directly and it crashes, it stays dead. Nothing brings it back. K8s marks it `Failed` and does nothing.

A **Deployment** is a manager that creates pods from a blueprint and watches them forever. If one crashes, Deployment replaces it immediately. If you push a new image version, Deployment rolls it out one pod at a time so users never see downtime.

```
Direct Pod:                   Deployment (replicas: 3):

  create pod my-llm           apply deployment.yaml
        ↓                              ↓
  ┌───────────┐               ┌─────────────────────────────────┐
  │  my-llm   │               │  Deployment: rag-agent          │
  │  Running  │  crashes →    │                                 │
  │     ↓     │               │  Pod-1  Running ✓               │
  │  DEAD     │               │  Pod-2  Running ✓               │
  │  (nothing │               │  Pod-3  CRASHED ✗               │
  │  happens) │               │          → K8s creates Pod-4    │
  └───────────┘               │  Pod-4  Starting... Running ✓   │
                              └─────────────────────────────────┘
```

### The Complete Deployment YAML — Every Line Explained

```yaml
# rag-agent-deployment.yaml
#
# Keeps 3 copies of your RAG orchestrator running at all times.
# Automatic crash recovery. Zero-downtime rollouts. Self-healing.

apiVersion: apps/v1
# Which K8s API group this object belongs to.
# Deployments live in "apps/v1". Core objects (Pod, Service) use "v1".

kind: Deployment
# The type of object. K8s uses this to apply the right behavior.

metadata:
  name: rag-orchestrator
  # Unique name in the namespace. Used in:
  #   kubectl describe deployment rag-orchestrator -n ai-platform
  #   kubectl rollout status deployment/rag-orchestrator -n ai-platform

  namespace: ai-platform
  # Which namespace this lives in. Always set this explicitly.

  labels:
    app: rag-orchestrator
    tier: orchestration
  # Labels are key-value tags. They have no meaning to K8s by themselves.
  # You use them to: filter with kubectl, select pods in Services,
  # target resources with KEDA. Think of them as searchable metadata.

spec:
  replicas: 3
  # Maintain exactly 3 pods at all times.
  # Controller Manager enforces this number continuously.
  # 1 crashes → it creates 1 more, immediately.

  strategy:
    type: RollingUpdate
    # When you push a new image version, update pods one at a time.
    # Always some pods serving traffic during the rollout.
    rollingUpdate:
      maxSurge: 1
      # During rollout: temporarily run 4 pods (3+1 new).
      # Full capacity is maintained throughout.
      maxUnavailable: 0
      # Never drop below 3 healthy pods during rollout.
      # True zero-downtime deployments.

  selector:
    matchLabels:
      app: rag-orchestrator
  # This Deployment manages pods that have this label.
  # MUST match spec.template.metadata.labels below.
  # Mismatch = Deployment cannot find its own pods.

  template:
  # The blueprint for every pod this Deployment creates.
    metadata:
      labels:
        app: rag-orchestrator   # MUST match selector.matchLabels above

    spec:
      restartPolicy: Always
      # If a container inside the pod crashes, restart it on the same node.
      # For Deployments, Always is the only valid option.

      containers:
      - name: rag-orchestrator
        image: your-registry.io/rag-orchestrator:v2.1
        # Always use a specific version tag in production.
        # Never :latest — makes rollbacks impossible.

        imagePullPolicy: Always
        # Always pull the image from the registry on pod start.
        # Use IfNotPresent in development (faster iteration).

        ports:
        - containerPort: 8000
        # The port your FastAPI app listens on inside the container.
        # This is documentation-only — it does not expose the port.
        # Services (next section) handle actual traffic routing.

        env:
        # Environment variables injected at runtime — NOT in the image.
        - name: RETRIEVER_SERVICE_URL
          value: "http://retriever-service:8001"
          # Uses K8s Service DNS name, not an IP.
          # Service names are stable forever. Pod IPs change every restart.

        - name: OPENAI_API_KEY
          valueFrom:
            secretKeyRef:
              name: ai-api-keys    # Name of the Secret object
              key: openai-key      # Key inside the Secret
          # Reads from a K8s Secret at runtime.
          # The key is never in the Docker image or in plaintext YAML.

        resources:
          requests:
            memory: "4Gi"
            # Minimum RAM guaranteed. Scheduler uses this for placement.
            # Set this to your pod's typical memory usage.
            cpu: "500m"
            # 500 millicores = 0.5 of one CPU core. Guaranteed minimum.
          limits:
            memory: "8Gi"
            # Hard ceiling. Exceed this → OOM-killed and restarted.
            # Prevents one leaking agent from crashing the whole node.
            cpu: "2000m"
            # Soft ceiling. Exceed this → CPU-throttled (slowed, not killed).

        livenessProbe:
          # Is the pod alive?
          # K8s calls this periodically. Fail 3x consecutively → restart container.
          # Catches frozen processes, infinite loops, deadlocked threads.
          httpGet:
            path: /health
            port: 8000
          initialDelaySeconds: 30
          # Wait 30s after startup before first check. App needs boot time.
          periodSeconds: 10
          failureThreshold: 3
          # Restart after 3 consecutive failures (30 seconds of unresponsiveness).

        readinessProbe:
          # Is the pod READY to receive traffic?
          # FAIL → removed from Service load balancer (traffic stops, pod lives)
          # PASS → added to Service load balancer (traffic flows)
          #
          # WHY THIS IS CRITICAL FOR LLMS:
          # Llama-3-8B takes 2-3 minutes to load into GPU VRAM.
          # Without this probe, K8s routes user requests immediately after
          # the container starts — before the model is loaded.
          # Every request returns a 500 error. With this probe, traffic
          # only flows to pods that have fully loaded the model.
          httpGet:
            path: /ready
            port: 8000
          initialDelaySeconds: 60
          # Wait 60s before first readiness check. Model loading takes time.
          periodSeconds: 5
          failureThreshold: 24
          # Allow 120 seconds total (24 x 5s) for the model to load.
```

### What Your FastAPI App Must Implement

```python
# src/main.py
from fastapi import FastAPI, HTTPException

app = FastAPI()
_model_ready = False
_model = None

@app.on_event("startup")
async def load_model():
    global _model_ready, _model
    # This runs once when the pod starts.
    # K8s will NOT send traffic here until /ready returns 200.
    # So this function can take as long as needed — nobody is waiting.
    print("Loading model into GPU VRAM...")
    _model = await load_your_llm()   # takes 1-3 minutes for large models
    _model_ready = True
    print("Model ready. Pod is now accepting traffic.")

@app.get("/health")
def health():
    # Liveness probe. Just confirm the Python process is alive.
    # Do NOT check model state here. Keep it trivially simple.
    return {"status": "alive"}

@app.get("/ready")
def ready():
    # Readiness probe. Only return 200 when model is fully loaded.
    if not _model_ready:
        raise HTTPException(status_code=503, detail="Model still loading")
    return {"status": "ready"}

@app.post("/chat")
async def chat(request: dict):
    if not _model_ready:
        raise HTTPException(status_code=503, detail="Model not ready")
    result = await _model.generate(request["prompt"])
    return {"response": result}
```

### Essential Deployment Commands

```bash
# Deploy for the first time (or update an existing deployment)
kubectl apply -f rag-agent-deployment.yaml -n ai-platform

# Watch pods come up in real time
kubectl get pods -n ai-platform -w
# NAME                              READY   STATUS              RESTARTS
# rag-orchestrator-7d9f-abc12       0/1     ContainerCreating   0
# rag-orchestrator-7d9f-abc12       0/1     Running             0
# (readiness probe passes after model loads...)
# rag-orchestrator-7d9f-abc12       1/1     Running             0
# 1/1 = 1 container ready out of 1 total

# Push a new image version — triggers a rolling update
kubectl set image deployment/rag-orchestrator \
    rag-orchestrator=your-registry.io/rag-orchestrator:v2.2 \
    -n ai-platform

# Watch the rolling update (3 old pods replaced by 3 new ones, one at a time)
kubectl rollout status deployment/rag-orchestrator -n ai-platform

# New version has a bug? Roll back immediately (takes seconds)
kubectl rollout undo deployment/rag-orchestrator -n ai-platform
```

---

## 2.3 Services

### The Problem Services Solve

Every Pod in Kubernetes gets a random IP address when it starts. When a pod restarts, it gets a completely different IP. In a multi-agent system, this means your agents cannot reliably call each other.

A **Service** is a stable address that sits in front of a set of pods. The Service address never changes. Pods behind it come and go. The Service automatically updates its routing table. Your agents call each other by Service name — a permanent DNS hostname — never by pod IP.

```
WITHOUT SERVICES — fragile

  Orchestrator hardcodes: "Retriever is at 10.244.0.15"
  Retriever pod crashes and restarts with new IP: 10.244.1.89
  Orchestrator calls 10.244.0.15 → Connection Refused ✗
  Your pipeline is broken.


WITH SERVICES — production-grade

  ┌────────────────────┐
  │  Orchestrator Pod  │──► http://retriever-service:8001/search
  └────────────────────┘                  │
                                          ▼
                            ┌─────────────────────────────┐
                            │   Service: retriever-service │
                            │   ClusterIP: 10.96.50.100   │ ← NEVER CHANGES
                            └────────┬───────────┬─────────┘
                                     │           │  load balanced
                                     ▼           ▼
                               Pod-1 (running) Pod-2 (running)
                              10.244.1.89    10.244.2.15

  Pods crash, restart, scale up or down — the Service DNS name never changes.
  The Orchestrator always calls retriever-service:8001 and it always works.
```

### The Three Service Types You Need to Know

| Type                  | Where Accessible                        | Use For                                                                    |
| --------------------- | --------------------------------------- | -------------------------------------------------------------------------- |
| `ClusterIP` (default) | Only inside the cluster                 | Every internal agent-to-agent call                                         |
| `NodePort`            | Outside cluster via NodeIP:Port         | Development — test your API from your laptop without a cloud load balancer |
| `LoadBalancer`        | Public internet via cloud load balancer | The single public endpoint your users call                                 |

**The rule:** Every internal AI service uses `ClusterIP`. Only your public-facing API uses `LoadBalancer`. Exposing internal services to the internet is a security anti-pattern.

### Service YAML for a Full Multi-Agent RAG System

```yaml
# ─── Retrieval Agent (internal only) ─────────────────────────────────────────
# Orchestrator calls: http://retriever-service:8001/search
# The Service name is the DNS hostname. All pods in the cluster can resolve it.
apiVersion: v1
kind: Service
metadata:
  name: retriever-service   # becomes the DNS name: retriever-service.ai-platform.svc.cluster.local
  namespace: ai-platform
spec:
  selector:
    app: retriever-agent    # routes traffic to pods with this label
                            # must match your Deployment's pod labels exactly
  ports:
  - port: 8001              # the port other services use to CALL this service
    targetPort: 8000        # the port the actual pod listens on
  type: ClusterIP           # cluster-internal only (this is the default)
---
# ─── LLM Inference Server (internal only) ────────────────────────────────────
# Orchestrator calls: http://llm-service:8080/v1/chat/completions
apiVersion: v1
kind: Service
metadata:
  name: llm-service
  namespace: ai-platform
spec:
  selector:
    app: llm-server
  ports:
  - port: 8080
    targetPort: 8000
  type: ClusterIP
---
# ─── Public API Gateway (internet-facing) ────────────────────────────────────
# Cloud provider creates a real load balancer. Users call the public IP.
apiVersion: v1
kind: Service
metadata:
  name: api-gateway-service
  namespace: ai-platform
spec:
  selector:
    app: api-gateway
  ports:
  - port: 80
    targetPort: 8000
  type: LoadBalancer   # cloud creates a public IP; kubectl get svc to see it
```

### The Full Network Topology

```
MULTI-AGENT RAG SYSTEM — NETWORK TOPOLOGY

INTERNET
    │
    ▼
LoadBalancer Service: api-gateway-service  (public IP: 34.x.x.x)
    │
    ▼
API Gateway Pod  (auth, rate limiting, routing)
    │
    ├───────────────────────────┐
    ▼                           ▼
ClusterIP: orchestrator-svc  ClusterIP: processor-svc
    │                           │
    ▼                           ▼
Orchestrator Pods (3x)       Document Processor Pods (0-50x, KEDA)
    │
    ├──────────────────────┐
    ▼                      ▼
ClusterIP: retriever-svc  ClusterIP: llm-service
    │                      │
    ▼                      ▼
Retriever Pods (5x)      LLM Server Pod (GPU node, vLLM)
    │
    ▼
ClusterIP: qdrant-service
    │
    ▼
Qdrant Pod (vector DB)
```

### Calling Services from Python — The DNS Resolution

```python
# Inside any pod in the ai-platform namespace

import httpx, os

# These all resolve to the same Service. Use the short name.
RETRIEVER_URL = "http://retriever-service:8001"                              # recommended
RETRIEVER_URL = "http://retriever-service.ai-platform:8001"                  # explicit namespace
RETRIEVER_URL = "http://retriever-service.ai-platform.svc.cluster.local:8001" # full DNS name

# Best practice: read from environment variable, fall back to Service DNS name
LLM_URL = os.getenv("LLM_SERVICE_URL", "http://llm-service:8080")

async def call_llm(messages: list) -> str:
    async with httpx.AsyncClient(timeout=120.0) as client:
        response = await client.post(
            f"{LLM_URL}/v1/chat/completions",
            json={"model": "llama-3-8b", "messages": messages}
        )
        response.raise_for_status()
        return response.json()["choices"][0]["message"]["content"]
```

---

## 2.4 ConfigMaps and Secrets

### The Golden Rule

> Never hardcode configuration or credentials inside a Docker image.

Anything environment-specific (API keys, model paths, service URLs, database passwords) must be injected at runtime by Kubernetes. This means:

- The same Docker image runs in dev, staging, and production — only the injected config differs
- Rotating an API key means updating a Secret, not rebuilding and redeploying the image
- Credentials never appear in Git history or container registries
- Access to credentials can be controlled via Kubernetes RBAC

Kubernetes provides two objects for this: **ConfigMaps** (non-sensitive config) and **Secrets** (credentials).

### Creating ConfigMaps

```yaml
# ai-platform-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: ai-platform-config
  namespace: ai-platform
data:
  # Simple key-value pairs become environment variables in your pods
  LLM_MODEL_NAME: "llama-3-8b"
  LLM_MAX_TOKENS: "4096"
  LLM_TEMPERATURE: "0.7"
  RETRIEVER_TOP_K: "5"
  EMBEDDING_MODEL: "BAAI/bge-large-en-v1.5"
  VECTOR_DB_URL: "http://qdrant-service:6333"
  LOG_LEVEL: "INFO"

  # You can also store entire files. The key becomes the filename.
  # This gets mounted as /app/config/agent_config.json inside the pod.
  agent_config.json: |
    {
      "max_iterations": 10,
      "tools": ["web_search", "calculator", "rag_retrieval"],
      "memory_type": "redis",
      "system_prompt": "You are a helpful AI assistant."
    }
```

```bash
# Apply it
kubectl apply -f ai-platform-config.yaml -n ai-platform

# Or create imperatively (good for quick testing)
kubectl create configmap ai-platform-config \
    --from-literal=LLM_MODEL_NAME=llama-3-8b \
    --from-literal=LLM_MAX_TOKENS=4096 \
    --from-file=agent_config.json \
    -n ai-platform
```

### Creating Secrets

```bash
# RECOMMENDED: create from literal values via kubectl
# Values are base64-encoded automatically. Never touch a file.
kubectl create secret generic ai-api-keys \
    --from-literal=openai-key="sk-proj-abc123..." \
    --from-literal=anthropic-key="sk-ant-abc123..." \
    --from-literal=huggingface-token="hf_abc123..." \
    -n ai-platform

# Verify (values are hidden by default in most tools)
kubectl get secret ai-api-keys -n ai-platform

# Decode a value to verify it stored correctly
kubectl get secret ai-api-keys -n ai-platform \
    -o jsonpath="{.data.openai-key}" | base64 --decode
```

> **On base64:** Kubernetes Secrets are base64-encoded, not encrypted. Anyone with `kubectl get secret` access can decode them. Base64 is not security — it is encoding. The real security wins are: credentials never in Docker images, never in Git, and access controlled via Kubernetes RBAC. For production-grade encryption at rest, pair K8s Secrets with the External Secrets Operator and AWS Secrets Manager or HashiCorp Vault.

### Consuming ConfigMaps and Secrets in Your Deployment

```yaml
spec:
  template:
    spec:
      containers:
      - name: rag-orchestrator
        image: your-registry.io/rag-orchestrator:v2.1

        # Pattern 1: single Secret value as one env var
        env:
        - name: OPENAI_API_KEY
          valueFrom:
            secretKeyRef:
              name: ai-api-keys      # the Secret object's name
              key: openai-key        # the key inside the Secret

        - name: ANTHROPIC_API_KEY
          valueFrom:
            secretKeyRef:
              name: ai-api-keys
              key: anthropic-key

        # Pattern 2: inject ALL keys from a ConfigMap as env vars at once
        # Every key in ai-platform-config becomes an environment variable.
        # LLM_MODEL_NAME, LLM_MAX_TOKENS, VECTOR_DB_URL, etc.
        envFrom:
        - configMapRef:
            name: ai-platform-config

        # Pattern 3: mount ConfigMap as files inside the container
        # Use for multi-line configs (JSON, YAML) that are awkward as env vars
        volumeMounts:
        - name: agent-config-vol
          mountPath: /app/config   # creates this directory in the container
          readOnly: true

      volumes:
      - name: agent-config-vol
        configMap:
          name: ai-platform-config
          items:
          - key: agent_config.json   # the key in the ConfigMap
            path: agent_config.json  # becomes /app/config/agent_config.json
```

### Reading It All in Python

```python
# src/main.py — zero hardcoded config, zero credentials in code
import os, json
from openai import AsyncOpenAI
from anthropic import AsyncAnthropic

# From Secrets (injected as env vars from secretKeyRef)
OPENAI_API_KEY    = os.environ["OPENAI_API_KEY"]     # raises if missing → fast failure
ANTHROPIC_API_KEY = os.environ["ANTHROPIC_API_KEY"]
HF_TOKEN          = os.getenv("HUGGINGFACE_TOKEN", "")  # optional

# From ConfigMap (injected via envFrom: configMapRef)
LLM_MODEL  = os.getenv("LLM_MODEL_NAME", "gpt-4o-mini")
MAX_TOKENS = int(os.getenv("LLM_MAX_TOKENS", "4096"))
VDB_URL    = os.getenv("VECTOR_DB_URL", "http://qdrant-service:6333")

# From ConfigMap mounted as a file
with open("/app/config/agent_config.json") as f:
    AGENT_CONFIG = json.load(f)

MAX_ITERATIONS = AGENT_CONFIG["max_iterations"]   # 10
TOOLS          = AGENT_CONFIG["tools"]            # ["web_search", ...]

# Initialize clients
openai_client    = AsyncOpenAI(api_key=OPENAI_API_KEY)
anthropic_client = AsyncAnthropic(api_key=ANTHROPIC_API_KEY)
```

---

---

## Phase 3

# Phase 3 — Resource Management: The Architect Level

This is where you provide the most value at a product company. Get resource management wrong and models OOM-crash, GPU nodes sit idle while CPU nodes are overloaded, and your team spends $15,000/month on GPU instances that run Python processes needing 0.1 CPU cores.

---

## 3.1 Requests and Limits

### The Two Numbers Every Pod Must Have

Every pod should declare a **request** (minimum guaranteed) and a **limit** (maximum allowed) for each resource.

```
           REQUESTS                        LIMITS
           ─────────────────────────       ──────────────────────────────
CPU        "Guarantee me this much         "Throttle (slow) me if I
            CPU — I need it always"         exceed this — don't kill me"
            Scheduler uses this.            Pod stays alive, just slower.

Memory     "Guarantee me this much         "OOM-kill me if I exceed this"
            RAM — I need it always"         Pod is killed and restarted.
            Scheduler uses this.            Protects the whole node.

GPU        "I need exactly this many       Must equal requests.
            GPUs — exclusive use"           GPUs are not fractionally
            Scheduler uses this.            shared by default in K8s.
```

### Why Requests Drive the Scheduling Decision

The Scheduler uses **requests** — not actual usage — to decide where to place a pod.

Imagine Node A has 100 Gi RAM. Pods on Node A have requested 90 Gi combined. The Scheduler sees only 10 Gi free on Node A — even if actual usage is only 40 Gi right now. This is by design: requests are commitments. The Scheduler must assume every pod could spike to its full requested amount simultaneously.

**Without requests:** Scheduler has no information. Your 16 Gi LLM pod might land on a node with 4 Gi free. Pod starts, begins loading weights, node runs out of RAM, OOM killer fires, pod dies, restarts, dies again — `CrashLoopBackOff`.

**With wrong requests (too low):** Same result. You said 2 Gi but actually need 16 Gi. Pod placed on node with 5 Gi free (looks fine to scheduler). Weights load. OOM kill.

**The rule:** Set `requests` to slightly above your pod's typical memory usage. Measure with `kubectl top pods` in staging first.

### Resource Units

```
CPU:
  1 CPU = 1 vCPU = 1000m (millicores)

  cpu: "1"      = 1 full core
  cpu: "500m"   = 0.5 core  (orchestrators, API wrappers)
  cpu: "250m"   = 0.25 core (very lightweight sidecars)
  cpu: "4"      = 4 cores   (LLM weight loading at startup)

Memory:
  memory: "256Mi"  = 256 megabytes
  memory: "4Gi"    = 4 gigabytes
  memory: "16Gi"   = 16 GB  (minimum for most local LLM inference)
  memory: "80Gi"   = 80 GB  (full A100 VRAM equivalent in system RAM)

GPU:
  nvidia.com/gpu: "1"  = 1 GPU, exclusively allocated
  nvidia.com/gpu: "2"  = 2 GPUs (tensor parallel for 70B+ models)

  GPU requests MUST equal GPU limits — K8s enforces this.
  GPU allocation is exclusive — no other pod shares your GPU.
```

### Resource Sizing Reference for GenAI Workloads

| Workload                         | CPU Request / Limit | RAM Request / Limit | GPU            |
| -------------------------------- | ------------------- | ------------------- | -------------- |
| OpenAI / Anthropic API wrapper   | 0.25 / 1            | 256 Mi / 512 Mi     | None           |
| Local embedding (bge-large)      | 2 / 4               | 4 Gi / 8 Gi         | Optional       |
| RAG retriever (vector DB client) | 1 / 4               | 2 Gi / 4 Gi         | None           |
| LangGraph / CrewAI orchestrator  | 0.5 / 2             | 1 Gi / 2 Gi         | None           |
| Document chunker / parser        | 1 / 4               | 2 Gi / 4 Gi         | None           |
| Llama-3-8B (vLLM, 1 GPU)         | 4 / 8               | 16 Gi / 20 Gi       | 1 x A100 40 GB |
| Llama-3-70B (vLLM, tp=2)         | 8 / 16              | 32 Gi / 40 Gi       | 2 x A100 80 GB |
| Whisper large-v3                 | 2 / 4               | 8 Gi / 12 Gi        | 1 x A100 40 GB |
| SDXL / Flux image generation     | 4 / 8               | 12 Gi / 16 Gi       | 1 x A100 80 GB |
| Qdrant vector DB                 | 2 / 8               | 4 Gi / 16 Gi        | None           |

### Complete Resource Config for an LLM Deployment

```yaml
spec:
  template:
    spec:
      containers:
      - name: vllm-server
        image: vllm/vllm-openai:v0.6.3
        args:
        - --model=/models/llama-3-8b
        - --tensor-parallel-size=1
        - --gpu-memory-utilization=0.90   # vLLM uses 90% of GPU VRAM for KV cache

        resources:
          requests:
            memory: "16Gi"
            # Covers: model weights in system RAM, tokenizer, request buffers.
            # Measure actual usage in staging. Set slightly above peak.
            cpu: "4"
            # Weight loading is CPU-intensive at startup. Tokenization needs CPU too.
            nvidia.com/gpu: "1"
            # CRITICAL: Without this, the Scheduler does not route this pod
            # to a GPU node. The container starts, CUDA fails, pod crashes.
          limits:
            memory: "20Gi"
            # OOM-kill protection. Leave headroom above requests for:
            # long-context KV cache spikes, large batch requests.
            cpu: "8"
            # Allow CPU burst during model loading startup.
            nvidia.com/gpu: "1"
            # Must equal requests for GPUs. K8s enforces this.

        readinessProbe:
          httpGet:
            path: /health
            port: 8000
          initialDelaySeconds: 120   # Llama-3-8B takes ~2 min to load
          periodSeconds: 10
          failureThreshold: 18       # 180 second total grace period

        livenessProbe:
          httpGet:
            path: /health
            port: 8000
          initialDelaySeconds: 150
          periodSeconds: 30
          failureThreshold: 3
```

### Diagnosing Resource Failures

```bash
# Pod is stuck in Pending — no node has enough resources
kubectl describe pod <pod-name> -n ai-platform
# Look for Events like:
# "0/5 nodes are available: 3 Insufficient nvidia.com/gpu, 2 Insufficient memory"
# Fix: increase node count, reduce requests, or check GPU nodes exist

# Pod shows OOMKilled in status
kubectl describe pod <pod-name> -n ai-platform
# Look for: "Last State: Terminated, Reason: OOMKilled"
# Fix: increase limits.memory (and requests.memory to match)

# Pod is Running but very slow
kubectl top pods -n ai-platform   # requires metrics-server
# If CPU usage is at or near the limit → being throttled
# Fix: increase limits.cpu
```

---

## 3.2 Node Selectors and Affinity

### The Cost Problem

A real production AI cluster has two classes of hardware:

- **GPU nodes:** $5–$15/hour (A100, H100). Essential for LLM inference, embedding at scale.
- **CPU nodes:** $0.10–$0.50/hour. Fine for orchestrators, retrievers, API gateways.

Without routing rules, K8s places pods wherever resources are available. It might put your 0.5-CPU Python orchestrator on your $10/hour A100 node (enormous waste), or try to put your LLM server on a CPU-only node (CUDA error, crash).

```
╔══════════════════════════════════════════════════════════════════════════════╗
║                SCHEDULING EFFICIENCY: WITH VS WITHOUT ROUTING                ║
╠══════════════════════════════════════════════════════════════════════════════╣
║                                                                              ║
║       WITHOUT ROUTING RULES                      WITH ROUTING RULES          ║
║                                                                              ║
║  A100 GPU Node ($10/hr)                 A100 GPU Node ($10/hr)               ║
║  ┌──────────────────────┐               ┌──────────────────────┐             ║
║  │ Python Orchestrator  │      →        │    LLM Server Pod    │             ║
║  │ cpu: 0.5, ram: 1Gi   │               │   1 GPU, 16Gi RAM    │             ║
║  │ 0% GPU utilization   │               │   fully utilized ✓   │             ║
║  │ $9.50/hr wasted      │               └──────────────────────┘             ║
║  └──────────────────────┘                                                    ║
║                                         CPU Node ($0.30/hr)                  ║
║  CPU Node ($0.30/hr)                    ┌──────────────────────┐             ║
║  ┌──────────────────────┐               │ Python Orchestrator  │             ║
║  │    LLM Server Pod    │               │    RAG Retriever     │             ║
║  │ No GPU → CUDA error  │               │     API Gateway      │             ║
║  │    pod crashes ✗     │               │  all running fine ✓  │             ║
║  └──────────────────────┘               └──────────────────────┘             ║
║                                                                              ║
╚══════════════════════════════════════════════════════════════════════════════╝
```

### Step 1 — Label Your Nodes

```bash
# Label GPU nodes
kubectl label node gpu-node-1 node-type=gpu-compute accelerator=nvidia-a100 gpu-memory=80gb
kubectl label node gpu-node-2 node-type=gpu-compute accelerator=nvidia-a100 gpu-memory=80gb

# Label CPU nodes
kubectl label node cpu-node-1 node-type=cpu-general
kubectl label node cpu-node-2 node-type=cpu-general
kubectl label node cpu-node-3 node-type=cpu-general

# Verify
kubectl get nodes --show-labels
```

### Step 2 — nodeSelector (Simple, Always Start Here)

`nodeSelector` places a pod only on nodes that have ALL the listed labels. If no matching node exists, the pod stays `Pending`.

```yaml
# LLM Server — must run on a GPU node
spec:
  template:
    spec:
      nodeSelector:
        node-type: gpu-compute       # only nodes with this label
        accelerator: nvidia-a100    # and specifically A100s

      containers:
      - name: vllm-server
        resources:
          requests:
            nvidia.com/gpu: "1"     # also request the GPU resource itself
---
# Orchestrator — must run on cheap CPU node
spec:
  template:
    spec:
      nodeSelector:
        node-type: cpu-general      # prevents landing on expensive GPU nodes
```

### Step 3 — Node Affinity (More Flexibility)

Node Affinity gives you `required` (hard) and `preferred` (soft) rules, plus richer operators.

```yaml
spec:
  template:
    spec:
      affinity:
        nodeAffinity:

          # REQUIRED: pod WILL NOT schedule unless this is satisfied.
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: node-type
                operator: In
                values: [gpu-compute]
              - key: accelerator
                operator: In
                values: [nvidia-a100, nvidia-h100]  # either A100 or H100 is fine

          # PREFERRED: K8s tries to honor this, but not a hard requirement.
          # Use for: "I prefer 80 GB VRAM nodes for 70B models, 40 GB is OK too"
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 80   # 0-100, higher = stronger preference
            preference:
              matchExpressions:
              - key: gpu-memory
                operator: In
                values: [80gb]
          - weight: 20
            preference:
              matchExpressions:
              - key: gpu-memory
                operator: In
                values: [40gb]

        # podAntiAffinity: spread THIS deployment's replicas across DIFFERENT nodes.
        # Without this, 3 LLM replicas might land on 1 GPU node.
        # If that node dies, all 3 replicas die simultaneously.
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchExpressions:
                - key: app
                  operator: In
                  values: [llm-server]
              topologyKey: kubernetes.io/hostname   # "different physical nodes"
```

### Step 4 — Taints and Tolerations (Reserve GPU Nodes Exclusively)

Node Affinity lets pods TARGET GPU nodes. But other workloads can still land there. **Taints** flip the logic: a tainted node repels ALL pods that don't explicitly agree to the taint. Only pods with the matching **Toleration** can schedule on it.

```bash
# Taint GPU nodes — nothing can schedule here unless it tolerates the taint
kubectl taint nodes gpu-node-1 gpu-reserved=true:NoSchedule
kubectl taint nodes gpu-node-2 gpu-reserved=true:NoSchedule

# Now: try deploying any non-tolerating pod → stays Pending on all GPU nodes
# Monitoring pods, logging daemons, orchestrators → all bounce off GPU nodes
```

```yaml
# In your LLM Deployment (the only workload that runs on GPU nodes)
spec:
  template:
    spec:
      tolerations:
      - key: "gpu-reserved"
        operator: "Equal"
        value: "true"
        effect: "NoSchedule"
      # Toleration = "I am allowed to run on this tainted node"
      # Without this, the Scheduler rejects all GPU nodes for this pod.

      nodeSelector:
        node-type: gpu-compute   # still need this to AIM at GPU nodes
```

After this setup: GPU nodes only run LLM/embedding pods. Orchestrators, retrievers, and gateways naturally land on CPU nodes without any extra configuration.

---

## 3.3 Persistent Volumes

### Why You Need Them

Containers are ephemeral: when a pod dies, everything it wrote to disk is gone. The next pod starts with a clean slate from the Docker image. This is perfect for stateless services. It is catastrophic for:

- **Model weights** — 40 GB re-download on every pod restart without a PV
- **Vector indexes** — your Qdrant index is wiped every pod restart
- **Training checkpoints** — hours of fine-tuning lost on a crash
- **Agent conversation memory** — session state that must span multiple requests

**Persistent Volumes (PVs)** are network-attached storage that exist completely independently of pods. Data written to a PV survives pod restarts, pod migrations, and node failures.

### The Three Storage Objects

```
StorageClass
│   "The catalog of available storage products"
│   Example: AWS EFS (NFS), AWS EBS (SSD), GCP Filestore
│   Usually pre-created by your cluster admin.
│
└── on demand, K8s provisions:

PersistentVolume (PV)
│   "The actual storage unit" — a specific EFS filesystem or EBS volume.
│   Usually auto-created when you create a PVC (dynamic provisioning).
│
└── claimed by:

PersistentVolumeClaim (PVC)
    "YOUR storage request — this is what you create"
    "I need 500 Gi of ReadOnlyMany NFS storage"
    Pods mount PVCs, not PVs directly.
```

### Access Modes — Critical for Multi-Agent Architectures

| Mode          | Abbreviation | Meaning                                 | Use Case                                    |
| ------------- | ------------ | --------------------------------------- | ------------------------------------------- |
| ReadWriteOnce | RWO          | One pod reads and writes                | Qdrant vector DB (single writer)            |
| ReadOnlyMany  | ROX          | Many pods read simultaneously           | Model weights shared across 10 LLM replicas |
| ReadWriteMany | RWX          | Many pods read and write simultaneously | Shared agent cache, multi-worker training   |

> **Cloud reality:** AWS EBS only supports RWO. For ROX or RWX (shared access across pods), you must use AWS EFS, GCP Filestore, or Azure NFS File Shares. Plan your storage class accordingly before designing your platform architecture.

### Complete PVC Setup for a GenAI Platform

```yaml
# ─── StorageClass (pre-created by cluster admin, shown for context) ───────────
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: efs-sc                   # EFS = AWS Elastic File System (supports RWX/ROX)
provisioner: efs.csi.aws.com
parameters:
  provisioningMode: efs-ap
  fileSystemId: fs-0abc123456789
  directoryPerms: "700"
---
# ─── PVC 1: Model Weights (ReadOnlyMany) ─────────────────────────────────────
# All LLM inference pods mount this simultaneously to read the same weights.
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: model-weights-pvc
  namespace: ai-platform
spec:
  accessModes: [ReadOnlyMany]
  resources:
    requests:
      storage: 500Gi   # room for multiple large models
  storageClassName: efs-sc
---
# ─── PVC 2: Vector Database (ReadWriteOnce) ───────────────────────────────────
# Qdrant writes its index here. Single writer at a time.
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: qdrant-data-pvc
  namespace: ai-platform
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 100Gi
  storageClassName: efs-sc
---
# ─── PVC 3: Shared Agent Cache (ReadWriteMany) ────────────────────────────────
# Multiple agent pods write logs, checkpoints, intermediate results.
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: agent-cache-pvc
  namespace: ai-platform
spec:
  accessModes: [ReadWriteMany]
  resources:
    requests:
      storage: 50Gi
  storageClassName: efs-sc
```

### Using PVCs in Your Deployments

```yaml
spec:
  template:
    spec:
      containers:
      - name: vllm-server
        volumeMounts:
        - name: model-storage          # references spec.volumes below
          mountPath: /models           # where it appears inside the container
          readOnly: true               # inference pods must not modify weights

        - name: shared-cache
          mountPath: /app/cache

      volumes:
      - name: model-storage
        persistentVolumeClaim:
          claimName: model-weights-pvc  # the PVC object name

      - name: shared-cache
        persistentVolumeClaim:
          claimName: agent-cache-pvc
```

### One-Time Model Seeder Job

```yaml
# seed-models-job.yaml — run once to populate the PVC
apiVersion: batch/v1
kind: Job
metadata:
  name: seed-llama3-8b
  namespace: ai-platform
spec:
  template:
    spec:
      restartPolicy: OnFailure   # retry if download fails; stop once done
      containers:
      - name: seeder
        image: python:3.11-slim
        command: ["python3", "-c", "
import subprocess, os
subprocess.run(['pip', 'install', '-q', 'huggingface_hub'], check=True)
from huggingface_hub import snapshot_download
snapshot_download(
    repo_id='meta-llama/Meta-Llama-3-8B',
    local_dir='/models/llama-3-8b',
    token=os.environ['HF_TOKEN'],
    ignore_patterns=['*.msgpack', '*.h5'],
)
print('Done!')
"]
        env:
        - name: HF_TOKEN
          valueFrom:
            secretKeyRef:
              name: hf-credentials
              key: token
        volumeMounts:
        - name: model-storage
          mountPath: /models
      volumes:
      - name: model-storage
        persistentVolumeClaim:
          claimName: model-weights-pvc
```

```bash
# Run the seeder once
kubectl apply -f seed-models-job.yaml -n ai-platform

# Watch download progress
kubectl logs -f job/seed-llama3-8b -n ai-platform

# Check completion
kubectl get job seed-llama3-8b -n ai-platform
# COMPLETIONS: 1/1  ← success, weights are on the PV

# From now on, every LLM pod mounts the PVC and starts in ~2 minutes
```

---

---

## Phase 4

# Phase 4 — AI-Specific Orchestration: The Pro Level

At this phase you stop writing raw Kubernetes YAML for every component and start using tools built specifically for AI workloads that sit on top of K8s. These three — KubeRay, KEDA, and KServe — are the industry standard for production GenAI infrastructure in 2025.

---

## 4.1 KubeRay

### Why Ray Instead of Raw K8s?

With raw Kubernetes, distributing a task across 10 GPU pods requires you to write custom message queue logic, inter-pod communication, retry handling, and failure recovery. It is hundreds of lines of infrastructure code.

**Ray** makes distributed computing as simple as a Python decorator:

```python
# Without Ray: hundreds of lines of queue/worker/retry code
# With Ray: this

@ray.remote(num_gpus=1)
def embed_documents(texts):
    model = load_embedding_model()
    return model.encode(texts)

# Runs in parallel across 4 GPU pods in your K8s cluster
futures = [embed_documents.remote(batch) for batch in batches]
results = ray.get(futures)  # waits for all 4 to complete
```

**KubeRay** is the Kubernetes operator that manages Ray clusters. It handles pod lifecycle, autoscaling, and fault tolerance so you never have to write K8s YAML for Ray workers.

### The Ray Cluster Architecture

```
╔══════════════════════════════════════════════════════════════════════════════╗
║                         KUBERAY CLUSTER ON KUBERNETES                        ║
╠══════════════════════════════════════════════════════════════════════════════╣
║                                                                              ║
║  RayCluster (K8s Custom Resource managed by KubeRay Operator)                ║
║                                                                              ║
║  ┌────────────────────────────────────────────────────────────────────────┐  ║
║  │                        HEAD NODE (1 CPU pod)                           │  ║
║  │  ┌──────────────────────────────────────────────────────────────────┐  │  ║
║  │  │ Global Control Store (GCS) — schedules Ray tasks                 │  │  ║
║  │  │ Ray Dashboard — web UI showing cluster state                     │  │  ║
║  │  │ Autoscaler — adds/removes worker pods based on load              │  │  ║
║  │  └──────────────────────────────┬───────────────────────────────────┘  │  ║
║  └─────────────────────────────────┼──────────────────────────────────────┘  ║
║                                    │                                         ║
║                                 manages                                      ║
║                                    │                                         ║
║          ┌─────────────────────────┴─────────────────────────┐               ║
║          ▼                         ▼                         ▼               ║
║  ┌──────────────┐          ┌──────────────┐          ┌──────────────┐        ║
║  │   WORKER-1   │          │   WORKER-2   │          │   WORKER-N   │        ║
║  │  (GPU pod)   │          │  (GPU pod)   │          │  (GPU pod)   │        ║
║  │              │          │              │          │              │        ║
║  │   Runs Ray   │          │   Runs Ray   │          │   Runs Ray   │        ║
║  │  tasks and   │          │  tasks and   │          │  tasks and   │        ║
║  │    actors    │          │    actors    │          │    actors    │        ║
║  └──────────────┘          └──────────────┘          └──────────────┘        ║
║                                                                              ║
╚══════════════════════════════════════════════════════════════════════════════╝

KubeRay Operator responsibilities:
- Creates Head and Worker pods from the RayCluster spec
- Scales Workers up when Ray has pending tasks, down when idle
- Restarts crashed workers and requeues their tasks automatically
```

### Installing KubeRay

```bash
helm repo add kuberay https://ray-project.github.io/kuberay-helm/
helm repo update

helm install kuberay-operator kuberay/kuberay-operator \
    --namespace ray-system \
    --create-namespace \
    --version 1.2.2

# Verify
kubectl get pods -n ray-system
# kuberay-operator-5d7f9d8b9c-xk2p4   1/1   Running
```

### RayCluster YAML

```yaml
# raycluster.yaml
apiVersion: ray.io/v1
kind: RayCluster
metadata:
  name: ai-ray-cluster
  namespace: ai-platform
spec:
  rayVersion: "2.38.0"   # must match your Python ray package version

  # HEAD NODE — coordinator, runs on cheap CPU node
  headGroupSpec:
    rayStartParams:
      dashboard-host: "0.0.0.0"
      num-gpus: "0"               # head does no computation
    template:
      spec:
        nodeSelector:
          node-type: cpu-general
        containers:
        - name: ray-head
          image: rayproject/ray-ml:2.38.0-gpu
          ports:
          - containerPort: 6379    # Ray GCS (cluster coordination)
          - containerPort: 8265    # Ray Dashboard
          - containerPort: 10001   # Ray Client (for remote Python connections)
          resources:
            requests: {cpu: "2", memory: "8Gi"}
            limits:   {cpu: "4", memory: "16Gi"}

  # WORKER NODES — GPU machines that run actual computations
  workerGroupSpecs:
  - groupName: gpu-workers
    replicas: 2              # start with 2 GPU workers
    minReplicas: 1           # keep at least 1 warm
    maxReplicas: 8           # auto-scale up to 8 under load
    rayStartParams:
      num-gpus: "1"          # tells Ray: each worker has 1 GPU
    template:
      spec:
        nodeSelector:
          node-type: gpu-compute
        tolerations:
        - key: gpu-reserved
          operator: Equal
          value: "true"
          effect: NoSchedule
        containers:
        - name: ray-worker
          image: rayproject/ray-ml:2.38.0-gpu
          resources:
            requests: {cpu: "8", memory: "32Gi", "nvidia.com/gpu": "1"}
            limits:   {cpu: "16", memory: "64Gi", "nvidia.com/gpu": "1"}
          volumeMounts:
          - name: model-storage
            mountPath: /models
            readOnly: true
        volumes:
        - name: model-storage
          persistentVolumeClaim:
            claimName: model-weights-pvc
```

```bash
kubectl apply -f raycluster.yaml -n ai-platform

# Access the Ray Dashboard
kubectl port-forward svc/ai-ray-cluster-head-svc 8265:8265 -n ai-platform
# Open: http://localhost:8265
# Shows: cluster resources, running tasks, actor locations, autoscaling events
```

### Parallel Embedding Pipeline with Ray

```python
# distributed_embedding.py
# This runs on the head node or your laptop.
# The GPU work happens on the K8s worker pods.

import ray
from typing import List

# Connect to the Ray cluster running in K8s
ray.init("ray://ai-ray-cluster-head-svc.ai-platform:10001")

resources = ray.cluster_resources()
print(f"Cluster: {resources.get('GPU', 0):.0f} GPUs, {resources.get('CPU', 0):.0f} CPUs")


@ray.remote(num_gpus=1, num_cpus=4)
class EmbeddingActor:
    # Runs on a GPU worker pod in K8s.
    # Ray creates one instance per GPU worker and keeps it warm.
    def __init__(self, model_name: str):
        import socket
        from sentence_transformers import SentenceTransformer
        print(f"Loading {model_name} on {socket.gethostname()}")
        # This runs on the GPU worker — model loads into that pod's GPU VRAM
        self.model = SentenceTransformer(model_name, device="cuda")
        print("Ready!")

    def embed(self, texts: List[str]) -> List[List[float]]:
        return self.model.encode(texts, normalize_embeddings=True).tolist()


def embed_corpus_parallel(documents: List[str], num_workers: int = 4) -> List[List[float]]:
    # Embeds a large corpus across N GPU pods in parallel
    # Create N actors — Ray distributes them across available GPU worker pods
    actors = [EmbeddingActor.remote("BAAI/bge-large-en-v1.5") for _ in range(num_workers)]

    # Split documents across workers
    batches = [documents[i::num_workers] for i in range(num_workers)]

    # Submit all N batches simultaneously — they run in parallel on different GPU pods!
    futures = [actors[i].embed.remote(batches[i]) for i in range(num_workers)]

    # Wait for all to complete
    batch_results = ray.get(futures)

    # Reassemble in original order
    embeddings = [None] * len(documents)
    for w_idx, w_embeddings in enumerate(batch_results):
        doc_indices = list(range(w_idx, len(documents), num_workers))
        for d_idx, emb in zip(doc_indices, w_embeddings):
            embeddings[d_idx] = emb

    return embeddings
```

---

## 4.2 KEDA

### Why CPU-Based Autoscaling Fails for AI Agents

Kubernetes' built-in Horizontal Pod Autoscaler (HPA) scales based on CPU or memory. This works for web servers. It completely misses the signal for AI agent pipelines.

Scenario: a document processing pipeline with agents consuming from a RabbitMQ queue.

```
3 AM  — Queue: 0 messages. Agents: idle.
        CPU usage: 0.5% (just Python interpreters).
        HPA sees "CPU is fine, no scaling needed."
        Result: 3 agents running at $0.30/hr = $0.90/hr wasted all night.

10 AM — Queue: 5,000 messages. Agents: still 3 (HPA has not triggered).
        CPU is still low — agents wait for I/O most of the time.
        HPA still sees "CPU is fine."
        Result: 3 agents processing 5,000 docs. Massive backlog. SLA violated.
```

**KEDA** scales based on external signals: queue depth, Kafka consumer lag, Prometheus metrics from your LLM server, or any custom HTTP endpoint. The killer feature: **scale-to-zero** — when the queue is empty, KEDA sets replicas to 0. Zero pods = zero cost.

```
KEDA SCALE-TO-ZERO LIFECYCLE

Queue depth: 0       → KEDA sets replicas = 0       → $0/hr
Queue depth: 50      → KEDA sets replicas = 5        → 5 agents working
Queue depth: 500     → KEDA sets replicas = 50 (max) → 50 agents working
Queue drains to 0    → KEDA waits cooldownPeriod     → scales back to 0
```

### Installing KEDA

```bash
helm repo add kedacore https://kedacore.github.io/charts
helm repo update

helm install keda kedacore/keda \
    --namespace keda \
    --create-namespace \
    --version 2.16.0

kubectl get pods -n keda
# keda-operator-xxx                     1/1  Running
# keda-operator-metrics-apiserver-xxx   1/1  Running
# keda-admission-webhooks-xxx           1/1  Running
```

### Complete KEDA Setup: RabbitMQ-Driven Document Processor

```yaml
# ─── 1. Worker Deployment ─────────────────────────────────────────────────────
# A standard Deployment. KEDA controls the replica count.
apiVersion: apps/v1
kind: Deployment
metadata:
  name: doc-processor
  namespace: ai-platform
spec:
  replicas: 1                    # KEDA overrides this immediately on startup
  selector:
    matchLabels: {app: doc-processor}
  template:
    metadata:
      labels: {app: doc-processor}
    spec:
      containers:
      - name: processor
        image: your-registry.io/doc-processor:latest
        env:
        - name: RABBITMQ_URL
          valueFrom:
            secretKeyRef: {name: rabbitmq-credentials, key: url}
        - name: OPENAI_API_KEY
          valueFrom:
            secretKeyRef: {name: ai-api-keys, key: openai-key}
        resources:
          requests: {memory: "2Gi", cpu: "1"}
          limits:   {memory: "4Gi", cpu: "2"}
---
# ─── 2. TriggerAuthentication ─────────────────────────────────────────────────
# Tells KEDA how to authenticate when reading RabbitMQ queue metrics.
apiVersion: keda.sh/v1alpha1
kind: TriggerAuthentication
metadata:
  name: rabbitmq-auth
  namespace: ai-platform
spec:
  secretTargetRef:
  - parameter: host
    name: rabbitmq-keda-secret   # a Secret containing the RabbitMQ connection URL
    key: host
---
# ─── 3. ScaledObject ──────────────────────────────────────────────────────────
# The core KEDA configuration. Defines what to scale, when, and by how much.
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: doc-processor-scaler
  namespace: ai-platform
spec:
  scaleTargetRef:
    name: doc-processor        # which Deployment to scale

  minReplicaCount: 0           # scale to ZERO when queue is empty — key feature
  maxReplicaCount: 50          # never exceed 50 replicas

  pollingInterval: 15          # check queue depth every 15 seconds
  cooldownPeriod: 300          # after queue empties, wait 5 min before scaling to 0
                               # prevents rapid scale-up/scale-down on burst traffic

  triggers:
  - type: rabbitmq
    metadata:
      queueName: "document-processing-queue"
      mode: QueueLength          # scale based on number of waiting messages
      value: "10"                # target: 1 replica per 10 queued messages
                                 # 0 msgs → 0 replicas
                                 # 50 msgs → 5 replicas
                                 # 500 msgs → 50 replicas (maxReplicaCount)
      protocol: amqp
    authenticationRef:
      name: rabbitmq-auth
```

### Your Python Worker Code

```python
# doc_processor.py — runs in each pod, consumes messages independently
import os, json, pika
from openai import OpenAI

RABBITMQ_URL = os.environ["RABBITMQ_URL"]
client = OpenAI(api_key=os.environ["OPENAI_API_KEY"])

def process(document: dict) -> None:
    response = client.chat.completions.create(
        model="gpt-4o-mini",
        messages=[
            {"role": "system", "content": "Extract key entities as JSON."},
            {"role": "user", "content": document["text"]}
        ],
        response_format={"type": "json_object"},
    )
    save_result(document["id"], json.loads(response.choices[0].message.content))

connection = pika.BlockingConnection(pika.URLParameters(RABBITMQ_URL))
channel = connection.channel()
channel.queue_declare(queue="document-processing-queue", durable=True)

def callback(ch, method, properties, body):
    process(json.loads(body))
    ch.basic_ack(delivery_tag=method.delivery_tag)

channel.basic_qos(prefetch_count=1)   # one message at a time per worker
channel.basic_consume(queue="document-processing-queue", on_message_callback=callback)
channel.start_consuming()
```

### KEDA with Prometheus for LLM-Specific Scaling

This is the 2025 production standard — scale your LLM inference replicas based on LLM-specific signals (pending request queue, KV cache saturation) rather than generic CPU:

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: vllm-scaler
  namespace: ai-platform
spec:
  scaleTargetRef:
    name: llm-server
  minReplicaCount: 1       # keep 1 warm — LLMs are slow to cold-start
  maxReplicaCount: 10
  pollingInterval: 30
  cooldownPeriod: 600      # 10 min cooldown — new LLM pods take ~2 min to load

  triggers:
  # Scale when too many requests are queued
  - type: prometheus
    metadata:
      serverAddress: http://prometheus-service.monitoring:9090
      metricName: vllm_pending_requests
      threshold: "5"      # scale up when avg pending requests per replica exceeds 5
      query: >
        sum(vllm:num_requests_waiting{namespace="ai-platform"}) /
        count(vllm:num_requests_waiting{namespace="ai-platform"})

  # Also scale when GPU KV cache is nearly full (long context pressure)
  - type: prometheus
    metadata:
      serverAddress: http://prometheus-service.monitoring:9090
      metricName: vllm_kv_cache_usage
      threshold: "0.85"   # scale up when cache is 85% full
      query: avg(vllm:gpu_cache_usage_perc{namespace="ai-platform"})
```

---

## 4.3 KServe and BentoML

### Why Specialized Inference Servers?

When you write a raw Kubernetes Deployment for your model, you are reinventing solved problems every time:

- Health check endpoints for slow-loading models
- Request batching to maximize GPU throughput
- Canary deployments for model version transitions
- Standardized inference protocols
- GPU memory optimization

KServe and BentoML are purpose-built abstractions that handle all of this.

### KServe — The Enterprise Standard

KServe is a CNCF incubating project. You create one `InferenceService` resource and KServe automatically creates the Deployment, Service, autoscaling rules, routing, and monitoring — all pre-configured correctly for AI inference.

```
YOU CREATE ONE OBJECT:           KSERVE CREATES AUTOMATICALLY:

InferenceService                 Deployment (predictor pods)
  name: llama-3-8b         →    Service (cluster endpoint)
  model: pvc://weights/llama     Ingress (external routing)
  runtime: vllm                  HPA or KEDA (autoscaling)
  gpu: 1                         ServiceMonitor (Prometheus)
```

#### Installing KServe

```bash
# Install cert-manager (required for KServe webhook certificates)
kubectl apply -f \
  https://github.com/cert-manager/cert-manager/releases/download/v1.19.0/cert-manager.yaml

kubectl wait --for=condition=Available deployment --all -n cert-manager --timeout=120s

# Install KServe in Standard (RawDeployment) mode — no Knative required
helm repo add kserve https://kserve.github.io/helm-charts/
helm repo update

helm install kserve kserve/kserve \
    --namespace kserve \
    --create-namespace \
    --set kserve.controller.deploymentMode=RawDeployment
```

#### KServe InferenceService YAML

```yaml
# llama3-inference-service.yaml
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: llama-3-8b
  namespace: ai-platform
  annotations:
    # Use KEDA for autoscaling instead of KServe's default HPA
    serving.kserve.io/autoscalerClass: external

spec:
  predictor:
    model:
      modelFormat:
        name: huggingface        # model format → selects the right inference runtime
      runtime: kserve-huggingface-server   # uses vLLM under the hood
      storageUri: "pvc://model-weights-pvc/llama-3-8b"   # from our PVC
      args:
      - --model_name=llama-3-8b
      - --tensor_parallel_size=1
      - --max_model_len=8192
      - --enable_chunked_prefill=true

      resources:
        requests:
          cpu: "4"
          memory: "16Gi"
          nvidia.com/gpu: "1"
        limits:
          cpu: "8"
          memory: "20Gi"
          nvidia.com/gpu: "1"

      nodeSelector:
        node-type: gpu-compute

      tolerations:
      - key: gpu-reserved
        operator: Equal
        value: "true"
        effect: NoSchedule
```

```bash
kubectl apply -f llama3-inference-service.yaml -n ai-platform

# Watch it become ready
kubectl get inferenceservice llama-3-8b -n ai-platform -w
# NAME          URL                                                      READY
# llama-3-8b    http://llama-3-8b.ai-platform.svc.cluster.local/v1      True
```

#### Calling the KServe Endpoint (OpenAI-Compatible)

KServe exposes an OpenAI-compatible API. Your existing OpenAI client code works unchanged:

```python
from openai import AsyncOpenAI

# From inside the cluster (any agent pod)
client = AsyncOpenAI(
    api_key="not-required",
    base_url="http://llama-3-8b.ai-platform.svc.cluster.local/v1"
)

async def generate(prompt: str) -> str:
    response = await client.chat.completions.create(
        model="llama-3-8b",
        messages=[{"role": "user", "content": prompt}],
        temperature=0.7,
        max_tokens=2048,
    )
    return response.choices[0].message.content

# Switch between OpenAI and your local KServe model with one env var change.
# Drop-in replacement. Same code. Same client.
```

### BentoML — The Developer-Friendly Alternative

BentoML takes a Python-first approach. You define your serving logic as a Python class, and BentoML automatically builds the Docker image and K8s manifests. Best for fast iteration and developer-owned deployments.

```python
# service.py
import bentoml, httpx, os
from openai import AsyncOpenAI

@bentoml.service(
    resources={"cpu": "2", "memory": "4Gi"},
    traffic={"timeout": 120, "max_concurrency": 20},
    scaling={"min_replicas": 1, "max_replicas": 10},
)
class RAGOrchestrator:
    # Full RAG pipeline exposed as a scalable API.

    def __init__(self):
        self.llm = AsyncOpenAI(api_key=os.environ["OPENAI_API_KEY"])
        self.retriever_url = os.getenv("RETRIEVER_URL", "http://retriever-service:8001")

    @bentoml.api
    async def chat(self, query: str) -> str:
        # 1. Retrieve relevant context
        async with httpx.AsyncClient() as http:
            docs = (await http.post(
                f"{self.retriever_url}/search",
                json={"query": query, "top_k": 5}
            )).json()["documents"]

        context = "\n".join([d["text"] for d in docs])

        # 2. Generate with context
        response = await self.llm.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {"role": "system", "content": f"Answer using this context:\n{context}"},
                {"role": "user", "content": query}
            ],
        )
        return response.choices[0].message.content
```

```bash
# Build and deploy to K8s with two commands
bentoml build
bentoml deploy . --name rag-orchestrator --namespace ai-platform

# BentoML handles: Docker image build, Deployment YAML, Service YAML,
# resource configuration, health checks, HPA rules — automatically.
```

---

---

## Reference Architecture

# Reference Architecture: Full GenAI Platform on K8s

This is the complete production architecture combining all four phases.

```
PRODUCTION MULTI-AGENT RAG PLATFORM

═══════════════════════════════════════════════════════════════════════
EXTERNAL TRAFFIC
═══════════════════════════════════════════════════════════════════════

  Internet (HTTPS) → LoadBalancer Service → Nginx Ingress
      │
      ▼
═══════════════════════════════════════════════════════════════════════
APPLICATION LAYER   (CPU nodes, $0.20/hr, no taints)
═══════════════════════════════════════════════════════════════════════

  API Gateway Pod (2 replicas)
  └── auth, rate limiting, request routing
      │
      ├── POST /chat ──────────────────────────────────────────────────┐
      │                                                                │
      ▼                                                                ▼
  Orchestrator Pods (3 replicas, KEDA)            Doc Processor Pods
  └── LangGraph multi-agent pipeline              └── KEDA: 0→50 replicas
      │                                               trigger: RabbitMQ
      ├── calls retriever-service:8001                scale-to-zero ✓
      ├── calls reranker-service:8002
      └── calls llm-service:8080
      │
      ├── Retriever Pods (5x, ClusterIP)
      ├── Re-ranker Pods (2x, ClusterIP)
      └── Embedder Pods (2x, ClusterIP)

═══════════════════════════════════════════════════════════════════════
AI INFERENCE LAYER  (GPU nodes, $10/hr, TAINTED — GPU workloads only)
═══════════════════════════════════════════════════════════════════════

  KServe InferenceService: llama-3-70b
  └── vLLM runtime, tensor_parallel_size=2
  └── nvidia.com/gpu: 2, memory: 32Gi
  └── KEDA: 1-5 replicas via vllm:num_requests_waiting metric
  └── endpoint: http://llama-3-70b.ai-platform.svc.cluster.local/v1

  KubeRay Cluster: ai-ray-cluster
  └── Head: 1 CPU pod (coordinator + dashboard)
  └── Workers: 2-8 GPU pods (auto-scaled by Ray)
  └── @ray.remote(num_gpus=1) EmbeddingActor across all workers

═══════════════════════════════════════════════════════════════════════
STORAGE LAYER   (PersistentVolumes, survive pod restarts forever)
═══════════════════════════════════════════════════════════════════════

  model-weights-pvc   500Gi  EFS  ReadOnlyMany
    → Llama-3-70B, BGE-large weights
    → Mounted by all LLM + embedding pods (read-only)

  qdrant-data-pvc     100Gi  EBS  ReadWriteOnce
    → Qdrant vector index

  agent-cache-pvc      50Gi  EFS  ReadWriteMany
    → Shared agent memory, session state

═══════════════════════════════════════════════════════════════════════
CONFIGURATION LAYER
═══════════════════════════════════════════════════════════════════════

  ConfigMaps:   ai-platform-config (model names, service URLs, batch sizes)
                agent-config (tools, max iterations, system prompts)

  Secrets:      ai-api-keys (openai, anthropic, cohere)
                hf-credentials (HuggingFace token)
                db-credentials (Qdrant, Redis)
                rabbitmq-credentials (message queue)
```

### Complete K8s Object Inventory

| Component             | Objects                                                 | Phases Used |
| --------------------- | ------------------------------------------------------- | ----------- |
| API Gateway           | Deployment (2r), Service (LoadBalancer)                 | 2           |
| Orchestrator          | Deployment (3r), Service (ClusterIP), KEDA ScaledObject | 2, 4        |
| Document Processor    | Deployment, KEDA (RabbitMQ, scale-to-zero)              | 2, 4        |
| Retriever / Re-ranker | Deployment (5r/2r), Service (ClusterIP)                 | 2           |
| LLM Server            | KServe InferenceService, GPU limits, taints, KEDA       | 1, 3, 4     |
| Embedding Service     | RayCluster (KubeRay)                                    | 4           |
| Model Weights         | PVC (500 Gi, EFS, ROX), one-time seeder Job             | 1, 3        |
| Vector DB             | StatefulSet, Service (ClusterIP), PVC (RWO)             | 2, 3        |
| API Keys              | Secrets (ai-api-keys, hf-credentials, etc.)             | 2           |
| Runtime Config        | ConfigMaps (ai-platform-config, agent-config)           | 2           |
| GPU Node Isolation    | Taints + Tolerations + nodeSelector                     | 3           |

---

---

## kubectl Cheat Sheet

### Viewing What Is Running

```bash
# List all pods — first thing to run when something breaks
kubectl get pods -n ai-platform

# Which node is each pod running on?
kubectl get pods -n ai-platform -o wide

# Filter by label — only LLM server pods
kubectl get pods -n ai-platform -l app=llm-server

# Watch pods update in real time (use during rollouts)
kubectl get pods -n ai-platform -w

# All Deployments and replica status
kubectl get deployments -n ai-platform

# All Services and their types
kubectl get services -n ai-platform
```

### Debugging

```bash
# Why is my pod Pending / CrashLoopBackOff / OOMKilled?
# The "Events" section at the bottom of the output has the answer.
kubectl describe pod <pod-name> -n ai-platform

# Common Events and what they mean:
# "0/5 nodes available: Insufficient nvidia.com/gpu"
#   → No GPU nodes have free GPUs. Scale up GPU node pool.
# "0/5 nodes available: Insufficient memory"
#   → All nodes are full. Scale up node pool or reduce requests.
# "Back-off restarting failed container"
#   → CrashLoopBackOff. Read the logs from the previous run.
# "Failed to pull image"
#   → Wrong image name/tag, or missing imagePullSecret for private registry.

# Stream live logs from a running pod
kubectl logs -f <pod-name> -n ai-platform

# Read logs from the PREVIOUS pod run (when pod is in CrashLoopBackOff)
# The current pod has no useful logs — it just started fresh.
kubectl logs --previous <pod-name> -n ai-platform

# Read logs from ALL pods with a label
kubectl logs -l app=rag-orchestrator -n ai-platform --all-containers

# Open a shell inside a running pod — like SSH into your container
kubectl exec -it <pod-name> -n ai-platform -- bash
# Then: env | grep OPENAI   # check env vars
#       ls /models           # check model weights are mounted
#       curl localhost:8000/health  # test health endpoint locally

# Test an internal service from your laptop (no public exposure needed)
kubectl port-forward svc/llm-service 8080:8000 -n ai-platform
# Now from your laptop: curl localhost:8080/v1/chat/completions

# Check GPU allocation across all nodes
kubectl describe nodes | grep -A 5 "Allocated resources"

# Live resource usage (requires metrics-server)
kubectl top pods -n ai-platform
kubectl top nodes
```

### Deploying and Managing

```bash
# Deploy from a YAML file (create if not exists, update if exists)
kubectl apply -f deployment.yaml
kubectl apply -f ./k8s/              # apply entire directory

# Push a new image version — triggers rolling update
kubectl set image deployment/rag-orchestrator \
    rag-orchestrator=your-registry.io/rag-orchestrator:v2.2 \
    -n ai-platform

# Watch the rolling update progress (one pod at a time)
kubectl rollout status deployment/rag-orchestrator -n ai-platform

# New version has a bug? Roll back immediately (takes seconds)
kubectl rollout undo deployment/rag-orchestrator -n ai-platform

# View rollout history
kubectl rollout history deployment/rag-orchestrator -n ai-platform

# Manually scale (useful for quick load testing)
kubectl scale deployment/rag-orchestrator --replicas=10 -n ai-platform

# Delete a deployment (pods deleted, PVCs NOT deleted by default)
kubectl delete deployment llm-server -n ai-platform
```

### Secrets and ConfigMaps

```bash
# Create a Secret from literal values
kubectl create secret generic ai-api-keys \
    --from-literal=openai-key="sk-proj-..." \
    --from-literal=anthropic-key="sk-ant-..." \
    -n ai-platform

# Update a Secret without deleting it
kubectl create secret generic ai-api-keys \
    --from-literal=openai-key="sk-proj-new..." \
    -n ai-platform --dry-run=client -o yaml | kubectl apply -f -

# Decode and view a Secret value
kubectl get secret ai-api-keys -n ai-platform \
    -o jsonpath="{.data.openai-key}" | base64 --decode

# Create a ConfigMap
kubectl create configmap ai-platform-config \
    --from-literal=LLM_MODEL_NAME=llama-3-8b \
    --from-file=agent_config.json \
    -n ai-platform

# View a ConfigMap
kubectl get configmap ai-platform-config -n ai-platform -o yaml
```

### Phase 4 Tools

```bash
# KEDA — check scaling status
kubectl get scaledobjects -n ai-platform
kubectl describe scaledobject doc-processor-scaler -n ai-platform
# Shows: current queue depth, current replicas, last scale event, errors

# KubeRay — check cluster status
kubectl get raycluster -n ai-platform
kubectl describe raycluster ai-ray-cluster -n ai-platform

# Ray Dashboard — access from your laptop
kubectl port-forward svc/ai-ray-cluster-head-svc 8265:8265 -n ai-platform
# Open http://localhost:8265

# KServe — check InferenceService status
kubectl get inferenceservice -n ai-platform
kubectl describe inferenceservice llama-3-8b -n ai-platform
```

### Pod Status Reference

| Status              | Meaning                              | What to Do                                                          |
| ------------------- | ------------------------------------ | ------------------------------------------------------------------- |
| `Pending`           | Waiting to be scheduled onto a node  | `describe pod` → check Events for resource or node issues           |
| `ContainerCreating` | Pulling image and starting container | Normal — wait. If stuck >5 min, describe the pod.                   |
| `Running` (0/1)     | Running but readiness probe failing  | `logs` → model still loading? Check readiness probe path            |
| `Running` (1/1)     | Fully running and ready for traffic  | All good                                                            |
| `CrashLoopBackOff`  | Container crashes repeatedly         | `logs --previous` → read the crash reason                           |
| `OOMKilled`         | Exceeded memory limit and was killed | Increase `limits.memory` and `requests.memory`                      |
| `ImagePullBackOff`  | Cannot pull the Docker image         | Check image name, tag, and registry credentials                     |
| `Evicted`           | Node ran out of resources            | Node was under memory pressure — increase node size or fix requests |

---

> **Your learning path from here:**
> 
> 1. Install `minikube` or `kind` locally — a free single-node K8s cluster for practice
> 2. Deploy a simple FastAPI app as your first Deployment + ClusterIP Service
> 3. Add a ConfigMap for config and a Secret for your API key
> 4. Add GPU resources and deploy a small model (e.g., a tiny embedding model)
> 5. Add KEDA tied to a Redis list — watch pods scale up and down
> 6. Try KServe on a cloud cluster (GKE Autopilot is easiest)
> 
> Kubernetes becomes intuitive through practice. Break things, read the Events, fix them. The loop is fast once you know the objects.
