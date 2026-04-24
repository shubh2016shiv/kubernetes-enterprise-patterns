# Windows WSL2 Setup

This is the preferred Windows path for this repository.

The mental model is:
- Windows is only the host operating system
- Ubuntu in WSL2 is your real working shell
- Docker Desktop is the container engine
- `kind` creates the Kubernetes cluster inside Docker
- `kubectl` talks to that cluster

If you remember only one thing, remember this:

**Do Kubernetes work in Ubuntu WSL2, not in PowerShell.**

## Stage 0.0 - What You Are Building

Before we type commands, understand the stack:

```text
Windows laptop
    |
    v
WSL2 Ubuntu shell
    |
    v
Docker Desktop engine
    |
    v
kind cluster
    |
    v
kubectl commands
```

Why this matters:
- Kubernetes is Linux-first in real enterprise environments.
- WSL2 makes your laptop behave much more like a Linux server or CI runner.
- That means the scripts in this repository behave the same way locally and in professional environments.

## Stage 1.0 - Open The Correct Things

### Step 1.1 - Start Docker Desktop

Do this on the Windows side first.

Why:
- `kind` creates Kubernetes nodes as Docker containers.
- If Docker Desktop is not running, cluster creation will fail immediately.

What success looks like:
- Docker Desktop opens normally.
- It shows the engine is running.

### Step 1.2 - Open Ubuntu, Not PowerShell

Open the Ubuntu app from the Windows Start menu.

Why:
- This repository uses Bash scripts.
- The path style, permissions, and tooling behavior must be Linux-like.

### Step 1.3 - Confirm You Are Really In Linux

Run:

```bash
uname -a
pwd
whoami
```

What this teaches:
- `uname -a` shows Linux kernel details.
- `pwd` shows your current folder.
- `whoami` shows your Ubuntu username.

What success looks like:
- `uname -a` mentions Linux
- You are inside your Ubuntu home directory, not a Windows prompt

## Stage 2.0 - Move To The Repository From Ubuntu

### Step 2.1 - Go To The Project Folder

Run:

```bash
cd "/mnt/d/Generative AI Portfolio Projects/kubernetes_architure"
pwd
```

Why this path looks strange:
- WSL2 mounts your Windows `D:` drive under `/mnt/d`
- So a Windows path like:

```text
D:\Generative AI Portfolio Projects\kubernetes_architure
```

becomes:

```text
/mnt/d/Generative AI Portfolio Projects/kubernetes_architure
```

What success looks like:
- `pwd` prints `/mnt/d/Generative AI Portfolio Projects/kubernetes_architure`

## Stage 3.0 - Run The Pre-Check Before Installing Anything

### Step 3.1 - Run The Repository Checker

Run:

```bash
bash setup/00-prerequisites/check-prerequisites.sh
```

Why:
- We do not guess what is missing.
- We let the repository tell us the real blockers first.

How to interpret the result:
- Missing `kind` = hard blocker
- Missing `helm` = not a blocker for the basic cluster, but important later
- Missing `kubectx` = optional workflow improvement
- Missing `k9s` = optional workflow improvement

## Stage 4.0 - Install The Tools

There are two installation paths:
- system-wide install with `sudo`
- user-local install into `~/.local/bin`

If you are learning and just want to get moving safely, the user-local path is completely fine.

## Stage 4.1 - System-Wide Install Path

Use this if you are comfortable entering your Ubuntu password for `sudo`.

### Step 4.1.1 - Install Base Utilities

Run:

```bash
sudo apt-get update
sudo apt-get install -y curl git ca-certificates
```

What this does:
- `apt-get update`: refreshes Ubuntu’s package list
- `curl`: downloads files from the internet
- `git`: clones repositories like `kubectx`
- `ca-certificates`: lets HTTPS downloads verify trusted certificates correctly

### Step 4.1.2 - Install `kind`

Run:

```bash
[ "$(uname -m)" = "x86_64" ] && ARCH=amd64 || ARCH=arm64
curl -Lo /tmp/kind "https://kind.sigs.k8s.io/dl/v0.23.0/kind-linux-${ARCH}"
chmod +x /tmp/kind
sudo mv /tmp/kind /usr/local/bin/kind
kind version
```

What each line means:
- detect your CPU architecture so you download the correct binary
- download the `kind` binary into `/tmp`
- make it executable
- move it into `/usr/local/bin` so Ubuntu can find it as a normal command
- verify the install

Why `kind` matters most:
- This repository cannot create the cluster without it.

What success looks like:
- `kind version` prints something like `kind v0.23.0 ...`

### Step 4.1.3 - Install `helm`

Run:

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version --short
```

What this teaches:
- Helm is the package manager for Kubernetes.
- Later, the ML serving part of this repository uses Helm-installed platform components.

What success looks like:
- `helm version --short` prints a version like `v3.x.x+...`

### Step 4.1.4 - Install `kubectx` and `kubens`

Run:

```bash
sudo git clone https://github.com/ahmetb/kubectx /opt/kubectx || true
sudo ln -sf /opt/kubectx/kubectx /usr/local/bin/kubectx
sudo ln -sf /opt/kubectx/kubens /usr/local/bin/kubens
command -v kubectx
command -v kubens
```

What this teaches:
- `kubectx` switches clusters
- `kubens` switches namespaces
- These help prevent confusion once you work with multiple environments

### Step 4.1.5 - Install `k9s`

Run:

```bash
curl -sS https://webinstall.dev/k9s | bash
k9s version --short || true
```

What this teaches:
- `k9s` is a fast terminal dashboard for Kubernetes
- It is optional, but it makes cluster exploration much easier

## Stage 4.2 - User-Local Install Path

Use this if:
- you do not want to install system-wide
- your `sudo` flow is inconvenient
- you want a learner-friendly setup owned by your Ubuntu user

This installs tools under `~/.local/bin`.

### Step 4.2.1 - Prepare Your Local CLI Folder

Run:

```bash
mkdir -p "$HOME/.local/bin" "$HOME/.local/share"

if ! grep -q 'HOME/.local/bin' "$HOME/.bashrc"; then
  printf '\n# Local CLI tools for Kubernetes learning\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$HOME/.bashrc"
fi

export PATH="$HOME/.local/bin:$PATH"
```

What this does:
- creates a user-owned `bin` folder
- teaches Bash to look there for commands
- avoids needing `sudo` for these tool installs

### Step 4.2.2 - Install `kind`

Run:

```bash
[ "$(uname -m)" = "x86_64" ] && ARCH=amd64 || ARCH=arm64
curl -fsSL -o "$HOME/.local/bin/kind" "https://kind.sigs.k8s.io/dl/v0.23.0/kind-linux-${ARCH}"
chmod +x "$HOME/.local/bin/kind"
kind version
```

### Step 4.2.3 - Install `helm`

Run:

```bash
export HELM_INSTALL_DIR="$HOME/.local/bin"
export USE_SUDO=false
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version --short
```

Why these environment variables matter:
- `HELM_INSTALL_DIR` tells the installer where to place the binary
- `USE_SUDO=false` prevents the script from trying system-wide installation

### Step 4.2.4 - Install `kubectx` and `kubens`

Run:

```bash
git clone https://github.com/ahmetb/kubectx "$HOME/.local/share/kubectx"
ln -sf "$HOME/.local/share/kubectx/kubectx" "$HOME/.local/bin/kubectx"
ln -sf "$HOME/.local/share/kubectx/kubens" "$HOME/.local/bin/kubens"
command -v kubectx
command -v kubens
```

### Step 4.2.5 - Install `k9s`

Run:

```bash
curl -fsSL https://webinstall.dev/k9s | bash
export PATH="$HOME/.local/bin:$PATH"
k9s version --short || true
```

### Step 4.2.6 - Reload Your Shell

Run:

```bash
source ~/.bashrc
```

Or just close Ubuntu and open it again.

Why:
- Your shell needs to pick up the new `PATH` entry if you changed `.bashrc`

## Stage 5.0 - Verify The Install

Run:

```bash
cd "/mnt/d/Generative AI Portfolio Projects/kubernetes_architure"
bash setup/00-prerequisites/check-prerequisites.sh
```

What success looks like now:
- `kind` should pass
- `kubectl` should pass
- `helm`, `kubectx`, and `k9s` should pass if you installed them

If only optional tools are missing:
- you can still move forward with Kubernetes basics

If `kind` is still missing:
- do not start cluster creation yet
- re-check the exact install step for `kind`

## Stage 6.0 - Create The Cluster

Once the prerequisite check looks good, run:

```bash
bash setup/01-cluster-setup/create-cluster.sh
bash setup/01-cluster-setup/verify-cluster.sh
```

What these do:
- `create-cluster.sh` creates the local `kind` cluster
- `verify-cluster.sh` confirms the control plane and nodes are healthy

What success looks like:
- nodes show as `Ready`
- cluster verification passes

## Stage 7.0 - If You Come Back Later And Forget Everything

Use this exact sequence:

```bash
# Windows side
# 1. Open Docker Desktop

# Ubuntu side
cd "/mnt/d/Generative AI Portfolio Projects/kubernetes_architure"
bash setup/00-prerequisites/check-prerequisites.sh
bash setup/01-cluster-setup/create-cluster.sh
bash setup/01-cluster-setup/verify-cluster.sh
```

That is your restart recipe.

## Most Important Things To Remember

- Open Docker Desktop before trying to create the cluster.
- Open Ubuntu, not PowerShell, for repository scripts.
- `kind` is the hard blocker for cluster creation.
- `helm` matters more when you move into KServe and enterprise add-ons.
- Your Windows `D:` drive appears as `/mnt/d` in WSL2.
- User-local install into `~/.local/bin` is perfectly valid for this learning project.

## Enterprise Translation

WSL2 is not production, but it gives you:
- Linux paths
- Bash behavior
- realistic CLI ergonomics
- a workflow much closer to cloud VMs, bastion hosts, and CI runners

That is why this is the recommended Windows path for the repository.
