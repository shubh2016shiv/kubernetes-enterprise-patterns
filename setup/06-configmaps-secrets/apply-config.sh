#!/usr/bin/env bash
# =============================================================================
# FILE: 06-configmaps-secrets/apply-config.sh
# PURPOSE: Demonstrate applying ConfigMaps and Secrets, and how a Pod
#          consumes them via environment variables and volume mounts.
# =============================================================================

set -euo pipefail

# ┌──────────────────────────────────────────────────────────────────────────┐
# │                    CONFIGMAP & SECRET DEMO FLOW                          │
# │                                                                           │
# │  Stage 1: Apply Configuration Objects                                    │
# │      ├── Apply app-configmap.yaml                                        │
# │      └── Apply app-secret.yaml                                           │
# │                                                                           │
# │  Stage 2: Deploy Consumer Pod                                            │
# │      └── Apply pod-using-config.yaml and wait for Ready                  │
# │                                                                           │
# │  Stage 3: Verify Environment Variables                                   │
# │      └── Exec into pod and check 'env' output                            │
# │                                                                           │
# │  Stage 4: Verify Volume Mounts                                           │
# │      └── Exec into pod and read mounted config file                      │
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
echo -e "${CYAN}${BOLD}  ConfigMaps and Secrets Demonstration${RESET}"
echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════${RESET}"

echo ""
echo -e "${BOLD}Stage 1.0 - Apply ConfigMap and Secret${RESET}"
kubectl apply -f "${MANIFESTS_DIR}/app-configmap.yaml"
kubectl apply -f "${MANIFESTS_DIR}/app-secret.yaml"

echo ""
echo -e "${BOLD}Stage 2.0 - Deploy the Consumer Pod${RESET}"
echo -e "  ${YELLOW}▸ The Pod will mount these objects as files and env vars${RESET}"
kubectl apply -f "${MANIFESTS_DIR}/pod-using-config.yaml"

echo -e "  ${YELLOW}▸ Waiting for pod to be Ready...${RESET}"
kubectl wait --for=condition=Ready pod/config-demo -n "${NAMESPACE}" --timeout=60s

echo ""
echo -e "${BOLD}Stage 3.0 - Verify Environment Variables${RESET}"
echo -e "  ${YELLOW}▸ Executing: kubectl exec config-demo -- env | grep -E 'APP_ENV|DB_'${RESET}"
kubectl exec config-demo -n "${NAMESPACE}" -- env | grep -E 'APP_ENV|LOG_LEVEL|DB_USERNAME|DB_PASSWORD|API_KEY' || true

echo ""
echo -e "${BOLD}Stage 4.0 - Verify Volume Mounts (Files)${RESET}"
echo -e "  ${YELLOW}▸ Reading the mounted app-settings.properties file:${RESET}"
kubectl exec config-demo -n "${NAMESPACE}" -- cat /etc/config/app-settings.properties

echo ""
echo -e "${GREEN}✓ Config demonstration complete!${RESET}"
echo ""
echo -e "  ${BOLD}Clean up command (optional):${RESET}"
echo -e "  kubectl delete -f ${MANIFESTS_DIR}/pod-using-config.yaml"
echo ""
echo -e "  ${BOLD}Next step:${RESET} 07-rbac/README.md"
echo ""
