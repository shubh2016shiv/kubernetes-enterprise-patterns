#!/usr/bin/env bash
# =============================================================================
# FILE:    load-images-into-kind.sh
# PURPOSE: Copy locally built application images into the kind cluster nodes.
# USAGE:   bash app_k8_deployment/deployment-lifecycle/load-images-into-kind.sh
# WHEN:    Run after building images and before applying Kubernetes manifests.
# PREREQS: kind cluster `local-enterprise-dev` exists and images are built.
# OUTPUT:  kind nodes can run patient-record-api and patient-intake-ui images.
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# SCRIPT FLOW
#
# Stage 1: Preflight Checks
#   - Verify kind, docker, target cluster, and image tags exist.
#
# Stage 2: Load Backend Image
#   - Copy patient-record-api image into every kind node.
#
# Stage 3: Load Frontend Image
#   - Copy patient-intake-ui image into every kind node.
#
# Stage 4: Explain Enterprise Equivalent
#   - Translate local image loading to registry-based promotion.
# ---------------------------------------------------------------------------

KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-local-enterprise-dev}"
API_IMAGE="${API_IMAGE:-patient-record-api:1.0.0}"
UI_IMAGE="${UI_IMAGE:-patient-intake-ui:1.0.0}"

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
# Stage 1.0: Preflight Checks
# Purpose: Avoid confusing ImagePullBackOff errors later in Kubernetes.
# Expected input: kind cluster and local Docker images exist.
# Expected output: all checks pass.
# ---------------------------------------------------------------------------
section "Stage 1.0: Preflight Checks"

run_cmd kind version
run_cmd docker image inspect --format "Image={{.Id}} Tags={{.RepoTags}}" "${API_IMAGE}"
run_cmd docker image inspect --format "Image={{.Id}} Tags={{.RepoTags}}" "${UI_IMAGE}"

if ! kind get clusters | grep -qx "${KIND_CLUSTER_NAME}"; then
  echo "ERROR: kind cluster '${KIND_CLUSTER_NAME}' does not exist."
  echo "Run: bash setup/01-cluster-setup/create-cluster.sh"
  exit 1
fi

# ---------------------------------------------------------------------------
# Stage 2.0: Load Backend Image
# Purpose: Make the FastAPI image available to kind nodes without a registry.
# Expected output: kind reports the image was loaded.
# ---------------------------------------------------------------------------
section "Stage 2.0: Load Backend Image"

echo "ENTERPRISE EMPHASIS: kind image loading is a laptop shortcut. Enterprise clusters pull from a registry with auth, vulnerability policy, and immutable tags."
run_cmd kind load docker-image "${API_IMAGE}" --name "${KIND_CLUSTER_NAME}"

# ---------------------------------------------------------------------------
# Stage 3.0: Load Frontend Image
# Purpose: Make the UI image available to kind nodes without a registry.
# Expected output: kind reports the image was loaded.
# ---------------------------------------------------------------------------
section "Stage 3.0: Load Frontend Image"

run_cmd kind load docker-image "${UI_IMAGE}" --name "${KIND_CLUSTER_NAME}"

# ---------------------------------------------------------------------------
# Stage 4.0: Enterprise Equivalent
# Purpose: Connect the local action to CI/CD registry promotion.
# Expected output: Learner knows what this maps to in production.
# ---------------------------------------------------------------------------
section "Stage 4.0: Enterprise Equivalent"

cat <<'TEXT'
Local:
  docker build -> kind load docker-image -> Deployment uses imagePullPolicy IfNotPresent

Enterprise:
  CI build -> scan -> sign -> push to registry -> GitOps updates image tag -> cluster pulls from registry

Next step:
  bash app_k8_deployment/deployment-lifecycle/deploy-patient-record-system.sh
TEXT
