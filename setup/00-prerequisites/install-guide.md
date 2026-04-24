# =============================================================================
# FILE: 00-prerequisites/install-guide.md
# PURPOSE: Step-by-step, platform-aware tool installation guide.
#          Written for engineers who want to understand WHY each tool exists,
#          not just blindly copy-paste install commands.
# =============================================================================

# Enterprise Kubernetes: Tool Installation Guide

> **Philosophy**: In enterprise environments, you never install tools randomly.
> Every tool serves a specific purpose in the workflow. Understand the role
> before running the install command.

---

## Table of Contents

1. [WSL2 Setup (Windows — REQUIRED first)](#1-wsl2-windows)
2. [Docker Desktop Configuration](#2-docker-desktop)
3. [kind — Your Local Cluster Engine](#3-kind)
4. [kubectl — The Universal K8s CLI](#4-kubectl)
5. [Optional Enterprise Tools](#5-optional-tools)
6. [Verify Everything](#6-verify)

Before following the shared commands below, open the matching platform guide in
`platform-guides/` so you have platform-specific context for your machine.

If you are doing this for the first time:
- Windows: start with `platform-guides/windows-wsl2/README.md`
- Linux: start with `platform-guides/linux/README.md`
- macOS: start with `platform-guides/macos/README.md`

Those guides explain not just the commands, but:
- why the command exists
- what success looks like
- what to do next

## Required Vs Optional In This Repository

Required to start the local Kubernetes track:
- `docker`
- `kind`
- `kubectl`

Optional but recommended:
- `helm`
- `kubectx`
- `k9s`

Important learning note:
- `kind` is the blocker for local cluster creation.
- `helm` becomes important as soon as you move into KServe and enterprise-style add-ons.
- `kubectx` and `k9s` improve operator workflow, but they are not blockers.

---

## 1. WSL2 (Windows)

### Why WSL2, not PowerShell?

In the enterprise world, Kubernetes runs on **Linux**. The control plane, worker
nodes, the container runtime (containerd), and every infrastructure tool is
Linux-native. When you SSH into an AWS EC2 node, an EKS node, or a GKE node —
it is Linux.

PowerShell is a Windows-only tool. It will not exist on any server you will
ever touch in a Kubernetes environment. WSL2 gives you a **real Linux kernel**
running natively on Windows, which means:
- The same bash scripts run locally and in CI/CD (GitHub Actions, GitLab CI)
- File paths, permissions (`chmod`), and tool behavior match production
- Docker Desktop integrates natively with WSL2

### Installation

```bash
# Run this from Windows Terminal (not WSL2 yet) with admin rights
# This installs WSL2 with Ubuntu (the most common enterprise Linux distro)
wsl --install -d Ubuntu-22.04

# After reboot, open WSL2 and set username/password
# Then update package lists (habit every engineer should have on day 1)
sudo apt-get update && sudo apt-get upgrade -y
```

### Enable WSL2 Integration with Docker Desktop

1. Open Docker Desktop → Settings → Resources → WSL Integration
2. Enable integration for your Ubuntu-22.04 distro
3. Click "Apply & Restart"

Now Docker commands typed inside WSL2 talk directly to Docker Desktop's engine.
This is the bridge that makes `kind` work on Windows.

### Exact “Do Not Get Lost” Startup Sequence For Windows

When you come back to this project later, use this order:

```bash
# 1. Start Docker Desktop on Windows first.
# 2. Open Ubuntu from the Start menu.

# 3. Verify you are in Linux, not PowerShell.
uname -a

# 4. Move to the repository from WSL2.
cd "/mnt/d/Generative AI Portfolio Projects/kubernetes_architure"

# 5. Run the prerequisite checker.
bash setup/00-prerequisites/check-prerequisites.sh

# 6. If kind is missing, install it before doing anything else.
# 7. Re-run the prerequisite checker.

# 8. Create the cluster.
bash setup/01-cluster-setup/create-cluster.sh

# 9. Verify cluster health.
bash setup/01-cluster-setup/verify-cluster.sh
```

---

## 2. Docker Desktop

### Role in this setup

Docker Desktop provides:
- The **Docker Engine** (daemon) that `kind` uses to create cluster nodes
- The **container runtime** that all your application containers run in
- **WSL2 integration** so Linux commands control the Windows Docker engine

### Configuration for Kubernetes workloads

Docker Desktop → Settings → Resources:

```
Memory:  8 GB   (kind cluster + your apps need headroom)
CPUs:    4      (more CPUs = faster pod scheduling simulation)
Swap:    2 GB   (safety net for memory spikes)
```

> **Why these numbers?**
> A 3-node kind cluster (1 control-plane + 2 workers) uses roughly 2-3 GB RAM
> at idle. Your apps on top of that need more. 8 GB gives comfortable headroom
> on a 16 GB machine, leaving 8 GB for your OS and other tools.

### Disable Docker Desktop's built-in Kubernetes

Docker Desktop → Settings → Kubernetes → **Uncheck** "Enable Kubernetes"

> **Why disable it?**
> We use `kind` instead. Having both enabled wastes resources and causes
> kubeconfig context confusion. You'll see a `docker-desktop` context appear
> in `kubectl config get-contexts` that you didn't create — confusing.

---

## 3. kind

### What kind is and why enterprises use it

`kind` runs each Kubernetes node as a Docker container. When you run
`kind create cluster`, it creates Docker containers that behave exactly like
real VMs running a full Kubernetes node. Inside each container:
- `kubelet` runs (the node agent that receives Pod assignments)
- `containerd` runs (the container runtime that actually starts your app containers)
- `kube-proxy` runs (handles network routing to services)

**Enterprise use cases for kind:**
- GitHub Actions / GitLab CI integration tests
- Pre-commit validation of K8s manifests against a real cluster
- Local reproduction of production issues without touching prod

### Installation

**macOS:**
```bash
# Homebrew is the standard package manager for macOS developer tools
brew install kind
```

**Linux / WSL2:**
```bash
# Detect architecture (amd64 for Intel/AMD, arm64 for Apple Silicon or ARM servers)
[ $(uname -m) = x86_64 ] && ARCH=amd64 || ARCH=arm64

# Download the kind binary to a temporary location first
curl -Lo /tmp/kind "https://kind.sigs.k8s.io/dl/v0.23.0/kind-linux-${ARCH}"

# Make it executable and move it to the system path using sudo
chmod +x /tmp/kind
sudo mv /tmp/kind /usr/local/bin/kind

# Verify
kind version
```

Important first-time learner note:
- `/usr/local/bin` is a protected system directory on Linux.
- A normal user usually cannot write there directly.
- If you try `curl -Lo /usr/local/bin/kind ...` without `sudo`, Linux will fail with `Permission denied`.
- That is why the safe flow is:
  1. download into `/tmp`
  2. make the file executable
  3. move it into `/usr/local/bin` with `sudo`

If you do not want to use `sudo`, use the user-local installation path from:
- `setup/00-prerequisites/platform-guides/windows-wsl2/README.md`

Why install `kind` first?
- This repository uses `kind` to create the actual Kubernetes cluster.
- Without it, everything after the prerequisites stage is blocked.
- It gives you a multi-node learning environment instead of a black-box single-node cluster.

> **Security note**: In enterprise environments, you'd verify the SHA-256
> checksum of downloaded binaries. See the official kind releases page for
> checksums. This is standard supply-chain security practice.

---

## 4. kubectl

### The most important tool in Kubernetes

`kubectl` is how every engineer interacts with every Kubernetes cluster in
existence. The same binary talks to:
- Your local `kind` cluster
- AWS EKS
- Google GKE
- Azure AKS
- On-premises clusters (OpenShift, Rancher, Vanilla K8s)

There is no "AWS version" of kubectl. It is universal.

### Installation

**macOS:**
```bash
brew install kubectl

# Or install a specific version (always version-pin in enterprise)
brew install kubectl@1.30
```

**Linux / WSL2:**
```bash
# Get the latest stable version string
K8S_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)

# Download the binary
curl -LO "https://dl.k8s.io/release/${K8S_VERSION}/bin/linux/amd64/kubectl"

# Verify the download (checksum validation — enterprise security practice)
curl -LO "https://dl.k8s.io/release/${K8S_VERSION}/bin/linux/amd64/kubectl.sha256"
echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
# Expected output: "kubectl: OK"

# Install to /usr/local/bin (standard for system-wide tools)
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Verify
kubectl version --client
```

### Configure kubectl autocomplete (saves hundreds of keystrokes per day)

```bash
# Add to your ~/.bashrc
echo 'source <(kubectl completion bash)' >> ~/.bashrc
echo 'alias k=kubectl' >> ~/.bashrc          # Industry standard shorthand
echo 'complete -o default -F __start_kubectl k' >> ~/.bashrc

# Reload
source ~/.bashrc

# Now you can type: k get pods   instead of  kubectl get pods
```

---

## 5. Optional Enterprise Tools

### kubectx + kubens

```bash
# macOS
brew install kubectx

# Linux/WSL2
sudo git clone https://github.com/ahmetb/kubectx /usr/local/kubectx
sudo ln -s /usr/local/kubectx/kubectx /usr/local/bin/kubectx
sudo ln -s /usr/local/kubectx/kubens /usr/local/bin/kubens
```

**Usage:**
```bash
kubectx                    # List all cluster contexts
kubectx my-cluster         # Switch to a different cluster
kubens                     # List namespaces
kubens production          # Switch default namespace to "production"
```

Why this matters:
- The easiest way to make dangerous mistakes in Kubernetes is to forget which cluster or namespace you are targeting.
- `kubectx` and `kubens` reduce that risk.

### k9s (Terminal Kubernetes Dashboard)

```bash
# macOS
brew install k9s

# Linux/WSL2
curl -sS https://webinstall.dev/k9s | bash
```

**Usage:** Just type `k9s` — you get a live, interactive view of your cluster.
Navigation is vim-like (j/k for up/down, Enter to drill in, Esc to go back).

Why this matters:
- It helps you inspect pods, logs, events, restarts, and resource health much faster than repeating long `kubectl` commands.

### helm

```bash
# macOS
brew install helm

# Linux/WSL2
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

Why this matters:
- Many enterprise Kubernetes platforms are installed through Helm charts.
- In this repository, Helm becomes especially useful when you move into the KServe section.

---

## 6. Verify

After installation, run:

```bash
bash 00-prerequisites/check-prerequisites.sh
```

On Windows with WSL2, run it from the repository root like this:

```bash
cd "/mnt/d/Generative AI Portfolio Projects/kubernetes_architure"
bash setup/00-prerequisites/check-prerequisites.sh
```

Expected output:
```
╔═══════════════════════════════════════════════════════╗
║     Kubernetes Enterprise Environment Pre-Check       ║
╚═══════════════════════════════════════════════════════╝

  Environment Detection
  ✓ Running inside WSL2 (recommended)

  Core: Docker
  ✓ Docker CLI     OK  (Docker version 25.x.x)
  ✓ Docker daemon  RUNNING  (Docker Engine 25.x.x)

  Cluster Tool: kind
  ✓ kind           OK  (kind v0.23.0)

  Primary CLI: kubectl
  ✓ kubectl        OK  (Client Version: v1.30.x)

  Summary
  ✓ ALL CHECKS PASSED — Environment is ready!
  → Next step: bash 01-cluster-setup/create-cluster.sh
```
