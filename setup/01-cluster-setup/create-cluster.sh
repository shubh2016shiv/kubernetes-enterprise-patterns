#!/usr/bin/env bash
# =============================================================================
# FILE: 01-cluster-setup/create-cluster.sh
# PURPOSE: Bootstrap a production-topology local Kubernetes cluster using kind.
#
# WHAT THIS SCRIPT DOES:
#   1. Validates prerequisites (Docker running, kind installed)
#   2. Checks if cluster already exists (idempotent — safe to run twice)
#   3. Creates the cluster from the YAML config
#   4. Verifies all nodes are Ready
#   5. Labels nodes for realistic scheduling simulation
#   6. Shows you what was created
#
# ENTERPRISE PRINCIPLE — IDEMPOTENCY:
#   A professional script should produce the SAME result whether run once or
#   ten times. It should check state before acting, never blindly re-create.
#   This is the foundation of Infrastructure-as-Code (IaC) thinking.
#
# HOW TO RUN:
#   bash 01-cluster-setup/create-cluster.sh
# =============================================================================

set -e
set -u
set -o pipefail

# ┌──────────────────────────────────────────────────────────────────────────┐
# │                    CLUSTER CREATION FLOW                                 │
# │                                                                          │
# │  Stage 1: Pre-flight Checks                                              │
# │      ├── Docker daemon is running?                                       │
# │      ├── kind binary on PATH?                                            │
# │      ├── kubectl binary on PATH?                                         │
# │      └── kind-cluster-config.yaml exists?                                │
# │                                                                          │
# │  Stage 2: Idempotency Check                                              │
# │      ├── Does cluster "local-enterprise-dev" already exist?              │
# │      │   YES → skip creation, update kubeconfig context, continue        │
# │      └── NO  → proceed to cluster creation                               │
# │                                                                          │
# │  Stage 3: Cluster Creation (kind create cluster)                         │
# │      ├── kind pulls kindest/node image (~700 MB, cached after first run) │
# │      ├── Creates 3 Docker containers (1 control-plane + 2 workers)       │
# │      ├── Runs kubeadm init → bootstraps API server, etcd, scheduler      │
# │      ├── Runs kubeadm join → workers join the cluster                    │
# │      └── Installs kindnet CNI → enables pod-to-pod networking            │
# │                                                                          │
# │  Stage 4: Node Readiness Wait                                            │
# │      └── Poll until all 3 nodes report Status=Ready                      │
# │                                                                          │
# │  Stage 5: Post-creation Summary                                          │
# │      ├── Print kubectl context, nodes, system pods, cluster-info         │
# │      └── Print "what to do next" guide                                   │
# │                                                                          │
# │  MACHINE CONTEXT:                                                        │
# │    Windows 11 / WSL2 Ubuntu 22.04 / Docker Desktop                       │
# │    16 GB RAM (8 GB allocated to Docker) / RTX 2060 6 GB                  │
# │    Expected total creation time: 60–120 seconds                          │
# │                                                                          │
# │  ENTERPRISE TRANSLATION:                                                 │
# │    This script ≈ Terraform + eksctl for AWS EKS cluster creation.        │
# │    On EKS: `eksctl create cluster --config-file cluster.yaml`            │
# │    On GKE: `gcloud container clusters create ...`                        │
# │    On AKS: `az aks create ...`                                           │
# │    The kubectl commands you run after creation are IDENTICAL.            │
# └──────────────────────────────────────────────────────────────────────────┘

# ─── CONFIGURATION ────────────────────────────────────────────────────────────
# Define all tuneable values at the top of the script (never hardcode inline).
# In enterprise, these would come from environment variables or a config file.

# Cluster name MUST match the "name:" field in kind-cluster-config.yaml.
# If they differ, kind will create a SECOND cluster with a different name.
CLUSTER_NAME="local-enterprise-dev"

# Path to the cluster configuration YAML.
# We use "$(dirname "$0")" to get the directory containing THIS script,
# making the path relative regardless of where you run it from.
CLUSTER_CONFIG="$(dirname "$0")/kind-cluster-config.yaml"

# How long to wait for nodes to reach "Ready" state after creation.
# 120 seconds is generous — typically takes 30-60 seconds.
NODE_READY_TIMEOUT=120

# ─── COLORS ───────────────────────────────────────────────────────────────────
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ─── HELPER FUNCTIONS ─────────────────────────────────────────────────────────

log_step() {
  echo ""
  echo -e "${BLUE}${BOLD}[STEP]${RESET} $1"
}

log_info() {
  echo -e "  ${CYAN}→${RESET} $1"
}

log_success() {
  echo -e "  ${GREEN}✓${RESET} $1"
}

log_warn() {
  echo -e "  ${YELLOW}⚠${RESET} $1"
}

log_error() {
  echo -e "  ${RED}✗${RESET} $1"
}

# ─── PRE-FLIGHT CHECKS ────────────────────────────────────────────────────────
# Before doing anything irreversible, validate that dependencies exist.
# This is called "pre-flight" — borrowed from aviation checklists.

log_step "Pre-flight checks"

# 1. Docker must be running
# `docker info` exits 0 if Docker daemon is reachable, non-zero if not.
if ! docker info &>/dev/null; then
  log_error "Docker daemon is not running."
  log_info  "On Windows: Open Docker Desktop application first."
  log_info  "On Linux: sudo systemctl start docker"
  exit 1
fi
log_success "Docker daemon is running"

# 2. kind binary must exist
if ! command -v kind &>/dev/null; then
  log_error "kind is not installed. See 00-prerequisites/install-guide.md"
  exit 1
fi
KIND_VERSION=$(kind version)
log_success "kind is installed: ${KIND_VERSION}"

# 3. kubectl binary must exist
if ! command -v kubectl &>/dev/null; then
  log_error "kubectl is not installed. See 00-prerequisites/install-guide.md"
  exit 1
fi
log_success "kubectl is installed: $(kubectl version --client --short 2>/dev/null | head -1)"

# 4. Config file must exist
if [[ ! -f "$CLUSTER_CONFIG" ]]; then
  log_error "Cluster config not found: ${CLUSTER_CONFIG}"
  log_info  "Run this script from the 'setup/' directory."
  exit 1
fi
log_success "Cluster config found: ${CLUSTER_CONFIG}"

# ─── CLUSTER CREATION ─────────────────────────────────────────────────────────

log_step "Checking if cluster '${CLUSTER_NAME}' already exists"

# `kind get clusters` lists all existing clusters by name.
# We pipe to grep to check if OUR specific cluster already exists.
# This is the idempotency check — if it exists, we skip creation.
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  log_warn "Cluster '${CLUSTER_NAME}' already exists."
  log_info  "To recreate: bash 01-cluster-setup/destroy-cluster.sh && bash 01-cluster-setup/create-cluster.sh"
  log_info  "Continuing with existing cluster..."

  # Even if cluster exists, re-configure kubectl context to point at it.
  # (In case you switched to a different cluster context in the meantime)
  kind export kubeconfig --name "${CLUSTER_NAME}"
  log_success "kubectl context updated to '${CLUSTER_NAME}'"

else
  log_step "Creating cluster '${CLUSTER_NAME}'"
  log_info  "This takes 60-120 seconds. kind is:"
  log_info  "  1. Pulling node image (kindest/node:v1.30.6)"
  log_info  "  2. Creating Docker containers for each node"
  log_info  "  3. Running kubeadm to bootstrap the control plane"
  log_info  "  4. Joining worker nodes to the cluster"
  log_info  "  5. Installing the CNI network plugin (kindnet)"
  echo ""

  # The actual cluster creation command.
  # --config: Path to our cluster topology YAML
  # --name:   Cluster name (overrides the name in YAML if both are set;
  #           keep them consistent to avoid confusion)
  # --wait:   Wait until ALL nodes reach Ready status before returning
  #           This makes the script blocking (good for automation)
  kind create cluster \
    --config "${CLUSTER_CONFIG}" \
    --name "${CLUSTER_NAME}" \
    --wait "${NODE_READY_TIMEOUT}s"

  log_success "Cluster '${CLUSTER_NAME}' created!"

  # After cluster creation, kind automatically writes credentials to ~/.kube/config
  # and switches your kubectl context to the new cluster.
  # Let's explicitly export to be certain:
  kind export kubeconfig --name "${CLUSTER_NAME}"
  log_success "kubectl context set to 'kind-${CLUSTER_NAME}'"
fi

# ─── VERIFY NODES ─────────────────────────────────────────────────────────────
# After creation, confirm that all nodes report "Ready" status.
# A node is "Ready" when:
#   - kubelet is running and reporting heartbeats to the API server
#   - The CNI network plugin has configured networking on the node
#   - The node passes all health checks (disk pressure, memory pressure, etc.)
#
# WHAT NODE STATUS MEANS (interview talking points):
#   Ready         → Node is healthy, can receive pods
#   NotReady      → Node exists but something is wrong (check: kubectl describe node)
#   SchedulingDisabled → Node is cordoned (no NEW pods, existing pods stay)
#   Unknown       → Control plane hasn't heard from node in >40 seconds
#                   (node_monitor_grace_period in kube-controller-manager)

log_step "Verifying node status"
echo ""

# `kubectl get nodes` shows all nodes in the cluster with their status.
# --output=wide adds extra columns: internal IP, OS image, container runtime
kubectl get nodes --output=wide

echo ""

# Wait for all nodes to be Ready with a timeout loop
log_info "Waiting for all nodes to be Ready..."
READY_TIMEOUT=120
ELAPSED=0
INTERVAL=5

while true; do
  # Count nodes that are NOT in Ready state
  # -o jsonpath extracts just the "Ready" condition status for all nodes
  # grep -c counts matching lines (nodes not yet ready)
  NOT_READY=$(kubectl get nodes -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' \
    | tr ' ' '\n' | grep -c "False\|Unknown" || true)

  if [[ "$NOT_READY" -eq 0 ]]; then
    log_success "All nodes are Ready!"
    break
  fi

  if [[ $ELAPSED -ge $READY_TIMEOUT ]]; then
    log_error "Timeout: ${NOT_READY} node(s) still not Ready after ${READY_TIMEOUT}s"
    log_info  "Debug: kubectl describe nodes | grep -A5 'Conditions:'"
    exit 1
  fi

  log_info "  ${NOT_READY} node(s) not ready yet... waiting ${INTERVAL}s (${ELAPSED}/${READY_TIMEOUT}s)"
  sleep $INTERVAL
  ELAPSED=$((ELAPSED + INTERVAL))
done

# ─── POST-CREATION: SHOW CLUSTER DETAILS ──────────────────────────────────────
# Give the engineer a clear picture of what was created.
# In enterprise, this summary would go into a deployment log / audit trail.

log_step "Cluster Summary"
echo ""

echo -e "${BOLD}  Context:${RESET}"
# Show the current kubectl context (which cluster kubectl commands go to)
# ENTERPRISE CONCEPT: "context" = cluster + user + namespace triplet
# Switching context = switching which cluster you're talking to
kubectl config current-context

echo ""
echo -e "${BOLD}  Nodes:${RESET}"
kubectl get nodes -o wide

echo ""
echo -e "${BOLD}  System Pods (Control Plane Components):${RESET}"
# -n kube-system: The kube-system namespace contains all Kubernetes system components
# These are the pods that make K8s work:
#   coredns         → DNS server for service discovery (pods look up services by name)
#   etcd            → The cluster database
#   kube-apiserver  → The REST API frontend
#   kube-controller-manager → Reconciliation loops
#   kube-scheduler  → Pod placement decisions
#   kube-proxy      → Service networking (iptables rules)
#   kindnet         → CNI plugin (pod networking)
kubectl get pods --namespace kube-system

echo ""
echo -e "${BOLD}  Cluster Info:${RESET}"
# Shows API server address and CoreDNS address
kubectl cluster-info

# ─── KUBECONFIG CONTEXT INFO ──────────────────────────────────────────────────
# Show all available contexts so the engineer understands how multi-cluster works.
echo ""
echo -e "${BOLD}  All kubectl Contexts:${RESET}"
# Each row = one cluster you can talk to
# CURRENT column (*) = the active context (where kubectl commands go)
kubectl config get-contexts

# ─── NEXT STEPS ───────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}${BOLD}════════════════════════════════════════════════════════${RESET}"
echo -e "${CYAN}${BOLD}  ✓ Cluster is ready!${RESET}"
echo -e "${CYAN}${BOLD}════════════════════════════════════════════════════════${RESET}"
echo ""
echo -e "  ${BOLD}Explore your cluster:${RESET}"
echo -e "  ${YELLOW}kubectl get nodes${RESET}              — List all nodes"
echo -e "  ${YELLOW}kubectl get pods -A${RESET}            — List ALL pods (all namespaces)"
echo -e "  ${YELLOW}kubectl get namespaces${RESET}         — List namespaces"
echo -e "  ${YELLOW}kubectl cluster-info${RESET}           — API server address"
echo -e "  ${YELLOW}kubectl api-resources${RESET}          — EVERY resource type K8s knows about"
echo ""
echo -e "  ${BOLD}Next step:${RESET}"
echo -e "  ${CYAN}bash 02-namespaces/apply-namespaces.sh${RESET}"
echo ""
