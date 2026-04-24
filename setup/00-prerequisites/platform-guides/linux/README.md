# Linux Setup

Linux is the closest local environment to the actual machines that run Kubernetes clusters and platform tooling in enterprise environments.

That is good news for learning:
- the shell behavior is already correct
- file permissions behave normally
- Bash scripts work naturally
- there is no Windows-to-Linux translation layer to think about

## Stage 0.0 - What You Are Building

Your local learning stack looks like this:

```text
Linux machine
    |
    v
Docker engine
    |
    v
kind cluster
    |
    v
kubectl commands
```

Why this matters:
- `kind` needs Docker to create cluster nodes
- `kubectl` needs a cluster to talk to
- this repository assumes Bash and Linux-like behavior throughout

## Stage 1.0 - Open The Correct Terminal

Open your normal Linux terminal.

Why:
- All commands in this repository are Bash-oriented
- you should avoid switching between shells when learning the core workflow

## Stage 2.0 - Move To The Repository

Run:

```bash
cd "/path/to/kubernetes_architure"
pwd
```

What this teaches:
- `cd` changes your working directory
- `pwd` confirms where you are before you run scripts

Replace `"/path/to/kubernetes_architure"` with the actual location of your repository.

## Stage 3.0 - Run The Pre-Check First

Run:

```bash
bash setup/00-prerequisites/check-prerequisites.sh
```

Why:
- we do not guess what is missing
- we let the repository check Docker, `kubectl`, `kind`, and helper tools for us

How to interpret the result:
- missing `kind` = hard blocker
- missing `helm` = not a blocker for the basics, but important later
- missing `kubectx` and `k9s` = useful but optional

## Stage 4.0 - Install The Required Tools

There are two groups of tools:

Required:
- `docker`
- `kind`
- `kubectl`

Recommended:
- `helm`
- `kubectx`
- `k9s`

## Stage 4.1 - Make Sure Docker Works

Before installing anything else, confirm Docker is installed and the daemon is running.

Run:

```bash
docker --version
docker info
```

What this teaches:
- `docker --version` checks that the CLI exists
- `docker info` checks that the Docker daemon is actually running

What success looks like:
- both commands print normal output
- `docker info` does not fail with a daemon error

If `docker info` fails:
- start Docker Engine or Docker Desktop for Linux first
- do not try to create the cluster yet

## Stage 4.2 - Install `kind`

Run:

```bash
[ "$(uname -m)" = "x86_64" ] && ARCH=amd64 || ARCH=arm64
curl -Lo /tmp/kind "https://kind.sigs.k8s.io/dl/v0.23.0/kind-linux-${ARCH}"
chmod +x /tmp/kind
sudo mv /tmp/kind /usr/local/bin/kind
kind version
```

What each line means:
- detect your CPU architecture so you download the right binary
- download the `kind` executable
- make it runnable
- move it to `/usr/local/bin` so your shell can find it as a command
- verify the install

Why `kind` matters most:
- this repository cannot create the local Kubernetes cluster without it

## Stage 4.3 - Install `kubectl`

Run:

```bash
K8S_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
curl -LO "https://dl.k8s.io/release/${K8S_VERSION}/bin/linux/amd64/kubectl"
curl -LO "https://dl.k8s.io/release/${K8S_VERSION}/bin/linux/amd64/kubectl.sha256"
echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
kubectl version --client
```

What this teaches:
- `kubectl` is downloaded directly from the Kubernetes project
- the checksum verification proves the file was downloaded correctly
- `install` places it into a standard executable path

Why `kubectl` matters:
- it is the main CLI for talking to any Kubernetes cluster anywhere

## Stage 4.4 - Install `helm`

Run:

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version --short
```

Why this matters:
- Helm is the package manager for Kubernetes
- later parts of this repository, especially the serving/platform side, become easier with Helm

## Stage 4.5 - Install `kubectx` and `kubens`

Run:

```bash
sudo git clone https://github.com/ahmetb/kubectx /opt/kubectx || true
sudo ln -sf /opt/kubectx/kubectx /usr/local/bin/kubectx
sudo ln -sf /opt/kubectx/kubens /usr/local/bin/kubens
command -v kubectx
command -v kubens
```

Why this matters:
- these tools help you switch clusters and namespaces safely
- they reduce the chance of running commands against the wrong target

## Stage 4.6 - Install `k9s`

Run:

```bash
curl -sS https://webinstall.dev/k9s | bash
k9s version --short || true
```

Why this matters:
- `k9s` gives you a fast terminal dashboard for exploring the cluster
- it is optional, but extremely useful while learning

## Stage 5.0 - Re-Run The Repository Check

Run:

```bash
cd "/path/to/kubernetes_architure"
bash setup/00-prerequisites/check-prerequisites.sh
```

What success looks like:
- `kind` passes
- `kubectl` passes
- Docker passes

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
- verify node and control-plane health

## Stage 7.0 - If You Come Back Later And Forget Everything

Use this exact restart recipe:

```bash
cd "/path/to/kubernetes_architure"
bash setup/00-prerequisites/check-prerequisites.sh
bash setup/01-cluster-setup/create-cluster.sh
bash setup/01-cluster-setup/verify-cluster.sh
```

## Most Important Things To Remember

- check Docker before blaming Kubernetes
- install `kind` before anything else if it is missing
- `kubectl` is your main Kubernetes command-line tool
- `helm`, `kubectx`, and `k9s` improve the workflow, but they are not the first blocker

## Enterprise Translation

The same shell patterns, file paths, and CLI behavior you use here are extremely close to what you use on:
- cloud VMs
- self-managed Linux servers
- CI/CD runners
- bastion hosts
