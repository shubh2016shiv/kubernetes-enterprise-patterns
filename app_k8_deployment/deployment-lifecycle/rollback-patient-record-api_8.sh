#!/usr/bin/env bash
# =============================================================================
# FILE:    rollback-patient-record-api.sh
# PURPOSE: Roll back the FastAPI backend Deployment to the previous revision.
# USAGE:   bash app_k8_deployment/deployment-lifecycle/rollback-patient-record-api.sh
# WHEN:    Run after a bad backend rollout or failed verification.
# PREREQS: patient-record-api Deployment has at least one previous revision.
# OUTPUT:  Kubernetes restores the previous ReplicaSet and waits for readiness.
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# SCRIPT FLOW
#
# Stage 1: Inspect Current History
#   - Show available Deployment revisions.
#
# Stage 2: Perform Rollback
#   - Ask Kubernetes to undo the latest rollout.
#
# Stage 3: Verify Rollback
#   - Wait for rollout and show pod state.
# ---------------------------------------------------------------------------

# CONFIGURATION EXPLANATION Rollback is scoped to `patient-record-system` so only this app's backend Deployment
# is changed. Namespace scoping is a production blast-radius control for operational commands.
NAMESPACE="patient-record-system"

section() {
  echo ""
  echo "=== $1 ==="
}

run_cmd() {
  echo "$ $*"
  "$@"
  echo ""
}

# ---------------------------------------------------------------------------
# Stage 1.0: Inspect Current History
# Purpose: Make the rollback target visible before changing live state.
# Expected input: Deployment exists.
# Expected output: rollout history shows revisions.
# ---------------------------------------------------------------------------
section "Stage 1.0: Inspect Current History"

run_cmd kubectl rollout history deployment/patient-record-api -n "${NAMESPACE}"

# ---------------------------------------------------------------------------
# Stage 2.0: Perform Rollback
# Purpose: Restore the previous Deployment revision.
# Expected output: kubectl confirms rollback started.
# ---------------------------------------------------------------------------
section "Stage 2.0: Perform Rollback"

echo "ENTERPRISE EMPHASIS: Rollback is a Deployment capability for stateless tiers. Database schema/data rollback is a separate and riskier operational process."
run_cmd kubectl rollout undo deployment/patient-record-api -n "${NAMESPACE}"

# ---------------------------------------------------------------------------
# Stage 3.0: Verify Rollback
# Purpose: Ensure readiness probes allow the restored pods to serve traffic.
# Expected output: rollout completes and pods are Ready.
# ---------------------------------------------------------------------------
section "Stage 3.0: Verify Rollback"

# CONFIGURATION EXPLANATION The 180s timeout confirms the restored ReplicaSet becomes ready. A ReplicaSet is the
# Deployment-owned object that keeps a specific pod template running, so rollback is not complete until those
# restored pods pass readiness.
run_cmd kubectl rollout status deployment/patient-record-api -n "${NAMESPACE}" --timeout=180s
run_cmd kubectl get pods -n "${NAMESPACE}" -l app=patient-record-api -o wide
run_cmd kubectl rollout history deployment/patient-record-api -n "${NAMESPACE}"

echo "Run final verification:"
echo "  bash app_k8_deployment/deployment-lifecycle/verify-patient-record-system.sh"
