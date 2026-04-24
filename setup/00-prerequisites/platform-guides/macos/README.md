# macOS Setup

This path uses a native Unix shell, Docker Desktop, and standard CLI tooling.

For a learner, macOS is a comfortable environment because:
- the shell experience is already Unix-like
- Bash-compatible scripts work naturally
- common developer tooling is easy to install with Homebrew

## Stage 0.0 - What You Are Building

Your local learning stack looks like this:

```text
macOS laptop
    |
    v
Terminal shell
    |
    v
Docker Desktop
    |
    v
kind cluster
    |
    v
kubectl commands
```

Why this matters:
- Docker Desktop provides the container engine
- `kind` uses that engine to create a Kubernetes cluster
- `kubectl` talks to the cluster once it exists

## Stage 1.0 - Open Terminal And Move To The Repository

Run:

```bash
cd "/path/to/kubernetes_architure"
pwd
```

What this teaches:
- `cd` moves into the repository
- `pwd` confirms where you are before running scripts

Replace `"/path/to/kubernetes_architure"` with the actual path on your Mac.

## Stage 2.0 - Run The Pre-Check First

Run:

```bash
bash setup/00-prerequisites/check-prerequisites.sh
```

Why:
- the repository tells us exactly what is missing
- we avoid random installation steps we may not need

How to interpret the result:
- missing `kind` = hard blocker
- missing `helm` = not a blocker for Kubernetes basics, but useful later
- missing `kubectx` and `k9s` = optional workflow tools

## Stage 3.0 - Make Sure Docker Desktop Is Running

Before installing cluster tools, make sure Docker Desktop is open.

Then run:

```bash
docker --version
docker info
```

What this teaches:
- `docker --version` confirms the CLI exists
- `docker info` confirms the Docker engine is actually running

If `docker info` fails:
- open Docker Desktop first
- wait for it to finish starting

## Stage 4.0 - Install The Required Tools

Required for this repository:
- `docker`
- `kind`
- `kubectl`

Recommended:
- `helm`
- `kubectx`
- `k9s`

## Stage 4.1 - Install `kind`

Run:

```bash
brew install kind
kind version
```

What this teaches:
- Homebrew is the standard package manager for many macOS developer tools
- `kind version` confirms the install worked

Why `kind` matters most:
- this repository cannot create the local cluster without it

## Stage 4.2 - Install `kubectl`

Run:

```bash
brew install kubectl
kubectl version --client
```

Why this matters:
- `kubectl` is the universal Kubernetes command-line tool
- it works against local clusters and enterprise cloud clusters alike

## Stage 4.3 - Install `helm`

Run:

```bash
brew install helm
helm version --short
```

Why this matters:
- Helm is the package manager for Kubernetes
- you will use it later for more platform-style installs

## Stage 4.4 - Install `kubectx`

Run:

```bash
brew install kubectx
command -v kubectx
command -v kubens
```

Why this matters:
- `kubectx` switches clusters
- `kubens` switches namespaces
- they reduce context mistakes once you have more than one environment

## Stage 4.5 - Install `k9s`

Run:

```bash
brew install k9s
k9s version --short || true
```

Why this matters:
- `k9s` gives you a fast terminal dashboard for inspecting pods, logs, events, and restarts

## Stage 5.0 - Re-Run The Repository Check

Run:

```bash
cd "/path/to/kubernetes_architure"
bash setup/00-prerequisites/check-prerequisites.sh
```

What success looks like:
- Docker passes
- `kind` passes
- `kubectl` passes

If only optional tools are missing:
- you can still continue

## Stage 6.0 - Create The Cluster

Run:

```bash
bash setup/01-cluster-setup/create-cluster.sh
bash setup/01-cluster-setup/verify-cluster.sh
```

What these do:
- create the local multi-node cluster
- verify that nodes and core components are healthy

## Stage 7.0 - If You Come Back Later And Forget Everything

Use this restart recipe:

```bash
cd "/path/to/kubernetes_architure"
bash setup/00-prerequisites/check-prerequisites.sh
bash setup/01-cluster-setup/create-cluster.sh
bash setup/01-cluster-setup/verify-cluster.sh
```

## Most Important Things To Remember

- start Docker Desktop before trying to create the cluster
- install `kind` first if it is missing
- `kubectl` is your main Kubernetes CLI
- `helm`, `kubectx`, and `k9s` improve the experience but are not the first blocker

## Enterprise Translation

macOS is not production, but the shell workflow is close enough to Linux that:
- the same Bash scripts work
- the same Kubernetes concepts apply
- the same CLI habits transfer cleanly into enterprise environments
