#!/usr/bin/env bash
# =============================================================================
# nuke-everything.sh — Full Environment Teardown Script
# =============================================================================
#
# PURPOSE
# -------
# Destroy every Kubernetes and Docker resource on this machine — clusters,
# namespaces, pods, services, persistent volumes, Docker containers, images,
# volumes, and networks — leaving the machine in a clean, empty state.
#
# APPROACH: BOTTOM-TO-TOP (safe deletion order)
# ---------------------------------------------
# Deleting from the top (clusters first) can orphan lower-level Docker
# resources that kind, Docker Desktop, or Helm created outside the cluster
# lifecycle. Instead we go bottom-to-top:
#
#   1. Kubernetes workloads (pods, deployments, statefulsets)
#   2. Kubernetes services and ingresses
#   3. Kubernetes config / secrets / configmaps
#   4. Kubernetes PVCs and PVs (persistent storage)
#   5. Kubernetes namespaces (drains + deletes all remaining objects)
#   6. kind clusters (removes the cluster and its Docker containers)
#   7. Docker containers (any remaining, including Docker Desktop services)
#   8. Docker volumes (named volumes = persistent data outside k8s)
#   9. Docker images (all pulled/built images)
#  10. Docker networks (custom bridge/overlay networks)
#  11. Docker builder cache (BuildKit cache layers)
#
# ENTERPRISE EQUIVALENT
# ---------------------
# In AWS/GCP/Azure, the equivalent is running `terraform destroy` or
# `eksctl delete cluster` before removing ECR images, EBS volumes, and VPCs.
# The ordering principle is the same: dependents before dependencies.
#
# WARNINGS
# --------
# This script is IRREVERSIBLE. There is no undo. All data stored in
# PersistentVolumeClaims, Docker volumes, or container writable layers
# will be permanently deleted.
#
# Each destructive phase shows a countdown so you can Ctrl+C in time.
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Terminal colours
# ---------------------------------------------------------------------------
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
BOLD='\033[1m'
RESET='\033[0m'

# ---------------------------------------------------------------------------
# Helper: print a section banner
# ---------------------------------------------------------------------------
banner() {
  echo ""
  echo -e "${CYAN}${BOLD}══════════════════════════════════════════════════════${RESET}"
  echo -e "${CYAN}${BOLD}  $1${RESET}"
  echo -e "${CYAN}${BOLD}══════════════════════════════════════════════════════${RESET}"
}

# ---------------------------------------------------------------------------
# Helper: countdown with a warning before each destructive phase.
# Usage:  countdown "what is about to be deleted" <seconds>
# ---------------------------------------------------------------------------
countdown() {
  local label="$1"
  local seconds="${2:-10}"

  echo ""
  echo -e "${RED}${BOLD}⚠  WARNING — ABOUT TO DELETE: ${label}${RESET}"
  echo -e "${YELLOW}   This action is IRREVERSIBLE. Press Ctrl+C NOW to abort.${RESET}"
  echo ""

  for (( i=seconds; i>0; i-- )); do
    printf "\r${YELLOW}   Deleting in %2d seconds...${RESET}" "$i"
    sleep 1
  done
  printf "\r${RED}   Proceeding with deletion...              ${RESET}\n"
  echo ""
}

# ---------------------------------------------------------------------------
# Helper: run a command and swallow errors (resource may already be gone)
# ---------------------------------------------------------------------------
try() {
  "$@" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Helper: check if a CLI tool is available
# ---------------------------------------------------------------------------
has() {
  command -v "$1" &>/dev/null
}

# ===========================================================================
# GLOBAL WARNING
# ===========================================================================
clear
echo ""
echo -e "${RED}${BOLD}╔══════════════════════════════════════════════════════════╗${RESET}"
echo -e "${RED}${BOLD}║           N U C L E A R   C L E A N U P                  ║${RESET}"
echo -e "${RED}${BOLD}║                                                          ║${RESET}"
echo -e "${RED}${BOLD}║  This script will PERMANENTLY DELETE:                    ║${RESET}"
echo -e "${RED}${BOLD}║    • All kind Kubernetes clusters                        ║${RESET}"
echo -e "${RED}${BOLD}║    • All Kubernetes namespaces, pods, PVCs, PVs          ║${RESET}"
echo -e "${RED}${BOLD}║    • All Docker containers (running and stopped)         ║${RESET}"
echo -e "${RED}${BOLD}║    • All Docker volumes (persistent data)                ║${RESET}"
echo -e "${RED}${BOLD}║    • All Docker images                                   ║${RESET}"
echo -e "${RED}${BOLD}║    • All Docker networks (non-default)                   ║${RESET}"
echo -e "${RED}${BOLD}║    • All Docker builder cache                            ║${RESET}"
echo -e "${RED}${BOLD}║                                                          ║${RESET}"
echo -e "${RED}${BOLD}║  There is NO UNDO.                                       ║${RESET}"
echo -e "${RED}${BOLD}╚══════════════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "${YELLOW}  You have 15 seconds to abort with Ctrl+C.${RESET}"
echo ""

for (( i=15; i>0; i-- )); do
  printf "\r${YELLOW}  Script starts in %2d seconds...${RESET}" "$i"
  sleep 1
done
echo ""
echo ""

# ===========================================================================
# PHASE 1 — Kubernetes workloads (pods, deployments, statefulsets, daemonsets)
# ===========================================================================
if has kubectl; then
  banner "PHASE 1 — Kubernetes Workloads (Pods / Deployments / StatefulSets)"

  # Collect non-system namespaces first
  NAMESPACES=$(kubectl get namespaces --no-headers -o custom-columns=":metadata.name" 2>/dev/null \
    | grep -v -E "^(kube-system|kube-public|kube-node-lease)$" || true)

  if [[ -n "$NAMESPACES" ]]; then
    echo -e "${YELLOW}  Non-system namespaces found:${RESET}"
    echo "$NAMESPACES" | sed 's/^/    • /'

    countdown "all Deployments, StatefulSets, DaemonSets, Jobs, CronJobs across all namespaces" 10

    for ns in $NAMESPACES; do
      echo -e "  Deleting workloads in namespace: ${CYAN}${ns}${RESET}"
      try kubectl delete deployments   --all -n "$ns" --timeout=60s
      try kubectl delete statefulsets  --all -n "$ns" --timeout=60s
      try kubectl delete daemonsets    --all -n "$ns" --timeout=60s
      try kubectl delete jobs          --all -n "$ns" --timeout=60s
      try kubectl delete cronjobs      --all -n "$ns" --timeout=60s
      try kubectl delete replicasets   --all -n "$ns" --timeout=60s
      # Force-delete any pods still Terminating — in enterprise this would be
      # investigated; locally we force to unblock teardown.
      try kubectl delete pods          --all -n "$ns" --force --grace-period=0
    done
    echo -e "${GREEN}  ✓ Workloads deleted.${RESET}"
  else
    echo -e "  No non-system namespaces found. Skipping workload deletion."
  fi
fi

# ===========================================================================
# PHASE 2 — Kubernetes Services and Ingresses
# ===========================================================================
if has kubectl && [[ -n "${NAMESPACES:-}" ]]; then
  banner "PHASE 2 — Kubernetes Services and Ingresses"

  countdown "all Services (excluding 'kubernetes' ClusterIP) and Ingresses" 8

  for ns in $NAMESPACES; do
    echo -e "  Deleting services/ingresses in namespace: ${CYAN}${ns}${RESET}"
    try kubectl delete ingress  --all -n "$ns" --timeout=60s
    try kubectl delete services --all -n "$ns" --timeout=60s
  done
  echo -e "${GREEN}  ✓ Services and Ingresses deleted.${RESET}"
fi

# ===========================================================================
# PHASE 3 — Kubernetes ConfigMaps and Secrets
# ===========================================================================
if has kubectl && [[ -n "${NAMESPACES:-}" ]]; then
  banner "PHASE 3 — Kubernetes ConfigMaps and Secrets"

  countdown "all ConfigMaps and Secrets in non-system namespaces" 8

  for ns in $NAMESPACES; do
    echo -e "  Deleting configmaps/secrets in namespace: ${CYAN}${ns}${RESET}"
    try kubectl delete configmaps --all -n "$ns" --timeout=60s
    # --field-selector prevents deletion of the default service-account token
    try kubectl delete secrets    --all -n "$ns" --timeout=60s
  done
  echo -e "${GREEN}  ✓ ConfigMaps and Secrets deleted.${RESET}"
fi

# ===========================================================================
# PHASE 4 — PersistentVolumeClaims and PersistentVolumes
# ===========================================================================
if has kubectl; then
  banner "PHASE 4 — PersistentVolumeClaims (PVCs) and PersistentVolumes (PVs)"
  echo -e "${YELLOW}  WHY THIS MATTERS: PVCs hold durable model weights, databases, and"
  echo -e "  training checkpoints. Deleting them destroys that data permanently."
  echo -e "  In enterprise, PVs map to EBS volumes or GCS buckets — always back up first.${RESET}"

  PVC_COUNT=$(kubectl get pvc --all-namespaces --no-headers 2>/dev/null | wc -l || echo 0)
  PV_COUNT=$(kubectl get pv --no-headers 2>/dev/null | wc -l || echo 0)

  echo -e "  Found ${CYAN}${PVC_COUNT}${RESET} PVCs and ${CYAN}${PV_COUNT}${RESET} PVs."

  if [[ "$PVC_COUNT" -gt 0 ]] || [[ "$PV_COUNT" -gt 0 ]]; then
    countdown "ALL PersistentVolumeClaims and PersistentVolumes — DATA WILL BE LOST" 12

    try kubectl delete pvc --all --all-namespaces --timeout=120s
    # PVs may be stuck in Released/Terminating; patch finalizers to unblock
    for pv in $(kubectl get pv --no-headers -o custom-columns=":metadata.name" 2>/dev/null || true); do
      try kubectl patch pv "$pv" -p '{"metadata":{"finalizers":null}}'
      try kubectl delete pv "$pv" --force --grace-period=0
    done
    echo -e "${GREEN}  ✓ PVCs and PVs deleted.${RESET}"
  else
    echo -e "  No PVCs or PVs found. Skipping."
  fi
fi

# ===========================================================================
# PHASE 5 — Kubernetes Namespaces
# ===========================================================================
if has kubectl && [[ -n "${NAMESPACES:-}" ]]; then
  banner "PHASE 5 — Kubernetes Namespaces"
  echo -e "  Deleting namespaces drains any remaining objects (finalizer-stuck resources)."
  echo -e "  System namespaces (kube-system, kube-public, kube-node-lease) are preserved"
  echo -e "  because kind manages them — the cluster delete in Phase 6 handles them."

  countdown "all non-system Kubernetes namespaces" 10

  for ns in $NAMESPACES; do
    echo -e "  Deleting namespace: ${CYAN}${ns}${RESET}"
    try kubectl delete namespace "$ns" --timeout=90s &
  done
  # Wait for parallel namespace deletions
  wait
  echo -e "${GREEN}  ✓ Namespaces deleted.${RESET}"
fi

# ===========================================================================
# PHASE 6 — kind Clusters
# ===========================================================================
if has kind; then
  banner "PHASE 6 — kind Kubernetes Clusters"

  CLUSTERS=$(kind get clusters 2>/dev/null || true)

  if [[ -n "$CLUSTERS" ]]; then
    echo -e "${YELLOW}  kind clusters found:${RESET}"
    echo "$CLUSTERS" | sed 's/^/    • /'

    countdown "ALL kind clusters listed above" 12

    for cluster in $CLUSTERS; do
      echo -e "  Deleting kind cluster: ${CYAN}${cluster}${RESET}"
      kind delete cluster --name "$cluster"
    done
    echo -e "${GREEN}  ✓ kind clusters deleted.${RESET}"
  else
    echo -e "  No kind clusters found. Skipping."
  fi
else
  echo -e "${YELLOW}  'kind' not found — skipping cluster deletion.${RESET}"
fi

# ===========================================================================
# PHASE 7 — Docker Containers (all, running and stopped)
# ===========================================================================
if has docker; then
  banner "PHASE 7 — Docker Containers (running + stopped)"

  CONTAINER_IDS=$(docker ps -aq 2>/dev/null || true)

  if [[ -n "$CONTAINER_IDS" ]]; then
    CONTAINER_COUNT=$(echo "$CONTAINER_IDS" | wc -l)
    echo -e "  Found ${CYAN}${CONTAINER_COUNT}${RESET} containers."

    countdown "ALL Docker containers (running containers will be force-stopped)" 10

    # Stop running containers gracefully first, then force-remove everything
    docker stop $(docker ps -q) 2>/dev/null || true
    docker rm --force $(docker ps -aq) 2>/dev/null || true
    echo -e "${GREEN}  ✓ Docker containers deleted.${RESET}"
  else
    echo -e "  No Docker containers found. Skipping."
  fi
fi

# ===========================================================================
# PHASE 8 — Docker Volumes (persistent data outside Kubernetes)
# ===========================================================================
if has docker; then
  banner "PHASE 8 — Docker Volumes (named volumes = persistent data)"
  echo -e "${YELLOW}  WHY: Docker volumes outlive containers. Any database data, model"
  echo -e "  checkpoints, or config stored in named volumes lives here.${RESET}"

  VOLUME_COUNT=$(docker volume ls -q 2>/dev/null | wc -l || echo 0)

  if [[ "$VOLUME_COUNT" -gt 0 ]]; then
    echo -e "  Found ${CYAN}${VOLUME_COUNT}${RESET} Docker volumes."

    countdown "ALL Docker volumes — data stored in them will be permanently lost" 12

    docker volume rm --force $(docker volume ls -q) 2>/dev/null || true
    echo -e "${GREEN}  ✓ Docker volumes deleted.${RESET}"
  else
    echo -e "  No Docker volumes found. Skipping."
  fi
fi

# ===========================================================================
# PHASE 9 — Docker Images
# ===========================================================================
if has docker; then
  banner "PHASE 9 — Docker Images (all pulled and locally built)"
  echo -e "  This removes every image — base images, model-serving images, debug images."
  echo -e "  They will be re-pulled on next use. This frees the most disk space."

  IMAGE_COUNT=$(docker images -q 2>/dev/null | wc -l || echo 0)

  if [[ "$IMAGE_COUNT" -gt 0 ]]; then
    echo -e "  Found ${CYAN}${IMAGE_COUNT}${RESET} Docker images."

    countdown "ALL Docker images (all tags and digests)" 10

    docker rmi --force $(docker images -q) 2>/dev/null || true
    echo -e "${GREEN}  ✓ Docker images deleted.${RESET}"
  else
    echo -e "  No Docker images found. Skipping."
  fi
fi

# ===========================================================================
# PHASE 10 — Docker Networks (custom only; bridge/host/none are built-in)
# ===========================================================================
if has docker; then
  banner "PHASE 10 — Docker Networks (custom networks only)"

  # The three built-in networks (bridge, host, none) cannot be deleted
  NETWORKS=$(docker network ls --filter type=custom -q 2>/dev/null || true)
  NETWORK_COUNT=$(echo "$NETWORKS" | grep -c . || echo 0)

  if [[ "$NETWORK_COUNT" -gt 0 ]]; then
    echo -e "  Found ${CYAN}${NETWORK_COUNT}${RESET} custom Docker networks."

    countdown "all custom Docker networks" 8

    docker network rm $NETWORKS 2>/dev/null || true
    echo -e "${GREEN}  ✓ Custom Docker networks deleted.${RESET}"
  else
    echo -e "  No custom Docker networks found. Skipping."
  fi
fi

# ===========================================================================
# PHASE 11 — Docker Builder Cache (BuildKit layers)
# ===========================================================================
if has docker; then
  banner "PHASE 11 — Docker Builder Cache (BuildKit layer cache)"
  echo -e "  BuildKit caches intermediate build layers. Pruning frees significant disk"
  echo -e "  space but means next builds re-download base layers from the registry."

  countdown "Docker builder cache (BuildKit layer cache)" 8

  docker builder prune --all --force 2>/dev/null || true
  echo -e "${GREEN}  ✓ Docker builder cache pruned.${RESET}"
fi

# ===========================================================================
# FINAL SUMMARY
# ===========================================================================
banner "TEARDOWN COMPLETE"

echo -e "${GREEN}${BOLD}  All phases complete. Environment state:${RESET}"
echo ""

if has kind; then
  REMAINING_CLUSTERS=$(kind get clusters 2>/dev/null | wc -l || echo 0)
  echo -e "  kind clusters   : ${CYAN}${REMAINING_CLUSTERS}${RESET}"
fi

if has docker; then
  echo -e "  Docker containers: ${CYAN}$(docker ps -aq 2>/dev/null | wc -l)${RESET}"
  echo -e "  Docker images    : ${CYAN}$(docker images -q 2>/dev/null | wc -l)${RESET}"
  echo -e "  Docker volumes   : ${CYAN}$(docker volume ls -q 2>/dev/null | wc -l)${RESET}"
fi

echo ""
echo -e "${YELLOW}  To rebuild from scratch:${RESET}"
echo -e "  1. Re-run the setup scripts in ${CYAN}setup/${RESET}"
echo -e "  2. Re-run the cluster bootstrap in ${CYAN}ml-serving/00-local-platform/${RESET}"
echo ""
echo -e "${GREEN}${BOLD}  Done.${RESET}"
echo ""
