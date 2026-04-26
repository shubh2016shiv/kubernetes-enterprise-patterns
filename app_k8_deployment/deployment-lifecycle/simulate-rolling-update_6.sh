#!/usr/bin/env bash
# =============================================================================
# FILE:    simulate-rolling-update.sh
# PURPOSE: Trigger and observe a backend rolling update like a CI/CD promotion.
# USAGE:   bash app_k8_deployment/deployment-lifecycle/simulate-rolling-update.sh 1.0.1
# WHEN:    Run after the system is deployed and a new API image tag is available.
# PREREQS: patient-record-api:<tag> has been built and loaded into kind.
# OUTPUT:  Deployment creates a new ReplicaSet and rolls traffic safely.
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# SCRIPT FLOW
#
# Stage 1: Preflight Checks
#   - Read target tag and verify namespace.
#
# Stage 2: Patch Deployment Image and Version
#   - Update the pod template the way a pipeline would.
#
# Stage 3: Watch Rollout
#   - Wait for readiness-gated rollout completion.
#
# Stage 4: Inspect Revision History
#   - Show rollout history for rollback learning.
# ---------------------------------------------------------------------------

# CONFIGURATION EXPLANATION This namespace tells kubectl which Deployment to modify. Namespaces are Kubernetes
# boundaries for application ownership; a rollout command sent to the wrong namespace can update nothing or the
# wrong copy of an app.
NAMESPACE="patient-record-system"
# CONFIGURATION EXPLANATION `1.0.1` is the default simulated release tag. A tag is the version label on a
# container image; production teams normally use immutable tags tied to a Git commit so rollouts are traceable.
TARGET_TAG="${1:-1.0.1}"
# CONFIGURATION EXPLANATION The target image combines the repository name and release tag. This must already be
# built and loaded into kind, or the new pods will not be able to start.
TARGET_IMAGE="patient-record-api:${TARGET_TAG}"

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
# Stage 1.0: Preflight Checks
# Purpose: Confirm the app exists before changing its rollout state.
# Expected input: Deployment has already been created.
# Expected output: deployment lookup succeeds.
# ---------------------------------------------------------------------------
section "Stage 1.0: Preflight Checks"

run_cmd kubectl get deployment patient-record-api -n "${NAMESPACE}"

# ---------------------------------------------------------------------------
# Stage 2.0: Patch Deployment Image and Version
# Purpose: Change the pod template, which creates a new ReplicaSet revision.
# Expected output: deployment image and API_VERSION env var are updated.
# ---------------------------------------------------------------------------
section "Stage 2.0: Patch Deployment Image and Version"

echo "ENTERPRISE EMPHASIS: CI/CD changes the desired state. Kubernetes performs the rollout through the Deployment controller."
run_cmd kubectl set image deployment/patient-record-api \
  api="${TARGET_IMAGE}" \
  -n "${NAMESPACE}"
run_cmd kubectl set env deployment/patient-record-api \
  API_VERSION="${TARGET_TAG}" \
  -n "${NAMESPACE}"

# ---------------------------------------------------------------------------
# Stage 3.0: Watch Rollout
# Purpose: Let readiness probes decide when new pods receive traffic.
# Expected output: rollout status reports successful completion.
# ---------------------------------------------------------------------------
section "Stage 3.0: Watch Rollout"

# CONFIGURATION EXPLANATION The 180s timeout makes the rollout a clear pass/fail gate. If readiness never
# succeeds, the script stops instead of hiding a failed release behind an endless wait.
run_cmd kubectl rollout status deployment/patient-record-api -n "${NAMESPACE}" --timeout=180s
run_cmd kubectl get pods -n "${NAMESPACE}" -l app=patient-record-api -o wide

# ---------------------------------------------------------------------------
# Stage 4.0: Inspect Revision History
# Purpose: Show the rollback points Kubernetes now knows about.
# Expected output: rollout history lists at least two revisions.
# ---------------------------------------------------------------------------
section "Stage 4.0: Inspect Revision History"

run_cmd kubectl rollout history deployment/patient-record-api -n "${NAMESPACE}"

cat <<'TEXT'
Next checks:
  bash app_k8_deployment/deployment-lifecycle/verify-patient-record-system.sh

Rollback if needed:
  bash app_k8_deployment/deployment-lifecycle/rollback-patient-record-api.sh
TEXT
