#!/usr/bin/env bash
# =============================================================================
# FILE:    observe-patient-record-system.sh
# PURPOSE: Inspect logs, Events, metrics, HPA state, and rollout state.
# USAGE:   bash app_k8_deployment/deployment-lifecycle/observe-patient-record-system.sh
# WHEN:    Run when debugging rollout, readiness, scaling, or request failures.
# PREREQS: patient-record-system namespace exists; metrics-server is optional.
# OUTPUT:  A production-style first look at application health signals.
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# SCRIPT FLOW
#
# Stage 1: Workload Snapshot
#   - Show pods, Services, endpoints, Ingress, HPA, PDB, and CronJob.
#
# Stage 2: Logs
#   - Read recent backend, frontend, schema, and database logs.
#
# Stage 3: Metrics
#   - Try kubectl top and explain metrics-server if unavailable.
#
# Stage 4: Events
#   - Show namespace Events ordered by time.
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
# Stage 1.0: Workload Snapshot
# Purpose: See the control-plane state before reading logs.
# Expected input: The application has been deployed.
# Expected output: Kubernetes objects show current desired and actual state.
# ---------------------------------------------------------------------------
section "Stage 1.0: Workload Snapshot"

run_cmd kubectl get pods -n "${NAMESPACE}" -o wide
run_cmd kubectl get svc,endpoints,ingress,pdb,hpa,cronjob -n "${NAMESPACE}"

# ---------------------------------------------------------------------------
# Stage 2.0: Logs
# Purpose: Read the first evidence most enterprise responders check.
# Expected output: Recent logs from each tier.
# ---------------------------------------------------------------------------
section "Stage 2.0: Logs"

run_cmd kubectl logs -n "${NAMESPACE}" deployment/patient-record-api --tail=80
run_cmd kubectl logs -n "${NAMESPACE}" deployment/patient-intake-ui --tail=80
run_cmd kubectl logs -n "${NAMESPACE}" statefulset/patient-record-database --tail=80
echo "$ kubectl logs -n ${NAMESPACE} job/patient-record-schema-initializer --tail=80"
kubectl logs -n "${NAMESPACE}" job/patient-record-schema-initializer --tail=80 \
  || echo "Schema Job logs are unavailable. The Job may have been deleted after successful completion."
echo ""

# ---------------------------------------------------------------------------
# Stage 3.0: Metrics
# Purpose: Show live CPU/memory usage when metrics-server is installed.
# Expected output: `kubectl top` output or a clear explanation.
# ---------------------------------------------------------------------------
section "Stage 3.0: Metrics"

echo "ENTERPRISE EMPHASIS: HPA depends on metrics. If this prints an error, install or fix metrics-server before expecting CPU-based scaling."
if kubectl top pods -n "${NAMESPACE}"; then
  echo ""
else
  echo "Metrics are unavailable. HPA TARGETS may show <unknown> until metrics-server is healthy."
fi

# ---------------------------------------------------------------------------
# Stage 4.0: Events
# Purpose: Events reveal scheduler, image, probe, and quota decisions.
# Expected output: Recent namespace Events sorted by timestamp.
# ---------------------------------------------------------------------------
section "Stage 4.0: Events"

run_cmd kubectl get events -n "${NAMESPACE}" --sort-by=.lastTimestamp
