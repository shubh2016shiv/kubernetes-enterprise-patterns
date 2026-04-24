#!/usr/bin/env bash
# =============================================================================
# FILE:    build-application-images.sh
# PURPOSE: Build the frontend and backend container images for the 3-tier app.
# USAGE:   bash app_k8_deployment/deployment-lifecycle/build-application-images.sh
# WHEN:    Run before loading images into kind or deploying the application.
# PREREQS: Docker Desktop is running with WSL2 integration enabled.
# OUTPUT:  Local images patient-record-api:1.0.0 and patient-intake-ui:1.0.0.
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# SCRIPT FLOW
#
# Stage 1: Preflight Checks
#   - Verify docker is installed and the daemon is reachable.
#
# Stage 2: Build Backend Image
#   - Build the FastAPI application image.
#
# Stage 3: Build Frontend Image
#   - Build the nginx/static UI image.
#
# Stage 4: Inspect Local Images
#   - Show the built tags and sizes.
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODULE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
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
# Purpose: Fail before any build work if Docker is unavailable.
# Expected input: Docker Desktop running on Windows with WSL2 integration.
# Expected output: docker info succeeds.
# ---------------------------------------------------------------------------
section "Stage 1.0: Preflight Checks"

run_cmd docker version --format "Client={{.Client.Version}} Server={{.Server.Version}}"
run_cmd docker info --format "DockerRootDir={{.DockerRootDir}} StorageDriver={{.Driver}}"

# ---------------------------------------------------------------------------
# Stage 2.0: Build Backend Image
# Purpose: Package the FastAPI backend as an immutable runtime artifact.
# Expected input: application-source/patient-record-api contains Dockerfile.
# Expected output: docker build completes and tags ${API_IMAGE}.
# ---------------------------------------------------------------------------
section "Stage 2.0: Build Backend Image"

echo "ENTERPRISE EMPHASIS: CI normally builds this image from a clean commit, scans it, signs it, and pushes it to a registry."
run_cmd docker build \
  --tag "${API_IMAGE}" \
  "${MODULE_DIR}/application-source/patient-record-api"

# Expected output:
#   Successfully built <image-id>
#   Successfully tagged patient-record-api:1.0.0

# ---------------------------------------------------------------------------
# Stage 3.0: Build Frontend Image
# Purpose: Package the patient intake UI and nginx reverse proxy.
# Expected input: application-source/patient-intake-ui contains Dockerfile.
# Expected output: docker build completes and tags ${UI_IMAGE}.
# ---------------------------------------------------------------------------
section "Stage 3.0: Build Frontend Image"

echo "ENTERPRISE EMPHASIS: Frontend images also go through versioning, scanning, and promotion; they are not informal static files."
run_cmd docker build \
  --tag "${UI_IMAGE}" \
  "${MODULE_DIR}/application-source/patient-intake-ui"

# Expected output:
#   Successfully built <image-id>
#   Successfully tagged patient-intake-ui:1.0.0

# ---------------------------------------------------------------------------
# Stage 4.0: Inspect Local Images
# Purpose: Confirm the tags exist before loading them into kind.
# Expected input: Both build steps succeeded.
# Expected output: docker image ls shows both images.
# ---------------------------------------------------------------------------
section "Stage 4.0: Inspect Local Images"

run_cmd docker image ls patient-record-api
run_cmd docker image ls patient-intake-ui

echo "Next step:"
echo "  bash app_k8_deployment/deployment-lifecycle/load-images-into-kind.sh"
