#!/usr/bin/env bash
# =============================================================================
# FILE:    check-cluster-prerequisites_2.sh
# PURPOSE: Verify the local Kubernetes platform is ready before applying the
#          FastAPI inference manifests.
# USAGE:   From WSL2, inside kubernetes-manifests/:
#            bash check-cluster-prerequisites_2.sh
# WHEN:    Run this before apply-inference-stack_3.sh if you are not sure whether
#          the kind cluster exists, kubectl is pointed at it, or nodes are Ready.
# PREREQS: Docker Desktop running, kind installed, kubectl installed.
# OUTPUT:  Clear pass/fail checks and the exact setup commands to run if the
#          local cluster is missing.
# =============================================================================

set -euo pipefail

# ┌─────────────────────────────────────────────────────────────────────┐
# │                    SCRIPT FLOW                                       │
# │                                                                      │
# │  Stage 1: Explain module boundary                                    │
# │      └── Inference owns serving resources, not cluster creation      │
# │                                                                      │
# │  Stage 2: Check local tools                                          │
# │      └── Verify kubectl and kind are installed                       │
# │                                                                      │
# │  Stage 3: Check cluster context                                      │
# │      └── Verify kubectl points at kind-local-enterprise-dev          │
# │                                                                      │
# │  Stage 4: Check node readiness                                       │
# │      └── Verify Kubernetes has Ready nodes before applying manifests │
# └─────────────────────────────────────────────────────────────────────┘

# CAN BE CHANGED: Set `KIND_CLUSTER_NAME` before running this script to check a
# different kind cluster. Example: `KIND_CLUSTER_NAME=mlops-dev bash check-cluster-prerequisites_2.sh`.
EXPECTED_KIND_CLUSTER="${KIND_CLUSTER_NAME:-local-enterprise-dev}"
# CAN BE CHANGED: Derived from EXPECTED_KIND_CLUSTER. Do not edit directly;
# change KIND_CLUSTER_NAME instead. Example result: `kind-mlops-dev`.
EXPECTED_CONTEXT="kind-${EXPECTED_KIND_CLUSTER}"
# CAN BE CHANGED: Update only if the repository moves to a different WSL2 path.
# Example: `/mnt/d/Generative AI Portfolio Projects/kubernetes_architure`.
REPO_ROOT="/mnt/d/Generative AI Portfolio Projects/kubernetes_architure"

print_stage() {
  local message="$1"
  printf '\n%s\n' "========================================================"
  printf '%s\n' "$message"
  printf '%s\n' "========================================================"
}

fail_with_setup_commands() {
  local reason="$1"

  echo "ERROR: ${reason}"
  echo
  echo "This inference module should not copy cluster setup manifests locally."
  echo "Cluster creation is a platform lifecycle concern owned by setup/."
  echo
  echo "Run the platform setup path from WSL2:"
  echo
  echo "  cd \"${REPO_ROOT}/setup/00-prerequisites\""
  echo "  bash check-prerequisites.sh"
  echo
  echo "  cd \"${REPO_ROOT}/setup/01-cluster-setup\""
  echo "  bash create-cluster.sh"
  echo "  bash verify-cluster.sh"
  echo
  echo "Then return here:"
  echo
  echo "  cd \"${REPO_ROOT}/k8s_mlops/ml-inferencing-fastapi/kubernetes-manifests\""
  echo "  bash check-cluster-prerequisites_2.sh"
  echo "  bash apply-inference-stack_3.sh"
  exit 1
}

# ─────────────────────────────────────────────────────────
# Stage 1.0: Explain Module Boundary
# Purpose: Keep the learning path clean. The inference module should explain
#          what it needs from the platform, not duplicate platform setup files.
# Expected input: A teammate may be starting from this folder first.
# Expected output: They understand where cluster setup lives.
# ─────────────────────────────────────────────────────────
print_stage "Stage 1.0: Confirming module boundary"

echo "This folder owns inference resources: Namespace, ConfigMap, ServiceAccount,"
echo "Secret placeholder, Deployment, Service, and HorizontalPodAutoscaler."
echo
echo "It does not own cluster creation, node lifecycle, Docker Desktop setup, or"
echo "kubectl installation. Those belong to setup/ so they stay reusable across"
echo "all Kubernetes and MLOps modules."

# ─────────────────────────────────────────────────────────
# Stage 2.0: Check Local Tools
# Purpose: Fail before running kubectl commands if required tools are missing.
# Expected input: kind and kubectl installed in WSL2.
# Expected output: Tool versions are visible.
# ─────────────────────────────────────────────────────────
print_stage "Stage 2.0: Checking local Kubernetes tools"

if ! command -v kubectl >/dev/null 2>&1; then
  fail_with_setup_commands "kubectl is not installed or not on PATH."
fi

if ! command -v kind >/dev/null 2>&1; then
  fail_with_setup_commands "kind is not installed or not on PATH."
fi

echo "kubectl: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
echo "kind: $(kind version)"

# ─────────────────────────────────────────────────────────
# Stage 3.0: Check kind Cluster and kubectl Context
# Purpose: Applying inference manifests without a reachable cluster creates
#          confusing errors for first-time readers.
# Expected input: kind cluster named local-enterprise-dev exists.
# Expected output: kubectl context points at kind-local-enterprise-dev.
# ─────────────────────────────────────────────────────────
print_stage "Stage 3.0: Checking kind cluster and kubectl context"

if ! kind get clusters | grep -qx "${EXPECTED_KIND_CLUSTER}"; then
  fail_with_setup_commands "kind cluster '${EXPECTED_KIND_CLUSTER}' does not exist."
fi

CURRENT_CONTEXT="$(kubectl config current-context 2>/dev/null || true)"
if [[ -z "${CURRENT_CONTEXT}" ]]; then
  fail_with_setup_commands "kubectl has no current context."
fi

echo "Current kubectl context: ${CURRENT_CONTEXT}"

if [[ "${CURRENT_CONTEXT}" != "${EXPECTED_CONTEXT}" ]]; then
  echo "WARNING: Expected context '${EXPECTED_CONTEXT}', but current context is '${CURRENT_CONTEXT}'."
  echo "Switching context for this local lab:"
  echo "  kubectl config use-context ${EXPECTED_CONTEXT}"
  kubectl config use-context "${EXPECTED_CONTEXT}"
fi

if ! kubectl cluster-info --request-timeout=5s >/dev/null 2>&1; then
  fail_with_setup_commands "Kubernetes API server is not reachable from kubectl."
fi

echo "Kubernetes API server is reachable."

# ─────────────────────────────────────────────────────────
# Stage 4.0: Check Node Readiness
# Purpose: Namespaces and Deployments can be created while nodes are unhealthy,
#          but pods will not schedule correctly. Catch that before deployment.
# Expected input: At least one Ready node.
# Expected output: Node table and Ready count.
# ─────────────────────────────────────────────────────────
print_stage "Stage 4.0: Checking node readiness"

kubectl get nodes -o wide

READY_NODES="$(kubectl get nodes --no-headers | awk '$2 == "Ready" { count++ } END { print count + 0 }')"
TOTAL_NODES="$(kubectl get nodes --no-headers | wc -l | tr -d ' ')"

if [[ "${READY_NODES}" -eq 0 ]]; then
  fail_with_setup_commands "No Kubernetes nodes are Ready."
fi

echo "Ready nodes: ${READY_NODES}/${TOTAL_NODES}"
echo
echo "Cluster prerequisite check passed."
echo "Next step:"
echo "  bash apply-inference-stack_3.sh"
