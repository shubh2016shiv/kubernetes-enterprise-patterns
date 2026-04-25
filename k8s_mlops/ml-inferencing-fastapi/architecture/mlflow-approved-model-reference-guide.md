# MLflow Approved Model Reference Guide

## What is this?

This guide explains the difference between the three kinds of model references
that appear in this platform, when each is appropriate, and why the inference
deployment must use one specific form — the immutable version URI.

The three forms are:

```
Form 1 — Moving alias (human-friendly approval pointer):
  models:/wine-quality-classifier-prod@champion

Form 2 — Immutable version (deployment-safe pinned reference):
  models:/wine-quality-classifier-prod/1

Form 3 — Local artifact path (local training output, not for Kubernetes):
  /mnt/d/.../artifacts/wine_quality_classifier/v_2026-04-25_001/
```

## Why does this exist?

Newcomers to MLflow often use `@champion` directly in their serving code because
it is readable and always points to the approved version. The problem is that
`@champion` is mutable: a manager can move it to a different version at any time
from the MLflow UI. That mutability is exactly what makes it valuable for human
governance — but it is also exactly what makes it unsafe to use as a serving
runtime reference.

This guide gives the learner a precise mental model for which form belongs where.

## The three reference forms explained

### Form 1 — Moving alias

```
models:/wine-quality-classifier-prod@champion
```

This URI tells MLflow: "give me the version that the `champion` alias currently
points to." The answer changes whenever a manager reassigns the alias.

**Appropriate uses:**
- Human communication: "the current approved version is champion."
- MLflow UI navigation.
- CI/CD alias-resolution step: the release bridge calls the MLflow API once with
  this URI to find out which version number `champion` resolves to at that exact
  moment.

**Never appropriate for:**
- FastAPI startup model loading.
- Kubernetes deployment environment variables.
- Any runtime path where the answer might change without a controlled rollout.

### Form 2 — Immutable version URI

```
models:/wine-quality-classifier-prod/1
```

This URI tells MLflow: "give me version 1 of this registered model." Version 1
exists in MLflow's artifact store as a fixed set of files. It will never change.
A manager can promote newer versions, but version 1 remains version 1 forever.

**Appropriate uses:**
- `MODEL_URI` environment variable in the Kubernetes ConfigMap.
- FastAPI startup model loading.
- Audit records: "at 14:03 on 2026-04-25, pods were serving version 1."
- Rollback instructions: "redeploy with MODEL_URI=models:/wine-quality-classifier-prod/1."

**When is it set?**
The release bridge resolves the `@champion` alias once and writes this URI into
the ConfigMap before the rolling restart. After that, every new pod that starts
reads this exact value from its environment and loads this exact version.

### Form 3 — Local artifact path

```
/mnt/d/.../artifacts/wine_quality_classifier/v_2026-04-25_001/
```

This is the versioned local directory written by the training pipeline to the
learner's laptop. It exists for local testing and debugging before MLflow is
involved. It is not a valid reference inside a Kubernetes pod because:

- The path does not exist on a Kubernetes worker node.
- Even in local kind clusters, pods do not have access to WSL2 filesystem paths.
- In production, the model artifact is stored in object storage (S3, GCS, Azure
  Blob) and served through MLflow's artifact proxy endpoint.

**Never use a local artifact path as MODEL_URI in a Kubernetes manifest.**

## How the alias resolves to a version

When the MLflow Python client receives `models:/wine-quality-classifier-prod@champion`,
it calls the MLflow Tracking Server REST API:

```
GET /api/2.0/mlflow/registered-models/alias
  ?name=wine-quality-classifier-prod
  &alias=champion
```

The server responds with the model version metadata, including the version number.
The client then constructs the artifact download URI for that version.

The release bridge performs this resolution explicitly and writes the result into
the deployment configuration. FastAPI never calls this API at runtime.

## ASCII reference resolution diagram

```
Manager sets champion alias in MLflow UI
  └── wine-quality-classifier-prod
        version 1 ← champion (alias moves to version 2 tomorrow)
        version 2 ← (promoted today)

                    Release Bridge runs
                    ────────────────────
                    Resolves @champion → version 2
                    Writes to ConfigMap:
                      MODEL_VERSION=2
                      MODEL_URI=models:/wine-quality-classifier-prod/2

                    kubectl rollout restart deployment
                    ────────────────────────────────────
New pod starts
  └── Reads MODEL_URI=models:/wine-quality-classifier-prod/2 from env
  └── mlflow.pyfunc.load_model("models:/wine-quality-classifier-prod/2")
  └── MLflow client calls GET /api/2.0/mlflow/model-versions/get-download-uri
  └── Downloads artifact from MLflow artifact store
  └── Deserializes sklearn Pipeline from model.pkl
  └── model_loaded = True
  └── /health/ready returns HTTP 200
  └── Traffic shifts to new pod
```

## Environment variable contract between CI/CD and FastAPI

These are the exact environment variables the release bridge sets in the
Kubernetes ConfigMap and the FastAPI app reads at startup:

| Variable | Set by | Example value | Purpose |
|---|---|---|---|
| `MODEL_URI` | CI/CD release bridge | `models:/wine-quality-classifier-prod/1` | Immutable serving reference, loaded at startup |
| `MODEL_REGISTRY_NAME` | Release bridge or static config | `wine-quality-classifier-prod` | Logged in health checks and prediction responses |
| `MODEL_VERSION` | Release bridge | `1` | Human-readable version for logging, metrics, and audit |
| `MLFLOW_TRACKING_URI` | Platform ConfigMap | `http://mlflow-service.ml-platform.svc.cluster.local:5000` | MLflow server the pod uses to download the artifact |

### Why MODEL_URI and MODEL_VERSION both exist

`MODEL_URI` is the full MLflow model URI that Python's `mlflow.pyfunc.load_model`
accepts directly. It contains the registry name and version in one string.

`MODEL_VERSION` is a standalone human-readable string used in logs, health check
responses, and prediction response headers. It makes dashboards and audit records
readable without parsing the `MODEL_URI` string.

Both are set by the release bridge at the same time from the same alias
resolution result. They are always consistent.

## How MLflow resolves version URIs inside a Kubernetes pod

Inside the Kubernetes pod, the MLflow Python client is installed in the container
image. When `mlflow.pyfunc.load_model("models:/wine-quality-classifier-prod/1")`
is called:

1. The client reads `MLFLOW_TRACKING_URI` from the environment.
2. It connects to the MLflow Tracking Server at that URI.
3. It requests the download URI for the registered model artifact.
4. It downloads the artifact files from the artifact store (local disk in the
   lab; object storage in production).
5. It deserializes the sklearn Pipeline and returns a pyfunc model wrapper.

This means two things must be true before a pod can load a model:
- `MLFLOW_TRACKING_URI` must point to a reachable MLflow server.
- The MLflow server must have access to the artifact store where the model files
  are stored.

In the local lab, both the MLflow server and its artifact store run on the
learner's WSL2 machine. The pod must reach the MLflow server over the network
(usually `localhost` or a NodePort service if the server is inside the cluster,
or the WSL2 host IP if the server is running outside the cluster).

## Enterprise translation

| Local lab | Enterprise | Reason |
|---|---|---|
| MLflow server at `http://127.0.0.1:5000` on learner's laptop | MLflow server at `https://mlflow.internal.company.com` behind TLS and SSO | Production MLflow needs authentication, TLS, and high availability |
| Artifacts stored at local `./mlflow-tracking/artifacts/` | Artifacts stored in S3, GCS, or Azure Blob Storage, proxied through MLflow `--serve-artifacts` | Object storage is durable, access-controlled, and globally reachable from any cluster node |
| Manual alias resolution via shell script | Automated alias resolution in CI/CD pipeline triggered by MLflow webhook or scheduled check | Enterprise platforms need audit logs, idempotency, and approval gates before each resolution |
| ConfigMap patched by hand | ConfigMap patched by Kustomize overlay, Helm chart values, or Argo CD ApplicationSet | GitOps means Git is the record of what was deployed, not a manually edited YAML |
| `kubectl rollout restart` run from developer terminal | `kubectl rollout restart` or equivalent triggered by Argo CD sync, Spinnaker pipeline, or GitHub Actions | Controlled deployments need pipeline gates, approval steps, and audit trails |
