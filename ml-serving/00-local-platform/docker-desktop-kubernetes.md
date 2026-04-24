# Docker Desktop Kubernetes Setup
#
# This file exists as context, not as the primary path for this repository.
# The main repository flow uses the multi-node `kind` cluster created in
# `setup/01-cluster-setup/`. Docker Desktop's built-in Kubernetes is useful to
# understand as a local option, but it is not the preferred learning path here.
#
# Hardware context:
#   - 16 GB system RAM
#   - RTX 2060 with 6 GB VRAM
#   - Docker Desktop already installed
#
# Practical local sizing:
#   - Keep KServe Standard mode, not Knative, for the first pass.
#   - Standard mode avoids the extra Knative/Istio stack and creates ordinary
#     Kubernetes Deployments, Services, Ingress/Gateway, and HPAs.
#   - For this small sklearn model, GPU is not useful. The RTX 2060 matters
#     later for PyTorch/Hugging Face GPU inference, not for this wine example.

## When To Use This

Use Docker Desktop Kubernetes only if you want to compare a single-node local
cluster with the `kind` cluster from the main setup path.

## Start Kubernetes In Docker Desktop

1. Open Docker Desktop.
2. Go to the Kubernetes view.
3. Create or enable the local Kubernetes cluster.
4. Wait until Docker Desktop shows Kubernetes as running.

## Verify From A Unix Shell

```bash
# kubectl talks to the Kubernetes API server.
# If this command works, your shell has a kubeconfig context pointing at the
# Docker Desktop cluster.
kubectl config current-context

# Expected local context is usually:
#   docker-desktop
#
# If you see another context, switch deliberately:
kubectl config use-context docker-desktop

# Nodes are the machines where pods run.
# Docker Desktop gives you a local single-node cluster, which is enough to learn
# control-plane behavior, manifests, CRDs, Services, and autoscaling objects.
kubectl get nodes -o wide

# Namespaces are isolation boundaries.
# A fresh local cluster normally has kube-system, kube-public, kube-node-lease,
# and default.
kubectl get namespaces
```

## Enterprise Translation

```text
Local Docker Desktop cluster  ->  EKS / AKS / GKE / OpenShift cluster
kubectl context               ->  kubeconfig + IAM/OIDC identity
local node                    ->  cloud VM node / node pool / managed node group
PVC local storage             ->  S3/GCS/Azure Blob/MLflow model registry
KServe InferenceService       ->  same object in local and production
```
