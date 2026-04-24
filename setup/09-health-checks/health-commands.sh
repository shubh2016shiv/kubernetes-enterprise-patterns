#!/usr/bin/env bash
# =============================================================================
# FILE: 09-health-checks/health-commands.sh
# PURPOSE: Demonstrate Liveness, Readiness, and Startup probes.
# =============================================================================

set -euo pipefail

# ┌──────────────────────────────────────────────────────────────────────────┐
# │                    HEALTH CHECK DEMO FLOW                                 │
# │                                                                           │
# │  Stage 1: Apply Deployment with Probes                                   │
# │      └── Apply health-checks-demo.yaml                                   │
# │                                                                           │
# │  Stage 2: Observe Probe Behavior                                         │
# │      └── Watch pods transition from 0/1 READY to 1/1 READY               │
# │                                                                           │
# │  Stage 3: Inspect Events                                                 │
# │      └── Describe Pod to see probe failures/successes in Events          │
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
echo -e "${CYAN}${BOLD}  Health Checks Demonstration${RESET}"
echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════${RESET}"

echo ""
echo -e "${BOLD}Stage 1.0 - Apply Health Check Demo${RESET}"
kubectl apply -f "${MANIFESTS_DIR}/health-checks-demo.yaml" -n "${NAMESPACE}"

echo ""
echo -e "${BOLD}Stage 2.0 - Observe Probe Behavior${RESET}"
echo -e "  ${YELLOW}▸ Watch the READY column. It stays 0/1 until the Readiness probe passes.${RESET}"
echo -e "  ${YELLOW}▸ The Startup probe must pass first, then Liveness/Readiness begin.${RESET}"
echo ""
kubectl get pods -l app=health-check-demo -n "${NAMESPACE}"

echo -e "  ${YELLOW}▸ Waiting for pod to become Ready (can take up to 30s due to probe delays)...${RESET}"
kubectl wait --for=condition=Ready pod -l app=health-check-demo -n "${NAMESPACE}" --timeout=60s || true

echo ""
echo -e "${BOLD}Stage 3.0 - Inspect Events${RESET}"
POD_NAME=$(kubectl get pod -l app=health-check-demo -n "${NAMESPACE}" -o jsonpath='{.items[0].metadata.name}')
echo -e "  ${YELLOW}▸ Executing: kubectl describe pod ${POD_NAME} -n ${NAMESPACE} | grep -A 10 Events${RESET}"
echo ""
kubectl describe pod "${POD_NAME}" -n "${NAMESPACE}" | awk '/Events:/,0'

echo ""
echo -e "${GREEN}✓ Health check demonstration complete!${RESET}"
echo ""
echo -e "  ${BOLD}Clean up command (optional):${RESET}"
echo -e "  kubectl delete -f ${MANIFESTS_DIR}/health-checks-demo.yaml -n ${NAMESPACE}"
echo ""
echo -e "  ${BOLD}Next step:${RESET} 10-enterprise-patterns/README.md"
echo ""
