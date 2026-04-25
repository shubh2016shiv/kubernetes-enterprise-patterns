# Release Bridge

## What is this?

The release bridge is the automation layer that connects the MLflow model
approval workflow to Kubernetes pod deployment. It answers the concrete question:
"a manager just moved `champion` to version 2 in MLflow — what must run before
Kubernetes pods serve version 2?"

The bridge is three scripts that run in sequence:

```
Step 1: resolve-approved-model-reference_1.sh
  Calls MLflow API → finds version number for @champion alias
  Writes: resolved_model_reference.env

Step 2: render-inference-config_2.sh
  Reads resolved_model_reference.env
  Updates: kubernetes-manifests/02-inference-configmap.yaml (MODEL_URI, MODEL_VERSION)
  Updates: kubernetes-manifests/05-inference-deployment.yaml (labels, checksum)

Step 3: rollout-approved-model_3.sh
  Applies ConfigMap and Deployment to the cluster
  Waits for rolling update to complete
  Runs smoke test
  Rolls back automatically if rollout or smoke test fails
```

## Commands

Run the full bridge from WSL2:

```bash
# Prerequisites: MLflow server running, champion alias set in MLflow registry.

# Step 1 — Resolve the alias
cd /mnt/d/Generative\ AI\ Portfolio\ Projects/kubernetes_architure/k8s_mlops/ml-inferencing-fastapi/release-bridge
bash resolve-approved-model-reference_1.sh

# Step 2 — Render Kubernetes config with the resolved version
bash render-inference-config_2.sh

# Step 3 — Apply config and roll out
bash rollout-approved-model_3.sh
```

What you should see after Step 1:

```text
✓ MLflow server reachable (HTTP 200).
✓ Alias 'champion' resolves to version: 1
  Immutable model URI: models:/wine-quality-classifier-prod/1
✓ Written to: resolved_model_reference.env
```

What you should see after Step 3:

```text
✓ Rolling update complete.
  All pods are now serving from: models:/wine-quality-classifier-prod/1
✓ Smoke test passed.
  Release complete.
```

Override environment variables for non-default settings:

```bash
MLFLOW_TRACKING_URI=http://127.0.0.1:5000 \
MODEL_REGISTRY_NAME=wine-quality-classifier-prod \
MODEL_ALIAS=champion \
bash resolve-approved-model-reference_1.sh
```

## Why three scripts instead of one?

Each script has a single responsibility and a clear output. This structure
maps directly to three CI/CD pipeline stages:

| Script | CI/CD stage | Can be run independently |
|---|---|---|
| `resolve-approved-model-reference_1.sh` | Registry resolution | Yes — useful for validation without deploying |
| `render-inference-config_2.sh` | Config rendering | Yes — dry run before applying |
| `rollout-approved-model_3.sh` | Cluster deployment | Requires the env file from step 1 |

In enterprise CI/CD, each script would be one pipeline step with its own
approval gate, retry policy, and audit log. Separating them makes it possible
to require human approval between the resolution step and the deployment step.
