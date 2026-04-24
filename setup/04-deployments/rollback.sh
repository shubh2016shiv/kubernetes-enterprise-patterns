#!/usr/bin/env bash
# =============================================================================
# FILE: 04-deployments/rollback.sh
# PURPOSE: Demonstrate a Deployment rollback after a bad rollout.
#
# WHY THIS EXISTS:
#   Rolling updates are only half of the story. In enterprise operations, the
#   real confidence comes from knowing how to inspect rollout history and return
#   to the previous ReplicaSet quickly when a new version misbehaves.
# =============================================================================

set -euo pipefail

# ┌──────────────────────────────────────────────────────────────────────────┐
# │                    ROLLBACK FLOW                                          │
# │                                                                           │
# │  Stage 1: Check History                                                  │
# │      └── kubectl rollout history deployment                              │
# │                                                                           │
# │  Stage 2: Execute Undo                                                   │
# │      └── kubectl rollout undo deployment                                 │
# │                                                                           │
# │  Stage 3: Verify Rollback                                                │
# │      └── Wait for pods to restart with previous ReplicaSet               │
# └──────────────────────────────────────────────────────────────────────────┘

NAMESPACE="applications"
DEPLOYMENT_NAME="nginx-deployment"

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
RESET='\033[0m'

echo ""
echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════${RESET}"
echo -e "${CYAN}${BOLD}  Deployment Rollback Demonstration${RESET}"
echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════${RESET}"

echo ""
echo -e "${BOLD}Stage 1.0 - Show rollout history${RESET}"
kubectl rollout history deployment/"${DEPLOYMENT_NAME}" -n "${NAMESPACE}"

echo ""
echo -e "${BOLD}Stage 2.0 - Undo the most recent rollout${RESET}"
echo -e "  ${YELLOW}▸ Executing: kubectl rollout undo deployment/${DEPLOYMENT_NAME}${RESET}"
kubectl rollout undo deployment/"${DEPLOYMENT_NAME}" -n "${NAMESPACE}"

echo ""
echo -e "${BOLD}Stage 3.0 - Wait for the rollback to finish${RESET}"
kubectl rollout status deployment/"${DEPLOYMENT_NAME}" -n "${NAMESPACE}" --timeout=120s

echo ""
echo -e "${GREEN}✓ Rollback complete!${RESET}"
echo ""
echo -e "${BOLD}Stage 4.0 - Show current pods after rollback${RESET}"
kubectl get pods -n "${NAMESPACE}" -l app=nginx -o wide
echo ""
