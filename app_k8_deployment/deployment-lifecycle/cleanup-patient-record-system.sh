#!/usr/bin/env bash
# =============================================================================
# FILE:    cleanup-patient-record-system.sh
# PURPOSE: Remove the patient record application namespace and all resources.
# USAGE:   bash app_k8_deployment/deployment-lifecycle/cleanup-patient-record-system.sh
# WHEN:    Run when the learner wants to reset this application track.
# PREREQS: kubectl points at the local learning cluster.
# OUTPUT:  Namespace deletion starts; PVC data in that namespace is removed.
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# SCRIPT FLOW
#
# Stage 1: Explain Data Impact
#   - State that deleting the namespace deletes the local database PVC.
#
# Stage 2: Delete Namespace
#   - Ask Kubernetes to remove all namespaced resources.
#
# Stage 3: Show Remaining State
#   - Confirm deletion status.
# ---------------------------------------------------------------------------

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
# Stage 1.0: Explain Data Impact
# Purpose: Make destructive local database cleanup explicit.
# Expected input: Learner intentionally runs cleanup.
# Expected output: Data impact is visible before delete command.
# ---------------------------------------------------------------------------
section "Stage 1.0: Explain Data Impact"

cat <<TEXT
ENTERPRISE EMPHASIS: This deletes the namespace, including the local database PVC.
That is acceptable for a local learning reset.
In production, database cleanup requires backups, retention checks, approvals,
and often a completely different process from application Deployment cleanup.
TEXT

# ---------------------------------------------------------------------------
# Stage 2.0: Delete Namespace
# Purpose: Remove the application stack from the cluster.
# Expected output: namespace deletion starts.
# ---------------------------------------------------------------------------
section "Stage 2.0: Delete Namespace"

run_cmd kubectl delete namespace "${NAMESPACE}" --ignore-not-found=true

# ---------------------------------------------------------------------------
# Stage 3.0: Show Remaining State
# Purpose: Confirm whether the namespace is gone or terminating.
# Expected output: namespace is absent or shown as Terminating.
# ---------------------------------------------------------------------------
section "Stage 3.0: Show Remaining State"

run_cmd kubectl get namespace "${NAMESPACE}" --ignore-not-found=true

