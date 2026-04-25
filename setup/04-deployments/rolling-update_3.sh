#!/usr/bin/env bash
# =============================================================================
# FILE:    rolling-update.sh
# PURPOSE: Deploy two sibling Deployments, perform a rolling update on the
#          gateway Deployment, inspect rollout history, roll back, and scale.
# USAGE:   bash setup/04-deployments/rolling-update.sh
# WHEN:    Run this after finishing the pod module and before the services module.
# PREREQS: Namespace `applications` exists and kubectl points at the learning cluster.
# OUTPUT:  Two healthy Deployments, at least two rollout revisions for the
#          gateway, and a successful rollback to the previous image.
# =============================================================================

set -euo pipefail

# ┌────────────────────────────────────────────────────────────────────────────┐
# │                           SCRIPT FLOW                                     │
# │                                                                            │
# │  Stage 1: Deploy Sibling Workloads                                        │
# │      └── Apply both Deployments and wait until all replicas are ready      │
# │                                                                            │
# │  Stage 2: Perform Rolling Update                                           │
# │      └── Change only the gateway image and watch a new ReplicaSet appear    │
# │                                                                            │
# │  Stage 3: Inspect Rollout History                                          │
# │      └── Show revisions for the gateway and confirm the backend is stable   │
# │                                                                            │
# │  Stage 4: Roll Back                                                        │
# │      └── Undo the latest gateway rollout                                    │
# │                                                                            │
# │  Stage 5: Manual Scaling                                                   │
# │      └── Scale the gateway up and back down to see reconciliation           │
# │                                                                            │
# │  Stage 6: Prepare for Services                                             │
# │      └── Leave both Deployments healthy for the networking module           │
# └────────────────────────────────────────────────────────────────────────────┘

NAMESPACE="applications"
GATEWAY_DEPLOYMENT="inference-gateway-deployment"
BACKEND_DEPLOYMENT="risk-profile-api-deployment"
MANIFESTS_DIR="$(cd "$(dirname "$0")" && pwd)"

section() {
  echo ""
  echo "=== $1 ==="
}

run_cmd() {
  echo "\$ $*"
  "$@"
  echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
# Stage 1.0: Deploy Sibling Workloads
# Purpose: Show that real clusters run multiple Deployments side by side.
# Expected input: applications namespace exists.
# Expected output: gateway and backend Deployments both become healthy.
# ─────────────────────────────────────────────────────────────────────────────
section "Stage 1.0: Deploy Sibling Workloads"

echo "Applying the internal backend first, then the edge gateway."
echo "This makes the module feel closer to a real platform: one Deployment rarely lives alone."
echo ""

run_cmd kubectl apply -f "${MANIFESTS_DIR}/risk-profile-api-deployment.yaml" -n "${NAMESPACE}"
run_cmd kubectl apply -f "${MANIFESTS_DIR}/inference-gateway-deployment.yaml" -n "${NAMESPACE}"

run_cmd kubectl rollout status deployment/"${BACKEND_DEPLOYMENT}" -n "${NAMESPACE}" --timeout=180s
run_cmd kubectl rollout status deployment/"${GATEWAY_DEPLOYMENT}" -n "${NAMESPACE}" --timeout=180s

run_cmd kubectl get deployments -n "${NAMESPACE}"
run_cmd kubectl get pods -n "${NAMESPACE}" -l 'tier=backend' -o wide

echo "Important lesson:"
echo "  Both Deployments are healthy now, but stable service-to-service communication"
echo "  is still a Services concern. Deployment creates pods; Service creates stable discovery."
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Stage 2.0: Perform Rolling Update
# Purpose: Show how one Deployment can change independently while its sibling stays stable.
# Expected output: only the gateway creates a new ReplicaSet revision.
# ─────────────────────────────────────────────────────────────────────────────
section "Stage 2.0: Perform Rolling Update"

echo "Updating only the gateway image from python:3.11.11-slim to python:3.12.8-slim."
echo "The backend Deployment should remain untouched."
echo ""

run_cmd kubectl set image deployment/"${GATEWAY_DEPLOYMENT}" \
  gateway=python:3.12.8-slim \
  --namespace="${NAMESPACE}"

run_cmd kubectl rollout status deployment/"${GATEWAY_DEPLOYMENT}" -n "${NAMESPACE}" --timeout=180s
run_cmd kubectl get deployments -n "${NAMESPACE}"
run_cmd kubectl get replicasets -n "${NAMESPACE}" -l app=inference-gateway

GATEWAY_POD_NAME=$(kubectl get pod -n "${NAMESPACE}" -l app=inference-gateway -o jsonpath='{.items[0].metadata.name}')
run_cmd kubectl get pod "${GATEWAY_POD_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.containers[0].image}'
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Stage 3.0: Inspect Rollout History
# Purpose: Show revision history for the Deployment being changed.
# Expected output: at least two revisions for the gateway and one steady backend Deployment.
# ─────────────────────────────────────────────────────────────────────────────
section "Stage 3.0: Inspect Rollout History"

run_cmd kubectl rollout history deployment/"${GATEWAY_DEPLOYMENT}" -n "${NAMESPACE}"
run_cmd kubectl get replicasets -n "${NAMESPACE}" -l app=inference-gateway
run_cmd kubectl get deployment "${BACKEND_DEPLOYMENT}" -n "${NAMESPACE}"

echo "Notice:"
echo "  The gateway has rollout history because we changed it."
echo "  The sibling backend is still on its original revision because we did not touch it."
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Stage 4.0: Roll Back
# Purpose: Demonstrate incident recovery for one Deployment without disturbing its sibling.
# Expected output: the gateway returns to the previous image revision.
# ─────────────────────────────────────────────────────────────────────────────
section "Stage 4.0: Roll Back"

echo "Simulating incident response for the gateway only."
echo "Rolling back does not rewrite the backend Deployment."
echo ""

run_cmd kubectl rollout undo deployment/"${GATEWAY_DEPLOYMENT}" -n "${NAMESPACE}"
run_cmd kubectl rollout status deployment/"${GATEWAY_DEPLOYMENT}" -n "${NAMESPACE}" --timeout=180s

GATEWAY_POD_NAME=$(kubectl get pod -n "${NAMESPACE}" -l app=inference-gateway -o jsonpath='{.items[0].metadata.name}')
run_cmd kubectl get pod "${GATEWAY_POD_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.containers[0].image}'
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Stage 5.0: Manual Scaling
# Purpose: Show how the ReplicaSet reconciliation loop reacts to replica changes.
# Expected output: gateway pod count grows to 5 and then returns to 3.
# ─────────────────────────────────────────────────────────────────────────────
section "Stage 5.0: Manual Scaling"

run_cmd kubectl scale deployment/"${GATEWAY_DEPLOYMENT}" --replicas=5 -n "${NAMESPACE}"
run_cmd kubectl get pods -n "${NAMESPACE}" -l app=inference-gateway

run_cmd kubectl scale deployment/"${GATEWAY_DEPLOYMENT}" --replicas=3 -n "${NAMESPACE}"
run_cmd kubectl rollout status deployment/"${GATEWAY_DEPLOYMENT}" -n "${NAMESPACE}" --timeout=120s

# ─────────────────────────────────────────────────────────────────────────────
# Stage 6.0: Prepare for Services
# Purpose: Leave the module in a clean state for the networking walkthrough.
# Expected output: both Deployments healthy and ready to be wired by Services.
# ─────────────────────────────────────────────────────────────────────────────
section "Stage 6.0: Prepare for Services"

run_cmd kubectl get deployments -n "${NAMESPACE}"
run_cmd kubectl get pods -n "${NAMESPACE}" -l 'tier=backend' -o wide

echo "Next step:"
echo "  bash setup/05-services/commands.sh"
