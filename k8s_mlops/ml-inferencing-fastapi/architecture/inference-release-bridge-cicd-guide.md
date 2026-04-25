# Inference Release Bridge — CI/CD and GitOps Guide

## What is this?

This guide describes the release bridge: the automation layer that sits between
a manager approving a model in MLflow and the new model actually serving traffic
in Kubernetes. Without this bridge, the two sides of the platform never talk to
each other.

The bridge answers: given that `champion` now points to version 2, how do
Kubernetes pods learn that and roll out cleanly?

## Why does this exist?

The key gap in naive MLOps implementations is assuming that "model approved in
MLflow" automatically means "model serving in production." It does not. MLflow
and Kubernetes are independent systems. MLflow knows about model versions and
aliases. Kubernetes knows about container images, ConfigMaps, and Deployments.
Neither one watches the other.

The release bridge is the piece of automation that:
1. Reads the MLflow registry state (which version is approved).
2. Translates that into Kubernetes deployment configuration.
3. Triggers a controlled, observable, rollback-capable rollout.

## ASCII concept diagram — where the bridge sits

```
 APPROVAL SIDE (MLflow)            BRIDGE               DEPLOYMENT SIDE (Kubernetes)
 ──────────────────────    ─────────────────────────    ─────────────────────────────

 Manager clicks:           Step 1:                      Step 4:
 Set champion = v2         resolve-approved-            kubectl apply configmap
                           model-reference.sh           (MODEL_URI pinned to v2)
      │                         │                              │
      │         ┌───────────────┘                             │
      │         │                                             │
      │         │  Calls MLflow REST API                      ▼
      │         │  GET /registered-models/alias               Step 5:
      │         │  ?name=wine-quality-classifier-prod         kubectl rollout restart
      │         │  &alias=champion                            deployment/wine-quality-
      │         │  → version=2                                inference-api
      │         │                                             │
      │         ▼                                             │
      │    Step 2:                                            ▼
      │    render-inference-                         New pod starts,
      │    config.sh                                 reads MODEL_URI=
      │    Patches ConfigMap YAML:                   models:/wine-quality-
      │    MODEL_URI=                                classifier-prod/2
      │    models:/wine-quality-                     │
      │    classifier-prod/2                         │
      │    MODEL_VERSION=2                           ▼
      │                                    mlflow.pyfunc.load_model()
      │         ▼                                    │
      │    Step 3:                                   ▼
      │    rollout-approved-                /health/ready → HTTP 200
      │    model.sh                                  │
      │    (calls steps 4 and 5)                     ▼
      │                                    Pod joins Service endpoints
      └────────────────────────────────→   Old pod drains and stops
                                           Traffic now on version 2
```

## The three bridge scripts in this module

### Script 1: `resolve-approved-model-reference_1.sh`

Purpose: Call the MLflow Tracking Server REST API to find out which version
number the `champion` alias currently points to. Write the result as environment
variables that subsequent scripts can source.

What it does:
```bash
# Calls: GET http://MLFLOW_TRACKING_URI/api/2.0/mlflow/registered-models/alias
# With:  name=wine-quality-classifier-prod  alias=champion
# Reads: model_version.version from the JSON response
# Writes: resolved_model_reference.env containing:
#   MODEL_REGISTRY_NAME=wine-quality-classifier-prod
#   MODEL_VERSION=2
#   MODEL_URI=models:/wine-quality-classifier-prod/2
```

Enterprise equivalent: A CI/CD pipeline step that calls the model registry API
and exports the result as pipeline variables. In GitHub Actions, this would be
a step that sets `$GITHUB_OUTPUT`. In Jenkins, it would set environment variables
for downstream stages. In Argo Workflows, it would be an output parameter.

### Script 2: `render-inference-config_2.sh`

Purpose: Read the resolved model reference from `resolved_model_reference.env`
and patch the Kubernetes ConfigMap YAML file so the next `kubectl apply` picks
up the correct `MODEL_URI` and `MODEL_VERSION`.

What it does:
```bash
# Sources: resolved_model_reference.env
# Reads:   MODEL_VERSION, MODEL_URI
# Updates: kubernetes-manifests/02-inference-configmap.yaml
#   MODEL_VERSION: "2"
#   MODEL_URI: "models:/wine-quality-classifier-prod/2"
```

Enterprise equivalent: Kustomize patch generation, Helm value overrides, or
a Jsonnet/CUE config renderer in a GitOps pipeline. The key concept is that
the Kubernetes configuration is generated or patched from the resolved registry
state rather than manually edited.

### Script 3: `rollout-approved-model_3.sh`

Purpose: Apply the updated ConfigMap and trigger a rolling restart of the
inference deployment. Wait for the rollout to complete. Run the smoke test.

What it does:
```bash
# 1. kubectl apply -f kubernetes-manifests/02-inference-configmap.yaml
# 2. kubectl rollout restart deployment/wine-quality-inference-api -n ml-inference
# 3. kubectl rollout status deployment/wine-quality-inference-api -n ml-inference --timeout=5m
# 4. (if rollout succeeds) run test-prediction_4.sh smoke test
# 5. (if rollout fails)    kubectl rollout undo and report failure
```

Enterprise equivalent: The apply + rollout restart + smoke test pattern is
standard across Kubernetes deployment systems. Argo Rollouts adds canary and
blue/green strategies. Flagger adds metric-based progressive delivery. The core
mechanics — apply, restart, gate on readiness, test, or undo — remain the same.

## The ConfigMap is not an auto-reload mechanism

A common misconception: "if I update the ConfigMap, running pods will reload the
model." This is wrong for pods that read ConfigMaps via `envFrom` (environment
variables). Environment variables are set once when the pod starts. Changing the
ConfigMap does not change the environment variables of running pods.

What the bridge must do after updating the ConfigMap:
```
Option A (used in this lab): kubectl rollout restart
  - Forces Kubernetes to terminate old pods and create new pods.
  - New pods read the updated environment variables.
  - Old pods keep serving until new pods are ready (zero-downtime rolling update).

Option B (enterprise alternative): Change the Deployment spec directly.
  - Patch the deployment with a new annotation hash of the ConfigMap content.
  - Kubernetes detects the spec change and triggers a rolling update automatically.
  - This is the pattern used by Helm when it manages ConfigMaps through chart values.

Option C (enterprise alternative): Use a sidecar config reloader.
  - Tools like `stakater/Reloader` watch for ConfigMap changes and trigger pod
    restarts automatically when mounted config changes.
  - Convenient for non-critical config, risky for model changes that need
    controlled rollouts and smoke tests.
```

For model serving, Option A is preferred in this lab because it is explicit,
observable, and safe.

## What rollback looks like

If the new model version fails readiness probes:

```
Automatic Kubernetes behavior:
  - The rollout stops adding new pods (maxUnavailable: 0 prevents removing old pods).
  - Old pods continue serving because the readiness gate blocked the new pod from
    entering the Service endpoint set.
  - The rollout is stuck in progress (not failed, not complete).
  - kubectl rollout status will show the rollout waiting.

Manual rollback:
  kubectl rollout undo deployment/wine-quality-inference-api -n ml-inference
  This restores the previous Deployment spec (and therefore the previous MODEL_URI).

Full rollback via bridge:
  1. Update the ConfigMap back to the previous MODEL_VERSION and MODEL_URI.
  2. Run: kubectl apply -f kubernetes-manifests/02-inference-configmap.yaml
  3. Run: kubectl rollout restart deployment/wine-quality-inference-api -n ml-inference
  This is the preferred path because it keeps the ConfigMap and Deployment in sync.
```

## How this bridge maps to GitHub Actions (enterprise example)

In a real GitHub Actions workflow, the bridge steps would look like:

```yaml
# .github/workflows/inference-release.yaml (conceptual, not in this lab)

on:
  workflow_dispatch:
    inputs:
      environment:
        description: 'Target environment (staging or production)'
        required: true

jobs:
  release-inference:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Resolve approved model reference
        id: resolve
        run: |
          # Calls MLflow API, extracts version number
          bash release-bridge/resolve-approved-model-reference_1.sh
          source resolved_model_reference.env
          echo "model_version=${MODEL_VERSION}" >> $GITHUB_OUTPUT
          echo "model_uri=${MODEL_URI}"         >> $GITHUB_OUTPUT

      - name: Render Kubernetes config
        run: |
          source resolved_model_reference.env
          bash release-bridge/render-inference-config_2.sh

      - name: Commit updated config
        # In GitOps, updated config is committed to the env branch.
        # Argo CD or Flux then detects the commit and applies it.
        run: |
          git config user.name "release-bot"
          git commit -am "release: inference model v${{ steps.resolve.outputs.model_version }}"
          git push origin main

      # With ArgoCD GitOps: Argo CD detects the config commit and syncs the cluster.
      # With direct deploy: continue with kubectl apply and rollout restart.

      - name: Smoke test
        run: bash kubernetes-manifests/test-prediction_4.sh
```

## Rollout strategy decision: why RollingUpdate with maxUnavailable: 0

The inference deployment uses:
```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxUnavailable: 0  # Never remove a ready pod before a new one is ready
    maxSurge: 1        # Allow one extra pod during the transition
```

This is the correct choice for ML inference because:

- `maxUnavailable: 0` means the old pod stays in the Service endpoint set until
  the new pod passes its readiness probe. Traffic never drops below capacity.

- `maxSurge: 1` means Kubernetes creates one new pod before removing the old one.
  This requires enough cluster capacity for N+1 pods temporarily.

- The readiness probe is set to check `/health/ready`, which returns HTTP 200
  only after the model artifact is loaded into memory. Model loading can take
  several seconds to a few minutes depending on model size. `maxUnavailable: 0`
  guarantees the old pod keeps serving during that loading window.

A `Recreate` strategy (stop all old pods, then start new pods) would cause a
gap in service. That is never acceptable for a production inference API.

## Enterprise patterns not covered in this local lab

The following patterns are the natural enterprise extensions of this bridge. They
are described here so the learner knows where this lab's approach fits in the
broader picture.

**Canary releases:** Instead of replacing all pods at once, route a small
percentage of traffic (e.g., 5%) to the new model version while the majority
still hits the old version. Monitor error rates and latency on the canary.
Promote or roll back based on observed metrics. Argo Rollouts and Flagger
implement this pattern on top of standard Kubernetes Deployments.

**Blue/green releases:** Maintain two complete Deployments (blue = current,
green = new). Switch traffic by updating the Service selector to point to the
green Deployment. Instant cutover with instant rollback by flipping the selector
back. Requires double the pod capacity during the transition.

**Shadow mode / A/B testing:** Route prediction requests to both the old model
and the new model simultaneously. Log both predictions but only return the old
model's answer to the caller. Compare offline. This is used for model quality
validation before a traffic shift.

**Progressive delivery gates:** Use metrics from Prometheus, Datadog, or
custom evaluation jobs to automatically gate a rollout. If prediction error rate
exceeds a threshold or latency degrades, Flagger or Argo Rollouts automatically
pauses or reverses the rollout without human intervention.

**Enterprise rollback comparison:**

| What we do locally | Enterprise equivalent | Notes |
|---|---|---|
| `kubectl rollout undo` | ArgoCD sync to previous Git SHA, Helm rollback, Argo Rollouts rollback | Enterprise rollback must update Git for auditability |
| Manual smoke test script | Canary analysis with Prometheus metrics, A/B test framework | Automated quality gates replace manual scripts at scale |
| Single deployment for all traffic | Blue/green, canary, shadow mode | Risk-controlled progressive delivery for high-traffic APIs |
| `maxUnavailable: 0` rolling update | Same strategy, with optional Argo Rollouts for advanced traffic splitting | The core rolling update concept is identical across platforms |
