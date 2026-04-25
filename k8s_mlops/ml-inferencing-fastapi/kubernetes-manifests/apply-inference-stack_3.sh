#!/usr/bin/env bash
# =============================================================================
# FILE:    apply-inference-stack_3.sh
# PURPOSE: Apply all Kubernetes manifests for the wine quality inference stack
#          in dependency order. Creates the namespace, config, and deployment.
# USAGE:   From WSL2, inside kubernetes-manifests/:
#            bash apply-inference-stack_3.sh
# WHEN:    Run this after:
#            1. check-cluster-prerequisites_2.sh passes.
#            2. The MLflow server is running.
#            3. A model version has been approved and champion alias is set.
#            4. The release bridge has resolved @champion and updated
#               02-inference-configmap.yaml with MODEL_URI and MODEL_VERSION.
#            5. The container image is built and loaded into kind:
#               docker build -t wine-quality-inference-api:1.0.0 ../runtime-image/
#               kind load docker-image wine-quality-inference-api:1.0.0 --name local-enterprise-dev
# PREREQS: kind cluster running, kubectl context set to local-enterprise-dev,
#          02-inference-configmap.yaml has been updated by render-inference-config.sh
# OUTPUT:  All resources created, deployment rolling out, pods becoming ready.
# =============================================================================

set -euo pipefail

# ┌─────────────────────────────────────────────────────────────────────────┐
# │                        APPLY FLOW                                        │
# │                                                                          │
# │  Stage 1: Preflight — verify kubectl context and cluster access          │
# │                                                                          │
# │  Stage 2: Apply namespace — isolates inference resources                 │
# │                                                                          │
# │  Stage 3: Apply ConfigMap — non-sensitive configuration including        │
# │           MODEL_URI and MLFLOW_TRACKING_URI                              │
# │                                                                          │
# │  Stage 4: Apply Secret placeholder — credentials slot for MLflow auth    │
# │                                                                          │
# │  Stage 5: Apply Deployment — starts inference pods, triggers rollout     │
# │                                                                          │
# │  Stage 6: Apply Service — stable cluster-internal endpoint               │
# │                                                                          │
# │  Stage 7: Apply HPA — autoscaling policy (needs metrics-server)          │
# │                                                                          │
# │  Stage 8: Wait for rollout — waits until all pods are ready              │
# └─────────────────────────────────────────────────────────────────────────┘

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# CAN BE CHANGED: Must match `metadata.name` in 01-namespace.yaml and every
# manifest namespace in this directory. Example: `NAMESPACE="ml-inference-dev"`.
NAMESPACE="ml-inference"

# ────────────────────────────────────────────────────────────────────────────���
# Stage 1.0: Preflight Checks
# Purpose: Confirm the environment is ready before touching the cluster.
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo "========================================================"
echo "  Stage 1: Preflight Checks"
echo "========================================================"

# Stage 1.1: Check kubectl is available.
if ! command -v kubectl &>/dev/null; then
  echo "✗ kubectl not found on PATH."
  echo "  Install kubectl inside WSL2: https://kubernetes.io/docs/tasks/tools/"
  exit 1
fi
echo "✓ kubectl found: $(kubectl version --client --short 2>/dev/null | head -1)"

# Stage 1.2: Confirm the cluster context.
CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null || echo "none")
echo "  Current kubectl context: ${CURRENT_CONTEXT}"

if [[ "${CURRENT_CONTEXT}" == "none" ]]; then
  echo "✗ No kubectl context is set."
  echo "  If using kind: kubectl config use-context kind-local-enterprise-dev"
  exit 1
fi

# Stage 1.3: Test cluster connectivity.
if ! kubectl cluster-info --request-timeout=5s &>/dev/null; then
  echo "✗ Cannot reach the Kubernetes API server."
  echo "  Confirm the kind cluster is running: kind get clusters"
  echo "  If the cluster stopped: kind start (or recreate it with the setup scripts)"
  exit 1
fi
echo "✓ Cluster reachable at context: ${CURRENT_CONTEXT}"

# Stage 1.4: Validate that MODEL_URI has been populated in the ConfigMap.
# The placeholder value "REPLACE_WITH_RESOLVED_URI" means the release bridge
# has not run yet. Do not deploy with placeholder values.
if grep -q "REPLACE_WITH_RESOLVED_URI" "${SCRIPT_DIR}/02-inference-configmap.yaml"; then
  echo ""
  echo "✗ 02-inference-configmap.yaml still has placeholder MODEL_URI."
  echo "  Run the release bridge to resolve the @champion alias first:"
  echo ""
  echo "    cd ../release-bridge"
  echo "    ./resolve-approved-model-reference.sh"
  echo "    ./render-inference-config.sh"
  echo ""
  echo "  Then re-run this script."
  exit 1
fi
echo "✓ ConfigMap MODEL_URI has been set by the release bridge."

# ─────────────────────────────────────────────────────────────────────────────
# Stage 2.0: Apply Namespace
# Purpose: Create ml-inference namespace before any other resources.
#          kubectl apply is idempotent — safe to re-run.
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo "========================================================"
echo "  Stage 2: Apply Namespace"
echo "========================================================"

kubectl apply -f "${SCRIPT_DIR}/01-namespace.yaml"

# Expected output: namespace/ml-inference created (or configured)

echo "✓ Namespace applied."

# ─────────────────────────────────────────────────────────────────────────────
# Stage 3.0: Apply ConfigMap
# Purpose: Inject MODEL_URI, MODEL_VERSION, MLFLOW_TRACKING_URI, and app config.
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo "========================================================"
echo "  Stage 3: Apply ConfigMap"
echo "========================================================"

kubectl apply -f "${SCRIPT_DIR}/02-inference-configmap.yaml"

# CAN BE CHANGED: If 02-inference-configmap.yaml `metadata.name` changes, update
# `wine-quality-inference-config` below. Example: `fraud-risk-inference-config`.
MODEL_URI=$(kubectl get configmap wine-quality-inference-config \
  -n "${NAMESPACE}" -o jsonpath='{.data.MODEL_URI}' 2>/dev/null || echo "unknown")
MODEL_VERSION=$(kubectl get configmap wine-quality-inference-config \
  -n "${NAMESPACE}" -o jsonpath='{.data.MODEL_VERSION}' 2>/dev/null || echo "unknown")

echo "✓ ConfigMap applied."
echo "  MODEL_URI:     ${MODEL_URI}"
echo "  MODEL_VERSION: ${MODEL_VERSION}"

# ─────────────────────────────────────────────────────────────────────────────
# Stage 4.0: Apply ServiceAccount
# Purpose: Create a dedicated Kubernetes workload identity before the
#          Deployment references it.
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo "========================================================"
echo "  Stage 4: Apply ServiceAccount"
echo "========================================================"

kubectl apply -f "${SCRIPT_DIR}/03-inference-serviceaccount.yaml"
echo "✓ ServiceAccount applied."
echo "  Workload identity: wine-quality-inference-api"

echo ""
echo "========================================================"
echo "  Stage 5: Apply Secret Placeholder"
echo "========================================================"

kubectl apply -f "${SCRIPT_DIR}/04-inference-secret-placeholder.yaml"
echo "✓ Secret placeholder applied (local lab placeholders only — not printed for security)."

# ─────────────────────────────────────────────────────────────────────────────
# Stage 6.0: Apply Deployment
# Purpose: Create the inference Deployment. Kubernetes starts pods and begins
#          the rolling update lifecycle. Pods are NOT yet receiving traffic —
#          readiness probes hold them until the model loads.
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo "========================================================"
echo "  Stage 6: Apply Deployment"
echo "========================================================"

kubectl apply -f "${SCRIPT_DIR}/05-inference-deployment.yaml"
echo "✓ Deployment applied. Pods are starting and loading the model artifact."

# ─────────────────────────────────────────────────────────────────────────────
# Stage 7.0: Apply Service
# Purpose: Create the stable cluster-internal endpoint for the inference API.
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo "========================================================"
echo "  Stage 7: Apply Service"
echo "========================================================"

kubectl apply -f "${SCRIPT_DIR}/06-inference-service.yaml"
echo "✓ Service applied."
echo "  Cluster-internal address: wine-quality-inference-service.${NAMESPACE}.svc.cluster.local:8080"

# ─────────────────────────────────────────────────────────────────────────────
# Stage 8.0: Apply HPA
# Purpose: Enable automatic scaling based on CPU utilization.
#          Requires metrics-server. If not installed, HPA is created but stays
#          inactive until metrics-server is available.
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo "========================================================"
echo "  Stage 8: Apply HPA"
echo "========================================================"

kubectl apply -f "${SCRIPT_DIR}/07-hpa.yaml"
echo "✓ HPA applied."
echo "  Scales between 2 and 4 replicas at 70% CPU utilization."
echo "  Requires metrics-server. If HPA shows <unknown> targets, install it:"
echo "    kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"

# ─────────────────────────────────────────────────────────────────────────────
# Stage 8.0: Wait for Rollout
# Purpose: Block until all pods are running and ready. The --timeout ensures
#          the script fails loudly if pods do not become ready within 5 minutes.
#          Common causes of timeout: MLflow unreachable, artifact missing,
#          container image not loaded into kind.
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo "========================================================"
echo "  Stage 9: Wait for Rollout"
echo "========================================================"
echo "  Waiting for deployment rollout (timeout: 5 minutes)..."
echo "  While waiting: model artifact is being downloaded from MLflow."
echo "  If this hangs: check pod logs:"
echo "    kubectl logs -l app.kubernetes.io/name=wine-quality-inference-api -n ${NAMESPACE}"

# CAN BE CHANGED: If the Deployment name changes in 05-inference-deployment.yaml,
# update `deployment/wine-quality-inference-api` below. Example:
# `deployment/fraud-risk-inference-api`.
# CAN BE CHANGED: Increase `--timeout=5m` for slower image pulls or large model
# downloads. Example: `--timeout=10m`.
if kubectl rollout status deployment/wine-quality-inference-api \
     -n "${NAMESPACE}" --timeout=5m; then
  echo ""
  echo "✓ Rollout complete. All pods are ready and receiving traffic."
  echo ""
  echo "========================================================"
  echo "  Inference stack is live."
  echo "  Run verify-inference-stack_5.sh to confirm pod health."
  echo "  Run test-prediction_4.sh to verify the /predict endpoint."
  echo "========================================================"
else
  echo ""
  echo "✗ Rollout did not complete within 5 minutes."
  echo ""
  echo "  Diagnose with:"
  echo "    kubectl get pods -n ${NAMESPACE}"
  echo "    kubectl describe pod -l app.kubernetes.io/name=wine-quality-inference-api -n ${NAMESPACE}"
  echo "    kubectl logs -l app.kubernetes.io/name=wine-quality-inference-api -n ${NAMESPACE} --previous"
  echo ""
  echo "  Common causes:"
  echo "    - MLFLOW_TRACKING_URI in ConfigMap is not reachable from the pod."
  echo "      Local fix: ensure MLflow server is running on WSL2 and use"
  echo "      http://host.docker.internal:5000 as the URI."
  echo "    - MODEL_URI does not exist in MLflow (wrong version number or deleted)."
  echo "    - Container image wine-quality-inference-api:1.0.0 not loaded into kind."
  echo "      Fix: kind load docker-image wine-quality-inference-api:1.0.0 --name local-enterprise-dev"
  exit 1
fi
