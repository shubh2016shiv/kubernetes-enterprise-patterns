#!/usr/bin/env bash
# =============================================================================
# FILE: 10-enterprise-patterns/enterprise-commands.sh
# PURPOSE: Demonstrate NetworkPolicies, PodDisruptionBudgets, and HPA.
# =============================================================================

set -euo pipefail

# ┌──────────────────────────────────────────────────────────────────────────┐
# │                    ENTERPRISE PATTERNS FLOW                               │
# │                                                                           │
# │  Stage 1: Apply Base Workloads                                           │
# │      └── Apply the deployment from module 08                             │
# │                                                                           │
# │  Stage 2: Apply Enterprise Policies                                      │
# │      ├── Apply network-policy.yaml                                       │
# │      ├── Apply pod-disruption-budget.yaml                                │
# │      └── Apply horizontal-pod-autoscaler.yaml                            │
# │                                                                           │
# │  Stage 3: Inspect Policies                                               │
# │      ├── Describe NetworkPolicy                                          │
# │      ├── Describe PDB (Check Allowed Disruptions)                        │
# │      └── Describe HPA (Check Targets)                                    │
# └──────────────────────────────────────────────────────────────────────────┘

NAMESPACE="applications"
MANIFESTS_DIR="$(dirname "$0")"

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
RESET='\033[0m'

echo ""
echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════${RESET}"
echo -e "${CYAN}${BOLD}  Enterprise Patterns Demonstration${RESET}"
echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════${RESET}"

echo ""
echo -e "${BOLD}Stage 1.0 - Ensure Base Deployment Exists${RESET}"
kubectl apply -f "${MANIFESTS_DIR}/../08-resource-management/deployment-with-limits.yaml" -n "${NAMESPACE}" > /dev/null

echo ""
echo -e "${BOLD}Stage 2.0 - Apply Enterprise Policies${RESET}"
kubectl apply -f "${MANIFESTS_DIR}/network-policy.yaml" -n "${NAMESPACE}"
kubectl apply -f "${MANIFESTS_DIR}/pod-disruption-budget.yaml" -n "${NAMESPACE}"
kubectl apply -f "${MANIFESTS_DIR}/horizontal-pod-autoscaler.yaml" -n "${NAMESPACE}"

echo ""
echo -e "${BOLD}Stage 3.0 - Inspect PodDisruptionBudget${RESET}"
echo -e "  ${YELLOW}▸ Executing: kubectl get pdb -n ${NAMESPACE}${RESET}"
echo -e "  ${YELLOW}▸ The 'ALLOWED DISRUPTIONS' column tells the cluster autoscaler if it's safe to drain nodes.${RESET}"
echo ""
kubectl get pdb -n "${NAMESPACE}"
echo ""
kubectl describe pdb my-app-pdb -n "${NAMESPACE}" | grep -E "Min available|Current healthy|Allowed disruptions"

echo ""
echo -e "${BOLD}Stage 4.0 - Inspect HorizontalPodAutoscaler${RESET}"
echo -e "  ${YELLOW}▸ Executing: kubectl get hpa -n ${NAMESPACE}${RESET}"
echo -e "  ${YELLOW}▸ Note: If TARGETS shows <unknown>, it means the metrics-server is not installed in the cluster.${RESET}"
echo ""
kubectl get hpa -n "${NAMESPACE}"

echo ""
echo -e "${BOLD}Stage 5.0 - Inspect NetworkPolicy${RESET}"
echo -e "  ${YELLOW}▸ Executing: kubectl describe networkpolicy -n ${NAMESPACE}${RESET}"
echo -e "  ${YELLOW}▸ This shows the ingress/egress rules applied to the pods.${RESET}"
echo ""
kubectl describe networkpolicy -n "${NAMESPACE}"

echo ""
echo -e "${GREEN}✓ Enterprise Patterns demonstration complete!${RESET}"
echo ""
echo -e "  ${BOLD}Clean up command (optional):${RESET}"
echo -e "  kubectl delete -f ${MANIFESTS_DIR}/network-policy.yaml -n ${NAMESPACE}"
echo -e "  kubectl delete -f ${MANIFESTS_DIR}/pod-disruption-budget.yaml -n ${NAMESPACE}"
echo -e "  kubectl delete -f ${MANIFESTS_DIR}/horizontal-pod-autoscaler.yaml -n ${NAMESPACE}"
echo ""
echo -e "  ${BOLD}Next step:${RESET} You have completed the fundamentals track! Proceed to Phase 5 (Root README)."
echo ""
