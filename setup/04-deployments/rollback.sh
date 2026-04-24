#!/usr/bin/env bash
# =============================================================================
# FILE:    rollback.sh
# PURPOSE: Demonstrate the rollback-only path for the gateway Deployment while
#          showing that sibling Deployments are not automatically changed.
# USAGE:   bash setup/04-deployments/rollback.sh
# WHEN:    Use this after at least one rollout change exists in gateway history.
# PREREQS: Deployment `inference-gateway-deployment` exists in namespace
#          `applications` and has at least one previous revision.
# OUTPUT:  The previous gateway ReplicaSet becomes active and the backend
#          sibling Deployment remains healthy and unchanged.
# =============================================================================

set -euo pipefail

# ┌────────────────────────────────────────────────────────────────────────────┐
# │                           SCRIPT FLOW                                     │
# │                                                                            │
# │  Stage 1: Show Rollout History                                            │
# │      └── Confirm there is a previous gateway revision to return to         │
# │                                                                            │
# │  Stage 2: Execute Rollback                                                │
# │      └── Undo only the latest gateway revision                             │
# │                                                                            │
# │  Stage 3: Verify Health                                                   │
# │      └── Wait for rollout to complete and confirm backend is still stable  │
# └────────────────────────────────────────────────────────────────────────────┘

NAMESPACE="applications"
GATEWAY_DEPLOYMENT="inference-gateway-deployment"
BACKEND_DEPLOYMENT="risk-profile-api-deployment"

section() {
  echo ""
  echo "=== $1 ==="
}

run_cmd() {
  echo "\$ $*"
  "$@"
  echo ""
}

section "Stage 1.0: Show Rollout History"
run_cmd kubectl rollout history deployment/"${GATEWAY_DEPLOYMENT}" -n "${NAMESPACE}"

section "Stage 2.0: Execute Rollback"
echo "If this were production, this command would revert the most recent bad gateway rollout."
echo "Notice that we are rolling back a single Deployment, not the whole namespace."
echo ""
run_cmd kubectl rollout undo deployment/"${GATEWAY_DEPLOYMENT}" -n "${NAMESPACE}"

section "Stage 3.0: Verify Health"
run_cmd kubectl rollout status deployment/"${GATEWAY_DEPLOYMENT}" -n "${NAMESPACE}" --timeout=180s
run_cmd kubectl get pods -n "${NAMESPACE}" -l app=inference-gateway -o wide
run_cmd kubectl get deployment "${BACKEND_DEPLOYMENT}" -n "${NAMESPACE}"
