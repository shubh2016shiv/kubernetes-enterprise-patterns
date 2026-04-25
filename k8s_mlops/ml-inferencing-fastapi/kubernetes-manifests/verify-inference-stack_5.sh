#!/usr/bin/env bash
# =============================================================================
# FILE:    verify-inference-stack_5.sh
# PURPOSE: Inspect the deployed inference stack and surface any unhealthy state.
#          Shows pod status, readiness, deployed model version, and probe results.
# USAGE:   From WSL2, inside kubernetes-manifests/:
#            bash verify-inference-stack.sh
# WHEN:    Run after apply-inference-stack_3.sh completes, or during debugging.
# PREREQS: Inference stack deployed in ml-inference namespace.
# OUTPUT:  Table of pod status, model version, readiness probe result.
# =============================================================================

set -euo pipefail

# CAN BE CHANGED: Must match 01-namespace.yaml. Example:
# `NAMESPACE="ml-inference-dev"` if you renamed the namespace.
NAMESPACE="ml-inference"

echo ""
echo "========================================================"
echo "  Wine Quality Inference Stack — Health Verification"
echo "========================================================"

# ─────────────────────────────────────────────────────────────────────────────
# Stage 1: Namespace and resource existence
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- Resources in namespace: ${NAMESPACE} ---"

if ! kubectl get namespace "${NAMESPACE}" &>/dev/null; then
  echo "✗ Namespace ${NAMESPACE} does not exist. Run apply-inference-stack_3.sh first."
  exit 1
fi

kubectl get all -n "${NAMESPACE}" 2>/dev/null || true

# ─────────────────────────────────────────────────────────────────────────────
# Stage 2: ConfigMap — show what model version is deployed
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- Deployed Model Reference (from ConfigMap) ---"

# CAN BE CHANGED: If the ConfigMap name changes in 02-inference-configmap.yaml,
# update `wine-quality-inference-config` below. Example:
# `fraud-risk-inference-config`.
MODEL_URI=$(kubectl get configmap wine-quality-inference-config \
  -n "${NAMESPACE}" -o jsonpath='{.data.MODEL_URI}' 2>/dev/null || echo "ConfigMap not found")
MODEL_VERSION=$(kubectl get configmap wine-quality-inference-config \
  -n "${NAMESPACE}" -o jsonpath='{.data.MODEL_VERSION}' 2>/dev/null || echo "unknown")
MLFLOW_URI=$(kubectl get configmap wine-quality-inference-config \
  -n "${NAMESPACE}" -o jsonpath='{.data.MLFLOW_TRACKING_URI}' 2>/dev/null || echo "unknown")

echo "  MODEL_URI:            ${MODEL_URI}"
echo "  MODEL_VERSION:        ${MODEL_VERSION}"
echo "  MLFLOW_TRACKING_URI:  ${MLFLOW_URI}"

# ─────────────────────────────────────────────────────────────────────────────
# Stage 3: Pod status and readiness
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- Pod Status ---"

POD_NAMES=$(kubectl get pods -n "${NAMESPACE}" \
  -l app.kubernetes.io/name=wine-quality-inference-api \
  -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

if [[ -z "${POD_NAMES}" ]]; then
  echo "✗ No inference pods found in namespace ${NAMESPACE}."
  echo "  Run apply-inference-stack_3.sh to deploy the stack."
  exit 1
fi

echo "  Pods matching label app.kubernetes.io/name=wine-quality-inference-api:"
kubectl get pods -n "${NAMESPACE}" \
  -l app.kubernetes.io/name=wine-quality-inference-api \
  -o wide 2>/dev/null || true

# ─────────────────────────────────────────────────────────────────────────────
# Stage 4: Probe each pod's /health/ready via port-forward
# This confirms the model was loaded successfully, not just that the pod exists.
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- Readiness Probe Verification (via port-forward) ---"
echo "  Starting temporary port-forward to first ready pod..."

# CAN BE CHANGED: If the app label changes in 05-inference-deployment.yaml,
# update the selector below. Example:
# `app.kubernetes.io/name=fraud-risk-inference-api`.
FIRST_POD=$(kubectl get pods -n "${NAMESPACE}" \
  -l app.kubernetes.io/name=wine-quality-inference-api \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [[ -z "${FIRST_POD}" ]]; then
  echo "✗ No pods found to probe."
else
  # Start port-forward in the background and probe it.
  # CAN BE CHANGED: Use a different local port if 18080 is already busy.
  # Example: `19080:8080`. If containerPort changes from 8080, update the
  # right-hand side too.
  kubectl port-forward pod/"${FIRST_POD}" 18080:8080 -n "${NAMESPACE}" &>/dev/null &
  PF_PID=$!
  sleep 2

  LIVENESS_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    http://127.0.0.1:18080/health/live 2>/dev/null || echo "unreachable")
  READINESS_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    http://127.0.0.1:18080/health/ready 2>/dev/null || echo "unreachable")
  METADATA=$(curl -s http://127.0.0.1:18080/ 2>/dev/null || echo "{}")

  kill "${PF_PID}" 2>/dev/null || true
  wait "${PF_PID}" 2>/dev/null || true

  echo "  Pod: ${FIRST_POD}"
  echo "  /health/live  → HTTP ${LIVENESS_STATUS}"
  echo "  /health/ready → HTTP ${READINESS_STATUS}"

  if [[ "${READINESS_STATUS}" == "200" ]]; then
    echo "  ✓ Pod is ready. Model is loaded and serving predictions."
    echo "  Metadata: ${METADATA}"
  elif [[ "${READINESS_STATUS}" == "503" ]]; then
    echo "  ✗ Pod is NOT ready (HTTP 503). Model may still be loading."
    echo "  Check logs: kubectl logs ${FIRST_POD} -n ${NAMESPACE}"
  else
    echo "  ✗ Unexpected status: ${READINESS_STATUS}."
    echo "  Check if port-forward is working and the pod is running."
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Stage 5: HPA status
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- HPA Status ---"
kubectl get hpa -n "${NAMESPACE}" 2>/dev/null || echo "  No HPA found."
echo ""
echo "  If TARGETS shows <unknown>, metrics-server is not installed."
echo "  Install: kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"

echo ""
echo "========================================================"
echo "  Verification complete."
echo "  Run test-prediction.sh to verify the /predict endpoint."
echo "========================================================"
