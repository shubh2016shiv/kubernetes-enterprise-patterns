#!/usr/bin/env bash
# =============================================================================
# FILE:    inspect-inference-resources_2.sh
# PURPOSE: Show which Kubernetes cluster, namespace, and inference resources
#          kubectl is currently pointed at before applying, testing, or deleting
#          the FastAPI inference stack.
# USAGE:   From WSL2, inside ml-inferencing-fastapi/:
#            bash inspect-inference-resources_2.sh
# WHEN:    Run this before deploy, rollout, smoke test, or destroy when you want
#          to confirm you are working with the expected inference namespace.
# PREREQS: kubectl installed and configured for the intended local kind cluster.
# OUTPUT:  Read-only inventory of cluster context, namespace, resources, model
#          config, service endpoints, autoscaler, and storage objects.
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# READ-ONLY SAFETY NOTE
# -----------------------------------------------------------------------------
# This script does not create, update, or delete anything. It only runs `kubectl
# get`, `kubectl describe`-style inventory commands, and local kind context checks.
# Use destroy-inference-stack_6.sh only when you intentionally want deletion.
# -----------------------------------------------------------------------------

# CAN BE CHANGED: Must match the kind cluster used by the local setup module.
# Example: `mlops-dev` if your cluster was created with that name.
KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-local-enterprise-dev}"

# CAN BE CHANGED: Derived from KIND_CLUSTER_NAME. Do not edit directly; change
# KIND_CLUSTER_NAME instead. Example result: `kind-mlops-dev`.
EXPECTED_CONTEXT="kind-${KIND_CLUSTER_NAME}"

# CAN BE CHANGED: Must match kubernetes-manifests/01-namespace.yaml
# metadata.name. Example: `ml-inference-dev`.
NAMESPACE="${NAMESPACE:-ml-inference}"

# CAN BE CHANGED: Must match kubernetes-manifests/05-inference-deployment.yaml
# metadata.name. Example: `fraud-risk-inference-api`.
DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-wine-quality-inference-api}"

# CAN BE CHANGED: Must match kubernetes-manifests/06-inference-service.yaml
# metadata.name. Example: `fraud-risk-inference-service`.
SERVICE_NAME="${SERVICE_NAME:-wine-quality-inference-service}"

# CAN BE CHANGED: Must match kubernetes-manifests/02-inference-configmap.yaml
# metadata.name. Example: `fraud-risk-inference-config`.
CONFIGMAP_NAME="${CONFIGMAP_NAME:-wine-quality-inference-config}"

print_stage() {
  local message="$1"
  printf '\n%s\n' "========================================================"
  printf '%s\n' "$message"
  printf '%s\n' "========================================================"
}

print_command_hint() {
  local command_text="$1"
  printf '  %s\n' "${command_text}"
}

require_command() {
  local command_name="$1"
  local install_hint="$2"

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "ERROR: ${command_name} is not installed or not on PATH."
    echo "Fix: ${install_hint}"
    exit 1
  fi
}

resource_exists() {
  local resource_type="$1"
  local resource_name="$2"

  kubectl get "${resource_type}" "${resource_name}" -n "${NAMESPACE}" >/dev/null 2>&1
}

print_stage "Stage 1.0: Confirm kubectl target"

require_command "kubectl" "Install kubectl inside WSL2, then retry."

CURRENT_CONTEXT="$(kubectl config current-context 2>/dev/null || echo "none")"
echo "Current kubectl context: ${CURRENT_CONTEXT}"
echo "Expected local context: ${EXPECTED_CONTEXT}"
echo "Expected namespace:     ${NAMESPACE}"

if [[ "${CURRENT_CONTEXT}" == "none" ]]; then
  echo
  echo "ERROR: kubectl has no current context."
  echo "Fix:"
  print_command_hint "kubectl config get-contexts"
  print_command_hint "kubectl config use-context ${EXPECTED_CONTEXT}"
  exit 1
fi

if [[ "${CURRENT_CONTEXT}" != "${EXPECTED_CONTEXT}" ]]; then
  echo
  echo "WARNING: kubectl is not pointed at the expected local context."
  echo "This may be intentional, but verify before applying or deleting resources."
  echo "To switch to the expected local context:"
  print_command_hint "kubectl config use-context ${EXPECTED_CONTEXT}"
fi

if ! kubectl cluster-info --request-timeout=5s >/dev/null 2>&1; then
  echo
  echo "ERROR: kubectl cannot reach the Kubernetes API server."
  echo "Fix: confirm the kind cluster is running:"
  print_command_hint "kind get clusters"
  exit 1
fi

echo "Kubernetes API server is reachable."

if command -v kind >/dev/null 2>&1; then
  echo
  echo "Local kind clusters visible from WSL2:"
  kind get clusters 2>/dev/null | sed 's/^/  - /' || true
else
  echo
  echo "kind not found on PATH. Skipping local kind cluster list."
fi

print_stage "Stage 2.0: Check inference namespace"

if ! kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
  echo "Namespace '${NAMESPACE}' does not exist in context '${CURRENT_CONTEXT}'."
  echo
  echo "Meaning:"
  echo "  - The inference stack is probably not deployed in this cluster, or"
  echo "  - You are pointed at the wrong kubectl context, or"
  echo "  - The stack was already destroyed."
  echo
  echo "Next useful commands:"
  print_command_hint "bash kubernetes-manifests/check-cluster-prerequisites_2.sh"
  print_command_hint "bash kubernetes-manifests/apply-inference-stack_3.sh"
  print_command_hint "kubectl get namespaces"
  exit 0
fi

echo "Namespace '${NAMESPACE}' exists."
echo
kubectl get namespace "${NAMESPACE}" --show-labels

print_stage "Stage 3.0: Inventory inference resources"

echo "Core resources in namespace '${NAMESPACE}':"
kubectl get all -n "${NAMESPACE}" 2>/dev/null || true

echo
echo "ConfigMaps, Secrets, and ServiceAccounts:"
kubectl get configmap,secret,serviceaccount -n "${NAMESPACE}" 2>/dev/null || true

print_stage "Stage 4.0: Check expected named resources"

EXPECTED_RESOURCES=(
  "configmap/${CONFIGMAP_NAME}"
  "deployment/${DEPLOYMENT_NAME}"
  "service/${SERVICE_NAME}"
  "serviceaccount/${DEPLOYMENT_NAME}"
  "secret/wine-quality-inference-secrets"
  "horizontalpodautoscaler/wine-quality-inference-hpa"
)

for resource in "${EXPECTED_RESOURCES[@]}"; do
  if kubectl get "${resource}" -n "${NAMESPACE}" >/dev/null 2>&1; then
    echo "FOUND:   ${resource}"
  else
    echo "MISSING: ${resource}"
  fi
done

print_stage "Stage 5.0: Show deployed model configuration"

if resource_exists "configmap" "${CONFIGMAP_NAME}"; then
  MODEL_URI="$(kubectl get configmap "${CONFIGMAP_NAME}" -n "${NAMESPACE}" -o jsonpath='{.data.MODEL_URI}' 2>/dev/null || echo "unknown")"
  MODEL_VERSION="$(kubectl get configmap "${CONFIGMAP_NAME}" -n "${NAMESPACE}" -o jsonpath='{.data.MODEL_VERSION}' 2>/dev/null || echo "unknown")"
  MODEL_REGISTRY_NAME="$(kubectl get configmap "${CONFIGMAP_NAME}" -n "${NAMESPACE}" -o jsonpath='{.data.MODEL_REGISTRY_NAME}' 2>/dev/null || echo "unknown")"
  MLFLOW_TRACKING_URI="$(kubectl get configmap "${CONFIGMAP_NAME}" -n "${NAMESPACE}" -o jsonpath='{.data.MLFLOW_TRACKING_URI}' 2>/dev/null || echo "unknown")"

  echo "MODEL_URI:           ${MODEL_URI}"
  echo "MODEL_VERSION:       ${MODEL_VERSION}"
  echo "MODEL_REGISTRY_NAME: ${MODEL_REGISTRY_NAME}"
  echo "MLFLOW_TRACKING_URI: ${MLFLOW_TRACKING_URI}"
else
  echo "ConfigMap '${CONFIGMAP_NAME}' is missing, so model config is not available."
fi

print_stage "Stage 6.0: Check rollout, endpoints, and autoscaling"

if resource_exists "deployment" "${DEPLOYMENT_NAME}"; then
  echo "Deployment summary:"
  kubectl get deployment "${DEPLOYMENT_NAME}" -n "${NAMESPACE}" -o wide
  echo
  echo "Recent rollout status:"
  kubectl rollout status "deployment/${DEPLOYMENT_NAME}" -n "${NAMESPACE}" --timeout=5s || true
else
  echo "Deployment '${DEPLOYMENT_NAME}' is missing."
fi

echo
if resource_exists "service" "${SERVICE_NAME}"; then
  echo "Service summary:"
  kubectl get service "${SERVICE_NAME}" -n "${NAMESPACE}" -o wide
  echo
  echo "Service endpoints:"
  kubectl get endpoints "${SERVICE_NAME}" -n "${NAMESPACE}" -o wide 2>/dev/null || true
else
  echo "Service '${SERVICE_NAME}' is missing."
fi

echo
echo "HorizontalPodAutoscaler status:"
kubectl get hpa -n "${NAMESPACE}" 2>/dev/null || echo "No HPA found."

print_stage "Stage 7.0: Check storage and volume expectations"

echo "PersistentVolumeClaims in namespace '${NAMESPACE}':"
kubectl get pvc -n "${NAMESPACE}" 2>/dev/null || true

echo
echo "PersistentVolumes related to the namespace, if any:"
kubectl get pv 2>/dev/null | grep "${NAMESPACE}" || echo "No PersistentVolumes visibly bound to ${NAMESPACE}."

echo
echo "Inference stack storage note:"
echo "  This FastAPI inference Deployment currently uses pod-local emptyDir volumes"
echo "  for /tmp and MLflow cache. emptyDir storage disappears when its pod is"
echo "  deleted. There is no inference PersistentVolumeClaim unless you add one."

print_stage "Stage 8.0: Suggested next commands"

echo "If the namespace/resources are missing and you want to deploy:"
print_command_hint "cd kubernetes-manifests"
print_command_hint "bash check-cluster-prerequisites_2.sh"
print_command_hint "bash apply-inference-stack_3.sh"

echo
echo "If resources exist and you want to verify health:"
print_command_hint "cd kubernetes-manifests"
print_command_hint "bash verify-inference-stack_5.sh"
print_command_hint "bash test-prediction_4.sh"

echo
echo "If resources exist and you want to reset inference only:"
print_command_hint "cd kubernetes-manifests"
print_command_hint "CONFIRM_DELETE_INFERENCE_STACK=${NAMESPACE} bash destroy-inference-stack_6.sh"
