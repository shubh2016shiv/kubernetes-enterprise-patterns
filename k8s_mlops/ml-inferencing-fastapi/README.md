# ml-inferencing-fastapi - Custom serving platform

## What is this?

This module teaches and implements the enterprise model serving side of the
MLOps platform. It picks up exactly where `ml-training` left off: a manager has
reviewed a trained model, promoted it into `wine-quality-classifier-prod`, and
assigned the `champion` alias. This module answers what must happen next before
a pod can serve that model to real traffic.

The module has three main parts:

1. **Architecture docs** (`architecture/`) — explains the handoff from MLflow
   model approval to Kubernetes pod serving, the difference between moving
   aliases and immutable version URIs, and the CI/CD release bridge concept.

2. **Inference runtime** (`runtime-image/`) — a FastAPI application that loads
   an approved MLflow model at startup and serves predictions. Structured with
   clean separation of concerns: typed settings, model registry resolver, model
   loader, prediction service, health checks, and route handlers.

3. **Kubernetes manifests and release bridge** (`kubernetes-manifests/`,
   `release-bridge/`) — manifests to deploy the API into the `ml-inference`
   namespace and scripts to resolve the MLflow alias, update the ConfigMap, and
   perform a zero-downtime rolling update.

## Why does this exist?

In a naive MLOps setup, serving code points at `@champion` directly and loads
"whatever the latest approved model is." This causes three production problems:

- **Uncontrolled updates** — if a manager reassigns `@champion` while pods are
  running, different pods may load different model versions with no rollout.
- **No auditability** — you cannot answer "which model version was serving at
  14:03 last Thursday?" because the alias is mutable and pods may have reloaded
  at different times.
- **No rollback lever** — moving `@champion` back does not reliably restore the
  previous model to all pods without a forced restart.

The enterprise solution: resolve the alias once at release time. Deploy the
resolved immutable version URI (`models:/wine-quality-classifier-prod/1`) as
configuration. Let Kubernetes control the rollout. Gate traffic with readiness
probes. Test with a smoke test. Roll back if anything fails.

## ASCII concept diagram

```
 TRAINING SIDE                     HANDOFF BOUNDARY             INFERENCE SIDE
 ─────────────                     ────────────────             ──────────────

 Training pipeline                                             FastAPI pod
 └── Optuna trials                                            ├── Reads MODEL_URI from env
 └── Best model registered                                    │   (set by CI/CD bridge)
     as wine-quality-classifier                               ├── mlflow.pyfunc.load_model()
     alias: candidate                                         ├── model loaded → ready
         │                                                    └── /predict serves requests
         │  Manager review                                            │
         ▼                                                            │
 Manager promotes to                 Release Bridge:                  │
 wine-quality-classifier-prod        Step 1: Resolve @champion alias  │
 alias: champion                     Step 2: Patch ConfigMap          │
 review_status=approved              Step 3: Rolling update           │
         │                                   │                        │
         └───────────────────────────────────┼────────────────────────┘
                                             ▼
                              Kubernetes rolling update
                              ├── New pod starts
                              ├── Loads MODEL_URI (immutable version)
                              ├── /health/ready → HTTP 200
                              ├── Joins Service endpoints
                              └── Old pod drains


  MLflow Model Registry:
  ┌───────────────────────────────────────────────┐
  │ wine-quality-classifier-prod                   │
  │   version 1  ← @champion (review_status=approved)│
  │   version 2  ← (challenger, pending review)    │
  └───────────────────────────────────────────────┘
            │
            │  Release bridge resolves @champion → version 1
            ▼
  ConfigMap:
  MODEL_URI=models:/wine-quality-classifier-prod/1  (immutable)
  MODEL_VERSION=1

  FastAPI pod:
  - Loads models:/wine-quality-classifier-prod/1 at startup
  - Serves this version for its entire lifetime
  - Does NOT watch @champion for changes
```

## Learning steps

1. Read [architecture/training-to-inference-handoff.md](architecture/training-to-inference-handoff.md)
   to understand the full sequence from approval to serving traffic.

2. Read [architecture/mlflow-approved-model-reference-guide.md](architecture/mlflow-approved-model-reference-guide.md)
   to understand why `@champion` is a human-friendly approval pointer but NOT a
   serving runtime reference.

3. Read [architecture/inference-release-bridge-cicd-guide.md](architecture/inference-release-bridge-cicd-guide.md)
   to understand the CI/CD bridge that connects MLflow approval to Kubernetes rollout.

4. Read [runtime-image/app/core/settings.py](runtime-image/app/core/settings.py)
   to see how Pydantic Settings provides a typed, validated config layer that
   eliminates scattered `os.getenv()` calls from business logic.

5. Read [runtime-image/app/model_loading/model_loader.py](runtime-image/app/model_loading/model_loader.py)
   to understand how the model is loaded once at startup and why readiness must
   depend on this completing successfully.

6. Read [runtime-image/app/health/health_checks.py](runtime-image/app/health/health_checks.py)
   to understand why liveness and readiness are separate and why liveness must
   never fail just because a model is still loading.

7. Read [runtime-image/app/main.py](runtime-image/app/main.py) to see the ASGI
   lifespan pattern that loads the model before the pod becomes ready.

8. Read [kubernetes-manifests/05-inference-deployment.yaml](kubernetes-manifests/05-inference-deployment.yaml)
   to see how MODEL_URI flows from ConfigMap → pod environment → FastAPI settings →
   model loader. Focus on the probe strategy (startup + liveness + readiness).

9. Read [release-bridge/resolve-approved-model-reference_1.sh](release-bridge/resolve-approved-model-reference_1.sh)
   to see how the CI/CD bridge calls the MLflow API to resolve `@champion` to
   an immutable version number.

10. Read [Anti-patterns this module intentionally avoids](#anti-patterns-this-module-intentionally-avoids)
    to understand which beginner/demo serving habits are deliberately not used here.

11. Run the release bridge and deploy the inference stack (Commands section below).

## Commands section

### Prerequisites

The MLflow server must be running and a model must have the `champion` alias set
in `wine-quality-classifier-prod`. Follow the `ml-training` module runbooks first.

```bash
# Confirm MLflow is running:
curl -I http://127.0.0.1:5000
# Expected: HTTP/1.1 200 OK
```

#### Alternative: Start MLflow from this folder (if not already running)

If MLflow is not yet running, you can start it directly from this folder:

```bash
bash check-and-start-mlflow_1.sh
```

This script:
- **Checks** if MLflow is already running on `127.0.0.1:5000`
- **Logs the URL** if it's already running, then exits
- **Starts MLflow** if needed, storing artifacts locally in `.mlflow-server/`

### Inspect the Kubernetes inference namespace before changing anything

Run this when you want to confirm which cluster `kubectl` is pointed at and
whether the expected inference namespace/resources already exist. This is a
read-only command. It does not create, update, or delete anything.

```bash
cd /mnt/d/Generative\ AI\ Portfolio\ Projects/kubernetes_architure/k8s_mlops/ml-inferencing-fastapi
bash inspect-inference-resources_2.sh
```

What you should see when the stack exists:

```text
Current kubectl context: kind-local-enterprise-dev
Expected namespace:     ml-inference
Namespace 'ml-inference' exists.
FOUND:   configmap/wine-quality-inference-config
FOUND:   deployment/wine-quality-inference-api
FOUND:   service/wine-quality-inference-service
```

What you should see when the stack has not been deployed yet:

```text
Namespace 'ml-inference' does not exist in context 'kind-local-enterprise-dev'.
Meaning:
  - The inference stack is probably not deployed in this cluster, or
  - You are pointed at the wrong kubectl context, or
  - The stack was already destroyed.
```

### Run FastAPI before containerizing

This validates the inference runtime before Docker or Kubernetes are involved.
The app still uses the centralized Pydantic Settings module, but local values
come from `.env` instead of manual `export` commands.

```bash
cd /mnt/d/Generative\ AI\ Portfolio\ Projects/kubernetes_architure/k8s_mlops/ml-inferencing-fastapi/runtime-image
bash run-local-fastapi_1.sh
```

What you should see:

```text
Stage 2.2: Checking MLflow reachability
MLflow is reachable at http://127.0.0.1:5000.
Uvicorn running on http://0.0.0.0:8080
Model loaded successfully
```

In a second WSL2 terminal:

```bash
curl http://127.0.0.1:8080/health/ready
```

What you should see:

```text
{"status":"ready", ... "model_version":"1", ...}
```

ENTERPRISE EMPHASIS: `.env` is a local developer convenience, not a production
deployment mechanism. Kubernetes still receives the same configuration names
from ConfigMap and Secret objects, and Continuous Integration/Continuous
Delivery (CI/CD) should render the immutable `MODEL_URI` after MLflow approval.

### Build the container image

```bash
cd /mnt/d/Generative\ AI\ Portfolio\ Projects/kubernetes_architure/k8s_mlops/ml-inferencing-fastapi/runtime-image
docker build -t wine-quality-inference-api:1.0.0 .
```

What you should see:

```text
[+] Building ... (using layer cache on repeat builds)
Successfully tagged wine-quality-inference-api:1.0.0
```

### Load the image into kind

```bash
kind load docker-image wine-quality-inference-api:1.0.0 --name local-enterprise-dev
```

What you should see:

```text
Image: "wine-quality-inference-api:1.0.0" with ID "sha256:..." not yet present on node ...
Loading image: done
```

### Run the release bridge

```bash
cd /mnt/d/Generative\ AI\ Portfolio\ Projects/kubernetes_architure/k8s_mlops/ml-inferencing-fastapi/release-bridge

# Step 1: Resolve @champion alias to immutable version
bash resolve-approved-model-reference_1.sh

# Step 2: Patch ConfigMap and Deployment manifests
bash render-inference-config_2.sh

# Step 3: Apply to cluster and wait for rollout
bash rollout-approved-model_3.sh
```

What you should see after Step 3:

```text
✓ Rolling update complete.
  All pods are now serving from: models:/wine-quality-classifier-prod/1
✓ Smoke test passed.
  Release complete.
```

### Verify the stack

```bash
cd /mnt/d/Generative\ AI\ Portfolio\ Projects/kubernetes_architure/k8s_mlops/ml-inferencing-fastapi/kubernetes-manifests
bash verify-inference-stack_5.sh
```

### Manually test a prediction (from WSL2)

```bash
# Port-forward to the service (or a pod)
kubectl port-forward service/wine-quality-inference-service 8080:8080 -n ml-inference &

# Send a prediction request
curl -s -X POST http://127.0.0.1:8080/predict \
  -H "Content-Type: application/json" \
  -d '{
    "alcohol": 14.23,
    "malic_acid": 1.71,
    "ash": 2.43,
    "alcalinity_of_ash": 15.6,
    "magnesium": 127.0,
    "total_phenols": 2.80,
    "flavanoids": 3.06,
    "nonflavanoid_phenols": 0.28,
    "proanthocyanins": 2.29,
    "color_intensity": 5.64,
    "hue": 1.04,
    "od280_od315_of_diluted_wines": 3.92,
    "proline": 1065.0
  }'
```

What you should see:

```json
{
  "predicted_class": 0,
  "predicted_label": "class_0",
  "served_model_uri": "models:/wine-quality-classifier-prod/1",
  "model_version": "1",
  "registry_name": "wine-quality-classifier-prod"
}
```

### Check pod logs

```bash
kubectl logs -l app.kubernetes.io/name=wine-quality-inference-api -n ml-inference --follow
```

### Rollback

```bash
# Roll back to the previous model version (Kubernetes revision undo)
kubectl rollout undo deployment/wine-quality-inference-api -n ml-inference

# Or: re-run the release bridge with the previous version set
MODEL_ALIAS=previous-champion bash release-bridge/resolve-approved-model-reference_1.sh
```

## Enterprise translation

| What we do locally | What enterprise does | Why it differs |
|---|---|---|
| MLflow running on WSL2 host at `http://127.0.0.1:5000` | MLflow behind TLS at `https://mlflow.internal.company.com` with SSO and high availability | Production model registries need auth, TLS, and multi-replica resilience |
| Model artifacts stored on local disk | Model artifacts in S3, GCS, or Azure Blob, proxied through MLflow `--serve-artifacts` | Object storage is durable, versioned, and reachable from any cluster node |
| Release bridge as bash scripts run manually | Release bridge as CI/CD pipeline steps triggered by MLflow webhook or cron | Enterprise releases need audit logs, idempotency, approval gates, and rollback history |
| `kind load docker-image` to push to local cluster | `docker push` to OCI registry (ECR, GCR, ACR, Harbor) then `imagePullPolicy: Always` | Container registries provide image scanning, versioning, and pull rate controls |
| `kubectl apply` run from developer terminal | ArgoCD or Flux sync from Git, triggered by config commit | GitOps means Git is the authoritative record of what is deployed and when |
| ConfigMap updated by bash script with `sed` | Kustomize overlay, Helm values, or Jsonnet template rendered by CI | Declarative config management is reproducible and reviewable in PRs |
| `kubectl rollout restart` for rolling update | Same pattern, or Argo Rollouts for canary/blue-green | The core rolling update is identical; Argo Rollouts adds metric-based gates |
| Smoke test bash script | Automated test job in CI/CD pipeline, canary analysis with Prometheus | Automated quality gates replace manual smoke tests at scale |
| `kubectl rollout undo` for rollback | ArgoCD sync to previous Git SHA, Argo Rollouts abort | Enterprise rollback must update Git for auditability |
| ClusterIP service for internal access | LoadBalancer or Ingress with TLS for external access | External traffic needs TLS termination, DNS, and rate limiting |
| 2 replicas with HPA 2-4 | 3+ replicas with HPA 3-50+, cluster autoscaler for node capacity | Production inference APIs need availability guarantees beyond laptop capacity |

## Anti-patterns this module intentionally avoids

| Anti-pattern | Why it is dangerous | Enterprise-safe pattern used here |
|---|---|---|
| Resolving `@champion` inside the serving pod | `@champion` is a moving pointer. If it changes while pods are running, different pods may serve different versions without a Kubernetes rollout. | Resolve `@champion` once in the release bridge, then deploy an immutable URI such as `models:/wine-quality-classifier-prod/1`. |
| Loading the model on every request | Each prediction would pay model download/deserialization cost, and MLflow outages could break serving even after a model was already approved. | Load the model once during FastAPI lifespan startup and serve from memory for the pod lifetime. |
| Swallowing model-load failures | A pod can remain alive but permanently unready. Readiness failures remove traffic, but they do not restart the container. | Fail startup when the configured model cannot load so the rollout fails clearly and rollback automation can act. |
| Using the `default` ServiceAccount | The workload identity is hidden, so future Role-Based Access Control (RBAC) permissions are hard to audit safely. | Use a named ServiceAccount, `wine-quality-inference-api`, and keep `automountServiceAccountToken: false` because the app does not call the Kubernetes API. |
| Smoke-testing only HTTP 200 or response shape | A stale pod, wrong model version, or wrong prediction can pass if the test only checks that JSON fields exist. | Test through the Kubernetes Service and assert expected class, label, `MODEL_URI`, and `MODEL_VERSION`. |
| Updating a ConfigMap without a rollout | Environment variables from ConfigMaps are read when the pod starts. Existing pods do not reload them automatically. | Patch a checksum annotation on the Deployment so Kubernetes creates new pods with the updated model reference. |
| Using a mutable image tag as release identity | Tags such as `latest` or reused local tags can point to different image contents over time. | Local lab uses `wine-quality-inference-api:1.0.0`; enterprise equivalent is an immutable Git SHA tag or image digest. |
| Hardcoding secrets in manifests | Plain Kubernetes Secret YAML is base64-encoded, not safely secret for Git history or broad namespace readers. | Keep only local placeholders in Git and document External Secrets Operator, Vault, or cloud secret managers for production. |
| Treating NodePort or manual `kubectl` as enterprise deployment | Manual commands are hard to audit, repeat, and roll back across teams and environments. | Use local scripts for learning, but document GitOps/CI/CD tools such as ArgoCD, Flux, Helm, Kustomize, and Argo Rollouts as the enterprise equivalent. |

## What to check if something goes wrong

**Symptom: Pods stuck in Pending state**
```text
Likely cause:  Insufficient CPU or memory in the kind cluster.
Diagnostic:    kubectl describe pod <pod-name> -n ml-inference
               Look for: "Insufficient cpu" or "Insufficient memory" in Events
Fix:           Reduce resource requests in 05-inference-deployment.yaml
               or add more resources to the Docker Desktop / kind cluster.
```

**Symptom: Pods in Running state but /health/ready returns HTTP 503**
```text
Likely cause:  Model artifact could not be downloaded. MLflow server unreachable
               or MODEL_URI does not exist.
Diagnostic:    kubectl logs <pod-name> -n ml-inference
               Look for: "model load failed" or "Connection refused"
Fix A (MLflow unreachable): Confirm MLFLOW_TRACKING_URI in ConfigMap.
               The pod must reach host.docker.internal:5000 (WSL2 host) or the
               MLflow Service inside the cluster. Test connectivity:
               kubectl exec -it <pod-name> -n ml-inference -- \
                 python3 -c "import urllib.request; print(urllib.request.urlopen('http://host.docker.internal:5000').status)"
Fix B (wrong MODEL_URI): Confirm the release bridge ran and the ConfigMap was
               updated. Check: kubectl get configmap wine-quality-inference-config
               -n ml-inference -o yaml | grep MODEL_URI
```

**Symptom: Rollout stuck — new pod never becomes ready**
```text
Likely cause:  Model loading takes longer than startupProbe timeout, or
               the model artifact was deleted from MLflow.
Diagnostic:    kubectl describe pod -l app.kubernetes.io/name=wine-quality-inference-api
               -n ml-inference
               Look for: "Startup probe failed" or "Readiness probe failed"
Fix:           Increase startupProbe failureThreshold in 05-inference-deployment.yaml
               or verify the model artifact exists in MLflow.
```

**Symptom: ImagePullBackOff**
```text
Likely cause:  Container image wine-quality-inference-api:1.0.0 was not loaded
               into the kind cluster.
Diagnostic:    kubectl describe pod <pod-name> -n ml-inference
               Look for: "Failed to pull image"
Fix:           kind load docker-image wine-quality-inference-api:1.0.0 --name local-enterprise-dev
               Then: kubectl rollout restart deployment/wine-quality-inference-api -n ml-inference
```

**Symptom: /predict returns HTTP 422 Unprocessable Entity**
```text
Likely cause:  Missing or incorrectly typed fields in the request body.
Diagnostic:    The HTTP 422 response body contains per-field error messages.
               Print it: curl -v -X POST http://127.0.0.1:8080/predict -H "Content-Type: application/json" -d '{"alcohol": 14.23}'
Fix:           Supply all 13 required fields matching the WineQualityFeatures schema.
               See runtime-image/app/prediction/schemas.py for the full field list.
```

**Symptom: HPA shows TARGETS as `<unknown>`**
```text
Likely cause:  metrics-server is not installed in the kind cluster.
Diagnostic:    kubectl get hpa -n ml-inference
Fix:           Install metrics-server:
               kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
               Then patch for kind: kubectl patch deployment metrics-server -n kube-system \
                 --type=json \
                 -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
```
