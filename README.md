# Enterprise Kubernetes & MLOps Architecture Lab

Welcome to the **Enterprise Kubernetes & MLOps Architecture Lab**. 

This repository is not a simple dump of Kubernetes YAML files. It is a **narrated, step-by-step platform engineering course** built directly into the codebase. Every manifest, script, and guide is thoroughly annotated to teach you not just *how* to deploy a resource, but *why* an enterprise platform team (like those at FAANG or major banks) configures it that way.

If you are a learner looking to build production-grade platform knowledge for senior interviews or real-world roles, start here.

---

## 🖥️ The Local Machine Context

Enterprise engineers develop locally but deploy globally. This repository is specifically tailored and validated for the following local machine profile:

| Component | Specification | Why It Matters |
|---|---|---|
| **OS** | Windows 11 | We use WSL2 as our mandatory Linux bridge. No PowerShell. |
| **Shell** | WSL2 (Ubuntu 22.04) | Production Kubernetes is 100% Linux. We train on Linux. |
| **Container Engine** | Docker Desktop | Provides the underlying daemon with WSL2 integration. |
| **RAM** | 16 GB | We allocate 8 GB to Docker Desktop to comfortably run a 3-node cluster. |
| **GPU** | NVIDIA RTX 2060 (6GB) | Required for the MLOps track (hardware-accelerated inference). |
| **Cluster** | `kind` | Simulates a real multi-node cluster (1 control plane, 2 workers) locally. |

---

## 🗺️ The Learning Journey

Your journey is split into two distinct tracks. **You must complete Track 1 before starting Track 2.**

```text
┌───────────────────────────────────────────────────────────────────────────┐
│                        THE ENTERPRISE ARCHITECTURE LAB                    │
│                                                                           │
│  TRACK 1: PLATFORM FUNDAMENTALS ────────────────────────────────────────┐ │
│  (Building the infrastructure layer)                                    │ │
│                                                                         │ │
│  [00] Prerequisites ──► [01] Cluster Setup ──► [02] Namespaces          │ │
│  (Docker/WSL2/kind)     (Multi-node kind)      (Tenant Isolation)       │ │
│                                                         │               │ │
│  ┌──────────────────────────────────────────────────────┘               │ │
│  ▼                                                                      │ │
│  [03] Pods ───────────► [04] Deployments ────► [05] Services            │ │
│  (Atomic unit)          (Rollouts/Rollbacks)   (Stable routing)         │ │
│                                                         │               │ │
│  ┌──────────────────────────────────────────────────────┘               │ │
│  ▼                                                                      │ │
│  [06] Config & Sec ───► [07] RBAC ───────────► [08] Resource Quotas     │ │
│  (12-Factor Apps)       (Zero-trust APIs)      (Multi-tenant safety)    │ │
│                                                         │               │ │
│  ┌──────────────────────────────────────────────────────┘               │ │
│  ▼                                                                      │ │
│  [09] Health Checks ──► [10] Enterprise Patterns                        │ │
│  (Liveness/Readiness)   (HPA, PDB, NetworkPolicies)                     │ │
│                                                                         │ │
│                                                                         │ │
│  TRACK 2: MLOPS & MODEL SERVING ────────────────────────────────────────┤ │
│  (Deploying intelligence on the platform)                               │ │
│                                                                         │ │
│  [00] KServe Local ───► [01] Standard Mode ──► [02] Model Registry      │ │
│  (Platform Add-ons)     (InferenceServices)    (Artifact Lifecycle)     │ │
│                                                         │               │ │
│  ┌──────────────────────────────────────────────────────┘               │ │
│  ▼                                                                      │ │
│  [03] E2E Pipeline ───► [04] Operations ─────► [05] Custom Serving      │ │
│  (Wine Quality ML)      (Canary, Scaling)      (FastAPI contrast)       │ │
└───────────────────────────────────────────────────────────────────────────┘
```

---

## 🚀 How to Start (From Zero)

If you are brand new to this repository, open your terminal (Windows Terminal) and follow these exact steps:

1. **Read the Windows Preparation Guide:**
   Go to [`setup/00-prerequisites/platform-guides/windows-wsl2/README.md`](setup/00-prerequisites/platform-guides/windows-wsl2/README.md).
   This will teach you how to set up WSL2 and Docker Desktop correctly for your 16GB machine.

2. **Run the One-Shot Installer:**
   Once inside your WSL2 Ubuntu terminal, run:
   ```bash
   cd "/mnt/d/Generative AI Portfolio Projects/kubernetes_architure"
   bash setup/00-prerequisites/platform-guides/windows-wsl2/step-by-step-install.sh
   ```
   *This installs `kind`, `kubectl`, `helm`, and other enterprise CLI tools.*

3. **Create the Cluster:**
   ```bash
   bash setup/01-cluster-setup/create-cluster.sh
   ```

4. **Verify Cluster Health:**
   ```bash
   bash setup/01-cluster-setup/verify-cluster.sh
   ```

5. **Begin the Learning Modules:**
   Navigate into [`setup/02-namespaces/README.md`](setup/02-namespaces/README.md) and read it. Then apply the resources using the provided bash script in that folder. Continue sequentially through folder `10`.

---

## 🧠 The Teaching Philosophy

As you navigate the code, you will notice three strict rules applied everywhere:

1. **The "Why" Before the "How"**: No manifest exists without an explanation of the business or platform reason behind it.
2. **ASCII Architecture**: Complex flows (like rolling updates or RBAC) have visual diagrams in the scripts and READMEs.
3. **The Local → Enterprise Translation**: Every module explicitly maps what you are doing locally (e.g., a `kind` NodePort) to what you would do in production (e.g., an AWS Application Load Balancer).

You are learning to think like an architect, not just an operator.

---
*Maintained via AI Agentic Coding with strict adherence to `AGENTS.md`.*
