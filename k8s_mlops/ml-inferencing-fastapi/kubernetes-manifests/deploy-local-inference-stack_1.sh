#!/usr/bin/env bash
# =============================================================================
# FILE:    deploy-local-inference-stack_1.sh
# PURPOSE: One-command local path that prepares the kind cluster and then
#          applies the FastAPI inference stack.
# USAGE:   From WSL2, inside kubernetes-manifests/:
#            bash deploy-local-inference-stack_1.sh
# WHEN:    Use this when starting from the inference module and you want the
#          least-friction local setup path.
# PREREQS: Docker Desktop running, MLflow running, approved model rendered into
#          02-inference-configmap.yaml, and inference image loaded into kind.
# OUTPUT:  Cluster exists and is verified, then inference manifests are applied.
# =============================================================================

set -euo pipefail

# ┌─────────────────────────────────────────────────────────────────────┐
# │                    SCRIPT FLOW                                       │
# │                                                                      │
# │  Stage 1: Resolve Paths and Cluster Name                             │
# │      └── Make the local cluster name explicit and easy to audit      │
# │                                                                      │
# │  Stage 2: Run Platform Prerequisites                                 │
# │      └── Reuse setup/00-prerequisites/check-prerequisites.sh         │
# │                                                                      │
# │  Stage 3: Create or Reuse kind Cluster                               │
# │      └── Reuse setup/01-cluster-setup/create-cluster.sh              │
# │                                                                      │
# │  Stage 4: Verify Cluster Health                                      │
# │      └── Reuse setup/01-cluster-setup/verify-cluster.sh              │
# │                                                                      │
# │  Stage 5: Apply Inference Stack                                      │
# │      └── Run check-cluster-prerequisites_2.sh, then script _3        │
# └─────────────────────────────────────────────────────────────────────┘

# ENTERPRISE EMPHASIS: The cluster name is a first-class variable because the
# Kubernetes context, kind cluster, and local container image loading all depend
# on the same value. The current setup module is intentionally standardized on
# local-enterprise-dev. If a teammate changes this name in one place but not the
# others, they may deploy to the wrong cluster or fail to find the image.
# CAN BE CHANGED: Set this from your shell to choose a kind cluster name, for
# example `export LOCAL_KIND_CLUSTER_NAME=mlops-dev`. Important: this wrapper
# currently accepts only `local-enterprise-dev` until the setup cluster config
# and setup scripts are changed to the same new name.
LOCAL_KIND_CLUSTER_NAME="${LOCAL_KIND_CLUSTER_NAME:-local-enterprise-dev}"
# CAN BE CHANGED: Derived from LOCAL_KIND_CLUSTER_NAME. Do not edit directly;
# change LOCAL_KIND_CLUSTER_NAME instead. Example result: `kind-mlops-dev`.
EXPECTED_CONTEXT="kind-${LOCAL_KIND_CLUSTER_NAME}"

# CAN BE CHANGED: These resolved paths should normally stay automatic. Change
# only if the repository layout moves; example setup path:
# `/mnt/d/.../kubernetes_architure/setup`.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
SETUP_DIR="${REPO_ROOT}/setup"
PREREQUISITES_SCRIPT="${SETUP_DIR}/00-prerequisites/check-prerequisites.sh"
CREATE_CLUSTER_SCRIPT="${SETUP_DIR}/01-cluster-setup/create-cluster.sh"
VERIFY_CLUSTER_SCRIPT="${SETUP_DIR}/01-cluster-setup/verify-cluster.sh"
CHECK_INFERENCE_CLUSTER_SCRIPT="${SCRIPT_DIR}/check-cluster-prerequisites_2.sh"
APPLY_INFERENCE_STACK_SCRIPT="${SCRIPT_DIR}/apply-inference-stack_3.sh"

print_stage() {
  local message="$1"
  printf '\n%s\n' "========================================================"
  printf '%s\n' "$message"
  printf '%s\n' "========================================================"
}

require_file() {
  local file_path="$1"
  local description="$2"

  if [[ ! -f "${file_path}" ]]; then
    echo "ERROR: Missing ${description}: ${file_path}"
    echo "Fix: confirm you are running inside the full kubernetes_architure repository."
    exit 1
  fi
}

run_bash_script() {
  local script_path="$1"
  local script_label="$2"

  echo "Running: ${script_label}"
  echo "Path:    ${script_path}"
  bash "${script_path}"
}

# ─────────────────────────────────────────────────────────
# Stage 1.0: Resolve Paths and Cluster Name
# Purpose: Make the wrapper safe to run from any current working directory and
#          make the local kind cluster identity impossible to miss.
# Expected input: This script lives in kubernetes-manifests/.
# Expected output: All dependent script paths are resolved.
# ─────────────────────────────────────────────────────────
print_stage "Stage 1.0: Resolving local deployment plan"

echo "Repository root: ${REPO_ROOT}"
echo "Inference manifest directory: ${SCRIPT_DIR}"
echo "LOCAL_KIND_CLUSTER_NAME: ${LOCAL_KIND_CLUSTER_NAME}"
echo "Expected kubectl context: ${EXPECTED_CONTEXT}"
echo
echo "Name rule:"
echo "  The setup/create-cluster.sh script is idempotent for the same cluster name."
echo "  If '${LOCAL_KIND_CLUSTER_NAME}' already exists, running it again should not"
echo "  recreate the cluster; it should reuse the existing local platform."

if [[ "${LOCAL_KIND_CLUSTER_NAME}" != "local-enterprise-dev" ]]; then
  echo
  echo "ERROR: This wrapper currently supports only LOCAL_KIND_CLUSTER_NAME=local-enterprise-dev."
  echo "Why: setup/01-cluster-setup/create-cluster.sh and kind-cluster-config.yaml"
  echo "are standardized on that cluster name."
  echo
  echo "Fix: unset LOCAL_KIND_CLUSTER_NAME or set it back explicitly:"
  echo "  export LOCAL_KIND_CLUSTER_NAME=local-enterprise-dev"
  exit 1
fi

require_file "${PREREQUISITES_SCRIPT}" "platform prerequisite script"
require_file "${CREATE_CLUSTER_SCRIPT}" "kind cluster creation script"
require_file "${VERIFY_CLUSTER_SCRIPT}" "kind cluster verification script"
require_file "${CHECK_INFERENCE_CLUSTER_SCRIPT}" "inference cluster prerequisite script"
require_file "${APPLY_INFERENCE_STACK_SCRIPT}" "inference apply script"

# ─────────────────────────────────────────────────────────
# Stage 2.0: Run Platform Prerequisites
# Purpose: Check Docker, kind, kubectl, and local machine readiness before
#          touching the cluster.
# Expected input: Docker Desktop is running with WSL2 integration enabled.
# Expected output: Prerequisite checks pass or fail with setup-specific guidance.
# ─────────────────────────────────────────────────────────
print_stage "Stage 2.0: Running platform prerequisite checks"

run_bash_script "${PREREQUISITES_SCRIPT}" "setup/00-prerequisites/check-prerequisites.sh"

# ─────────────────────────────────────────────────────────
# Stage 3.0: Create or Reuse kind Cluster
# Purpose: Reuse the canonical setup script instead of copying cluster manifests
#          into the inference module.
# Expected input: kind is installed and Docker Desktop is running.
# Expected output: Cluster '${LOCAL_KIND_CLUSTER_NAME}' exists.
# ─────────────────────────────────────────────────────────
print_stage "Stage 3.0: Creating or reusing the local kind cluster"

if command -v kind >/dev/null 2>&1 && kind get clusters | grep -qx "${LOCAL_KIND_CLUSTER_NAME}"; then
  echo "Cluster '${LOCAL_KIND_CLUSTER_NAME}' already exists."
  echo "Still running create-cluster.sh because it is designed to be idempotent."
else
  echo "Cluster '${LOCAL_KIND_CLUSTER_NAME}' does not exist yet."
  echo "Running create-cluster.sh to create the local enterprise-style cluster."
fi

run_bash_script "${CREATE_CLUSTER_SCRIPT}" "setup/01-cluster-setup/create-cluster.sh"

# ─────────────────────────────────────────────────────────
# Stage 3.1: Set kubectl Context
# Purpose: Avoid the exact failure mode where kubectl has no current context.
# Expected input: kind context exists after create-cluster.sh.
# Expected output: kubectl points at kind-local-enterprise-dev by default.
# ─────────────────────────────────────────────────────────
print_stage "Stage 3.1: Setting kubectl context"

if ! kubectl config get-contexts -o name | grep -qx "${EXPECTED_CONTEXT}"; then
  echo "ERROR: Expected kubectl context '${EXPECTED_CONTEXT}' was not found."
  echo "Diagnostic: kubectl config get-contexts"
  exit 1
fi

kubectl config use-context "${EXPECTED_CONTEXT}"
echo "kubectl context set to ${EXPECTED_CONTEXT}."

# ─────────────────────────────────────────────────────────
# Stage 4.0: Verify Cluster Health
# Purpose: Confirm nodes and core Kubernetes system pods are healthy before
#          deploying the inference workload.
# Expected input: Cluster exists and kubectl context is set.
# Expected output: setup/verify-cluster.sh passes.
# ─────────────────────────────────────────────────────────
print_stage "Stage 4.0: Verifying cluster health"

run_bash_script "${VERIFY_CLUSTER_SCRIPT}" "setup/01-cluster-setup/verify-cluster.sh"

# ─────────────────────────────────────────────────────────
# Stage 5.0: Apply Inference Stack
# Purpose: Now that the platform exists, hand off to the inference-owned scripts.
# Expected input: ConfigMap has resolved MODEL_URI and image is loaded into kind.
# Expected output: Namespace, ConfigMap, ServiceAccount, Secret, Deployment,
#                  Service, and HorizontalPodAutoscaler are applied.
# ─────────────────────────────────────────────────────────
print_stage "Stage 5.0: Checking inference cluster prerequisites"

run_bash_script "${CHECK_INFERENCE_CLUSTER_SCRIPT}" "kubernetes-manifests/check-cluster-prerequisites_2.sh"

print_stage "Stage 5.1: Applying inference Kubernetes manifests"

run_bash_script "${APPLY_INFERENCE_STACK_SCRIPT}" "kubernetes-manifests/apply-inference-stack_3.sh"

echo
echo "Local inference deployment flow completed."
echo "Recommended next checks:"
echo "  bash verify-inference-stack_5.sh"
echo "  bash test-prediction_4.sh"
