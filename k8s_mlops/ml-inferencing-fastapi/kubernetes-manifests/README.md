# Kubernetes Manifests — Wine Quality Inference Stack

## What is this?

This directory contains the Kubernetes manifests that deploy the wine quality
inference API into the `ml-inference` namespace. These manifests define:

- The namespace that isolates inference workloads.
- The ConfigMap that carries the approved model reference and runtime config.
- The ServiceAccount that gives the inference API a dedicated Kubernetes identity.
- The Secret placeholder for MLflow credentials (local lab only).
- The Deployment that runs the FastAPI inference pods.
- The Service that provides a stable cluster-internal endpoint.
- The HorizontalPodAutoscaler that scales pods based on CPU utilization.

The scripts in this directory apply the manifests in order and verify the
deployed state.

## Why cluster setup files are not copied here

This module intentionally does not copy `setup/01-cluster-setup` manifests or
scripts into `kubernetes-manifests/`. Cluster creation, Docker Desktop setup,
node lifecycle, and `kubectl` installation are platform lifecycle concerns.
Inference owns only the resources needed to serve an approved model.

Enterprise translation: in a real organization, the machine learning inference
team usually deploys into an existing platform cluster. A platform engineering
team owns the cluster baseline, node pools, networking, admission policies, and
shared controllers. Copying those files into every application module creates
configuration drift, which means two folders claim to define the same platform
but slowly become different.

## Apply order

Manifests are numbered to indicate their dependency order. Apply them in order,
or use `apply-inference-stack_3.sh` after `check-cluster-prerequisites_2.sh`.

| File | Kind | What it creates |
|---|---|---|
| `01-namespace.yaml` | Namespace | `ml-inference` namespace with Pod Security Admission |
| `02-inference-configmap.yaml` | ConfigMap | MODEL_URI, MODEL_VERSION, MLFLOW_TRACKING_URI, app config |
| `03-inference-serviceaccount.yaml` | ServiceAccount | Dedicated workload identity for the inference API |
| `04-inference-secret-placeholder.yaml` | Secret | Credential slot for MLflow auth (local placeholders) |
| `05-inference-deployment.yaml` | Deployment | 2-replica rolling-update inference API |
| `06-inference-service.yaml` | Service | ClusterIP endpoint at port 8080 |
| `07-hpa.yaml` | HorizontalPodAutoscaler | Scale 2-4 replicas at 70% CPU |
| `08-inference-cleanup-targets.yaml` | List | Delete targets for resetting the inference stack |

## Commands

**One-command local deployment path:**
```bash
cd /mnt/d/Generative\ AI\ Portfolio\ Projects/kubernetes_architure/k8s_mlops/ml-inferencing-fastapi/kubernetes-manifests
bash deploy-local-inference-stack_1.sh
```

What you should see:

```text
LOCAL_KIND_CLUSTER_NAME: local-enterprise-dev
Running: setup/00-prerequisites/check-prerequisites.sh
Running: setup/01-cluster-setup/create-cluster.sh
Running: setup/01-cluster-setup/verify-cluster.sh
Running: kubernetes-manifests/check-cluster-prerequisites_2.sh
Running: kubernetes-manifests/apply-inference-stack_3.sh
```

The important variable is `LOCAL_KIND_CLUSTER_NAME`. It defaults to
`local-enterprise-dev`, which matches the setup module and the image-loading
commands. If that cluster already exists with the same name, the setup
`create-cluster.sh` script is idempotent and reuses it instead of creating a
second cluster. Do not change this variable unless you also update the canonical
setup cluster name and kind cluster config.

**Manual platform setup path, only if you want to run the phases yourself:**

```bash
cd /mnt/d/Generative\ AI\ Portfolio\ Projects/kubernetes_architure/setup/00-prerequisites
bash check-prerequisites.sh

cd /mnt/d/Generative\ AI\ Portfolio\ Projects/kubernetes_architure/setup/01-cluster-setup
bash create-cluster.sh
bash verify-cluster.sh
```

**Check only whether the cluster is ready before applying inference manifests:**
```bash
cd /mnt/d/Generative\ AI\ Portfolio\ Projects/kubernetes_architure/k8s_mlops/ml-inferencing-fastapi/kubernetes-manifests
bash check-cluster-prerequisites_2.sh
```

**Build and load the container image (WSL2):**
```bash
cd ../runtime-image
docker build -t wine-quality-inference-api:1.0.0 .
kind load docker-image wine-quality-inference-api:1.0.0 --name local-enterprise-dev
```

**Run the release bridge first (to populate MODEL_URI in the ConfigMap):**
```bash
cd ../release-bridge
./resolve-approved-model-reference_1.sh
./render-inference-config_2.sh
```

**Apply the full stack:**
```bash
cd ../kubernetes-manifests
bash apply-inference-stack_3.sh
```

**Verify the stack is healthy:**
```bash
bash verify-inference-stack_5.sh
```

**Run a smoke test:**
```bash
bash test-prediction_4.sh
```

**Rollback to the previous deployment:**
```bash
kubectl rollout undo deployment/wine-quality-inference-api -n ml-inference
```

**Destroy only the inference stack and start fresh:**

This is destructive. It deletes the `ml-inference` namespace and the inference
resources inside it. It does not delete the kind cluster, MLflow model artifacts,
source files, or local Docker images by default.

The `CONFIRM_DELETE_INFERENCE_STACK=ml-inference` part is a Bash environment
variable set only for this one command. It is the safety confirmation. The
script refuses to delete unless that value exactly matches the namespace it will
remove.

```bash
cd /mnt/d/Generative\ AI\ Portfolio\ Projects/kubernetes_architure/k8s_mlops/ml-inferencing-fastapi/kubernetes-manifests
CONFIRM_DELETE_INFERENCE_STACK=ml-inference bash destroy-inference-stack_6.sh
```

What you should see:

```text
Stage 1.0: Destructive cleanup preflight
Stage 2.0: Deleting inference Kubernetes resources
Inference Kubernetes resources deleted.
Cluster deletion skipped.
Local Docker image deletion skipped.
```

**Optional: also delete the local kind cluster**

Use this only when you want to remove the whole local Kubernetes platform and
all cluster-local volumes. This affects more than inference.

```bash
DELETE_KIND_CLUSTER=true \
CONFIRM_DELETE_KIND_CLUSTER=local-enterprise-dev \
CONFIRM_DELETE_INFERENCE_STACK=ml-inference \
bash destroy-inference-stack_6.sh
```

**Optional: also delete the local inference container image**

```bash
DELETE_LOCAL_IMAGE=true \
CONFIRM_DELETE_INFERENCE_STACK=ml-inference \
bash destroy-inference-stack_6.sh
```
