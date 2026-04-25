#!/usr/bin/env bash
# =============================================================================
# FILE:    rollout-approved-model_3.sh
# PURPOSE: Apply the updated Kubernetes ConfigMap and trigger a rolling restart
#          of the inference Deployment so new pods load the approved model
#          version. Wait for the rollout to complete. Run the smoke test.
#          Roll back automatically if the rollout does not complete.
# USAGE:   From WSL2, inside release-bridge/:
#            bash rollout-approved-model.sh
# WHEN:    Third step of the release bridge. Run after render-inference-config.sh
#          has updated the ConfigMap and Deployment manifests.
# PREREQS: kubernetes-manifests/02-inference-configmap.yaml updated by
#          render-inference-config.sh. Inference Deployment already deployed.
# OUTPUT:  Rolling update complete. All pods serving the new approved model.
# =============================================================================

set -euo pipefail

# ┌─────────────────────────────────────────────────────────────────────────┐
# │                     RELEASE BRIDGE FLOW — Step 3                         │
# │                                                                          │
# │  Stage 1: Load resolved reference and validate                          │
# │                                                                          │
# │  Stage 2: Apply updated ConfigMap                                        │
# │      └── kubectl apply -f 02-inference-configmap.yaml                   │
# │                                                                          │
# │  Stage 3: Apply updated Deployment manifest                             │
# │      └── kubectl apply -f 05-inference-deployment.yaml                  │
# │      └── checksum/config annotation change triggers rollout             │
# │                                                                          │
# │  Stage 4: Wait for rollout                                              │
# │      └── kubectl rollout status --timeout=5m                            │
# │                                                                          │
# │  Stage 5: Smoke test                                                    │
# │      └── bash test-prediction.sh                                        │
# │                                                                          │
# │  On failure: kubectl rollout undo + alert                               │
# └─────────────────────────────────────────────────────────────────────────┘

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="${SCRIPT_DIR}/../kubernetes-manifests"
ENV_FILE="${SCRIPT_DIR}/resolved_model_reference.env"
# CAN BE CHANGED: Must match 01-namespace.yaml and all other scripts.
# Example: `ml-inference-dev`. If changed, update 01-namespace.yaml and
# NAMESPACE in verify-inference-stack_5.sh and test-prediction_4.sh.
NAMESPACE="ml-inference"
# CAN BE CHANGED: Must match metadata.name in 05-inference-deployment.yaml.
# Example: `fraud-risk-inference-api`. If changed, update that Deployment manifest
# and 07-hpa.yaml scaleTargetRef.name.
DEPLOYMENT="wine-quality-inference-api"
# CAN BE CHANGED: How long to wait for pods to become Ready before declaring
# failure and auto-rolling back. Example: `10m` on slow networks or large models.
ROLLOUT_TIMEOUT="5m"

echo ""
echo "========================================================"
echo "  Release Bridge — Step 3: Rollout Approved Model"
echo "========================================================"

# ─────────────────────────────────────────────────────────────────────────────
# Stage 1.0: Load resolved reference
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- Stage 1: Loading resolved reference ---"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "✗ ${ENV_FILE} not found."
  echo "  Run resolve-approved-model-reference.sh and render-inference-config.sh first."
  exit 1
fi

# shellcheck source=/dev/null
source "${ENV_FILE}"

echo "✓ Deploying:"
echo "  MODEL_URI:     ${MODEL_URI}"
echo "  MODEL_VERSION: ${MODEL_VERSION}"
echo "  Resolved from alias: @${MODEL_ALIAS} at ${RESOLVED_AT}"

# ─────────────────────────────────────────────────────────────────────────────
# Stage 2.0: Apply the updated ConfigMap
# Purpose: Inject the new MODEL_URI and MODEL_VERSION into the cluster.
#          Running pods do NOT reload env vars from the ConfigMap — a pod restart
#          is required. The Deployment rollout in Stage 3 handles that restart.
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- Stage 2: Applying updated ConfigMap ---"

kubectl apply -f "${MANIFESTS_DIR}/02-inference-configmap.yaml"
echo "✓ ConfigMap applied with MODEL_URI=${MODEL_URI}"

# ─────────────────────────────────────────────────────────────────────────────
# Stage 3.0: Apply the updated Deployment
# Purpose: The Deployment manifest has a checksum/config annotation that was
#          updated by render-inference-config.sh. Applying it with the new
#          annotation value causes Kubernetes to create a new ReplicaSet and
#          roll out new pods with the updated environment variables.
#
# Why not use `kubectl rollout restart` alone?
#   rollout restart creates a new ReplicaSet but does NOT change the pod's
#   environment because the ConfigMap values are read when the pod starts.
#   If the ConfigMap changes but the Deployment spec does not, a rollout restart
#   will pick up the new ConfigMap values. However, combining the annotation
#   change with kubectl apply gives us a reviewable, Git-diffable record of
#   every configuration change in the Deployment's revision history.
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- Stage 3: Applying updated Deployment (triggers rolling update) ---"

kubectl apply -f "${MANIFESTS_DIR}/05-inference-deployment.yaml"
echo "✓ Deployment applied. Rolling update in progress."
echo "  Old pods serve traffic until new pods pass /health/ready."
echo "  New pods connect to MLflow at ${MLFLOW_TRACKING_URI:-http://127.0.0.1:5000}"
echo "  and load: ${MODEL_URI}"

# ─────────────────────────────────────────────────────────────────────────────
# Stage 4.0: Wait for rollout
# Purpose: Block until all pods in the Deployment are running and ready.
#          If the rollout does not complete within ROLLOUT_TIMEOUT, attempt
#          automatic rollback to the previous revision.
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- Stage 4: Waiting for rolling update to complete (timeout: ${ROLLOUT_TIMEOUT}) ---"
echo "  While waiting, Kubernetes is:"
echo "    1. Starting new pod(s) with MODEL_URI=${MODEL_URI}"
echo "    2. New pod connects to MLflow and loads the model artifact"
echo "    3. New pod's /health/ready returns HTTP 200 (model loaded)"
echo "    4. Kubernetes adds new pod to Service endpoints"
echo "    5. Kubernetes removes old pod from Service endpoints"
echo "    6. Old pod terminates gracefully"
echo ""

if kubectl rollout status "deployment/${DEPLOYMENT}" \
     -n "${NAMESPACE}" \
     --timeout="${ROLLOUT_TIMEOUT}"; then

  echo ""
  echo "✓ Rolling update complete."
  echo "  All pods are now serving from: ${MODEL_URI}"

else
  # Rollout did not complete in time. Automatically undo to the previous revision.
  echo ""
  echo "✗ Rolling update did not complete within ${ROLLOUT_TIMEOUT}."
  echo ""
  echo "  Automatically rolling back to previous deployment revision..."
  kubectl rollout undo "deployment/${DEPLOYMENT}" -n "${NAMESPACE}" || true

  echo ""
  echo "  Rollback initiated. Verify the rollback state:"
  echo "    kubectl rollout status deployment/${DEPLOYMENT} -n ${NAMESPACE}"
  echo "    kubectl get pods -n ${NAMESPACE}"
  echo ""
  echo "  Investigate why the rollout failed:"
  echo "    kubectl describe deployment ${DEPLOYMENT} -n ${NAMESPACE}"
  echo "    kubectl logs -l app.kubernetes.io/name=wine-quality-inference-api -n ${NAMESPACE} --previous"
  echo ""
  echo "  Common causes:"
  echo "    - MLFLOW_TRACKING_URI is not reachable from inside the pod."
  echo "      Check: kubectl exec -it <pod-name> -n ${NAMESPACE} -- curl http://host.docker.internal:5000"
  echo "    - MODEL_URI version does not exist in the MLflow registry."
  echo "      Check: curl ${MLFLOW_TRACKING_URI:-http://127.0.0.1:5000}/api/2.0/mlflow/model-versions/get"
  echo "    - Container image wine-quality-inference-api:1.0.0 is not in the kind cluster."
  echo "      Fix: kind load docker-image wine-quality-inference-api:1.0.0 --name local-enterprise-dev"
  exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# Stage 5.0: Smoke test
# Purpose: Verify that the new pods can actually serve a prediction before
#          declaring the release complete. A pod that passes readiness but
#          returns wrong predictions is caught here, not in production traffic.
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- Stage 5: Running post-rollout smoke test ---"

if bash "${MANIFESTS_DIR}/test-prediction.sh"; then
  echo ""
  echo "========================================================"
  echo "  ✓ Release complete."
  echo ""
  echo "  Summary:"
  echo "    Registered model:  ${MODEL_REGISTRY_NAME}"
  echo "    Approved alias:    @${MODEL_ALIAS}"
  echo "    Deployed version:  ${MODEL_VERSION}"
  echo "    Immutable URI:     ${MODEL_URI}"
  echo "    Resolved at:       ${RESOLVED_AT}"
  echo ""
  echo "  Rollback command (if needed):"
  echo "    kubectl rollout undo deployment/${DEPLOYMENT} -n ${NAMESPACE}"
  echo "========================================================"
else
  echo ""
  echo "✗ Smoke test failed after successful rollout."
  echo "  The pods are running but the /predict endpoint returned an unexpected result."
  echo ""
  echo "  Initiating rollback..."
  kubectl rollout undo "deployment/${DEPLOYMENT}" -n "${NAMESPACE}" || true
  echo ""
  echo "  Investigate the failure:"
  echo "    kubectl logs -l app.kubernetes.io/name=wine-quality-inference-api -n ${NAMESPACE}"
  exit 1
fi
