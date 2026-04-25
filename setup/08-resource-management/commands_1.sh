#!/usr/bin/env bash
# =============================================================================
# FILE:    commands.sh
# PURPOSE: Apply ResourceQuota and LimitRange policies, deploy a compliant
#          workload, inspect quota usage, and demonstrate policy rejection.
# USAGE:   bash setup/08-resource-management/commands.sh
# WHEN:    Run after setup/07-rbac, once the learner understands that access
#          control and resource control solve different platform problems.
# PREREQS: Namespace `applications` exists and kubectl points at the kind
#          learning cluster.
# OUTPUT:  Resource policies exist, the demo Deployment rolls out, quota usage
#          is visible, and an oversized pod is rejected by policy.
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# SCRIPT FLOW
#
# Stage 1: Preflight Checks
#   - Verify the applications namespace exists.
#
# Stage 2: Apply Resource Policies
#   - Apply ResourceQuota and LimitRange guardrails.
#
# Stage 3: Deploy Compliant Workload
#   - Create a small Deployment that fits within the policies.
#
# Stage 4: Inspect Quota Usage
#   - Show Used vs Hard budget after the Deployment exists.
#
# Stage 5: Prove LimitRange Rejection
#   - Server-side dry-run an oversized pod and confirm Kubernetes rejects it.
#
# Stage 6: Debugging Runbook
#   - Leave the learner with practical checks for quota and limit failures.
# ---------------------------------------------------------------------------

NAMESPACE="applications"
DEPLOYMENT_NAME="resource-managed-gateway"
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
# Stage 2.0: Apply Resource Policies
# Purpose: Create namespace and workload resource guardrails.
# Expected output: ResourceQuota and LimitRange are created or configured.
# ---------------------------------------------------------------------------
section "Stage 2.0: Apply Resource Policies"

run_cmd kubectl apply -f "${SCRIPT_DIR}/resource-quota.yaml"
run_cmd kubectl apply -f "${SCRIPT_DIR}/limit-range.yaml"

# ---------------------------------------------------------------------------
# Stage 3.0: Deploy Compliant Workload
# Purpose: Show a workload that fits inside both policy layers.
# Expected output: Deployment rolls out with two ready replicas.
# ---------------------------------------------------------------------------
section "Stage 3.0: Deploy Compliant Workload"

run_cmd kubectl apply -f "${SCRIPT_DIR}/deployment-with-limits.yaml"
run_cmd kubectl rollout status "deployment/${DEPLOYMENT_NAME}" -n "${NAMESPACE}" --timeout=90s
run_cmd kubectl get deployment "${DEPLOYMENT_NAME}" -n "${NAMESPACE}"
run_cmd kubectl get pods -n "${NAMESPACE}" -l "app=${DEPLOYMENT_NAME}" -o wide

# ---------------------------------------------------------------------------
# Stage 4.0: Inspect Quota Usage
# Purpose: Show how requests, limits, and object counts consume namespace budget.
# Expected output: Used values are visible next to Hard limits.
# ---------------------------------------------------------------------------
section "Stage 4.0: Inspect Quota Usage"

run_cmd kubectl describe quota applications-quota -n "${NAMESPACE}"
run_cmd kubectl describe limitrange applications-limit-range -n "${NAMESPACE}"

POD_NAME="$(kubectl get pods -n "${NAMESPACE}" -l "app=${DEPLOYMENT_NAME}" -o jsonpath='{.items[0].metadata.name}')"
echo "Inspecting one pod's requests and limits: ${POD_NAME}"
run_cmd kubectl describe pod "${POD_NAME}" -n "${NAMESPACE}"

# ---------------------------------------------------------------------------
# Stage 5.0: Prove LimitRange Rejection
# Purpose: Demonstrate that policy blocks an oversized container before it runs.
# Expected output: The server-side dry-run returns a Forbidden error.
# ---------------------------------------------------------------------------
section "Stage 5.0: Prove LimitRange Rejection"

echo "This dry-run pod asks for 2 CPU in one container, above the 1 CPU container max."
echo "The failure is expected and proves the LimitRange is enforcing policy."

if kubectl apply -n "${NAMESPACE}" --dry-run=server -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: oversized-resource-test
spec:
  containers:
    - name: test
      image: busybox:1.36
      command: ["sh", "-c", "sleep 3600"]
      resources:
        requests:
          cpu: "2"
          memory: "128Mi"
        limits:
          cpu: "2"
          memory: "256Mi"
EOF
then
  echo "ERROR: oversized dry-run pod was accepted, but it should have been rejected."
  echo "Check applications-limit-range max.cpu."
  exit 1
else
  echo "Expected rejection observed. LimitRange is doing its job."
fi

# ---------------------------------------------------------------------------
# Stage 6.0: Resource Debugging Runbook
# Purpose: Teach the order of checks for quota, limit, and scheduling failures.
# Expected output: Actionable next steps.
# ---------------------------------------------------------------------------
section "Stage 6.0: Resource Debugging Runbook"

echo "1. If a workload is rejected by quota:"
echo "   kubectl describe quota applications-quota -n ${NAMESPACE}"
echo ""
echo "2. If a workload is rejected by LimitRange:"
echo "   kubectl describe limitrange applications-limit-range -n ${NAMESPACE}"
echo ""
echo "3. If a pod is Pending:"
echo "   kubectl describe pod <pod-name> -n ${NAMESPACE}"
echo ""
echo "4. If a pod is OOMKilled:"
echo "   kubectl describe pod <pod-name> -n ${NAMESPACE}"
echo ""
echo "5. If you need to clean up this demo workload:"
echo "   kubectl delete -f ${SCRIPT_DIR}/deployment-with-limits.yaml"
echo ""
echo "Next step:"
echo "  setup/09-health-checks/README.md"
