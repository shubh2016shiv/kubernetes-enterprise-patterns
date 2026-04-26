#!/usr/bin/env bash
# =============================================================================
# FILE: 01-cluster-setup/destroy-cluster_3.sh
# PURPOSE: Cleanly tear down the local Kubernetes cluster.
#
# WHEN TO USE THIS:
#   - Recreating a cluster from scratch (fresh slate)
#   - Freeing RAM/CPU when not using Kubernetes
#   - Simulating cluster decommission (enterprise lifecycle management)
#
# WHAT GETS DELETED:
#   - All Docker containers running as cluster nodes
#   - The cluster's entry in ~/.kube/config
#   - All namespaces, pods, services, deployments — everything
#
# WHAT IS PRESERVED:
#   - Your Docker images (kindest/node stays cached locally)
#   - Other cluster contexts in your kubeconfig (if any)
#   - Your YAML manifest files (they're just files on disk)
#
# ENTERPRISE EQUIVALENT:
#   Deleting an EKS/GKE/AKS cluster is a serious, often irreversible action
#   in production. It would require approval workflows, backup verification,
#   and runbooks. Here it's trivial and intentional — that's the beauty of
#   local development environments.
# =============================================================================

set -e
set -u
set -o pipefail

# CAN BE CHANGED: Must match CLUSTER_NAME in create-cluster_1.sh and verify-cluster_2.sh,
# and the name field in kind-cluster-config.yaml. Example: `ml-inference-dev`.
# CONFIGURATION EXPLANATION `local-enterprise-dev` is the kind cluster name. kind also creates the kubectl
# context `kind-local-enterprise-dev`, so this value must match
# kind-cluster-config.yaml or this script may deleted a different local cluster than
# the learner expects.
CLUSTER_NAME="local-enterprise-dev"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
RESET='\033[0m'

echo ""
echo -e "${YELLOW}${BOLD}╔═══════════════════════════════════════════════════════╗${RESET}"
echo -e "${YELLOW}${BOLD}║        Destroying cluster: ${CLUSTER_NAME}  ║${RESET}"
echo -e "${YELLOW}${BOLD}╚═══════════════════════════════════════════════════════╝${RESET}"

# ─── CONFIRM CLUSTER EXISTS ───────────────────────────────────────────────────
# Attempting to delete a non-existent cluster produces an error.
# Check first to provide a meaningful message instead of a confusing stack trace.
if ! kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  echo -e "  ${YELLOW}Cluster '${CLUSTER_NAME}' does not exist. Nothing to destroy.${RESET}"
  exit 0
fi

echo ""
echo -e "  ${RED}This will delete all workloads and cluster state.${RESET}"
echo -e "  ${RED}Your YAML files are safe (they live on disk, not in the cluster).${RESET}"
echo ""

# ─── SAFETY PROMPT ────────────────────────────────────────────────────────────
# Even in dev environments, a confirmation prompt is good practice.
# It teaches the muscle memory needed when working with production clusters.
# In automated CI/CD pipelines, you'd pass --yes flag to bypass this.
read -r -p "  Are you sure? Type 'yes' to confirm: " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
  echo -e "  ${GREEN}Aborted. Cluster is intact.${RESET}"
  exit 0
fi

echo ""
echo -e "  Deleting cluster '${CLUSTER_NAME}'..."

# kind delete cluster:
#   - Stops and removes all Docker containers (nodes)
#   - Removes the cluster from ~/.kube/config
#   - Cleans up any temporary networking resources kind created
kind delete cluster --name "${CLUSTER_NAME}"

echo ""
echo -e "  ${GREEN}✓ Cluster '${CLUSTER_NAME}' destroyed.${RESET}"
echo ""

# ─── SHOW REMAINING CONTEXTS ──────────────────────────────────────────────────
# After deletion, show remaining kubectl contexts.
# This reinforces the concept of multi-cluster management.
echo -e "  Remaining kubectl contexts:"
kubectl config get-contexts 2>/dev/null || echo "  (none — kubeconfig is empty)"

echo ""
echo -e "  ${GREEN}To recreate: bash 01-cluster-setup/create-cluster_1.sh${RESET}"
echo ""
