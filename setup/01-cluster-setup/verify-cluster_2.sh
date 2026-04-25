#!/usr/bin/env bash
# =============================================================================
# FILE: 01-cluster-setup/verify-cluster_2.sh
# PURPOSE: Post-creation health check. Run this after create-cluster_1.sh
#          to confirm every system component is operational.
#
# ENTERPRISE CONTEXT:
#   In production, cluster health verification is automated via:
#     - CloudWatch (AWS EKS)
#     - Cloud Monitoring (GKE)
#     - Azure Monitor (AKS)
#     - Prometheus + Alertmanager (self-managed)
#
#   This script teaches you what to look for — the same checks that
#   production monitoring tools perform under the hood.
#
# WHAT WE CHECK:
#   1. Cluster is reachable (API server responds)
#   2. All nodes are Ready
#   3. All system pods are Running
#   4. CoreDNS is working (service discovery is functional)
#   5. Node resources are visible (CPU/Memory allocation)
# =============================================================================

set -e
set -u
set -o pipefail

# CAN BE CHANGED: Must match CLUSTER_NAME in create-cluster_1.sh and the
# name field in kind-cluster-config.yaml. Example: `ml-inference-dev`.
# If changed, also update destroy-cluster_3.sh and kind-cluster-config.yaml.
CLUSTER_NAME="local-enterprise-dev"

GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
RESET='\033[0m'

PASS=0
FAIL=0

check() {
  local label="$1"
  local cmd="$2"
  printf "  %-50s " "${label}"
  if eval "$cmd" &>/dev/null; then
    echo -e "${GREEN}PASS${RESET}"
    ((PASS++))
  else
    echo -e "${RED}FAIL${RESET}"
    ((FAIL++))
  fi
}

echo ""
echo -e "${CYAN}${BOLD}════════════════════════════════════════════════════════${RESET}"
echo -e "${CYAN}${BOLD}  Cluster Health Verification: ${CLUSTER_NAME}${RESET}"
echo -e "${CYAN}${BOLD}════════════════════════════════════════════════════════${RESET}"

# ─── CHECK 1: API SERVER REACHABILITY ─────────────────────────────────────────
# The API server is the ENTRY POINT to the entire cluster.
# `kubectl cluster-info` sends a GET request to the /healthz endpoint.
# If this fails: network issue, cluster down, or wrong context.
echo ""
echo -e "${BOLD}  [1] API Server Connectivity${RESET}"
check "API server responds to cluster-info" "kubectl cluster-info"

# ─── CHECK 2: NODE HEALTH ─────────────────────────────────────────────────────
# Each node must be Ready. A "Ready" condition means:
#   - kubelet is running and reporting to the API server
#   - The node's container runtime is healthy
#   - Network plugin is configured
#   - Node doesn't have resource pressure (DiskPressure, MemoryPressure, PIDPressure)
echo ""
echo -e "${BOLD}  [2] Node Status${RESET}"
echo ""
kubectl get nodes -o wide
echo ""

# Count nodes not in Ready state using JSONPath
# JSONPath is a query language for JSON — used heavily with kubectl -o jsonpath
# This extracts the status of the "Ready" condition for all nodes
NOT_READY_COUNT=$(kubectl get nodes \
  -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' \
  | tr ' ' '\n' | grep -c "False\|Unknown" || true)

if [[ "$NOT_READY_COUNT" -eq 0 ]]; then
  echo -e "  ${GREEN}✓ All nodes are Ready${RESET}"
  ((PASS++))
else
  echo -e "  ${RED}✗ ${NOT_READY_COUNT} node(s) NOT Ready${RESET}"
  echo -e "  ${YELLOW}Debug: kubectl describe nodes | grep -A10 'Conditions:'${RESET}"
  ((FAIL++))
fi

# ─── CHECK 3: SYSTEM PODS ─────────────────────────────────────────────────────
# The kube-system namespace contains Kubernetes' own infrastructure pods.
# ALL of these must be Running for the cluster to function properly.
echo ""
echo -e "${BOLD}  [3] System Pods (kube-system namespace)${RESET}"
echo ""
# Show all pods in kube-system with their status
kubectl get pods --namespace kube-system --output wide
echo ""

# Count pods in kube-system that are NOT Running
UNHEALTHY_SYSTEM_PODS=$(kubectl get pods -n kube-system \
  -o jsonpath='{.items[*].status.phase}' \
  | tr ' ' '\n' | grep -c -v "Running\|Succeeded" || true)

if [[ "$UNHEALTHY_SYSTEM_PODS" -eq 0 ]]; then
  echo -e "  ${GREEN}✓ All system pods are Running${RESET}"
  ((PASS++))
else
  echo -e "  ${YELLOW}⚠ ${UNHEALTHY_SYSTEM_PODS} system pod(s) may not be Running${RESET}"
  echo -e "  ${YELLOW}Note: Some pods may still be initializing. Wait 30s and retry.${RESET}"
  ((FAIL++))
fi

# ─── CHECK 4: COREDNS ─────────────────────────────────────────────────────────
# CoreDNS is the CLUSTER-INTERNAL DNS server.
# Without it, no pod can find any service by name.
#
# HOW IT WORKS (critical for interviews):
#   1. When you create a Service called "my-api" in namespace "production"
#   2. CoreDNS automatically gets a DNS entry: my-api.production.svc.cluster.local
#   3. Any pod asking for "my-api" or "my-api.production" gets the Service's ClusterIP
#   4. CoreDNS is how microservices find each other WITHOUT hardcoded IPs
#
# In enterprise, CoreDNS is configured with custom resolvers (forward rules)
# to also resolve your corporate DNS (e.g., internal.company.com)
echo ""
echo -e "${BOLD}  [4] CoreDNS (Service Discovery)${RESET}"
check "CoreDNS pods exist in kube-system" \
  "kubectl get pods -n kube-system -l k8s-app=kube-dns | grep -q Running"

# ─── CHECK 5: NODE RESOURCE CAPACITY ──────────────────────────────────────────
# Shows CPU and memory CAPACITY of each node.
# This is what the kube-scheduler uses when deciding where to place pods.
# "cpu: 8" means 8 CPUs, "memory: 15Gi" means 15 GiB RAM.
echo ""
echo -e "${BOLD}  [5] Node Resource Capacity${RESET}"
echo ""
# custom-columns is a way to format kubectl output as a table with chosen fields
kubectl get nodes -o custom-columns=\
"NAME:.metadata.name,\
STATUS:.status.conditions[-1].type,\
CPU:.status.capacity.cpu,\
MEMORY:.status.capacity.memory,\
ZONE:.metadata.labels.topology\.kubernetes\.io/zone"

# ─── CHECK 6: KUBECONFIG CONTEXT ──────────────────────────────────────────────
# Verify we're pointed at the right cluster.
# In enterprise, accidentally running kubectl against the wrong cluster
# (e.g., prod instead of dev) is a common and dangerous mistake.
# Tools like kubectx, kubie, and k9s help prevent this.
echo ""
echo -e "${BOLD}  [6] kubectl Context${RESET}"
CURRENT_CONTEXT=$(kubectl config current-context)
echo ""
echo -e "  Current context: ${YELLOW}${CURRENT_CONTEXT}${RESET}"

if [[ "$CURRENT_CONTEXT" == "kind-${CLUSTER_NAME}" ]]; then
  echo -e "  ${GREEN}✓ Pointing at correct cluster${RESET}"
  ((PASS++))
else
  echo -e "  ${YELLOW}⚠ Not pointing at 'kind-${CLUSTER_NAME}'${RESET}"
  echo -e "  ${YELLOW}  Run: kubectl config use-context kind-${CLUSTER_NAME}${RESET}"
  ((FAIL++))
fi

# ─── SUMMARY ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}${BOLD}════════════════════════════════════════════════════════${RESET}"
TOTAL=$((PASS + FAIL))
if [[ $FAIL -eq 0 ]]; then
  echo -e "  ${GREEN}${BOLD}✓ ALL CHECKS PASSED (${PASS}/${TOTAL})${RESET}"
  echo -e "  ${CYAN}Cluster is healthy and ready for workloads!${RESET}"
  echo ""
  echo -e "  ${BOLD}Next step:${RESET} bash 02-namespaces/apply-namespaces.sh"
else
  echo -e "  ${RED}${BOLD}✗ ${FAIL} CHECK(S) FAILED (${PASS}/${TOTAL} passed)${RESET}"
  echo -e "  ${YELLOW}Common fixes:${RESET}"
  echo -e "    - Wait 30s for pods to initialize, then re-run this script"
  echo -e "    - kubectl describe node <node-name>  → check Events section"
  echo -e "    - kubectl describe pod <pod> -n kube-system → check containers"
  echo -e "    - kind export logs ./cluster-logs --name ${CLUSTER_NAME}"
fi
echo -e "${CYAN}${BOLD}════════════════════════════════════════════════════════${RESET}"
echo ""
