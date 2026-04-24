# 00-prerequisites

This module prepares the workstation before any cluster exists. Run [check-prerequisites.sh](/D:/Generative%20AI%20Portfolio%20Projects/kubernetes_architure/setup/00-prerequisites/check-prerequisites.sh) first to see what is already available, then use [install-guide.md](/D:/Generative%20AI%20Portfolio%20Projects/kubernetes_architure/setup/00-prerequisites/install-guide.md) and the platform-specific guides to fill the gaps.

## File Order

1. `check-prerequisites.sh`: tells you what is missing right now.
2. `install-guide.md`: explains the shared enterprise setup logic.
3. `platform-guides/<platform>/README.md`: gives platform-specific steps.
4. `first-time-windows-k8s-checklist.md`: the shortest path if you are on Windows and want the spoon-fed sequence.

## Why This Exists

Enterprise Kubernetes work fails fast when Docker, `kubectl`, `kind`, or WSL2 are misconfigured. This module makes those dependencies explicit before the learner hits harder-to-debug cluster errors later.

## What Is Actually Required To Start

You only need these to begin the Kubernetes learning path in this repository:
- Docker Desktop running
- WSL2 Ubuntu shell on Windows, or a native Linux/macOS shell
- `kubectl`
- `kind`

These are optional but strongly recommended:
- `helm`: needed later for KServe and many enterprise platform installs
- `kubectx`: helps switch clusters and namespaces safely
- `k9s`: makes cluster inspection much faster

If `kind` is missing, you cannot create the local cluster yet.

## Toolchain Explanations: What Are These Tools?

As a platform engineer, your toolkit is critical. Here is what these tools do and how they fit into the enterprise picture:

### 1. `kind` (Kubernetes IN Docker) — **Required**
*The Sandbox Environment*
- **What it is:** A tool that spins up a full, working Kubernetes cluster inside Docker containers on your local machine. It treats Docker containers as if they were physical Kubernetes "nodes."
- **How it comes into the picture:** To learn and test Kubernetes, you need a cluster. Cloud clusters (like AWS EKS or Google GKE) cost money and take 15-20 minutes to spin up. `kind` allows you to spin up a fully compliant, multi-node Kubernetes cluster on your laptop in about 30 seconds for free. 
- **Enterprise Use Case:** Engineers use `kind` to write and test their code locally before pushing it. It's also used heavily in automated CI/CD pipelines (like GitHub Actions) to run integration tests against a real cluster before deploying to Production.

### 2. `kubectx` (and `kubens`) — **Optional**
*The Context Switcher*
- **What it is:** A lightning-fast way to switch between different Kubernetes clusters (contexts) and different environments (namespaces).
- **How it comes into the picture:** By default, if you want to switch your terminal from your local cluster to a cloud cluster, you have to type `kubectl config use-context my-long-aws-cluster-name-us-east-1`. `kubectx` lets you just type `kubectx aws-cluster`. 
- **Enterprise Use Case:** In a real company, you will juggle multiple clusters daily (e.g., `local`, `dev`, `staging`, `prod-eu`). `kubectx` prevents you from accidentally deploying code to Production when you thought you were connected to Dev. 

### 3. `k9s` — **Optional**
*The Terminal Dashboard*
- **What it is:** A terminal-based UI (user interface) that acts like a real-time dashboard for your Kubernetes cluster. Think of it like the Windows Task Manager (or Linux `htop`), but for Kubernetes.
- **How it comes into the picture:** Typing `kubectl get pods`, then `kubectl describe pod XYZ`, then `kubectl logs XYZ` over and over is slow and tedious when debugging. `k9s` gives you a visual list of your pods where you can use arrow keys to navigate, press `l` to see logs, or press `s` to open a shell instantly.
- **Enterprise Use Case:** SREs (Site Reliability Engineers) and DevOps teams use `k9s` during live production outages because it allows them to navigate the cluster and find failing applications significantly faster than typing raw `kubectl` commands.

### 4. `helm` — **Optional**
*The Package Manager*
- **What it is:** The "App Store" or package manager for Kubernetes. It is the exact equivalent of `apt` on Ubuntu, `brew` on Mac, or `npm` in Node.js.
- **How it comes into the picture:** Deploying a simple app might take 3 YAML files. But deploying a complex database (like PostgreSQL) might require 20 highly complex YAML files. Instead of writing them yourself, Helm bundles all those YAML files into a single package called a "Chart." 
- **Enterprise Use Case:** If a company needs to install an industry-standard monitoring stack (like Prometheus and Grafana) into their cluster, they don't write the YAML from scratch. They run `helm install prometheus prometheus-community/kube-prometheus-stack`, and Helm automatically configures and deploys hundreds of resources perfectly in seconds.

## Windows Learner Shortcut

If you are on Windows, your practical path is:
1. Open Ubuntu in WSL2.
2. Confirm Docker Desktop is open on the Windows side.
3. Install `kind` first.
4. Install `helm`, `kubectx`, and `k9s` next.
5. Re-run `bash setup/00-prerequisites/check-prerequisites.sh`.
6. Start the cluster with `bash setup/01-cluster-setup/create-cluster.sh`.

If you want the simplest possible guided version, open:
- [first-time-windows-k8s-checklist.md](/D:/Generative%20AI%20Portfolio%20Projects/kubernetes_architure/setup/00-prerequisites/first-time-windows-k8s-checklist.md)
- [platform-guides/windows-wsl2/README.md](/D:/Generative%20AI%20Portfolio%20Projects/kubernetes_architure/setup/00-prerequisites/platform-guides/windows-wsl2/README.md)
