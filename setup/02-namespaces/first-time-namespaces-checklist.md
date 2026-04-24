# First-Time Namespaces Checklist

This is the shortest possible “tell me exactly what to do” version for the namespace stage.

## What A Namespace Is In One Line

A namespace is a logical Kubernetes boundary inside one cluster that helps group resources and apply policies.

## What It Is Not

It is not:
- a separate cluster
- a VM
- a container
- a Linux process

## Step 1 - Read The Namespace YAML

```bash
less setup/02-namespaces/namespaces.yaml
```

Focus on:
- namespace names
- labels
- annotations

## Step 2 - Apply The Namespaces

```bash
bash setup/02-namespaces/apply-namespaces.sh
```

## Step 3 - Inspect What Was Created

```bash
kubectl get namespaces
kubectl get namespaces --show-labels
kubectl describe namespace applications
```

## Step 4 - Learn The `default` Namespace Trap

Remember:

```text
kubectl get pods
```

does not mean “all pods.”

It usually means “pods in the current namespace.”

## Step 5 - Continue The Learning Path

Next:

- [03-pods/README.md](/D:/Generative%20AI%20Portfolio%20Projects/kubernetes_architure/setup/03-pods/README.md)
