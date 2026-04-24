# =============================================================================
# FILE:    platform-guides/windows-wsl2/README.md
# PURPOSE: The definitive "I have never touched Kubernetes" guide for Windows
#          users with Docker Desktop. Covers everything from WSL2 verification
#          to a running, verified local Kubernetes cluster.
# MACHINE: Windows 11, 16 GB RAM, RTX 2060 6 GB, Docker Desktop installed.
# =============================================================================

# Windows + WSL2: Your Enterprise Kubernetes Development Environment

> **Who this guide is for**: You are on Windows. Docker Desktop is installed.
> You have never run a Kubernetes cluster. By the end of this guide, you will
> have a real, multi-node Kubernetes cluster running on your laptop, controlled
> by the same tools that engineers use on AWS, GCP, and Azure every day.

---

## Why WSL2 and Not PowerShell?

Before a single command, you need to understand this:

```
Enterprise Kubernetes runs on Linux. Every single Kubernetes node —
whether it is an AWS EC2 instance, a Google Compute Engine VM, or a
bare-metal server in a data center — runs Linux. The tools (kubectl,
helm, kind, kubectx, k9s) are Linux-native. The scripts engineers
write and run in CI/CD pipelines (GitHub Actions, GitLab CI) run on
Linux runners.

PowerShell does not exist on any server you will ever SSH into during
Kubernetes operations. If you learn Kubernetes through PowerShell,
you are learning on a tool you will never use in production.

WSL2 (Windows Subsystem for Linux 2) gives you a real Linux kernel
running directly on your Windows hardware. It is not an emulator.
It shares memory and CPU with Windows natively. Inside WSL2, you have
a genuine Ubuntu terminal — the same shell environment that runs on
every enterprise Kubernetes node.

That is why every command in this repository uses Bash, not PowerShell.
```

---

## The Full Architecture — What You Are Building

```
┌──────────────────────────────────────────────────────────────────────┐
│  WINDOWS HOST (16 GB RAM, RTX 2060)                                  │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │  WSL2 (Ubuntu 22.04) — Your Linux Shell                     │    │
│  │                                                              │    │
│  │   $ kubectl get nodes                                       │    │
│  │   $ kind create cluster                                     │    │
│  │   $ helm install ...                                        │    │
│  │                                                              │    │
│  │   ↕ talks to Docker Engine via WSL2 integration            │    │
│  └──────────────────────────────────────────────────────────────┘    │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │  Docker Desktop                                              │    │
│  │                                                              │    │
│  │   Docker Engine (daemon) ← kind uses this to create nodes   │    │
│  │                                                              │    │
│  │   ┌──────────────────────────────────────────────────┐     │    │
│  │   │  kind Cluster: "learning-cluster"                 │     │    │
│  │   │                                                   │     │    │
│  │   │  ┌───────────────────┐  ┌─────────┐  ┌─────────┐│     │    │
│  │   │  │ control-plane     │  │worker-1 │  │worker-2 ││     │    │
│  │   │  │ (Docker container)│  │(Docker  │  │(Docker  ││     │    │
│  │   │  │                   │  │container│  │container││     │    │
│  │   │  │ kube-apiserver    │  │         │  │         ││     │    │
│  │   │  │ etcd              │  │kubelet  │  │kubelet  ││     │    │
│  │   │  │ scheduler         │  │containerd  containerd││     │    │
│  │   │  │ controller-mgr    │  │kube-proxy  kube-proxy││     │    │
│  │   │  └───────────────────┘  └─────────┘  └─────────┘│     │    │
│  │   └──────────────────────────────────────────────────┘     │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘

kubectl (in WSL2) ──────────────────────────────► kube-apiserver
                                                   (control-plane node)
```

**Reading the diagram:**
- WSL2 is your Linux shell. You type commands here.
- Docker Desktop is the container engine. kind uses it to create "nodes" (which are actually Docker containers that contain a full Kubernetes node stack).
- The kind cluster has 3 nodes: 1 control plane + 2 workers. These are 3 Docker containers running simultaneously.
- kubectl is the Kubernetes CLI. You run it in WSL2, it connects to the kube-apiserver inside the control-plane container, and commands propagate from there.

---

## Step 0: Verify You Are Inside WSL2

Open Ubuntu from the Windows Start menu (search "Ubuntu"). You should see a Linux terminal prompt, not a `PS C:\>` prompt.

Verify:
```bash
# This command should output a Linux kernel version string.
# If you see "Microsoft" in the output, you are in WSL2. Correct.
uname -r

# Expected output (yours will differ in version numbers):
#   5.15.167.4-microsoft-standard-WSL2
```

If you see a PowerShell prompt instead, open the Start menu, search "Ubuntu", and launch it.

---

## Step 1: Verify Docker Desktop Is Running and WSL2-Integrated

```bash
# Check that Docker CLI works from inside WSL2.
# If Docker Desktop is not running, this will fail with a connection error.
docker version

# What you should see:
#   Client: Docker Engine - Community
#    Version:           26.x.x
#   Server: Docker Desktop
#    Engine:
#     Version:          26.x.x
#
# The key: BOTH Client AND Server must show. If only Client shows,
# Docker Desktop is not running. Start it on Windows first.
```

**If Docker is not integrated with WSL2:**
1. Open Docker Desktop on Windows.
2. Click the gear icon → Settings → Resources → WSL Integration.
3. Toggle ON for your Ubuntu distro.
4. Click "Apply & Restart".
5. Close and reopen your Ubuntu terminal.
6. Run `docker version` again.

---

## Step 2: Configure Docker Desktop Resources for Your Machine

Docker Desktop runs the Kubernetes nodes. It needs enough memory.

Go to: **Docker Desktop → Settings → Resources → Advanced**

Set these values for your 16 GB machine:

```
Memory:  8 GB    ← Half your RAM. Leaves 8 GB for Windows + WSL2.
CPUs:    6       ← Leave 2 cores for Windows and other apps.
Swap:    2 GB    ← Safety buffer for memory spikes during heavy workloads.
Disk:    60 GB   ← Kind nodes + container images can grow. 60 GB is safe.
```

> **Why 8 GB for Docker?**
> A 3-node kind cluster (1 control-plane + 2 workers) consumes roughly 2–3 GB
> at idle. Your learning workloads on top of that need headroom. 8 GB of 16 GB
> gives you room to run multiple pods, pull container images, and still keep
> Windows responsive.

**Disable Docker Desktop's built-in Kubernetes:**
Docker Desktop → Settings → Kubernetes → **uncheck** "Enable Kubernetes"

> **Why?** We use `kind` instead. If both are enabled, you get two Kubernetes
> clusters: one called `docker-desktop` and one called `kind-learning-cluster`.
> Running `kubectl get nodes` would talk to the wrong cluster silently — a
> very confusing failure mode for a learner. Disable the built-in one.

Click "Apply & Restart" after making all changes.

---

## Step 3: Install Required Tools (Inside WSL2)

> **You only do this once.** After installation, these tools persist inside
> your WSL2 Ubuntu environment across reboots.

Run the one-shot install script from inside WSL2:

```bash
# Navigate to the repository
cd "/mnt/d/Generative AI Portfolio Projects/kubernetes_architure"

# Run the installer
bash setup/00-prerequisites/platform-guides/windows-wsl2/step-by-step-install.sh
```

The script installs, in order:
1. `kind` — the Kubernetes cluster engine
2. `kubectl` — the universal Kubernetes CLI
3. `helm` — the Kubernetes package manager
4. `kubectx` + `kubens` — fast cluster/namespace switching
5. `k9s` — the terminal Kubernetes dashboard

After it finishes, run the prerequisite checker to verify everything:

```bash
bash setup/00-prerequisites/check-prerequisites.sh
```

---

## Step 4: Create Your First Cluster

```bash
cd "/mnt/d/Generative AI Portfolio Projects/kubernetes_architure"
bash setup/01-cluster-setup/create-cluster.sh
```

This creates a 3-node kind cluster called `learning-cluster`. The first run
downloads the node container image (~700 MB). This may take 5–10 minutes on
first run. Subsequent cluster recreations are fast.

**What you should see at the end:**
```
✓ Cluster "learning-cluster" is ready
✓ 3 nodes: 1 control-plane, 2 workers
✓ All system pods are Running
✓ kubectl context set to kind-learning-cluster
→ Next step: bash setup/01-cluster-setup/verify-cluster.sh
```

---

## Step 5: Verify the Cluster

```bash
bash setup/01-cluster-setup/verify-cluster.sh
```

Or verify manually:
```bash
# See your cluster nodes
kubectl get nodes

# Expected output:
#   NAME                               STATUS   ROLES           AGE
#   learning-cluster-control-plane     Ready    control-plane   2m
#   learning-cluster-worker            Ready    <none>          90s
#   learning-cluster-worker2           Ready    <none>          90s

# See what is running inside your cluster by default
kubectl get pods --all-namespaces

# The system pods you expect to see Running:
#   kube-system   coredns-*             2/2   Running
#   kube-system   etcd-*                1/1   Running
#   kube-system   kube-apiserver-*      1/1   Running
#   kube-system   kube-controller-*     1/1   Running
#   kube-system   kube-proxy-*          3/3   Running (one per node)
#   kube-system   kube-scheduler-*      1/1   Running
#   local-path-storage  local-path-*   1/1   Running
```

---

## Step 6: Open k9s (Your Cluster Dashboard)

```bash
k9s
```

This opens a live, vim-navigable view of everything in your cluster. You will
see nodes, pods, namespaces, and resource usage in real time.

Navigation:
- `0` — show all namespaces
- `:pods` — focus on pods view
- `j` / `k` — navigate up/down
- `Enter` — drill into a resource
- `l` — view logs for a pod
- `Esc` — go back
- `Ctrl+C` — exit

---

## Daily Startup Sequence (Bookmark This)

Every time you come back to this project, do this in order:

```bash
# 1. Start Docker Desktop on Windows (if it's not already running).

# 2. Open Ubuntu from the Start menu.

# 3. Confirm you are in Linux:
uname -r   # Should show "microsoft-standard-WSL2"

# 4. Confirm Docker is available:
docker version   # Both Client and Server should appear.

# 5. Navigate to the repository:
cd "/mnt/d/Generative AI Portfolio Projects/kubernetes_architure"

# 6. Check if your cluster is already running:
kubectl get nodes 2>/dev/null || echo "Cluster not running — recreate with:"
echo "  bash setup/01-cluster-setup/create-cluster.sh"

# 7. If the cluster is running, you are ready. If not, create it.
```

> **Why recreate the cluster sometimes?** kind clusters are not persistent
> across Windows reboots — Docker containers (the nodes) stop. The cluster
> configuration is preserved on disk, so `create-cluster.sh` rebuilds it
> identically in under 2 minutes.

---

## Common Problems and Fixes

### "Docker daemon is not running"
- Open Docker Desktop on Windows. Wait for it to fully start (whale icon in taskbar).
- Then return to WSL2 and retry.

### "Cannot connect to the Docker daemon at unix:///var/run/docker.sock"
- Docker Desktop's WSL2 integration is disabled.
- Docker Desktop → Settings → Resources → WSL Integration → enable your Ubuntu distro.

### "kind: command not found"
- kind is not installed, or not on PATH.
- Run: `bash setup/00-prerequisites/platform-guides/windows-wsl2/step-by-step-install.sh`

### "kubectl: Unable to connect to the server"
- The cluster may not be running.
- Check: `docker ps | grep learning-cluster`
- If no containers appear, the cluster is stopped. Recreate it:
  `bash setup/01-cluster-setup/create-cluster.sh`

### k9s shows blank / no resources
- You may be in the wrong namespace. Press `0` to show all namespaces.

### Node stays NotReady for more than 3 minutes
- Usually a Docker memory issue. Check Docker Desktop → Resources → Memory is set to at least 8 GB.
- Recreate the cluster: `bash setup/01-cluster-setup/create-cluster.sh`

---

## What This Maps to in Enterprise

| Local Setup | Enterprise Equivalent |
|---|---|
| WSL2 Ubuntu terminal | Linux bastion host / Cloud Shell / Jump server |
| Docker Desktop | Managed container runtime on EC2/GCE nodes |
| kind cluster | AWS EKS, Google GKE, Azure AKS, On-prem OpenShift |
| kind nodes (Docker containers) | EC2 instances, GCE VMs, Azure VMs, bare-metal |
| local kubeconfig (`~/.kube/config`) | kubeconfig from `aws eks update-kubeconfig`, `gcloud container clusters get-credentials` |
| `kubectl get nodes` | Same command, same output — kubectl is universal |
| k9s dashboard | Kubernetes Dashboard, Lens, OpenLens, Rancher UI |

---

## Next Step

You have a running Kubernetes cluster. Now learn what is inside it.

→ Continue to: [01-cluster-setup/README.md](../../01-cluster-setup/README.md)
