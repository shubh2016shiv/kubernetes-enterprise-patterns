#!/usr/bin/env bash
# =============================================================================
# FILE:    destroy-inference-stack_4.sh
# PURPOSE: Delete the local FastAPI inference stack so the learner can start
#          fresh without guessing which Kubernetes resources exist.
# USAGE:   From WSL2, inside kubernetes-manifests/:
#            CONFIRM_DELETE_INFERENCE_STACK=ml-inference bash destroy-inference-stack_4.sh
# WHEN:    Run only when you intentionally want to remove the deployed inference
#          API, Service, ConfigMap, Secret placeholder, HPA, and namespace.
# PREREQS: kubectl installed, kubectl context pointed at the intended cluster.
# OUTPUT:  Inference-owned Kubernetes resources are deleted or reported absent.
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# DESTRUCTIVE WARNING
# -----------------------------------------------------------------------------
# This script deletes Kubernetes resources. It is safe for normal local reset
# only because it is scoped to the inference namespace by default.
#
# It does NOT delete the kind cluster unless DELETE_KIND_CLUSTER=true is set.
# It does NOT delete MLflow model artifacts or local source files.
# It does NOT delete host Docker images unless DELETE_LOCAL_IMAGE=true is set.
# -----------------------------------------------------------------------------

# CAN BE CHANGED: Must match 01-namespace.yaml metadata.name and the namespace
# values in 08-inference-cleanup-targets.yaml. Example: `ml-inference-dev`.
NAMESPACE="${NAMESPACE:-ml-inference}"

# CAN BE CHANGED: Must match the local kind cluster used by the setup module.
# Example: `mlops-dev` if your kind cluster was created with that name.
KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-local-enterprise-dev}"

# CAN BE CHANGED: Must match the local image tag used by 05-inference-deployment.yaml.
# Example: `fraud-risk-inference-api:1.0.0`.
LOCAL_IMAGE_NAME="${LOCAL_IMAGE_NAME:-wine-quality-inference-api:1.0.0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLEANUP_TARGETS_FILE="${SCRIPT_DIR}/08-inference-cleanup-targets.yaml"

print_stage() {
  local message="$1"
  printf '\n%s\n' "========================================================"
  printf '%s\n' "$message"
  printf '%s\n' "========================================================"
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

require_cleanup_confirmation() {
  if [[ "${CONFIRM_DELETE_INFERENCE_STACK:-}" != "${NAMESPACE}" ]]; then
    echo "REFUSING TO DELETE."
    echo
    echo "This script deletes the inference namespace and all inference resources in it."
    echo "Namespace targeted: ${NAMESPACE}"
    echo
    echo "Run again with an explicit confirmation:"
    echo "  CONFIRM_DELETE_INFERENCE_STACK=${NAMESPACE} bash destroy-inference-stack_4.sh"
    echo
    echo "What will be removed from Kubernetes:"
    echo "  - Namespace: ${NAMESPACE}"
    echo "  - Deployment: wine-quality-inference-api"
    echo "  - Service: wine-quality-inference-service"
    echo "  - ConfigMap: wine-quality-inference-config"
    echo "  - Secret placeholder: wine-quality-inference-secrets"
    echo "  - ServiceAccount: wine-quality-inference-api"
    echo "  - HorizontalPodAutoscaler: wine-quality-inference-hpa"
    echo
    echo "What will NOT be removed by default:"
    echo "  - kind cluster '${KIND_CLUSTER_NAME}'"
    echo "  - MLflow registered model versions or artifacts"
    echo "  - local source files"
    echo "  - host Docker image ${LOCAL_IMAGE_NAME}"
    exit 1
  fi
}

delete_inference_resources() {
  print_stage "Stage 2.0: Deleting inference Kubernetes resources"

  if [[ ! -f "${CLEANUP_TARGETS_FILE}" ]]; then
    echo "ERROR: Missing cleanup manifest: ${CLEANUP_TARGETS_FILE}"
    echo "Fix: restore 08-inference-cleanup-targets.yaml."
    exit 1
  fi

  echo "Deleting resources listed in:"
  echo "  ${CLEANUP_TARGETS_FILE}"
  echo
  echo "Expected result:"
  echo "  kubectl reports resources as deleted or not found."

  kubectl delete -f "${CLEANUP_TARGETS_FILE}" --ignore-not-found=true --wait=true

  echo
  echo "Inference Kubernetes resources deleted."
}

delete_kind_cluster_if_requested() {
  if [[ "${DELETE_KIND_CLUSTER:-false}" != "true" ]]; then
    echo
    echo "Cluster deletion skipped."
    echo "To also delete the local kind cluster, run:"
    echo "  DELETE_KIND_CLUSTER=true CONFIRM_DELETE_KIND_CLUSTER=${KIND_CLUSTER_NAME} \\"
    echo "  CONFIRM_DELETE_INFERENCE_STACK=${NAMESPACE} bash destroy-inference-stack_4.sh"
    return
  fi

  print_stage "Stage 3.0: Optional kind cluster deletion"

  if [[ "${CONFIRM_DELETE_KIND_CLUSTER:-}" != "${KIND_CLUSTER_NAME}" ]]; then
    echo "REFUSING TO DELETE KIND CLUSTER."
    echo
    echo "Deleting the kind cluster removes the entire local Kubernetes platform,"
    echo "including every namespace, pod, service, and local cluster volume in it."
    echo
    echo "Run again with:"
    echo "  DELETE_KIND_CLUSTER=true CONFIRM_DELETE_KIND_CLUSTER=${KIND_CLUSTER_NAME} \\"
    echo "  CONFIRM_DELETE_INFERENCE_STACK=${NAMESPACE} bash destroy-inference-stack_4.sh"
    exit 1
  fi

  require_command "kind" "Install kind inside WSL2, then retry."

  if kind get clusters | grep -qx "${KIND_CLUSTER_NAME}"; then
    echo "Deleting kind cluster: ${KIND_CLUSTER_NAME}"
    kind delete cluster --name "${KIND_CLUSTER_NAME}"
    echo "kind cluster deleted."
  else
    echo "kind cluster '${KIND_CLUSTER_NAME}' does not exist. Nothing to delete."
  fi
}

delete_local_image_if_requested() {
  if [[ "${DELETE_LOCAL_IMAGE:-false}" != "true" ]]; then
    echo
    echo "Local Docker image deletion skipped."
    echo "To also remove the host image, run:"
    echo "  DELETE_LOCAL_IMAGE=true CONFIRM_DELETE_INFERENCE_STACK=${NAMESPACE} \\"
    echo "  bash destroy-inference-stack_4.sh"
    return
  fi

  print_stage "Stage 4.0: Optional local Docker image deletion"

  require_command "docker" "Start Docker Desktop with WSL2 integration enabled."

  echo "Removing local Docker image if it exists: ${LOCAL_IMAGE_NAME}"
  docker image rm "${LOCAL_IMAGE_NAME}" 2>/dev/null || true
  echo "Local image cleanup attempted."
}

print_stage "Stage 1.0: Destructive cleanup preflight"

require_command "kubectl" "Install kubectl inside WSL2, then retry."

CURRENT_CONTEXT="$(kubectl config current-context 2>/dev/null || echo "none")"
echo "Current kubectl context: ${CURRENT_CONTEXT}"
echo "Target namespace: ${NAMESPACE}"
echo "Target kind cluster for optional deletion: ${KIND_CLUSTER_NAME}"

if [[ "${CURRENT_CONTEXT}" == "none" ]]; then
  echo "ERROR: kubectl has no current context."
  echo "Fix: set the intended context before deleting resources."
  exit 1
fi

require_cleanup_confirmation
delete_inference_resources
delete_kind_cluster_if_requested
delete_local_image_if_requested

echo
echo "========================================================"
echo "Cleanup complete."
echo
echo "To start fresh:"
echo "  bash deploy-local-inference-stack_1.sh"
echo "========================================================"
