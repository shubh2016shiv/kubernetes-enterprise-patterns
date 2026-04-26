#!/usr/bin/env bash
# =============================================================================
# FILE:    commands.sh
# PURPOSE: Apply the health check demo, observe readiness through Service
#          endpoints, inspect probe Events, and inspect application logs.
# USAGE:   bash setup/09-health-checks/commands.sh
# WHEN:    Run after setup/08-resource-management so the learner already
#          understands resource requests and limits on the probed workload.
# PREREQS: Namespace `applications` exists and kubectl points at the kind
#          learning cluster.
# OUTPUT:  probes-demo Deployment and Service exist; pods become Ready; endpoint,
#          Event, and log inspection commands show how to debug pod health.
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# SCRIPT FLOW
#
# Stage 1: Preflight Checks
#   - Verify the applications namespace exists.
#
# Stage 2: Apply Health Check Demo
#   - Create the Deployment with probes and the Service used for endpoint checks.
#
# Stage 3: Watch Readiness and Endpoints
#   - Wait for pods to become Ready and inspect Service endpoints.
#
# Stage 4: Inspect Probe State
#   - Read pod Conditions and Events from kubectl describe.
#
# Stage 5: Inspect Logs for Human Visibility
#   - Use kubectl logs to show what the application emitted.
#
# Stage 6: Debugging Runbook
#   - Explain how probes, Events, and logs fit together.
# ---------------------------------------------------------------------------

# CONFIGURATION EXPLANATION `applications` keeps the probe demo workload separate from system pods. That matters
# because health-check failures in this lesson should only affect the demo Deployment,
# not platform components such as CoreDNS.
NAMESPACE="applications"
# CONFIGURATION EXPLANATION `probes-demo` is the Deployment this module inspects. Scripts use the name to find
# the matching pods, so it must stay aligned with the manifest metadata.name and the
# app label used by selectors.
DEPLOYMENT_NAME="probes-demo"
# CONFIGURATION EXPLANATION `probes-demo-service` is the Service inspected by this module. A Service is the
# stable network address in front of changing pods, so naming it explicitly makes
# debugging endpoint readiness repeatable.
SERVICE_NAME="probes-demo-service"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

section() {
  echo ""
  echo "=== $1 ==="
}

run_cmd() {
  echo "\$ $*"
  "$@"
  echo ""
}

# ---------------------------------------------------------------------------
# Stage 1.0: Preflight Checks
# Purpose: Fail early if namespace prerequisites are missing.
# Expected input: setup/02-namespaces has created applications.
# Expected output: namespace lookup succeeds.
# ---------------------------------------------------------------------------
section "Stage 1.0: Preflight Checks"

run_cmd kubectl version --client=true

if kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
  echo "${NAMESPACE} namespace exists"
else
  echo "ERROR: namespace '${NAMESPACE}' does not exist."
  echo "Run: bash setup/02-namespaces/apply-namespaces.sh"
  exit 1
fi

# ---------------------------------------------------------------------------
# Stage 2.0: Apply Health Check Demo
# Purpose: Create probed pods plus a Service that exposes readiness state.
# Expected output: Deployment and Service are created or configured.
# ---------------------------------------------------------------------------
section "Stage 2.0: Apply Health Check Demo"

run_cmd kubectl apply -f "${SCRIPT_DIR}/health-checks-demo.yaml"
# CONFIGURATION EXPLANATION The 90s timeout is a guardrail for automation: if Kubernetes cannot finish the
# rollout or readiness wait by then, the learner gets a clear failure instead of an
# endless terminal. Production CI/CD pipelines use the same pattern to protect runner
# capacity and surface broken releases quickly.
run_cmd kubectl rollout status "deployment/${DEPLOYMENT_NAME}" -n "${NAMESPACE}" --timeout=90s

# ---------------------------------------------------------------------------
# Stage 3.0: Watch Readiness and Endpoints
# Purpose: Show that readiness controls Service endpoint membership.
# Expected output: pods are Ready and Service endpoints contain pod IPs.
# ---------------------------------------------------------------------------
section "Stage 3.0: Watch Readiness and Endpoints"

run_cmd kubectl get pods -n "${NAMESPACE}" -l "app=${DEPLOYMENT_NAME}" -o wide
# CONFIGURATION EXPLANATION The 90s timeout is a guardrail for automation: if Kubernetes cannot finish the
# rollout or readiness wait by then, the learner gets a clear failure instead of an
# endless terminal. Production CI/CD pipelines use the same pattern to protect runner
# capacity and surface broken releases quickly.
run_cmd kubectl wait --for=condition=Ready pod -n "${NAMESPACE}" -l "app=${DEPLOYMENT_NAME}" --timeout=90s
run_cmd kubectl get endpoints "${SERVICE_NAME}" -n "${NAMESPACE}"

# ---------------------------------------------------------------------------
# Stage 4.0: Inspect Probe State
# Purpose: Teach where Kubernetes records probe outcomes.
# Expected output: Conditions and Events are visible in describe output.
# ---------------------------------------------------------------------------
section "Stage 4.0: Inspect Probe State"

# CONFIGURATION EXPLANATION `$(kubectl get pod -n "${NAMESPACE}" -l "app=${DEPLOYMENT_NAME}" -o
# jsonpath='{.items[0].metadata.name}')` is the demo pod name used by follow-up
# kubectl commands. The script keeps it in one place so log, exec, and cleanup steps
# all refer to the same workload.
POD_NAME="$(kubectl get pod -n "${NAMESPACE}" -l "app=${DEPLOYMENT_NAME}" -o jsonpath='{.items[0].metadata.name}')"
echo "Inspecting pod: ${POD_NAME}"
run_cmd kubectl describe pod "${POD_NAME}" -n "${NAMESPACE}"

echo "Recent namespace Events:"
run_cmd kubectl get events -n "${NAMESPACE}" --sort-by=.lastTimestamp

# ---------------------------------------------------------------------------
# Stage 5.0: Inspect Logs for Human Visibility
# Purpose: Connect the user's black-box pod question to concrete debugging commands.
# Expected output: Logs are visible without printing secrets.
# ---------------------------------------------------------------------------
section "Stage 5.0: Inspect Logs for Human Visibility"

echo "Kubernetes probes answer whether the pod should run or receive traffic."
echo "Logs answer what the application did inside the container."
run_cmd kubectl logs "${POD_NAME}" -n "${NAMESPACE}" --tail=40

echo "If a container restarts, this command is often the first human-debugging move:"
echo "kubectl logs ${POD_NAME} -n ${NAMESPACE} --previous"
echo ""

# ---------------------------------------------------------------------------
# Stage 6.0: Health Debugging Runbook
# Purpose: Leave a practical order of checks for unhealthy pods.
# Expected output: Actionable next steps.
# ---------------------------------------------------------------------------
section "Stage 6.0: Health Debugging Runbook"

echo "1. Check pod status and readiness:"
echo "   kubectl get pods -n ${NAMESPACE} -l app=${DEPLOYMENT_NAME}"
echo ""
echo "2. Check Service endpoints:"
echo "   kubectl get endpoints ${SERVICE_NAME} -n ${NAMESPACE}"
echo ""
echo "3. Read Kubernetes Events:"
echo "   kubectl describe pod <pod-name> -n ${NAMESPACE}"
echo ""
echo "4. Read current application logs:"
echo "   kubectl logs <pod-name> -n ${NAMESPACE}"
echo ""
echo "5. Read previous crashed-container logs:"
echo "   kubectl logs <pod-name> -n ${NAMESPACE} --previous"
echo ""
echo "6. Remember the boundary:"
echo "   probes are control-plane signals; logs, metrics, and traces are human visibility."
echo ""
echo "Next recommended learning module:"
echo "  setup/10-observability-debugging/ before enterprise reliability patterns"
