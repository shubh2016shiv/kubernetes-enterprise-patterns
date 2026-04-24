# 01-cluster-setup

This module creates the local multi-node `kind` cluster that the rest of the repository depends on.

Think of this module as the moment where your laptop stops being “just a machine with Docker” and starts behaving like a real Kubernetes platform lab.

## Stage 0.0 - What You Are Building

Before running commands, understand what this module is creating:

```text
Your laptop
    |
    v
Docker engine
    |
    v
kind cluster
    |
    +--> 1 control-plane node
    |
    +--> 2 worker nodes
```

Why this matters:
- Kubernetes is not “one container” or “one process”
- even locally, we want to simulate the separation between control plane and worker nodes
- that is why this repository uses `kind` instead of a simpler black-box local mode

## Stage 1.0 - File Order And Why It Matters

Open and use the files in this order:

1. `kind-cluster-config.yaml`
2. `create-cluster.sh`
3. `verify-cluster.sh`
4. `destroy-cluster.sh`

Why this order matters:
- the YAML is the cluster blueprint
- the create script applies that blueprint
- the verify script checks whether the platform is healthy
- the destroy script resets the lab when you want a clean start

This is the same operational rhythm used in enterprise platform work:

```text
define desired state
    ->
create or reconcile environment
    ->
verify health
    ->
start onboarding workloads
```

## Stage 2.0 - Read The Cluster Blueprint First

Before creating anything, open:

- [kind-cluster-config.yaml](/D:/Generative%20AI%20Portfolio%20Projects/kubernetes_architure/setup/01-cluster-setup/kind-cluster-config.yaml)

What to look for:
- cluster name
- Kubernetes version
- number of nodes
- control-plane vs worker roles
- port mappings
- zone labels

### Why This YAML Matters

This file is the architectural contract for your local cluster.

It teaches you:
- what a control-plane node is
- what a worker node is
- why multi-node topology matters
- how traffic enters the cluster locally
- how labels help Kubernetes spread workloads across nodes

### Most Important Things In The YAML

#### 1. `name: local-enterprise-dev`

This is the name of the cluster.

Why you care:
- `kind get clusters` will show this name
- `kubectl` context will become `kind-local-enterprise-dev`
- Docker containers for nodes will be named with this cluster prefix

#### 2. Control plane plus workers

You are not creating one node.

You are creating:
- 1 control-plane node
- 2 worker nodes

Why this matters:
- the control plane runs Kubernetes management components
- workers run your actual workloads
- this is much closer to enterprise reality than a single-node setup

#### 3. Port mappings

These lines let your host machine reach services inside the cluster.

Important ones:
- `8080` and `8443`: ingress-style entry points
- `30000` and `30001`: NodePort access for lab testing

Why this matters:
- later modules use these mappings so you can reach workloads from your browser or `curl`

## Stage 3.0 - Confirm Prerequisites Before Creating The Cluster

Do not jump straight into `create-cluster.sh`.

First run:

```bash
cd "/path/to/kubernetes_architure"
bash setup/00-prerequisites/check-prerequisites.sh
```

What must already be true:
- Docker is installed
- Docker daemon is running
- `kind` is installed
- `kubectl` is installed

If `kind` is missing:
- stop here
- go back to the prerequisite docs

## Stage 4.0 - Create The Cluster

Run:

```bash
cd "/path/to/kubernetes_architure"
bash setup/01-cluster-setup/create-cluster.sh
```

## Stage 4.1 - What `create-cluster.sh` Actually Does

The script is not “just one command.”

It performs these stages:

1. checks Docker
2. checks `kind`
3. checks `kubectl`
4. confirms the cluster YAML exists
5. checks whether the cluster already exists
6. creates it if needed
7. exports kubeconfig
8. waits for nodes to become `Ready`
9. prints cluster details

Why this is good engineering:
- it is idempotent
- it validates before acting
- it gives you diagnostic output instead of failing mysteriously

## Stage 4.2 - What You Should Expect During Cluster Creation

When the cluster is being created, `kind` is doing real work under the hood:

```text
pull node image
    ->
create Docker containers as nodes
    ->
bootstrap Kubernetes control plane
    ->
join worker nodes
    ->
write kubeconfig
    ->
wait for Ready status
```

Typical time:
- around 60 to 120 seconds

What success looks like:
- `kubectl get nodes` shows 3 nodes
- all nodes show `Ready`
- current context becomes `kind-local-enterprise-dev`

## Stage 5.0 - Verify The Cluster

After creation, run:

```bash
bash setup/01-cluster-setup/verify-cluster.sh
```

### What `verify-cluster.sh` Checks

It verifies:
- API server connectivity
- node readiness
- `kube-system` pod health
- CoreDNS presence
- node resource visibility
- active `kubectl` context

Why this matters:
- a cluster that exists is not automatically a healthy cluster
- enterprise engineers always check control plane and system health before trusting the environment

### What Success Looks Like

You should see:
- API server responding
- all nodes marked `Ready`
- system pods in `kube-system` mostly `Running`
- context set to `kind-local-enterprise-dev`

## Stage 6.0 - Learn To Inspect The Cluster Manually

After the verify script passes, run these yourself:

```bash
kubectl get nodes -o wide
kubectl get pods -A
kubectl get namespaces
kubectl cluster-info
kubectl config get-contexts
docker ps | grep kind
```

What each command teaches:
- `kubectl get nodes -o wide`: node names, roles, IPs, and runtime details
- `kubectl get pods -A`: every pod in every namespace
- `kubectl get namespaces`: built-in and later custom namespaces
- `kubectl cluster-info`: where the API server is reachable
- `kubectl config get-contexts`: which clusters your `kubectl` knows about
- `docker ps | grep kind`: the fact that `kind` nodes are really Docker containers

## Stage 7.0 - If Something Fails

### Problem: Docker is not running

Symptom:
- `docker info` fails

Fix:
- start Docker Desktop or Docker Engine
- rerun the create script

### Problem: `kind` is missing

Symptom:
- the create script stops during pre-flight checks

Fix:
- go back to [setup/00-prerequisites/README.md](/D:/Generative%20AI%20Portfolio%20Projects/kubernetes_architure/setup/00-prerequisites/README.md)

### Problem: nodes stay `NotReady`

Symptom:
- create script times out
- verify script shows failing nodes

Useful commands:

```bash
kubectl get nodes -o wide
kubectl describe nodes
kubectl get pods -n kube-system
```

Why:
- `describe` shows conditions and events
- `kube-system` pods reveal whether networking or control-plane components are stuck

### Problem: wrong context

Symptom:
- `kubectl` points somewhere unexpected

Fix:

```bash
kubectl config use-context kind-local-enterprise-dev
```

Why this matters:
- context mistakes are one of the most common Kubernetes operator mistakes

## Stage 8.0 - Destroy And Recreate The Cluster Safely

When you want a clean reset, run:

```bash
bash setup/01-cluster-setup/destroy-cluster.sh
```

What this does:
- deletes the local cluster
- removes cluster state
- keeps your YAML files safe on disk

Why this is useful:
- local labs should be easy to destroy and rebuild
- that lets you learn by repetition without fear

## Stage 9.0 - The First-Time Learner Command Sequence

If you want the shortest practical flow, use this:

```bash
cd "/path/to/kubernetes_architure"

# 1. Confirm prerequisites
bash setup/00-prerequisites/check-prerequisites.sh

# 2. Read the cluster blueprint
less setup/01-cluster-setup/kind-cluster-config.yaml

# 3. Create the cluster
bash setup/01-cluster-setup/create-cluster.sh

# 4. Verify the cluster
bash setup/01-cluster-setup/verify-cluster.sh

# 5. Explore it manually
kubectl get nodes -o wide
kubectl get pods -A
kubectl cluster-info
```

## Stage 10.0 - If You Come Back Later And Forget Everything

Use this restart recipe:

```bash
cd "/path/to/kubernetes_architure"
bash setup/00-prerequisites/check-prerequisites.sh
bash setup/01-cluster-setup/create-cluster.sh
bash setup/01-cluster-setup/verify-cluster.sh
```

## Most Important Things To Remember

- read the YAML before running the creation script
- `kind` is creating real Kubernetes nodes as Docker containers
- the cluster is only useful after verification, not just after creation
- multi-node topology is one of the key educational choices in this repository

## What Comes Next

Once this module is healthy, move to:

- [02-namespaces/README.md](/D:/Generative%20AI%20Portfolio%20Projects/kubernetes_architure/setup/02-namespaces/README.md)

Why namespaces come next:
- once the platform exists, the first enterprise habit is isolation
- namespaces are the first clean boundary you learn inside a cluster
