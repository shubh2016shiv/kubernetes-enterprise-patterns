#!/usr/bin/env bash
# =============================================================================
# FILE:    repush-application-image.sh
# PURPOSE: Rebuild, reload, and restart one application image in kind.
# USAGE:   bash app_k8_deployment/deployment-lifecycle/repush-application-image.sh api 1.0.0
# WHEN:    Run when code changes but the learning lab keeps the same image tag.
# PREREQS: Docker Desktop, kind, and the patient-record-system Deployment exist.
# OUTPUT:  Updated image is loaded into kind and the matching Deployment restarts.
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# SCRIPT FLOW
#
# Stage 1: Parse and Validate Inputs
#   - Decide whether to rebuild api or ui.
#
# Stage 2: Build Image
#   - Build the selected container image.
#
# Stage 3: Load Image into kind
#   - Copy the selected image into cluster nodes.
#
# Stage 4: Restart Deployment
#   - Force pods to pick up the rebuilt same-tag image.
#
# Stage 5: Verify Rollout
#   - Wait for readiness-gated rollout completion.
# ---------------------------------------------------------------------------

TARGET_COMPONENT="${1:-api}"
TARGET_TAG="${2:-1.0.0}"
KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-local-enterprise-dev}"
NAMESPACE="patient-record-system"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODULE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

section() {
  echo ""
  echo "=== $1 ==="
}

run_cmd() {
  echo "$ $*"
  "$@"
  echo ""
}

# ---------------------------------------------------------------------------
# Stage 1.0: Parse and Validate Inputs
# Purpose: Keep the script explicit so learners know which tier is changing.
# Expected input: component is either api or ui.
# Expected output: IMAGE, CONTEXT_DIR, and DEPLOYMENT_NAME are set.
# ---------------------------------------------------------------------------
section "Stage 1.0: Parse and Validate Inputs"

case "${TARGET_COMPONENT}" in
  api)
    IMAGE="patient-record-api:${TARGET_TAG}"
    CONTEXT_DIR="${MODULE_DIR}/application-source/patient-record-api"
    DEPLOYMENT_NAME="patient-record-api"
    CONTAINER_NAME="api"
    ;;
  ui)
    IMAGE="patient-intake-ui:${TARGET_TAG}"
    CONTEXT_DIR="${MODULE_DIR}/application-source/patient-intake-ui"
    DEPLOYMENT_NAME="patient-intake-ui"
    CONTAINER_NAME="ui"
    ;;
  *)
    echo "ERROR: component must be 'api' or 'ui'."
    echo "Usage: bash app_k8_deployment/deployment-lifecycle/repush-application-image.sh api 1.0.0"
    exit 1
    ;;
esac

echo "Component: ${TARGET_COMPONENT}"
echo "Image:     ${IMAGE}"

# ---------------------------------------------------------------------------
# Stage 2.0: Build Image
# Purpose: Recreate the selected runtime artifact from local source.
# Expected output: docker build succeeds for the selected component.
# ---------------------------------------------------------------------------
section "Stage 2.0: Build Image"

run_cmd docker build --tag "${IMAGE}" "${CONTEXT_DIR}"

# ---------------------------------------------------------------------------
# Stage 3.0: Load Image into kind
# Purpose: Replace the image copy available to kind nodes.
# Expected output: kind load completes successfully.
# ---------------------------------------------------------------------------
section "Stage 3.0: Load Image into kind"

run_cmd kind load docker-image "${IMAGE}" --name "${KIND_CLUSTER_NAME}"

# ---------------------------------------------------------------------------
# Stage 4.0: Restart Deployment
# Purpose: Same-tag rebuilds need an explicit restart so pods pick up new bytes.
# Expected output: pod template changes through rollout restart.
# ---------------------------------------------------------------------------
section "Stage 4.0: Restart Deployment"

echo "ENTERPRISE EMPHASIS: Same-tag repush is common in local labs but discouraged in production. Enterprise pipelines prefer immutable tags."
run_cmd kubectl set image "deployment/${DEPLOYMENT_NAME}" \
  "${CONTAINER_NAME}=${IMAGE}" \
  -n "${NAMESPACE}"
run_cmd kubectl rollout restart "deployment/${DEPLOYMENT_NAME}" -n "${NAMESPACE}"

# ---------------------------------------------------------------------------
# Stage 5.0: Verify Rollout
# Purpose: Wait for Kubernetes to replace pods and pass readiness checks.
# Expected output: rollout status succeeds.
# ---------------------------------------------------------------------------
section "Stage 5.0: Verify Rollout"

run_cmd kubectl rollout status "deployment/${DEPLOYMENT_NAME}" -n "${NAMESPACE}" --timeout=180s
run_cmd kubectl get pods -n "${NAMESPACE}" -l "app=${DEPLOYMENT_NAME}" -o wide

