# First-Time Cluster Checklist

This is the shortest possible “just tell me exactly what to run” version for the cluster setup stage.

## Before Running Anything

1. Make sure Docker is running.
2. Make sure `kind` and `kubectl` are installed.
3. Move to the repository root.

```bash
cd "/path/to/kubernetes_architure"
```

## Step 1 - Check Prerequisites

```bash
bash setup/00-prerequisites/check-prerequisites.sh
```

If `kind` is missing, stop and install it first.

## Step 2 - Read The Cluster Blueprint

```bash
less setup/01-cluster-setup/kind-cluster-config.yaml
```

Focus on:
- cluster name
- 1 control-plane node
- 2 worker nodes
- port mappings

## Step 3 - Create The Cluster

```bash
bash setup/01-cluster-setup/create-cluster.sh
```

Wait until:
- nodes are created
- all nodes become `Ready`

## Step 4 - Verify The Cluster

```bash
bash setup/01-cluster-setup/verify-cluster.sh
```

## Step 5 - Explore It Yourself

```bash
kubectl get nodes -o wide
kubectl get pods -A
kubectl cluster-info
kubectl config get-contexts
```

## Step 6 - Continue The Learning Path

```bash
bash setup/02-namespaces/apply-namespaces.sh
```

Or first read:

- [02-namespaces/README.md](/D:/Generative%20AI%20Portfolio%20Projects/kubernetes_architure/setup/02-namespaces/README.md)
