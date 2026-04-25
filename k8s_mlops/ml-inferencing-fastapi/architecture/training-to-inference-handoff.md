# Training-to-Inference Handoff Guide

## What is this?

This document describes the exact sequence of events that connects the training
side of the MLOps platform to the inference side. It answers one concrete
question: once a manager has set `champion` in MLflow, what must happen before a
FastAPI pod can serve that model to real traffic?

The handoff is not automatic. It is a deliberate sequence involving MLflow,
CI/CD automation (or manual release steps), Kubernetes configuration, a
container rollout, and a readiness gate. This document maps each step and
explains why it cannot be skipped.

## Why does this exist?

A common beginner mistake is to point FastAPI directly at the MLflow alias so it
loads "whatever champion is right now." That design has three serious production
problems:

1. **Uncontrolled updates** — if a manager moves `champion` from version 1 to
   version 2, all existing pods immediately load the new model on their next
   request or restart. There is no controlled rollout, no smoke test, and no
   traffic gate.

2. **No auditability** — you cannot answer the question "which model version was
   serving traffic at 14:03 last Thursday?" because the alias is mutable and
   pods may have loaded different versions depending on when they last restarted.

3. **No rollback lever** — if version 2 degrades accuracy, moving `champion`
   back does not reliably restore version 1 to all pods. You would need to force-
   restart them and hope the alias moved before each pod's next reload.

The enterprise solution is to resolve the alias once at release time and then
deploy the resolved immutable version number. Kubernetes then controls the
rollout, and old pods serve version 1 until new pods prove themselves ready.

## ASCII concept diagram — the full handoff

```
                              TRAINING SIDE
                              ─────────────
Training pipeline
  └── Optuna hyperparameter search
  └── Best model registered as wine-quality-classifier
  └── Alias: candidate
  └── Tag: review_status=pending_human_review
            │
            │  Human review: metrics, artifacts, schema, lineage
            ▼
Manager promotes candidate to wine-quality-classifier-prod
  └── Alias: champion  →  models:/wine-quality-classifier-prod@champion
  └── Tag: review_status=approved
            │
            │  *** HANDOFF BOUNDARY ***
            │
            ▼
                             RELEASE BRIDGE
                             ─────────────
Step 1 — Resolve alias to immutable version
  resolve-approved-model-reference_1.sh
  └── Calls MLflow API: GET alias champion
  └── Returns: version=1
  └── Writes: MODEL_VERSION=1
              MODEL_URI=models:/wine-quality-classifier-prod/1

Step 2 — Write resolved reference into Kubernetes config
  render-inference-config_2.sh
  └── Patches 02-inference-configmap.yaml with MODEL_URI and MODEL_VERSION

Step 3 — Apply config and roll out new pods
  rollout-approved-model_3.sh
  └── kubectl apply -f 02-inference-configmap.yaml
  └── kubectl rollout restart deployment/wine-quality-inference-api
  └── Rolling update: new pod starts, old pod kept alive until new is ready
            │
            ▼
                             INFERENCE SIDE
                             ─────────────
New FastAPI pod starts
  └── Pydantic Settings reads MODEL_URI from environment
  └── ModelLoader calls mlflow.pyfunc.load_model(model_uri)
  └── Model loaded into memory
  └── model_loaded flag = True
            │
            │  Kubernetes readiness probe: GET /health/ready
            ▼
/health/ready returns HTTP 200
  └── Pod joins Service endpoints
  └── Kubernetes removes old pod from endpoints
  └── Traffic flows to new pod serving models:/wine-quality-classifier-prod/1

Smoke test (optional but recommended)
  test-prediction_4.sh
  └── Sends one known sample to /predict
  └── Verifies response schema and label

                              MONITORING
                              ──────────
Inference pod logs: served_model_uri, model_version, latency, errors
```

Vocabulary used above:

`alias` means a mutable named pointer in the MLflow Model Registry. The alias
`champion` can be moved from version 1 to version 2 by a manager. The alias
itself is not immutable — only the version number it resolves to at a specific
moment is immutable.

`immutable version` means a specific registered model version number such as `1`
or `2`. Once created, its artifact content never changes.

`rolling update` means Kubernetes starts new pods with the updated configuration
before removing old pods. Traffic stays live throughout the update because the
old pods keep running until new pods pass their readiness probes.

`readiness probe` means Kubernetes periodically checks whether a pod is ready
to serve traffic. For ML inference, readiness must depend on the model artifact
being successfully loaded into memory, not just the process starting.

## The critical rule FastAPI must follow

FastAPI receives an approved model reference from the platform. It does not
choose, discover, or resolve a model on its own.

```
WRONG pattern (never do this):

  # Inside FastAPI startup:
  client = MlflowClient()
  version = client.get_model_version_by_alias("wine-quality-classifier-prod", "champion")
  model = mlflow.pyfunc.load_model(f"models:/wine-quality-classifier-prod/{version.version}")

WHY it is wrong:
  - FastAPI becomes a decision maker instead of an executor.
  - If champion changes while pods are running, different pods may load
    different model versions in the same deployment.
  - Rollback is broken: moving the alias does not reload already-running pods.
  - Audit trail breaks: you cannot reconstruct which version served at 14:03.


CORRECT pattern:

  # CI/CD resolves the alias once and patches the Kubernetes ConfigMap:
  MODEL_URI=models:/wine-quality-classifier-prod/1

  # Inside FastAPI startup — reads what the platform decided:
  model = mlflow.pyfunc.load_model(settings.model_uri)

WHY it is correct:
  - FastAPI executes the platform's decision. It does not make its own.
  - All pods in the same deployment load exactly the same version.
  - Rollback is explicit: redeploy with the previous MODEL_URI.
  - Audit trail is preserved: the ConfigMap at deploy time records which version.
```

## What changes when champion moves tomorrow

Suppose version 1 is `champion` today and version 2 is promoted to `champion`
tomorrow.

Without the release bridge:
- Running pods still serve version 1 (they already loaded it at startup).
- No new pods are started because the deployment spec did not change.
- Traffic silently stays on version 1 forever unless pods restart for other
  reasons (node maintenance, OOM, crash, manual restart).
- A forced restart would suddenly switch all pods to version 2 with no
  controlled rollout and no smoke test.

With the release bridge:
- The bridge detects or is triggered by the alias change.
- It resolves the new alias to version 2.
- It updates the ConfigMap with `MODEL_URI=models:/wine-quality-classifier-prod/2`.
- It triggers a rolling restart of the deployment.
- New pods load version 2. Readiness gates traffic. Old pods drain.
- If version 2 fails readiness, the rollout stops and version 1 continues
  serving. Kubernetes automatically pauses the rollout on probe failures.

## How this maps to enterprise systems

| Local lab step | Enterprise equivalent | Enterprise tool examples |
|---|---|---|
| Manager clicks MLflow UI to set `champion` | Approval portal, governance workflow, model risk committee sign-off | Internal platform portal, MLflow with SSO, Weights & Biases model management |
| `resolve-approved-model-reference_1.sh` resolves alias | CI/CD pipeline step that calls model registry API | GitHub Actions, GitLab CI, Jenkins, Argo Workflows |
| `render-inference-config_2.sh` patches ConfigMap YAML | Kustomize overlay, Helm values update, or ArgoCD ApplicationSet patch | Kustomize, Helm, Terraform, CDK for Kubernetes |
| `kubectl rollout restart` triggers rolling update | GitOps merge to environment branch triggers Argo CD or Flux sync | Argo CD, Flux, Spinnaker, AWS CodeDeploy |
| Readiness probe gates traffic | Same pattern, exactly — readiness probes are not a local shortcut | Identical in EKS, GKE, AKS, OpenShift |
| `test-prediction_4.sh` smoke test | Automated test job in CI, canary analysis, progressive delivery gate | Argo Rollouts, Flagger, Keptn, custom Kubernetes Job |
| Manual rollback via re-deploy | GitOps: revert the environment branch commit | ArgoCD sync to previous Git SHA, Helm rollback, Argo Rollouts rollback |
