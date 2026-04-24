#!/usr/bin/env bash
# =============================================================================
# FILE: 07-rbac/rbac-commands.sh
# PURPOSE: Demonstrate RBAC enforcement. Create roles and test permissions
#          using Kubernetes' built-in `auth can-i` command.
# =============================================================================

set -euo pipefail

# ┌──────────────────────────────────────────────────────────────────────────┐
# │                    RBAC DEPLOYMENT & TESTING FLOW                         │
# │                                                                           │
# │  Stage 1: Apply RBAC Objects                                             │
# │      ├── Apply service-account.yaml                                      │
# │      ├── Apply role.yaml                                                 │
# │      └── Apply rolebinding.yaml                                          │
# │                                                                           │
# │  Stage 2: Test Permissions (auth can-i)                                  │
# │      ├── Test GET pods (Should be YES)                                   │
# │      └── Test DELETE pods (Should be NO)                                 │
# │                                                                           │
# │  Stage 3: Inspect RBAC State                                             │
# │      └── Describe Role and RoleBinding                                   │
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
echo -e "${CYAN}${BOLD}  RBAC Demonstration${RESET}"
echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════${RESET}"

echo ""
echo -e "${BOLD}Stage 1.0 - Apply RBAC Objects${RESET}"
kubectl apply -f "${MANIFESTS_DIR}/service-account.yaml"
kubectl apply -f "${MANIFESTS_DIR}/role.yaml"
kubectl apply -f "${MANIFESTS_DIR}/rolebinding.yaml"

echo ""
echo -e "${BOLD}Stage 2.0 - Test Permissions (auth can-i)${RESET}"
echo -e "  ${YELLOW}▸ The 'auth can-i' command asks the API server if an identity can perform an action.${RESET}"
echo ""

echo -e "  ${CYAN}Test 1: Can ml-api-sa GET pods in the applications namespace?${RESET}"
echo -e "  ${BOLD}\$ kubectl auth can-i get pods --as=system:serviceaccount:${NAMESPACE}:ml-api-sa -n ${NAMESPACE}${RESET}"
kubectl auth can-i get pods --as="system:serviceaccount:${NAMESPACE}:ml-api-sa" -n "${NAMESPACE}"

echo ""
echo -e "  ${CYAN}Test 2: Can ml-api-sa DELETE pods in the applications namespace?${RESET}"
echo -e "  ${BOLD}\$ kubectl auth can-i delete pods --as=system:serviceaccount:${NAMESPACE}:ml-api-sa -n ${NAMESPACE}${RESET}"
kubectl auth can-i delete pods --as="system:serviceaccount:${NAMESPACE}:ml-api-sa" -n "${NAMESPACE}" || true

echo ""
echo -e "  ${CYAN}Test 3: Can ml-api-sa GET secrets? (Should be no!)${RESET}"
echo -e "  ${BOLD}\$ kubectl auth can-i get secrets --as=system:serviceaccount:${NAMESPACE}:ml-api-sa -n ${NAMESPACE}${RESET}"
kubectl auth can-i get secrets --as="system:serviceaccount:${NAMESPACE}:ml-api-sa" -n "${NAMESPACE}" || true

echo ""
echo -e "${BOLD}Stage 3.0 - Inspect RBAC State${RESET}"
echo -e "  ${YELLOW}▸ Executing: kubectl describe role ml-api-reader -n ${NAMESPACE}${RESET}"
kubectl describe role ml-api-reader -n "${NAMESPACE}"

echo ""
echo -e "${GREEN}✓ RBAC demonstration complete!${RESET}"
echo ""
echo -e "  ${BOLD}Next step:${RESET} 08-resource-management/README.md"
echo ""
